---
name: grill-with-tla
description: A relentless interview to sharpen a CUBRID design, in which every decision is written into a TLA+ model that TLC checks and TLAPS proves before the next round, and the glossary and ADRs are written as we go.
disable-model-invocation: true
---

Call the Skill tool three times, for "grilling", "domain-modeling" and "cubrid-tla". Then run them
as one loop over a single spec directory, `docs/tla/<CBRD-key or slug>/`:

- **The model is the design tree's ledger.** A settled decision is written into the spec the same
  round (an action, a guard, a claim row in MAP.md). An open decision is a constant or a
  nondeterministic choice, so TLC explores every option still on the table.
- **Facts come from TLC, not from the user.** Before each round, run `tools/tla/tla-check` on the
  directory. An option whose variant violates a locked claim is struck from the round with its
  counterexample cited; a recommended answer names the cfg that supports it.
- **A counterexample becomes a question.** When the correct variant fails, the next round asks the
  decision the trace exposes, shown as numbered steps mapped to code (`file:function`) or SQL, in
  Korean. Model errors are fixed silently; only real design choices reach the user.
- **Claims are the user's.** Adding, dropping or weakening a claim, and every fairness or
  environment assumption a liveness claim needs (cubrid-tla P7), is a decision put to the user,
  never a fix made to get a pass.
- **Terms.** Action and variable names use GLOSSARY.md's terms; a term the model forces to be
  precise goes into GLOSSARY.md at once (domain-modeling).
- **ADRs.** A decision that meets domain-modeling's three ADR conditions cites the spec directory,
  the claim it settles and the `RESULT: OK` run that verified it.

The session is done when the grilling frontier is empty, `tools/tla/tla-check docs/tla/<key>/`
prints `RESULT: OK` (every claim with its mutant, TLAPS obligations all proved), MAP.md has no
blank row, and the user confirms the shared understanding. The verified spec is the abstract spec
the implementation must later refine (cubrid-tla step 9).
