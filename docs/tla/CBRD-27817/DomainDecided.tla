---------------------------- MODULE DomainDecided ----------------------------
(* CBRD-27817: the compiler (XASL generation) decides every slot's domain, collation and comparison; the server
   follows the decision and keeps no row-time fallback that reads the value's own type or collation.

   One behavior is one client session: XASL generation compiles slots into cached plans (Compile), the server
   unpacks a plan any number of times (Load, once per execution of a cached plan), and the executor runs the
   loaded slots (Exec). The expression-program decision of an arithmetic node is made on both sides (Decide):
   by XASL generation, which writes the program image, and by the server's debug build, which recompiles the
   program and asserts the image is the same.

   Slot classes (site):
     "list"   a subquery's list read by IN / ANY (pt_make_regu_subquery UNBOX_AS_TABLE, pt_to_outlist list regu)
     "single" a scalar subquery's value list (pt_make_regu_subquery, pt_to_outlist single tuple)
     "box"    a regu value list (TYPE_REGU_VAR_LIST), the container of CUME_DIST / PERCENT_RANK's operands
     "row"    every other regu, list position and comparison the executor reads
   Input class (cls): "left" when type checking left the slot's parse-tree domain to its values (a variable type
   or a LEAVE / ENFORCE collation: a bind in a subquery's select list, GROUP_CONCAT(?), MAX(?)), "fixed" else.
   Annotations (ann): the domain unpacked for the slot: "fixed" (a type and a NORMAL collation), "variable",
   "leave", "enforce", "none" (no domain: a NULL pointer). *)
EXTENDS Naturals, FiniteSets

CONSTANTS Mutant, NComp, NLoad

\* Types for Apalache (tools/tla/apalache-types writes them into the declarations).
\* apalache-type: Mutant Str
\* apalache-type: NComp Int
\* apalache-type: NLoad Int
\* apalache-type: compiled Set({ site: Str, cls: Str, ann: Str })
\* apalache-type: loaded Set({ site: Str, cls: Str, ann: Str })
\* apalache-type: decls Set({ side: Str, conv: Bool, decl: Bool })
\* apalache-type: nComp Int
\* apalache-type: nLoad Int
\* apalache-type: bad Bool
\* apalache-type: crash Bool
\* apalache-type: diff Bool
\* apalache-type: listBindRan Bool

Sites == {"list", "single", "box", "row"}
Classes == {"left", "fixed"}
Anns == {"fixed", "variable", "leave", "enforce", "none"}
Sides == {"cli", "srv"}
Slot == [site : Sites, cls : Classes, ann : Anns]
Decl == [side : Sides, conv : BOOLEAN, decl : BOOLEAN]

Mutants == {"none", "pre_list", "pre_single", "box_variable", "box_pack_always", "decline_server_field",
            "label_read", "row_left"}
ASSUME Mutant \in Mutants /\ NComp \in Nat /\ NLoad \in Nat

VARIABLES compiled, loaded, decls, nComp, nLoad, bad, crash, diff, listBindRan
vars == <<compiled, loaded, decls, nComp, nLoad, bad, crash, diff, listBindRan>>

(* Which (site, cls) pairs XASL generation meets: a container is always the CUME_DIST / PERCENT_RANK operand
   list, whose own parse-tree type is the function's; a plain regu has a fixed domain since CBRD-27583. *)
Meets(s, c) == CASE s = "box" -> c = "fixed"
                 [] s = "row" -> c = "fixed" \/ Mutant = "row_left"
                 [] OTHER     -> TRUE

(* The domain XASL generation unpacks for a slot (the change).
   list:   pt_make_regu_subquery reads a list left to its values as its first column
           (pt_reader_domain (regu->domain, domain_list_column_of (xasl, 0))) - develop kept the ENFORCE domain;
   single: the value list takes the regu's reader domain (value_list->dom = regu->domain) - develop kept
           pt_make_val_list's parse-tree domain (VARIABLE for MAX(?), LEAVE for GROUP_CONCAT(?));
   box:    regu->domain = NULL - develop: tp_domain_resolve_default (DB_TYPE_VARIABLE). *)
AnnDev(s, c) ==
  CASE s = "list"   -> IF c = "left" THEN "enforce" ELSE "fixed"
    [] s = "single" -> IF c = "left" THEN "variable" ELSE "fixed"
    [] s = "box"    -> "variable"
    [] OTHER        -> IF c = "left" THEN "variable" ELSE "fixed"
Ann(s, c) ==
  CASE s = "list"   -> IF Mutant = "pre_list" THEN AnnDev(s, c) ELSE "fixed"
    [] s = "single" -> IF Mutant = "pre_single" THEN AnnDev(s, c) ELSE "fixed"
    [] s = "box"    -> IF Mutant = "box_variable" THEN AnnDev(s, c) ELSE "none"
    [] OTHER        -> AnnDev(s, c)

Decided(a) == a = "fixed"

(* Does the executor read the slot's domain at the row? Only a plain slot: a list read by IN / ANY is read in
   the list's own column domain and compared by the decided comparison (eval_some_list_eval: type_list.domp[0],
   eval_value_rel_cmp (.., compare)); a scalar subquery's value is read in the list's column domain
   (qdata_get_single_tuple_from_list_id: type_list.domp[i]); a container's elements are read, never the
   container. The mutant label_read is an executor path that would read a list regu's own domain. *)
ReadAtRow(s) == s = "row"
ReadsLabel(s) == Mutant = "label_read" /\ s = "list"

(* xasl_to_stream: the type, then the domain unless the regu is a container (or_put_domain dereferences the
   domain it packs: a NULL one is a crash). *)
PacksDomain(s) == s # "box" \/ Mutant = "box_pack_always"

(* The expression program's decision for an arithmetic node whose result coerces into its domain: decline
   (keep the interpreted node) when no converter of the kernel type into the domain exists.
   XASL generation knows the kernel type (expr_arith_decided from the operand domains); the server's unpack
   also fills decided.arith and result_conv, which XASL generation never sees (UNRESOLVED / NULL there).
   The mutant reads result_conv: NULL on the client side. *)
Decline(side, conv) ==
  IF Mutant = "decline_server_field" /\ side = "cli" THEN TRUE ELSE ~conv

(* What a slot's answer depends on: the decided comparison and the list's column domains, the same in develop
   and in the change; a path that read the slot's own domain (label_read) would answer by the annotation, which
   the change made different from develop's. *)
AnswerKey(s, a) == IF ReadsLabel(s) THEN a ELSE "decided"

Init ==
  /\ compiled = {}
  /\ loaded = {}
  /\ decls = {}
  /\ nComp = 0
  /\ nLoad = 0
  /\ bad = FALSE
  /\ crash = FALSE
  /\ diff = FALSE
  /\ listBindRan = FALSE

\* XASL generation compiles a slot into a plan the cache keeps (xts_process_regu_variable packs it).
Compile(s, c) ==
  /\ nComp < NComp
  /\ Meets(s, c)
  /\ LET a == Ann(s, c) IN
       /\ compiled' = compiled \cup {[site |-> s, cls |-> c, ann |-> a]}
       /\ crash' = (crash \/ (PacksDomain(s) /\ a = "none"))
  /\ nComp' = nComp + 1
  /\ UNCHANGED <<loaded, decls, nLoad, bad, diff, listBindRan>>

\* The server unpacks a cached plan's slot (stx_build_regu_variable, stx_build_val_list).
Load(e) ==
  /\ nLoad < NLoad
  /\ e \in compiled
  /\ loaded' = loaded \cup {e}
  /\ nLoad' = nLoad + 1
  /\ UNCHANGED <<compiled, decls, nComp, bad, crash, diff, listBindRan>>

(* The executor runs a loaded slot. With the row-time fallbacks removed, a slot read at the row must be
   decided (bad: the read of a domain left to the value, an assert in optdebug). A list read by IN / ANY answers
   as develop did. *)
Exec(e) ==
  /\ e \in loaded
  /\ bad' = (bad \/ (ReadAtRow(e.site) /\ ~Decided(e.ann)))
  /\ diff' = (diff \/ AnswerKey(e.site, AnnDev(e.site, e.cls)) # AnswerKey(e.site, e.ann))
  /\ listBindRan' = (listBindRan \/ (e.site = "list" /\ e.cls = "left"))
  /\ UNCHANGED <<compiled, loaded, decls, nComp, nLoad, crash>>

\* A side decides an arithmetic node's program (expr_compile_node_impl at the coerce_result decline).
Decide(side, conv) ==
  /\ nComp < NComp
  /\ decls' = decls \cup {[side |-> side, conv |-> conv, decl |-> Decline(side, conv)]}
  /\ nComp' = nComp + 1
  /\ UNCHANGED <<compiled, loaded, nLoad, bad, crash, diff, listBindRan>>

\* The session ends once its compilations are spent (loads of cached plans may still be left).
Done == nComp = NComp /\ UNCHANGED vars

Next ==
  \/ \E s \in Sites, c \in Classes : Compile(s, c)
  \/ \E e \in compiled : Load(e)
  \/ \E e \in loaded : Exec(e)
  \/ \E side \in Sides, conv \in BOOLEAN : Decide(side, conv)
  \/ Done

Spec == Init /\ [][Next]_vars

---------------------------------------------------------------------------
TypeOK ==
  /\ compiled \in SUBSET Slot
  /\ loaded \in SUBSET compiled
  /\ decls \in SUBSET Decl
  /\ nComp \in 0..NComp
  /\ nLoad \in 0..NLoad
  /\ bad \in BOOLEAN /\ crash \in BOOLEAN /\ diff \in BOOLEAN /\ listBindRan \in BOOLEAN

\* C1: the executor never reads a domain left to the value.
NoUndecidedRead == ~bad
\* C2: every domain unpacked is decided; a container carries none.
LoadDecided == \A e \in loaded : IF e.site = "box" THEN e.ann = "none" ELSE Decided(e.ann)
\* C3: no NULL domain is packed into the stream.
NoNullPack == ~crash
\* C4: both sides take the same expression-program decision for the same node.
ImageSame == \A a, b \in decls : a.conv = b.conv => a.decl = b.decl
\* C5: every slot answers as in develop.
SameAnswer == ~diff

IndInv ==
  /\ TypeOK
  /\ \A e \in compiled : e.ann = Ann(e.site, e.cls) /\ Meets(e.site, e.cls)
  /\ \A d \in decls : d.decl = Decline(d.side, d.conv)
  /\ NoUndecidedRead /\ LoadDecided /\ NoNullPack /\ ImageSame /\ SameAnswer

\* Apalache's inductive check binds the constants here.
CInit ==
  /\ Mutant = "none"
  /\ NComp \in Nat
  /\ NLoad \in Nat

---------------------------------------------------------------------------
\* Witnesses: outcomes that must be reachable.
NotListBindRan == ~listBindRan
NotDeclinedBothSides == ~(\E a, b \in decls : a.side = "cli" /\ b.side = "srv" /\ a.decl /\ b.decl)
NotContainerLoaded == ~(\E e \in loaded : e.site = "box")
=============================================================================
