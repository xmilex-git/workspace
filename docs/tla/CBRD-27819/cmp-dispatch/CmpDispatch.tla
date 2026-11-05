---------------------------- MODULE CmpDispatch ----------------------------
(* CBRD-27819 (CUBRID/cubrid#8349): which cmpval a decided comparison runs, and
   on which values.  An integer against a NUMERIC compares by an exact cmpval
   that reads the integer and the NUMERIC as they are; every other pair
   compares by the compared type's cmpval after the decided conversions.

   One run is one comparison: the client decides it (domain_compute_comparison,
   develop's rule for an old client, the PR's for a new one), the stream
   carries method / sources / conversions / target, the server installs a
   cmpval at one site (unpack, the key bound's mirror, the expression leaf) and
   the consumer converts the values and calls the cmpval.  A cmpval that reads a
   value of another type (db_get_bigint on a NUMERIC) is the defect class of
   7c1130bed and of the mirror finding (ghost "bad").

   Values are tenths (10 = 1.0) and exactly representable in every type the
   model converts to, so every type-safe comparison has the exact answer. *)
EXTENDS Integers

CONSTANTS MaxV, Mutant
ASSUME Assm == /\ MaxV \in Nat
               /\ Mutant \in {"none", "head", "pre_7c1130bed", "decide_converts",
                              "wrong_int_index", "no_reverse", "unpack_generic",
                              "expr_no_conv_check"}

\* values in tenths, every half step: -1.0, -0.5, 0, 0.5, 1.0 for MaxV = 10
Vals == {v \in -MaxV..MaxV : v % 5 = 0}
Ints == {"SHORT", "INT", "BIGINT"}
Types == Ints \cup {"NUMERIC", "DOUBLE"}
\* tp_more_general_type order of the numeric types
Rank(t) == CASE t = "SHORT" -> 1 [] t = "INT" -> 2 [] t = "BIGINT" -> 3
             [] t = "NUMERIC" -> 4 [] t = "DOUBLE" -> 5
Clients == {"old", "new"}
Sites == {"decide", "unpack", "mirror", "expr"}
Phases == {"decide", "install", "eval", "done"}
Bools == {FALSE, TRUE}

Holds(t, v) == t \in Ints => v % 10 = 0
Sign(x) == IF x > 0 THEN 1 ELSE IF x < 0 THEN -1 ELSE 0
Exact(a, b) == (a = "NUMERIC" /\ b \in Ints) \/ (b = "NUMERIC" /\ a \in Ints)

\* a cmpval: kind "generic" reads two values of .type; kind "exact" reads the
\* integer type .type and a NUMERIC, the NUMERIC first when .numFirst
Generic(t) == [kind |-> "generic", type |-> t, numFirst |-> FALSE]
IntIndex(t) == IF Mutant = "wrong_int_index"
                 THEN (IF t = "SHORT" THEN "INT" ELSE IF t = "INT" THEN "SHORT" ELSE t)
                 ELSE t
ExactCmp(s0, s1) == IF s1 = "NUMERIC" THEN [kind |-> "exact", type |-> IntIndex(s0), numFirst |-> FALSE]
                    ELSE [kind |-> "exact", type |-> IntIndex(s1), numFirst |-> TRUE]
\* domain_rules.c domain_compare_cmp () for a compare that converts neither side
DomainCompareCmp(s0, s1, compared) == IF Exact(s0, s1) THEN ExactCmp(s0, s1) ELSE Generic(compared)
Reads(c) == IF c.kind = "exact"
              THEN (IF c.numFirst THEN <<"NUMERIC", c.type>> ELSE <<c.type, "NUMERIC">>)
              ELSE <<c.type, c.type>>
Cmps == [kind : {"generic", "exact"}, type : Types, numFirst : Bools]
Compares == [method : {"DIRECT", "CONVERT"}, src : Types \X Types, conv : {0, 1} \X {0, 1},
             target : Types, cmp : Cmps]

\* domain_compute_comparison (): develop (old client) and the PR (new client).
\* A numeric pair of two types converts the less general side to the other's type.
DecSkip(client, a, b) == client = "new" /\ Exact(a, b) /\ Mutant # "decide_converts"
DecTarget(a, b) == IF Rank(a) >= Rank(b) THEN a ELSE b
DecConvNone(client, a, b) == a = b \/ DecSkip(client, a, b)
DecConv(client, a, b) == IF DecConvNone(client, a, b) THEN <<0, 0>>
                         ELSE <<IF a = DecTarget(a, b) THEN 0 ELSE 1, IF b = DecTarget(a, b) THEN 0 ELSE 1>>
DecAfter0(client, a, b) == IF DecConv(client, a, b)[1] = 1 THEN DecTarget(a, b) ELSE a
Decide(client, a, b) ==
  [method |-> IF DecConvNone(client, a, b) THEN "DIRECT" ELSE "CONVERT",
   src |-> <<a, b>>, conv |-> DecConv(client, a, b), target |-> DecTarget(a, b),
   cmp |-> IF client = "new" /\ DecConvNone(client, a, b) THEN DomainCompareCmp(a, b, DecAfter0(client, a, b))
           ELSE Generic(DecAfter0(client, a, b))]

\* stream_to_xasl.c stx_unpack_decided_compare (): the stream has no cmpval
Unpack(d) ==
  LET converts == d.conv[1] = 1 \/ d.conv[2] = 1
      compared == IF d.conv[1] = 1 THEN d.target ELSE d.src[1]
  IN [method |-> d.method, src |-> d.src, conv |-> d.conv, target |-> d.target,
      cmp |-> IF Mutant = "unpack_generic" THEN Generic(compared)
              ELSE IF ~converts \/ Mutant = "pre_7c1130bed" THEN DomainCompareCmp(d.src[1], d.src[2], compared)
              ELSE Generic(compared)]

\* domain_rules.c domain_compare_mirror () on an unpacked bound (stx_build_key_compares);
\* "head" is 7c1130bed, which picks the cmpval without looking at the conversions
Mirror(c) ==
  LET converts == c.conv[1] = 1 \/ c.conv[2] = 1
      compared == IF c.conv[2] = 1 THEN c.target ELSE c.src[2]
  IN [method |-> c.method, src |-> <<c.src[2], c.src[1]>>, conv |-> <<c.conv[2], c.conv[1]>>,
      target |-> c.target,
      cmp |-> IF ~converts \/ Mutant = "head" THEN DomainCompareCmp(c.src[2], c.src[1], compared)
              ELSE Generic(compared)]

\* expr_compile.c expr_pred_exact_number (): the generic leaf runs the decided
\* comparison on the unconverted values
ExprLeaf(c) == Exact(c.src[1], c.src[2])
               /\ (Mutant = "expr_no_conv_check" \/ (c.method = "DIRECT" /\ c.conv[1] = 0 /\ c.conv[2] = 0))

\* the types the consumer hands to the cmpval (domain_compare_converted converts first)
Actual(c) == <<IF c.conv[1] = 1 THEN c.target ELSE c.src[1], IF c.conv[2] = 1 THEN c.target ELSE c.src[2]>>
Answer(c, x, y) == IF c.kind = "exact" /\ c.numFirst /\ Mutant = "no_reverse" THEN Sign(y - x) ELSE Sign(x - y)

VARIABLES phase, client, site, ty, val, dec, inst, leaf, bad, wrong, usedExact
vars == <<phase, client, site, ty, val, dec, inst, leaf, bad, wrong, usedExact>>

None == [method |-> "DIRECT", src |-> <<"INT", "INT">>, conv |-> <<0, 0>>,
         target |-> "INT", cmp |-> Generic("INT")]

Init == /\ phase = "decide"
        /\ client \in Clients
        /\ site \in Sites
        /\ site = "decide" => client = "new"    \* an old client runs no PR code in-process
        /\ ty \in Types \X Types
        /\ val \in Vals \X Vals
        /\ Holds(ty[1], val[1]) /\ Holds(ty[2], val[2])
        /\ dec = None /\ inst = None
        /\ leaf = FALSE /\ bad = FALSE /\ wrong = FALSE /\ usedExact = FALSE

\* the client decides the comparison (xasl_generation / pt_decide_key_compare)
DecideStep == /\ phase = "decide"
              /\ dec' = Decide(client, ty[1], ty[2])
              /\ phase' = "install"
              /\ UNCHANGED <<client, site, ty, val, inst, leaf, bad, wrong, usedExact>>

\* the server installs the cmpval it will run
Install == /\ phase = "install"
           /\ inst' = CASE site = "decide" -> dec
                        [] site = "unpack" -> Unpack(dec)
                        [] site = "expr" -> Unpack(dec)
                        [] site = "mirror" -> Mirror(Unpack(dec))
           /\ leaf' = IF site = "expr" /\ ExprLeaf(Unpack(dec)) THEN TRUE ELSE FALSE
           /\ phase' = "eval"
           /\ UNCHANGED <<client, site, ty, val, dec, bad, wrong, usedExact>>

\* the consumer runs it; the mirror compares the bound's pair exchanged (index key first);
\* an expression term that is no exact leaf goes to the interpreter (tp_value_compare)
Eval == /\ phase = "eval"
        /\ LET interp == site = "expr" /\ leaf = FALSE
               x == IF site = "mirror" THEN val[2] ELSE val[1]
               y == IF site = "mirror" THEN val[1] ELSE val[2]
               given == IF leaf = TRUE THEN inst.src ELSE Actual(inst)
               unsafe == ~interp /\ Reads(inst.cmp) # given
           IN /\ bad' = IF unsafe THEN TRUE ELSE FALSE
              /\ \E r \in IF unsafe THEN {-1, 0, 1} ELSE {IF interp THEN Sign(x - y) ELSE Answer(inst.cmp, x, y)} :
                   wrong' = IF ~unsafe /\ r # Sign(x - y) THEN TRUE ELSE FALSE
              /\ usedExact' = IF ~interp /\ inst.cmp.kind = "exact" THEN TRUE ELSE FALSE
        /\ phase' = "done"
        /\ UNCHANGED <<client, site, ty, val, dec, inst, leaf>>

Done == phase = "done" /\ UNCHANGED vars

Next == DecideStep \/ Install \/ Eval \/ Done
Spec == Init /\ [][Next]_vars

\* ---- properties ----
TypeOK == /\ phase \in Phases /\ client \in Clients /\ site \in Sites
          /\ ty \in Types \X Types /\ val \in Vals \X Vals
          /\ dec \in Compares /\ inst \in Compares
          /\ leaf \in Bools /\ bad \in Bools /\ wrong \in Bools /\ usedExact \in Bools
\* C1: a cmpval only ever reads values of the types it was made for
TypeSafe == ~bad
\* C2: every comparison answers the values' order
ExactAnswer == ~wrong
\* C3: a new stream compares an integer against a NUMERIC by the exact cmpval, unconverted
NewExactPair == (phase = "done" /\ client = "new" /\ Exact(ty[1], ty[2]))
                  => (usedExact /\ inst.conv = <<0, 0>>)

\* witnesses
NotOldMirror == ~(phase = "done" /\ client = "old" /\ site = "mirror" /\ Exact(ty[1], ty[2]) /\ ~bad)
NotNewExactMirror == ~(phase = "done" /\ client = "new" /\ site = "mirror" /\ usedExact
                       /\ ty[1] = "NUMERIC" /\ val[1] # val[2])

\* ---- inductive invariant (TLAPS: CmpDispatch_proofs.tla) ----
Installed(c, s, a, b) == CASE s = "decide" -> Decide(c, a, b)
                           [] s = "unpack" -> Unpack(Decide(c, a, b))
                           [] s = "expr" -> Unpack(Decide(c, a, b))
                           [] s = "mirror" -> Mirror(Unpack(Decide(c, a, b)))
IndInv == /\ phase \in Phases /\ client \in Clients /\ site \in Sites
          /\ ty \in Types \X Types /\ val \in Vals \X Vals
          /\ site = "decide" => client = "new"
          /\ Holds(ty[1], val[1]) /\ Holds(ty[2], val[2])
          /\ dec = IF phase = "decide" THEN None ELSE Decide(client, ty[1], ty[2])
          /\ inst = IF phase \in {"eval", "done"} THEN Installed(client, site, ty[1], ty[2]) ELSE None
          /\ leaf = IF phase \in {"eval", "done"} /\ site = "expr" /\ ExprLeaf(Unpack(dec)) THEN TRUE ELSE FALSE
          /\ bad = FALSE /\ wrong = FALSE
          /\ usedExact = IF phase = "done" /\ ~(site = "expr" /\ leaf = FALSE) /\ inst.cmp.kind = "exact" THEN TRUE ELSE FALSE
          /\ TypeOK
=============================================================================
