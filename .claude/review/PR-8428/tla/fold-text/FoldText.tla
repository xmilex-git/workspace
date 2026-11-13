------------------------------ MODULE FoldText ------------------------------
(***************************************************************************)
(* PR 8428 (CBRD-27961) review model, head 3599b53b4.  One statement of a  *)
(* driver session from its parse to the bind-signature recompile:          *)
(* db_compile_statement_local saves the statement node's text, pt_compile  *)
(* may fold a set operation (pt_fold_union) and return another node,       *)
(* mq_translate may return another node, the text is restored, and         *)
(* db_recompile_for_bind_signature compiles the node's text again.  A text *)
(* is a record [t |-> whose text, l |-> whose length]: the parser gives    *)
(* the statement node its own length and every other node the length of    *)
(* the statement before it in the text (0 for the first statement).        *)
(* No concurrency: the client compiles one statement at a time.            *)
(***************************************************************************)
EXTENDS Naturals, TLC

\* Types for Apalache (tools/tla/apalache-types writes them into the declarations).
\* apalache-type: NStmt Int
\* apalache-type: Mutant Str
\* apalache-type: stage Str
\* apalache-type: k Int
\* apalache-type: n Int
\* apalache-type: top {t: Int, l: Int}
\* apalache-type: isUnion Bool
\* apalache-type: sub {t: Int, l: Int}
\* apalache-type: subBefore {t: Int, l: Int}
\* apalache-type: saved {t: Int, l: Int}
\* apalache-type: nfold Int
\* apalache-type: rec Str
\* apalache-type: topFolded Bool
\* apalache-type: lastSame Bool
\* apalache-type: seen Set(Str)
CONSTANTS NStmt, Mutant
ASSUME NStmt \in 1..3
ASSUME Mutant \in {"none", "merge-base", "no-fold-copy", "no-restore"}

\* text owners: statement k of the text, 0 = none (length 0), VId a view text parsed during translation
VId == 9
Owners == (0..NStmt) \cup {VId}
Txt == [t : Owners, l : Owners]
Own(k) == [t |-> k, l |-> k]
Inner(k) == [t |-> k, l |-> k - 1]            \* a non-statement node of statement k
NoTxt == [t |-> 0, l |-> 0]

FoldCopy == Mutant \notin {"merge-base", "no-fold-copy"}
RestoreOn == Mutant \notin {"merge-base", "no-restore"}

VARIABLES stage,    \* "idle" -> "parsed" -> "compiled" -> "translated" -> "restored" -> "done"
  k,        \* the statement compiled: k-th statement of the text
  n,        \* number of statements in the text (session dimension)
  top,      \* text of the current statement node
  isUnion,  \* the statement node is still a set operation
  sub,      \* text of a set operation inside a subquery (NoTxt when none), and of what replaces it
  subBefore,\* ghost: sub's text before any fold
  saved,    \* db_compile_statement_local's saved text
  nfold,    \* pt_fold_union calls so far (bounded)
  rec,      \* "none" | "ok" | "err452" | "wrong": outcome of the bind-signature recompile
  topFolded,\* pt_compile returned another statement node (a fold of the statement's set operation)
  lastSame, \* ghost: the node a fold returned already had the set operation's text
  seen      \* ghost: shapes reached (witnesses)

vars == <<stage, k, n, top, isUnion, sub, subBefore, saved, nfold, rec, topFolded, lastSame, seen>>

Init ==
  /\ stage = "idle" /\ k = 1 /\ n = 1 /\ top = NoTxt /\ isUnion = FALSE /\ sub = NoTxt /\ subBefore = NoTxt
  /\ saved = NoTxt /\ nfold = 0 /\ rec = "none" /\ topFolded = FALSE /\ lastSame = FALSE /\ seen = {}

(* the parser: statement kk of a text of nn statements; its node carries its own text, a subquery its inner text *)
Parse ==
  /\ stage = "idle"
  /\ \E nn \in 1..NStmt, kk \in 1..NStmt, u \in BOOLEAN, s \in BOOLEAN :
       /\ kk <= nn
       /\ n' = nn /\ k' = kk
       /\ top' = Own(kk) /\ isUnion' = u
       /\ sub' = (IF s THEN Inner(kk) ELSE NoTxt) /\ subBefore' = (IF s THEN Inner(kk) ELSE NoTxt)
  \* db_compile_statement_local: int stmt_start_line ...; char *sql_user_text = statement->sql_user_text
  /\ saved' = Own(k')
  /\ stage' = "parsed"
  /\ UNCHANGED <<nfold, rec, topFolded, lastSame, seen>>

(* pt_fold_union on the statement's set operation: the arm that remains (an inner node) replaces it, or a derived
   table made by parser_new_node around it, which takes g_query_string: the last statement parsed (the n-th) *)
FoldTop ==
  /\ stage = "parsed" /\ isUnion /\ nfold < 2
  /\ \E wrap \in BOOLEAN :
       LET made == IF wrap THEN Own(n) ELSE Inner(k)
       IN /\ top' = IF FoldCopy THEN top ELSE made
          /\ lastSame' = (made = top)
          /\ seen' = seen \cup {IF wrap THEN "wrap" ELSE "fold"}
  /\ isUnion' = FALSE /\ nfold' = nfold + 1 /\ topFolded' = TRUE
  /\ UNCHANGED <<stage, k, n, sub, subBefore, saved, rec>>

(* pt_fold_union on a set operation inside a subquery: the arm and the set operation carry the same inner text *)
FoldSub ==
  /\ stage = "parsed" /\ sub # NoTxt /\ nfold < 2
  /\ \E wrap \in BOOLEAN :
       LET made == IF wrap THEN Own(n) ELSE Inner(k)
       IN /\ sub' = IF FoldCopy THEN sub ELSE made
          /\ lastSame' = (made = sub)
  /\ nfold' = nfold + 1 /\ seen' = seen \cup {"sub"}
  /\ UNCHANGED <<stage, k, n, top, isUnion, subBefore, saved, rec, topFolded>>

(* pt_fold_union with STATEMENT_SET_FOLD_NOTHING: the node itself *)
FoldNothing ==
  /\ stage = "parsed" /\ isUnion /\ nfold < 2
  /\ nfold' = nfold + 1 /\ lastSame' = TRUE
  /\ UNCHANGED <<stage, k, n, top, isUnion, sub, subBefore, saved, rec, topFolded, seen>>

Compiled ==
  /\ stage = "parsed"
  /\ stage' = "compiled"
  /\ UNCHANGED <<k, n, top, isUnion, sub, subBefore, saved, nfold, rec, topFolded, lastSame, seen>>

(* mq_translate may come back with a new statement node made by parser_new_node: "fresh" takes g_query_string, the
   last statement parsed (the n-th); "view" is the PR body's case, a node made after a view's text was parsed during
   the translation (no run reached it, MAP.md) *)
Translate ==
  /\ stage = "compiled"
  /\ \E newTop \in {"none", "fresh", "view"} :
       /\ top' = CASE newTop = "none" -> top
                    [] newTop = "fresh" -> Own(n)
                    [] newTop = "view" -> [t |-> VId, l |-> VId]
       /\ seen' = seen \cup (CASE newTop = "none" -> {} [] newTop = "fresh" -> {"fresh"} [] newTop = "view" -> {"view"})
  /\ stage' = "translated"
  /\ UNCHANGED <<k, n, isUnion, sub, subBefore, saved, nfold, rec, topFolded, lastSame>>

(* the end of db_compile_statement_local: statement->sql_user_text = sql_user_text ... *)
Restore ==
  /\ stage = "translated"
  /\ top' = IF RestoreOn THEN saved ELSE top
  /\ seen' = IF top # saved THEN seen \cup {"restored"} ELSE seen
  /\ stage' = "restored"
  /\ UNCHANGED <<k, n, isUnion, sub, subBefore, saved, nfold, rec, topFolded, lastSame>>

\* @type: {t: Int, l: Int} => Int;
TextLen(x) == IF x.l = 0 THEN 0 ELSE 1
(* db_recompile_for_bind_signature: one statement compiles its node's text (ER_QPROC_INVALID_XASLNODE without
   a length), several the text they were prepared from (original_buffer) *)
Recompile ==
  /\ stage = "restored"
  /\ rec' = IF n > 1 THEN "ok"
            ELSE IF top.t = 0 \/ TextLen(top) = 0 THEN "err452"
            ELSE IF top = Own(k) THEN "ok" ELSE "wrong"
  /\ stage' = "done"
  /\ UNCHANGED <<k, n, top, isUnion, sub, subBefore, saved, nfold, topFolded, lastSame, seen>>

(* a compilation without bind values to recompile for (a prepare, csql, the recompiled session's own compilation) *)
NoRecompile ==
  /\ stage = "restored"
  /\ stage' = "done"
  /\ UNCHANGED <<k, n, top, isUnion, sub, subBefore, saved, nfold, rec, topFolded, lastSame, seen>>

(* the next statement *)
Reset ==
  /\ stage = "done"
  /\ stage' = "idle" /\ k' = 1 /\ n' = 1 /\ top' = NoTxt /\ isUnion' = FALSE /\ sub' = NoTxt /\ subBefore' = NoTxt
  /\ saved' = NoTxt /\ nfold' = 0 /\ rec' = "none" /\ topFolded' = FALSE /\ lastSame' = FALSE
  /\ UNCHANGED seen

Next == Parse \/ FoldTop \/ FoldSub \/ FoldNothing \/ Compiled \/ Translate \/ Restore \/ Recompile \/ NoRecompile \/ Reset
Spec == Init /\ [][Next]_vars /\ WF_vars(Next)
\* liveness on one statement: from a parse, the compilation ends
OneStmt == Init /\ [][Next /\ ~Reset]_vars /\ WF_vars(Next /\ ~Reset)

(***************************************************************************)
(* Properties                                                              *)
(***************************************************************************)
TypeOK ==
  /\ stage \in {"idle", "parsed", "compiled", "translated", "restored", "done"}
  /\ k \in 1..NStmt /\ n \in 1..NStmt
  /\ top \in Txt /\ sub \in Txt /\ subBefore \in Txt /\ saved \in Txt
  /\ isUnion \in BOOLEAN /\ nfold \in 0..2
  /\ rec \in {"none", "ok", "err452", "wrong"} /\ topFolded \in BOOLEAN /\ lastSame \in BOOLEAN
  /\ seen \in SUBSET {"fold", "wrap", "sub", "view", "fresh", "restored"}

\* C1: a driver session recompiles the statement it prepared (no -452, not another text)
RecompileOK == rec \in {"none", "ok"}
\* C3: once compiled, the statement node carries its own text (XASL cache user text, tranlist, error log)
OwnText == stage \in {"restored", "done"} => top = Own(k)
\* C2: a set operation inside a subquery folds to a node with the text it had
SubUnchanged == stage # "idle" => sub = subBefore

IndInv ==
  /\ TypeOK
  /\ RecompileOK
  /\ OwnText
  /\ SubUnchanged
  /\ (stage \in {"parsed", "compiled", "translated", "restored", "done"} => saved = Own(k))
  /\ (stage = "idle" => top = NoTxt /\ rec = "none")
  /\ (stage \in {"parsed", "compiled", "translated", "restored"} => rec = "none")

Terminates == <>(stage = "done")

\* Apalache: three statements per text (Owners needs a constant range)
CInit == NStmt = 3 /\ Mutant = "none"

\* witnesses
NotSeen(x) == x \notin seen
NoFold == NotSeen("fold")
NoWrap == NotSeen("wrap")
NoView == NotSeen("view")
NoFresh == NotSeen("fresh")
NoSubFold == NotSeen("sub")
NoRestored == NotSeen("restored")
=============================================================================
