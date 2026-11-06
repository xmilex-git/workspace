------------------------------ MODULE DescTree ------------------------------
(* CBRD-27848 under concurrent structure changes.  A descending index range scan whose start bound merges keys
   (several keys compare equal to it) walks the leaf chain to the left with a conditional latch
   (btree_range_scan_descending_fix_prev_leaf).  When that latch fails before any key was read, the special case
   re-positions the scan.  Fix chooses how:
     "code"     develop 21c6e635d: clone the bound into cur_key, search C then P with equal_as = DB_EQ
     "restart"  the decided design: wait for P (unconditional fix), release it, restart from the root
   Other transactions run DML and vacuum one operation at a time, each under write latches on the leaves it
   changes: insert a key (invisible to the scan's snapshot), vacuum such a key, split a leaf into a free page,
   merge a leaf into its left neighbour and free it.  A freed page keeps its stale content and can be reused by a
   later split.  Keys of the scan's snapshot (Vis) stay in the index throughout: MVCC keeps a deleted key's record
   until vacuum, and vacuum removes only keys no snapshot sees.  Fence marks a leaf's lower fence (slot 1). *)
EXTENDS Naturals, Sequences, FiniteSets

CONSTANTS Layout,     \* "base" | "scale" | "trace" (six one-key leaves, for trace validation)
          Fenced,     \* a split gives the right leaf a lower fence (btree_split_node)
          Incl,       \* inclusive start bound (b <= X) or exclusive (b < X)
          Fix,        \* "code" | "restart"
          Mutant,     \* "none" | "noclear" (CBRD-27851 undone) | "nolinkcheck" (P's freed/linked checks dropped)
          MaxWrites   \* operations other transactions perform

Fence == 0
Clone == 100    \* cur_key holds a clone of the start bound (Fix = "code")
NoKey == 101
Pages == 1..(IF Layout = "trace" THEN 7 ELSE 4)
Cap == 3        \* keys per leaf

Vis == CASE Layout = "base" -> {1, 2, 4, 5, 7, 8}       \* the scan's snapshot sees these
          [] Layout = "scale" -> {1, 2, 4, 5, 6, 8, 9}
          [] OTHER -> {1, 2, 3, 4, 5, 7}
Inv == CASE Layout = "base" -> {3, 6, 9}                \* keys DML may insert (invisible)
          [] Layout = "scale" -> {3, 7, 10}
          [] OTHER -> {6, 8}
Eq == CASE Layout = "base" -> {4, 5}                    \* keys that compare equal to X
         [] Layout = "scale" -> {4, 5, 6}
         [] OTHER -> {7}
Filtered == IF Layout = "scale" THEN {2} ELSE {}
NV == CASE Layout = "base" -> 9 [] Layout = "scale" -> 10 [] OTHER -> 8
MinEq == CHOOSE k \in Eq : \A j \in Eq : k <= j
MaxEq == CHOOSE k \in Eq : \A j \in Eq : j <= k
\* the start's threshold: the scan returns keys below it (b < X: below the first equal key; b <= X: up to the last)
T == IF Incl THEN MaxEq + 1 ELSE MinEq
W == {v \in Vis : v < T /\ v \notin Filtered}

RECURSIVE DescSeq(_)
DescSeq(S) == IF S = {} THEN << >>
              ELSE LET m == CHOOSE k \in S : \A j \in S : j <= k IN <<m>> \o DescSeq(S \ {m})
Expected == DescSeq(W)

F(seq) == (IF Fenced THEN <<Fence>> ELSE << >>) \o seq
InitContent == IF Layout = "trace"
               THEN [p \in Pages |-> CASE p = 1 -> <<1>> [] p = 2 -> F(<<2>>) [] p = 3 -> F(<<3>>)
                                       [] p = 4 -> F(<<4>>) [] p = 5 -> F(<<5>>) [] p = 6 -> F(<<7>>)
                                       [] OTHER -> << >>]
               ELSE IF Layout = "base"
               THEN [p \in Pages |-> CASE p = 1 -> <<1, 2>>
                                       [] p = 2 -> (IF Fenced THEN <<Fence>> ELSE << >>) \o <<4, 5>>
                                       [] p = 3 -> (IF Fenced THEN <<Fence>> ELSE << >>) \o <<7, 8>>
                                       [] OTHER -> << >>]
               ELSE [p \in Pages |-> CASE p = 1 -> <<1, 2>>
                                       [] p = 2 -> (IF Fenced THEN <<Fence>> ELSE << >>) \o <<4, 5, 6>>
                                       [] p = 3 -> (IF Fenced THEN <<Fence>> ELSE << >>) \o <<8, 9>>
                                       [] OTHER -> << >>]

VARIABLES chain, content,              \* the leaf chain (page ids left to right) and every page's records
          wop, wl, writes,             \* the writer's pending operation, its write latches, operations done
          pc, C, s, P, curKey, started, force, result, err,
          gg, events                   \* ghosts: the refinement's position in the gap; witnesses
vars == <<chain, content, wop, wl, writes, pc, C, s, P, curKey, started, force, result, err, gg, events>>

InChain(p) == \E i \in 1..Len(chain) : chain[i] = p
Idx(p) == IF InChain(p) THEN CHOOSE i \in 1..Len(chain) : chain[i] = p ELSE 0
Keys(seq) == {seq[t] : t \in 1..Len(seq)} \ {Fence}
AllKeys == UNION {Keys(content[chain[i]]) : i \in 1..Len(chain)}
SlotsOf(p) == 0..Len(content[p])
\* record values at or below / above position (p, sl) in chain order
AtOrBelow(p, sl) == UNION {Keys(content[chain[i]]) : i \in 1..(Idx(p) - 1)}
                    \cup ({content[p][t] : t \in 1..sl} \ {Fence})
Above(p, sl) == UNION {Keys(content[chain[i]]) : i \in (Idx(p) + 1)..Len(chain)}
                \cup ({content[p][t] : t \in (sl + 1)..Len(content[p])} \ {Fence})
Max(S) == CHOOSE m \in S : \A j \in S : j <= m
GVal(p, sl) == IF AtOrBelow(p, sl) = {} THEN 0 ELSE Max(AtOrBelow(p, sl))
\* btree_locate_key / btree_locate_key_from_saved_leaf from the root: stands just below Tv (records below Tv at or
\* below the position, the rest above); separators equal to a key make several positions possible
Below(Tv) == {<<p, sl>> \in {<<q, t>> : q \in {chain[i] : i \in 1..Len(chain)}, t \in 0..(Cap + 1)} :
                sl \in SlotsOf(p) /\ (\A v \in AtOrBelow(p, sl) : v < Tv) /\ (\A v \in Above(p, sl) : v >= Tv)}

\* within one page
LocalSlots(p, Tv) == {sl \in SlotsOf(p) :
                        /\ \A t \in 1..sl : content[p][t] = Fence \/ content[p][t] < Tv
                        /\ \A t \in (sl + 1)..Len(content[p]) : content[p][t] = Fence \/ content[p][t] >= Tv}
HasLess(p, Tv) == \E v \in Keys(content[p]) : v < Tv
SlotOfKey(p, v) == CHOOSE t \in 1..Len(content[p]) : content[p][t] = v
Restarted == {<<0, 0>>}
\* fix_prev_leaf's normal path with P and C latched: btree_leaf_is_key_between_min_max, btree_search_leaf_page on
\* cur_key in C, then in P (30238-30365)
NormalSearch(c, p, k) ==
  IF k \in Keys(content[c])
  THEN IF SlotOfKey(c, k) > 1 THEN {<<c, SlotOfKey(c, k) - 1>>} ELSE {<<p, Len(content[p])>>}
  ELSE IF Keys(content[c]) = {} THEN Restarted
  ELSE IF HasLess(c, k) /\ \E v \in Keys(content[c]) : v >= k
       THEN {<<c, sl>> : sl \in LocalSlots(c, k)}
  ELSE IF ~HasLess(c, k)
       THEN IF HasLess(p, k) THEN {<<p, sl>> : sl \in LocalSlots(p, k)} ELSE Restarted
  ELSE Restarted
\* Fix = "code": the clone of X searched with DB_EQ: any key equal to X may be the one found
EqSlots(p) == {t \in 1..Len(content[p]) : content[p][t] \in Eq}
CodeSearch(c, p) ==
  IF EqSlots(c) # {}
  THEN {IF t > 1 THEN <<c, t - 1>> ELSE <<p, Len(content[p])>> : t \in EqSlots(c)}
  ELSE IF Keys(content[c]) # {} /\ \A v \in Keys(content[c]) : v > MaxEq
       THEN IF EqSlots(p) # {} THEN {<<p, t - 1>> : t \in EqSlots(p)}
            ELSE IF HasLess(p, MinEq) THEN {<<p, sl>> : sl \in LocalSlots(p, MinEq)} ELSE Restarted
  ELSE Restarted

\* pages the scan holds or waits for (page latch waiters are granted in order)
ScanPages == CASE pc = "scan" -> {C} [] pc = "gap" -> {P} [] pc = "gapc" -> {P, C} [] OTHER -> {}

TypeOK ==
  /\ chain \in Seq(Pages) /\ content \in [Pages -> Seq(0..NV)]
  /\ wl \in SUBSET Pages /\ writes \in 0..MaxWrites
  /\ pc \in {"start", "scan", "gap0", "gap", "gapc", "resume", "done"}
  /\ C \in Pages /\ P \in Pages /\ s \in 0..(Cap + 1)
  /\ curKey \in (1..NV) \cup {Clone, NoKey}
  /\ started \in BOOLEAN /\ force \in BOOLEAN /\ err \in BOOLEAN
  /\ result \in Seq(1..NV)

NoOp == [kind |-> "none", p |-> 1, q |-> 1, v |-> 0, k |-> 0]

Init ==
  /\ chain = (IF Layout = "trace" THEN <<1, 2, 3, 4, 5, 6>> ELSE <<1, 2, 3>>) /\ content = InitContent
  /\ wop = NoOp /\ wl = {} /\ writes = 0
  /\ pc = "start" /\ C = 1 /\ s = 0 /\ P = 1 /\ curKey = NoKey
  /\ started = FALSE /\ force = FALSE /\ result = << >> /\ err = FALSE
  /\ gg = 0 /\ events = {}

WriterVars == <<chain, content, wop, wl, writes>>
ScanVars == <<pc, C, s, P, curKey, started, force, result, err, gg>>

\* ---------------- the scan ----------------

\* btree_range_scan_start: clears the restart request (CBRD-27851) and locates the start from the root
Start ==
  /\ pc = "start"
  /\ IF Mutant = "noclear" /\ force
       THEN UNCHANGED <<pc, C, s, force>>       \* advance_over_filtered_keys sees the request and gives up again
       ELSE \E pos \in Below(T) :
              /\ pos[1] \notin wl
              /\ C' = pos[1] /\ s' = pos[2] /\ force' = FALSE /\ pc' = "scan"
  /\ UNCHANGED <<P, curKey, started, result, err, gg, events>> /\ UNCHANGED WriterVars

\* btree_range_scan_resume: locates cur_key (a key read before) from the root; it is consumed
Resume ==
  /\ pc = "resume"
  /\ \E pos \in Below(curKey) :
       /\ pos[1] \notin wl
       /\ C' = pos[1] /\ s' = pos[2] /\ force' = FALSE /\ pc' = "scan"
  /\ UNCHANGED <<P, curKey, started, result, err, gg>> /\ UNCHANGED WriterVars
  /\ events' = events \cup {"resume"}

\* advance_over_filtered_keys reads the record at slot s of the latched leaf C; a fence is skipped.  A key that
\* passes the key filter sets is_scan_started; it is returned when the snapshot sees it.
ScanRecord ==
  /\ pc = "scan" /\ s >= 1
  /\ s' = s - 1
  /\ LET r == content[C][s] IN
       IF r = Fence THEN UNCHANGED <<curKey, started, result>>
       ELSE /\ curKey' = r
            /\ started' = (started \/ r \notin Filtered)
            \* the descending range check looks at the opposite limit only (none here): the start's position is
            \* what keeps keys at or above the bound out
            /\ result' = IF r \in Vis /\ r \notin Filtered THEN Append(result, r) ELSE result
  /\ UNCHANGED <<pc, C, P, force, err, gg, events>> /\ UNCHANGED WriterVars

ScanEnd ==
  /\ pc = "scan" /\ s = 0 /\ Idx(C) = 1
  /\ pc' = "done"
  /\ UNCHANGED <<C, s, P, curKey, started, force, result, err, gg, events>> /\ UNCHANGED WriterVars

\* fix_prev_leaf: the conditional latch of the left leaf succeeds; C is released
PrevLatched ==
  /\ pc = "scan" /\ s = 0 /\ Idx(C) > 1 /\ chain[Idx(C) - 1] \notin wl
  /\ C' = chain[Idx(C) - 1] /\ s' = Len(content[chain[Idx(C) - 1]])
  /\ UNCHANGED <<pc, P, curKey, started, force, result, err, gg, events>> /\ UNCHANGED WriterVars

\* the conditional latch fails: C is released (30176-30180); nothing is latched until P is requested
PrevLatchFails ==
  /\ pc = "scan" /\ s = 0 /\ Idx(C) > 1 /\ chain[Idx(C) - 1] \in wl
  /\ pc' = "gap0" /\ P' = chain[Idx(C) - 1] /\ gg' = GVal(C, 0)
  /\ UNCHANGED <<C, s, curKey, started, force, result, err, events>> /\ UNCHANGED WriterVars

\* P (from C's prev link, read while C was latched) is requested unconditionally (30182)
GapRequestP ==
  /\ pc = "gap0" /\ pc' = "gap"
  /\ UNCHANGED <<C, s, P, curKey, started, force, result, err, gg, events>> /\ UNCHANGED WriterVars

\* the restart request the caller acts on: btree_range_scan_resume once started, btree_range_scan_start before
Restart ==
  /\ force' = TRUE
  /\ IF started THEN pc' = "resume" /\ UNCHANGED curKey
                ELSE pc' = "start" /\ curKey' = NoKey     \* the start branch clears cur_key

Linked == InChain(P) /\ Idx(P) < Len(chain) /\ chain[Idx(P) + 1] = C

\* the unconditional fix of P returns (30182).  P freed, reused elsewhere or unlinked from C: restart (30188-30210).
\* The decided design restarts here too when no key was read (P released); otherwise C is fixed next, P held.
GapFixP ==
  /\ pc = "gap" /\ P \notin wl
  /\ IF ~Linked /\ Mutant # "nolinkcheck"
       THEN Restart /\ events' = events \cup {"gaprestart"}
     ELSE IF Fix = "restart" /\ ~started /\ curKey = NoKey
       THEN Restart /\ events' = events \cup {"special"}
     ELSE pc' = "gapc" /\ UNCHANGED <<curKey, force, events>>
  /\ UNCHANGED <<C, s, P, started, result, err, gg>> /\ UNCHANGED WriterVars

\* C is latched too and searched (30214-30365)
GapLinked ==
  /\ pc = "gapc" /\ C \notin wl
  /\ IF Fix = "code" /\ ~started /\ curKey = NoKey
       THEN /\ curKey' = Clone
            /\ events' = events \cup {"special"}
            /\ \E pos \in CodeSearch(C, P) :
                 IF pos = <<0, 0>> THEN /\ force' = TRUE /\ pc' = "start" /\ UNCHANGED <<C, s>>
                 ELSE /\ C' = pos[1] /\ s' = pos[2] /\ pc' = "scan" /\ UNCHANGED force
            /\ UNCHANGED err
     ELSE IF curKey = Clone
       THEN \* the clone is compared without its bound: ER_TP_CANT_COERCE (release), assert (debug)
            /\ err' = TRUE /\ pc' = "done"
            /\ UNCHANGED <<C, s, curKey, force, events>>
     ELSE /\ \E pos \in NormalSearch(C, P, curKey) :
               IF pos = <<0, 0>> THEN Restart /\ UNCHANGED <<C, s>>
               ELSE /\ C' = pos[1] /\ s' = pos[2] /\ pc' = "scan" /\ UNCHANGED <<curKey, force>>
          /\ UNCHANGED <<err, events>>
  /\ UNCHANGED <<P, started, result, gg>> /\ UNCHANGED WriterVars

\* ---------------- other transactions ----------------

\* an operation and the leaves it write-latches: the leaves whose records or links it changes
InsOps == {[kind |-> "ins", p |-> p, q |-> p, v |-> v, k |-> sl] :
             v \in Inv \ AllKeys, p \in {chain[i] : i \in 1..Len(chain)}, sl \in 0..Cap}
VacOps == {[kind |-> "vac", p |-> p, q |-> p, v |-> v, k |-> 0] :
             v \in Inv, p \in {chain[i] : i \in 1..Len(chain)}}
SplitOps == {[kind |-> "split", p |-> p, q |-> q, v |-> 0, k |-> k] :
               p \in {chain[i] : i \in 1..Len(chain)}, q \in Pages, k \in 1..(Cap + 1)}
MergeOps == {[kind |-> "merge", p |-> p, q |-> q, v |-> 0, k |-> 0] :
               p \in {chain[i] : i \in 1..Len(chain)}, q \in Pages}

NextOf(p) == IF Idx(p) < Len(chain) THEN {chain[Idx(p) + 1]} ELSE {}
Valid(op) ==
  CASE op.kind = "ins" ->
         /\ op.k \in SlotsOf(op.p)
         /\ ~(op.k = 0 /\ Len(content[op.p]) > 0 /\ content[op.p][1] = Fence)
         /\ Cardinality(Keys(content[op.p])) < Cap
         /\ \A v \in AtOrBelow(op.p, op.k) : v < op.v
         /\ \A v \in Above(op.p, op.k) : v > op.v
    [] op.kind = "vac" -> op.v \in Keys(content[op.p])
    [] op.kind = "split" ->
         /\ ~InChain(op.q)
         /\ op.k < Len(content[op.p])
         /\ Keys(SubSeq(content[op.p], 1, op.k)) # {}
    [] op.kind = "merge" ->
         /\ InChain(op.q) /\ Idx(op.q) = Idx(op.p) + 1
         /\ Cardinality(Keys(content[op.p])) + Cardinality(Keys(content[op.q])) <= Cap
    [] OTHER -> FALSE
LatchSet(op) ==
  CASE op.kind \in {"ins", "vac"} -> {op.p}
    [] op.kind = "split" -> {op.p, op.q} \cup NextOf(op.p)
    [] op.kind = "merge" -> {op.p, op.q} \cup NextOf(op.q)
    [] OTHER -> {}

WriterLatch ==
  /\ wop = NoOp /\ writes < MaxWrites
  /\ \E op \in InsOps \cup VacOps \cup SplitOps \cup MergeOps :
       /\ Valid(op)
       /\ LatchSet(op) \cap ScanPages = {}
       /\ wop' = op /\ wl' = LatchSet(op)
  /\ writes' = writes + 1
  /\ UNCHANGED <<chain, content>> /\ UNCHANGED ScanVars /\ UNCHANGED events

Insert(seq, k, v) == SubSeq(seq, 1, k) \o <<v>> \o SubSeq(seq, k + 1, Len(seq))
Remove(seq, v) == LET t == CHOOSE t \in 1..Len(seq) : seq[t] = v
                  IN SubSeq(seq, 1, t - 1) \o SubSeq(seq, t + 1, Len(seq))
KeysOnly(seq) == SelectSeq(seq, LAMBDA r : r # Fence)

WriterApply ==
  /\ wop # NoOp
  /\ CASE wop.kind = "ins" ->
            /\ content' = [content EXCEPT ![wop.p] = Insert(@, wop.k, wop.v)]
            /\ UNCHANGED chain
       [] wop.kind = "vac" ->
            /\ content' = [content EXCEPT ![wop.p] = Remove(@, wop.v)]
            /\ UNCHANGED chain
       [] wop.kind = "split" ->
            /\ content' = [content EXCEPT ![wop.p] = SubSeq(@, 1, wop.k),
                                          ![wop.q] = (IF Fenced THEN <<Fence>> ELSE << >>)
                                                     \o SubSeq(content[wop.p], wop.k + 1, Len(content[wop.p]))]
            /\ chain' = SubSeq(chain, 1, Idx(wop.p)) \o <<wop.q>> \o SubSeq(chain, Idx(wop.p) + 1, Len(chain))
       [] OTHER ->  \* merge: q's keys move to p, q leaves the chain and keeps its stale records
            /\ content' = [content EXCEPT ![wop.p] = @ \o KeysOnly(content[wop.q])]
            /\ chain' = SubSeq(chain, 1, Idx(wop.q) - 1) \o SubSeq(chain, Idx(wop.q) + 1, Len(chain))
  /\ wop' = NoOp /\ wl' = {}
  /\ events' = events \cup (IF pc \in {"gap0", "gap", "gapc"} THEN {wop.kind \o "-in-gap"} ELSE {})
  /\ UNCHANGED writes /\ UNCHANGED ScanVars

Terminated == pc = "done" /\ wop = NoOp /\ UNCHANGED vars

ScanStep == Start \/ Resume \/ ScanRecord \/ ScanEnd \/ PrevLatched \/ PrevLatchFails \/ GapRequestP \/ GapFixP
            \/ GapLinked
Next == ScanStep \/ WriterLatch \/ WriterApply \/ Terminated

Spec == Init /\ [][Next]_vars /\ WF_vars(ScanStep) /\ WF_vars(WriterApply)

---------------------------------------------------------------------------
\* C1: the scan returns exactly the visible in-range keys, in descending order, whatever the latch timing and the
\* concurrent structure changes
IsPrefix(a, b) == Len(a) <= Len(b) /\ SubSeq(b, 1, Len(a)) = a
ResultIsPrefix == IsPrefix(result, Expected)
CompleteAnswer == (pc = "done" /\ ~err) => result = Expected
\* C2: the start bound is never compared without its bound (no ER_TP_CANT_COERCE, no assert)
NoBoundlessCompare == ~err
\* C3: the scan ends (other transactions perform MaxWrites operations)
ScanEnds == <>(pc = "done")

\* refinement into DescScan: the value of the next record to read
Abs == INSTANCE DescScan WITH
         N <- NV,
         W <- W,
         Top <- T - 1,
         pc <- CASE pc = "start" -> "start" [] pc = "done" -> "done" [] OTHER -> "scan",
         g <- CASE pc = "scan" -> GVal(C, s) [] pc \in {"gap0", "gap", "gapc", "resume"} -> gg [] OTHER -> 0,
         emitted <- {result[i] : i \in 1..Len(result)},
         hasCur <- curKey \in 1..NV,
         cpos <- IF curKey \in 1..NV THEN curKey ELSE 0
AbsSpec == Abs!Spec

\* witnesses
NotEvent(e) == e \notin events
NotSpecial == NotEvent("special")
NotSplitInGap == NotEvent("split-in-gap")
NotMergeInGap == NotEvent("merge-in-gap")
NotGapRestartAfterStart == ~("gaprestart" \in events /\ "resume" \in events)
NotAnsweredAfterSpecial == ~(pc = "done" /\ "special" \in events /\ result # << >>)

IndInv == TypeOK /\ ResultIsPrefix /\ NoBoundlessCompare /\ CompleteAnswer
=============================================================================
