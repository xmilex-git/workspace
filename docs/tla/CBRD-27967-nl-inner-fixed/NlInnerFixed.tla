----------------------------- MODULE NlInnerFixed -----------------------------
(* A three-level nested-loop chain: an outer index scan (leaf L, then the row's heap page Hc), a middle
   sequential heap scan over the chain M1 M2, and the innermost sequential heap scan over the chain B1 B2
   (B1 its header page, which holds rows too). R is the query's thread; W a writer, V vacuum and S an
   in-statement change by R's own transaction (an SP the statement calls).
   The design: the innermost heap scan is a fixed scan (its page stays latched between its rows, and
   scan_reset_scan_block releases it when the scan stops early), a middle heap scan is a cached scan
   (it copies the page, releases the latch, and reads the remaining rows of the page from the copy; a
   reset drops the copy). Mutants re-enable develop's choices and each missing step. *)
EXTENDS Naturals, FiniteSets

CONSTANTS NO, R1, R2, MR1, MR2, EarlyStop, HcLow, WProg, Mutant
\* apalache-type: NO Int
\* apalache-type: R1 Int
\* apalache-type: R2 Int
\* apalache-type: MR1 Int
\* apalache-type: MR2 Int
\* apalache-type: EarlyStop Bool
\* apalache-type: HcLow Bool
\* apalache-type: WProg Str
\* apalache-type: Mutant Str

VARIABLES lx, ls, rpc, orow, mr, mp, ip, rr, held, refix, cvp, cpass, mpass, wpc, vpc, ifix, mfix,
          stale, seen
\* apalache-type: lx Str -> Str
\* apalache-type: ls Str -> Set(Str)
\* apalache-type: rpc Str
\* apalache-type: orow Int
\* apalache-type: mr Int
\* apalache-type: mp Int
\* apalache-type: ip Int
\* apalache-type: rr Int
\* apalache-type: held Set(Str)
\* apalache-type: refix Set(Str)
\* apalache-type: cvp Int
\* apalache-type: cpass Int
\* apalache-type: mpass Int
\* apalache-type: wpc Int
\* apalache-type: vpc Int
\* apalache-type: ifix Int
\* apalache-type: mfix Int
\* apalache-type: stale Bool
\* apalache-type: seen Set(Str)

vars == <<lx, ls, rpc, orow, mr, mp, ip, rr, held, refix, cvp, cpass, mpass, wpc, vpc, ifix, mfix,
          stale, seen>>

Pages == {"L", "Hc", "M1", "M2", "B1", "B2"}
Threads == {"R", "W", "V"}
IFixed == Mutant # "inner-unfixed"
MCached == Mutant # "middle-unfixed"
Ordered == Mutant \notin {"no-ordered", "no-reset-no-ordered"}
\* develop's scan_reset_scan_block keeps a page an early stop left held ("no-reset-unfix" alone is the code
\* with only the fixed-scan selection widened)
ResetUnfix == Mutant \notin {"no-reset-unfix", "no-reset-no-ordered"}
ResetDrop == Mutant # "keep-copy"

\* pgbuf_ordered_fix ranks heap pages by (hfid, pageid); the outer heap's place among the others is either way
Rank(p) == IF p = "Hc" THEN (IF HcLow THEN 1 ELSE 6) ELSE IF p = "M1" THEN 2 ELSE IF p = "M2" THEN 3
           ELSE IF p = "B1" THEN 4 ELSE 5
Page(i) == IF i = 1 THEN "B1" ELSE "B2"
\* the rows of an innermost page: the header page B1 may hold none
Rows(i) == IF i = 1 THEN R1 ELSE R2
\* the middle chain: its header page M1, then M2
MPage(i) == IF i = 1 THEN "M1" ELSE "M2"
MRows(i) == IF i = 1 THEN MR1 ELSE MR2

\* @typeAlias: op = { a: Str, p: Str, m: Str };
\* @type: (Str, Str) => $op;
Acq(p, m) == [a |-> "acq", p |-> p, m |-> m]
\* @type: (Str) => $op;
Rel(p) == [a |-> "rel", p |-> p, m |-> "-"]

\* W: an UPDATE of an inner row (heap page, then its index entry while the heap page is still held: the
\* worst order a DML could take), a relocation over two inner pages in rank order, a middle and an outer
\* row update. "btree-holds-heap" requests a heap page while holding the leaf, an edge the code never
\* takes (btree_range_scan unfixes its leaf before returning, btree.c:30911; btree code unfixes before it
\* reads the heap, btree.c:26538).
WLen == IF WProg = "btree-holds-heap" THEN 4 ELSE 12
\* @type: (Int) => $op;
WOp(i) ==
  IF WProg = "btree-holds-heap"
  THEN IF i = 1 THEN Acq("L", "X") ELSE IF i = 2 THEN Acq("B2", "X") ELSE IF i = 3 THEN Rel("B2") ELSE Rel("L")
  ELSE IF i = 1 THEN Acq("B2", "X") ELSE IF i = 2 THEN Acq("L", "X") ELSE IF i = 3 THEN Rel("L")
  ELSE IF i = 4 THEN Rel("B2") ELSE IF i = 5 THEN Acq("B1", "X") ELSE IF i = 6 THEN Acq("B2", "X")
  ELSE IF i = 7 THEN Rel("B2") ELSE IF i = 8 THEN Rel("B1") ELSE IF i = 9 THEN Acq("M1", "X")
  ELSE IF i = 10 THEN Rel("M1") ELSE IF i = 11 THEN Acq("Hc", "X") ELSE Rel("Hc")
\* @type: (Int) => Set(Str);
WHolds(i) ==
  IF WProg = "btree-holds-heap"
  THEN (IF i = 2 THEN {"L"} ELSE IF i = 3 THEN {"L", "B2"} ELSE IF i = 4 THEN {"L"} ELSE {})
  ELSE IF i = 2 \/ i = 4 THEN {"B2"} ELSE IF i = 3 THEN {"B2", "L"} ELSE IF i = 6 \/ i = 8 THEN {"B1"}
  ELSE IF i = 7 THEN {"B1", "B2"} ELSE IF i = 10 THEN {"M1"} ELSE IF i = 12 THEN {"Hc"} ELSE {}

\* V: vacuum, one page at a time (the index first, then the heap pages)
VLen == 12
\* @type: (Int) => $op;
VOp(i) ==
  IF i = 1 THEN Acq("L", "X") ELSE IF i = 2 THEN Rel("L") ELSE IF i = 3 THEN Acq("M1", "X")
  ELSE IF i = 4 THEN Rel("M1") ELSE IF i = 5 THEN Acq("M2", "X") ELSE IF i = 6 THEN Rel("M2")
  ELSE IF i = 7 THEN Acq("B1", "X") ELSE IF i = 8 THEN Rel("B1")
  ELSE IF i = 9 THEN Acq("B2", "X") ELSE IF i = 10 THEN Rel("B2") ELSE IF i = 11 THEN Acq("Hc", "X") ELSE Rel("Hc")
\* @type: (Int) => Set(Str);
VHolds(i) ==
  IF i = 2 THEN {"L"} ELSE IF i = 4 THEN {"M1"} ELSE IF i = 6 THEN {"M2"} ELSE IF i = 8 THEN {"B1"}
  ELSE IF i = 10 THEN {"B2"} ELSE IF i = 12 THEN {"Hc"} ELSE {}

CanS(p) == lx[p] = "none"
CanX(t, p) == lx[p] = "none" /\ ls[p] \subseteq {t}
Seen(e, c) == IF c THEN {e} ELSE {}
\* @type: (Set(Str)) => (Str -> Set(Str));
Drop(ps) == [p \in Pages |-> IF p \in ps THEN ls[p] \ {"R"} ELSE ls[p]]

(***************************************************************************)
(* R: the query                                                            *)
(***************************************************************************)
\* the innermost pages R holds above a rank: pgbuf_ordered_fix unfixes them when it would wait for a
\* lower-ranked page, and refixes them after
Above(r) == {p \in held : Rank(p) > r}
\* R's request for a heap page p of another level: yield the pages above it when p is busy
Yields(p) == Ordered /\ Above(Rank(p)) # {} /\ ~CanS(p)
YieldTo(p) ==
  /\ ls' = Drop(Above(Rank(p))) /\ held' = held \ Above(Rank(p)) /\ refix' = refix \cup Above(Rank(p))
  /\ seen' = seen \cup {"ordered-yield"}

\* the outer index scan: btree_range_scan fixes the leaf, collects OIDs and unfixes it before returning
RLeaf ==
  /\ rpc = "leaf" /\ CanS("L")
  /\ rpc' = "lookup"
  /\ seen' = seen \cup Seen("level-move-held", held # {})
  /\ UNCHANGED <<lx, ls, orow, mr, mp, ip, rr, held, refix, cvp, cpass, mpass, wpc, vpc, ifix, mfix,
                 stale>>
\* the outer row's heap page (fix, read, unfix)
RLookupYield ==
  /\ rpc = "lookup" /\ Yields("Hc") /\ YieldTo("Hc")
  /\ UNCHANGED <<lx, rpc, orow, mr, mp, ip, rr, cvp, cpass, mpass, wpc, vpc, ifix, mfix, stale>>
RLookup ==
  /\ rpc = "lookup" /\ CanS("Hc")
  /\ IF refix # {}
     THEN rpc' = "refix" /\ ls' = [ls EXCEPT !["Hc"] = @ \cup {"R"}]
     ELSE rpc' = "mstart" /\ ls' = ls
  /\ UNCHANGED <<lx, orow, mr, mp, ip, rr, held, refix, cvp, cpass, mpass, wpc, vpc, ifix, mfix,
                 stale, seen>>
\* pgbuf_ordered_fix refixes the yielded pages, lowest rank first, while it holds the page it was asked
\* for (Hc in "refix", M1 in "mrefix"); that page is released once the yielded pages are back
\* @type: (Str) => Str;
RefixHolder(pc) == IF pc = "refix" THEN "Hc" ELSE MPage(mp)
RRefix ==
  /\ rpc \in {"refix", "mrefix"} /\ \E p \in refix :
       /\ \A q \in refix : Rank(p) <= Rank(q)
       /\ CanS(p) /\ held' = held \cup {p} /\ refix' = refix \ {p}
       /\ ls' = [x \in Pages |-> IF x = p THEN ls[x] \cup {"R"}
                                ELSE IF refix = {p} /\ x = RefixHolder(rpc) THEN ls[x] \ {"R"} ELSE ls[x]]
       /\ rpc' = IF refix # {p} THEN rpc ELSE IF rpc = "refix" THEN "mstart" ELSE IF mr = 0 THEN "mrow" ELSE "istart"
  /\ UNCHANGED <<lx, orow, mr, mp, ip, rr, cvp, cpass, mpass, wpc, vpc, ifix, mfix, stale,
                 seen>>

\* the middle scan restarts for the outer row (scan_reset_scan_block): the design drops the page copy
RMStart ==
  /\ rpc = "mstart"
  /\ rpc' = "mrow" /\ mr' = 0 /\ mp' = 1 /\ mpass' = mpass + 1 /\ mfix' = 0
  /\ cvp' = IF ResetDrop THEN 0 ELSE cvp
  /\ UNCHANGED <<lx, ls, orow, ip, rr, held, refix, cpass, wpc, vpc, ifix, stale, seen>>
\* the middle page R is about to fix: the current page for a row it has no copy of, or M2 when M1 is read
MWant == IF mr < MRows(mp) /\ ~(MCached /\ cvp = mp) THEN MPage(mp)
         ELSE IF mp = 1 /\ mr = MRows(1) THEN "M2" ELSE "none"
\* one middle row: from the copy when the page is copied, else fix the page (cached: copy it, release the latch;
\* develop: fix, read the row, unfix)
RMRowYield ==
  /\ rpc = "mrow" /\ MWant # "none" /\ Yields(MWant) /\ YieldTo(MWant)
  /\ UNCHANGED <<lx, rpc, orow, mr, mp, ip, rr, cvp, cpass, mpass, wpc, vpc, ifix, mfix, stale>>
RMRow ==
  /\ rpc = "mrow" /\ mr < MRows(mp)
  /\ IF MCached /\ cvp = mp
     THEN /\ stale' = (stale \/ cpass # mpass)
          /\ UNCHANGED <<cvp, cpass, mfix>>
     ELSE /\ CanS(MPage(mp)) /\ mfix' = mfix + 1
          /\ cvp' = (IF MCached THEN mp ELSE 0) /\ cpass' = mpass /\ stale' = stale
  /\ mr' = mr + 1
  /\ IF refix # {} THEN rpc' = "mrefix" /\ ls' = [ls EXCEPT ![MPage(mp)] = @ \cup {"R"}] ELSE rpc' = "istart" /\ ls' = ls
  /\ seen' = seen \cup Seen("level-move-held", held # {}) \cup Seen("copy-read", MCached /\ cvp = mp)
  /\ UNCHANGED <<lx, orow, mp, ip, rr, held, refix, mpass, wpc, vpc, ifix>>
\* heap_next to the middle chain's next page: fix M2 (cached: copied only when it holds a row, as
\* heap_next_internal copies a page on its way to a slot), release it
RMNextPage ==
  /\ rpc = "mrow" /\ mp = 1 /\ mr = MRows(1)
  /\ CanS("M2") /\ mfix' = mfix + 1
  /\ cvp' = (IF MCached /\ MR2 > 0 THEN 2 ELSE cvp) /\ cpass' = (IF MCached /\ MR2 > 0 THEN mpass ELSE cpass)
  /\ mp' = 2 /\ mr' = 0
  /\ IF refix # {} THEN rpc' = "mrefix" /\ ls' = [ls EXCEPT !["M2"] = @ \cup {"R"}] ELSE rpc' = "mrow" /\ ls' = ls
  /\ UNCHANGED <<lx, orow, ip, rr, held, refix, mpass, wpc, vpc, ifix, stale, seen>>
\* the middle chain's end: on to the next outer row
RMEnd ==
  /\ rpc = "mrow" /\ mp = 2 /\ mr = MRows(2)
  /\ rpc' = "onext"
  /\ UNCHANGED <<lx, ls, orow, mr, mp, ip, rr, held, refix, cvp, cpass, mpass, wpc, vpc, ifix, mfix, stale, seen>>

\* the innermost scan restarts (heap_next from a null OID): the header page B1 first; a page still held
\* is the old watcher, released once B1 is fixed (or first, when B1 is busy and ranks below it)
RIStartYield ==
  /\ rpc = "istart" /\ IFixed /\ "B1" \notin held /\ Yields("B1")
  /\ ls' = Drop(Above(Rank("B1"))) /\ held' = held \ Above(Rank("B1"))
  /\ seen' = seen \cup {"ordered-yield"}
  /\ UNCHANGED <<lx, rpc, orow, mr, mp, ip, rr, refix, cvp, cpass, mpass, wpc, vpc, ifix, mfix, stale>>
RIStart ==
  /\ rpc = "istart"
  /\ IF IFixed
     THEN \/ "B1" \in held /\ ls' = Drop(held \ {"B1"}) /\ held' = {"B1"} /\ ifix' = 0
          \/ /\ "B1" \notin held /\ CanS("B1")
             /\ ls' = [p \in Pages |-> IF p = "B1" THEN ls[p] \cup {"R"} ELSE IF p \in held THEN ls[p] \ {"R"}
                                       ELSE ls[p]]
             /\ held' = {"B1"} /\ ifix' = 1
     ELSE ls' = ls /\ held' = held /\ ifix' = 0
  /\ rpc' = "inner" /\ ip' = 1 /\ rr' = 0
  /\ seen' = seen \cup Seen("restart-on-held", held # {})
  /\ UNCHANGED <<lx, orow, mr, mp, refix, cvp, cpass, mpass, wpc, vpc, mfix, stale>>
\* one innermost row: under the held latch (fixed), or fix-read-unfix (develop)
RIRow ==
  /\ rpc = "inner" /\ rr < Rows(ip)
  /\ IF IFixed THEN ifix' = ifix ELSE CanS(Page(ip)) /\ ifix' = ifix + 1
  /\ rr' = rr + 1
  /\ UNCHANGED <<lx, ls, rpc, orow, mr, mp, ip, held, refix, cvp, cpass, mpass, wpc, vpc, mfix, stale,
                 seen>>
\* an early stop after a row (a semi join's first match, an outer join's single fetch)
RIEarly ==
  /\ rpc = "inner" /\ EarlyStop /\ rr > 0
  /\ rpc' = "iend" /\ seen' = seen \cup {"early-stop"}
  /\ UNCHANGED <<lx, ls, orow, mr, mp, ip, rr, held, refix, cvp, cpass, mpass, wpc, vpc, ifix, mfix,
                 stale>>
\* heap_next to the chain's next page: the next page is fixed before the held one is released
RINextPage ==
  /\ rpc = "inner" /\ rr = Rows(1) /\ ip = 1
  /\ IF IFixed
     THEN /\ CanS("B2")
          /\ ls' = [p \in Pages |-> IF p = "B2" THEN ls[p] \cup {"R"} ELSE IF p = "B1" THEN ls[p] \ {"R"} ELSE ls[p]]
          /\ held' = {"B2"} /\ ifix' = ifix + 1
     ELSE UNCHANGED <<ls, held, ifix>>
  /\ ip' = 2 /\ rr' = 0
  /\ UNCHANGED <<lx, rpc, orow, mr, mp, refix, cvp, cpass, mpass, wpc, vpc, mfix, stale, seen>>
\* heap_next past the last page: S_END with no page held (heap_file.c:7713)
RIEnd ==
  /\ rpc = "inner" /\ rr = Rows(2) /\ ip = 2
  /\ ls' = Drop(held) /\ held' = {} /\ rpc' = "iend"
  /\ UNCHANGED <<lx, orow, mr, mp, ip, rr, refix, cvp, cpass, mpass, wpc, vpc, ifix, mfix, stale, seen>>
\* back to the middle level: the design's reset releases a page an early stop left held
RIBack ==
  /\ rpc = "iend"
  /\ IF ResetUnfix THEN ls' = Drop(held) /\ held' = {} ELSE UNCHANGED <<ls, held>>
  /\ rpc' = "mrow"
  /\ UNCHANGED <<lx, orow, mr, mp, ip, rr, refix, cvp, cpass, mpass, wpc, vpc, ifix, mfix, stale, seen>>
\* the next outer row, or the end of the query (heap_scancache_end unfixes a held page)
RONext ==
  /\ rpc = "onext"
  /\ orow' = orow + 1
  /\ IF orow + 1 = NO
     THEN rpc' = "done" /\ ls' = Drop(held) /\ held' = {}
     ELSE rpc' = "leaf" /\ UNCHANGED <<ls, held>>
  /\ UNCHANGED <<lx, mr, mp, ip, rr, refix, cvp, cpass, mpass, wpc, vpc, ifix, mfix, stale, seen>>

RAct == RLeaf \/ RLookupYield \/ RLookup \/ RRefix \/ RMStart \/ RMRowYield \/ RMRow \/ RMNextPage \/ RMEnd
        \/ RIStartYield \/ RIStart
        \/ RIRow \/ RIEarly \/ RINextPage \/ RIEnd \/ RIBack \/ RONext

(***************************************************************************)
(* W, V, S                                                                 *)
(***************************************************************************)
\* W and V take write latches only
\* @type: (Str, $op) => Bool;
DoOp(t, o) ==
  IF o.a = "rel"
  THEN /\ lx' = [lx EXCEPT ![o.p] = IF @ = t THEN "none" ELSE @]
       /\ ls' = [ls EXCEPT ![o.p] = @ \ {t}]
  ELSE CanX(t, o.p) /\ lx' = [lx EXCEPT ![o.p] = t] /\ ls' = ls

WStep ==
  /\ wpc <= WLen
  /\ LET o == WOp(wpc) IN DoOp("W", o)
  /\ wpc' = wpc + 1
  /\ seen' = seen \cup Seen("w-waited-r", FALSE)
  /\ UNCHANGED <<rpc, orow, mr, mp, ip, rr, held, refix, cvp, cpass, mpass, vpc, ifix, mfix, stale>>
VStep ==
  /\ vpc <= VLen
  /\ LET o == VOp(vpc) IN DoOp("V", o)
  /\ vpc' = vpc + 1
  /\ UNCHANGED <<rpc, orow, mr, mp, ip, rr, held, refix, cvp, cpass, mpass, wpc, ifix, mfix, stale, seen>>
Done == rpc = "done" /\ wpc > WLen /\ vpc > VLen
Terminating == Done /\ UNCHANGED vars

Init ==
  /\ lx = [p \in Pages |-> "none"] /\ ls = [p \in Pages |-> {}]
  /\ rpc = "leaf" /\ orow = 0 /\ mr = 0 /\ mp = 1 /\ ip = 1 /\ rr = 0 /\ held = {} /\ refix = {}
  /\ cvp = 0 /\ cpass = 0 /\ mpass = 0
  /\ wpc = 1 /\ vpc = 1 /\ ifix = 0 /\ mfix = 0 /\ stale = FALSE /\ seen = {}

Next == RAct \/ WStep \/ VStep \/ Terminating

Spec == Init /\ [][Next]_vars
FairSpec == Spec /\ WF_vars(RAct) /\ WF_vars(WStep) /\ WF_vars(VStep)

(***************************************************************************)
(* Properties                                                              *)
(***************************************************************************)
\* the page R requests in its current step ("none": it is not about to wait)
WantR ==
  IF rpc = "leaf" THEN "L"
  ELSE IF rpc = "lookup" THEN (IF Yields("Hc") THEN "none" ELSE "Hc")
  ELSE IF rpc \in {"refix", "mrefix"} THEN (IF "B1" \in refix THEN "B1" ELSE IF "B2" \in refix THEN "B2" ELSE "none")
  ELSE IF rpc = "mrow" /\ MWant # "none" THEN (IF Yields(MWant) THEN "none" ELSE MWant)
  ELSE IF rpc = "istart" /\ IFixed /\ "B1" \notin held THEN (IF Yields("B1") THEN "none" ELSE "B1")
  ELSE IF rpc = "inner" /\ rr = Rows(1) /\ ip = 1 /\ IFixed THEN "B2"
  ELSE IF rpc = "inner" /\ rr < Rows(ip) /\ ~IFixed THEN Page(ip)
  ELSE "none"
\* @type: (Str) => $op;
WantOp(t) ==
  IF t = "R" THEN Acq(WantR, "S")
  ELSE IF t = "W" THEN (IF wpc <= WLen THEN WOp(wpc) ELSE Rel("none"))
  ELSE IF vpc <= VLen THEN VOp(vpc) ELSE Rel("none")
\* @type: (Str, $op) => Set(Str);
BlockersOf(t, o) ==
  IF o.a # "acq" \/ o.p = "none" THEN {}
  ELSE IF o.m = "S" THEN {x \in Threads : x # t /\ lx[o.p] = x}
  ELSE {x \in Threads : x # t /\ (lx[o.p] = x \/ x \in ls[o.p])}
Edge(a, b) == LET o == WantOp(a) IN b \in BlockersOf(a, o)

\* C1: no latch wait cycle (two or three threads)
NoWaitCycle ==
  /\ ~\E a, b \in Threads : a # b /\ Edge(a, b) /\ Edge(b, a)
  /\ ~\E a, b, c \in Threads : a # b /\ b # c /\ a # c /\ Edge(a, b) /\ Edge(b, c) /\ Edge(c, a)
\* C2: the innermost scan holds no page while R works at another level
LevelRelease == rpc \in {"leaf", "lookup", "refix", "mstart", "mrow", "onext"} => held = {}
\* C3: one innermost pass fixes each of its pages once and one middle pass fixes each middle page once
\* (develop: once per row)
IFixBound == ifix <= 2
MFixBound == mfix <= 2
\* C4: a middle row read from a copy reads the copy its own pass took, of the page as it is
NoStale == ~stale

\* C5: every thread finishes
AllDone == <>Done

\* witnesses (each expected violated)
NotSeen(e) == e \notin seen
NotEarly == NotSeen("early-stop")
NotYield == NotSeen("ordered-yield")
NotRestartHeld == NotSeen("restart-on-held")
NotCopyRead == NotSeen("copy-read")
NotWWaitsR == ~Edge("W", "R")
NotVWaitsR == ~Edge("V", "R")

(***************************************************************************)
(* Inductive invariant (the design: Mutant = "none")                       *)
(***************************************************************************)
RPcs == {"leaf", "lookup", "refix", "mstart", "mrow", "mrefix", "istart", "inner", "iend", "onext", "done"}
Events == {"early-stop", "level-move-held", "ordered-yield", "restart-on-held", "copy-read", "w-waited-r"}
\* @type: (Int, Int, Int) => Bool;
In(x, lo, hi) == lo <= x /\ x <= hi

TypeOK ==
  /\ DOMAIN lx = Pages /\ \A p \in Pages : lx[p] \in Threads \cup {"none"}
  /\ DOMAIN ls = Pages /\ \A p \in Pages : ls[p] \subseteq Threads
  /\ rpc \in RPcs /\ In(orow, 0, NO) /\ In(mr, 0, MR1 + MR2) /\ mp \in {1, 2} /\ ip \in {1, 2} /\ In(rr, 0, R1 + R2)
  /\ held \subseteq {"B1", "B2"} /\ refix \subseteq {"B1", "B2"} /\ cvp \in {0, 1, 2} /\ cpass >= 0 /\ mpass >= 0
  /\ In(wpc, 1, WLen + 1) /\ In(vpc, 1, VLen + 1) /\ In(ifix, 0, 2) /\ In(mfix, 0, 2) /\ stale \in BOOLEAN
  /\ seen \subseteq Events

\* every latch is held by the thread whose position says so
ILatchR ==
  /\ \A p \in Pages : lx[p] # "R"
  /\ \A p \in Pages : ("R" \in ls[p]) <=> p \in held
ILatchW == \A p \in Pages : (lx[p] = "W") <=> p \in WHolds(wpc)
ILatchV == \A p \in Pages : (lx[p] = "V") <=> p \in VHolds(vpc)
INoS == \A p \in Pages : ls[p] \subseteq {"R"}
IExcl == \A p \in Pages : lx[p] # "none" => ls[p] = {}

\* R holds an innermost page only inside the innermost pass (and, after an early stop, until it goes back)
IRHeld ==
  /\ refix = {} /\ rpc \notin {"refix", "mrefix"}
  /\ rpc = "inner" => held = {Page(ip)}
  /\ rpc = "iend" => held \subseteq {Page(ip)}
  /\ rpc \notin {"inner", "iend"} => held = {}
\* the outer and middle positions
IRPos ==
  /\ (rpc = "done") <=> orow = NO
  /\ rpc \in {"istart", "inner", "iend"} => mr >= 1
  /\ rpc = "onext" => mp = 2 /\ mr = MRows(2)
  /\ mr <= MRows(mp)
  /\ rpc = "iend" /\ held # {} => rr >= 1
  /\ rpc = "inner" /\ ip = 1 => ifix <= 1
  /\ rpc \in {"leaf", "lookup", "mstart"} => ~("R" \in ls["L"])
\* the middle copy belongs to the current pass from the pass's first row on
ICopy ==
  /\ cpass <= mpass
  /\ rpc \in {"mrow", "istart", "inner", "iend", "onext"} =>
       /\ mpass >= 1
       /\ (cvp # 0 => cpass = mpass)
       /\ (cvp = 2 => mp = 2)
       /\ (mr > 0 => cvp = mp)
       /\ (mp = 2 => cvp # 0)
       /\ (mp = 1 /\ mr = 0 => cvp = 0)
       /\ (mp = 2 /\ MR2 > 0 => cvp = 2)
       /\ mfix = (IF mp = 2 THEN 2 ELSE IF mr > 0 THEN 1 ELSE 0)

IndInv ==
  /\ TypeOK
  /\ NoWaitCycle
  /\ LevelRelease
  /\ IFixBound
  /\ MFixBound
  /\ NoStale
  /\ ILatchR
  /\ ILatchW
  /\ ILatchV
  /\ INoS
  /\ IExcl
  /\ IRHeld
  /\ IRPos
  /\ ICopy
=============================================================================
