------------------------------- MODULE GcBuf -------------------------------
(* PR CUBRID/cubrid#8398 (CBRD-27926) at ea06eca48: the GROUP_CONCAT accumulator
   buffer and the capacity the aggregate node remembers for it.

   The accumulator DB_VALUE owns a private-heap buffer; db_string_append appends in
   place when the bytes fit the capacity the node remembers (info.group_concat.capacity
   for info.group_concat.buf) and otherwise grows it to the next power of two of the
   Caps chain, clamped at group_concat_max_len + 1 (qstr_reserve). The capacity counts
   only while the accumulator still holds the buffer it was recorded for
   (qdata_group_concat_capacity), and the sites that replace the buffer reset it to 0.

   Nodes: "o" is the aggregate node of the query's own XASL (serial groups, the GROUP BY
   dimension list whose value moves to the output list, the coordinator of a parallel
   BUILDVALUE scan); each member of Workers is a parallel scan worker's clone of it, reused
   by every pass and every execution of the cached clone. Each node is touched by one thread at a time (single owner), so one call of a
   code function on one node is one step; the allocator is shared and hands out any free
   address, which is how a freed buffer's address comes back (ABA).

   Heaps: a buffer lives on the heap that allocated it ("coord" the coordinator's private
   heap, "h0" malloc while workers are alive, "wk" a worker's private heap) and must be
   freed by the same one (rehome_agg_value's contract). *)
EXTENDS Naturals, FiniteSets

CONSTANTS NA, Max, Base, Caps, V, R, P, G, TM, SpareMax, MaxFaults, Workers, Mutant

\* Types for Apalache (tools/tla/apalache-types writes them into the declarations).
\* apalache-type: NA Int
\* apalache-type: Max Int
\* apalache-type: Base Int
\* apalache-type: Caps Set(Int)
\* apalache-type: V Int
\* apalache-type: R Int
\* apalache-type: P Int
\* apalache-type: G Int
\* apalache-type: TM Int
\* apalache-type: SpareMax Int
\* apalache-type: MaxFaults Int
\* apalache-type: Workers Set(Str)
\* apalache-type: Mutant Str
\* apalache-type: heap Int -> Int
\* apalache-type: hp Int -> Str
\* apalache-type: filled Int -> Int
\* apalache-type: grown Int -> Bool
\* apalache-type: str Str -> Int
\* apalache-type: size Str -> Int
\* apalache-type: cnt Str -> Int
\* apalache-type: rows Str -> Int
\* apalache-type: typ Str -> Str
\* apalache-type: pv Str -> Int
\* apalache-type: ps Str -> Int
\* apalache-type: mid Str -> Bool
\* apalache-type: ibuf Str -> Int
\* apalache-type: icap Str -> Int
\* apalache-type: ph Str
\* apalache-type: wph Str -> Str
\* apalache-type: merger Str
\* apalache-type: mrows Int
\* apalache-type: passes Int
\* apalache-type: tasks Int
\* apalache-type: grp Int
\* apalache-type: err Bool
\* apalache-type: faults Int
\* apalache-type: ext Set(Int)
\* apalache-type: ovf Bool
\* apalache-type: uaf Bool
\* apalache-type: badFree Bool
\* apalache-type: wrongHeap Bool
\* apalache-type: leak Bool
\* apalache-type: slow Bool
\* apalache-type: seen Set(Str)

VARIABLES heap, hp, filled, grown, str, size, cnt, rows, typ, pv, ps, mid, ibuf, icap,
          ph, wph, merger, mrows, passes, tasks, grp, err, faults, ext, ovf, uaf, badFree, wrongHeap,
          leak, slow, seen

vars == <<heap, hp, filled, grown, str, size, cnt, rows, typ, pv, ps, mid, ibuf, icap,
          ph, wph, merger, mrows, passes, tasks, grp, err, faults, ext, ovf, uaf, badFree, wrongHeap,
          leak, slow, seen>>

Mutants == {"none", "develop", "noResetFirst", "noResetRehome", "noResetClone", "noResetInit",
            "noResetReplace", "noResetCoerce", "noPtrCheck", "noBufRecord", "noClamp", "noTerm",
            "noCopy", "freeBeforeCopy", "wrongHeapMerge", "twiceNeed", "noFreeOld"}

ASSUME Assm ==
  /\ NA \in Nat /\ NA >= 1 /\ Max \in Nat /\ Max >= 1 /\ V \in Nat /\ V >= 1
  /\ R \in Nat /\ P \in Nat /\ G \in Nat /\ TM \in Nat /\ SpareMax \in Nat /\ MaxFaults \in Nat
  /\ Mutant \in Mutants
  /\ Workers # {} /\ "o" \notin Workers /\ "none" \notin Workers
  \* the doubling chain qstr_reserve walks (64, 128, ...): starts at Base, doubles, reaches Limit
  /\ Caps \subseteq Nat /\ Base \in Caps /\ Base >= 1
  /\ \A c \in Caps : Base <= c
  /\ \A a, b \in Caps : a < b => 2 * a <= b
  /\ \A b \in Caps : b > Base => \E a \in Caps : 2 * a = b
  /\ \E c \in Caps : c >= Max + 1

Addr == 1 .. NA
Nodes == {"o"} \cup Workers
Heaps == {"none", "h0", "coord", "wk"}
Limit == Max + 1
MaxOf(a, b) == IF a >= b THEN a ELSE b
MinOf(a, b) == IF a <= b THEN a ELSE b

\* qstr_reserve: the smallest member of the chain that holds need ...
IsP2(p, need) == p \in Caps /\ need <= p /\ \A q \in Caps : need <= q => p <= q
\* ... clamped at limit unless need is larger (new_capacity = MAX (needed, limit))
IsNewCap(c, need) ==
  \E p \in Caps : IsP2(p, need) /\ c = (IF p > Limit THEN MaxOf(need, Limit) ELSE p)
CapCands == Caps \cup (1 .. 2 * Limit)

\* the heap a node's buffer is allocated on and freed by
Ctx(n) == IF n \in Workers THEN "wk"
          ELSE IF ph = "par" THEN (IF Mutant = "wrongHeapMerge" THEN "wk" ELSE "h0")
          ELSE "coord"
\* where the code expects the node's buffer to live (rehome_agg_value's contract)
Loc(n) == IF n \in Workers THEN "wk" ELSE IF ph = "par" THEN "h0" ELSE "coord"
\* a node that may run its own calls now
Active(n) == IF n = "o" THEN ph = "scan" \/ (ph = "par" /\ merger # "none")
             ELSE wph[n] = "run" /\ merger # n    \* a worker in write_finalize has ended its scan

\* ---------------------------------------------------------------------------
\* Init: an execution has not started; nothing is allocated; both nodes hold NULL
\* (stx_build_aggregate_type: buf = NULL, capacity = 0).
Init ==
  /\ heap = [a \in Addr |-> 0] /\ hp = [a \in Addr |-> "none"]
  /\ filled = [a \in Addr |-> 0] /\ grown = [a \in Addr |-> FALSE]
  /\ str = [n \in Nodes |-> 0] /\ size = [n \in Nodes |-> 0]
  /\ cnt = [n \in Nodes |-> 0] /\ rows = [n \in Nodes |-> 0]
  /\ typ = [n \in Nodes |-> "var"] /\ pv = [n \in Nodes |-> 0] /\ ps = [n \in Nodes |-> 0]
  /\ mid = [n \in Nodes |-> FALSE]
  /\ ibuf = [n \in Nodes |-> 0] /\ icap = [n \in Nodes |-> 0]
  /\ ph = "start" /\ wph = [w \in Workers |-> "idle"] /\ merger = "none" /\ mrows = 0
  /\ passes = 0 /\ tasks = 0 /\ grp = 0 /\ err = FALSE /\ faults = 0
  /\ ext = {}
  /\ ovf = FALSE /\ uaf = FALSE /\ badFree = FALSE /\ wrongHeap = FALSE /\ leak = FALSE
  /\ slow = FALSE /\ seen = {}

\* ---------------------------------------------------------------------------
\* Heap updates: allocate a (size c, heap h, contents f, grown g) and free old in one step;
\* a = 0 or old = 0 means none (addresses are 1 .. NA).
HeapAF(a, c, old) == [x \in Addr |-> IF x = a THEN c ELSE IF x = old THEN 0 ELSE heap[x]]
HpAF(a, h, old) == [x \in Addr |-> IF x = a THEN h ELSE IF x = old THEN "none" ELSE hp[x]]
FillAF(a, f, old) == [x \in Addr |-> IF x = a THEN f ELSE IF x = old THEN 0 ELSE filled[x]]
GrownAF(a, g, old) == [x \in Addr |-> IF x = a THEN g ELSE IF x = old THEN FALSE ELSE grown[x]]
BadFree(old) == old # 0 /\ heap[old] = 0
WrongHeap(old, h) == old # 0 /\ hp[old] # h
\* contents a copy of node n's string carries: its bytes, or garbage (Limit + 1, never a size)
CopyOf(n, newsize) ==
  IF Mutant # "noCopy" /\ (str[n] = 0 \/ filled[str[n]] = size[n]) THEN newsize ELSE Limit + 1
ReadsFreed(n) == str[n] # 0 /\ heap[str[n]] = 0
\* the capacity qstr_reserve gives a buffer that must hold req bytes
CapRule(c, need, req) ==
  IF Mutant = "develop" THEN c = need
  ELSE IF Mutant = "twiceNeed" THEN c = 2 * req
  ELSE IF Mutant = "noClamp" THEN \E p \in Caps : IsP2(p, req) /\ c = p
  ELSE IsNewCap(c, req)

\* ---------------------------------------------------------------------------
\* Group start (qexec_start_mainblock_iterations / qexec_gby_start_group ->
\* qdata_initialize_aggregate_list): curr_cnt = 0, capacity = 0. The value was cleared
\* (or moved out) when the previous group ended, so the node holds no buffer.
OInit ==
  /\ ph = "start" /\ grp < G
  /\ cnt' = [cnt EXCEPT !["o"] = 0] /\ rows' = [rows EXCEPT !["o"] = 0]
  /\ icap' = IF Mutant = "noResetInit" THEN icap ELSE [icap EXCEPT !["o"] = 0]
  /\ typ' = [typ EXCEPT !["o"] = "var"]
  /\ ph' = "scan" /\ passes' = 0
  /\ UNCHANGED <<heap, hp, filled, grown, str, size, pv, ps, mid, ibuf, wph, merger, mrows, tasks, grp,
                 err, faults, ext, ovf, uaf, badFree, wrongHeap, leak, slow, seen>>

\* One qdata_concatenate_dbval call reaches node n with v bytes to append (a row's value after
\* the CBRD-27583 cast, a separator, or a worker's partial string at the merge). The first call
\* of a group runs qdata_group_concat_first_value's head before it:
\* db_string_make_empty_typed_string allocates a 1-byte empty string (CHAR or BIT when the
\* domain is fixed), then capacity = 0. During a merge the coordinator's node takes the
\* separator and the worker's string (qdata_group_concat_value: at most two calls).
FirstAt(n, a, t) ==
  /\ heap[a] = 0
  /\ heap' = [heap EXCEPT ![a] = 1] /\ hp' = [hp EXCEPT ![a] = Ctx(n)]
  /\ filled' = [filled EXCEPT ![a] = 0] /\ grown' = [grown EXCEPT ![a] = FALSE]
  /\ leak' = (leak \/ str[n] # 0)
  /\ str' = [str EXCEPT ![n] = a] /\ size' = [size EXCEPT ![n] = 0]
  /\ typ' = [typ EXCEPT ![n] = t]
  /\ icap' = IF Mutant = "noResetFirst" THEN icap ELSE [icap EXCEPT ![n] = 0]
  /\ seen' = seen \cup (IF ibuf[n] = a /\ icap[n] > 0 THEN {"stale"} ELSE {})
                  \cup (IF t = "char" THEN {"charstart"} ELSE {})
RowStart(n, v) ==
  /\ Active(n) /\ ~err /\ pv[n] = 0 /\ ps[n] = 0
  /\ IF n = "o" /\ ph = "par"
     THEN /\ cnt["o"] > 0 /\ mrows < 2
          /\ mrows' = mrows + 1 /\ UNCHANGED <<rows, cnt>>
     ELSE /\ rows[n] < R
          /\ rows' = [rows EXCEPT ![n] = @ + 1] /\ cnt' = [cnt EXCEPT ![n] = @ + 1]
          /\ UNCHANGED mrows
  /\ pv' = [pv EXCEPT ![n] = v]
  /\ IF cnt[n] = 0
     THEN \E a \in Addr, t \in {"var", "char"} : FirstAt(n, a, t)
     ELSE UNCHANGED <<heap, hp, filled, grown, leak, str, size, typ, icap, seen>>
  /\ UNCHANGED <<ps, mid, ibuf, ph, wph, merger, passes, tasks, grp, err, faults, ext, ovf, uaf, badFree,
                 wrongHeap, slow>>

\* qstr_reserve's growth: a new buffer of the chain's capacity (develop: the exact size
\* db_string_concatenate allocates), the old bytes copied, the old buffer freed on the
\* current heap, capacity = the new size. req is what the code asked for (need without
\* the terminator for noTerm); newsize the string's size after the append.
GrowAt(n, need, req, newsize, a, c) ==
  LET s == str[n]
      fs == IF Mutant = "noFreeOld" THEN 0 ELSE s    \* the buffer the step frees
  IN
    /\ heap[a] = 0 /\ CapRule(c, need, req)
    /\ heap' = HeapAF(a, c, fs) /\ hp' = HpAF(a, Ctx(n), fs)
    /\ filled' = FillAF(a, CopyOf(n, newsize), fs) /\ grown' = GrownAF(a, TRUE, fs)
    /\ badFree' = (badFree \/ BadFree(fs))
    /\ wrongHeap' = (wrongHeap \/ WrongHeap(fs, Ctx(n)))
    /\ uaf' = (uaf \/ ReadsFreed(n) \/ (Mutant = "freeBeforeCopy" /\ s # 0 /\ size[n] > 0))
    \* overflow: the bytes written (the terminator included) past what was allocated
    /\ ovf' = (ovf \/ need > c)
    /\ slow' = (slow \/ (s # 0 /\ grown[s] /\ (req <= heap[s] \/ (c < 2 * heap[s] /\ c < Limit))))
    /\ str' = [str EXCEPT ![n] = a] /\ size' = [size EXCEPT ![n] = newsize]
    /\ icap' = [icap EXCEPT ![n] = c]
    /\ seen' = seen \cup (IF c = Limit /\ c \notin Caps THEN {"clamp"} ELSE {}) \cup {"grow"}
Grow(n, need, req, newsize) == \E a \in Addr, c \in CapCands : GrowAt(n, need, req, newsize, a, c)

\* an append that fits the capacity: the bytes go to the end of the buffer
InPlace(n, need, newsize, cap0) ==
  LET s == str[n] IN
  /\ heap' = heap /\ hp' = hp /\ grown' = grown
  /\ filled' = [filled EXCEPT ![s] = IF filled[s] = size[n] THEN newsize ELSE Limit + 1]
  /\ ovf' = (ovf \/ heap[s] = 0 \/ need > heap[s])
  /\ size' = [size EXCEPT ![n] = newsize] /\ icap' = [icap EXCEPT ![n] = cap0]
  /\ seen' = seen \cup {"inplace"}
  /\ UNCHANGED <<str, uaf, badFree, wrongHeap, slow>>

\* qstr_reserve's allocation fails (OOM): the value is unchanged and the query ends with the error
Fail(n, cap0) ==
  /\ faults < MaxFaults
  /\ err' = TRUE /\ faults' = faults + 1
  /\ icap' = [icap EXCEPT ![n] = cap0]
  /\ seen' = seen \cup {"oom"}
  /\ UNCHANGED <<heap, hp, filled, grown, str, size, ovf, uaf, badFree, wrongHeap, slow>>

Cap0(n) == IF mid[n] \/ ibuf[n] = str[n] \/ Mutant = "noPtrCheck" THEN icap[n] ELSE 0
Room(n) == Max - size[n]
Trunc(n) == pv[n] > Room(n)
AddOf(n, sp) == IF Trunc(n) THEN Room(n) - sp ELSE pv[n]
NeedOf(n, sp) == size[n] + AddOf(n, sp) + 1
ReqOf(n, sp) == IF Mutant = "noTerm" THEN NeedOf(n, sp) - 1 ELSE NeedOf(n, sp)
SpareOf(n, sp) == IF Trunc(n) THEN sp ELSE 0
ACommon == UNCHANGED <<cnt, rows, ph, wph, merger, mrows, passes, tasks, grp, ext>>

\* res_size >= max_allowed_size: nothing appended
AFull(n) ==
  /\ Room(n) = 0
  /\ pv' = [pv EXCEPT ![n] = 0] /\ mid' = [mid EXCEPT ![n] = FALSE]
  /\ icap' = [icap EXCEPT ![n] = Cap0(n)]
  /\ ibuf' = IF Mutant = "noBufRecord" THEN ibuf ELSE [ibuf EXCEPT ![n] = str[n]]
  /\ seen' = seen \cup {"full"}
  /\ UNCHANGED <<heap, hp, filled, grown, str, size, typ, ps, err, faults, ovf, uaf,
                 badFree, wrongHeap, leak, slow>>

\* the parts every appending branch shares (sp: spare bytes of a cut multibyte character)
APre(n, sp) ==
  /\ Room(n) > 0 /\ (Trunc(n) \/ sp = 0)
  /\ pv' = [pv EXCEPT ![n] = 0] /\ mid' = [mid EXCEPT ![n] = FALSE]
  /\ UNCHANGED <<leak>>

\* CHAR/BIT start value: db_string_concatenate once (exact size), capacity = 0
ACharAt(n, sp, a) ==
  /\ typ[n] = "char"
  /\ heap[a] = 0
  /\ heap' = HeapAF(a, NeedOf(n, sp), str[n]) /\ hp' = HpAF(a, Ctx(n), str[n])
  /\ filled' = FillAF(a, CopyOf(n, size[n] + AddOf(n, sp)), str[n])
  /\ grown' = GrownAF(a, FALSE, str[n])
  /\ badFree' = (badFree \/ BadFree(str[n]))
  /\ wrongHeap' = (wrongHeap \/ WrongHeap(str[n], Ctx(n)))
  /\ uaf' = (uaf \/ ReadsFreed(n))
  /\ str' = [str EXCEPT ![n] = a] /\ size' = [size EXCEPT ![n] = size[n] + AddOf(n, sp)]
  /\ icap' = [icap EXCEPT ![n] = IF Mutant = "noResetReplace" THEN Cap0(n) ELSE 0]
  /\ typ' = [typ EXCEPT ![n] = "var"]
  /\ ps' = [ps EXCEPT ![n] = SpareOf(n, sp)]
  /\ ibuf' = IF Mutant = "noBufRecord" \/ SpareOf(n, sp) > 0 THEN ibuf ELSE [ibuf EXCEPT ![n] = a]
  /\ seen' = seen \cup {"replace"} \cup (IF Trunc(n) THEN {"trunc"} ELSE {})
  /\ UNCHANGED <<ovf, slow, err, faults>>
AChar(n, sp) == \E a \in Addr : ACharAt(n, sp, a)

AIn(n, sp) ==
  /\ typ[n] = "var" /\ Mutant # "develop" /\ ReqOf(n, sp) <= Cap0(n)
  /\ InPlace(n, NeedOf(n, sp), size[n] + AddOf(n, sp), Cap0(n))
  /\ ps' = [ps EXCEPT ![n] = SpareOf(n, sp)]
  /\ ibuf' = IF Mutant = "noBufRecord" \/ SpareOf(n, sp) > 0 THEN ibuf ELSE [ibuf EXCEPT ![n] = str[n]]
  /\ UNCHANGED <<typ, err, faults>>

AGrowAt(n, sp, a, c) ==
  /\ typ[n] = "var" /\ (Mutant = "develop" \/ ReqOf(n, sp) > Cap0(n))
  /\ GrowAt(n, NeedOf(n, sp), ReqOf(n, sp), size[n] + AddOf(n, sp), a, c)
  /\ ps' = [ps EXCEPT ![n] = SpareOf(n, sp)]
  /\ ibuf' = IF Mutant = "noBufRecord" \/ SpareOf(n, sp) > 0 THEN ibuf ELSE [ibuf EXCEPT ![n] = a]
  /\ UNCHANGED <<typ, err, faults>>
AGrow(n, sp) == \E a \in Addr, c \in CapCands : AGrowAt(n, sp, a, c)

AFail(n, sp) ==
  /\ typ[n] = "var" /\ (Mutant = "develop" \/ ReqOf(n, sp) > Cap0(n))
  /\ Fail(n, Cap0(n))
  /\ ps' = ps
  /\ ibuf' = IF Mutant = "noBufRecord" THEN ibuf ELSE [ibuf EXCEPT ![n] = str[n]]
  /\ UNCHANGED <<typ>>

\* The rest of the qdata_concatenate_dbval call: qdata_group_concat_capacity's pointer check (Cap0),
\* the truncation at group_concat_max_len (a multibyte character cut at the limit leaves sp spare
\* bytes, added by ZeroAppend in the same call), then db_string_append. The caller records
\* buf = db_get_string afterwards (after ZeroAppend when there are spare bytes).
AppendCall(n) ==
  /\ Active(n) /\ ~err /\ pv[n] > 0
  /\ \/ AFull(n)
     \/ \E sp \in 0 .. MinOf(SpareMax, Room(n)) :
          APre(n, sp) /\ (AChar(n, sp) \/ AIn(n, sp) \/ AGrow(n, sp) \/ AFail(n, sp))
  /\ ACommon

\* db_string_append_zero_bytes in the same call: capacity_p as AppendCall left it, no pointer
\* check; then the caller records buf.
ZNeed(n) == size[n] + ps[n] + 1
ZReq(n) == IF Mutant = "noTerm" THEN ZNeed(n) - 1 ELSE ZNeed(n)
ZCommon == UNCHANGED <<cnt, rows, typ, pv, mid, leak, ph, wph, merger, mrows, passes, tasks, grp, ext>>
ZIn(n) ==
  /\ Mutant # "develop" /\ ZReq(n) <= icap[n]
  /\ InPlace(n, ZNeed(n), size[n] + ps[n], icap[n])
  /\ ibuf' = IF Mutant = "noBufRecord" THEN ibuf ELSE [ibuf EXCEPT ![n] = str[n]]
  /\ UNCHANGED <<err, faults>>
ZGrowAt(n, a, c) ==
  /\ (Mutant = "develop" \/ ZReq(n) > icap[n])
  /\ GrowAt(n, ZNeed(n), ZReq(n), size[n] + ps[n], a, c)
  /\ ibuf' = IF Mutant = "noBufRecord" THEN ibuf ELSE [ibuf EXCEPT ![n] = a]
  /\ UNCHANGED <<err, faults>>
ZGrow(n) == \E a \in Addr, c \in CapCands : ZGrowAt(n, a, c)
ZFail(n) ==
  /\ (Mutant = "develop" \/ ZReq(n) > icap[n])
  /\ Fail(n, icap[n])
  /\ ibuf' = IF Mutant = "noBufRecord" THEN ibuf ELSE [ibuf EXCEPT ![n] = str[n]]
ZeroAppend(n) ==
  /\ Active(n) /\ ~err /\ ps[n] > 0
  /\ ps' = [ps EXCEPT ![n] = 0]
  /\ (ZIn(n) \/ ZGrow(n) \/ ZFail(n))
  /\ ZCommon

\* an exact-size copy of node n's string at a (on heap h), its old buffer freed on heap fh
CopyTo(n, a, h, fh) ==
  /\ heap[a] = 0
  /\ heap' = HeapAF(a, size[n] + 1, str[n]) /\ hp' = HpAF(a, h, str[n])
  /\ filled' = FillAF(a, CopyOf(n, size[n]), str[n]) /\ grown' = GrownAF(a, FALSE, str[n])
  /\ badFree' = (badFree \/ BadFree(str[n]))
  /\ wrongHeap' = (wrongHeap \/ WrongHeap(str[n], fh))
  /\ uaf' = (uaf \/ ReadsFreed(n))
  /\ str' = [str EXCEPT ![n] = a]

\* db_string_append's codeset branch (string1 changes codeset): string1 becomes its coerced copy
\* (exact size) and capacity = 0; the append that follows in the same call reads the capacity
\* without the pointer check (mid).
Coerce(n) ==
  /\ Active(n) /\ ~err /\ pv[n] > 0 /\ ~mid[n] /\ typ[n] = "var" /\ str[n] # 0
  /\ size[n] < Max /\ Mutant # "develop"
  /\ \E a \in Addr : CopyTo(n, a, Ctx(n), Ctx(n))
  /\ icap' = IF Mutant = "noResetCoerce" THEN icap ELSE [icap EXCEPT ![n] = 0]
  /\ mid' = [mid EXCEPT ![n] = TRUE]
  /\ seen' = seen \cup {"coerce"}
  /\ UNCHANGED <<size, cnt, rows, typ, pv, ps, ibuf, ph, wph, merger, mrows, passes, tasks, grp, err,
                 faults, ext, ovf, leak, slow>>

\* rehome_agg_value: clone on the destination heap (exact size), then free on the source heap;
\* rehome_node resets the capacity first.
Rehome(from, to) ==
  LET s == str["o"] IN
  /\ IF s = 0
     THEN UNCHANGED <<heap, hp, filled, grown, str, badFree, wrongHeap, uaf>>
     ELSE \E a \in Addr : CopyTo("o", a, to, from)
  /\ icap' = IF Mutant = "noResetRehome" THEN icap ELSE [icap EXCEPT !["o"] = 0]

\* A parallel pass starts (px_scan: rehome_agg_list BORROW, then the workers start; a worker's
\* initialize_node sets curr_cnt = 0 and keeps the clone's info).
StartPar ==
  /\ ph = "scan" /\ ~err /\ passes < P /\ pv["o"] = 0 /\ ps["o"] = 0
  \* a worker that took no row holds nothing to clear
  /\ \A w \in Workers : wph[w] = "idle" \/ (wph[w] = "merged" /\ str[w] = 0)
  /\ Rehome("coord", "h0")
  /\ ph' = "par" /\ tasks' = 0
  /\ seen' = seen \cup (IF str["o"] # 0 THEN {"rehome"} ELSE {})
  /\ UNCHANGED <<size, cnt, rows, typ, pv, ps, mid, ibuf, wph, merger, mrows, passes, grp, err, faults,
                 ext, ovf, leak, slow>>

\* A worker task starts on clone w (initialize_node<PT_GROUP_CONCAT>: curr_cnt = 0, the clone's info
\* kept). The clone pool hands a clone to any task of the pass, so a cleared clone can run again
\* in the same pass; at most TM tasks per pass.
WRun(w) ==
  /\ ph = "par" /\ ~err /\ tasks < TM
  /\ wph[w] = "idle" \/ (wph[w] = "merged" /\ str[w] = 0)
  /\ wph' = [wph EXCEPT ![w] = "run"] /\ tasks' = tasks + 1
  /\ cnt' = [cnt EXCEPT ![w] = 0] /\ rows' = [rows EXCEPT ![w] = 0] /\ typ' = [typ EXCEPT ![w] = "var"]
  /\ UNCHANGED <<heap, hp, filled, grown, str, size, pv, ps, mid, ibuf, icap, ph, merger, mrows, passes,
                 grp, err, faults, ext, ovf, uaf, badFree, wrongHeap, leak, slow, seen>>

CloneAt(w, a) ==
  /\ heap[a] = 0
  /\ heap' = HeapAF(a, size[w] + 1, 0) /\ hp' = HpAF(a, Ctx("o"), 0)
  /\ filled' = FillAF(a, CopyOf(w, size[w]), 0) /\ grown' = GrownAF(a, FALSE, 0)
  /\ leak' = (leak \/ str["o"] # 0)
  /\ str' = [str EXCEPT !["o"] = a]

\* finalize_node under writer_results_mutex, on heap 0: worker w's partial string goes to the
\* coordinator's node, appended (qdata_group_concat_value: the coordinator's RowStart and
\* AppendCall while merger = w) or cloned (pr_clone_value, capacity 0).
WMerge(w) ==
  /\ wph[w] = "run" /\ merger = "none" /\ ~err /\ pv[w] = 0 /\ ps[w] = 0
  /\ IF cnt[w] = 0 \/ size[w] = 0
     THEN /\ wph' = [wph EXCEPT ![w] = "merged"]
          /\ UNCHANGED <<heap, hp, filled, grown, str, size, cnt, typ, icap, merger, mrows, uaf,
                         leak, seen>>
     ELSE IF cnt["o"] > 0
     THEN /\ merger' = w /\ mrows' = 0
          /\ cnt' = [cnt EXCEPT !["o"] = @ + cnt[w]]
          /\ seen' = seen \cup {"mergeappend"}
          /\ UNCHANGED <<heap, hp, filled, grown, str, size, typ, icap, wph, uaf, leak>>
     ELSE /\ \E a \in Addr : CloneAt(w, a)
          /\ uaf' = (uaf \/ ReadsFreed(w))
          /\ size' = [size EXCEPT !["o"] = size[w]] /\ typ' = [typ EXCEPT !["o"] = "var"]
          /\ cnt' = [cnt EXCEPT !["o"] = cnt[w]]
          /\ icap' = IF Mutant = "noResetClone" THEN icap ELSE [icap EXCEPT !["o"] = 0]
          /\ wph' = [wph EXCEPT ![w] = "merged"]
          /\ seen' = seen \cup {"clone"}
          /\ UNCHANGED <<merger, mrows>>
  /\ UNCHANGED <<rows, pv, ps, mid, ibuf, ph, passes, tasks, grp, err, faults, ext, ovf, badFree,
                 wrongHeap, slow>>

\* the merge of worker merger has appended what it appends; the mutex is released
MergeDone ==
  /\ merger # "none" /\ ~err /\ mrows >= 1 /\ pv["o"] = 0 /\ ps["o"] = 0
  /\ wph' = [wph EXCEPT ![merger] = "merged"] /\ merger' = "none" /\ mrows' = 0
  /\ UNCHANGED <<heap, hp, filled, grown, str, size, cnt, rows, typ, pv, ps, mid, ibuf, icap, ph,
                 passes, tasks, grp, err, faults, ext, ovf, uaf, badFree, wrongHeap, leak, slow, seen>>

\* qexec_clear_xasl on worker w's clone: the accumulator is freed on the worker's heap; the
\* clone's info.group_concat keeps buf and capacity for the next pass or execution.
WClear(w) ==
  /\ wph[w] = "merged"
  /\ heap' = HeapAF(0, 0, str[w]) /\ hp' = HpAF(0, "none", str[w])
  /\ filled' = FillAF(0, 0, str[w]) /\ grown' = GrownAF(0, FALSE, str[w])
  /\ badFree' = (badFree \/ BadFree(str[w])) /\ wrongHeap' = (wrongHeap \/ WrongHeap(str[w], "wk"))
  /\ str' = [str EXCEPT ![w] = 0] /\ size' = [size EXCEPT ![w] = 0]
  /\ wph' = [wph EXCEPT ![w] = "idle"]
  /\ UNCHANGED <<cnt, rows, typ, pv, ps, mid, ibuf, icap, ph, merger, mrows, passes, tasks, grp, err,
                 faults, ext, ovf, uaf, leak, slow, seen>>

\* The workers are done (read (): rehome_agg_list RESTORE); a partitioned scan may go on serially.
Restore ==
  /\ ph = "par" /\ ~err /\ merger = "none" /\ pv["o"] = 0 /\ ps["o"] = 0
  /\ \A w \in Workers : wph[w] \in {"merged", "idle"}
  /\ Rehome("h0", "coord")
  /\ ph' = "scan" /\ passes' = passes + 1
  /\ UNCHANGED <<size, cnt, rows, typ, pv, ps, mid, ibuf, wph, merger, mrows, tasks, grp, err, faults,
                 ext, ovf, leak, slow, seen>>

\* The group ends: qdata_finalize_aggregate_list (no buffer change), then the value is either
\* cleared (qexec_clear_agg_list at the end of a BUILDVALUE query) or moved to the GROUP BY
\* output list (qexec_gby_finalize_group_dim: struct copy, PRIM_SET_NULL), whose owner frees it
\* later (ExtFree).
OEnd ==
  /\ ph = "scan" /\ ~err /\ pv["o"] = 0 /\ ps["o"] = 0
  /\ \/ /\ heap' = HeapAF(0, 0, str["o"]) /\ hp' = HpAF(0, "none", str["o"])
        /\ filled' = FillAF(0, 0, str["o"]) /\ grown' = GrownAF(0, FALSE, str["o"])
        /\ badFree' = (badFree \/ BadFree(str["o"]))
        /\ wrongHeap' = (wrongHeap \/ WrongHeap(str["o"], "coord"))
        /\ UNCHANGED <<ext, seen>>
     \/ /\ str["o"] # 0
        /\ ext' = ext \cup {str["o"]}
        /\ seen' = seen \cup {"moveout"}
        /\ UNCHANGED <<heap, hp, filled, grown, badFree, wrongHeap>>
  /\ str' = [str EXCEPT !["o"] = 0] /\ size' = [size EXCEPT !["o"] = 0]
  /\ cnt' = [cnt EXCEPT !["o"] = 0]
  /\ grp' = grp + 1 /\ ph' = IF grp + 1 < G THEN "start" ELSE "done"
  /\ UNCHANGED <<rows, typ, pv, ps, mid, ibuf, icap, wph, merger, mrows, passes, tasks, err, faults, ovf,
                 uaf, leak, slow>>

\* the output list's owner frees a value moved out to it (pr_clear_value of the output node)
ExtFreeA(a) ==
    /\ a \in ext
    /\ heap' = HeapAF(0, 0, a) /\ hp' = HpAF(0, "none", a)
    /\ filled' = FillAF(0, 0, a) /\ grown' = GrownAF(0, FALSE, a)
    /\ badFree' = (badFree \/ BadFree(a)) /\ wrongHeap' = (wrongHeap \/ WrongHeap(a, "coord"))
    /\ ext' = ext \ {a}
    /\ UNCHANGED <<str, size, cnt, rows, typ, pv, ps, mid, ibuf, icap, ph, wph, merger, mrows,
                   passes, tasks, grp, err, faults, ovf, uaf, leak, slow, seen>>
ExtFree == \E a \in ext : ExtFreeA(a)

\* The query fails: the coordinator's value is discarded (rehome DISCARD on heap 0 during a
\* parallel pass, qexec_clear on its own heap otherwise) and every worker's clone is cleared.
Live == {str[n] : n \in Nodes} \ {0}
ErrEnd ==
  /\ err
  /\ LET ho == IF ph = "par" THEN "h0" ELSE "coord"
     IN /\ heap' = [x \in Addr |-> IF x \in Live THEN 0 ELSE heap[x]]
        /\ hp' = [x \in Addr |-> IF x \in Live THEN "none" ELSE hp[x]]
        /\ filled' = [x \in Addr |-> IF x \in Live THEN 0 ELSE filled[x]]
        /\ grown' = [x \in Addr |-> IF x \in Live THEN FALSE ELSE grown[x]]
        /\ badFree' = (badFree \/ (\E n \in Nodes : BadFree(str[n]))
                       \/ (\E n, m \in Nodes : n # m /\ str[n] # 0 /\ str[n] = str[m]))
        /\ wrongHeap' = (wrongHeap \/ WrongHeap(str["o"], ho)
                         \/ (\E w \in Workers : WrongHeap(str[w], "wk")))
  /\ str' = [n \in Nodes |-> 0] /\ size' = [n \in Nodes |-> 0] /\ cnt' = [n \in Nodes |-> 0]
  /\ pv' = [n \in Nodes |-> 0] /\ ps' = [n \in Nodes |-> 0] /\ mid' = [n \in Nodes |-> FALSE]
  /\ err' = FALSE /\ wph' = [w \in Workers |-> "idle"] /\ merger' = "none" /\ mrows' = 0
  /\ grp' = grp + 1 /\ ph' = IF grp + 1 < G THEN "start" ELSE "done"
  /\ UNCHANGED <<rows, typ, ibuf, icap, passes, tasks, faults, ext, ovf, uaf, leak, slow, seen>>

Terminating ==
  /\ ph = "done" /\ ext = {} /\ \A w \in Workers : str[w] = 0
  /\ UNCHANGED vars

Next ==
  \/ OInit
  \/ \E n \in Nodes, v \in 1 .. V : RowStart(n, v)
  \/ \E n \in Nodes : AppendCall(n) \/ ZeroAppend(n) \/ Coerce(n)
  \/ StartPar \/ \E w \in Workers : WRun(w) \/ WMerge(w) \/ WClear(w)
  \/ MergeDone \/ Restore \/ OEnd \/ ExtFree \/ ErrEnd
  \/ Terminating

Spec == Init /\ [][Next]_vars

\* ---------------------------------------------------------------------------
\* Properties

\* C1: no byte is written past the allocation or into freed memory, no copy reads freed
\* memory, every free hits a live buffer on the heap that allocated it, no buffer is dropped
NoOverflow == ~ovf
NoUseAfterFree == ~uaf
NoBadFree == ~badFree
RightHeap == ~wrongHeap
NoLeak == ~leak
Owned(a) == (\E n \in Nodes : str[n] = a) \/ a \in ext
AOrphan(a) == heap[a] > 0 <=> Owned(a)
NoOrphan == \A a \in Addr : AOrphan(a)

\* C2: the accumulator holds every byte appended so far and nothing past group_concat_max_len
NIntact(n) == size[n] <= Max /\ (str[n] # 0 => filled[str[n]] = size[n])
Intact == \A n \in Nodes : NIntact(n)

\* C3: a reserve-grown buffer is replaced only when the bytes do not fit, and by one at least
\* twice as large or at the limit (the allocation count per group is logarithmic)
NoSlowGrowth == ~slow

\* C4: a live accumulator buffer is at most about twice its string
NMem(n) == str[n] # 0 => heap[str[n]] <= MaxOf(Base, 2 * size[n] + 1)
MemBound == \A n \in Nodes : NMem(n)

\* C5: a reserve-grown buffer does not pass group_concat_max_len + 1
AClamp(a) == grown[a] => heap[a] <= Limit
Clamped == \A a \in Addr : AClamp(a)

Bools == {TRUE, FALSE}
SeenTags == {"stale", "charstart", "clamp", "grow", "inplace", "oom", "full", "replace", "trunc",
             "coerce", "rehome", "mergeappend", "clone", "moveout"}
Phases == {"start", "scan", "par", "done"}
WPhases == {"idle", "run", "merged"}

TypeOK ==
  /\ heap \in [Addr -> Nat] /\ hp \in [Addr -> Heaps] /\ filled \in [Addr -> Nat]
  /\ grown \in [Addr -> Bools]
  /\ str \in [Nodes -> 0 .. NA] /\ size \in [Nodes -> Nat] /\ cnt \in [Nodes -> Nat]
  /\ rows \in [Nodes -> Nat] /\ typ \in [Nodes -> {"var", "char"}]
  /\ pv \in [Nodes -> Nat] /\ ps \in [Nodes -> Nat] /\ mid \in [Nodes -> Bools]
  /\ ibuf \in [Nodes -> 0 .. NA] /\ icap \in [Nodes -> Nat]
  /\ ph \in Phases /\ wph \in [Workers -> WPhases] /\ merger \in Workers \cup {"none"}
  /\ mrows \in Nat /\ passes \in Nat /\ tasks \in Nat /\ grp \in Nat
  /\ err \in Bools /\ faults \in Nat /\ ext \in SUBSET Addr
  /\ ovf \in Bools /\ uaf \in Bools /\ badFree \in Bools /\ wrongHeap \in Bools
  /\ leak \in Bools /\ slow \in Bools /\ seen \in SUBSET SeenTags

\* Inductive invariant (Apalache cfg, TLAPS)
NLive(n) == str[n] # 0 => heap[str[n]] > 0 /\ hp[str[n]] = Loc(n)
R_live == \A n \in Nodes : NLive(n)
NDisj(n, m) == (n # m /\ str[n] # 0) => str[n] # str[m]
R_disj == \A n, m \in Nodes : NDisj(n, m)
AExt(a) == heap[a] > 0 /\ hp[a] = "coord" /\ \A n \in Nodes : str[n] # a
R_ext == \A a \in ext : AExt(a)
AFree(a) == heap[a] = 0 => hp[a] = "none" /\ ~grown[a]
R_free == \A a \in Addr : AFree(a)
NCap1(n) == (str[n] # 0 /\ ibuf[n] = str[n] /\ icap[n] > 0) => icap[n] = heap[str[n]] /\ grown[str[n]]
NCap2(n) == (str[n] # 0 /\ grown[str[n]]) => icap[n] = heap[str[n]] /\ (ibuf[n] = str[n] \/ ps[n] > 0)
NCap3(n) == mid[n] => icap[n] = 0 /\ str[n] # 0 /\ pv[n] > 0 /\ typ[n] = "var"
NCap4(n) == (pv[n] > 0 \/ ps[n] > 0) => str[n] # 0 /\ Active(n)
NCap5(n) == ps[n] > 0 => /\ pv[n] = 0 /\ size[n] + ps[n] = Max /\ typ[n] = "var"
                         /\ (icap[n] = 0 \/ (icap[n] = heap[str[n]] /\ grown[str[n]]))
NCap6(n) == str[n] = 0 => size[n] = 0
NCap7(n) == cnt[n] = 0 => str[n] = 0
NCap8(n) == (typ[n] = "char" /\ str[n] # 0) => size[n] = 0 /\ heap[str[n]] = 1 /\ ps[n] = 0 /\ ~mid[n]
R_cap1 == \A n \in Nodes : NCap1(n)
R_cap2 == \A n \in Nodes : NCap2(n)
R_cap3 == \A n \in Nodes : NCap3(n)
R_cap4 == \A n \in Nodes : NCap4(n)
R_cap5 == \A n \in Nodes : NCap5(n)
R_cap6 == \A n \in Nodes : NCap6(n)
R_cap7 == \A n \in Nodes : NCap7(n)
R_cap8 == \A n \in Nodes : NCap8(n)
R_cap == R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8
AGrown(a) == grown[a] => heap[a] \in Caps \cup {Limit}
R_grown == \A a \in Addr : AGrown(a)
R_ph1 == ph # "par" => merger = "none" /\ \A w \in Workers : wph[w] # "run"
R_ph2 == merger # "none" => wph[merger] = "run" /\ pv[merger] = 0 /\ ps[merger] = 0 /\ cnt["o"] > 0
R_ph3 == (ph = "start" \/ ph = "done") => str["o"] = 0
R_ph4 == (cnt["o"] > 0 /\ (ph = "scan" \/ ph = "par")) => str["o"] # 0
WPh5(w) == (wph[w] = "run" /\ cnt[w] > 0) => str[w] # 0
WPh6(w) == wph[w] = "idle" => str[w] = 0
R_ph5 == \A w \in Workers : WPh5(w)
R_ph6 == \A w \in Workers : WPh6(w)
R_phase == R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6

IndInv ==
  /\ TypeOK
  /\ NoOverflow /\ NoUseAfterFree /\ NoBadFree /\ RightHeap /\ NoLeak /\ NoSlowGrowth
  /\ NoOrphan /\ Intact /\ MemBound /\ Clamped
  /\ R_live /\ R_disj /\ R_ext /\ R_free /\ R_grown
  /\ R_cap1 /\ R_cap2 /\ R_cap3 /\ R_cap4 /\ R_cap5 /\ R_cap6 /\ R_cap7 /\ R_cap8
  /\ R_ph1 /\ R_ph2 /\ R_ph3 /\ R_ph4 /\ R_ph5 /\ R_ph6

\* ---------------------------------------------------------------------------
\* Witnesses (expected violated: the outcome is reachable)
NotStale == "stale" \notin seen            \* a new buffer landed on a node's stale buf with capacity > 0
NotInPlace == "inplace" \notin seen
NotClamp == "clamp" \notin seen
NotSpare == \A n \in Nodes : ps[n] = 0
NotClone == "clone" \notin seen
NotMergeAppend == "mergeappend" \notin seen
NotMoveOut == "moveout" \notin seen
NotReplace == "replace" \notin seen
NotCoerce == "coerce" \notin seen
NotOom == "oom" \notin seen
NotFull == "full" \notin seen

\* TLC fingerprint without the witness history (pass, scale and mutant cfgs)
View == <<heap, hp, filled, grown, str, size, cnt, rows, typ, pv, ps, mid, ibuf, icap,
          ph, wph, merger, mrows, passes, tasks, grp, err, faults, ext, ovf, uaf, badFree, wrongHeap,
          leak, slow>>

\* Apalache: role sets are literals; integer bounds open
CInit == /\ NA = 4 /\ Caps = {1, 2, 4, 8} /\ Base = 1 /\ Mutant = "none"
         /\ Workers = {"w1", "w2"}
         \* Apalache needs constant integer ranges: Max, V and SpareMax bound 1 .. 2 * Limit, 1 .. V
         \* and 0 .. SpareMax; the loop bounds stay open
         /\ Max = 4 /\ V = 2 /\ SpareMax = 1
         /\ R \in Nat /\ P \in Nat /\ G \in Nat /\ TM \in Nat /\ MaxFaults \in Nat
=============================================================================
