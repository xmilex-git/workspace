------------------------------ MODULE KeyRewind ------------------------------
(***************************************************************************)
(* CBRD-28030: an index range scan that is rewound (or restarted from the  *)
(* root) after it stopped inside a key's overflow OIDs.                    *)
(*                                                                         *)
(* One thread runs NOut scan sessions over one B-tree scan structure      *)
(* (bts).  A session is the inner index scan for one outer row of a SEMI / *)
(* ANTI join (or one side of an index MIN/MAX boundary scan).  The B-tree *)
(* fills an OID buffer key by key: a key's leaf-record objects, then its   *)
(* overflow pages.  A full buffer interrupts the key in the middle of its  *)
(* overflow chain and marks it partially processed; the next iteration    *)
(* resumes there and skips the leaf record.  The consumer reads the buffer *)
(* in order and stops at its first matching object; the scan is then     *)
(* rewound (BTREE_RESET_SCAN) or reset (bts_reset_scan) for the next      *)
(* session, which starts again from the root.                              *)
(*                                                                         *)
(* Objects are numbered 1..NObj in scan order: key k holds                 *)
(* Base(k)+1 .. Base(k)+KeyLen(k), its leaf record first, then NPg(k) pages  *)
(* of PG objects.  Every object is visible (vacuum and MVCC are outside   *)
(* this model; see MAP.md).                                                *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS NK, LeafN, PG, NPG, OvfKeys, SOFT, CAP, NOut, ResetKinds, Fix, Mutant

VARIABLES rlo, rhi, M, j, bpc, started, ck, kcons, flag, anchor, lastvis, ovp, pg, buf, cons, bufv,
          ex, bad, lost, nopos, res, hitIn, resumed, nread

\* Types for Apalache (tools/tla/apalache-types writes them into the declarations).
\* apalache-type: NK Int
\* apalache-type: LeafN Int
\* apalache-type: PG Int
\* apalache-type: NPG Int
\* apalache-type: OvfKeys Set(Int)
\* apalache-type: SOFT Int
\* apalache-type: CAP Int
\* apalache-type: NOut Int
\* apalache-type: ResetKinds Set(Str)
\* apalache-type: Fix Str
\* apalache-type: Mutant Str
\* apalache-type: rlo Int -> Int
\* apalache-type: rhi Int -> Int
\* apalache-type: M Int -> Set(Int)
\* apalache-type: j Int
\* apalache-type: bpc Str
\* apalache-type: started Bool
\* apalache-type: ck Int
\* apalache-type: kcons Bool
\* apalache-type: flag Bool
\* apalache-type: anchor Int
\* apalache-type: lastvis Int
\* apalache-type: ovp Int
\* apalache-type: pg Int
\* apalache-type: buf Int
\* apalache-type: cons Int
\* apalache-type: bufv Int -> Int
\* apalache-type: ex Int
\* apalache-type: bad Bool
\* apalache-type: lost Bool
\* apalache-type: nopos Bool
\* apalache-type: res Int -> Str
\* apalache-type: hitIn Int -> Str
\* apalache-type: resumed Bool
\* apalache-type: nread Int

ASSUME /\ NK \in Nat \ {0} /\ LeafN \in Nat \ {0} /\ PG \in Nat \ {0} /\ NPG \in Nat
       /\ OvfKeys \subseteq 1..NK /\ NOut \in Nat \ {0}
       /\ SOFT \in Nat \ {0} /\ CAP \in Nat /\ CAP >= SOFT /\ CAP >= LeafN + PG
       /\ ResetKinds \subseteq {"rewind", "flip"} /\ ResetKinds # {}
       /\ Fix \in {"none", "macro", "macro_bts", "start"}
       /\ Mutant \in {"none", "clear_every_call"}

\* Key structure.  The model's sizes are uniform; a trace cfg substitutes the recorded run's
\* per-key sizes for these operators (KeyRewindTrace.tla).
NPg(k) == IF k \in OvfKeys THEN NPG ELSE 0
LeafOf(k) == LeafN
PgCnt(k, p) == PG
KeyLen(k) == LeafN + NPg(k) * PG
Base(k) == (k - 1) * LeafN + Cardinality({i \in OvfKeys : i < k}) * NPG * PG
PageStart(k, p) == Base(k) + LeafN + (p - 1) * PG
\* the page after the one ending with anchor a (anchors are page-final here: every object is visible)
AnchorNext(k, a) == (a - Base(k) - LeafN - 1) \div PG + 2
NObj == Base(NK) + KeyLen(NK)
\* constant-bounded universes for Apalache (P59): U bounds NObj without Cardinality
U == NK * (LeafN + NPG * PG)
Objs == {o \in 1..U : o <= NObj}
Objs0 == {o \in 0..U : o <= NObj}
\* a session's matching objects: none or one (a skipped object that is the only match exposes every skip)
MatchSets == {{}} \cup {{o} : o \in Objs}
ExRange == {o \in 1..(U + 1) : o <= NObj + 1}
BufMax == CAP + LeafN
FirstPg(k) == IF NPg(k) > 0 THEN PgCnt(k, 1) ELSE 0
PageObj(k, p, i) == PageStart(k, p) + i
IsLeafObj(k, o) == Base(k) < o /\ o <= Base(k) + LeafOf(k)
IsOvfObj(k, o) == Base(k) + LeafOf(k) < o /\ o <= Base(k) + KeyLen(k)
RangeFirst(s) == Base(rlo[s]) + 1
RangeLast(s) == Base(rhi[s]) + KeyLen(rhi[s])
InRange(s, o) == RangeFirst(s) <= o /\ o <= RangeLast(s)


data == <<rlo, rhi, M>>
scan == <<started, ck, kcons, flag, anchor, lastvis, ovp, pg>>
ghost == <<ex, bad, lost, nopos, res, hitIn, resumed, nread>>
vars == <<data, j, bpc, scan, buf, cons, bufv, ghost>>

Init ==
  /\ rlo \in [1..NOut -> 1..NK]
  /\ rhi \in [1..NOut -> 1..NK]
  /\ \A s \in 1..NOut : rlo[s] <= rhi[s]
  /\ M \in [1..NOut -> MatchSets]
  /\ j = 1
  /\ bpc = "locate"          \* BTREE_INIT_SCAN at open: every field clean
  /\ started = FALSE /\ ck = 1 /\ kcons = FALSE /\ flag = FALSE
  /\ anchor = 0 /\ lastvis = 0 /\ ovp = 0 /\ pg = 1
  /\ buf = 0 /\ cons = 0 /\ bufv = [i \in 1..BufMax |-> 0]
  /\ ex = RangeFirst(1)
  /\ bad = FALSE /\ lost = FALSE /\ nopos = FALSE
  /\ res = [s \in 1..NOut |-> "none"]
  /\ hitIn = [s \in 1..NOut |-> "none"]
  /\ resumed = FALSE
  /\ nread = 0

\* The buffer receives objects start .. start+n-1; the ghost ex is the next object scan order expects.
Fill(start, n) ==
  /\ bad' = (bad \/ start # ex)
  /\ ex' = start + n
  /\ bufv' = [i \in 1..BufMax |-> IF buf < i /\ i <= buf + n THEN start + (i - buf - 1) ELSE bufv[i]]
  /\ buf' = buf + n
  /\ nread' = nread + n

(* btree_range_scan_start: a scan not started finds its first key from the root. *)
Start ==
  /\ bpc = "locate" /\ ~started
  /\ started' = TRUE /\ ck' = rlo[j] /\ kcons' = FALSE /\ bpc' = "key"
  /\ flag' = IF Fix = "start" THEN FALSE ELSE flag
  /\ UNCHANGED <<data, j, anchor, lastvis, ovp, pg, buf, cons, bufv, ghost>>

(* btree_range_scan_advance_over_filtered_keys: the next key of the range. *)
Advance ==
  /\ bpc = "locate" /\ started /\ kcons /\ ck < rhi[j]
  /\ ck' = ck + 1 /\ kcons' = FALSE /\ bpc' = "key"
  /\ UNCHANGED <<data, j, started, flag, anchor, lastvis, ovp, pg, buf, cons, bufv, ghost>>

(* end_scan: past the range's last key; is_scan_started and C_vpid are cleared. *)
EndScan ==
  /\ bpc = "locate" /\ started /\ kcons /\ ck = rhi[j]
  /\ bpc' = "end" /\ started' = FALSE
  /\ UNCHANGED <<data, j, ck, kcons, flag, anchor, lastvis, ovp, pg, buf, cons, bufv, ghost>>

(* btree_range_scan_resume: the key the last iteration stopped in. *)
ResumeKey ==
  /\ bpc = "locate" /\ started /\ ~kcons
  /\ bpc' = "key"
  /\ UNCHANGED <<data, j, scan, buf, cons, bufv, ghost>>

(* btree_range_scan_select_visible_oids, key not partially processed: soft capacity check. *)
SoftStop ==
  /\ bpc = "key" /\ ~flag
  /\ buf > 0 /\ buf <= SOFT /\ buf + LeafOf(ck) + FirstPg(ck) > SOFT
  /\ bpc' = "iterend"
  /\ UNCHANGED <<data, j, scan, buf, cons, bufv, ghost>>

(* ... leaf record objects, then the overflow chain from its first page. *)
LeafFill ==
  /\ bpc = "key" /\ ~flag
  /\ ~(buf > 0 /\ buf <= SOFT /\ buf + LeafOf(ck) + FirstPg(ck) > SOFT)
  /\ Fill(Base(ck) + 1, LeafOf(ck))
  /\ lastvis' = 0 /\ pg' = 1 /\ bpc' = "page"
  /\ UNCHANGED <<data, j, started, ck, kcons, flag, anchor, ovp, cons, lost, nopos, res, hitIn, resumed>>

(* ... key partially processed: skip the leaf record and resume in the overflow chain
   (non-unique: btree_ovf_scan_locate_resume by O_last_oid; unique: the page after O_vpid). *)
KeyResume ==
  /\ bpc = "key" /\ flag
  /\ flag' = FALSE /\ bpc' = "page"
  /\ nopos' = (nopos \/ ovp # ck)
  /\ resumed' = TRUE
  /\ pg' \in IF anchor = 0 THEN {1}
             ELSE IF IsOvfObj(ck, anchor) THEN {AnchorNext(ck, anchor)}
             ELSE {p \in 1..(NPG + 1) : p <= NPg(ck) + 1}   \* an anchor of another key's chain lands anywhere in this one
  /\ UNCHANGED <<data, j, started, ck, kcons, anchor, lastvis, ovp, buf, cons, bufv, ex, bad, lost, res, hitIn, nread>>

(* the whole chain is read: O_vpid cleared, key consumed. *)
KeyDone ==
  /\ bpc = "page" /\ pg > NPg(ck)
  /\ kcons' = TRUE /\ ovp' = 0 /\ bpc' = "locate"
  /\ UNCHANGED <<data, j, started, ck, flag, anchor, lastvis, pg, buf, cons, bufv, ghost>>

(* hard capacity: the next page does not fit; save the resume position and end the iteration. *)
Interrupt ==
  /\ bpc = "page" /\ pg <= NPg(ck) /\ buf + PgCnt(ck, pg) > CAP
  /\ ovp' = ck /\ anchor' = lastvis /\ flag' = TRUE /\ bpc' = "iterend"
  /\ UNCHANGED <<data, j, started, ck, kcons, lastvis, pg, buf, cons, bufv, ghost>>

PageFill ==
  /\ bpc = "page" /\ pg <= NPg(ck) /\ buf + PgCnt(ck, pg) <= CAP
  /\ Fill(PageObj(ck, pg, 1), PgCnt(ck, pg))
  /\ lastvis' = PageObj(ck, pg, PgCnt(ck, pg)) /\ pg' = pg + 1
  /\ UNCHANGED <<data, j, bpc, started, ck, kcons, flag, anchor, ovp, cons, lost, nopos, res, hitIn, resumed>>

(* the executor reads the next buffered OID; a match stops the session (single_fetched). *)
Consume ==
  /\ bpc \in {"iterend", "end"} /\ cons < buf
  /\ cons' = cons + 1
  /\ LET o == bufv[cons + 1] IN
       IF o \in M[j]
       THEN /\ res' = [res EXCEPT ![j] = "match"]
            /\ hitIn' = [hitIn EXCEPT ![j] = IF \E k \in 1..NK : IsLeafObj(k, o) THEN "leaf" ELSE "ovf"]
            /\ bpc' = "stopped"
       ELSE UNCHANGED <<res, hitIn, bpc>>
  /\ UNCHANGED <<data, j, scan, buf, bufv, ex, bad, lost, nopos, resumed, nread>>

(* buffer drained, scan not ended: the next btree_range_scan call (counters reset at its entry). *)
NextIter ==
  /\ bpc = "iterend" /\ cons = buf
  /\ buf' = 0 /\ cons' = 0 /\ bpc' = "locate"
  /\ flag' = IF Mutant = "clear_every_call" THEN FALSE ELSE flag
  /\ UNCHANGED <<data, j, started, ck, kcons, anchor, lastvis, ovp, pg, bufv, ghost>>

(* scan ended with no match. *)
EndNoMatch ==
  /\ bpc = "end" /\ cons = buf
  /\ res' = [res EXCEPT ![j] = "nomatch"]
  /\ lost' = (lost \/ nread # RangeLast(j) - RangeFirst(j) + 1)
  /\ bpc' = "stopped"
  /\ UNCHANGED <<data, j, scan, buf, cons, bufv, ex, bad, nopos, hitIn, resumed, nread>>

NextSession ==
  /\ j' = j + 1 /\ bpc' = "locate" /\ buf' = 0 /\ cons' = 0
  /\ ex' = RangeFirst(j + 1)
  /\ nread' = 0
  /\ started' = FALSE

(* qexec_reset_sa_inner_scan_block -> scan_reset_scan_block -> BTREE_RESET_SCAN *)
Rewind ==
  /\ bpc = "stopped" /\ j < NOut /\ "rewind" \in ResetKinds
  /\ NextSession
  /\ anchor' = 0 /\ lastvis' = 0 /\ ovp' = 0
  /\ flag' = IF Fix \in {"macro", "macro_bts"} THEN FALSE ELSE flag
  /\ UNCHANGED <<data, ck, kcons, pg, bufv, bad, lost, nopos, res, hitIn, resumed>>

(* qexec_intprt_fnc, index MIN/MAX boundary scan: bts_reset_scan, then S_GO_BACKWARD *)
Flip ==
  /\ bpc = "stopped" /\ j < NOut /\ "flip" \in ResetKinds
  /\ NextSession
  /\ flag' = IF Fix = "macro_bts" THEN FALSE ELSE flag
  /\ UNCHANGED <<data, ck, kcons, anchor, lastvis, ovp, pg, bufv, bad, lost, nopos, res, hitIn, resumed>>

Done == bpc = "stopped" /\ j = NOut /\ UNCHANGED vars

Next ==
  \/ Start \/ Advance \/ EndScan \/ ResumeKey
  \/ SoftStop \/ LeafFill \/ KeyResume \/ KeyDone \/ Interrupt \/ PageFill
  \/ Consume \/ NextIter \/ EndNoMatch \/ Rewind \/ Flip \/ Done

Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* Properties *)

TypeOK ==
  /\ rlo \in [1..NOut -> 1..NK]
  /\ rhi \in [1..NOut -> 1..NK]
  /\ M \in [1..NOut -> SUBSET Objs]
  /\ j \in 1..NOut
  /\ bpc \in {"locate", "key", "page", "iterend", "end", "stopped"}
  /\ started \in BOOLEAN
  /\ ck \in 1..NK
  /\ kcons \in BOOLEAN
  /\ flag \in BOOLEAN
  /\ anchor \in Objs0
  /\ lastvis \in Objs0
  /\ ovp \in 0..NK
  /\ pg \in 1..(NPG + 2)
  /\ buf \in 0..BufMax
  /\ cons \in 0..BufMax
  /\ bufv \in [1..BufMax -> Objs0]
  /\ ex \in ExRange
  /\ bad \in BOOLEAN
  /\ lost \in BOOLEAN
  /\ nopos \in BOOLEAN
  /\ res \in [1..NOut -> {"none", "match", "nomatch"}]
  /\ hitIn \in [1..NOut -> {"none", "leaf", "ovf"}]
  /\ resumed \in BOOLEAN
  /\ nread \in 0..U

\* C1: every finished session answered SEMI (match) / ANTI (nomatch) as a full read of its range does.
SemiAntiCorrect ==
  \A s \in 1..NOut :
    res[s] # "none" => ((res[s] = "match") <=> (\E o \in M[s] : InRange(s, o)))

\* C2: the buffer receives the range's objects in scan order, none skipped or repeated, and an
\* ended scan has read all of them.
ScanInOrder == ~bad
ScanComplete == ~lost

\* C3: the leaf record is skipped only for the key whose resume position the last iteration saved.
ResumeOwnKey == ~nopos

\* witnesses
NotStoppedPartial == ~(bpc = "stopped" /\ flag)
NotLeafAfterOvf == ~(NOut >= 2 /\ hitIn[1] = "ovf" /\ hitIn[2] = "leaf")
NotResumedMatch == ~(resumed /\ \E s \in 1..NOut : res[s] = "match")
NotFlipStale == ~(bpc = "locate" /\ ~started /\ flag /\ j > 1)

-----------------------------------------------------------------------------
(* Inductive invariant (the fixed design: Fix = "start" or "macro_bts"). *)

InvBuf == cons <= buf /\ buf <= CAP
InvRange == \A s \in 1..NOut : rlo[s] <= rhi[s]
InvCk == started => rlo[j] <= ck /\ ck <= rhi[j]
\* where the scan stands, as the next object scan order expects
InvKeyStart == (started /\ bpc \in {"locate", "key", "iterend"} /\ ~kcons /\ ~flag) => ex = Base(ck) + 1
InvPartial == (started /\ flag) =>
  /\ ~kcons /\ ovp = ck /\ bpc \in {"locate", "key", "iterend", "stopped"}
  /\ lastvis = anchor
  /\ (bpc \in {"locate", "key"} => buf = 0)
  /\ (anchor # 0 => (anchor - Base(ck) - LeafOf(ck)) % PG = 0)
  /\ (anchor = 0 => ex = PageObj(ck, 1, 1))
  /\ (anchor # 0 => IsOvfObj(ck, anchor) /\ ex = anchor + 1 /\ AnchorNext(ck, anchor) <= NPg(ck))
InvPage == bpc = "page" =>
  /\ started /\ ~kcons /\ ~flag /\ pg <= NPg(ck) + 1
  /\ ex = PageObj(ck, pg, 1)
  /\ (lastvis # 0 => lastvis = ex - 1 /\ IsOvfObj(ck, lastvis))
  /\ (lastvis = 0 => pg = 1)
InvConsumed == (started /\ kcons) => ex = Base(ck) + KeyLen(ck) + 1 /\ ~flag /\ ovp = 0 /\ bpc = "locate"
InvNotStarted == (~started /\ bpc = "locate") => ex = RangeFirst(j) /\ buf = 0
InvEnd == bpc = "end" => ex = RangeLast(j) + 1 /\ ~flag /\ ~started
InvStartedPc == bpc \in {"key", "page", "iterend"} => started
InvFix == (~started /\ flag) => Fix = "start" /\ bpc \in {"locate", "stopped"}
\* the buffer holds the objects just before ex, in order, all of the current range
InvBufObjs == \A i \in 1..BufMax : i <= buf => bufv[i] = ex - buf + i - 1 /\ InRange(j, bufv[i])
\* no object the session has consumed before its stop matched
InvNoMatchYet == bpc # "stopped" =>
  \A o \in Objs : (RangeFirst(j) <= o /\ o < ex - buf + cons) => o \notin M[j]
InvRes == \A s \in 1..NOut : (s > j => res[s] = "none") /\ (s < j => res[s] # "none")
\* the objects read this session are exactly those before ex
InvRead == nread = ex - RangeFirst(j)
InvResCur == (res[j] # "none") = (bpc = "stopped")

IndInv ==
  /\ TypeOK
  /\ InvBuf
  /\ InvRange
  /\ InvCk
  /\ InvKeyStart
  /\ InvPartial
  /\ InvPage
  /\ InvConsumed
  /\ InvNotStarted
  /\ InvEnd
  /\ InvStartedPc
  /\ InvFix
  /\ InvBufObjs
  /\ InvNoMatchYet
  /\ InvRes
  /\ InvResCur
  /\ InvRead
  /\ ScanInOrder
  /\ ScanComplete
  /\ ResumeOwnKey
  /\ SemiAntiCorrect

\* Apalache: the inductive check runs at the main cfg's sizes (ranges over NObj need constant bounds, P59).
CInit ==
  /\ NK = 2 /\ LeafN = 1 /\ PG = 2 /\ NPG = 2 /\ OvfKeys = {1, 2} /\ SOFT = 3 /\ CAP = 3 /\ NOut = 2
  /\ ResetKinds = {"rewind", "flip"} /\ Fix = "start" /\ Mutant = "none"
=============================================================================
