---------------------------- MODULE OvfDirChain ----------------------------
(***************************************************************************)
(* PR 8432 review copy (head cca5378df): Swap = "routed" is the PR's     *)
(* btree_ovf_dir_route_oid leaf swap, Swap = "first" the merge-base's.    *)
(* One key of a non-unique index: its leaf record and its OID-ordered       *)
(* overflow chain with the separator directory (CBRD-24094, PR 7447), plus  *)
(* ALTER INDEX ... COMPACT pulls (CBRD-27401, PR 7899).  Code: develop      *)
(* 21c6e635d, src/storage/btree.c.  Every action is one operation done      *)
(* under the key's leaf WRITE latch (MAP.md, refinement map), so actions    *)
(* do not interleave inside; the only split step is the leaf swap of        *)
(* btree_replace_first_oid_with_ovfl_oid, whose two halves are separately   *)
(* durable (crash fault).                                                   *)
(***************************************************************************)
EXTENDS Naturals, Sequences, FiniteSets, TLC

CONSTANTS NOid, NVer, PageCap, DirCap, Mutant, CrashSwap, Compact, DFix, Swap

ASSUME NOid \in Nat \ {0} /\ NVer \in Nat \ {0}
ASSUME PageCap \in Nat /\ PageCap >= 2 /\ DirCap \in Nat /\ DirCap >= 2
ASSUME CrashSwap \in BOOLEAN /\ Compact \in BOOLEAN
\* leaf swap page: merge-base 953e83256 always the first page; PR 8432 head the page the directory routes D to
ASSUME Swap \in {"first", "routed"}
\* candidate fix for H2: a miss also searches the first data page, the only page the swap puts an object in
ASSUME DFix \in {"none", "first_page_fallback"}
ASSUME Mutant \in {"none", "no_catch_all", "no_step_back", "no_set_sep", "grow_right_any",
                   "no_backoff", "adv_strict", "split_le", "swap_keep", "route_always"}

Obj == (1..NOid) \X (1..NVer)          \* <<OID, version>>: versions share the OID (reused OIDs)
Oid(o) == o[1]
MaxPg == NOid * NVer                    \* a page never empty, so this many pages suffice
Pg == 1..MaxPg
NoPg == 0
Ent == [sep : 1..NOid, pg : Pg]

VARIABLES
  chain,  \* data pages in next_vpid order; chain[1] is the leaf record's ovfl link
  data,   \* [Pg -> Seq(Obj)]: slot-1 record of each data page (<<>> when free)
  hdr,    \* [Pg -> {"N","H"}]: BTREE_OVF_DIR_HEADER.dir_vpid NULL or stamped with the head
  dir,    \* directory pages in next order, dir[1] = the immutable head; each a Seq(Ent)
  leaf,   \* objects in the leaf record (LeafCap 1: at most one)
  live,   \* ghost: objects the key holds
  stale,  \* ghost: objects left behind by a crash that recovery could not find again
  pend,   \* <<o>> while the swap's second half (remove o from the first page) is pending
  bad,    \* ghost: assertion / error outcomes
  seen    \* ghost: structural events reached (witnesses)

vars == <<chain, data, hdr, dir, leaf, live, stale, pend, bad, seen>>
\* TLC fingerprint without the ghosts: bad is an invariant violation anyway, seen only feeds witnesses
View == <<chain, data, hdr, dir, leaf, live, stale, pend>>

Range(s) == {s[i] : i \in DOMAIN s}
InsertAt(s, i, e) == SubSeq(s, 1, i - 1) \o <<e>> \o SubSeq(s, i, Len(s))
RemoveAt(s, i) == SubSeq(s, 1, i - 1) \o SubSeq(s, i + 1, Len(s))
Last(s) == s[Len(s)]
IndexOf(s, e) == CHOOSE i \in DOMAIN s : s[i] = e

RECURSIVE FlatPages(_)
FlatPages(c) == IF c = <<>> THEN <<>> ELSE data[Head(c)] \o FlatPages(Tail(c))
RECURSIVE FlatSeq(_)
FlatSeq(ss) == IF ss = <<>> THEN <<>> ELSE Head(ss) \o FlatSeq(Tail(ss))
Flat == FlatPages(chain)
FlatDir == FlatSeq(dir)
ChainObjs == Range(Flat)

FreePg == Pg \ Range(chain)
NewPg == CHOOSE p \in FreePg : \A q \in FreePg : p <= q      \* file_alloc: lowest free page

(* btree_insert_object_ordered_by_oid: binary search, 0-based offset *)
RECURSIVE BSI(_, _, _, _, _)
BSI(s, x, lo, hi, mid) ==
  IF lo > hi THEN mid
  ELSE LET m == (lo + hi) \div 2
           mo == Oid(s[m + 1])
       IN IF x = mo THEN m
          ELSE IF x > mo THEN BSI(s, x, m + 1, hi, m + 1)
          ELSE BSI(s, x, lo, m - 1, m)
InsOrdered(s, o) == InsertAt(s, BSI(s, Oid(o), 0, Len(s) - 1, 0) + 1, o)

(* btree_find_oid_from_ovfl: early outs on the first and the last object, then a search *)
InPage(o, p) ==
  LET s == data[p] IN
  IF Oid(o) < Oid(s[1]) THEN FALSE
  ELSE IF s[1] = o THEN TRUE
  ELSE IF Oid(o) > Oid(Last(s)) THEN FALSE
  ELSE o \in Range(s)

(* btree_ovf_dir_locate *)
AdvOK(a, x) == IF Mutant = "adv_strict" THEN a < x ELSE a <= x
RECURSIVE Adv(_, _)
Adv(x, d) == IF d < Len(dir) /\ AdvOK(dir[d + 1][1].sep, x) THEN Adv(x, d + 1) ELSE d
RECURSIVE BS(_, _, _, _, _)
BS(x, d, lo, hi, idx) ==
  IF lo > hi THEN idx
  ELSE LET m == (lo + hi) \div 2
       IN IF ~(d = 1 /\ m = 0 /\ Mutant # "no_catch_all") /\ dir[d][m + 1].sep > x
          THEN BS(x, d, lo, m - 1, idx)
          ELSE BS(x, d, m + 1, hi, m)
Locate(x) == LET d == Adv(x, 1) IN <<d, BS(x, d, 0, Len(dir[d]) - 1, 0) + 1>>

(* btree_ovf_dir_find_oid: route, then step back while the OID does not exceed the page's first *)
RECURSIVE Walk(_, _, _, _)
Walk(o, d, i, st) ==
  LET p == dir[d][i].pg IN
  IF InPage(o, p) THEN <<p, st>>
  ELSE IF Oid(o) > Oid(data[p][1]) \/ Mutant = "no_step_back" THEN <<NoPg, st>>
  ELSE IF i > 1 THEN Walk(o, d, i - 1, TRUE)
  ELSE IF d = 1 THEN <<NoPg, st>>
  ELSE Walk(o, d - 1, Len(dir[d - 1]), TRUE)

Find(o) ==
  IF chain = <<>> THEN <<NoPg, FALSE>>
  ELSE IF hdr[chain[1]] = "N"
       THEN IF InPage(o, chain[1]) THEN <<chain[1], FALSE>> ELSE <<NoPg, FALSE>>
       ELSE LET l == Locate(Oid(o))
                w == Walk(o, l[1], l[2], FALSE)
            IN IF w[1] = NoPg /\ DFix = "first_page_fallback" /\ InPage(o, chain[1])
               THEN <<chain[1], TRUE>> ELSE w

(* directory positions *)
DirPos(dd) == UNION {{<<d, i>> : i \in DOMAIN dd[d]} : d \in DOMAIN dd}
HasEnt(dd, p) == \E di \in DirPos(dd) : dd[di[1]][di[2]].pg = p
PosOf(dd, p) == CHOOSE di \in DirPos(dd) : dd[di[1]][di[2]].pg = p

(* btree_ovf_dir_insert_entry: new entry becomes dd[d][pos] *)
DirInsert(dd, d, pos, e) ==
  IF Len(dd[d]) < DirCap THEN [dd EXCEPT ![d] = InsertAt(@, pos, e)]
  ELSE IF pos = Len(dd[d]) + 1 /\ d = Len(dd) THEN Append(dd, <<e>>)
  ELSE LET n == Len(dd[d])
           h == n \div 2
           lo == SubSeq(dd[d], 1, h)
           up == SubSeq(dd[d], h + 1, n)
       IN IF pos - 1 <= h
          THEN SubSeq(dd, 1, d - 1) \o <<InsertAt(lo, pos, e), up>> \o SubSeq(dd, d + 1, Len(dd))
          ELSE SubSeq(dd, 1, d - 1) \o <<lo, InsertAt(up, pos - h, e)>> \o SubSeq(dd, d + 1, Len(dd))
DirInsertEv(dd, d, pos) ==
  IF Len(dd[d]) < DirCap THEN {}
  ELSE IF pos = Len(dd[d]) + 1 /\ d = Len(dd) THEN {"dirtail"} ELSE {"dirsplit"}

(* btree_ovf_dir_remove_entry: in place, or pull the next page up into the head, or unlink *)
DirRemove(dd, p) ==
  IF ~HasEnt(dd, p) THEN dd
  ELSE LET di == PosOf(dd, p)
           d == di[1]
       IN IF Len(dd[d]) > 1 THEN [dd EXCEPT ![d] = RemoveAt(@, di[2])]
          ELSE IF d = 1 THEN SubSeq(dd, 2, Len(dd))      \* next record pulled up into the head
          ELSE RemoveAt(dd, d)
DirRemoveBad(dd, p) ==
  IF ~HasEnt(dd, p) THEN {"dir_entry_missing"}
  ELSE LET di == PosOf(dd, p) IN
       IF Len(dd[di[1]]) = 1 /\ di[1] = 1 /\ Len(dd) = 1 THEN {"head_empty_no_next"} ELSE {}
DirRemoveEv(dd, p) ==
  IF HasEnt(dd, p) /\ Len(dd[PosOf(dd, p)[1]]) = 1
  THEN IF PosOf(dd, p)[1] = 1 THEN {"pullup"} ELSE {"dirunlink"} ELSE {}

(* btree_ovf_dir_set_separator and its four asserts *)
SetSep(dd, p, ns) ==
  IF ~HasEnt(dd, p) THEN dd
  ELSE LET di == PosOf(dd, p) IN [dd EXCEPT ![di[1]][di[2]].sep = ns]
SetSepBad(dd, p, ns) ==
  IF ~HasEnt(dd, p) THEN {"dir_entry_missing"}
  ELSE LET di == PosOf(dd, p)
           d == di[1]
           i == di[2]
           es == dd[d]
       IN (IF i = 1 /\ d = 1 THEN {"setsep_catchall"} ELSE {})
          \cup (IF es[i].sep > ns THEN {"setsep_down"} ELSE {})
          \cup (IF i > 1 /\ ~(i = 2 /\ d = 1) /\ es[i - 1].sep > ns THEN {"setsep_prev"} ELSE {})
          \cup (IF i < Len(es) /\ ns > es[i + 1].sep THEN {"setsep_next"} ELSE {})

Idle == pend = <<>>

(* btree_replace_first_oid_with_ovfl_oid at PR 8432: a non-unique chain with a directory sends D past the
   first page iff OID_GT (D, last object of the first page); btree_ovf_dir_route_oid then takes the page
   btree_ovf_dir_locate returns (the first page when it routes there) *)
SwapPg(o) ==
  IF Swap = "routed" /\ hdr[chain[1]] = "H" /\ (Mutant = "route_always" \/ Oid(o) > Oid(Last(data[chain[1]])))
  THEN dir[Locate(Oid(o))[1]][Locate(Oid(o))[2]].pg
  ELSE chain[1]

(* btree_overflow_remove_object on chain[ci] at position k, with the page unlink and directory upkeep *)
RemoveObjAt(ci, k, ev) ==
  LET p == chain[ci] IN
  IF Len(data[p]) = 1
  THEN /\ chain' = RemoveAt(chain, ci)
       /\ data' = [data EXCEPT ![p] = <<>>]
       /\ hdr' = [hdr EXCEPT ![p] = "N"]
       /\ IF hdr[p] = "H"
          THEN IF ci = 1 /\ Len(chain) = 1
               THEN dir' = <<>> /\ bad' = bad /\ seen' = seen \cup ev \cup {"destroy"}
               ELSE /\ dir' = DirRemove(dir, p)
                    /\ bad' = bad \cup DirRemoveBad(dir, p)
                    /\ seen' = seen \cup ev \cup {"pagefree"} \cup DirRemoveEv(dir, p)
          ELSE dir' = dir /\ bad' = bad /\ seen' = seen \cup ev
  ELSE /\ data' = [data EXCEPT ![p] = RemoveAt(@, k)]
       /\ seen' = seen \cup ev
       /\ UNCHANGED <<chain, hdr, dir, bad>>

(* btree_ovf_dir_grow_chain: grow right on an ascending OID at the rightmost page, else split in half *)
Grow(o, ci, d, i) ==
  LET t == chain[ci]
      s == data[t]
      q == NewPg
      gr == ci = Len(chain) /\ (Mutant = "grow_right_any" \/ Oid(o) > Oid(Last(s)))
      h == Len(s) \div 2
      sep == IF gr THEN Oid(o) ELSE Oid(s[h + 1])
      lowS == IF gr THEN s ELSE SubSeq(s, 1, h)
      upS == IF gr THEN <<o>> ELSE SubSeq(s, h + 1, Len(s))
      toLow == ~gr /\ (IF Mutant = "split_le" THEN Oid(o) <= sep ELSE Oid(o) < sep)
      e == [sep |-> sep, pg |-> q]
  IN /\ chain' = InsertAt(chain, ci + 1, q)
     /\ data' = [data EXCEPT ![t] = IF toLow THEN InsOrdered(lowS, o) ELSE lowS,
                             ![q] = IF gr \/ toLow THEN upS ELSE InsOrdered(upS, o)]
     /\ hdr' = [hdr EXCEPT ![t] = "H", ![q] = "H"]
     /\ dir' = IF d = 0 THEN <<<<[sep |-> Oid(s[1]), pg |-> t], e>>>> ELSE DirInsert(dir, d, i + 1, e)
     /\ seen' = seen \cup {IF gr THEN "growright" ELSE "split"}
                     \cup (IF d = 0 THEN {"birth"} ELSE DirInsertEv(dir, d, i + 1))

(* btree_ovf_dir_append_object *)
AppendOvf(o) ==
  LET f == chain[1] IN
  IF hdr[f] = "N"
  THEN IF Len(data[f]) < PageCap
       THEN data' = [data EXCEPT ![f] = InsOrdered(@, o)] /\ UNCHANGED <<chain, hdr, dir, seen>>
       ELSE Grow(o, 1, 0, 0)
  ELSE LET l == Locate(Oid(o))
           t == dir[l[1]][l[2]].pg
       IN IF Len(data[t]) < PageCap
          THEN data' = [data EXCEPT ![t] = InsOrdered(@, o)] /\ UNCHANGED <<chain, hdr, dir, seen>>
          ELSE Grow(o, IndexOf(chain, t), l[1], l[2])

(* insert of a new object version into the key *)
Insert(o) ==
  /\ Idle
  /\ o \notin live \cup stale
  /\ live' = live \cup {o}
  /\ IF leaf = {}
     THEN leaf' = {o} /\ UNCHANGED <<chain, data, hdr, dir, seen>>
     ELSE IF chain = <<>>
          THEN LET q == NewPg IN
               /\ chain' = <<q>>
               /\ data' = [data EXCEPT ![q] = <<o>>]
               /\ hdr' = [hdr EXCEPT ![q] = "N"]
               /\ UNCHANGED <<dir, seen>>
          ELSE AppendOvf(o)
  /\ leaf # {} => leaf' = leaf
  /\ UNCHANGED <<stale, pend, bad>>

(* physical removal: vacuum, rollback of the insert, non-MVCC delete *)
Remove(o) ==
  /\ Idle
  /\ o \in live
  /\ IF o \in leaf
     THEN IF chain = <<>>
          THEN leaf' = {} /\ live' = live \ {o} /\ UNCHANGED <<chain, data, hdr, dir, stale, pend, bad, seen>>
          ELSE LET sp == SwapPg(o)
                   lst == Last(data[sp])
                   sev == {"swap"} \cup (IF sp # chain[1] THEN {"routed"} ELSE {})
                             \cup (IF sp # chain[1] /\ Len(data[sp]) = 1 THEN {"routedfree"} ELSE {})
               IN /\ leaf' = {lst}
                  /\ live' = live \ {o}
                  /\ IF CrashSwap
                     THEN \* swap sysop committed: the swap page's last object went to the leaf and o took
                          \* its place at o's OID-ordered position (btree_record_replace_object)
                          /\ data' = [data EXCEPT ![sp] = InsOrdered(SubSeq(@, 1, Len(@) - 1), o)]
                          /\ pend' = <<o>>
                          /\ seen' = seen \cup sev
                          /\ UNCHANGED <<chain, hdr, dir, stale, bad>>
                     ELSE IF Mutant = "swap_keep"
                     THEN /\ seen' = seen \cup sev
                          /\ UNCHANGED <<chain, data, hdr, dir, stale, pend, bad>>
                     ELSE /\ RemoveObjAt(IndexOf(chain, sp), Len(data[sp]), sev)
                          /\ UNCHANGED <<stale, pend>>
     ELSE LET f == Find(o) IN
          IF f[1] = NoPg
          THEN /\ bad' = bad \cup {"unknown_key"}
               /\ UNCHANGED <<chain, data, hdr, dir, leaf, live, stale, pend, seen>>
          ELSE /\ RemoveObjAt(IndexOf(chain, f[1]), IndexOf(data[f[1]], o),
                                IF f[2] THEN {"stepback"} ELSE {})
               /\ live' = live \ {o}
               /\ UNCHANGED <<leaf, stale, pend>>

(* the swap's second half: remove the displaced object at the offset the replace returned *)
SwapDone ==
  /\ pend # <<>>
  /\ LET ci == CHOOSE c \in DOMAIN chain : pend[1] \in Range(data[chain[c]])
     IN RemoveObjAt(ci, IndexOf(data[chain[ci]], pend[1]), {})
  /\ pend' = <<>>
  /\ UNCHANGED <<leaf, live, stale>>

(* crash between the halves; recovery re-executes the removal by lookup (vacuum re-run, undo of the insert) *)
CrashRecover ==
  /\ pend # <<>>
  /\ pend' = <<>>
  /\ LET o == pend[1]
         f == Find(o)
     IN IF f[1] = NoPg
        THEN /\ stale' = stale \cup {o}
             /\ bad' = bad \cup {"crash_swap_lost"}
             /\ seen' = seen \cup {"crash"}
             /\ UNCHANGED <<chain, data, hdr, dir, leaf, live>>
        ELSE /\ RemoveObjAt(IndexOf(chain, f[1]), IndexOf(data[f[1]], o), {"crash"})
             /\ UNCHANGED <<leaf, live, stale>>

(* btree_ovf_compact_pull on the pair chain[ci], chain[ci+1], moving n objects: merge or partial move *)
PullAt(ci, n) ==
  LET l == chain[ci]
      r == chain[ci + 1]
      ls == data[l]
      rs == data[r]
  IN /\ n <= Len(rs)
     /\ Len(ls) + n <= PageCap
     /\ IF n < Len(rs)
        THEN /\ Mutant = "no_backoff" \/ Oid(rs[n]) < Oid(rs[n + 1])
             /\ data' = [data EXCEPT ![l] = ls \o SubSeq(rs, 1, n), ![r] = SubSeq(rs, n + 1, Len(rs))]
             /\ dir' = IF Mutant = "no_set_sep" THEN dir ELSE SetSep(dir, r, Oid(rs[n + 1]))
             /\ bad' = bad \cup SetSepBad(dir, r, Oid(rs[n + 1]))
             /\ seen' = seen \cup {"partial"}
             /\ UNCHANGED <<chain, hdr>>
        ELSE /\ data' = [data EXCEPT ![l] = ls \o rs, ![r] = <<>>]
             /\ chain' = RemoveAt(chain, ci + 1)
             /\ hdr' = [hdr EXCEPT ![r] = "N"]
             /\ dir' = DirRemove(dir, r)
             /\ bad' = bad \cup DirRemoveBad(dir, r)
             /\ seen' = seen \cup {"merge"} \cup DirRemoveEv(dir, r)
     /\ UNCHANGED <<leaf, live, stale, pend>>

Pull ==
  /\ Compact
  /\ Idle
  /\ Len(chain) >= 2
  /\ hdr[chain[1]] = "H"
  /\ \E ci \in 1..(Len(chain) - 1), n \in 1..PageCap : PullAt(ci, n)

Init ==
  /\ chain = <<>>
  /\ data = [p \in Pg |-> <<>>]
  /\ hdr = [p \in Pg |-> "N"]
  /\ dir = <<>>
  /\ leaf = {}
  /\ live = {}
  /\ stale = {}
  /\ pend = <<>>
  /\ bad = {}
  /\ seen = {}

Next == \/ \E o \in Obj : Insert(o) \/ Remove(o)
        \/ Pull
        \/ SwapDone
        \/ CrashRecover

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(* Properties                                                              *)
(***************************************************************************)
TypeOK ==
  /\ chain \in Seq(Pg)
  /\ data \in [Pg -> Seq(Obj)]
  /\ hdr \in [Pg -> {"N", "H"}]
  /\ dir \in Seq(Seq(Ent))
  /\ leaf \subseteq Obj /\ Cardinality(leaf) <= 1
  /\ live \subseteq Obj /\ stale \subseteq Obj
  /\ pend \in Seq(Obj) /\ Len(pend) <= 1

\* C2: one chain, no empty or overfull page, the leaf record never empty while the chain exists
Shape ==
  /\ Len(chain) = Cardinality(Range(chain))
  /\ \A k \in DOMAIN chain : Len(data[chain[k]]) \in 1..PageCap
  /\ \A p \in FreePg : data[p] = <<>>
  /\ chain # <<>> => leaf # {}
  /\ \A d \in DOMAIN dir : Len(dir[d]) \in 1..DirCap

\* C2: the chain is globally OID-ordered
Sorted == Idle => \A i, j \in DOMAIN Flat : i < j => Oid(Flat[i]) <= Oid(Flat[j])

\* C2: the directory exists iff the chain grew to two pages (kept on shrink), its entries follow the
\* chain, every data page header carries it, separators do not descend after the head's entry 0
DirMatch ==
  /\ chain = <<>> => dir = <<>>
  /\ chain # <<>> => \A k \in DOMAIN chain : hdr[chain[k]] = IF dir = <<>> THEN "N" ELSE "H"
  /\ dir = <<>> => Len(chain) <= 1
  /\ dir # <<>> => Len(FlatDir) = Len(chain) /\ \A k \in DOMAIN chain : FlatDir[k].pg = chain[k]
DirSorted == \A a, b \in 2..Len(FlatDir) : a < b => FlatDir[a].sep <= FlatDir[b].sep

\* C1: every object of the chain is found by btree_ovf_dir_find_oid
Routable == Idle => \A k \in DOMAIN chain : \A j \in DOMAIN data[chain[k]] :
              data[chain[k]][j] \notin stale => Find(data[chain[k]][j])[1] = chain[k]

\* C4: no object lost or duplicated by a structural change
Content ==
  Idle => /\ Len(Flat) = Cardinality(ChainObjs)
          /\ leaf \cap ChainObjs = {}
          /\ ChainObjs \cup leaf = live \cup stale

\* C1, C3, C5: no lookup miss, no directory assert, no object lost across a crash
NoBad == bad = {}

Safety == Shape /\ Sorted /\ DirMatch /\ DirSorted /\ Routable /\ Content /\ NoBad

\* Refinement to the abstract order model (C2, C3; TLAPS-proved there)
AbsSep(k) == IF dir = <<>> \/ k > Len(FlatDir) THEN 0 ELSE FlatDir[k].sep
Order == INSTANCE OvfOrder WITH
           MaxP <- MaxPg,
           Obj <- Obj,
           OidVals <- 0..NOid,
           np <- Len(chain),
           cont <- [r \in 1..MaxPg |-> IF r <= Len(chain) THEN Range(data[chain[r]]) ELSE {}],
           sep <- [r \in 1..MaxPg |-> IF r <= Len(chain) THEN AbsSep(r) ELSE 0]
OrderSpec == Order!Spec

(* witnesses: each expected violated *)
NotEv(e) == e \notin seen
NoStepBack == NotEv("stepback")
NoPullUp == NotEv("pullup")
NoDirSplit == NotEv("dirsplit")
NoDirTail == NotEv("dirtail")
NoPartial == NotEv("partial")
NoMerge == NotEv("merge")
NoSwap == NotEv("swap")
NoRouted == NotEv("routed")
NoRoutedFree == NotEv("routedfree")
=============================================================================
