"""guard.py (anchor = a line that starts a top-level construct, never inside a comment) <file> <block-anchor-regex> <define-block-file> <decl-regex>...
Wraps every single-line declaration matching a decl regex (anchored at line start) in
#if !defined (SERVER_MODE) / #endif and inserts the define block (a file) before the line
matching block-anchor-regex. Fails if a regex matches no line or more than one."""
import re, sys
path, anchor, block = sys.argv[1], sys.argv[2], open(sys.argv[3]).read()
lines = open(path).read().split('\n')
for rx in sys.argv[4:]:
    hits = [i for i, l in enumerate(lines) if re.match(rx, l)]
    if len(hits) != 1:
        sys.exit(f"{path}: {rx!r} matched {len(hits)} lines")
    i = hits[0]
    lines[i] = '#if !defined (SERVER_MODE)\n' + lines[i] + '\n#endif'
hits = [i for i, l in enumerate(lines) if re.match(anchor, l)]
if len(hits) != 1:
    sys.exit(f"{path}: anchor {anchor!r} matched {len(hits)} lines")
lines[hits[0]] = block.rstrip('\n') + '\n\n' + lines[hits[0]]
open(path, 'w').write('\n'.join(lines))
