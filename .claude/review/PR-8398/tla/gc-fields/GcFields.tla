------------------------------- MODULE GcFields -------------------------------
(* PR CUBRID/cubrid#8398 (CBRD-27926) at ea06eca48 against its merge base, develop 0661d2c12:
   the fields of the GROUP_CONCAT accumulator DB_VALUE after every append.

   "dev" is develop's path: qdata_concatenate_dbval -> qdata_add_chars_to_dbval ->
   db_string_concatenate (string1, string2, &tmp_val), then pr_clone_value (&tmp_val, accumulator)
   when tmp_val is not NULL. "pr" is the PR's path: qdata_append_chars_to_dbval -> db_string_append
   (in place, qstr_reserve when the bytes do not fit) and db_string_append_zero_bytes. Both run on
   the same inputs, so every field the PR leaves differently from develop shows as a difference of
   dev[n] and pr[n]. The buffer protocol (capacity, addresses, heaps) is GcBuf's model; here the
   capacity only decides whether qstr_reserve runs (fresh = capacity 0 forces it, otherwise either).

   A value is the record of the DB_VALUE fields a reader can see:
     t    DB_VALUE_DOMAIN_TYPE: "C" CHAR, "VC" VARCHAR, "B" BIT, "VB" VARBIT
     p    domain.char_info.length (the precision); Float = -1 (TP_FLOATING_PRECISION_VALUE)
     sz   data.ch.medium.size: bytes for a character string, bits for a bit string
     ln   the characters of the content (intl_char_count over sz bytes); bits for a bit string
     lc   data.ch.medium.length, the cached character count db_get_string_length returns; Unk = -1
     zp   the offset of the first zero byte GROUP_CONCAT's spare bytes left (Unk = none), zl the
          characters before it: db_string_fix_string_size's strlen stops there
     cs   codeset ("u", "k", "i" by collation; "raw" for bits), co the collation id (0 for bits)
     nul  domain.general_info.is_null
     cmp  the compression cache (compressed_size): "ny" DB_NOT_YET_COMPRESSED, "un"
          DB_UNCOMPRESSABLE, "ok" a compressed copy of the current bytes, "st" a compressed copy of
          bytes the value no longer holds *)
EXTENDS Integers, FiniteSets

CONSTANTS MaxP, Max, VSz, VP, R, P, G, Workers, AggTypes, Css, UColls, KColls, DomColl, Thresh,
          Oracles, Modes, Mutant, Fix, SepFix

\* Types for Apalache (tools/tla/apalache-types writes them into the declarations).
\* apalache-type: MaxP Int
\* apalache-type: Max Int
\* apalache-type: VSz Int
\* apalache-type: VP Int
\* apalache-type: R Int
\* apalache-type: P Int
\* apalache-type: G Int
\* apalache-type: Workers Set(Str)
\* apalache-type: AggTypes Set(Str)
\* apalache-type: Css Set(Str)
\* apalache-type: UColls Set(Int)
\* apalache-type: KColls Set(Int)
\* apalache-type: DomColl Int
\* apalache-type: Thresh Int
\* apalache-type: Oracles Set(Bool)
\* apalache-type: Modes Set(Str)
\* apalache-type: Mutant Str
\* apalache-type: Fix Str
\* apalache-type: SepFix Bool
\* apalache-type: ora Bool
\* apalache-type: mode Str
\* apalache-type: at Str
\* apalache-type: dcs Str
\* apalache-type: sepv { t: Str, p: Int, sz: Int, ln: Int, lc: Int, zp: Int, zl: Int, cs: Str, co: Int, nul: Bool, cmp: Str }
\* apalache-type: dev Str -> { t: Str, p: Int, sz: Int, ln: Int, lc: Int, zp: Int, zl: Int, cs: Str, co: Int, nul: Bool, cmp: Str }
\* apalache-type: pr Str -> { t: Str, p: Int, sz: Int, ln: Int, lc: Int, zp: Int, zl: Int, cs: Str, co: Int, nul: Bool, cmp: Str }
\* apalache-type: fresh Str -> Bool
\* apalache-type: ph Str
\* apalache-type: wph Str -> Str
\* apalache-type: ocnt Bool
\* apalache-type: rows Str -> Int
\* apalache-type: passes Int
\* apalache-type: grp Int
\* apalache-type: errd Str -> Bool
\* apalache-type: outv Str -> { t: Str, p: Int, sz: Int, ln: Int, lc: Int, zp: Int, zl: Int, cs: Str, co: Int, nul: Bool, cmp: Str }
\* apalache-type: written Bool
\* apalache-type: assertF Bool
\* apalache-type: staleW Bool
\* apalache-type: seen Set(Str)

VARIABLES ora, mode, at, dcs, sepv, dev, pr, fresh, ph, wph, ocnt, rows, passes, grp, errd, outv,
          written, assertF, staleW, seen

vars == <<ora, mode, at, dcs, sepv, dev, pr, fresh, ph, wph, ocnt, rows, passes, grp, errd, outv,
          written, assertF, staleW, seen>>

\* Apalache type aliases (ignored by TLC)
\* @typeAlias: val = { t: Str, p: Int, sz: Int, ln: Int, lc: Int, zp: Int, zl: Int, cs: Str, co: Int, nul: Bool, cmp: Str };
\* @typeAlias: res = { e: Bool, r: $val };
\* @typeAlias: pres = { e: Bool, r: $val, f: Bool };
\* @typeAlias: pstep = { e: Bool, r: $val, f: Bool, x: Bool };
GcFields_aliases == TRUE

Float == -1
Unk == -1
Sides == {"dev", "pr"}
Nodes == {"o"} \cup Workers
Chars == {"C", "VC"}
Bits == {"B", "VB"}
Padded == {"C", "B"}
IsVar(t) == t = "VC" \/ t = "VB"
Cat(t) == IF t \in Chars THEN "char" ELSE "bit"
CsOf(c) == IF c \in UColls THEN "u" ELSE IF c \in KColls THEN "k" ELSE "i"
Min(a, b) == IF a < b THEN a ELSE b

(***************************************************************************)
(* Shared value constructors (unchanged by the PR)                         *)
(* Coverage note: TLC's -coverage walks an operator's body once per        *)
(* reference of a LET name, so a computed value referenced more than once  *)
(* is handed to the next operator as an argument instead.                  *)
(***************************************************************************)

\* db_value_domain_init: a VARCHAR/VARBIT's -1 or 0 becomes the maximum, a CHAR/BIT's stays floating
DomInit(t, p) ==
  IF IsVar(t) THEN (IF p = Float \/ p = 0 \/ p > MaxP THEN MaxP ELSE p)
  ELSE (IF p = Float \/ p = 0 THEN Float ELSE p)

\* db_get_string_length: the cache, else intl_char_count (bits: the size)
\* @type: ($val) => Int;
Getter(x) == IF x.lc # Unk THEN x.lc ELSE x.ln

\* QSTR_VALUE_PRECISION
\* @type: ($val) => Int;
QVP(x) == IF x.p = Float THEN Getter(x) ELSE x.p

SumP(p1, p2) == IF p1 = Float \/ p2 = Float THEN Float ELSE Min(MaxP, p1 + p2)

\* qstr_make_typed_string -> db_make_{char,varchar,bit,varbit} -> db_value_domain_init + db_make_db_char
\* @type: (Str, Int, Int, Int, Int, Int, Str, Int) => $val;
Mk(t, p, sz, ln, zp, zl, cs, co) ==
  [t |-> t, p |-> DomInit(t, p), sz |-> sz, ln |-> ln, lc |-> Unk, zp |-> zp, zl |-> zl,
   cs |-> IF t \in Bits THEN "raw" ELSE cs, co |-> IF t \in Bits THEN 0 ELSE co,
   nul |-> (sz = 0 /\ ora), cmp |-> "ny"]

\* db_value_domain_init on a NULL value
\* @type: (Str) => $val;
NullV(t) ==
  [t |-> t, p |-> DomInit(t, Float), sz |-> 0, ln |-> 0, lc |-> Unk, zp |-> Unk, zl |-> Unk,
   cs |-> "n", co |-> 0, nul |-> TRUE, cmp |-> "ny"]

\* pr_clone_value: mr_setval_string keeps the length cache and the compression cache,
\* mr_setval_varbit remakes the value (db_make_varbit)
\* @type: ($val, $val) => $val;
CloneOf(x, m) == IF x.t \in Chars /\ ~m.nul THEN [m EXCEPT !.lc = x.lc, !.cmp = x.cmp] ELSE m
\* @type: ($val) => $val;
Clone(x) ==
  IF x.nul THEN NullV(x.t) ELSE LET m == Mk(x.t, x.p, x.sz, x.ln, x.zp, x.zl, x.cs, x.co) IN CloneOf(x, m)

\* db_value_domain_init (&temp, type, QSTR_VALUE_PRECISION (x)) + db_char_string_coerce: the same
\* characters in codeset cs (the model keeps the byte count)
\* @type: ($val, Str, Int) => $val;
Coerce(x, cs, co) ==
  [x EXCEPT !.p = DomInit(x.t, QVP(x)), !.lc = Unk, !.cs = cs, !.co = co, !.cmp = "ny"]

\* the first group value starts from db_value_domain_init + db_string_make_empty_typed_string of the
\* function's domain; oracle_style_empty_string makes it NULL and the code clears is_null again
\* @type: (Str) => $val;
Empty(t) ==
  [t |-> t, p |-> DomInit(t, Float), sz |-> 0, ln |-> 0, lc |-> Unk, zp |-> Unk, zl |-> Unk,
   cs |-> IF t \in Bits THEN "raw" ELSE dcs, co |-> IF t \in Bits THEN 0 ELSE DomColl,
   nul |-> FALSE, cmp |-> "ny"]

\* the first zero byte after appending v to a value of s1 bytes / l1 characters
\* @type: ($val, Int, $val) => Int;
ZpAfter(a, s1, v) == IF a.zp # Unk THEN a.zp ELSE IF v.zp # Unk THEN s1 + v.zp ELSE Unk
\* @type: ($val, Int, $val) => Int;
ZlAfter(a, l1, v) == IF a.zp # Unk THEN a.zl ELSE IF v.zp # Unk THEN l1 + v.zl ELSE Unk

\* the common codeset of a character append: LANG_RT_COMMON_COLL of one collation, its codeset when
\* the two codesets differ
\* @type: ($val, $val) => Str;
CommonCs(a, v) == IF a.cs = v.cs THEN a.cs ELSE CsOf(a.co)
\* @type: ($val, Str) => $val;
CoerceA(a, cs) == IF a.cs # cs THEN Coerce(a, cs, a.co) ELSE a
\* @type: ($val, $val, Str) => $val;
CoerceV(a, v, cs) == IF a.cs = cs /\ v.cs # cs THEN Coerce(v, cs, a.co) ELSE v

(***************************************************************************)
(* develop: db_string_concatenate (a, v, &tmp_val)                         *)
(***************************************************************************)

\* qstr_concatenate over the coerced operands: a padded type counts its precision, a string with no
\* bytes its pad characters
\* @type: ($val, $val, Str, Int, Int, Int) => $res;
DevCatC3(a1, v1, cs, co, l1, l2) ==
  LET s1 == IF a1.sz = 0 THEN l1 ELSE a1.sz
      s2 == IF v1.sz = 0 THEN l2 ELSE v1.sz
  IN [e |-> FALSE,
      r |-> [Mk("VC", SumP(a1.p, v1.p), s1 + s2, l1 + l2, ZpAfter(a1, s1, v1), ZlAfter(a1, l1, v1), cs, co)
             EXCEPT !.lc = Min(l1 + l2, MaxP)]]
\* @type: ($val, $val, Str, Int) => $res;
DevCatC2(a1, v1, cs, co) ==
  DevCatC3(a1, v1, cs, co, IF a1.t \in Padded THEN QVP(a1) ELSE Getter(a1),
           IF v1.t \in Padded THEN QVP(v1) ELSE Getter(v1))
\* @type: ($val, $val, Str) => $res;
DevCatC(a, v, cs) == LET a1 == CoerceA(a, cs) v1 == CoerceV(a, v, cs) IN DevCatC2(a1, v1, cs, a.co)

\* qstr_bit_concatenate: BIT + BIT stays BIT; a BIT's logical length is its length (the s_type == CHAR test)
\* @type: ($val, $val, Int) => $res;
DevCatB(a, v, len) ==
  [e |-> FALSE, r |-> Mk(IF a.t = "B" /\ v.t = "B" THEN "B" ELSE "VB", SumP(a.p, v.p), len, len, Unk, Unk, "raw", 0)]

\* @type: ($val, $val) => $res;
DevCatNull(a, v) ==
  [e |-> FALSE,
   r |-> IF ora /\ a.nul THEN Clone(v)
         ELSE IF ora /\ v.nul THEN Clone(a)
         ELSE NullV(IF a.t \in Chars
                    THEN (IF a.t = "VC" \/ v.t = "VC" THEN "VC" ELSE "C")
                    ELSE (IF a.t = "VB" \/ v.t = "VB" THEN "VB" ELSE "B"))]

\* @type: ($val, $val) => $res;
DevCat(a, v) ==
  IF Cat(a.t) # Cat(v.t) THEN [e |-> TRUE, r |-> a]
  ELSE IF a.nul \/ v.nul THEN DevCatNull(a, v)
  ELSE IF a.t \in Bits THEN DevCatB(a, v, Getter(a) + Getter(v))
  ELSE IF a.co # v.co THEN [e |-> TRUE, r |-> a]
  ELSE DevCatC(a, v, CommonCs(a, v))

\* develop's qdata_concatenate_dbval + the caller's pr_clone_value when tmp_val is not NULL
\* @type: ($val, $val) => $res;
DevKeep(a, r) == [e |-> FALSE, r |-> IF r.nul THEN a ELSE Clone(r)]
\* the spare bytes: qstr_make_typed_string (type, result, precision, ..., size + spare, cs (a), co (a))
\* @type: ($val, $val, Int) => $val;
DevSpare(a, r, sp) ==
  Mk(r.t, r.p, r.sz + sp, r.ln + sp, IF r.zp # Unk THEN r.zp ELSE r.sz, IF r.zp # Unk THEN r.zl ELSE r.ln,
     a.cs, a.co)
\* @type: ($val, Int, $res) => $res;
DevStep2(a, sp, d) ==
  IF d.e THEN [e |-> TRUE, r |-> a]
  ELSE LET r == IF sp > 0 THEN DevSpare(a, d.r, sp) ELSE d.r IN DevKeep(a, r)
\* @type: ($val, $val, Int) => $res;
DevStep(a, v, sp) == LET d == DevCat(a, v) IN DevStep2(a, sp, d)

(***************************************************************************)
(* PR: db_string_append (a, v, &capacity) + db_string_append_zero_bytes    *)
(***************************************************************************)
PrP(p1, p2) ==
  IF p1 = Float \/ p2 = Float THEN (IF Fix = "prec" THEN MaxP ELSE Float)
  ELSE Min(MaxP, p1 + p2)

\* qstr_reserve: a new buffer, the value remade by qstr_make_typed_string with its own fields, the
\* length cache restored, is_null cleared
\* @type: ($val, $val) => $val;
ReserveOf(x, m) == [m EXCEPT !.lc = x.lc, !.nul = IF Mutant = "reserve-keeps-null" THEN m.nul ELSE FALSE]
\* @type: ($val) => $val;
Reserve(x) == LET m == Mk(x.t, x.p, x.sz, x.ln, x.zp, x.zl, x.cs, x.co) IN ReserveOf(x, m)

Stale(c) == IF c = "ok" THEN "st" ELSE c

\* the CHAR/BIT start value: db_string_concatenate, then *string1 = result, capacity 0
\* @type: ($val, Bool, { e: Bool, r: $val }) => { e: Bool, r: $val, f: Bool };
PrAppChar(a, f0, d) ==
  IF d.e THEN [e |-> TRUE, r |-> a, f |-> f0]
  ELSE [e |-> FALSE, r |-> d.r, f |-> TRUE]

\* VARBIT: bit_ncat into the (maybe grown) buffer; the precision from the entry values
\* @type: ($val, $val, $val) => $pres;
PrAppB(a, v, a1) ==
  LET len == Getter(a) + Getter(v)
  IN [e |-> FALSE, f |-> FALSE,
      r |-> [a1 EXCEPT !.sz = len, !.ln = len, !.lc = Unk, !.p = PrP(a.p, v.p), !.cmp = Stale(a1.cmp)]]

\* VARCHAR: a1/v1 coerced, l1 = db_get_string_length (string1), lg2 = string2's logical length
\* @type: ($val, $val, $val, Str, Int, Int, $val) => $pres;
PrAppC3(a, a1, v1, cs, l1, lg2, a2) ==
  LET pad == v1.sz = 0 /\ lg2 > 0 /\ Mutant # "no-pad"
      s2 == IF pad THEN lg2 ELSE v1.sz
  IN [e |-> FALSE, f |-> FALSE,
      r |-> [a2 EXCEPT !.sz = a1.sz + s2, !.ln = l1 + lg2, !.zp = ZpAfter(a1, a1.sz, v1),
                       !.zl = ZlAfter(a1, l1, v1),
                       !.lc = IF Mutant = "len-is-size" THEN a1.sz + s2 ELSE l1 + lg2,
                       !.p = PrP(a1.p, v1.p), !.cs = cs, !.co = a.co, !.cmp = Stale(a2.cmp)]]
\* @type: ($val, $val, $val, Str, Bool) => $pres;
PrAppC2(a, a1, v1, cs, grow) ==
  LET a2 == IF grow THEN Reserve(a1) ELSE a1
  IN PrAppC3(a, a1, v1, cs, Getter(a1), IF v1.t \in Padded THEN QVP(v1) ELSE Getter(v1), a2)
\* the codeset branch: string1 itself coerced resets the capacity (the append below regrows it)
\* @type: ($val, $val, Bool, Bool, Str) => $pres;
PrAppC(a, v, f0, g, cs) ==
  LET a1 == CoerceA(a, cs) v1 == CoerceV(a, v, cs) IN PrAppC2(a, a1, v1, cs, f0 \/ g \/ a.cs # cs)

\* @type: ($val, $val, Bool, Bool) => $pres;
PrApp(a, v, f0, g) ==
  IF v.nul THEN [e |-> FALSE, r |-> a, f |-> f0]
  ELSE IF ~IsVar(a.t) /\ Mutant # "keep-char" THEN LET d == DevCat(a, v) IN PrAppChar(a, f0, d)
  ELSE IF Cat(a.t) # Cat(v.t) THEN [e |-> TRUE, r |-> a, f |-> f0]
  ELSE IF a.t \in Bits THEN LET a1 == IF f0 \/ g THEN Reserve(a) ELSE a IN PrAppB(a, v, a1)
  ELSE IF a.co # v.co THEN [e |-> TRUE, r |-> a, f |-> f0]
  ELSE PrAppC(a, v, f0, g, CommonCs(a, v))

\* db_string_append_zero_bytes, then db_string_put_cs_and_collation with the accumulator's codeset and
\* collation from before the append (qdata_append_chars_to_dbval)
\* @type: ($val, Int, Str, Int) => $val;
PrZero2(a1, sp, cs0, co0) ==
  [a1 EXCEPT !.sz = a1.sz + sp, !.ln = a1.ln + sp,
             !.zp = IF a1.zp # Unk THEN a1.zp ELSE a1.sz, !.zl = IF a1.zp # Unk THEN a1.zl ELSE a1.ln,
             !.lc = IF Mutant = "no-lc-reset" THEN a1.lc ELSE Unk,
             !.cs = IF Mutant = "no-cs-restore" THEN a1.cs ELSE cs0,
             !.co = IF Mutant = "no-cs-restore" THEN a1.co ELSE co0,
             !.cmp = Stale(a1.cmp)]
\* @type: ($val, Int, Bool, Str, Int) => $val;
PrZero(a, sp, g, cs0, co0) == LET a1 == IF g THEN Reserve(a) ELSE a IN PrZero2(a1, sp, cs0, co0)

\* x: db_string_append_zero_bytes asserts a VARCHAR
\* @type: ($val, Int, Bool, $pres) => $pstep;
PrStep2(a, sp, g2, q) ==
  IF q.e THEN [e |-> TRUE, r |-> a, f |-> FALSE, x |-> FALSE]
  ELSE IF sp > 0
       THEN LET z == PrZero(q.r, sp, q.f \/ g2, a.cs, a.co) IN [e |-> FALSE, r |-> z, f |-> FALSE, x |-> q.r.t # "VC"]
       ELSE [e |-> FALSE, r |-> q.r, f |-> q.f, x |-> FALSE]
\* @type: ($val, $val, Int, Bool, Bool, Bool) => $pstep;
PrStep(a, v, sp, f0, g1, g2) == LET q == PrApp(a, v, f0, g1) IN PrStep2(a, sp, g2, q)

(***************************************************************************)
(* What qdata_concatenate_dbval hands to the append                       *)
(***************************************************************************)

\* well-formed input values; under oracle_style_empty_string a value with no bytes is NULL
\* (db_make_db_char), and GROUP_CONCAT never aggregates a NULL argument
\* @type: ($val) => Bool;
ValOK(v) ==
  /\ v.ln <= v.sz
  /\ (v.t \in Bits) => (v.ln = v.sz /\ v.cs = "raw" /\ v.co = 0)
  /\ (v.t \in Chars) => (v.sz > 0 <=> v.ln > 0) /\ v.cs \in Css /\ v.co = DomColl
  /\ v.p # Float => v.ln <= v.p
  \* a CHAR(n) / BIT(n) value holds n characters (bits), or none (pad characters only)
  /\ (v.t \in Padded /\ v.p # Float /\ v.sz > 0) => v.ln = v.p
  /\ ora => v.sz > 0
VSet ==
  {v \in [t: {"C", "VC", "B", "VB"}, p: {Float} \cup 1..VP, sz: 0..VSz, ln: 0..VSz, lc: {Unk},
          zp: {Unk}, zl: {Unk}, cs: Css \cup {"raw"}, co: {0, DomColl}, nul: {FALSE}, cmp: {"ny"}] :
     ValOK(v)}


\* the separator: SEPARATOR '' under oracle_style_empty_string is NULL; at ea06eca48 (SepFix = FALSE)
\* qdata_group_concat_value replaces it with a non-NULL empty string of the function's type, after the
\* separator fix it appends no separator. A bit string takes no separator (the default ',' is a
\* character string, a bit-string literal separator is refused at prepare).
OraSep(t) == IF SepFix THEN NullV(t) ELSE Empty(t)
SepSet(t) ==
  IF t \in Bits THEN {IF ora THEN OraSep(t) ELSE NullV(t)}
  ELSE (IF ora THEN {OraSep(t)} ELSE {}) \cup {v \in VSet : v.t \in Chars}

\* db_string_limit_size_string: the first keep bytes cut back to cnt whole characters; the cut
\* character's bytes are the spare bytes
\* @type: ($val, Int, Int) => $val;
Trunc(x, keep, cnt) ==
  Mk(x.t, IF x.t \in Padded THEN Min(x.p, cnt) ELSE x.p, keep, cnt,
     IF x.zp # Unk /\ x.zp < keep THEN x.zp ELSE Unk, IF x.zp # Unk /\ x.zp < keep THEN x.zl ELSE Unk,
     x.cs, x.co)

\* the (adj, cnt) cuts of a value x for an accumulator of res bytes (bits: exactly the room; never
\* empty at the first value; a cut character leaves at most 3 spare bytes)
\* @type: ($val, Int, Int, Int) => Bool;
CutOK(x, res, adj, cnt) ==
  /\ cnt <= adj /\ cnt <= x.ln /\ (adj = 0 <=> cnt = 0)
  /\ (x.t \in Bits => adj = Max - res /\ cnt = adj)
  /\ (res = 0 => adj > 0)
  /\ Max - res - adj <= 3
  \* past the first zero byte every byte is a one-byte character (intl_char_count, intl_char_size in
  \* db_string_limit_size_string, string_opfunc.c:6182): the cut keeps them all and leaves no spare byte
  /\ x.zp # Unk => IF Max - res > x.zp THEN adj = Max - res /\ cnt = x.zl + adj - x.zp
                   ELSE adj <= x.zp /\ cnt <= x.zl

\* an input value with the fields a caller sets (no cached length, no zero byte, not compressed)
\* @type: (Str, Int, Int, Int, Str, Int) => $val;
MkV(t, p, sz, ln, cs, co) ==
  [t |-> t, p |-> p, sz |-> sz, ln |-> ln, lc |-> Unk, zp |-> Unk, zl |-> Unk, cs |-> cs, co |-> co, nul |-> FALSE,
   cmp |-> "ny"]
\* the arguments a GROUP_CONCAT of the accumulator's type aggregates: type checking makes them the
\* accumulator's category (a value of the other category is the fault table's)
\* @type: ($val) => Bool;
ArgOK(x) == ValOK(x) /\ Cat(x.t) = Cat(at)

\* the (adj, cnt) choice of a value x for an accumulator of res bytes: (0, 0) when x fits, else a cut
\* @type: ($val, Int, Int, Int) => Bool;
CutValid(x, res, adj, cnt) ==
  IF res + x.sz <= Max THEN adj = 0 /\ cnt = 0
  ELSE adj <= Max - res /\ cnt <= Max - res /\ CutOK(x, res, adj, cnt)
\* @type: ($val, Int, Int, Int) => $val;
CutV(x, res, adj, cnt) == IF res + x.sz <= Max THEN x ELSE Trunc(x, adj, cnt)
\* @type: ($val, Int, Int) => Int;
CutSp(x, res, adj) == IF res + x.sz <= Max THEN 0 ELSE Max - res - adj

(***************************************************************************)
(* Actions                                                                 *)
(***************************************************************************)
\* @type: (Str, Str) => $val;
Acc(s, n) == IF s = "dev" THEN dev[n] ELSE pr[n]
Live == ~errd["dev"] /\ ~errd["pr"]

\* @type: (Str, Bool) => Set(Str);
Seen(e, c) == IF c THEN {e} ELSE {}

\* one qdata_concatenate_dbval call on node n with string2 vd (develop) / vp (PR) and sp spare bytes;
\* node clr (a merged worker clone) is cleared in the same step
\* @type: (Str -> $val, Str, $val, Str) => (Str -> $val);
Upd(f, n, x, clr) == [m \in Nodes |-> IF m = n THEN x ELSE IF m = clr THEN NullV(at) ELSE f[m]]
\* @type: (Str, Str, $val, $val, Int, $res, $pstep) => Bool;
DoApp2(n, clr, a0, v, sp, dr, pq) ==
  /\ dev' = Upd(dev, n, dr.r, clr)
  /\ pr' = Upd(pr, n, pq.r, clr)
  /\ fresh' = [fresh EXCEPT ![n] = pq.f]
  /\ errd' = [errd EXCEPT !["dev"] = @ \/ dr.e, !["pr"] = @ \/ pq.e]
  /\ assertF' = (assertF \/ pq.x)
  /\ seen' = seen \cup Seen("pad", v.t = "C" /\ v.sz = 0) \cup Seen("spare", sp > 0)
                  \cup Seen("trunc-null", v.nul)
                  \cup Seen("coerce-acc", a0.t = "VC" /\ v.t \in Chars /\ a0.cs # v.cs /\ a0.cs # CsOf(a0.co))
                  \cup Seen("coerce-v", a0.t = "VC" /\ v.t \in Chars /\ a0.cs # v.cs /\ a0.cs = CsOf(a0.co))
                  \cup Seen("empty-sep", ~v.nul /\ v.sz = 0)
                  \cup Seen("pr-float", ~pq.r.nul /\ pq.r.p = Float /\ IsVar(pq.r.t))
                  \cup Seen("pr-finite", ~pq.r.nul /\ pq.r.p # Float /\ pq.r.p < MaxP /\ IsVar(pq.r.t))
                  \cup Seen("merge-app", clr # "none") \cup Seen("merge-cut", clr # "none" /\ v # dev[clr])
\* @type: (Str, Str, $val, $val, Bool, $val, $val, Int, Bool, Bool) => Bool;
DoApp(n, clr, a0, b0, f0, vd, vp, sp, g1, g2) ==
  LET dr == DevStep(a0, vd, sp) pq == PrStep(b0, vp, sp, f0, g1, g2) IN DoApp2(n, clr, a0, vd, sp, dr, pq)

\* the step kinds: "first" (qdata_group_concat_first_value, serial), "wfirst" (a worker task's first
\* value), "sep" / "val" (qdata_group_concat_value on the serial node or a worker), "msep" / "mval"
\* (finalize_node: qdata_group_concat_value on the coordinator's node with worker w's value)
Guard(n, w, k) ==
  CASE k = "first" -> mode = "serial" /\ n = "o" /\ ph \in {"idle", "out"} /\ grp < G
    [] k = "wfirst" -> mode = "px" /\ n = w /\ ph = "px" /\ wph[w] = "idle" /\ passes < P
    [] k \in {"sep", "val"} -> n = w /\ rows[n] < R /\ dev[n].sz < Max
                                /\ IF n = "o" THEN mode = "serial" /\ ph = "acc" ELSE wph[n] = "acc"
    [] k = "msep" -> n = "o" /\ ph = "px" /\ ocnt /\ wph[w] = "acc" /\ ~sepv.nul /\ dev["o"].sz < Max
    [] k = "mval" -> n = "o" /\ ph = "px" /\ ocnt /\ wph[w] = (IF sepv.nul THEN "acc" ELSE "msep")
                     /\ dev["o"].sz < Max

After(n, w, k) ==
  CASE k = "first" -> /\ ph' = "acc" /\ rows' = [rows EXCEPT !["o"] = 1] /\ grp' = grp + 1
                      /\ UNCHANGED <<wph, passes>>
    [] k = "wfirst" -> /\ wph' = [wph EXCEPT ![w] = "acc"] /\ rows' = [rows EXCEPT ![w] = 1]
                       /\ passes' = passes + 1 /\ UNCHANGED <<ph, grp>>
    [] k \in {"sep", "val"} -> /\ rows' = [rows EXCEPT ![n] = @ + 1] /\ UNCHANGED <<ph, wph, passes, grp>>
    [] k = "msep" -> /\ wph' = [wph EXCEPT ![w] = "msep"] /\ UNCHANGED <<ph, rows, passes, grp>>
    [] k = "mval" -> /\ wph' = [wph EXCEPT ![w] = "idle"] /\ UNCHANGED <<ph, rows, passes, grp>>

\* @type: (Str, Str, Str, $val, $val, Int, Bool, Bool) => Bool;
AppStep(n, w, k, vd, vp, sp, g1, g2) ==
  /\ Live /\ Guard(n, w, k)
  /\ LET a0 == IF k \in {"first", "wfirst"} THEN Empty(at) ELSE dev[n]
         b0 == IF k \in {"first", "wfirst"} THEN Empty(at) ELSE pr[n]
     IN DoApp(n, IF k = "mval" THEN w ELSE "none", a0, b0, k \in {"first", "wfirst"} \/ fresh[n], vd, vp, sp, g1, g2)
  /\ After(n, w, k)
  /\ UNCHANGED <<ora, mode, at, dcs, sepv, ocnt, outv, written, staleW>>

\* res_size >= group_concat_max_len: qdata_concatenate_dbval appends nothing
Full(n, w, k) ==
  /\ Live
  /\ CASE k \in {"sep", "val"} -> n = w /\ rows[n] < R /\ dev[n].sz >= Max
                                  /\ IF n = "o" THEN mode = "serial" /\ ph = "acc" ELSE wph[n] = "acc"
       [] k = "msep" -> n = "o" /\ ph = "px" /\ ocnt /\ wph[w] = "acc" /\ ~sepv.nul /\ dev["o"].sz >= Max
       [] k = "mval" -> n = "o" /\ ph = "px" /\ ocnt /\ wph[w] = (IF sepv.nul THEN "acc" ELSE "msep")
                        /\ dev["o"].sz >= Max
  /\ dev' = Upd(dev, "none", NullV(at), IF k = "mval" THEN w ELSE "none")
  /\ pr' = Upd(pr, "none", NullV(at), IF k = "mval" THEN w ELSE "none")
  /\ After(n, w, k)
  /\ seen' = seen \cup {"full"}
  /\ UNCHANGED <<ora, mode, at, dcs, sepv, fresh, ocnt, errd, outv, written, assertF, staleW>>

\* px: rehome_agg_list (BORROW) at the start of a parallel BUILDVALUE scan: the coordinator's value is
\* NULL (qdata_initialize_aggregate_list) and rehome_agg_value returns at once
Borrow ==
  /\ mode = "px" /\ ph \in {"idle", "out"} /\ grp < G /\ Live
  /\ ph' = "px" /\ ocnt' = FALSE /\ passes' = 0 /\ grp' = grp + 1
  /\ dev' = [dev EXCEPT !["o"] = NullV(at)] /\ pr' = [pr EXCEPT !["o"] = NullV(at)]
  /\ UNCHANGED <<ora, mode, at, dcs, sepv, fresh, wph, rows, errd, outv, written, assertF, staleW, seen>>

\* finalize_node: the coordinator's node is empty -> capacity = 0 + pr_clone_value of the worker's value
MergeClone(w) ==
  /\ ph = "px" /\ wph[w] = "acc" /\ ~ocnt /\ Live
  /\ dev' = [dev EXCEPT !["o"] = Clone(dev[w]), ![w] = NullV(at)]
  /\ pr' = [pr EXCEPT !["o"] = Clone(pr[w]), ![w] = NullV(at)]
  /\ fresh' = [fresh EXCEPT !["o"] = TRUE]
  /\ ocnt' = TRUE /\ wph' = [wph EXCEPT ![w] = "idle"]
  /\ seen' = seen \cup {"merge-clone"} \cup Seen("clone-erases", pr[w].p = Float /\ IsVar(pr[w].t))
  /\ UNCHANGED <<ora, mode, at, dcs, sepv, ph, rows, passes, grp, errd, outv, written, assertF, staleW>>

\* read (): rehome_agg_list (RESTORE): the coordinator's value is cloned back onto its own heap
Restore ==
  /\ mode = "px" /\ ph = "px" /\ Live /\ \A w \in Workers : wph[w] = "idle"
  /\ dev' = [dev EXCEPT !["o"] = Clone(dev["o"])] /\ pr' = [pr EXCEPT !["o"] = Clone(pr["o"])]
  /\ fresh' = [fresh EXCEPT !["o"] = TRUE]
  /\ ph' = "rest"
  /\ seen' = seen \cup Seen("restore-erases", ~pr["o"].nul /\ pr["o"].p = Float /\ IsVar(pr["o"].t))
  /\ UNCHANGED <<ora, mode, at, dcs, sepv, wph, ocnt, rows, passes, grp, errd, outv, written, assertF, staleW>>

\* qdata_finalize_aggregate_list: db_string_fix_string_size on a non-NULL character result (strlen
\* stops at the first zero byte); it remakes the value, so db_make_db_char clears the compression cache.
\* The mutant keeps the cache, as an in-place size fix would.
\* @type: ($val) => $val;
FixSize(x) ==
  IF x.nul \/ x.t \in Bits THEN x
  ELSE LET m == IF x.zp # Unk THEN Mk(x.t, x.p, x.zp, x.zl, Unk, Unk, x.cs, x.co)
                ELSE Mk(x.t, x.p, x.sz, x.ln, Unk, Unk, x.cs, x.co)
       IN IF Mutant = "compress-mid" THEN [m EXCEPT !.cmp = x.cmp] ELSE m

Fin ==
  /\ Live /\ IF mode = "serial" THEN ph = "acc" ELSE ph = "rest"
  /\ dev' = [dev EXCEPT !["o"] = FixSize(dev["o"])] /\ pr' = [pr EXCEPT !["o"] = FixSize(pr["o"])]
  /\ ph' = "fin"
  /\ UNCHANGED <<ora, mode, at, dcs, sepv, fresh, wph, ocnt, rows, passes, grp, errd, outv, written,
                 assertF, staleW, seen>>

\* pr_do_db_value_string_compression from mr_lengthval/writeval_string: the result written to the
\* output list; the mutant also lets it run on an accumulator between appends
CanCompress(n) ==
  \/ n = "o" /\ ph = "fin"
  \/ Mutant = "compress-mid" /\ (IF n = "o" THEN ph = "acc" ELSE wph[n] = "acc")
\* @type: ($val) => $val;
Cmp(x) == IF ~x.nul /\ x.t \in Chars /\ x.cmp = "ny" THEN [x EXCEPT !.cmp = IF x.sz >= Thresh THEN "ok" ELSE "un"] ELSE x
Compress(n) ==
  /\ Live /\ CanCompress(n)
  /\ \E s \in Sides : ~Acc(s, n).nul /\ Acc(s, n).t \in Chars /\ Acc(s, n).cmp = "ny"
  /\ dev' = [dev EXCEPT ![n] = Cmp(dev[n])] /\ pr' = [pr EXCEPT ![n] = Cmp(pr[n])]
  /\ UNCHANGED <<ora, mode, at, dcs, sepv, fresh, ph, wph, ocnt, rows, passes, grp, errd, outv, written,
                 assertF, staleW, seen>>

\* the output tuple is written; the accumulator is then cleared (qexec_clear_agg_list) or moved out
\* (qexec_gby_finalize_group_dim), and the next group starts from qdata_initialize_aggregate_list
Write ==
  /\ ph = "fin" /\ Live
  /\ outv' = [s \in Sides |-> Acc(s, "o")] /\ written' = TRUE
  /\ staleW' = (staleW \/ dev["o"].cmp = "st" \/ pr["o"].cmp = "st")
  /\ dev' = [dev EXCEPT !["o"] = NullV(at)] /\ pr' = [pr EXCEPT !["o"] = NullV(at)]
  /\ ph' = "out"
  /\ seen' = seen \cup Seen("out-VC", dev["o"].t = "VC") \cup Seen("out-VB", dev["o"].t = "VB")
             \cup Seen("out-ok", pr["o"].cmp = "ok") \cup Seen("out-float", ~pr["o"].nul /\ pr["o"].p = Float)
  /\ UNCHANGED <<ora, mode, at, dcs, sepv, fresh, wph, ocnt, rows, passes, grp, errd, assertF>>

Terminating ==
  /\ (~Live \/ (grp = G /\ ph = "out"))
  /\ UNCHANGED vars

Init ==
  /\ ora \in Oracles
  /\ mode \in Modes
  /\ at \in AggTypes
  /\ dcs \in (IF at \in Bits THEN {"raw"} ELSE Css)
  /\ sepv \in SepSet(at)
  /\ dev = [n \in Nodes |-> NullV(at)]
  /\ pr = [n \in Nodes |-> NullV(at)]
  /\ fresh = [n \in Nodes |-> TRUE]
  /\ ph = "idle"
  /\ wph = [w \in Workers |-> "idle"]
  /\ ocnt = FALSE
  /\ rows = [n \in Nodes |-> 0]
  /\ passes = 0
  /\ grp = 0
  /\ errd = [s \in Sides |-> FALSE]
  /\ outv = [s \in Sides |-> NullV(at)]
  /\ written = FALSE
  /\ assertF = FALSE
  /\ staleW = FALSE
  /\ seen = {}

Vals == {"C", "VC", "B", "VB"} \X ({Float} \cup 1..VP) \X (0..VSz) \X (0..VSz) \X (Css \cup {"raw"}) \X {0, DomColl}
\* the input values ValOK admits under some oracle setting (constant: TLC computes it once)
ValsWF == {f \in Vals : LET x == MkV(f[1], f[2], f[3], f[4], f[5], f[6]) IN
                          /\ x.ln <= x.sz
                          /\ (x.t \in Bits) => (x.ln = x.sz /\ x.cs = "raw" /\ x.co = 0)
                          /\ (x.t \in Chars) => (x.sz > 0 <=> x.ln > 0) /\ x.cs \in Css /\ x.co = DomColl
                          /\ x.p # Float => x.ln <= x.p
                          /\ (x.t \in Padded /\ x.p # Float /\ x.sz > 0) => x.ln = x.p}
\* the (adj, cnt) choices CutValid admits
\* @type: ($val, Int) => Set(<<Int, Int>>);
CutPairs(x, res) == {c \in (0..Max) \X (0..Max) : CutValid(x, res, c[1], c[2])}

\* one value or separator call on node n with worker w: x cut for the accumulator's res bytes
\* @type: (Str, Str, Str, $val, Int, Int, Int, Bool, Bool) => Bool;
Feed(n, w, k, x, res, adj, cnt, g1, g2) ==
  /\ LET v == CutV(x, res, adj, cnt) IN AppStep(n, w, k, v, v, CutSp(x, res, adj), g1, g2)

\* finalize_node's worker value (each side its own clone), cut for the coordinator's res bytes
\* @type: (Str, Int, Int, Int, Bool, Bool) => Bool;
FeedW(w, res, adj, cnt, g1, g2) ==
  /\ LET vd == CutV(dev[w], res, adj, cnt) vp == CutV(pr[w], res, adj, cnt)
     IN AppStep("o", w, "mval", vd, vp, CutSp(dev[w], res, adj), g1, g2)

Next ==
  \/ \E f \in ValsWF, g1, g2 \in BOOLEAN :
        LET x == MkV(f[1], f[2], f[3], f[4], f[5], f[6]) IN
        /\ ArgOK(x)
        /\ \/ \E c \in CutPairs(x, 0) : Feed("o", "o", "first", x, 0, c[1], c[2], g1, g2)
           \/ \E n \in Nodes : dev[n].sz < Max /\ \E c \in CutPairs(x, dev[n].sz) :
                Feed(n, n, "val", x, dev[n].sz, c[1], c[2], g1, g2)
           \/ \E w \in Workers, c \in CutPairs(x, 0) : Feed(w, w, "wfirst", x, 0, c[1], c[2], g1, g2)
  \/ \E g1, g2 \in BOOLEAN :
        /\ ~sepv.nul
        /\ \/ \E n \in Nodes : dev[n].sz < Max /\ \E c \in CutPairs(sepv, dev[n].sz) :
                Feed(n, n, "sep", sepv, dev[n].sz, c[1], c[2], g1, g2)
           \/ \E w \in Workers : dev["o"].sz < Max /\ \E c \in CutPairs(sepv, dev["o"].sz) :
                Feed("o", w, "msep", sepv, dev["o"].sz, c[1], c[2], g1, g2)
  \/ \E w \in Workers, g1, g2 \in BOOLEAN :
        dev["o"].sz < Max /\ \E c \in CutPairs(dev[w], dev["o"].sz) : FeedW(w, dev["o"].sz, c[1], c[2], g1, g2)
  \/ \E n \in Nodes, k \in {"sep", "val"} : Full(n, n, k)
  \/ \E w \in Workers, k \in {"msep", "mval"} : Full("o", w, k)
  \/ Borrow
  \/ \E w \in Workers : MergeClone(w)
  \/ Restore
  \/ Fin
  \/ \E n \in Nodes : Compress(n)
  \/ Write
  \/ Terminating

Spec == Init /\ [][Next]_vars

\* the state without the witness flags (pass cfgs)
NoSeen == <<ora, mode, at, dcs, sepv, dev, pr, fresh, ph, wph, ocnt, rows, passes, grp, errd, outv,
            written, assertF, staleW>>

(***************************************************************************)
(* Properties                                                              *)
(***************************************************************************)

\* C6: db_string_append leaves string1 what db_string_concatenate (string1, string2, string1) leaves it
AccEq == \A n \in Nodes : dev[n] = pr[n]
\* @type: ($val) => $val;
NoP(x) == [x EXCEPT !.p = 0]
AccEqButP == \A n \in Nodes : NoP(dev[n]) = NoP(pr[n])

\* C7: the result a reader gets: the type, the precision a domain is resolved to
\* (tp_domain_resolve_value, db_make_* turn -1 into the maximum), the bytes, the length, codeset,
\* collation, NULL
\* @type: ($val) => { t: Str, p: Int, sz: Int, len: Int, cs: Str, co: Int, nul: Bool };
View(x) ==
  [t |-> x.t, p |-> DomInit(x.t, x.p), sz |-> x.sz, len |-> Getter(x), cs |-> x.cs, co |-> x.co,
   nul |-> x.nul]
OutEq == written => outv["dev"] = outv["pr"]
OutView == written => View(outv["dev"]) = View(outv["pr"])
\* @type: ($val) => { t: Str, sz: Int, len: Int, cs: Str, co: Int, nul: Bool };
ViewNoP(x) == [t |-> x.t, sz |-> x.sz, len |-> Getter(x), cs |-> x.cs, co |-> x.co, nul |-> x.nul]
OutViewButP == written => ViewNoP(outv["dev"]) = ViewNoP(outv["pr"])
ErrEq == errd["dev"] = errd["pr"]

\* C8: a compressed copy of other bytes is never written
NoStaleWrite == ~staleW

\* C9: the cached length is the content's
LenCache ==
  \A s \in Sides, n \in Nodes :
    LET x == Acc(s, n) IN (~x.nul /\ x.t \in Chars /\ x.lc # Unk) => x.lc = x.ln

\* C10: db_string_append_zero_bytes is called on a VARCHAR only
NoAssert == ~assertF

\* a value's precision bounds its length
PrecBound ==
  \A s \in Sides, n \in Nodes :
    LET x == Acc(s, n) IN (~x.nul /\ x.p # Float) => x.p >= Getter(x)

\* Witnesses (each expected violated)
NotSeen(e) == e \notin seen
NotPad == NotSeen("pad")
NotSpare == NotSeen("spare")
NotTruncNull == NotSeen("trunc-null")
NotCoerceAcc == NotSeen("coerce-acc")
NotCoerceV == NotSeen("coerce-v")
NotEmptySep == NotSeen("empty-sep")
NotPrFloat == NotSeen("pr-float")
NotPrFinite == NotSeen("pr-finite")
NotFull == NotSeen("full")
NotMergeClone == NotSeen("merge-clone")
NotMergeApp == NotSeen("merge-app")
NotMergeCut == NotSeen("merge-cut")
NotCloneErases == NotSeen("clone-erases")
NotRestoreErases == NotSeen("restore-erases")
NotOutVC == NotSeen("out-VC")
NotOutVB == NotSeen("out-VB")
NotOutOk == NotSeen("out-ok")
NotOutFloat == NotSeen("out-float")
(***************************************************************************)
(* Inductive invariant (the candidate fix: Fix = "prec", SepFix)           *)
(***************************************************************************)
Types == {"C", "VC", "B", "VB"}
SzMax == Max + VP + 3
\* @type: ($val) => Bool;
ValR(x) ==
  /\ x.t \in Types /\ x.p \in {Float} \cup 1..MaxP /\ x.sz \in 0..SzMax /\ x.ln \in 0..SzMax
  /\ x.lc \in {Unk} \cup 0..SzMax /\ x.zp \in {Unk} \cup 0..SzMax /\ x.zl \in {Unk} \cup 0..SzMax
  /\ x.cs \in Css \cup {"raw", "n"} /\ x.co \in {0, DomColl} /\ x.cmp \in {"ny", "un", "ok", "st"}
Events == {"pad", "spare", "trunc-null", "coerce-acc", "coerce-v", "empty-sep", "pr-float", "pr-finite",
           "merge-app", "merge-cut", "merge-clone", "clone-erases", "restore-erases", "full", "out-VC", "out-VB",
           "out-ok", "out-float"}

TypeOK ==
  /\ ora \in BOOLEAN /\ mode \in Modes /\ at \in AggTypes /\ dcs \in Css \cup {"raw"}
  /\ ValR(sepv)
  /\ DOMAIN dev = Nodes /\ DOMAIN pr = Nodes /\ fresh \in [Nodes -> BOOLEAN]
  /\ \A n \in Nodes : ValR(dev[n]) /\ ValR(pr[n])
  /\ ph \in {"idle", "acc", "px", "rest", "fin", "out"} /\ wph \in [Workers -> {"idle", "acc", "msep"}]
  /\ ocnt \in BOOLEAN /\ rows \in [Nodes -> 0..R] /\ passes \in 0..P /\ grp \in 0..G
  /\ errd \in [Sides -> BOOLEAN] /\ DOMAIN outv = Sides /\ \A x \in Sides : ValR(outv[x])
  /\ written \in BOOLEAN /\ assertF \in BOOLEAN /\ staleW \in BOOLEAN /\ seen \in SUBSET Events

\* an accumulator a group left: VARCHAR, VARBIT, or BIT when only bits were appended to a BIT start;
\* a VARCHAR or VARBIT one has the maximum precision (develop's db_value_domain_init)
\* @type: ($val) => Bool;
AccOK(x) ==
  \/ x.nul /\ x.t = at /\ x = NullV(at)
  \/ /\ ~x.nul /\ x.t \in {"VC", "VB", "B"} /\ Cat(x.t) = Cat(at) /\ (x.t = "B" => at = "B")
     /\ IsVar(x.t) => x.p = MaxP
     /\ x.t = "B" => x.p = Float
     \* the cut keeps res_size within group_concat_max_len; a cut character leaves at most 3 spare bytes
     /\ x.sz <= Max + 3
     /\ x.cmp \in {"ny", "un", "ok"}
     /\ x.t \in Bits => x.ln = x.sz /\ x.lc = Unk /\ x.cs = "raw" /\ x.co = 0 /\ x.zp = Unk /\ x.zl = Unk
     /\ x.t \in Chars => /\ x.ln <= x.sz /\ (x.sz = 0 <=> x.ln = 0) /\ x.lc \in {Unk, x.ln}
                          /\ x.cs \in Css /\ x.co = DomColl
                          /\ (x.zp = Unk <=> x.zl = Unk)
                          \* a zero byte at byte zp after zl characters: a character takes at least one byte
                          /\ (x.zp # Unk => /\ x.zl <= x.zp /\ x.zp < x.sz /\ x.zl < x.ln /\ (x.zp = 0 <=> x.zl = 0)
                                            \* the first value is never cut to nothing, so a character precedes the spare bytes
                                            /\ x.zp > 0
                                            \* only zero bytes follow the first one (the spare bytes of a cut)
                                            /\ x.ln - x.zl = x.sz - x.zp
                                            \* spare bytes are written only when the cut fills the accumulator
                                            /\ x.sz >= Max)
     /\ ora => x.sz > 0
     /\ x.p # Float => x.p >= Getter(x)

IAcc == \A n \in Nodes : AccOK(dev[n])
INoErr == ~errd["dev"] /\ ~errd["pr"] /\ ~assertF /\ ~staleW
ISep == /\ sepv.nul => sepv = NullV(at)
        /\ ~sepv.nul => /\ ValOK(sepv) /\ Cat(sepv.t) = Cat(at) /\ sepv.t \in Chars
                         /\ sepv = MkV(sepv.t, sepv.p, sepv.sz, sepv.ln, sepv.cs, sepv.co)
                         /\ sepv.p \in {Float} \cup 1..VP /\ sepv.sz <= VSz /\ sepv.cs \in Css
ICmp == \A n \in Nodes : dev[n].cmp # "ny" => n = "o" /\ ph = "fin"
ISerial == mode = "serial" => ph \in {"idle", "acc", "fin", "out"} /\ \A w \in Workers : wph[w] = "idle" /\ dev[w].nul
IPx == mode = "px" => ph \in {"idle", "px", "rest", "fin", "out"}
IIdle == ph \in {"idle", "out"} => dev["o"].nul /\ \A w \in Workers : wph[w] = "idle"
IAccPh == ph = "acc" => ~dev["o"].nul
IOcnt == ph = "px" => (ocnt <=> ~dev["o"].nul)
IRest == ph \in {"rest", "fin", "out"} => \A w \in Workers : wph[w] = "idle"
IWph == \A w \in Workers : (wph[w] = "idle" <=> dev[w].nul) /\ (wph[w] # "idle" => ph = "px")
IMsep == \A w \in Workers : wph[w] = "msep" => ~sepv.nul /\ ocnt
IOut == /\ written => outv["dev"] = outv["pr"] /\ AccOK(outv["dev"])
        /\ ~written => outv = [s \in Sides |-> NullV(at)]

IndInv ==
  /\ TypeOK
  /\ AccEq
  /\ IAcc
  /\ INoErr
  /\ ISep
  /\ ICmp
  /\ ISerial
  /\ IPx
  /\ IIdle
  /\ IAccPh
  /\ IOcnt
  /\ IRest
  /\ IWph
  /\ IMsep
  /\ IOut

=============================================================================
