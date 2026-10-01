"""code-index — build-free symbol lookup in a CUBRID task worktree.

usage: code-index WORKSPACE COMMAND ...

  definition NAME           where NAME is defined: function, macro, type, struct member,
                            enumerator, grammar rule, Java class (a C++ member may be
                            written Class::name)
  body NAME | PATH:NAME | PATH:LINE [--all]
                            the definition's source with line numbers; past 500 lines only the
                            first 60 unless --all; several definitions are listed to pick from
  outline PATH              the functions, types and macros of one file with line ranges
  callers NAME [--all]      each use of NAME inside a function, with that function's name
  references NAME [--all]   every use of NAME; '-' when it is outside any function

Hits are "path:line[-end] ..." relative to WORKSPACE. Each carries {server,sa,cs}, the libraries
whose CMakeLists compile the file ({other} when none; headers carry none), and [...], the #if
conditions around the line (include guards and __cplusplus left out). callers and references
print the first 200 hits unless --all.

The index lives in WORKSPACE/.cache/code-index/ and re-indexes the files that changed before
every query, so line numbers match the files on disk; remove that directory to rebuild it.
Comments, strings, regex searches and names reported as not found are rg's job.
"""

# Decisions (grilling 2026-10-02; evidence in docs/research/code-index-evaluation.md):
#   D3  The index belongs to the task worktree, in WORKSPACE/.cache/code-index/. The engine
#       .gitignore ignores /.cache/; a worktree that does not gets a line in the common info/exclude.
#   D4  Every query first re-indexes only the files whose mtime or size changed. flock serialises
#       the sessions that share a worktree.
#   D7  Scope: tracked and not-yet-added files under src/ (minus src/win_tools/) and pl_engine/.
#   D10 Definitions come from Universal Ctags (C++ parser for .c/.h/.i, Java), a column-0 scan, a
#       grammar-rule scan and GNU Global; uses come from GNU Global -r plus -s. Both tools index
#       only the first branch of a function header split by #if/#else before a shared body
#       (pgbuf_fix_debug is found, pgbuf_fix_release is not), and ctags skips the C functions of
#       .y/.l files: the column-0 scan of GNU-style "name (" header lines finds both. Global's yacc
#       parser yields no rules for csql_grammar.y or load_grammar.yy (acceptance B8), hence the
#       rule scan.
#   D11 Hits carry the file's libraries and the #if conditions; no per-build evaluation.

import argparse
import bisect
import collections
import fcntl
import hashlib
import json
import os
import posixpath
import re
import signal
import sqlite3
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
TOOLS = os.path.join(REPO, ".git_ignored_dir", "code-index", "tools", "bin")
CTAGS = os.path.join(TOOLS, "ctags")
GTAGS = os.path.join(TOOLS, "gtags")
GLOBAL = os.path.join(TOOLS, "global")
CTAGS_OPTIONS = os.path.join(HERE, "ctags.options")
GTAGS_CONF = os.path.join(HERE, "gtags.conf")
GTAGS_LABEL = "code-index"

SCHEMA = "1"
SCOPE_DIRS = ("src", "pl_engine")
SCOPE_EXCLUDE = ("src/win_tools/",)
CTAGS_EXT = (".c", ".cpp", ".h", ".hpp", ".i", ".java")
GTAGS_EXT = (".c", ".cpp", ".h", ".hpp", ".i", ".y", ".yy", ".java")
GRAMMAR_EXT = (".y", ".yy", ".l")
INDEX_EXT = CTAGS_EXT + GRAMMAR_EXT
COLUMN0_EXT = (".c", ".cpp", ".h", ".hpp", ".i") + GRAMMAR_EXT
COMPILED_EXT = (".c", ".cpp") + GRAMMAR_EXT
OUTLINE_KINDS = ("function", "method", "class", "struct", "union", "enum", "typedef", "macro",
                 "namespace", "interface", "rule")
ENCLOSING_KINDS = ("function", "method", "rule")  # a grammar action's code is "in" its rule
BODY_LIMIT, BODY_HEAD, HIT_LIMIT = 500, 60, 200
BULK_UPDATE = 10  # above this many changed files one gtags -i run replaces per-file updates
LIBRARIES = (("cubrid", "server"), ("sa", "sa"), ("cs", "cs"))

NAME = re.compile(r"^~?[A-Za-z_][A-Za-z0-9_]*(::~?[A-Za-z_][A-Za-z0-9_]*)*$")
TARGET = re.compile(r"^(?P<path>[^:]+\.[A-Za-z]+):(?P<what>[^:].*)$")
COLUMN0_HEADER = re.compile(r"([A-Za-z_][A-Za-z0-9_]*) ?\(")
RULE_HEAD = re.compile(r"^([A-Za-z_][A-Za-z0-9_.]*)\s*(?:(:)|$|/[*/])")
NOT_DEFINITIONS = frozenset(("if", "for", "while", "switch", "return", "sizeof", "defined", "_DEFUN"))
DIRECTIVE = re.compile(r"^\s*#\s*(if|ifdef|ifndef|elif|else|endif|define)\b(.*)$")
NOT_DEFINED = re.compile(r"^!\s*defined\s*\(?\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)?$")
CMAKE_SET = re.compile(r"^\s*set\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s+([^\s)]+)\s*\)", re.M | re.I)
CMAKE_TARGET = re.compile(r"^\s*(bison|flex)_target\s*\(\s*(\w+)\s+(\S+)", re.M | re.I)
CMAKE_DIR_FILE = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*_DIR)\}/([A-Za-z0-9_./+-]+)")
CMAKE_GENERATED = re.compile(r"\$\{((?:BISON|FLEX)_\w+?)_(?:OUTPUTS|OUTPUT_SOURCE)\}")

Def = collections.namedtuple("Def", "name path line end kind scope scope_kind signature source")
DEF_COLUMNS = "name, path, line, end_line, kind, scope, scope_kind, signature, source"


class Failure(Exception):
    """An error printed as 'code-index: <message>' that ends the run with its exit status."""

    def __init__(self, message, status=4):
        Exception.__init__(self, message)
        self.status = status


def note(message):
    sys.stderr.write("code-index: %s\n" % message)


def run(cmd, cwd=None, env=None, check=True):
    proc = subprocess.run(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and proc.returncode != 0:
        tail = proc.stderr.decode("utf-8", "replace").strip().splitlines()[-3:]
        raise Failure("%s exited %d: %s" % (os.path.basename(cmd[0]), proc.returncode, " | ".join(tail)))
    return proc


def read_text(path):
    try:
        with open(path, "rb") as fh:
            return fh.read().decode("utf-8", "replace")
    except OSError:
        return ""


def read_lines(ws, rel):
    text = read_text(os.path.join(ws, rel))
    if "\r" in text:
        text = text.replace("\r\n", "\n")
    return text.split("\n")


# ---------------------------------------------------------------------------
# Index location, scope and freshness (D3, D4, D7)
# ---------------------------------------------------------------------------

def resolve_workspace(arg):
    ws = os.path.realpath(arg)
    proc = run(["git", "-C", ws, "rev-parse", "--show-toplevel"], check=False)
    if proc.returncode != 0 or os.path.realpath(proc.stdout.decode().strip()) != ws:
        raise Failure("WORKSPACE must be the root of an engine worktree (got %s)" % arg, 2)
    if not (os.path.isfile(os.path.join(ws, "CMakeLists.txt")) and os.path.isdir(os.path.join(ws, "src"))):
        raise Failure("%s is not a CUBRID engine checkout (no CMakeLists.txt and src/)" % ws, 2)
    return ws


def ensure_ignored(ws):
    if run(["git", "-C", ws, "check-ignore", "-q", ".cache/code-index/index.sqlite"], check=False).returncode == 0:
        return
    common = run(["git", "-C", ws, "rev-parse", "--git-common-dir"]).stdout.decode().strip()
    exclude = os.path.join(ws, common, "info", "exclude")  # join keeps an absolute common dir
    os.makedirs(os.path.dirname(exclude), exist_ok=True)
    with open(exclude, "a") as fh:
        fh.write("/.cache/code-index/\n")
    note("this worktree did not ignore /.cache/; added /.cache/code-index/ to %s" % exclude)


def open_index(ws):
    path = os.path.join(ws, ".cache", "code-index")
    if not os.path.isdir(path):
        ensure_ignored(ws)
        os.makedirs(path, exist_ok=True)
    lock = open(os.path.join(path, "lock"), "a")
    fcntl.flock(lock, fcntl.LOCK_EX)  # held until the process exits
    db = sqlite3.connect(os.path.join(path, "index.sqlite"))
    db.execute("PRAGMA synchronous = OFF")  # the index can always be rebuilt
    db.execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)")
    return path, lock, db


def create_tables(db):
    db.executescript("""
        DROP TABLE IF EXISTS defs;
        DROP TABLE IF EXISTS files;
        CREATE TABLE files (path TEXT PRIMARY KEY, mtime_ns INTEGER, size INTEGER);
        CREATE TABLE defs (name TEXT, path TEXT, line INTEGER, end_line INTEGER, kind TEXT,
                           scope TEXT, scope_kind TEXT, signature TEXT, source TEXT);
        CREATE INDEX defs_by_name ON defs (name);
        CREATE INDEX defs_by_path ON defs (path, line);
    """)


def set_meta(db, **values):
    db.executemany("INSERT OR REPLACE INTO meta VALUES (?, ?)", sorted(values.items()))


def scope_files(ws):
    out = run(["git", "-C", ws, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--"]
              + list(SCOPE_DIRS)).stdout
    files = {}
    for rel in out.decode("utf-8", "replace").split("\0"):
        if not rel.endswith(INDEX_EXT) or rel.startswith(SCOPE_EXCLUDE):
            continue
        try:
            st = os.stat(os.path.join(ws, rel))
        except OSError:
            continue  # deleted in the worktree but still in git's index
        files[rel] = (st.st_mtime_ns, st.st_size)
    return files


def fingerprint():
    digest = hashlib.sha256(SCHEMA.encode())
    for path in (CTAGS_OPTIONS, GTAGS_CONF, os.path.realpath(__file__)):
        digest.update(read_text(path).encode("utf-8"))
    digest.update(os.path.realpath(TOOLS).encode("utf-8"))  # a reinstalled toolchain moves in the store
    return digest.hexdigest()


def global_env(ws, path):
    env = dict(os.environ)
    for key in ("GTAGSLIBPATH", "GTAGSOBJDIRPREFIX", "MAKEOBJDIRPREFIX", "GTAGSFORCECPP"):
        env.pop(key, None)
    env.update(GTAGSROOT=ws, GTAGSDBPATH=path, GTAGSCONF=GTAGS_CONF, GTAGSLABEL=GTAGS_LABEL,
               PATH=TOOLS + os.pathsep + env.get("PATH", ""))
    return env


def refresh(ws, path, db):
    started = time.time()
    files = scope_files(ws)
    meta = dict(db.execute("SELECT key, value FROM meta"))
    gtags_db = all(os.path.exists(os.path.join(path, name)) for name in ("GTAGS", "GRTAGS", "GPATH"))
    if meta.get("fingerprint") != fingerprint() or meta.get("complete") != "1" or not gtags_db:
        build(ws, path, db, files)
        note("indexed %d files in %.1f s" % (len(files), time.time() - started))
        return
    known = dict((row[0], (row[1], row[2])) for row in db.execute("SELECT path, mtime_ns, size FROM files"))
    changed = sorted(rel for rel, signature in files.items() if known.get(rel) != signature)
    removed = sorted(rel for rel in known if rel not in files)
    if changed or removed:
        update(ws, path, db, files, changed, removed)
        note("re-indexed %d changed file(s) in %.1f s" % (len(changed) + len(removed), time.time() - started))


def write_list(path, name, rels):
    listfile = os.path.join(path, name)
    with open(listfile, "w") as fh:
        fh.write("".join(rel + "\n" for rel in rels))
    return listfile


def build(ws, path, db, files):
    set_meta(db, complete="0")
    create_tables(db)
    db.commit()
    for name in ("GTAGS", "GRTAGS", "GPATH"):
        if os.path.exists(os.path.join(path, name)):
            os.remove(os.path.join(path, name))
    rels = sorted(files)
    with open(os.path.join(path, "build.log"), "w") as log:
        gtags_list = write_list(path, "gtags.list", [rel for rel in rels if rel.endswith(GTAGS_EXT)])
        gtags = subprocess.Popen([GTAGS, "-f", gtags_list, path], cwd=ws, env=global_env(ws, path),
                                 stdout=log, stderr=subprocess.STDOUT)
        ctags = start_ctags(ws, path, [rel for rel in rels if rel.endswith(CTAGS_EXT)], log)
        column0 = column0_rows(ws, [rel for rel in rels if rel.endswith(COLUMN0_EXT)])
        column0 += rule_rows(ws, [rel for rel in rels if rel.endswith((".y", ".yy"))])
        store_definitions(db, read_ctags(*ctags), column0)
        if gtags.wait() != 0:
            raise Failure("gtags failed; see %s" % log.name)
    db.executemany("INSERT INTO files VALUES (?, ?, ?)", [(rel,) + files[rel] for rel in rels])
    set_meta(db, fingerprint=fingerprint(), complete="1", schema=SCHEMA)
    db.commit()


def update(ws, path, db, files, changed, removed):
    set_meta(db, complete="0")
    db.commit()
    touched = changed + removed
    with open(os.path.join(path, "build.log"), "w") as log:
        ctags = start_ctags(ws, path, [rel for rel in changed if rel.endswith(CTAGS_EXT)], log)
        env = global_env(ws, path)
        gtags_touched = [rel for rel in touched if rel.endswith(GTAGS_EXT)]
        gtags = None
        if len(gtags_touched) > BULK_UPDATE:
            gtags_list = write_list(path, "gtags.list", sorted(rel for rel in files if rel.endswith(GTAGS_EXT)))
            gtags = subprocess.Popen([GTAGS, "-i", "-f", gtags_list, path], cwd=ws, env=env,
                                     stdout=log, stderr=subprocess.STDOUT)
        else:
            # --single-update re-reads the file whatever its mtime; gtags -i compares mtimes in whole seconds.
            for rel in gtags_touched:
                if subprocess.call([GLOBAL, "--single-update", rel], cwd=ws, env=env, stdout=log,
                                   stderr=subprocess.STDOUT) != 0:
                    raise Failure("global --single-update %s failed; see %s" % (rel, log.name))
        column0 = column0_rows(ws, [rel for rel in changed if rel.endswith(COLUMN0_EXT)])
        column0 += rule_rows(ws, [rel for rel in changed if rel.endswith((".y", ".yy"))])
        db.executemany("DELETE FROM defs WHERE path = ?", [(rel,) for rel in touched])
        store_definitions(db, read_ctags(*ctags), column0)
        if gtags is not None and gtags.wait() != 0:
            raise Failure("gtags -i failed; see %s" % log.name)
    db.executemany("DELETE FROM files WHERE path = ?", [(rel,) for rel in removed])
    db.executemany("INSERT OR REPLACE INTO files VALUES (?, ?, ?)", [(rel,) + files[rel] for rel in changed])
    set_meta(db, complete="1")
    db.commit()


def start_ctags(ws, path, rels, log):
    if not rels:
        return None, None
    listfile = write_list(path, "ctags.list", rels)
    out = os.path.join(path, "ctags.json")
    proc = subprocess.Popen([CTAGS, "--options=" + CTAGS_OPTIONS, "--output-format=json", "-f", out,
                             "-L", listfile], cwd=ws, stdout=log, stderr=subprocess.STDOUT)
    return proc, out


def read_ctags(proc, out):
    if proc is None:
        return []
    if proc.wait() != 0:
        raise Failure("ctags failed; see build.log")
    rows = []
    with open(out, "rb") as fh:
        for raw in fh:
            try:
                tag = json.loads(raw.decode("utf-8", "replace"))
            except ValueError:
                continue
            if tag.get("_type") != "tag" or "line" not in tag:
                continue
            end = tag.get("end")
            rows.append((tag["name"], tag["path"], int(tag["line"]), int(end) if end else None,
                         tag.get("kind", ""), tag.get("scope", ""), tag.get("scopeKind", ""),
                         tag.get("signature", ""), "ctags"))
    os.remove(out)
    return rows


def column0_rows(ws, rels):
    """GNU-style definitions: an identifier and " (" at column 0, then a column-0 "{" before any ";" line."""
    rows = []
    for rel in rels:
        lines = read_lines(ws, rel)
        for i, text in enumerate(lines):
            if not text or not (text[0].isalpha() or text[0] == "_"):
                continue
            match = COLUMN0_HEADER.match(text)
            if not match or match.group(1) in NOT_DEFINITIONS:
                continue
            brace = opening_brace(lines, i)
            if brace is not None:
                rows.append((match.group(1), rel, i + 1, closing_brace(lines, brace), "function", "", "", "",
                             "column0"))
    return rows


def opening_brace(lines, header):
    # A split header (#if/#else around two "name (" lines) shares the "{" after its #endif.
    for j in range(header, min(header + 40, len(lines))):
        text = lines[j]
        if text.startswith("{"):
            return j
        if not text.startswith("#") and text.rstrip().endswith(";"):
            return None
    return None


def closing_brace(lines, brace):
    for k in range(brace + 1, len(lines)):
        if lines[k].startswith("}"):
            return k + 1
    return None


def rule_rows(ws, rels):
    """Yacc rules: a column-0 name between the first two %% lines, its ':' on that line or the next
    non-blank one; the rule ends at its ';' line (or where the rules section ends)."""
    rows = []
    for rel in rels:
        lines = read_lines(ws, rel)
        marks = [i for i, text in enumerate(lines) if text.strip() == "%%"]
        if not marks:
            continue
        last = marks[1] if len(marks) > 1 else len(lines)
        i = marks[0] + 1
        while i < last:
            match = RULE_HEAD.match(lines[i])
            if not match:
                i += 1
                continue
            j = i
            if match.group(2) is None:
                j = i + 1
                while j < last and not lines[j].strip():
                    j += 1
                if j >= last or not lines[j].lstrip().startswith(":"):
                    i += 1
                    continue
            end = next((k + 1 for k in range(j, last) if lines[k].strip() == ";"), last)
            rows.append((match.group(1), rel, i + 1, end, "rule", "", "", "", "rule"))
            i = end
    return rows


def store_definitions(db, ctags, column0):
    seen = set((row[1], row[2], row[0]) for row in ctags)
    sql = "INSERT INTO defs (%s) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)" % DEF_COLUMNS
    db.executemany(sql, ctags)
    db.executemany(sql, [row for row in column0 if (row[1], row[2], row[0]) not in seen])


# ---------------------------------------------------------------------------
# Annotations: libraries and #if conditions (D11)
# ---------------------------------------------------------------------------

def build_membership(ws):
    """Map each source path to the libraries (server, sa, cs) whose CMakeLists lists it."""
    root = read_text(os.path.join(ws, "CMakeLists.txt"))
    values = collections.defaultdict(list)
    for name, value in CMAKE_SET.findall(root):
        values[name].append(value.strip('"'))

    def expand(text, depth=0):
        def substitute(match):
            if match.group(1) in ("CMAKE_SOURCE_DIR", "CMAKE_CURRENT_SOURCE_DIR"):
                return ""
            for value in values.get(match.group(1), ()):
                expanded = expand(value, depth + 1) if depth < 8 else value
                if "${" not in expanded:
                    return expanded
            return match.group(0)
        return re.sub(r"\$\{(\w+)\}", substitute, text)

    def relative(path):
        return posixpath.normpath(path).lstrip("/")

    generated = {}
    for tool, name, source in CMAKE_TARGET.findall(root):
        variable = re.match(r"^\$\{(\w+)\}$", source)
        # CSQL_GRAMMAR_INPUT is set twice (the second points into the build tree): keep a real file.
        candidates = values.get(variable.group(1), ()) if variable else (source,)
        for candidate in candidates:
            rel = relative(expand(candidate))
            if os.path.isfile(os.path.join(ws, rel)):
                generated["%s_%s" % (tool.upper(), name)] = rel
                break
    members = collections.defaultdict(set)
    for directory, library in LIBRARIES:
        text = read_text(os.path.join(ws, directory, "CMakeLists.txt"))
        for variable, tail in CMAKE_DIR_FILE.findall(text):
            members[relative(expand("${%s}" % variable) + "/" + tail)].add(library)
        for target in CMAKE_GENERATED.findall(text):
            if target in generated:
                members[generated[target]].add(library)
    return members


def clean_expression(text):
    text = re.sub(r"/\*.*?\*/", " ", text)
    text = text.split("//")[0].split("/*")[0]
    return " ".join(text.split())


def render_conditions(stack):
    parts = []
    for shown, state, hidden in stack:
        if hidden:
            continue
        part = shown if state == "if" else "#else of " + shown if state == "else" else state
        parts.append(part if len(part) <= 70 else part[:67] + "...")
    return " > ".join(parts)


def condition_segments(lines):
    """[(first line, rendered #if stack)] — the stack that holds from that line until the next entry."""
    starts, texts = [1], [""]
    stack = []
    guard = None  # (stack depth, macro) of an #ifndef X that is an include guard if #define X follows
    i = 0
    while i < len(lines):
        match = DIRECTIVE.match(lines[i])
        if not match:
            if lines[i].strip():
                guard = None
            i += 1
            continue
        text, j = lines[i], i
        while text.rstrip().endswith("\\") and j + 1 < len(lines):
            j += 1
            text = text.rstrip()[:-1] + " " + lines[j].strip()
        word, expression = DIRECTIVE.match(text).group(1), clean_expression(DIRECTIVE.match(text).group(2))
        if word in ("if", "ifdef", "ifndef"):
            shown = {"if": expression, "ifdef": "defined(%s)" % expression,
                     "ifndef": "!defined(%s)" % expression}[word]
            stack.append([("#if 0" if shown == "0" else shown), "if", "__cplusplus" in expression])
            macro = expression if word == "ifndef" else None
            if word == "if" and NOT_DEFINED.match(expression):
                macro = NOT_DEFINED.match(expression).group(1)
            guard = (len(stack), macro) if macro else None
        elif word == "define":
            if guard and guard[0] == len(stack) and expression.split("(")[0].split()[:1] == [guard[1]]:
                stack[-1][2] = True
            guard = None
        else:
            guard = None
            if stack and word == "elif":
                stack[-1][1] = "#elif " + expression
            elif stack and word == "else":
                stack[-1][1] = "else"
            elif stack and word == "endif":
                stack.pop()
        starts.append(j + 2)
        texts.append(render_conditions(stack))
        i = j + 1
    return starts, texts


class Annotator(object):
    def __init__(self, ws):
        self.ws = ws
        self.members = build_membership(ws)
        self.segments = {}

    def libraries(self, rel):
        if not rel.endswith(COMPILED_EXT):
            return ""
        found = self.members.get(rel)
        if not found:
            return " {other}"
        return " {%s}" % ",".join(library for _, library in LIBRARIES if library in found)

    def conditions(self, rel, line):
        if rel.endswith(".java"):
            return ""
        if rel not in self.segments:
            self.segments[rel] = condition_segments(read_lines(self.ws, rel))
        starts, texts = self.segments[rel]
        text = texts[bisect.bisect_right(starts, line) - 1]
        return " [%s]" % text if text else ""

    def __call__(self, rel, line):
        return self.libraries(rel) + self.conditions(rel, line)


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

def split_name(name):
    return tuple(name.rsplit("::", 1)) if "::" in name else ("", name)


def global_hits(ws, path, flag, name):
    proc = run([GLOBAL, flag, name], cwd=ws, env=global_env(ws, path), check=False)
    if proc.returncode != 0 and proc.stderr.strip():
        raise Failure("global %s %s: %s" % (flag, name, proc.stderr.decode("utf-8", "replace").strip()))
    hits = []
    for line in proc.stdout.decode("utf-8", "replace").splitlines():
        parts = line.split(None, 3)
        if len(parts) >= 3 and parts[1].isdigit():
            hits.append((parts[0], posixpath.normpath(parts[2]), int(parts[1]), parts[3] if len(parts) > 3 else ""))
    return hits


def definitions(ws, path, db, name):
    scope, base = split_name(name)
    rows = [Def(*row) for row in db.execute("SELECT %s FROM defs WHERE name = ?" % DEF_COLUMNS, (base,))]
    if scope:
        rows = [r for r in rows if r.scope == scope or r.scope.endswith("::" + scope)]
    else:
        seen = set((r.path, r.line) for r in rows)
        for _, rel, line, _ in global_hits(ws, path, "-x", base):
            if (rel, line) not in seen:
                seen.add((rel, line))
                rows.append(Def(base, rel, line, None, "definition", "", "", "", "global"))
    return sorted(rows, key=lambda r: (r.path, r.line))


def describe(r, annotate, signature=True):
    text = "%s:%d" % (r.path, r.line)
    if r.end and r.end > r.line:
        text += "-%d" % r.end
    text += " %s %s%s" % (r.kind, r.name, r.signature if signature and r.signature else "")
    if r.scope:
        text += " (%s %s)" % (r.scope_kind or "in", r.scope)
    return text + annotate(r.path, r.line)


def normalize(ws, arg):
    rel = os.path.relpath(os.path.realpath(arg), ws) if os.path.isabs(arg) else arg
    rel = posixpath.normpath(rel)
    if rel == ".." or rel.startswith("../"):
        raise Failure("%s is outside WORKSPACE" % arg, 2)
    return rel


def cmd_definition(ws, path, db, annotate, args):
    rows = definitions(ws, path, db, args.name)
    if not rows:
        raise Failure("no definition of %s in this worktree's index; search with rg" % args.name, 1)
    return [describe(r, annotate) for r in rows]


def declaration_start(lines, line):
    """The return type and template lines above a definition's name line, up to two."""
    start = line
    for _ in range(2):
        above = lines[start - 2].strip() if start >= 2 else ""
        if not above or above.startswith(("#", "/", "*")) or above.endswith((";", "{", "}", ":", "*/")):
            break
        start -= 1
    return start


def cmd_body(ws, path, db, annotate, args):
    match = TARGET.match(args.target)
    rel = normalize(ws, match.group("path")) if match else None
    if match and match.group("what").isdigit():
        line = int(match.group("what"))
        rows = [Def(*row) for row in db.execute(
            "SELECT %s FROM defs WHERE path = ? AND line <= ? AND end_line >= ? ORDER BY line DESC"
            % DEF_COLUMNS, (rel, line, line))]
        rows = [r for r in rows if not r.name.startswith("__anon")][:1]
    else:
        name = match.group("what") if match else args.target
        if not NAME.match(name):
            raise Failure("NAME must be an identifier (got %s)" % name, 2)
        rows = [r for r in definitions(ws, path, db, name) if rel is None or r.path == rel]
    if not rows:
        raise Failure("no definition of %s in this worktree's index; search with rg" % args.target, 1)
    if len(rows) > 1:
        out = [describe(r, annotate) for r in rows]
        out.append("%d definitions; pick one with: body <path>:<line>" % len(rows))
        return out, 2
    r = rows[0]
    lines = read_lines(ws, r.path)
    start, end = declaration_start(lines, r.line), min(r.end or r.line, len(lines))
    stop = end if args.all or end - start + 1 <= BODY_LIMIT else start + BODY_HEAD - 1
    out = ["== " + describe(r, annotate)]
    out.extend("%6d\t%s" % (n, lines[n - 1]) for n in range(start, stop + 1))
    if stop < end:
        out.append("... %d more lines (%d-%d): rerun with --all, or read that range of %s directly"
                   % (end - stop, stop + 1, end, r.path))
    return out


def cmd_outline(ws, path, db, annotate, args):
    rel = normalize(ws, args.path)
    if db.execute("SELECT 1 FROM files WHERE path = ?", (rel,)).fetchone() is None:
        if os.path.isfile(os.path.join(ws, rel)):
            raise Failure("%s is outside the code index (src/ without src/win_tools/, pl_engine/)" % rel, 1)
        raise Failure("no such file in %s: %s" % (ws, rel), 1)
    rows = [Def(*row) for row in db.execute(
        "SELECT %s FROM defs WHERE path = ? AND kind IN (%s) ORDER BY line"
        % (DEF_COLUMNS, ",".join("?" * len(OUTLINE_KINDS))), (rel,) + OUTLINE_KINDS)]
    if rel.endswith(GRAMMAR_EXT):  # grammar rules come from Global's yacc parser
        seen = set(r.line for r in rows)
        for name, _, line, _ in global_hits(ws, path, "-f", rel):
            if line not in seen:
                rows.append(Def(name, rel, line, None, "definition", "", "", "", "global"))
        rows.sort(key=lambda r: r.line)
    rows = [r for r in rows if not r.name.startswith("__anon")]
    out = ["%s%s: %d entries" % (rel, annotate.libraries(rel), len(rows))]
    for r in rows:
        span = "%d-%d" % (r.line, r.end) if r.end and r.end > r.line else "%d" % r.line
        scope = " (%s %s)" % (r.scope_kind or "in", r.scope) if r.scope else ""
        out.append("%s %s %s%s%s" % (span, r.kind, r.name, scope, annotate.conditions(rel, r.line)))
    return out


def enclosing_function(db, cache, rel, line):
    if rel not in cache:
        cache[rel] = [Def(*row) for row in db.execute(
            "SELECT %s FROM defs WHERE path = ? AND kind IN (%s) AND end_line IS NOT NULL ORDER BY line"
            % (DEF_COLUMNS, ",".join("?" * len(ENCLOSING_KINDS))), (rel,) + ENCLOSING_KINDS)
            if not row[0].startswith("__anon")]
    inside = [r for r in cache[rel] if r.line <= line <= r.end]
    if not inside:
        return None
    innermost = min(r.end for r in inside)  # a split header's variants share one end
    names = []
    for r in inside:
        if r.end == innermost:
            separator = "." if rel.endswith(".java") else "::"
            name = (r.scope + separator if r.scope and r.scope_kind in ("class", "struct", "namespace") else "") + r.name
            if name not in names:
                names.append(name)
    return "|".join(names)


def cmd_uses(ws, path, db, annotate, args, callers):
    if not NAME.match(args.name):
        raise Failure("NAME must be an identifier (got %s)" % args.name, 2)
    _, base = split_name(args.name)
    hits = {}
    for flag in ("-rx", "-sx"):  # -s holds the uses of names Global has no definition for
        for _, rel, line, text in global_hits(ws, path, flag, base):
            hits.setdefault((rel, line), text)
    own = set((row[0], row[1]) for row in db.execute("SELECT path, line FROM defs WHERE name = ?", (base,)))
    cache, found = {}, []
    for (rel, line), text in sorted(hits.items()):
        if (rel, line) in own:
            continue
        function = enclosing_function(db, cache, rel, line)
        if callers and function is None:
            continue
        found.append((rel, line, function, text))
    if not found:
        raise Failure("no %s of %s in this worktree's index; search with rg"
                      % ("callers" if callers else "references", args.name), 1)
    shown = found if args.all else found[:HIT_LIMIT]
    out = ["%s:%d %s%s  %s" % (rel, line, function or "-", annotate(rel, line), " ".join(text.split())[:160])
           for rel, line, function, text in shown]
    if callers:
        summary = "%d call sites in %d functions" % (len(found), len(set(f[2] for f in found)))
    else:
        summary = "%d references" % len(found)
    if len(shown) < len(found):
        summary += "; showing the first %d, rerun with --all" % len(shown)
    out.append(summary)
    return out


def parse_args(argv):
    parser = argparse.ArgumentParser(prog="code-index", usage="code-index WORKSPACE COMMAND ...",
                                     description=__doc__.split("\n\n", 2)[2],
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("workspace", help="root of the CUBRID task worktree")
    commands = parser.add_subparsers(dest="command", metavar="COMMAND")
    for command, operand, has_all, summary in (
            ("definition", "name", False, "where NAME is defined"),
            ("body", "target", True, "the source of NAME, PATH:NAME or PATH:LINE"),
            ("outline", "path", False, "the functions, types and macros of one file"),
            ("callers", "name", True, "each use of NAME inside a function"),
            ("references", "name", True, "every use of NAME")):
        sub = commands.add_parser(command, help=summary, description=summary)
        sub.add_argument(operand)
        if has_all:
            sub.add_argument("--all", action="store_true", help="print everything, past the default limit")
    args = parser.parse_args(argv)
    if not args.command:
        parser.error("COMMAND is required")
    return args


def main(argv):
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")
    args = parse_args(argv)
    try:
        for tool in (CTAGS, GTAGS, GLOBAL):
            if not os.access(tool, os.X_OK):
                raise Failure("%s is missing; run 'just code-index-install' in %s" % (tool, REPO), 3)
        if args.command in ("definition", "callers", "references") and not NAME.match(args.name):
            raise Failure("NAME must be an identifier (got %s)" % args.name, 2)
        ws = resolve_workspace(args.workspace)
        path, lock, db = open_index(ws)
        refresh(ws, path, db)
        annotate = Annotator(ws)
        if args.command == "definition":
            result = cmd_definition(ws, path, db, annotate, args)
        elif args.command == "body":
            result = cmd_body(ws, path, db, annotate, args)
        elif args.command == "outline":
            result = cmd_outline(ws, path, db, annotate, args)
        else:
            result = cmd_uses(ws, path, db, annotate, args, args.command == "callers")
    except Failure as failure:
        note(str(failure))
        return failure.status
    lines, status = result if isinstance(result, tuple) else (result, 0)
    sys.stdout.write("\n".join(lines) + "\n")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
