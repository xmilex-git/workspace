# CBRD-28033 — the batched nested-loop join beyond one join step (open design, not a verified model)

Status: **work in progress**. `BatchChain` was written in the grilling round of 2026-11-11 to settle what a batch must
hold when it stays open while the join step above moves to its next row. It was checked with TLC only (10 cfgs, each
as expected); it has no inductive invariant, no refinement map and no trace validation, and nothing here is
implemented. The one-step join that is implemented is the verified model `BatchJoin` in `docs/tla/CBRD-28005/`
(its MAP: D38, D39, C8). Whether the batched join is adopted at all is under consideration (CBRD-28033 body;
`docs/tla/CBRD-28005/MAP.md` D40..D43).

## What the model says (TLC, bounds N0 = 3, F1 = 2, M2 = 2, Cap1 = 2, Cap2 = 3)

| cfg | Result | Meaning |
|---|---|---|
| `BatchChain` | pass | a batch that carries every value list above it (`Prefix`) and stays open across the rows of the step above returns the same rows in the same order |
| `BatchChain.option-upper-end` | pass, `FanBound` holds | closing at the end of the upper row's children (the implemented rule, D38) is correct, and a batch never holds more than the fan-out of one upper row |
| `BatchChain.mutant-no-prefix` | violation `AllReturned` | the stored form of D38 (the immediate outer's values only) kept open across upper rows returns a row with the wrong upper value |
| `BatchChain.mutant-bottom-up` | violation `AllReturned` | when the first scan ends the levels are emptied from the top; emptying the lower level first leaves rows held |
| `BatchChain.option-last-row` | pass | leaving the value lists above as the last replayed row is correct only because a full batch closes in the call that filled it |
| `BatchChain.mutant-late-close` | violation `NoExtra` | ... and breaks as soon as a close is late |
| `BatchChain.option-late-saved` | pass | putting back what the value lists held when the batch closed is correct either way: the rule to implement |
| `BatchChain.witness-span`, `-nested`, `-done` | reached | a batch holding rows of two upper rows; a replay of the lower level inside the upper level's replay; a finished run |

A level of the model is a join step or the index lookup of a correlated subquery of the upper step's row: both run once
for a row of the step above and read the value lists above them.

## Decisions carried over (the user, 2026-11-11)

- The target scope of CBRD-28033: join steps at any depth, the index lookup of a correlated subquery, semi and anti
  joins; not the correlated subquery of a first scan, nor the join step under a step with a correlated subquery.
- No parameter: if adopted it runs by default. Errors of rows read ahead are accepted; C8 is stated for statements
  whose snapshot is not rebuilt; a correlated subquery runs as many times and in the same order.
- A subquery with a result cache is not read ahead for a key the cache holds.

## Owed before this is a verified model

Claims and sources, refinement map, fault table, IndInv with its Apalache cfgs, trace validation after the code
exists, `## Result`.
