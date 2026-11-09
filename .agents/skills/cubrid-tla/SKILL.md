---
name: cubrid-tla
description: "Verify a CUBRID design or code change in TLA+: model it from the code, model-check it with TLC (mutants, witnesses, scale), check its inductive invariant with Apalache, validate recorded runs of the build against it, and hunt the holes (races, lost wakeups, deadlocks, use-after-free, lost errors, crash and vacuum interleavings, unhandled input classes). TLAPS proof only when the user explicitly asks. Use when designing or changing concurrent or stateful engine logic (latches, locks, MVCC/vacuum, parallel query workers, WAL/recovery, state machines, decision tables), when asked to \"TLA+로 검증\", \"모델 체킹\", \"증명해줘\", \"설계 구멍 찾아\", and as the TLA+ step of cubrid-pr-review and grill-with-tla."
argument-hint: "<spec dir> | <claim or ticket to model>"
allowed-tools: Bash(tools/tla/*), Bash(just tla-*), Bash(tools/code-index/*), Bash(git *), Read, Write, Edit, Glob, Grep, Skill
---

# CUBRID TLA+ verification

This file is the whole route. The reference files hold detail reached from one step only:
`MODELING.md` (CUBRID primitive patterns, refinement), `INDUCTIVE.md` (Apalache), `TRACE.md`
(instrumentation, hole reproduction), `PROOFS.md` (TLAPS, on request only). The run behind every
`(P<n>)` is in `PITFALLS.md`; a new lesson goes there as a case under its rule, or as a new rule
whose sentence is added to this file (or the reference file it belongs to) in the same commit.

## Terms

- **Verified model**: a spec directory for which `tools/tla/tla-check <dir>` prints `RESULT: OK`.
- **Claim** `C<n>`: a falsifiable sentence the change or design promises, with its source.
- **Refinement map**: every model step named at a code site with the protection that makes it one step. Model-checking proves the model; the map and **trace validation** (a recorded run of the real build accepted by the spec) tie it to the code.
- **Mutant**: a known-wrong variant the properties must reject. **Witness**: an outcome that must be reachable. A pass with a **surviving mutant** or an unexplained **dead expression** is **vacuous**: it proves nothing until the mutant fails or the expression fires.
- **IndInv**: the inductive invariant; a **CTI** (counterexample to induction) is an IndInv state with a successor outside IndInv.
- **Hole**: a counterexample whose every step maps to code; a finding only after a runtime reproduction.

## Toolchain

- `just tla-install` once per host (TLC + PlusCal 1.8.0, Apalache 0.62.4, tlapm 1.6.0-pre; pinned in `tools/tla/tools.nix`, GC root `.git_ignored_dir/tla/tools`).
- `tools/tla/tla-check [--prove] [--only GLOB] [--workers N] [--heap SIZE] DIR...` translates PlusCal, runs every cfg (Apalache cfgs in the background beside TLC), proves with `--prove` only, and checks the directory's completeness; its header lists every cfg line it reads. Evidence: `.git_ignored_dir/scratch/tla/<dir>-<stamp>/`; read the `PASS`/`FAIL` lines and the last line. `--only` ends in `RESULT: PARTIAL`.
- `tools/tla/apalache-split DIR CFG K/N [CONJ...]` checks one group of IndInv's conjuncts (`INDUCTIVE.md`); `tools/tla/trace2tla` turns `TLATRACE` log lines into a data module (`TRACE.md`); `just tla-selftest` runs `examples/` after any change to `tools/tla/` or this skill.
- TLC, Apalache and tlapm run only through `tools/tla/tla-check`, whose verdict is read per cfg and per obligation, never from a tool's exit status. (P1)
- TLAPS runs only when the user's own message asks for a proof ("TLAPS", "증명해줘", "명확히 검증해줘"); a generic "TLA+로 검증", a skill, a ticket or a review step is not that request, and without it no proof module is written and the report says TLAPS 요청 없음. (P48)
- `tools/tla/tla-check` is changed by writing a new file and renaming it over the old one: bash reads a running script from its open file. (P18)
- Stop only the processes your own runner started, by the pid it recorded; other sessions run TLC and tlapm on this host. (P29)

## Where the model lives

| Work | Spec directory |
|---|---|
| design or implementation (yours, a ticket) | `docs/tla/<CBRD-key or slug>/`, committed with the design |
| PR review | `.claude/review/PR-<N>/tla/<slug>/` beside the report (local) |
| skill examples | `examples/<slug>/` — `px-error-handoff` (PlusCal, faults, trace), `condvar-handoff` (fairness, environment process, Apalache) |

## The directory a verified model needs

| File | Role |
|---|---|
| `<Module>.tla` | PlusCal for code-shaped logic (one label = one step), plain TLA+ for state-shaped logic |
| `<Module>.cfg` | main check, `\* expect: pass`; INVARIANTS name every safety property and `IndInv`, PROPERTY every liveness property |
| `<Module>.scale-<n>.cfg` | the same check with constants one size up |
| `<Module>.mutant-<n>.cfg` | one per claim at least: a `Mutant` constant value the properties must reject |
| `<Module>.witness-<n>.cfg` | an outcome that must be reachable, as an invariant `Not<Outcome>` expected violated |
| `<Module>.apalache-<n>.cfg` | `INIT IndInv`, `NEXT Next`, `INVARIANT IndInv` by Apalache over every value of the integer constants (`INDUCTIVE.md`) |
| `<Module>.inductive-<n>.cfg` | the same by TLC, only when Apalache cannot type IndInv (P42) |
| `<Module>Trace.tla` + data module, `*.witness-trace-*.cfg`, `*.reject-*.cfg` | trace validation of every model of code (`TRACE.md`); a design with no implementation or a pattern example carries `trace-exempt: <reason>` in MAP.md instead |
| `<Module>_proofs.tla` | only when the user asked for a proof (P48) |
| `MAP.md` | claims, refinement map, properties, fault table, mutants, witnesses, dead expressions, bounds, `## Result` |

Each cfg's first line is its expectation (`\* expect: pass | violation <Name> | deadlock | liveness | refinement`); only mutant and witness cfgs may expect an error. A mutant that only the refinement mapping catches is expected as `\* expect: refinement`: TLC reports a broken refinement by location, not by the PROPERTY's name. (P10)

## Steps

### 1. Claims

Write MAP.md's `## Claim and sources` table first: one row per claim, each a sentence a reader can falsify, each with its source (JIRA body or `design.md` clause, PR description, code comment, manual, POSIX). Collect from every place the behavior is specified — for a feature spread over tickets, every linked ticket and its comments (`/jira`), the latest statement winning and the superseded one named. Every claim is a safety (never X), a liveness (eventually Y) or an equivalence (same answer as Z). A claim you cannot source is a question for the user, not an assumption. Done when every behavior the change or design promises is a row.

### 2. Refinement map

Read the code at the exact sha (`tools/code-index/code-index <worktree> body|callers|references`). For every shared variable the claims touch, name who writes it and under which protection (page latch, lock, mutex, atomic, single owner). Then cut steps:

- One step = the code between two acquire/release points of the protection guarding the shared state it touches; an access outside any protection is its own step; an atomic is one step per operation (a CAS or fetch-add is one, a load then a store are two); a condition wait is two steps (release-and-sleep, wake-and-reacquire). A coarser step hides races — the model's most common hole; justify every boundary in the map's "One step because" column.
- Name every row at `file:function` and the symbol. A row you cannot place in code is a model invention: delete it or make it a claim.
- Before the model is final, list the callers of every protocol entry point (code-index `callers`) and give each exit path (LIMIT, error, interrupt, reset, the end of a range) an action or a fault-table row. (P11)
- Each return branch of a wait is its own row naming the lock it holds on return; a branch that returns unlocked is split at every shared read and write. (P43)
- Every function the change's diff touches, and every path between its acquire and release points, has a map row or a fault-table row with the code fact that excludes it; "not covered" is never a report line. (P44)
- A guard and the shared-state access it protects are two steps when the code reads them apart; a mutant that survives the coarser step is the signal to split it. (P24)

`MODELING.md` has the CUBRID primitive patterns (page latch, lock manager, MVCC snapshot and vacuum, WAL, PX workers, condvar, decision table) and the code each one is read from. Done when every action and every variable of the spec has a row.

### 3. Fault model

Answer every row of this checklist in MAP.md's fault table as modeled, or not applicable with the reason. Faults are nondeterministic actions enabled wherever the code can raise them, not only at the first site. Environment assumptions (fairness, bounded spurious wakeups) go in the same table; a liveness claim names the fairness it needs and the code that provides it.

| Fault | Where it can fire |
|---|---|
| error return | every call in the mapped code that returns an error code |
| interrupt / query cancel | every loop that checks `logtb_is_interrupted` or the PX interrupt |
| lock timeout, deadlock victim | every unconditional lock request |
| conditional latch failure | every `PGBUF_CONDITIONAL_LATCH` fix and every promotion |
| OOM | every allocation whose failure path the change touches |
| crash / `kill -9` | between any two durable writes; for temp files, between create and cleanup |
| spurious wakeup | every condition wait |
| concurrent DML | every page or object the scanned set covers |
| vacuum | every version a snapshot of the change can read |
| checkpoint, page flush, page replacement | every page fixed without being pinned across the step |
| HA log apply | replicated state the change reads on a slave |
| nested statement (SP SQL from the client) | the READ COMMITTED statement snapshot the change reads |

- A crash fault's intermediate state is the exact page write of the function that performs the first half, read in that function, never the caller's comment. (P27)
- A model that reads the READ COMMITTED statement snapshot has a fault row for a nested statement (SP SQL from the client) that invalidates and rebuilds it mid-statement (`network_sr.c` `logtb_invalidate_snapshot_data`). (P55)

### 4. Spec and cfgs

- Constants: the smallest values that still exhibit each interleaving class — at least 2 of every concurrent role (3 when a claim says "all" or "any other"), every input class of a decision (NULL, each type class, boundary values). The scale cfg goes one size up.
- Ghost variables flag violations (`uaf`, `badConsume`) and record outcomes for witnesses.
- `Mutant` is a constant; each mutant re-enables one wrong ordering, missing guard or missing check the claims depend on. In a review the pre-change behavior is a mutant: the ticket's defect must fail on it and pass on the change.
- Fairness: weak fairness on a process covers a step that stays enabled; a mutex retake enabled only intermittently is not covered, and a lock or latch is fair only when the code queues waiters in order. Environment processes get no fairness unless a claim needs it, and MAP.md says so. TLC refuses SYMMETRY with PROPERTY (liveness is unsound under it).

Spec traps — each a wrong verdict TLC or Apalache reports silently, or a parse error far from its cause; read the spec against them before the first run:

- `define` sees globals only: state the properties read is declared as a global variable. (P5)
- An environment process that loops (the OS, vacuum, a DML stream) must be able to end when the system ends, or TLC reports a false deadlock. (P8)
- A worker loop is bounded by a counter every iteration advances, never by one only some iterations advance, or TLC reports a false liveness counterexample. (P25)
- A cfg writes only simple values (naturals, strings, model values and sets of them); a negative number, a sequence or a function is a spec operator substituted in the cfg with `Name <- Op`. (P19)
- An ordered decision is an IF ... ELSE IF chain: a CASE whose guards can hold together is a CHOOSE, and TLC's first-match hides the arm Apalache or Isabelle may take. (P56)
- A variable both assigned and listed in UNCHANGED silently narrows the action to where the two agree; after a bulk UNCHANGED edit, check each action that assigns the variable. (P58)
- Comments say `COUNT-star`, never `COUNT(*)`: `(*` opens a nested block comment and SANY reports the EOF far below it. (P60)
- Apalache takes no `Seq(_)` and no `a..b` with a non-constant bound: a program is a function over `1..N` with `N` a constant, and a variable-bounded range is written as inequalities over a constant range. (P59)
- Every CONSTANTS and VARIABLES declaration carries its first name on the keyword's line, or `tools/tla/apalache-types` leaves the block untyped. (P47)

### 5. Check, then hunt

Run `tools/tla/tla-check <dir>`; iterate until `RESULT: OK`. A pass is suspect until the model fails on demand, so attack it — each attack adds a cfg that passes or produces a finding:

1. **Mutation.** For every guard, ordering, latch hold and check in the mapped code, add the mutant that removes it. A guard whose removal violates nothing is a surviving mutant: a property is missing (add it) or the guard is not needed (a finding or a question).
2. **Dead expressions.** `tla-check` lists sub-expressions TLC never evaluated; MAP.md explains each as a mutant-only branch, a violation ghost, or a hole in the model. A dead expression that maps to code is explained by the code fact that makes it unreachable (`file:line`), or the model grows until it fires; "not reached at these bounds" counts only after a larger bound leaves it dead too. (P12)
3. **Atomicity.** Split every step adjacent to shared state once more; a pass that holds only with the coarser step means the code relies on a protection the map must name.
4. **Faults.** Enable each fault at every point the code can raise it.
5. **Scale.** A property that fails only at N+1 is a finding.
6. **Liveness.** A liveness counterexample that loops through an unfair lock retake is a fairness assumption to state in MAP.md (and to put to the user when it is a design question), never a reason to weaken the property. (P7)

### 6. Inductive invariant

Write `IndInv` as a list of named conjuncts, one `  /\ Name` per line, and check it with the Apalache cfg (`INDUCTIVE.md`: cfg, typing, iteration, traps). Only when the user asked for a proof (P48), prove the INV1 premises with TLAPS (`PROOFS.md`).

- Every safety property of the claims is a named conjunct of IndInv, so the inductive check reaches the claims without a proof. (P64)
- The inductive check is iterated with `tools/tla/apalache-split`, one background job per group of conjuncts, from an IndInv whose first version already holds the well-formedness conjuncts (index fields in range, idle handlers reset, messages in their sender's shape, queues holding only what their phase allows); after a fix only the changed conjuncts rerun, and `tla-check`'s run is the record. (P62)
- A conjunct too slow for one Apalache run is split by transition (`TF=` on apalache-split, `search.transitionFilter` on a part cfg), the parts together covering every transition; a part's timeout is never a pass. (P63)
- A CTI from a state the system cannot reach means IndInv is too weak: strengthen IndInv, never the spec, and keep IndInv in the main cfg's INVARIANTS so TLC confirms the new conjunct on every reachable state. (P6)
- The inductive check is the Apalache cfg; a TLC inductive cfg is written only when IndInv's types do not fit Apalache. (P42)

Time budget — the B1a check of P62 took four hours because each round waited for its slowest group and reran what had passed; this is the procedure that avoids it:

1. Write IndInv with its well-formedness conjuncts, then launch every group at once as background jobs — `TMO=1200 tools/tla/apalache-split <dir> <Cfg> K/N` for K = 1..N, N ≈ conjuncts / 6 — and classify each group the moment it ends (`PASS`, `CTI` with its State0 → State1 diff, `ERROR ... timeout`). Independent work continues meanwhile; no group is waited on.
2. A group that times out at 1200 s is relaunched as transition parts in parallel: read `Found N transitions` from its log and run `TF='0->0|1->(k|k+8|k+16|...)'` for k = 0..7, each its own background job; a part's timeout is a smaller part, never a pass.
3. After a fix, rerun by name only the conjuncts the fix added or changed (`apalache-split <dir> <Cfg> 1/1 Inv7 Inv12`); a strengthened IndInv keeps every other group's pass.
4. `tools/tla/tla-check <dir>` runs once, after every group has passed. A conjunct that passes only as transition parts becomes its own `apalache-<n>.cfg` per part with `--tuning-options=search.transitionFilter=...` on its `\* apalache:` line, so the record run is parallel too; a cfg that needs more than 1800 s carries a `\* timeout:` line.

### 7. Counterexamples

Every counterexample from a correct-variant cfg is classified in MAP.md before anything else:

- **Model error**: the trace takes a step the mapped code cannot take. Fix the map or the spec and name the code line that forbids the step. A counterexample that stops the scan or buffer where the code's capacity checks forbid it is a model error: derive the stop condition from the code's arithmetic first. (P28)
- **Hole**: every step maps to code and no protection forbids the interleaving. Until a run of the build takes the same steps (`cubrid-diagnose`; `TRACE.md` "Reproducing a hole") it is a question carrying the trace mapped to `file:line`. A hole's runtime reproduction logs the structural events of the counterexample (TLATRACE at the snapshot, alloc, free and fix sites), so a run shows the interleaving happened and not only a wrong answer. (P17)
- A hole confirmed in the code stays a failing `\* expect: pass` cfg, so the directory reports `RESULT: FAILED` until the code is fixed; the candidate fix gets its own cfg, and the code cfg's expectation is never flipped. (P9)

### 8. Trace validation

Every model of code that exists is tied to it by trace validation: an instrumented build of the exact sha records runs the trace spec accepts and a corrupted run it refuses; only a design with no implementation or a pattern example carries `trace-exempt: <reason>` in MAP.md. (P50)

Instrument a scratch worktree of the exact sha, record runs that cover every action of the refinement map (fault branches included), and check them (`TRACE.md`). A run the spec refuses is a divergence between code and model, classified like a counterexample (step 7).

### 9. Refinement (when an abstract spec exists)

When the design was verified as an abstract spec (`docs/tla/<key>/`), the implementation spec names it as a PROPERTY through a refinement mapping (`MODELING.md` "Refinement"); a design spec without an implementation spec is recorded as such in the report.

### 10. Record and report

- A model is a result only once `tools/tla/tla-check` has run it to `RESULT: OK`; a spec written but not run, or run without a proof the user asked for, is reported as 미완, never as verified. (P45)
- A TLAPS proof of an abstract spec reaches the code-level model only through a refinement PROPERTY TLC checks inside its bounds; the report says per claim what it has. (P16)

MAP.md's `## Result` holds the facts: date, `RESULT: OK` line, run dir, per-cfg states and depth, Apalache cfgs passed, obligations proved (or TLAPS 요청 없음), the spec sha256 lines from `summary.txt`, the engine sha and build the trace ran on. The report (review or design) carries this block in Korean:

```
TLA+ 검증: <통과 | 실패 | 미완> — <spec dir>
- 속성: C1 <safety|liveness> <TLC 통과|실패> <IndInv 귀납성: Apalache | TLC | TLAPS 요청 없음> ... (claim별 한 줄, 출처)
- 결함: <없음 | H<n> 코드 cfg 실패, 런타임 재현(빌드 fingerprint, 결과), 후보 수정 cfg 통과>
- mutant: <n>개 모두 위반 검출 / 살아남은 mutant: <없음 | 목록>
- 경계: <상수>, scale <상수>; IndInv 귀납성은 Apalache로 정수 상수 전 범위(역할 집합 크기는 고정); liveness는 TLC 경계 안에서만
- trace validation: <수용 n건, 거부 n건 | trace-exempt(구현 전 설계 또는 패턴 예제)>
- 반례: <없음 | 분류와 재현 여부>
```

Completion: `tools/tla/tla-check <dir>` prints `RESULT: OK` (or `RESULT: FAILED` only on the code cfgs of confirmed holes, each a MAP.md finding with its runtime reproduction), MAP.md has no row left blank, every counterexample is classified, trace validation is done or `trace-exempt` with its reason, and the block above names the bounds and what the model does not cover.
