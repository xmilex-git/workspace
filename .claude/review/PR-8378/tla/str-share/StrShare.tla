------------------------------ MODULE StrShare ------------------------------
(* CUBRID/cubrid#8378 (CBRD-27847) at c45aac991: heap_attrinfo_set_converted ()
   shares the buffer of a CHAR / VARCHAR / BIT / BIT VARYING value that
   heap_attrinfo_can_share_string () accepts, and casts every other value.

   One Assign step is one call of heap_attrinfo_set_converted () for one
   attribute of the row the executor is writing; Build is the record build
   (locator_allocate_copy_area_by_attr_info) that reads every value the row
   set. Everything runs in the one thread that executes the statement: the
   holders of a shared buffer (a list file tuple, the plan's constant, the
   scan cache area that holds an ODKU's old row, a reevaluated value) are
   private to it, so the model needs no interleaving, only the order of the
   assignments, the early releases and the build.

   Values are abstract: a value has a type, the type the plan expects (pt), a
   codeset and collation, a precision (0 = unset), a length in characters or
   bits, whether its characters take more bytes than one (wide), whether it
   owns its buffer (nc = DB_NEED_CLEAR) and who holds its buffer (h). *)
EXTENDS Integers, FiniteSets

CONSTANTS MaxPrec, NCols, Rows, Mutant, ReevOn

\* Types for Apalache (tools/tla/apalache-types writes them into the declarations).
\* apalache-type: MaxPrec Int
\* apalache-type: NCols Int
\* apalache-type: Rows Int
\* apalache-type: Mutant Str
\* apalache-type: ReevOn Bool
\* apalache-type: row Int
\* apalache-type: ncol Int
\* apalache-type: borrows Set({h: Str, nc: Bool, freed: Bool})
\* apalache-type: eqViol Bool
\* apalache-type: errViol Bool
\* apalache-type: shareViol Bool
\* apalache-type: uafOwned Bool
\* apalache-type: uafPage Bool
\* apalache-type: sawCharCount Bool
\* apalache-type: sawNonSpaceFull Bool
\* apalache-type: sawCastErr Bool

VARIABLES row, ncol, borrows, eqViol, errViol, shareViol, uafOwned, uafPage,
          sawCharCount, sawNonSpaceFull, sawCastErr
vars == <<row, ncol, borrows, eqViol, errViol, shareViol, uafOwned, uafPage,
          sawCharCount, sawNonSpaceFull, sawCastErr>>

-----------------------------------------------------------------------------
(* Input classes *)
(* Apalache type aliases and operator types: TLC reads them as comments. *)
\* @typeAlias: col = {t: Str, cs: Str, co: Str, p: Int};
\* @typeAlias: val = {t: Str, pt: Str, cs: Str, co: Str, p: Int, len: Int, wide: Bool, nc: Bool};
\* @typeAlias: attr = {err: Str, t: Str, cs: Str, co: Str, p: Int, chars: Int, wide: Bool, pad: Str, padN: Int};
\* @typeAlias: pair = {cs: Str, co: Str};
\* @typeAlias: run = {b: Str, n: Int};
\* @typeAlias: runs = {first: $run, second: $run};
StrShareAliases == TRUE

CharTypes == {"C", "V"}
BitTypes == {"B", "VB"}
IsChar(t) == t \in CharTypes
IsFixed(t) == t \in {"C", "B"}
IsVar(t) == t \in {"V", "VB"}
SameFamily(t, u) == IsChar(t) = IsChar(u)

\* codeset / collation pairs: a collation belongs to one codeset (LANG_COLLATION);
\* a DB_VALUE stores the two apart, so one inconsistent pair is an input too
\* @type: (Str, Str) => $pair;
Pair(c, k) == [cs |-> c, co |-> k]
ColPairs == {Pair("u", "ubin"), Pair("u", "uci"), Pair("i", "ibin"), Pair("e", "ebin"), Pair("b", "bin")}
ValPairs == ColPairs \cup {Pair("i", "ubin")}
BitPair == Pair("n", "n")

ColPrecs == {2, MaxPrec}
ValPrecs == 0 .. (MaxPrec + 1)
Lens == 0 .. (MaxPrec + 1)

Holders == IF ReevOn THEN {"tuple", "const", "odku", "reevExpr", "reevPage"}
           ELSE {"tuple", "const", "odku"}

\* @type: (Str, $pair, Int) => $col;
Col(t, pr, p) == [t |-> t, cs |-> pr.cs, co |-> pr.co, p |-> p]

\* @type: (Str, Str, $pair, Int, Int, Bool, Bool) => $val;
Val(t, pt, pr, p, l, w, nc) ==
  [t |-> t, pt |-> pt, cs |-> pr.cs, co |-> pr.co, p |-> p, len |-> l, wide |-> w, nc |-> nc]
\* the columns, and the values of each family (a string into a bit column, or a bit string into a
\* string column, takes the converter path and is not modeled); a bit value has no codeset; only
\* utf8 and euckr characters take more than one byte here. Zero-arity sets: TLC builds them once.
Cols == {Col(t, pr, p) : t \in CharTypes, pr \in ColPairs, p \in ColPrecs}
        \cup {Col(t, BitPair, p) : t \in BitTypes, p \in ColPrecs}
CharVals == {v \in {Val(t, pt, pr, p, l, w, nc) :
                       t \in CharTypes, pt \in CharTypes, pr \in ValPairs, p \in ValPrecs, l \in Lens,
                       w \in BOOLEAN, nc \in BOOLEAN} :
               v.wide => v.cs \in {"u", "e"}}
BitVals == {Val(t, pt, BitPair, p, l, FALSE, nc) :
              t \in BitTypes, pt \in BitTypes, p \in ValPrecs, l \in Lens, nc \in BOOLEAN}
\* @type: ($col) => Set($val);
ValsFor(d) == IF IsChar(d.t) THEN CharVals ELSE BitVals
\* who holds a buffer: a page pointer (reevPage) never owns it
\* @type: ($val) => Set(Str);
HoldersFor(v) == IF v.nc THEN Holders \ {"reevPage"} ELSE Holders

-----------------------------------------------------------------------------
(* heap_attrinfo_can_share_string () and the branch of heap_attrinfo_set_converted () *)

\* the value's precision as tp_domain_resolve_value makes it: an unset variable one is the maximum
\* @type: ($val) => Int;
NormP(v) == IF IsVar(v.t) /\ v.p = 0 THEN MaxPrec ELSE v.p
\* the code's `precision`; mutants: no normalization, or an oversized one taken as the maximum too
\* @type: ($val) => Int;
CodeP(v) == IF Mutant = "no_unset_norm" THEN v.p
            ELSE IF Mutant = "over_as_max" /\ IsVar(v.t) /\ v.p > MaxPrec THEN MaxPrec
            ELSE NormP(v)
\* @type: ($val) => Int;
Size(v) == IF v.wide THEN 3 * v.len ELSE v.len

\* @type: ($val, $col) => Bool;
CanShareString(v, d) ==
  LET P == CodeP(v) IN
  /\ (Mutant # "no_needclear" => ~v.nc)
  /\ IsChar(d.t) => /\ (Mutant # "no_codeset" => v.cs = d.cs)
                    /\ (Mutant # "no_collation" => v.co = d.co)
  /\ (Mutant # "no_precision" => P = d.p)
  /\ IF IsFixed(d.t)
       THEN IF Mutant = "char_any_len" THEN v.len <= P ELSE v.len = P
     ELSE IF Mutant = "trust_precision" THEN TRUE
     ELSE IF d.t = "V" /\ Size(v) <= P THEN TRUE
     ELSE IF Mutant = "size_only" /\ d.t = "V" THEN FALSE
     ELSE v.len <= P

\* value_type == catalog type, DB_VALUE_DOMAIN_TYPE (attr_val) == value_type, then the string test;
\* mutant develop: the merge-base, which shares no string
\* @type: ($val, $col) => Bool;
Shares(v, d) ==
  /\ Mutant # "develop"
  /\ v.pt = d.t
  /\ (Mutant # "no_premise" => v.t = v.pt)
  /\ CanShareString(v, d)

-----------------------------------------------------------------------------
(* What each path leaves in the attribute, and the record bytes it writes *)

\* @type: ($col) => Str;
PadOf(d) == IF IsChar(d.t)
            THEN CASE d.cs = "e" -> "a1a1" [] d.cs = "b" -> "00" [] OTHER -> "sp"
            ELSE "0bit"
\* @type: ($col) => Str;
WriterPad(d) == IF IsChar(d.t) THEN "sp" ELSE "0bit"

NoErr == "none"
\* tp_value_auto_cast_with_precision_check into the catalog domain: converts the codeset,
\* fails a value longer than the precision, pads a fixed type with the codeset's pad character
\* @type: ($val, $col) => $attr;
Cast(v, d) ==
  IF v.len > d.p
  THEN [err |-> "trunc", t |-> d.t, cs |-> d.cs, co |-> d.co, p |-> d.p, chars |-> 0, wide |-> FALSE,
        pad |-> "none", padN |-> 0]
  ELSE [err |-> NoErr, t |-> d.t, cs |-> d.cs, co |-> d.co, p |-> d.p, chars |-> v.len, wide |-> v.wide,
        pad |-> IF IsFixed(d.t) /\ v.len < d.p THEN PadOf(d) ELSE "none",
        padN |-> IF IsFixed(d.t) THEN d.p - v.len ELSE 0]
\* the shared setval: the value as it is; an oversized precision is refused (ER_INVALID_PRECISION)
\* @type: ($val) => $attr;
Setval(v) ==
  [err |-> IF v.p > MaxPrec THEN "invprec" ELSE NoErr, t |-> v.t, cs |-> v.cs, co |-> v.co, p |-> NormP(v),
   chars |-> v.len, wide |-> v.wide, pad |-> "none", padN |-> 0]

\* @type: ($attr) => Int;
ALen(a) == a.chars + a.padN
\* the record writer pads a fixed-type value shorter than the column with a space (zero bits)
\* @type: (Str, Int) => $run;
Run(b, n) == [b |-> b, n |-> n]
\* @type: ($attr, $col) => $runs;
Runs(a, d) ==
  LET wn == IF IsFixed(d.t) /\ ALen(a) < d.p THEN d.p - ALen(a) ELSE 0
      none == Run("none", 0)
      r1 == IF a.padN > 0 THEN Run(a.pad, a.padN) ELSE none
      r2 == IF wn > 0 THEN Run(WriterPad(d), wn) ELSE none
  IN IF r1.n = 0 THEN [first |-> r2, second |-> none]
     ELSE IF r2.n = 0 THEN [first |-> r1, second |-> none]
     ELSE IF r1.b = r2.b THEN [first |-> Run(r1.b, r1.n + r2.n), second |-> none]
     ELSE [first |-> r1, second |-> r2]
\* @type: ($attr, $col) => <<Str, Int, Bool, $runs>>;
Record(a, d) == <<a.cs, a.chars, a.wide, Runs(a, d)>>
\* the attribute value's domain as tp_domain_resolve_value reads it
\* @type: ($attr) => <<Str, Str, Str, Int, Int>>;
Dom(a) == <<a.t, a.cs, a.co, a.p, ALen(a)>>

\* @type: ($attr, $attr, $col) => Bool;
SameAsCast(a, c, d) == a.err = NoErr /\ c.err = NoErr => Record(a, d) = Record(c, d) /\ Dom(a) = Dom(c)

\* C4: what the PR promises to share
\* @type: ($val, $col) => Bool;
Eligible(v, d) ==
  /\ v.t = d.t /\ v.pt = d.t /\ ~v.nc
  /\ IsChar(d.t) => v.cs = d.cs /\ v.co = d.co
  /\ NormP(v) = d.p
  /\ IF IsFixed(d.t) THEN v.len = d.p ELSE v.len <= d.p

\* a holder that lets the buffer go between the assignment and the build:
\* locator_mvcc_reev_cond_assigns clears an owned reevaluated value right after it;
\* locator_mvcc_reeval_scan_filters ends its local scan cache (unfixes the page) before the force;
\* mutant odku_reread: the force rereads the old row into the scan cache area the ODKU values point into
EarlyRelease(h, nc) ==
  \/ h = "reevExpr" /\ nc
  \/ h = "reevPage"
  \/ h = "odku" /\ Mutant = "odku_reread"

-----------------------------------------------------------------------------
Init ==
  /\ row = 0 /\ ncol = 0 /\ borrows = {}
  /\ eqViol = FALSE /\ errViol = FALSE /\ shareViol = FALSE /\ uafOwned = FALSE /\ uafPage = FALSE
  /\ sawCharCount = FALSE /\ sawNonSpaceFull = FALSE /\ sawCastErr = FALSE

\* heap_attrinfo_set_converted (): one attribute of the row
\* @type: ($val, $col) => Bool;
AssignWith(v, d) ==
  LET s == Shares(v, d)
      c == Cast(v, d)
      a == IF s THEN Setval(v) ELSE c
  IN
  /\ eqViol' = (eqViol \/ ~SameAsCast(a, c, d))
  /\ errViol' = (errViol \/ a.err # c.err)
  /\ shareViol' = (shareViol \/ (Eligible(v, d) /\ ~s))
  /\ sawCharCount' = (sawCharCount \/ (s /\ d.t = "V" /\ Size(v) > d.p))
  /\ sawNonSpaceFull' = (sawNonSpaceFull \/ (s /\ d.t = "C" /\ d.cs \in {"e", "b"}))
  /\ sawCastErr' = (sawCastErr \/ (~s /\ c.err # NoErr))
  /\ IF a.err # NoErr
       \* the statement fails: the row is not built
       THEN row' = row + 1 /\ ncol' = 0 /\ borrows' = {}
       ELSE /\ row' = row /\ ncol' = ncol + 1
            /\ IF s THEN \E h \in HoldersFor(v) :
                            borrows' = borrows \cup {[h |-> h, nc |-> v.nc, freed |-> EarlyRelease(h, v.nc)]}
                 ELSE borrows' = borrows
  /\ UNCHANGED <<uafOwned, uafPage>>

Assign ==
  /\ row < Rows /\ ncol < NCols
  /\ \E d \in Cols : \E v \in ValsFor(d) : AssignWith(v, d)

\* locator_allocate_copy_area_by_attr_info (): reads every value the row set
Build ==
  /\ row < Rows /\ ncol > 0
  /\ uafOwned' = (uafOwned \/ \E b \in borrows : b.freed /\ b.h # "reevPage")
  /\ uafPage' = (uafPage \/ \E b \in borrows : b.freed /\ b.h = "reevPage")
  /\ row' = row + 1 /\ ncol' = 0 /\ borrows' = {}
  /\ UNCHANGED <<eqViol, errViol, shareViol, sawCharCount, sawNonSpaceFull, sawCastErr>>

Finished == row = Rows /\ UNCHANGED vars

Next == Assign \/ Build \/ Finished
Spec == Init /\ [][Next]_vars

-----------------------------------------------------------------------------
(* Properties *)
Bools == BOOLEAN
TypeOK ==
  /\ row \in 0 .. Rows /\ ncol \in 0 .. NCols
  /\ borrows \subseteq [h : Holders, nc : Bools, freed : Bools]
  /\ {eqViol, errViol, shareViol, uafOwned, uafPage, sawCharCount, sawNonSpaceFull, sawCastErr} \subseteq Bools

SameValue == ~eqViol                \* C1
SameError == ~errViol               \* C3
SharesExact == ~shareViol           \* C4
NoDanglingOwned == ~uafOwned        \* C2 (owned values)
NoDanglingPage == ~uafPage          \* C2 (page pointers)
NoDangling == NoDanglingOwned /\ NoDanglingPage

\* a borrowed buffer released before the build is one only a reevaluation or the mutant can release
BorrowsInv ==
  \A b \in borrows : b.freed => (b.h \in {"reevExpr", "reevPage"} \/ Mutant = "odku_reread")
\* inductive: no violation yet, and nothing released early outside reevaluation when it is off
IndInv ==
  /\ row \in Nat /\ row <= Rows
  /\ ncol \in Nat /\ ncol <= NCols
  /\ borrows \in SUBSET [h : Holders, nc : BOOLEAN, freed : BOOLEAN]
  /\ eqViol = FALSE /\ errViol = FALSE /\ shareViol = FALSE /\ uafOwned = FALSE /\ uafPage = FALSE
  /\ sawCharCount \in BOOLEAN /\ sawNonSpaceFull \in BOOLEAN /\ sawCastErr \in BOOLEAN
  /\ \A b \in borrows : b.freed => b.h \in {"reevExpr", "reevPage"}
  /\ \A b \in borrows : b.freed /\ b.h = "reevExpr" => b.nc
  /\ ~ReevOn => \A b \in borrows : ~b.freed

\* witnesses
NotCharCount == ~sawCharCount
NotNonSpaceFull == ~sawNonSpaceFull
NotCastErr == ~sawCastErr

\* Apalache's constant initialization for the inductive cfg: every bound, reevaluation off
CInit == MaxPrec = 3 /\ NCols \in Nat /\ Rows \in Nat /\ Mutant = "none" /\ ReevOn = FALSE
=============================================================================
