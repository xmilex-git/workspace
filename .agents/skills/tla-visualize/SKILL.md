---
name: tla-visualize
description: "Turn the TLA+ models of one CUBRID issue (docs/tla, review models) into a long-scroll HTML page: the variant comparison, the model structure, and each counterexample drawn on it step by step."
disable-model-invocation: true
argument-hint: "<CBRD key | PR number | spec dir | slug>"
---

# TLA+ models of an issue, as a page

One issue in, one `index.html` out: every TLA+ model made while working the issue (a `cubrid-tla`,
`grill-with-tla` or `cubrid-pr-review` spec directory), which variants were adopted or rejected and why, and
— the point of the page — each counterexample replayed on the model's own structure diagram.

The agent writes data only: `.git_ignored_dir/tla-visualize/<issue>/page.json`
([`reference/page-schema.md`](reference/page-schema.md)). `reference/build.mjs` assembles it with
`reference/template.html`, pele and the fonts; the template's layout, CSS and color taxonomy stay as they are.

## Terms

- **Model variant** (GLOSSARY `모델 변형`): one cfg's choice of constants inside a spec — `current` (the code
  before the change), `fix` (a candidate fix), `alt` (a rejected design), `adopted` (the main cfg). Mutants and
  witnesses are verification tools, never variants.
- **Counterexample stage**: the structure diagram with the trace's path lit up to step k, the sequence of
  actors, and the value table, moved together by one step control.

## 0. Gates

1. Playwright MCP: `ToolSearch` resolves `mcp__playwright__playwright_navigate`. Without it, stop: `Playwright MCP가 없어 이 스킬을 실행할 수 없습니다. 설치 후 다시 불러주세요.`
2. frontend-design: `/frontend-design:frontend-design` is in the skill list (or `~/.claude/plugins/cache/*/frontend-design` exists). Without it, stop with the same sentence naming the plugin. With it, call the Skill tool for `frontend-design:frontend-design` now, passing the issue's subject: it advises the copy, the headline and what to emphasize; the template's layout and taxonomy are fixed.
3. Toolchain: `.git_ignored_dir/tla-visualize/tools/bin/node` exists, else run `just tla-visualize-install`.

## 1. Find the issue's spec directories

- A CBRD key: every `docs/tla/*` whose name contains the key (`CBRD-27967`, `CBRD-27967-nl-inner-fixed`,
  `CBRD-27970-27971`), every `docs/tla/*/MAP.md` and `.claude/review/PR-*/tla/*/MAP.md` whose first 20 lines
  name the key, and the review models of the PRs those MAP.md files name.
- A PR number: `.claude/review/PR-<N>/tla/*`, plus the CBRD key from `gh pr view <N> --repo CUBRID/cubrid
  --json title` resolved as above.
- A path or a slug: that directory (`docs/tla/<slug>`).
- No argument: list issues with spec directories, newest MAP.md first, and ask with AskUserQuestion.

Done when every directory found is listed with its RESULT line; ask the user only when two readings of the
argument give different sets.

## 2. Read

For each directory: MAP.md whole; every cfg's first line (`\* expect:`) and constants; the run dir named in
`## Result` and its TLC logs. Then GLOSSARY.md: the issue's `###` section and every term the page will use, and
`.agents/skills/cubrid-jira-issue-write/tone_guide.md`. Measured runtime facts (SQL, results, fetch counts)
come from MAP.md, the JIRA draft under `.git_ignored_dir/jira/<key>/` and the issue's memory; nothing else
is quoted as measured.

## 3. Classify the cfgs

Every cfg of every directory lands in exactly one place:

| cfg | Lands in |
|---|---|
| main `<Module>.cfg` | `compare` row, `adopted` |
| `code-*`, `mutant-code`, `mutant-develop`, the review's pre-change mutant | `compare` row, `current` |
| `fix-*`, option cfgs, a Decisions row's rejected alternative with its own cfg | `compare` row, `fix` (still open) or `alt` (rejected) |
| other `mutant-*` | `verification.mutants` |
| `witness-*`, trace cfgs | `verification.witnesses` or `verification.lines` |
| `scale-*`, `apalache-*`, `inductive-*`, other pass cfgs | `bounds` |

A rejected alternative with no cfg of its own (a Decisions row) is an `alt` row whose evidence names the
decision and says no cfg checked it. Done when the count of cfgs equals the rows and lines they became.

## 4. Draw each model's structure

Run `tools/tla/model-graph <dir>/<Module>.tla`: a PlusCal spec gives each process's labels and pc edges with
the IF conditions on them; a plain spec gives each action's guards, writes, constants and the comment above
it, and `enables` (one action writes what another's guard reads). Draw one Mermaid flowchart per model:

- node id = the action or label name; node text = what it does in GLOSSARY terms, then the identifier
  (`리더가 페이지 비트맵을 모음<br/>Collect`);
- edges = the order the code runs, from pc edges or the `enables` pairs that are real control flow; an edge
  only one variant takes is dashed and labeled with the variant (`-.->|현재 코드|`);
- other transactions, vacuum and other threads in a `subgraph`;
- one edge per line, so `build.mjs` can find each edge's index.

## 5. Replay each counterexample

Draw every counterexample of a `current` variant and every hole (`H<n>`) MAP.md records; any other
counterexample left out is named in `cxLead` with the reason.

1. `tools/tla/trace-steps <log>` prints the violated property and each state's action, actors (`pc` changes)
   and `keys` (the function keys a plain action touched: `s1`, `w2`), with every changed value.
2. One `steps[]` entry per state after the initial one: `actor` from `actors`/`keys`, `node` = the action's
   node, `text` = what happened in one 합니다체 sentence, `code` = the refinement map's `file:function`,
   `state` = the values of the chosen `stateCols` (3 to 5 changed paths that explain the violation), `bad` on
   the last step.
3. `fix`: the adopted variant's guard as a node of the same diagram and the step number it stops the trace at.
4. A trace whose log is gone comes from MAP.md's numbered steps with `log: null`; TLC is not rerun for it.

## 6. Write page.json, build, verify, send

Write page.json by [`reference/page-schema.md`](reference/page-schema.md), then:

```bash
.git_ignored_dir/tla-visualize/tools/bin/node .agents/skills/tla-visualize/reference/build.mjs .git_ignored_dir/tla-visualize/<issue>/page.json
```

It prints `BUILT <path> <bytes>, <n> diagrams, <m> step diagrams`, or `ERROR: <field>: <reason>` to fix in
page.json. Then run [`reference/verify.md`](reference/verify.md) and send `index.html` with SendUserFile.

Done when the build prints BUILT, every check of verify.md passes at both sizes, and the report to the user
names the page, the spec directories with their RESULT, the counterexamples drawn and any left out.

## Wording

- Body text follows `cubrid-jira-issue-write/tone_guide.md`: 합니다체, short sentences, the normal behavior before
  the defect, every term glossed at first use, every number with its unit or source. Identifiers (actions,
  cfgs, `file:function`) stay as written in English.
- Every concept GLOSSARY.md names is written with GLOSSARY's term, never one of its `_Avoid_` words. A concept
  GLOSSARY lacks keeps its identifier, glossed once.
- `effect` holds only what a build measured, with the build; a model-only consequence is written in code terms
  with `reproduced: false`. An SQL example nobody ran is never written.
- "검증" states its bounds as the inputs it was limited to ("worker 2개, 페이지 2개로 제한한 모든 실행
  순서"); "증명" is used only for TLAPS obligations proved, and `bounds.proof` says `TLAPS 요청 없음` otherwise.
- A model whose RESULT is not OK is drawn too, with its badge; "검증된 모델" is used only for `RESULT: OK`.

## Changing the template or the toolchain

The case behind each `(P<n>)` is in `PITFALLS.md`.

- A diagram container is `tv-pele`, never `pele`: pele's own SVG carries the class `pele`, and a rule on `.pele` lands on the SVG too. (P1)
- A grid column in the template is `minmax(0,1fr)`: a bare `1fr` grows to its widest diagram and widens the whole page on a phone. (P2)
- A section padding in the template sets top and bottom only: a `padding` shorthand on a `.tv-wrap` element erases its side gutters. (P3)
- A font comes into `tools/tla-visualize/tools.nix` as one pinned file: the google-fonts package fetches the whole google/fonts repository (gigabytes). (P4)
- Verification scrolls with `window.scrollTo({top, behavior: 'instant'})` before a viewport screenshot: the page scrolls smoothly, and the screenshot tool's `selector` does not scroll. (P5)
