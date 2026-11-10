---------------------------- MODULE MergePartials ----------------------------
(* The partial entries of one partition of the hash GROUP BY merge folded into the merge table
   (query_executor.c qexec_gby_merge_partials), for a GROUP BY without the first-row copy
   (rd->no_first_tuple): an entry whose key has no group yet makes one (qexec_gby_mtable_add),
   and the add can grow the slot array (qexec_gby_mtable_grow), which frees the array the
   caller's slot pointer s points into.  One thread, one partition. *)
EXTENDS Naturals, FiniteSets

CONSTANTS N, NK, Fix, Mutant
\* apalache-type: N Int
\* apalache-type: NK Int
\* apalache-type: Fix Str
\* apalache-type: Mutant Str

Ent  == 1..N                   \* the partial entries of the partition, in list order
Keys == 1..NK
Caps == {2, 4, 8, 16, 32, 64}  \* slot counts (the code starts at QEXEC_GBY_MTABLE_SLOTS = 256)
Gens == 0..N                   \* at most one grow per entry

VARIABLES ent, pre, has, grp, cnt, cap, gen, i, pc, s, v, uaf, grew, foldOld
\* apalache-type: ent Int -> Int
\* apalache-type: pre Set(Int)
\* apalache-type: has Int -> Bool
\* apalache-type: grp Int -> Int
\* apalache-type: cnt Int
\* apalache-type: cap Int
\* apalache-type: gen Int
\* apalache-type: i Int
\* apalache-type: pc Str
\* apalache-type: s {gen: Int, key: Int}
\* apalache-type: v {direct: Bool, gen: Int, key: Int}
\* apalache-type: uaf Bool
\* apalache-type: grew Bool
\* apalache-type: foldOld Bool

vars == <<ent, pre, has, grp, cnt, cap, gen, i, pc, s, v, uaf, grew, foldOld>>

\* ent[j]: the key of partial entry j (one row each, tuple_count 1).
\* pre: the keys whose group the partition's rows made before any partial entry (qexec_gby_merge_fold
\*   folds every piece's rows first, qexec_gby_merge_rows), one row each.
\* has[k], grp[k]: group k exists in the table; its tuple_count (the accumulators fold the same way).
\* cnt, cap, gen: t->count, t->mask + 1, and which slot array t->slots is (a grow makes the next one
\*   and frees the old one).
\* s: the slot pointer qexec_gby_mtable_find returned: the array it points into and the key it is for.
\* v: what the fold reads the group through: a slot pointer (direct = FALSE, valid only while
\*   gen = v.gen) or the group's value itself (direct = TRUE: the AGGREGATE_HASH_VALUE is carved
\*   from the arena, which a grow does not move).
\* uaf: a read through a slot of a freed array (ghost).  grew, foldOld: witnesses' ghosts.

Base(k) == IF k \in pre THEN 1 ELSE 0
Count(k) == Cardinality({j \in Ent : ent[j] = k})
Folded(k) == Cardinality({j \in Ent : j < i /\ ent[j] = k})

Init ==
  /\ ent \in [Ent -> Keys]
  /\ pre \in SUBSET Keys
  /\ has = [k \in Keys |-> k \in pre]
  /\ grp = [k \in Keys |-> Base(k)]
  /\ cnt = Cardinality(pre)
  \* the array the rows left: grown at half full from 2 slots
  /\ cap \in Caps /\ cap > 2 * cnt /\ (cap = 2 \/ cap \div 2 <= 2 * cnt)
  /\ gen = 0
  /\ i = 1
  /\ pc = "load"
  /\ s = [gen |-> 0, key |-> 1]
  /\ v = [direct |-> FALSE, gen |-> 0, key |-> 1]
  /\ uaf = FALSE
  /\ grew = FALSE
  /\ foldOld = FALSE

\* qdata_load_agg_hentry_from_tuple, qexec_gby_mtable_hash, qexec_gby_mtable_find: s points into
\* the current array; a key with a group folds through s (s->value), a key without one is added
Load ==
  /\ pc = "load"
  /\ IF i <= N
     THEN /\ s' = [gen |-> gen, key |-> ent[i]]
          /\ IF has[ent[i]]
             THEN /\ pc' = "fold"
                  /\ v' = [direct |-> FALSE, gen |-> gen, key |-> ent[i]]
                  /\ foldOld' = TRUE
             ELSE /\ pc' = "add"
                  /\ UNCHANGED <<v, foldOld>>
     ELSE /\ pc' = "done"
          /\ UNCHANGED <<s, v, foldOld>>
  /\ UNCHANGED <<ent, pre, has, grp, cnt, cap, gen, i, uaf, grew>>

\* after qexec_gby_mtable_add returned NO_ERROR: the budget check, then what the fold reads through
AfterAdd(k, g) ==
  \/ /\ pc' = "over"            \* limit > 0 && t->bytes > limit: break; qexec_gby_merge_partition rewinds
     /\ UNCHANGED v
  \/ /\ pc' = IF Mutant = "skip_new" THEN "next" ELSE "fold"
     /\ v' = IF Mutant = "develop"
             THEN [direct |-> FALSE, gen |-> s.gen, key |-> k]   \* s->value: s still points into the array it was found in
             ELSE IF Fix = "added"
             THEN [direct |-> TRUE, gen |-> g, key |-> k]        \* the value qexec_gby_mtable_add returned in *added
             ELSE [direct |-> FALSE, gen |-> g, key |-> k]       \* refind: s = qexec_gby_mtable_find () again

\* qexec_gby_mtable_add (tpl NULL): the group carved in the arena, s->key/s->value set, t->count++,
\* and qexec_gby_mtable_grow when t->count * 2 > t->mask (a new array, the old one db_private_free'd)
Add ==
  /\ pc = "add"
  /\ LET k == s.key
         c == cnt + 1
     IN /\ has' = [has EXCEPT ![k] = TRUE]
        /\ grp' = [grp EXCEPT ![k] = 0]
        /\ cnt' = c
        /\ IF c * 2 > cap - 1
           THEN \/ /\ cap' = cap * 2
                   /\ gen' = gen + 1
                   /\ grew' = TRUE
                   /\ AfterAdd(k, gen + 1)
                \/ /\ pc' = "err"         \* grow's db_private_alloc fails: rc != NO_ERROR, break
                   /\ UNCHANGED <<cap, gen, grew, v>>
           ELSE /\ UNCHANGED <<cap, gen, grew>>
                /\ AfterAdd(k, gen)
  /\ UNCHANGED <<ent, pre, s, i, uaf, foldOld>>

\* mutant skip_new: the new group takes no accumulators from the entry that made it
Skip ==
  /\ pc = "next"
  /\ i' = i + 1
  /\ pc' = "load"
  /\ UNCHANGED <<ent, pre, has, grp, cnt, cap, gen, s, v, uaf, grew, foldOld>>

\* qdata_aggregate_accumulator_to_accumulator (s->value->accumulators[i], ...) for every aggregate,
\* then s->value->tuple_count += tuple_count: the entry into its group
Fold ==
  /\ pc = "fold"
  /\ LET k == v.key
         stale == ~v.direct /\ v.gen # gen
     IN /\ uaf' = (uaf \/ stale)
        /\ IF stale
           THEN \/ grp' = [grp EXCEPT ![k] = grp[k] + 1]   \* the freed array not overwritten yet: the read lands on the group
                \/ UNCHANGED grp                          \* overwritten: a garbage group pointer, the entry is lost (or SIGSEGV)
           ELSE grp' = [grp EXCEPT ![k] = grp[k] + 1]
  /\ i' = i + 1
  /\ pc' = "load"
  /\ UNCHANGED <<ent, pre, has, cnt, cap, gen, s, v, grew, foldOld>>

Done ==
  /\ pc \in {"done", "over", "err"}
  /\ UNCHANGED vars

Next == Load \/ Add \/ Skip \/ Fold \/ Done

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
\* C1: no read through a slot of a freed slot array
NoStaleSlotRead == ~uaf

\* C2: a finished fold holds one group per key of the partition, each counting its rows and entries
FoldCorrect ==
  pc = "done" =>
    \A k \in Keys : /\ has[k] = (k \in pre \/ Count(k) > 0)
                    /\ grp[k] = Base(k) + Count(k)

TypeOK ==
  /\ ent \in [Ent -> Keys]
  /\ pre \in SUBSET Keys
  /\ has \in [Keys -> BOOLEAN]
  /\ grp \in [Keys -> 0..(N + 1)]
  /\ cnt \in 0..NK
  /\ cap \in Caps
  /\ gen \in Gens
  /\ i \in 1..(N + 1)
  /\ pc \in {"load", "add", "fold", "next", "done", "over", "err"}
  /\ s \in [gen : Gens, key : Keys]
  /\ v \in [direct : BOOLEAN, gen : Gens, key : Keys]
  /\ uaf \in BOOLEAN
  /\ grew \in BOOLEAN
  /\ foldOld \in BOOLEAN

Live == pc \in {"load", "add", "fold", "next", "done"}

\* the entry being handled is one of the partition's, and s and v are for its key
EntryIdx ==
  /\ pc \in {"add", "fold", "next"} => i <= N /\ s.key = ent[i]
  /\ pc = "fold" => v.key = ent[i]
  /\ pc = "done" => i = N + 1

\* the groups are the keys of the rows and of the entries before i (and of entry i once added)
HasGroups ==
  /\ pc \in {"load", "add", "done"} => \A k \in Keys : has[k] = (k \in pre \/ Folded(k) > 0)
  /\ pc \in {"fold", "next"} => \A k \in Keys : has[k] = (k \in pre \/ Folded(k) > 0 \/ k = ent[i])
  /\ pc = "add" => ~has[s.key]

\* every group counts its rows and the entries folded so far
GroupCounts == Live => \A k \in Keys : grp[k] = Base(k) + Folded(k)

CountIsGroups == pc # "err" => cnt = Cardinality({k \in Keys : has[k]})

\* grown at half full: below half after every add that returned NO_ERROR
LoadFactor == pc # "err" => 2 * cnt <= cap - 1

\* s is in the current array until an add grows it; what the fold reads through is valid
SlotGen ==
  /\ s.gen <= gen /\ v.gen <= gen
  /\ pc \in {"add"} => s.gen = gen
  /\ pc = "fold" => (v.direct \/ v.gen = gen)

\* every grow of this loop came with a group the loop added
GenBound == gen <= cnt - Cardinality(pre)

\* the state only a mutant's step makes
MutantOnly == pc = "next" => Mutant = "skip_new"

IndInv ==
  /\ TypeOK
  /\ MutantOnly
  /\ GenBound
  /\ NoStaleSlotRead
  /\ FoldCorrect
  /\ EntryIdx
  /\ HasGroups
  /\ GroupCounts
  /\ CountIsGroups
  /\ LoadFactor
  /\ SlotGen

\* witnesses
NotGrewInPartials == ~grew
NotFoldExisting == ~foldOld
NotDoneAfterGrow == ~(pc = "done" /\ grew)

CInit == /\ N = 3 /\ NK = 2 /\ Fix = "added" /\ Mutant = "none"
=============================================================================
