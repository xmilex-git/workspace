# page.json

The only file the agent writes per issue. `build.mjs` turns it into `index.html` beside it and refuses a
missing required field, a kind outside the four, a step whose `node`, `edge`, `actor` or `to` is not in its
diagram, and any Mermaid source pele cannot render (every counterexample step included), naming the field.

Text fields are plain text with three inline marks: `` `code` ``, `**bold**`, `[label](https://…)`.
A field shown as `text | [text]` takes one paragraph or a list of paragraphs.

## Top level

| Field | Required | Content |
|---|---|---|
| `issue` | yes | `CBRD-27967`, `PR-8432` or the slug; the nav brand and the page title |
| `eyebrow` | yes | the `{ … }` line above the headline: the issue key and its subject in GLOSSARY terms |
| `title` | yes | the headline, one claim of the issue in two short lines split by `\n` |
| `lead` | yes | two or three sentences: normal behavior, what went wrong, what the models checked |
| `links` | no | `[{label, href}]`; the first is the PR (gradient pill) |
| `specs` | yes | `[{dir, result, run}]`, one per spec directory; `result` is `OK`, `FAILED`, `PARTIAL` or `미완` read from MAP.md `## Result` |
| `problem` | no | `{heading, lead, body: text \| [text], repro: {build, sql, result}}`; `repro` only for a measured run |
| `compare`, `compareHeading`, `compareLead` | yes | the variant table (below) |
| `timeline`, `timelineSource` | no | `[{date, events: [text]}]` in date order; a `:` in an event is replaced |
| `models`, `modelsLead` | yes | one per spec directory (below) |
| `counterexamples`, `cxLead` | no | one per counterexample drawn (below) |
| `verification` | yes | `{lead, body, mutants: [{name, removes, caught}], witnesses: [{name, shows}], lines: [text]}`; `caught` empty = surviving mutant |
| `bounds` | yes | `{checked, outside, indinv, proof}`, each `text \| [text]` |
| `footer` | no | replaces the generated footer line |

The hero's four numbers are computed from `compare`, `verification.mutants` and `specs`; they are not fields.

## compare[]

| Field | Content |
|---|---|
| `variant` | the cfg name without the module (`mutant-code`, `fix-query-start`), or the module name for the main cfg |
| `kind` | `current` (the code before the change: `code-*`, `mutant-code`, `mutant-develop`), `fix` (`fix-*` not adopted yet), `alt` (an option cfg or a rejected design of Decisions), `adopted` (the main cfg) |
| `spec` | the module, as `` `PxHeapRcSnapshot` `` |
| `model` | what this variant is, one sentence with the code coordinate (sha, function) |
| `defect` | the violated claim and property, or `없음` |
| `effect` | what CUBRID does: a measured SQL result, error code or crash with its build; otherwise the code-level consequence; `—` for the adopted row |
| `reproduced` | `true` when `effect` was measured on a build, `false` when only the model shows it; omit when there is no defect |
| `handling` | first line `수정`, `기각` or `채택`; the next line the reason with its decision number |
| `evidence` | the cfg's TLC result (states), the counterexample section, trace validation, runtime numbers |

## models[]

| Field | Content |
|---|---|
| `id` | short id the counterexamples refer to |
| `dir`, `module`, `result` | spec directory, module name, its RESULT |
| `title` | the question the model answers, in GLOSSARY terms |
| `what` | `text \| [text]`: what the model runs together and what it must decide |
| `diagram` | Mermaid flowchart of the model's structure (SKILL.md step 4); node ids = action or label names |
| `diagramCaption`, `diagramRight`, `diagramNotes` | caption, right caption, notes under the figure |
| `claims` | `[{id, kind, text, source}]` from MAP.md `## Claim and sources` |
| `map` | optional `[{step, code, why}]`: the refinement-map rows the counterexamples pass through |

## counterexamples[]

| Field | Content |
|---|---|
| `title`, `lead` | what goes wrong, in one sentence and a paragraph (bounds of the run included) |
| `variant`, `kind`, `property` | the variant that fails, its kind, the violated property (`deadlock` for a deadlock) |
| `model` | `models[].id` whose diagram carries the path; `structure` replaces that diagram for this counterexample |
| `log` | the TLC log path the steps came from, or `null` when they came from MAP.md |
| `actors` | `[{id, label}]`, the sequence diagram's participants (threads, transactions, vacuum) |
| `steps` | one per TLC state after the initial one: `{actor, to?, action, node?, edge?, bad?, text, code?, state?}`. `node` is the diagram node the step is at; the edge from the previous step's node is lit when it exists, `edge: "A->B"` names it when the step re-enters a node; `bad: true` on the violating step |
| `stateCols` | the columns of the value table; each step's `state` maps a column to its value after the step |
| `fix` | `{variant, node, stopAt, text}`: the adopted variant's guard node and the step number it stops the trace at |
