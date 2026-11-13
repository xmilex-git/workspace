------------------------------- MODULE PR8353 -------------------------------
(***************************************************************************)
(* CUBRID/cubrid#8353 (CBRD-27862) at c7dbe4ba6: a B-tree node search of a *)
(* single-column SHORT/INTEGER/BIGINT index compares the records' key      *)
(* images instead of reading each key into a DB_VALUE.                     *)
(*                                                                         *)
(* The model runs the same page search twice:                              *)
(*   "old" - develop: every probe reads the key with the sequential        *)
(*           or_advance reader and compares with btree_compare_bound_key.  *)
(*   "new" - the PR: btree_integral_search_key_init decides once; a probe  *)
(*           whose record yields an image (btree_leaf_record_key_image /   *)
(*           btree_non_leaf_record_key_image) compares it with             *)
(*           btree_integral_search_key_compare, any other probe falls back *)
(*           to the reader, which now finds the key through                *)
(*           btree_leaf_record_key_offset.                                 *)
(* and checks that both runs return the same answer, and that the answer   *)
(* is right for the page.                                                  *)
(*                                                                         *)
(* Scaling: a stored byte has BW bits instead of 8; byte counts are the    *)
(* real ones (OR_SHORT_SIZE 2, OR_INT_SIZE 4, OR_BIGINT_SIZE 8, OID 8,     *)
(* MVCCID 8, NON_LEAF_RECORD_SIZE 8), so offsets and bounds are exact.     *)
(*                                                                         *)
(* Mutation # "none" plants a defect so that the run shows the model can   *)
(* see it.                                                                 *)
(***************************************************************************)
EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS MaxKeys, Mutation

Mutations == {"none",
              "nodesc",            \* compare ignores is_desc
              "unsigned",          \* image widened without sign extension
              "offset_noclass",    \* key offset skips the class OID
              "offset_nodel",      \* key offset skips the delete MVCCID
              "nonleaf_pnt",       \* image probe does not read the child pointer
              "pagebounds_image",  \* image probe also when page_bounds != NULL
              "guard_conv"}        \* init accepts a bound that converts
ASSUME Mutation \in Mutations
ASSUME MaxKeys \in 1..6

LT == -1
EQ == 0
GT == 1
Sign(x) == IF x < 0 THEN LT ELSE IF x > 0 THEN GT ELSE EQ
Cmp(a, b) == Sign(a - b)
Flip(c) == -c

(* ---------------------- stored images (scaled) ------------------------ *)
BW == 2
Base == 2^BW
Types == {"SHORT", "INTEGER", "BIGINT"}
Size(t) == CASE t = "SHORT" -> 2 [] t = "INTEGER" -> 4 [] t = "BIGINT" -> 8
NBits(n) == BW * n
TMin(t) == -(2^(NBits(Size(t)) - 1))
TMax(t) == 2^(NBits(Size(t)) - 1) - 1
Interesting(t) == {TMin(t), -1, 0, 1, TMax(t)}

Repeat(x, n) == [i \in 1..n |-> x]

(* mr_index_writeval_*: or_put_data of the native (little-endian) value *)
Encode(v, n) == LET u == IF v < 0 THEN v + 2^NBits(n) ELSE v
                IN [i \in 1..n |-> (u \div (Base^(i - 1))) % Base]
RECURSIVE SumLE(_, _)
SumLE(b, i) == IF i > Len(b) THEN 0 ELSE b[i] * Base^(i - 1) + SumLE(b, i + 1)
(* memcpy into short/int/DB_BIGINT, then widen to DB_BIGINT *)
DecodeSigned(b) == LET u == SumLE(b, 1)
                       n == Len(b)
                   IN IF u >= 2^(NBits(n) - 1) THEN u - 2^NBits(n) ELSE u
Extract(cells, off, n) == [i \in 1..n |-> cells[off + i]]

(* ------------------------- record layouts ----------------------------- *)
OID == 8
MVCCID == 8
NLFIX == 8      \* NON_LEAF_RECORD_SIZE = DISK_VPID_ALIGNED_SIZE
OVFVPID == 6

(* header variants of a page's leaf records (btree_write_record_header):  *)
(* coid = the record carries a class OID (unique index, subclass object)  *)
Hdrs == {[uniq |-> FALSE, coid |-> FALSE, ins |-> FALSE, del |-> FALSE],
         [uniq |-> TRUE,  coid |-> FALSE, ins |-> TRUE,  del |-> FALSE],
         [uniq |-> TRUE,  coid |-> TRUE,  ins |-> TRUE,  del |-> TRUE],
         [uniq |-> FALSE, coid |-> FALSE, ins |-> TRUE,  del |-> TRUE]}

(* btree_write_record_header + key: header bytes carry recognizable junk *)
LeafCells(h, ovf, t, v) ==
  Repeat(3, OID)
  \o (IF h.uniq /\ h.coid THEN Repeat(2, OID) ELSE <<>>)
  \o (IF h.ins THEN Repeat(1, MVCCID) ELSE <<>>)
  \o (IF h.del THEN Repeat(Base - 1, MVCCID) ELSE <<>>)
  \o (IF ovf THEN Repeat(0, OVFVPID) ELSE Encode(v, Size(t)))
NonLeafCells(ovf, t, v) ==
  Repeat(2, NLFIX) \o (IF ovf THEN Repeat(0, OVFVPID) ELSE Encode(v, Size(t)))

(* develop's btree_read_record_without_decompression: sequential advances *)
SeqOffset(h) ==
  LET o1 == OID
      o2 == IF h.uniq /\ h.coid THEN o1 + OID ELSE o1   \* uniq && CLASS_OID flag
      o3 == IF h.ins THEN o2 + MVCCID ELSE o2
  IN IF h.del THEN o3 + MVCCID ELSE o3
(* btree_leaf_record_key_offset *)
HelperOffset(h) ==
  OID
  + (IF h.uniq /\ h.coid /\ Mutation # "offset_noclass" THEN OID ELSE 0)
  + (IF h.ins THEN MVCCID ELSE 0)
  + (IF h.del /\ Mutation # "offset_nodel" THEN MVCCID ELSE 0)

(* ---------------------- the two comparisons --------------------------- *)
(* btree_compare_bound_key / btree_compare_key on DB_VALUEs.  A "direct"  *)
(* bound compares as the index type's cmpval; a "conv" bound converts and *)
(* merges neighbours (value \div 2) - any comparison the PR must not take *)
GenCmp(sc, r) ==
  LET c == IF sc.bound = "conv" THEN Cmp(sc.v \div 2, r \div 2) ELSE Cmp(sc.v, r)
  IN IF sc.desc THEN Flip(c) ELSE c

(* btree_integral_search_key_compare *)
IntCmp(sc, img) ==
  LET val == IF Mutation = "unsigned" THEN SumLE(img, 1) ELSE DecodeSigned(img)
      c == Cmp(sc.v, val)
  IN IF sc.desc /\ Mutation # "nodesc" THEN Flip(c) ELSE c

(* btree_integral_search_key_init: size > 0 *)
Guard(sc) ==
  /\ sc.kt = sc.t
  /\ (sc.bound \in {"none", "direct"} \/ Mutation = "guard_conv")
  /\ ~(sc.node = "nonleaf" /\ sc.pb /\ Mutation # "pagebounds_image")

Cells(sc, i) ==
  IF sc.node = "leaf" THEN LeafCells(sc.hdr, sc.ovf[i], sc.t, sc.keys[i])
  ELSE NonLeafCells(sc.ovf[i], sc.t, sc.keys[i])

(* the image, or <<>> for NULL *)
Image(sc, i) ==
  LET cells == Cells(sc, i)
      n == Size(sc.t)
      off == IF sc.node = "leaf" THEN HelperOffset(sc.hdr) ELSE NLFIX
  IN IF sc.ovf[i] \/ off + n > Len(cells) THEN <<>> ELSE Extract(cells, off, n)

(* the key a reader returns; a key in overflow pages reads back whole *)
ReadKey(m, sc, i) ==
  LET cells == Cells(sc, i)
      n == Size(sc.t)
      off == IF sc.node = "nonleaf" THEN NLFIX
             ELSE IF m = "old" THEN SeqOffset(sc.hdr) ELSE HelperOffset(sc.hdr)
  IN IF sc.ovf[i] THEN sc.keys[i]
     ELSE IF off + n > Len(cells) THEN TMax("BIGINT") + 1000   \* reader error
     ELSE DecodeSigned(Extract(cells, off, n))

(* <<c, probe kind>> *)
Probe(m, sc, i) ==
  IF m = "new" /\ Guard(sc) /\ Image(sc, i) # <<>>
  THEN <<IntCmp(sc, Image(sc, i)), "img">>
  ELSE <<GenCmp(sc, ReadKey(m, sc, i)), "gen">>

(* --------------------------- scenarios -------------------------------- *)
Sorted(s, desc) == \A i \in 1..(Len(s) - 1) :
                     IF desc THEN s[i] > s[i + 1] ELSE s[i] < s[i + 1]
KeySeqs(t, desc) == UNION {{s \in [1..k -> Interesting(t)] : Sorted(s, desc)} : k \in 1..MaxKeys}

VARIABLES sc, st
vars == <<sc, st>>
Modes == {"old", "new"}

InitSt(s) ==
  [done |-> FALSE, l |-> IF s.node = "leaf" THEN 1 ELSE 2, r |-> Len(s.keys), mid |-> 0, c |-> 0,
   res |-> "none", slot |-> 0, fence |-> FALSE, eqslot |-> 0, ufe |-> FALSE, isread |-> FALSE,
   pnt |-> 0, tmpk |-> 0, bnd |-> <<>>, imgs |-> 0]

Init ==
  \E nd \in {"leaf", "nonleaf"}, t \in Types, d \in BOOLEAN, h \in Hdrs, b \in {"none", "direct", "conv"}:
  \E ks \in KeySeqs(t, d):
  \E o \in [1..Len(ks) -> BOOLEAN],
     f1 \in (IF nd = "leaf" /\ Len(ks) >= 2 THEN BOOLEAN ELSE {FALSE}),
     fn \in (IF nd = "leaf" /\ Len(ks) >= 2 THEN BOOLEAN ELSE {FALSE}),
     pb \in (IF nd = "nonleaf" THEN BOOLEAN ELSE {FALSE}),
     kt \in (IF b = "conv" THEN Types ELSE {t}),
     e \in (IF b = "conv" THEN {LT, EQ, GT} ELSE {EQ}):
  \E v \in Interesting(kt):
    /\ sc = [node |-> nd, t |-> t, desc |-> d, hdr |-> IF nd = "leaf" THEN h ELSE CHOOSE x \in Hdrs : ~x.uniq /\ ~x.ins,
             bound |-> b, keys |-> ks, ovf |-> o, f1 |-> f1, fn |-> fn, pb |-> pb, kt |-> kt, v |-> v,
             merges |-> b = "conv", eqas |-> e]
    /\ st = [m \in Modes |-> InitSt(sc)]

(* -------------------- btree_search_leaf_page -------------------------- *)
IsFence(s, i) == (i = 1 /\ s.f1) \/ (i = Len(s.keys) /\ s.fn)

LeafStep(m) ==
  LET s == st[m]
      n == Len(sc.keys)
  IN IF s.l <= s.r THEN
       LET mid == (s.l + s.r + 1) \div 2       \* CEIL_PTVDIV
           p == Probe(m, sc, mid)
           c0 == p[1]
           s1 == [s EXCEPT !.mid = mid, !.isread = TRUE, !.imgs = @ + (IF p[2] = "img" THEN 1 ELSE 0)]
           Go(x, c) == IF c < 0 THEN [x EXCEPT !.r = mid - 1, !.c = c] ELSE [x EXCEPT !.l = mid + 1, !.c = c]
       IN st' = [st EXCEPT ![m] =
            IF c0 = EQ /\ IsFence(sc, mid) THEN
              (IF mid = 1 THEN Go([s1 EXCEPT !.fence = TRUE], GT)
               ELSE IF sc.merges /\ sc.eqas # EQ THEN Go([s1 EXCEPT !.fence = TRUE, !.ufe = TRUE], LT)
               ELSE [s1 EXCEPT !.fence = TRUE, !.done = TRUE, !.res = "BIGGER", !.slot = n])
            ELSE IF c0 = EQ /\ sc.merges /\ sc.eqas # EQ THEN Go([s1 EXCEPT !.eqslot = mid], sc.eqas)
            ELSE IF c0 = EQ THEN [s1 EXCEPT !.done = TRUE, !.res = "FOUND", !.slot = mid, !.c = EQ]
            ELSE Go(s1, c0)]
     ELSE
       LET s1 == IF s.isread /\ IsFence(sc, s.mid) THEN [s EXCEPT !.fence = TRUE] ELSE s
       IN st' = [st EXCEPT ![m] =
            IF s.eqslot # 0 THEN [s EXCEPT !.done = TRUE, !.res = "FOUND", !.slot = s.eqslot]
            ELSE IF s.ufe THEN [s EXCEPT !.done = TRUE, !.res = "BIGGER", !.slot = n]
            ELSE IF s.c < 0 THEN [s1 EXCEPT !.done = TRUE, !.res = IF s.mid = 1 THEN "SMALLER" ELSE "BETWEEN",
                                            !.slot = s.mid]
            ELSE [s1 EXCEPT !.done = TRUE, !.res = IF s.mid = n THEN "BIGGER" ELSE "BETWEEN", !.slot = s.mid + 1]]

(* ------------------- btree_search_nonleaf_page ------------------------ *)
(* child pointer of slot i is i; bnd is what the page_bounds update reads *)
NonLeafStep(m) ==
  LET s == st[m]
      n == Len(sc.keys)
  IN IF n = 1 THEN st' = [st EXCEPT ![m] = [s EXCEPT !.done = TRUE, !.slot = 1, !.pnt = 1]]
     ELSE IF s.l <= s.r THEN
       LET mid == (s.l + s.r + 1) \div 2
           p == Probe(m, sc, mid)
           img == p[2] = "img"
           \* btree_non_leaf_record_key_image reads the fixed portion before it decides
           pnt == IF img /\ Mutation = "nonleaf_pnt" THEN s.pnt ELSE mid
           tmpk == IF img THEN 0 ELSE mid          \* temp_key is cleared each probe
           c == IF p[1] = EQ /\ sc.merges THEN sc.eqas ELSE p[1]
           s1 == [s EXCEPT !.mid = mid, !.pnt = pnt, !.tmpk = tmpk, !.c = c, !.imgs = @ + (IF img THEN 1 ELSE 0)]
       IN st' = [st EXCEPT ![m] =
            IF c = EQ THEN [s1 EXCEPT !.done = TRUE, !.slot = mid, !.bnd = IF sc.pb THEN <<"eq", tmpk>> ELSE <<>>]
            ELSE IF c < 0 THEN [s1 EXCEPT !.r = mid - 1]
            ELSE [s1 EXCEPT !.l = mid + 1]]
     ELSE
       st' = [st EXCEPT ![m] =
         IF s.c < 0 THEN [s EXCEPT !.done = TRUE, !.slot = s.mid - 1, !.pnt = s.mid - 1,
                                   !.bnd = IF sc.pb THEN <<"lt", s.mid - 1, s.tmpk>> ELSE <<>>]
         ELSE [s EXCEPT !.done = TRUE, !.slot = s.mid,
                        !.bnd = IF sc.pb THEN <<"ge", s.tmpk>> ELSE <<>>]]

Step(m) == IF sc.node = "leaf" THEN LeafStep(m) ELSE NonLeafStep(m)

AllDone == \A m \in Modes : st[m].done
Next ==
  \/ /\ ~st["old"].done /\ Step("old") /\ UNCHANGED sc
  \/ /\ st["old"].done /\ ~st["new"].done /\ Step("new") /\ UNCHANGED sc
  \/ AllDone /\ UNCHANGED vars

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

(* ---------------------------- properties ------------------------------ *)
Out(s) == IF sc.node = "leaf" THEN <<s.res, s.slot, s.fence>>
          ELSE <<s.slot, s.pnt, s.bnd>>

(* the PR answers as develop does, for every page and search key *)
SameAnswer == AllDone => Out(st["old"]) = Out(st["new"])

(* the child pointer handed back is the chosen slot's *)
ChildIsSlot == \A m \in Modes : (st[m].done /\ sc.node = "nonleaf") => Out(st[m])[2] = st[m].slot

(* the answer is right for a leaf without fence keys or merging bound *)
LeafRight(s) ==
  LET n == Len(sc.keys)
      C(i) == GenCmp(sc, sc.keys[i])
  IN CASE s.res = "FOUND"   -> C(s.slot) = EQ
       [] s.res = "SMALLER" -> s.slot = 1 /\ C(1) = LT
       [] s.res = "BIGGER"  -> s.slot = n + 1 /\ C(n) = GT
       [] s.res = "BETWEEN" -> 1 < s.slot /\ s.slot <= n /\ C(s.slot - 1) = GT /\ C(s.slot) = LT
       [] OTHER -> FALSE
LeafCorrect == \A m \in Modes :
  (st[m].done /\ sc.node = "leaf" /\ ~sc.f1 /\ ~sc.fn /\ ~sc.merges) => LeafRight(st[m])

(* the image path is taken where the PR intends it (not vacuous) *)
ImageUsedWhenAllowed ==
  (AllDone /\ Guard(sc) /\ \A i \in DOMAIN sc.ovf : ~sc.ovf[i] /\ Len(sc.keys) > 1) => st["new"].imgs > 0
ImageNeverWithConv == (AllDone /\ sc.bound = "conv") => st["new"].imgs = 0

Termination == <>AllDone

(* -------------- whole-range lemmas (checked as ASSUMEs) --------------- *)
(* every SHORT and INTEGER pair, BIGINT on its edges, both orders *)
Sample(t) == IF t = "BIGINT" THEN Interesting(t) \cup {TMin(t) + 1, TMax(t) - 1, -2, 2, 2^14, -(2^14) - 1}
             ELSE TMin(t)..TMax(t)
ASSUME Mutation = "none" =>
  \A t \in Types, d \in BOOLEAN : \A v, r \in Sample(t) :
    LET s == [v |-> v, desc |-> d, bound |-> "direct"]
    IN /\ DecodeSigned(Encode(r, Size(t))) = r
       /\ IntCmp(s, Encode(r, Size(t))) = GenCmp(s, r)
(* the helper finds the key where develop's reader did, for every header *)
ASSUME Mutation = "none" =>
  \A u, co, ins, del \in BOOLEAN :
    LET h == [uniq |-> u, coid |-> co, ins |-> ins, del |-> del]
    IN /\ HelperOffset(h) = SeqOffset(h)
       /\ \A t \in Types : \A v \in Interesting(t) :
            DecodeSigned(Extract(LeafCells(h, FALSE, t, v), HelperOffset(h), Size(t))) = v
=============================================================================
