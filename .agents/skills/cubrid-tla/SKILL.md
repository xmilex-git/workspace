---
name: cubrid-tla
description: "Verify a CUBRID design or code change in TLA+ — model it from the code, model-check it with TLC, check its inductive invariant with Apalache (TLAPS proof only on an explicit request), validate recorded runs against it, and hunt the holes (races, lost wakeups, deadlocks, use-after-free, lost errors, crash and vacuum interleavings, unhandled input classes). Use when designing or changing concurrent or stateful engine logic (latches, locks, MVCC/vacuum, parallel query workers, WAL/recovery, state machines, decision tables), when asked to \"TLA+로 검증\", \"모델 체킹\", \"증명해줘\", \"설계 구멍 찾아\", and as the TLA+ step of cubrid-pr-review and grill-with-tla."
argument-hint: "<spec dir> | <claim or ticket to model>"
allowed-tools: Bash(tools/tla/*), Bash(just tla-*), Bash(tools/code-index/*), Bash(git *), Read, Write, Edit, Glob, Grep, Skill
---

# CUBRID TLA+ verification

A **verified model** is a spec directory for which `tools/tla/tla-check <dir>` prints `RESULT: OK`.
The check is mechanical; this skill is how to build a model that deserves it. A TLC pass proves the
model, not the code: what ties the two is the **refinement map** (every model step named at a code
site, with the protection that makes it one step) and **trace validation**
(a run of the real build accepted by the spec). A model that never fails is suspect until its
**mutants** fail.

The lessons behind every `(P<n>)` are in `PITFALLS.md`; a new lesson goes there as a case under its
rule, or as a new rule added to both files in one commit.

## Toolchain

- `just tla-install` once per host: TLC and the PlusCal translator (tla2tools 1.8.0), TLAPS
  (tlapm 1.6.0-pre with Isabelle2025, LS4, Zenon and Z3, the release build re-linked against nixpkgs' glibc in
  `tools/tla/tlapm-next.nix`) and Apalache 0.62.4 (`tools/tla/apalache.nix`), pinned in
  `tools/tla/tools.nix`, GC root `.git_ignored_dir/tla/tools`.
- `tools/tla/tla-check [--prove] [--workers N] [--heap SIZE] [--stretch F] DIR...` (or `just tla-check DIR...`)
  translates PlusCal, runs every cfg, proves every theorem only with `--prove`, and checks completeness.
  `--only GLOB` reruns the matching cfgs or proof modules while iterating; it ends in `RESULT: PARTIAL`,
  never a result. Evidence goes to
  `.git_ignored_dir/scratch/tla/<dir>-<stamp>/`; read only the `PASS`/`FAIL` lines and the last line.
- `tools/tla/apalache-split DIR CFG K/N [CONJ...]` checks group K of N of an Apalache inductive cfg's IndInv
  conjuncts and prints PASS, or the counterexample's step diff (step 6); `TF=<regex>` checks a subset of Next's
  transitions (P63).
- `tools/tla/trace2tla <Module> <Op>=<log>...` turns `TLATRACE` lines of an instrumented run into a
  TLA+ data module (`TRACE.md`).
- `just tla-selftest` runs `examples/`; run it after touching `tools/tla/` or this skill's rules.
- TLAPS runs only when the user's own message explicitly asks for a proof ("TLAPS", "증명해줘", "명확히 검증해줘"): then `tools/tla/tla-check --prove` proves every proof module and requires one; otherwise no proof module is written, step 6 ends at the inductive cfgs, and the report says TLAPS 요청 없음. A generic "TLA+로 검증", a skill, a ticket or a review step never counts as that request. (P48)
- TLC and tlapm run only through `tools/tla/tla-check`, whose verdict is read per cfg and per obligation, never from a tool's exit status. (P1)
- Change `tools/tla/tla-check` by writing a new file and renaming it over the old one: bash reads a running script from its open file, so an in-place rewrite corrupts the runs other sessions have in flight. (P18)
- Stop only the processes your own runner started, by the pid it recorded; other sessions run tlapm and TLC on this host at the same time, so never kill by pattern or by a pid read from `ps`. (P29)

## Where the model lives

| Work | Spec directory |
|---|---|
| design or implementation (yours, a ticket) | `docs/tla/<CBRD-key or slug>/` in this repo, committed with the design |
| PR review | `.claude/review/PR-<N>/tla/<slug>/` beside the report (local) |
| skill examples | `.agents/skills/cubrid-tla/examples/<slug>/` |

## The directory a verified model needs

`tla-check` refuses a directory that lacks any of these:

| File | Role |
|---|---|
| `<Module>.tla` | the spec: PlusCal for code-shaped logic (labels = atomic steps), plain TLA+ for state-shaped logic |
| `<Module>.cfg` | main check, `\* expect: pass`; INVARIANTS name every safety property and `IndInv`, PROPERTY every liveness property |
| `<Module>.scale-<n>.cfg` | the same check with constants one size up |
| `<Module>.mutant-<n>.cfg` | one per claim at least: a known-wrong variant (`Mutant` constant) the properties must reject |
| `<Module>.witness-<n>.cfg` | an outcome that must be reachable, as an invariant `Not<Outcome>` expected violated |
| `<Module>.apalache-<n>.cfg` | `INIT IndInv`, `NEXT Next`, `INVARIANT IndInv` checked by Apalache over every value of the integer constants (`PROOFS.md`, "Apalache"): the inductive check |
| `<Module>.inductive-<n>.cfg` | the same check by TLC, only when IndInv's types do not fit Apalache (P42) |
| `<Module>_proofs.tla` | only when the user asked for a proof (P48): TLAPS proof of the three INV1 premises for the correct variant (`PROOFS.md`) |
| `MAP.md` | claims, refinement map, properties, fault model, mutants, witnesses, dead expressions, bounds |
| trace files (every model of code; `trace-exempt:` in MAP.md only for a design with no implementation or a pattern example) | `<Module>Trace.tla`, its data module, `*.witness-trace-*.cfg`, `*.reject-*.cfg` (`TRACE.md`) |

Each cfg's first line is its expectation (`\* expect: pass | violation <Name> | deadlock | liveness |
refinement`); only mutant and witness cfgs may expect an error, and `tools/tla/tla-check`'s header
lists the optional lines. A mutant that only the refinement mapping catches is expected as `\* expect: refinement`: TLC reports a broken refinement as "Action property line N ... of module <Abstract> is violated", by location, not by the PROPERTY's name. (P10) Shape anchors: `examples/px-error-handoff/`
(PlusCal, faults, trace validation) and `examples/condvar-handoff/` (fairness, environment process).

## Steps

### 1. Claims

Write MAP.md's `## Claim and sources` table first: one row per claim `C<n>`, each a sentence a
reader can falsify, each with its source — the JIRA body or `design.md` clause, the PR description,
a code comment, the manual, POSIX. Collect them from every place the behavior is specified: for a
feature spread over several tickets, every linked ticket and its comments (`/jira`), the latest
statement winning and the superseded one named. Every claim is a safety (never X), a liveness
(eventually Y) or an equivalence (same answer as Z) property.

A claim you cannot source is a question for the user, not an assumption. Done when every behavior
the change or design promises is a row.

### 2. Refinement map

Read the code at the exact sha (`tools/code-index/code-index <worktree> body|callers|references`).
For every shared variable the claims touch, name who writes it and under which protection (page
latch, lock, mutex, atomic, single owner). Then cut steps:

- One model step = the code between two acquire/release points of the protection guarding the
  shared state it touches. An access to shared state outside any protection is its own step.
- A coarser step hides races; that is the model's most common hole. Justify every step boundary in
  the map's "One step because" column.
- Name every row at `file:function` and the symbol. A row you cannot place in code is a model
  invention: delete it or make it a claim.

Before the model is final, list the callers of every protocol entry point in the mapped code (code-index `callers`) and give each exit path (LIMIT, error, interrupt, reset, the end of a range) an action or a fault-table row saying why it is not modeled. (P11)

- Map each return branch of a wait separately and name the lock it holds: a primitive that returns unlocked (`thread_suspend_timeout_wakeup_and_unlock_entry`) gets one row per branch of its caller, and a branch that does not re-lock is split at each shared read and write, never copied from the branch that does. (P43)
- Before the report, give every function a hunk of the verified change touches, and every path between its acquire and release points (error returns, interrupts, hand-offs, invalidation, lock-free lookups), a map row or a fault-table row carrying the code fact that excludes it; "not covered" is never a report line. (P44)

Done when every action and every variable of the spec has a row (`MODELING.md` has the CUBRID
primitive patterns: page latch, lock manager, MVCC snapshot and vacuum, WAL, PX workers, condvar).

### 3. Fault model

Walk `MODELING.md`'s fault checklist (error return at each call, interrupt, lock timeout, deadlock
victim, OOM, crash / `kill -9`, spurious wakeup, concurrent DML, vacuum, checkpoint, HA apply) and
record each as modeled or not applicable with the reason. Faults are nondeterministic actions,
enabled wherever the code can raise them. Environment assumptions (fairness, bounded spurious
wakeups) go in the same table; a liveness claim names the fairness it needs and the code that
provides it. Done when every checklist row is answered (the crash row: P27).

### 4. Spec and cfgs

- Constants: the smallest values that still exhibit each interleaving class: at least 2 of every
  concurrent role (3 when a claim is about "all" or "any other"), every input class of a decision
  (NULL, each type class, boundary values). The scale cfg goes one size up.
- Ghost variables flag violations (`uaf`, `badConsume`) and record outcomes for witnesses.
- `Mutant` is a constant; each mutant re-enables one wrong ordering, missing guard or missing
  check the claims depend on. In a review, the pre-change behavior is a mutant: the defect the
  ticket describes must fail on it (fail-before) and pass on the change (pass-after).
- Before the first TLC run, read the spec against `MODELING.md`'s "Spec traps": each is a wrong verdict TLC reports
  silently or a parse error far from its cause. (P8, P19, P25, P56, P58, P59, P60)

### 5. Check, then hunt

Run `tools/tla/tla-check <dir>`; iterate until `RESULT: OK`. Then attack the model — each attack
either adds a cfg that passes or produces a finding:

1. **Mutation.** For every guard, ordering, latch hold and check in the mapped code, ask whether
   some mutant removes it. Add one per guard the claims rely on. A guard whose removal violates
   nothing is a **surviving mutant**: either a property is missing (add it) or the guard is not
   needed (a finding or a question).
2. **Dead expressions.** `dead-expr-lines` lists sub-expressions TLC never evaluated; MAP.md
   explains each as a mutant-only branch, a violation ghost, or a hole in the model. A dead expression that maps to code is explained by the code fact that makes it unreachable (`file:line`), or the model grows until it fires; "not reached at these bounds" counts only after a larger bound leaves it dead too, and MAP.md names that bound. (P12)
3. **Atomicity.** Split every step adjacent to shared state once more; a pass that only holds
   with the coarser step means the code relies on a protection the map must name. A guard and the shared-state access it protects are two steps when the code reads them apart (an interrupt check, then a lookup of shared memory): a mutant that survives the coarser step is the signal to split it. (P24)
4. **Faults.** Enable each fault at every point the code can raise it, not only at the first.
5. **Scale.** The scale cfg must pass; a property that fails only at N+1 is a finding.
6. **Liveness.** A liveness counterexample in the correct model that loops through an unfair lock retake is a fairness assumption to state in MAP.md (and to put to the user when it is a design question), never a reason to weaken the property. (P7)

### 6. Inductive invariant (and proof on request)

Write `IndInv` as a list of named conjuncts, one `  /\ Name` per line, and check it with the Apalache inductive cfg
(`PROOFS.md`, "Apalache": the cfg, the typing and the traps; TLC's inductive cfg only where Apalache cannot type it). Only
when the user asked for a proof (P48), prove the INV1 premises and their temporal conclusion `Spec => []IndInv` with
TLAPS (`PROOFS.md`).

- Iterate the inductive check with `tools/tla/apalache-split`, one background job per group of conjuncts, never with repeated single runs: IndInv's first version already carries the well-formedness conjuncts every protocol needs (each index field in range, each idle handler's fields reset, each message in the shape its sender builds, each queue holding only what its phase allows, each record not yet in use equal to its initial value); a group is classified and fixed as soon as it ends, while the others run; after a fix only the added or changed conjuncts rerun, since a stronger IndInv keeps every other group's pass (a weakened conjunct reruns them all); `tools/tla/tla-check`'s single run is the record once every group passed, and an IndInv too large for one Apalache run is recorded as several `apalache-<n>` cfgs, each INVARIANT a part of IndInv under `INIT` of the whole, which tla-check runs in parallel beside the TLC cfgs. (P62)
- An inductive-cfg counterexample from a state the system cannot reach means IndInv is too weak: strengthen IndInv, never the spec, and keep IndInv in the main cfg's INVARIANTS so TLC confirms the strengthened conjunct on every reachable state. (P6)
- An obligation fails until the proof is right: split it, never `OMITTED`, never a weaker theorem.
  `PROOFS.md` lists what tlapm on this host cannot do and the sound workaround for each.

### 7. Counterexamples

Every TLC counterexample from a correct-variant cfg is classified in MAP.md before anything else:

- **Model error**: the trace takes a step the mapped code cannot take. Fix the map or the spec, and
  name the code line that forbids the step.
- **Hole**: every step maps to code, and no protection forbids the interleaving. It becomes a
  finding only after a runtime reproduction (`cubrid-diagnose`: a fail-before run on a build, with
  a delay injected on a scratch worktree when the window is narrow); until then it is a question
  carrying the step-by-step trace mapped to `file:line`. `TRACE.md` "Reproducing a hole" says which runs count. (P17, P26)
- A counterexample that needs the scan or buffer to stop where the code's capacity checks forbid it is a model error: derive a stop or overflow condition from the code's arithmetic (what the check counts, what it reserves) before a hole is reported. (P28)
- A hole confirmed in the code stays a failing `\* expect: pass` cfg of the code as it stands, so the directory reports `RESULT: FAILED` until the code is fixed; the candidate fix gets its own pass cfg, and the code cfg's expectation is never flipped to make the directory pass. (P9)

### 8. Trace validation (every model of code)

- Every model of code that exists — a PR head, a branch, develop — is tied to it by trace validation: an instrumented build of the exact sha records runs the trace spec accepts and a corrupted run it refuses, and `tools/tla/tla-check` fails a directory without a `*.witness-trace-*` and a `*.reject-*` cfg. Only a design spec with no implementation yet, or a pattern example, carries a MAP.md line `trace-exempt: <reason>`, and the implementation's spec adds the trace later. (P50)

Instrument a scratch worktree of the exact sha,
record runs that cover every action of the refinement map, and check them (`TRACE.md`). An
accepted run and a rejected corrupted run are both required; a run the spec refuses is a
divergence between code and model, resolved like a counterexample (step 7).

### 9. Refinement (when an abstract spec exists)

When the design was verified as an abstract spec (`docs/tla/<key>/`), the code-level spec of the
implementation must refine it: its main cfg names the abstract spec as a PROPERTY through a
refinement mapping (`MODELING.md`, "Refinement"). A design spec without an implementation spec is
recorded as such in the report.

### 10. Record and report

- A model is a result only once `tools/tla/tla-check` has run it to `RESULT: OK`: TLC on the main and scale cfgs, every mutant rejected, every witness reached, IndInv inductive (Apalache, or TLC where Apalache cannot type IndInv), TLAPS proving the INV1 theorems when the user asked for a proof (P48), and trace validation where step 8 requires it; a spec written but not run, or run without a proof the user asked for, is reported as 미완, never as verified. (P45)

MAP.md's last section, `## Result`, holds the facts: date, `RESULT: OK` line, run dir, per-cfg
states and depth, obligations proved (or TLAPS 요청 없음), the spec sha256 lines from `summary.txt`, the engine sha and
build the trace ran on. The report (review or design) carries a TLA+ block in Korean:

```
TLA+ 검증: <통과 | 실패 | 미완> — <spec dir>
- 속성: C1 <safety|liveness> <TLC 통과|실패> <TLAPS: 이 spec | 추상 spec + TLC refinement | 요청 없음> ... (claim별 한 줄, 출처)
- 결함: <없음 | H<n> 코드 cfg 실패, 런타임 재현(빌드 fingerprint, 결과), 후보 수정 cfg 통과>
- mutant: <n>개 모두 위반 검출 / 살아남은 mutant: <없음 | 목록>
- 경계: <상수>, scale <상수>; IndInv 귀납성은 Apalache로 정수 상수 전 범위(역할 집합 크기는 고정); TLAPS(요청 시)는 safety (`Spec => []IndInv`), liveness는 공정성 증명을 쓴 claim만 (나머지는 TLC 경계 안에서만)
- trace validation: <수용 n건, 거부 n건 | trace-exempt(구현 전 설계 또는 패턴 예제)>
- 반례: <없음 | 분류와 재현 여부>
```

A TLAPS proof of an abstract spec counts for the code-level model only through a refinement PROPERTY that TLC checks on that model's cfgs, inside their bounds; the report says per claim which it has: TLAPS on the abstract spec plus TLC refinement, TLC only, or neither. (P16)

A completion report names the bounds and what the model does not cover; "검증됨" without the bounds
and the fault table is not a result.

Completion: `tools/tla/tla-check <dir>` prints `RESULT: OK` (or `RESULT: FAILED` only on the code cfgs
of confirmed holes, each a MAP.md finding with its runtime reproduction), MAP.md has every section filled with
no row left blank, every counterexample is classified, trace validation is done or recorded as not
required with the reason, and the report block above is written.
