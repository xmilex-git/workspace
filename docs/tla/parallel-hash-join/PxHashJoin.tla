----------------------------- MODULE PxHashJoin -----------------------------
(* Parallel hash join of CUBRID develop e98bdd885 (src/query/parallel/px_hash_join/):
   one parallel phase of a leader and its worker tasks.
     Phase "split": build_partitions + split_task (tuples into partition lists),
     Phase "join":  execute_partitions + join_task (one partition context per claim),
     Phase "probe": probe_execute + probe_task (probe pages against the shared hash table).
   Units are the claimed work items: list pages (split, probe) or partition contexts
   (join). Pages 1..NM are the membuf region a single CAS winner walks; the rest are
   handed out by the sector fetch_add (or, in join, the scan_mutex counter).
   Mutant selects a known-wrong variant so the properties are shown to catch it. *)
EXTENDS Integers, FiniteSets

CONSTANTS Workers, Leader, User, NU, NM, NP, Phase, NullFill, Mutant
ASSUME Assm ==
  /\ Workers # {} /\ "none" \notin Workers /\ Leader \notin Workers /\ User \notin Workers /\ Leader # User
  /\ NU \in Nat /\ NU >= 1 /\ NM \in 0..NU /\ NP \in Nat /\ NP >= 3
  /\ Phase \in {"split", "join", "probe"} /\ NullFill \in BOOLEAN
  /\ Mutant \in {"none", "unlocked_dispenser", "membuf_no_cas", "unlocked_flush",
                 "preserved_build", "end_before_error", "early_join", "worker_frees_table",
                 "no_clear_interrupt", "lost_end_on_error", "check_no_rearm"}

Units == 1..NU
Parts == 0..(NP - 1)
KeyVals == {"k1", "k2", "null"}
ErrVals == {"none", "err", "intr"}
\* qdata_hash_scan_key: k1 and k2 hash apart.
H(k) == IF k = "k1" THEN 0 ELSE 1
\* split_task: NULL keys go to the last partition in a NULL-fill join, are dropped otherwise (NP = dropped).
PartOf(k) == IF k = "null" THEN (IF NullFill THEN NP - 1 ELSE NP)
             ELSE IF NullFill THEN H(k) % (NP - 1) ELSE H(k) % NP

(* --algorithm PxHashJoin
variables
  key \in IF Phase = "join" THEN {[v \in Units |-> "k1"]} ELSE [Units -> KeyVals],
  pushed = {},                 \* tasks handed to the worker pool
  active = {},                 \* task_manager::m_active_tasks, as the set of tasks not yet ended
  next = NM + 1,               \* sector_scan.next_sector_index / shared_info->next_index
  membufClaimed = FALSE,       \* sector_scan.membuf_claimed
  owner = "none",              \* ghost: the CAS winner
  cnt = [v \in Units |-> 0],   \* ghost: times unit v was handed out
  temp = [w \in Workers |-> [q \in Parts |-> {}]],  \* split: worker-local temp_part_list_id
  parts = [q \in Parts |-> {}],                     \* split: shared part_list_id
  out = [w \in Workers |-> {}],                     \* join/probe: per-context result list
  merged = {},                 \* leader: hjoin_merge_qlist of every context
  hasError = FALSE,            \* task_manager::m_has_error
  mainErr = "none",            \* leader's error context
  failed = [w \in Workers |-> "none"],  \* ghost: the error the worker raised
  intr = FALSE,                \* tdes->interrupt of the transaction
  cancelled = FALSE,           \* ghost: the user cancelled
  freed = FALSE,               \* leader-stack state destroyed (task_manager, shared_info, sector scan)
  tableFreed = FALSE,          \* the build hash table of single_context freed
  uaf = FALSE,                 \* ghost: a worker touched freed state
  res = "none",                \* the phase's return to its caller
  final = "none",              \* what the query gets
  fellBack = FALSE;            \* split failed and hjoin_try_partition retried single-threaded

define
  OutVals == ((0..NU) \X {"b1", "-", "ctx"})
  \* rows <<probe unit, build tuple>>: the build side holds one tuple b1 with key k1; NULL-fill emits
  \* <<v, "-">> for an unmatched probe row, <<0, "b1">> an unmatched build row; a join context v is <<v, "ctx">>
  ProbeOut(v) == IF key[v] = "k1" THEN {<<v, "b1">>}
                 ELSE IF NullFill /\ Mutant # "preserved_build" THEN {<<v, "-">>} ELSE {}
  ExpParts == [q \in Parts |-> {v \in Units : PartOf(key[v]) = q}]
  ExpOut == IF Phase = "join" THEN Units \X {"ctx"}
            ELSE UNION {ProbeOut(v) : v \in Units}
                 \cup (IF Mutant = "preserved_build" /\ \A v \in Units : key[v] # "k1"
                       THEN {<<0, "b1">>} ELSE {})
  TypeOK ==
    /\ key \in [Units -> KeyVals] /\ pushed \subseteq Workers /\ active \subseteq Workers
    /\ next \in Nat /\ membufClaimed \in BOOLEAN /\ owner \in Workers \cup {"none"}
    /\ cnt \in [Units -> Nat]
    /\ temp \in [Workers -> [Parts -> SUBSET Units]] /\ parts \in [Parts -> SUBSET Units]
    /\ out \in [Workers -> SUBSET OutVals] /\ merged \subseteq OutVals
    /\ hasError \in BOOLEAN /\ mainErr \in ErrVals /\ failed \in [Workers -> ErrVals]
    /\ intr \in BOOLEAN /\ cancelled \in BOOLEAN
    /\ freed \in BOOLEAN /\ tableFreed \in BOOLEAN /\ uaf \in BOOLEAN
    /\ res \in ErrVals \cup {"ok"} /\ final \in ErrVals \cup {"ok"} /\ fellBack \in BOOLEAN
  \* C1: no unit is handed out twice.
  ExactlyOnce == \A v \in Units : cnt[v] <= 1
  \* C2, C3: a parallel phase that succeeds produces the serial answer.
  Complete == pc[Leader] = "Done" /\ final = "ok" /\ ~fellBack =>
                IF Phase = "split" THEN parts = ExpParts ELSE merged = ExpOut
  \* C4: the phase returns an error iff a worker raised one, and returns one that was raised.
  NoLostError == pc[Leader] \in {"L_free", "L_fallback", "Done"} =>
                   /\ (res # "ok" <=> \E w \in Workers : failed[w] # "none")
                   /\ (res # "ok" => \E w \in Workers : failed[w] = res)
  \* C5: no worker touches leader-stack state or the shared hash table after it is freed.
  NoUseAfterFree == ~uaf
  \* C6: the interrupt a worker raises to stop its peers does not outlive the query.
  NoLeakedInterrupt == pc[Leader] = "Done" /\ ~cancelled => ~intr
  \* C8: a user cancel is never consumed while the query still succeeds.
  CancelHonored == pc[Leader] = "Done" /\ cancelled => (final # "ok" \/ intr)
  \* C7
  LeaderFinishes == <>(pc[Leader] = "Done")
  \* Witness predicates (each must be reachable; its witness cfg expects a violation).
  NotWorkerErrorReported == ~(pc[Leader] = "Done" /\ final = "err")
  NotFallbackSucceeds == ~(pc[Leader] = "Done" /\ fellBack /\ final = "ok")
  NotCancelReported == ~(pc[Leader] = "Done" /\ cancelled /\ final = "intr")
  NotBothDispensers == ~(pc[Leader] = "Done" /\ final = "ok" /\ owner # "none"
                         /\ \E w \in Workers : w # owner /\ out[w] # {})
end define;

fair process worker \in Workers
variables mb = 0, u = 1, won = FALSE, tmp = 0, p = 0, ret = "check", ok = FALSE,
          matched = FALSE, ended = FALSE;
begin
W_start:
  await self \in pushed;
W_check:      \* has_error () || check_interrupt () at the top of the page / context loop
  uaf := uaf \/ freed;
  if hasError then
    goto W_cleanup;
  elsif intr then
    intr := FALSE || failed[self] := "intr";
    if Mutant = "check_no_rearm" then goto W_cleanup; else goto W_err; end if;
  end if;
W_claim:      \* sector_page_iterator::get_next_page / join_task::get_next_context
  if mb = 0 then
    if NM = 0 then
      mb := -1;
      goto W_claim;
    elsif Mutant = "membuf_no_cas" then
      tmp := IF membufClaimed THEN 1 ELSE 0 || uaf := uaf \/ freed;
      goto W_cas_write;
    elsif membufClaimed then
      mb := -1 || uaf := uaf \/ freed;
      goto W_claim;
    else
      membufClaimed := TRUE || owner := self || mb := 1 || uaf := uaf \/ freed;
      goto W_claim;
    end if;
  elsif mb >= 1 /\ mb <= NM then
    cnt[mb] := cnt[mb] + 1 || u := mb || mb := mb + 1 || uaf := uaf \/ freed;
    goto W_proc;
  elsif Mutant = "unlocked_dispenser" then
    tmp := next || uaf := uaf \/ freed;
    goto W_fa_write;
  elsif next <= NU then
    cnt[next] := cnt[next] + 1 || u := next || next := next + 1 || uaf := uaf \/ freed;
    goto W_proc;
  else
    ok := TRUE || uaf := uaf \/ freed;
    goto W_cleanup;
  end if;
W_cas_write:  \* mutant membuf_no_cas: the claim's write after a separate read
  if tmp = 0 then
    membufClaimed := TRUE || owner := self || mb := 1 || uaf := uaf \/ freed;
  else
    mb := -1 || uaf := uaf \/ freed;
  end if;
  tmp := 0;
  goto W_claim;
W_fa_write:   \* mutant unlocked_dispenser: the increment's write after a separate read
  if tmp <= NU then
    cnt[tmp] := cnt[tmp] + 1 || u := tmp || next := tmp + 1 || uaf := uaf \/ freed;
    tmp := 0;
    goto W_proc;
  else
    ok := TRUE || tmp := 0;
    goto W_cleanup;
  end if;
W_proc:       \* the unit's work: split one page / hjoin_execute one context / probe one page
  either
    failed[self] := "err" || uaf := uaf \/ freed;
    goto W_err;
  or
    uaf := uaf \/ freed \/ (Phase = "probe" /\ tableFreed);
    if Phase = "split" then
      if PartOf(key[u]) < NP then
        temp[self][PartOf(key[u])] := temp[self][PartOf(key[u])] \cup {u};
        either
          goto W_check;
        or
          p := PartOf(key[u]) || ret := "check";
          goto W_fl;
        end either;
      else
        goto W_check;
      end if;
    elsif Phase = "probe" then
      out[self] := out[self] \cup ProbeOut(u)
        || matched := matched \/ (Mutant = "preserved_build" /\ key[u] = "k1");
      goto W_check;
    else
      out[self] := out[self] \cup {<<u, "ctx">>};
      goto W_check;
    end if;
  end either;
W_fl:         \* split: flush temp list p into the shared part list under part_mutexes[p]
  if Mutant = "unlocked_flush" then
    tmp := IF parts[p] # {} THEN 1 ELSE 0 || uaf := uaf \/ freed;
    goto W_fl_write;
  else
    either
      failed[self] := "err" || uaf := uaf \/ freed;
      goto W_err;
    or
      parts[p] := IF parts[p] # {} THEN parts[p] \cup temp[self][p] ELSE temp[self][p]
        || uaf := uaf \/ freed;
      temp[self][p] := {};
      if ret = "merge" then p := p + 1; goto W_merge; else goto W_check; end if;
    end either;
  end if;
W_fl_write:   \* mutant unlocked_flush: append-or-adopt decided on a stale tuple count
  parts[p] := IF tmp = 1 THEN parts[p] \cup temp[self][p] ELSE temp[self][p]
    || uaf := uaf \/ freed;
  temp[self][p] := {};
  tmp := 0;
  if ret = "merge" then p := p + 1; goto W_merge; else goto W_check; end if;
W_err:        \* task_manager::handle_error: m_has_error.exchange (true)
  if Mutant = "end_before_error" /\ ~ended then
    active := active \ {self} || ended := TRUE || uaf := uaf \/ freed;
    goto W_err;
  else
    won := ~hasError || hasError := TRUE || uaf := uaf \/ freed;
  end if;
W_swap:       \* the winner swaps its error into the leader's error context, then notify_stop
  if won then mainErr := failed[self]; end if;
  uaf := uaf \/ freed;
W_rearm:      \* logtb_set_tran_index_interrupt (.., true): stop the peers
  intr := TRUE;
W_cleanup:
  if Phase = "split" /\ ok /\ failed[self] = "none" then
    p := 0;
    goto W_merge;
  else
    goto W_pclean;
  end if;
W_merge:      \* split: the final per-partition merge after the input is exhausted
  if p < NP then
    if temp[self][p] = {} then
      p := p + 1;
      goto W_merge;
    else
      ret := "merge";
      goto W_fl;
    end if;
  end if;
W_pclean:     \* own cleanup: temps destroyed / hash_scan cleared with the shared table detached
  if Phase = "split" then
    temp[self] := [q \in Parts |-> {}];
  elsif Phase = "probe" then
    tableFreed := tableFreed \/ Mutant = "worker_frees_table"
      || out[self] := out[self] \cup (IF Mutant = "preserved_build" /\ ok /\ ~matched
                                      THEN {<<0, "b1">>} ELSE {});
  end if;
W_end:        \* base_task::retire -> task_manager::end_task
  if ~ended /\ ~(Mutant = "lost_end_on_error" /\ failed[self] # "none") then
    active := active \ {self};
  end if;
  uaf := uaf \/ freed;
end process;

fair process leader = Leader
begin
L_push:       \* task_manager::push_task for every worker
  with w \in Workers \ pushed do
    pushed := pushed \cup {w} || active := active \cup {w};
  end with;
  if pushed # Workers then goto L_push; end if;
L_join:       \* task_manager::join: wait (lock, [] { m_active_tasks == 0 })
  if Mutant = "early_join" then
    await active = {} \/ hasError;
  else
    await active = {};
  end if;
L_after:      \* has_error () ? clear_interrupt + error : merge every context
  if hasError then
    if Mutant # "no_clear_interrupt" then intr := FALSE; end if;
    res := mainErr;
  else
    res := "ok" || merged := UNION {out[w] : w \in Workers};
  end if;
L_free:       \* return: task_manager, shared info, sector scan go; later hjoin_clear_manager frees the table
  freed := TRUE || tableFreed := TRUE;
L_fallback:   \* hjoin_try_partition: a split error other than ER_INTERRUPTED retries single-threaded
  if Phase = "split" /\ res \notin {"ok", "intr"} then
    fellBack := TRUE;
    if intr then intr := FALSE || final := "intr"; else final := "ok"; end if;
  else
    final := res;
  end if;
end process;

process user = User
begin
U_cancel:     \* xlogtb_set_interrupt from the client, any time before the query ends
  either
    skip;
  or
    await pc[Leader] # "Done";
    intr := TRUE || cancelled := TRUE;
  end either;
end process;
end algorithm; *)
\* BEGIN TRANSLATION
VARIABLES key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, 
          out, merged, hasError, mainErr, failed, intr, cancelled, freed, 
          tableFreed, uaf, res, final, fellBack, pc

(* define statement *)
OutVals == ((0..NU) \X {"b1", "-", "ctx"})


ProbeOut(v) == IF key[v] = "k1" THEN {<<v, "b1">>}
               ELSE IF NullFill /\ Mutant # "preserved_build" THEN {<<v, "-">>} ELSE {}
ExpParts == [q \in Parts |-> {v \in Units : PartOf(key[v]) = q}]
ExpOut == IF Phase = "join" THEN Units \X {"ctx"}
          ELSE UNION {ProbeOut(v) : v \in Units}
               \cup (IF Mutant = "preserved_build" /\ \A v \in Units : key[v] # "k1"
                     THEN {<<0, "b1">>} ELSE {})
TypeOK ==
  /\ key \in [Units -> KeyVals] /\ pushed \subseteq Workers /\ active \subseteq Workers
  /\ next \in Nat /\ membufClaimed \in BOOLEAN /\ owner \in Workers \cup {"none"}
  /\ cnt \in [Units -> Nat]
  /\ temp \in [Workers -> [Parts -> SUBSET Units]] /\ parts \in [Parts -> SUBSET Units]
  /\ out \in [Workers -> SUBSET OutVals] /\ merged \subseteq OutVals
  /\ hasError \in BOOLEAN /\ mainErr \in ErrVals /\ failed \in [Workers -> ErrVals]
  /\ intr \in BOOLEAN /\ cancelled \in BOOLEAN
  /\ freed \in BOOLEAN /\ tableFreed \in BOOLEAN /\ uaf \in BOOLEAN
  /\ res \in ErrVals \cup {"ok"} /\ final \in ErrVals \cup {"ok"} /\ fellBack \in BOOLEAN

ExactlyOnce == \A v \in Units : cnt[v] <= 1

Complete == pc[Leader] = "Done" /\ final = "ok" /\ ~fellBack =>
              IF Phase = "split" THEN parts = ExpParts ELSE merged = ExpOut

NoLostError == pc[Leader] \in {"L_free", "L_fallback", "Done"} =>
                 /\ (res # "ok" <=> \E w \in Workers : failed[w] # "none")
                 /\ (res # "ok" => \E w \in Workers : failed[w] = res)

NoUseAfterFree == ~uaf

NoLeakedInterrupt == pc[Leader] = "Done" /\ ~cancelled => ~intr

CancelHonored == pc[Leader] = "Done" /\ cancelled => (final # "ok" \/ intr)

LeaderFinishes == <>(pc[Leader] = "Done")

NotWorkerErrorReported == ~(pc[Leader] = "Done" /\ final = "err")
NotFallbackSucceeds == ~(pc[Leader] = "Done" /\ fellBack /\ final = "ok")
NotCancelReported == ~(pc[Leader] = "Done" /\ cancelled /\ final = "intr")
NotBothDispensers == ~(pc[Leader] = "Done" /\ final = "ok" /\ owner # "none"
                       /\ \E w \in Workers : w # owner /\ out[w] # {})

VARIABLES mb, u, won, tmp, p, ret, ok, matched, ended

vars == << key, pushed, active, next, membufClaimed, owner, cnt, temp, parts, 
           out, merged, hasError, mainErr, failed, intr, cancelled, freed, 
           tableFreed, uaf, res, final, fellBack, pc, mb, u, won, tmp, p, ret, 
           ok, matched, ended >>

ProcSet == (Workers) \cup {Leader} \cup {User}

Init == (* Global variables *)
        /\ key \in (IF Phase = "join" THEN {[v \in Units |-> "k1"]} ELSE [Units -> KeyVals])
        /\ pushed = {}
        /\ active = {}
        /\ next = NM + 1
        /\ membufClaimed = FALSE
        /\ owner = "none"
        /\ cnt = [v \in Units |-> 0]
        /\ temp = [w \in Workers |-> [q \in Parts |-> {}]]
        /\ parts = [q \in Parts |-> {}]
        /\ out = [w \in Workers |-> {}]
        /\ merged = {}
        /\ hasError = FALSE
        /\ mainErr = "none"
        /\ failed = [w \in Workers |-> "none"]
        /\ intr = FALSE
        /\ cancelled = FALSE
        /\ freed = FALSE
        /\ tableFreed = FALSE
        /\ uaf = FALSE
        /\ res = "none"
        /\ final = "none"
        /\ fellBack = FALSE
        (* Process worker *)
        /\ mb = [self \in Workers |-> 0]
        /\ u = [self \in Workers |-> 1]
        /\ won = [self \in Workers |-> FALSE]
        /\ tmp = [self \in Workers |-> 0]
        /\ p = [self \in Workers |-> 0]
        /\ ret = [self \in Workers |-> "check"]
        /\ ok = [self \in Workers |-> FALSE]
        /\ matched = [self \in Workers |-> FALSE]
        /\ ended = [self \in Workers |-> FALSE]
        /\ pc = [self \in ProcSet |-> CASE self \in Workers -> "W_start"
                                        [] self = Leader -> "L_push"
                                        [] self = User -> "U_cancel"]

W_start(self) == /\ pc[self] = "W_start"
                 /\ self \in pushed
                 /\ pc' = [pc EXCEPT ![self] = "W_check"]
                 /\ UNCHANGED << key, pushed, active, next, membufClaimed, 
                                 owner, cnt, temp, parts, out, merged, 
                                 hasError, mainErr, failed, intr, cancelled, 
                                 freed, tableFreed, uaf, res, final, fellBack, 
                                 mb, u, won, tmp, p, ret, ok, matched, ended >>

W_check(self) == /\ pc[self] = "W_check"
                 /\ uaf' = (uaf \/ freed)
                 /\ IF hasError
                       THEN /\ pc' = [pc EXCEPT ![self] = "W_cleanup"]
                            /\ UNCHANGED << failed, intr >>
                       ELSE /\ IF intr
                                  THEN /\ /\ failed' = [failed EXCEPT ![self] = "intr"]
                                          /\ intr' = FALSE
                                       /\ IF Mutant = "check_no_rearm"
                                             THEN /\ pc' = [pc EXCEPT ![self] = "W_cleanup"]
                                             ELSE /\ pc' = [pc EXCEPT ![self] = "W_err"]
                                  ELSE /\ pc' = [pc EXCEPT ![self] = "W_claim"]
                                       /\ UNCHANGED << failed, intr >>
                 /\ UNCHANGED << key, pushed, active, next, membufClaimed, 
                                 owner, cnt, temp, parts, out, merged, 
                                 hasError, mainErr, cancelled, freed, 
                                 tableFreed, res, final, fellBack, mb, u, won, 
                                 tmp, p, ret, ok, matched, ended >>

W_claim(self) == /\ pc[self] = "W_claim"
                 /\ IF mb[self] = 0
                       THEN /\ IF NM = 0
                                  THEN /\ mb' = [mb EXCEPT ![self] = -1]
                                       /\ pc' = [pc EXCEPT ![self] = "W_claim"]
                                       /\ UNCHANGED << membufClaimed, owner, 
                                                       uaf, tmp >>
                                  ELSE /\ IF Mutant = "membuf_no_cas"
                                             THEN /\ /\ tmp' = [tmp EXCEPT ![self] = IF membufClaimed THEN 1 ELSE 0]
                                                     /\ uaf' = (uaf \/ freed)
                                                  /\ pc' = [pc EXCEPT ![self] = "W_cas_write"]
                                                  /\ UNCHANGED << membufClaimed, 
                                                                  owner, mb >>
                                             ELSE /\ IF membufClaimed
                                                        THEN /\ /\ mb' = [mb EXCEPT ![self] = -1]
                                                                /\ uaf' = (uaf \/ freed)
                                                             /\ pc' = [pc EXCEPT ![self] = "W_claim"]
                                                             /\ UNCHANGED << membufClaimed, 
                                                                             owner >>
                                                        ELSE /\ /\ mb' = [mb EXCEPT ![self] = 1]
                                                                /\ membufClaimed' = TRUE
                                                                /\ owner' = self
                                                                /\ uaf' = (uaf \/ freed)
                                                             /\ pc' = [pc EXCEPT ![self] = "W_claim"]
                                                  /\ tmp' = tmp
                            /\ UNCHANGED << next, cnt, u, ok >>
                       ELSE /\ IF mb[self] >= 1 /\ mb[self] <= NM
                                  THEN /\ /\ cnt' = [cnt EXCEPT ![mb[self]] = cnt[mb[self]] + 1]
                                          /\ mb' = [mb EXCEPT ![self] = mb[self] + 1]
                                          /\ u' = [u EXCEPT ![self] = mb[self]]
                                          /\ uaf' = (uaf \/ freed)
                                       /\ pc' = [pc EXCEPT ![self] = "W_proc"]
                                       /\ UNCHANGED << next, tmp, ok >>
                                  ELSE /\ IF Mutant = "unlocked_dispenser"
                                             THEN /\ /\ tmp' = [tmp EXCEPT ![self] = next]
                                                     /\ uaf' = (uaf \/ freed)
                                                  /\ pc' = [pc EXCEPT ![self] = "W_fa_write"]
                                                  /\ UNCHANGED << next, cnt, u, 
                                                                  ok >>
                                             ELSE /\ IF next <= NU
                                                        THEN /\ /\ cnt' = [cnt EXCEPT ![next] = cnt[next] + 1]
                                                                /\ next' = next + 1
                                                                /\ u' = [u EXCEPT ![self] = next]
                                                                /\ uaf' = (uaf \/ freed)
                                                             /\ pc' = [pc EXCEPT ![self] = "W_proc"]
                                                             /\ ok' = ok
                                                        ELSE /\ /\ ok' = [ok EXCEPT ![self] = TRUE]
                                                                /\ uaf' = (uaf \/ freed)
                                                             /\ pc' = [pc EXCEPT ![self] = "W_cleanup"]
                                                             /\ UNCHANGED << next, 
                                                                             cnt, 
                                                                             u >>
                                                  /\ tmp' = tmp
                                       /\ mb' = mb
                            /\ UNCHANGED << membufClaimed, owner >>
                 /\ UNCHANGED << key, pushed, active, temp, parts, out, merged, 
                                 hasError, mainErr, failed, intr, cancelled, 
                                 freed, tableFreed, res, final, fellBack, won, 
                                 p, ret, matched, ended >>

W_cas_write(self) == /\ pc[self] = "W_cas_write"
                     /\ IF tmp[self] = 0
                           THEN /\ /\ mb' = [mb EXCEPT ![self] = 1]
                                   /\ membufClaimed' = TRUE
                                   /\ owner' = self
                                   /\ uaf' = (uaf \/ freed)
                           ELSE /\ /\ mb' = [mb EXCEPT ![self] = -1]
                                   /\ uaf' = (uaf \/ freed)
                                /\ UNCHANGED << membufClaimed, owner >>
                     /\ tmp' = [tmp EXCEPT ![self] = 0]
                     /\ pc' = [pc EXCEPT ![self] = "W_claim"]
                     /\ UNCHANGED << key, pushed, active, next, cnt, temp, 
                                     parts, out, merged, hasError, mainErr, 
                                     failed, intr, cancelled, freed, 
                                     tableFreed, res, final, fellBack, u, won, 
                                     p, ret, ok, matched, ended >>

W_fa_write(self) == /\ pc[self] = "W_fa_write"
                    /\ IF tmp[self] <= NU
                          THEN /\ /\ cnt' = [cnt EXCEPT ![tmp[self]] = cnt[tmp[self]] + 1]
                                  /\ next' = tmp[self] + 1
                                  /\ u' = [u EXCEPT ![self] = tmp[self]]
                                  /\ uaf' = (uaf \/ freed)
                               /\ tmp' = [tmp EXCEPT ![self] = 0]
                               /\ pc' = [pc EXCEPT ![self] = "W_proc"]
                               /\ ok' = ok
                          ELSE /\ /\ ok' = [ok EXCEPT ![self] = TRUE]
                                  /\ tmp' = [tmp EXCEPT ![self] = 0]
                               /\ pc' = [pc EXCEPT ![self] = "W_cleanup"]
                               /\ UNCHANGED << next, cnt, uaf, u >>
                    /\ UNCHANGED << key, pushed, active, membufClaimed, owner, 
                                    temp, parts, out, merged, hasError, 
                                    mainErr, failed, intr, cancelled, freed, 
                                    tableFreed, res, final, fellBack, mb, won, 
                                    p, ret, matched, ended >>

W_proc(self) == /\ pc[self] = "W_proc"
                /\ \/ /\ /\ failed' = [failed EXCEPT ![self] = "err"]
                         /\ uaf' = (uaf \/ freed)
                      /\ pc' = [pc EXCEPT ![self] = "W_err"]
                      /\ UNCHANGED <<temp, out, p, ret, matched>>
                   \/ /\ uaf' = (uaf \/ freed \/ (Phase = "probe" /\ tableFreed))
                      /\ IF Phase = "split"
                            THEN /\ IF PartOf(key[u[self]]) < NP
                                       THEN /\ temp' = [temp EXCEPT ![self][PartOf(key[u[self]])] = temp[self][PartOf(key[u[self]])] \cup {u[self]}]
                                            /\ \/ /\ pc' = [pc EXCEPT ![self] = "W_check"]
                                                  /\ UNCHANGED <<p, ret>>
                                               \/ /\ /\ p' = [p EXCEPT ![self] = PartOf(key[u[self]])]
                                                     /\ ret' = [ret EXCEPT ![self] = "check"]
                                                  /\ pc' = [pc EXCEPT ![self] = "W_fl"]
                                       ELSE /\ pc' = [pc EXCEPT ![self] = "W_check"]
                                            /\ UNCHANGED << temp, p, ret >>
                                 /\ UNCHANGED << out, matched >>
                            ELSE /\ IF Phase = "probe"
                                       THEN /\ /\ matched' = [matched EXCEPT ![self] = matched[self] \/ (Mutant = "preserved_build" /\ key[u[self]] = "k1")]
                                               /\ out' = [out EXCEPT ![self] = out[self] \cup ProbeOut(u[self])]
                                            /\ pc' = [pc EXCEPT ![self] = "W_check"]
                                       ELSE /\ out' = [out EXCEPT ![self] = out[self] \cup {<<u[self], "ctx">>}]
                                            /\ pc' = [pc EXCEPT ![self] = "W_check"]
                                            /\ UNCHANGED matched
                                 /\ UNCHANGED << temp, p, ret >>
                      /\ UNCHANGED failed
                /\ UNCHANGED << key, pushed, active, next, membufClaimed, 
                                owner, cnt, parts, merged, hasError, mainErr, 
                                intr, cancelled, freed, tableFreed, res, final, 
                                fellBack, mb, u, won, tmp, ok, ended >>

W_fl(self) == /\ pc[self] = "W_fl"
              /\ IF Mutant = "unlocked_flush"
                    THEN /\ /\ tmp' = [tmp EXCEPT ![self] = IF parts[p[self]] # {} THEN 1 ELSE 0]
                            /\ uaf' = (uaf \/ freed)
                         /\ pc' = [pc EXCEPT ![self] = "W_fl_write"]
                         /\ UNCHANGED << temp, parts, failed, p >>
                    ELSE /\ \/ /\ /\ failed' = [failed EXCEPT ![self] = "err"]
                                  /\ uaf' = (uaf \/ freed)
                               /\ pc' = [pc EXCEPT ![self] = "W_err"]
                               /\ UNCHANGED <<temp, parts, p>>
                            \/ /\ /\ parts' = [parts EXCEPT ![p[self]] = IF parts[p[self]] # {} THEN parts[p[self]] \cup temp[self][p[self]] ELSE temp[self][p[self]]]
                                  /\ uaf' = (uaf \/ freed)
                               /\ temp' = [temp EXCEPT ![self][p[self]] = {}]
                               /\ IF ret[self] = "merge"
                                     THEN /\ p' = [p EXCEPT ![self] = p[self] + 1]
                                          /\ pc' = [pc EXCEPT ![self] = "W_merge"]
                                     ELSE /\ pc' = [pc EXCEPT ![self] = "W_check"]
                                          /\ p' = p
                               /\ UNCHANGED failed
                         /\ tmp' = tmp
              /\ UNCHANGED << key, pushed, active, next, membufClaimed, owner, 
                              cnt, out, merged, hasError, mainErr, intr, 
                              cancelled, freed, tableFreed, res, final, 
                              fellBack, mb, u, won, ret, ok, matched, ended >>

W_fl_write(self) == /\ pc[self] = "W_fl_write"
                    /\ /\ parts' = [parts EXCEPT ![p[self]] = IF tmp[self] = 1 THEN parts[p[self]] \cup temp[self][p[self]] ELSE temp[self][p[self]]]
                       /\ uaf' = (uaf \/ freed)
                    /\ temp' = [temp EXCEPT ![self][p[self]] = {}]
                    /\ tmp' = [tmp EXCEPT ![self] = 0]
                    /\ IF ret[self] = "merge"
                          THEN /\ p' = [p EXCEPT ![self] = p[self] + 1]
                               /\ pc' = [pc EXCEPT ![self] = "W_merge"]
                          ELSE /\ pc' = [pc EXCEPT ![self] = "W_check"]
                               /\ p' = p
                    /\ UNCHANGED << key, pushed, active, next, membufClaimed, 
                                    owner, cnt, out, merged, hasError, mainErr, 
                                    failed, intr, cancelled, freed, tableFreed, 
                                    res, final, fellBack, mb, u, won, ret, ok, 
                                    matched, ended >>

W_err(self) == /\ pc[self] = "W_err"
               /\ IF Mutant = "end_before_error" /\ ~ended[self]
                     THEN /\ /\ active' = active \ {self}
                             /\ ended' = [ended EXCEPT ![self] = TRUE]
                             /\ uaf' = (uaf \/ freed)
                          /\ pc' = [pc EXCEPT ![self] = "W_err"]
                          /\ UNCHANGED << hasError, won >>
                     ELSE /\ /\ hasError' = TRUE
                             /\ uaf' = (uaf \/ freed)
                             /\ won' = [won EXCEPT ![self] = ~hasError]
                          /\ pc' = [pc EXCEPT ![self] = "W_swap"]
                          /\ UNCHANGED << active, ended >>
               /\ UNCHANGED << key, pushed, next, membufClaimed, owner, cnt, 
                               temp, parts, out, merged, mainErr, failed, intr, 
                               cancelled, freed, tableFreed, res, final, 
                               fellBack, mb, u, tmp, p, ret, ok, matched >>

W_swap(self) == /\ pc[self] = "W_swap"
                /\ IF won[self]
                      THEN /\ mainErr' = failed[self]
                      ELSE /\ TRUE
                           /\ UNCHANGED mainErr
                /\ uaf' = (uaf \/ freed)
                /\ pc' = [pc EXCEPT ![self] = "W_rearm"]
                /\ UNCHANGED << key, pushed, active, next, membufClaimed, 
                                owner, cnt, temp, parts, out, merged, hasError, 
                                failed, intr, cancelled, freed, tableFreed, 
                                res, final, fellBack, mb, u, won, tmp, p, ret, 
                                ok, matched, ended >>

W_rearm(self) == /\ pc[self] = "W_rearm"
                 /\ intr' = TRUE
                 /\ pc' = [pc EXCEPT ![self] = "W_cleanup"]
                 /\ UNCHANGED << key, pushed, active, next, membufClaimed, 
                                 owner, cnt, temp, parts, out, merged, 
                                 hasError, mainErr, failed, cancelled, freed, 
                                 tableFreed, uaf, res, final, fellBack, mb, u, 
                                 won, tmp, p, ret, ok, matched, ended >>

W_cleanup(self) == /\ pc[self] = "W_cleanup"
                   /\ IF Phase = "split" /\ ok[self] /\ failed[self] = "none"
                         THEN /\ p' = [p EXCEPT ![self] = 0]
                              /\ pc' = [pc EXCEPT ![self] = "W_merge"]
                         ELSE /\ pc' = [pc EXCEPT ![self] = "W_pclean"]
                              /\ p' = p
                   /\ UNCHANGED << key, pushed, active, next, membufClaimed, 
                                   owner, cnt, temp, parts, out, merged, 
                                   hasError, mainErr, failed, intr, cancelled, 
                                   freed, tableFreed, uaf, res, final, 
                                   fellBack, mb, u, won, tmp, ret, ok, matched, 
                                   ended >>

W_merge(self) == /\ pc[self] = "W_merge"
                 /\ IF p[self] < NP
                       THEN /\ IF temp[self][p[self]] = {}
                                  THEN /\ p' = [p EXCEPT ![self] = p[self] + 1]
                                       /\ pc' = [pc EXCEPT ![self] = "W_merge"]
                                       /\ ret' = ret
                                  ELSE /\ ret' = [ret EXCEPT ![self] = "merge"]
                                       /\ pc' = [pc EXCEPT ![self] = "W_fl"]
                                       /\ p' = p
                       ELSE /\ pc' = [pc EXCEPT ![self] = "W_pclean"]
                            /\ UNCHANGED << p, ret >>
                 /\ UNCHANGED << key, pushed, active, next, membufClaimed, 
                                 owner, cnt, temp, parts, out, merged, 
                                 hasError, mainErr, failed, intr, cancelled, 
                                 freed, tableFreed, uaf, res, final, fellBack, 
                                 mb, u, won, tmp, ok, matched, ended >>

W_pclean(self) == /\ pc[self] = "W_pclean"
                  /\ IF Phase = "split"
                        THEN /\ temp' = [temp EXCEPT ![self] = [q \in Parts |-> {}]]
                             /\ UNCHANGED << out, tableFreed >>
                        ELSE /\ IF Phase = "probe"
                                   THEN /\ /\ out' = [out EXCEPT ![self] = out[self] \cup (IF Mutant = "preserved_build" /\ ok[self] /\ ~matched[self]
                                                                                           THEN {<<0, "b1">>} ELSE {})]
                                           /\ tableFreed' = (tableFreed \/ Mutant = "worker_frees_table")
                                   ELSE /\ TRUE
                                        /\ UNCHANGED << out, tableFreed >>
                             /\ temp' = temp
                  /\ pc' = [pc EXCEPT ![self] = "W_end"]
                  /\ UNCHANGED << key, pushed, active, next, membufClaimed, 
                                  owner, cnt, parts, merged, hasError, mainErr, 
                                  failed, intr, cancelled, freed, uaf, res, 
                                  final, fellBack, mb, u, won, tmp, p, ret, ok, 
                                  matched, ended >>

W_end(self) == /\ pc[self] = "W_end"
               /\ IF ~ended[self] /\ ~(Mutant = "lost_end_on_error" /\ failed[self] # "none")
                     THEN /\ active' = active \ {self}
                     ELSE /\ TRUE
                          /\ UNCHANGED active
               /\ uaf' = (uaf \/ freed)
               /\ pc' = [pc EXCEPT ![self] = "Done"]
               /\ UNCHANGED << key, pushed, next, membufClaimed, owner, cnt, 
                               temp, parts, out, merged, hasError, mainErr, 
                               failed, intr, cancelled, freed, tableFreed, res, 
                               final, fellBack, mb, u, won, tmp, p, ret, ok, 
                               matched, ended >>

worker(self) == W_start(self) \/ W_check(self) \/ W_claim(self)
                   \/ W_cas_write(self) \/ W_fa_write(self) \/ W_proc(self)
                   \/ W_fl(self) \/ W_fl_write(self) \/ W_err(self)
                   \/ W_swap(self) \/ W_rearm(self) \/ W_cleanup(self)
                   \/ W_merge(self) \/ W_pclean(self) \/ W_end(self)

L_push == /\ pc[Leader] = "L_push"
          /\ \E w \in Workers \ pushed:
               /\ active' = (active \cup {w})
               /\ pushed' = (pushed \cup {w})
          /\ IF pushed' # Workers
                THEN /\ pc' = [pc EXCEPT ![Leader] = "L_push"]
                ELSE /\ pc' = [pc EXCEPT ![Leader] = "L_join"]
          /\ UNCHANGED << key, next, membufClaimed, owner, cnt, temp, parts, 
                          out, merged, hasError, mainErr, failed, intr, 
                          cancelled, freed, tableFreed, uaf, res, final, 
                          fellBack, mb, u, won, tmp, p, ret, ok, matched, 
                          ended >>

L_join == /\ pc[Leader] = "L_join"
          /\ IF Mutant = "early_join"
                THEN /\ active = {} \/ hasError
                ELSE /\ active = {}
          /\ pc' = [pc EXCEPT ![Leader] = "L_after"]
          /\ UNCHANGED << key, pushed, active, next, membufClaimed, owner, cnt, 
                          temp, parts, out, merged, hasError, mainErr, failed, 
                          intr, cancelled, freed, tableFreed, uaf, res, final, 
                          fellBack, mb, u, won, tmp, p, ret, ok, matched, 
                          ended >>

L_after == /\ pc[Leader] = "L_after"
           /\ IF hasError
                 THEN /\ IF Mutant # "no_clear_interrupt"
                            THEN /\ intr' = FALSE
                            ELSE /\ TRUE
                                 /\ intr' = intr
                      /\ res' = mainErr
                      /\ UNCHANGED merged
                 ELSE /\ /\ merged' = UNION {out[w] : w \in Workers}
                         /\ res' = "ok"
                      /\ intr' = intr
           /\ pc' = [pc EXCEPT ![Leader] = "L_free"]
           /\ UNCHANGED << key, pushed, active, next, membufClaimed, owner, 
                           cnt, temp, parts, out, hasError, mainErr, failed, 
                           cancelled, freed, tableFreed, uaf, final, fellBack, 
                           mb, u, won, tmp, p, ret, ok, matched, ended >>

L_free == /\ pc[Leader] = "L_free"
          /\ /\ freed' = TRUE
             /\ tableFreed' = TRUE
          /\ pc' = [pc EXCEPT ![Leader] = "L_fallback"]
          /\ UNCHANGED << key, pushed, active, next, membufClaimed, owner, cnt, 
                          temp, parts, out, merged, hasError, mainErr, failed, 
                          intr, cancelled, uaf, res, final, fellBack, mb, u, 
                          won, tmp, p, ret, ok, matched, ended >>

L_fallback == /\ pc[Leader] = "L_fallback"
              /\ IF Phase = "split" /\ res \notin {"ok", "intr"}
                    THEN /\ fellBack' = TRUE
                         /\ IF intr
                               THEN /\ /\ final' = "intr"
                                       /\ intr' = FALSE
                               ELSE /\ final' = "ok"
                                    /\ intr' = intr
                    ELSE /\ final' = res
                         /\ UNCHANGED << intr, fellBack >>
              /\ pc' = [pc EXCEPT ![Leader] = "Done"]
              /\ UNCHANGED << key, pushed, active, next, membufClaimed, owner, 
                              cnt, temp, parts, out, merged, hasError, mainErr, 
                              failed, cancelled, freed, tableFreed, uaf, res, 
                              mb, u, won, tmp, p, ret, ok, matched, ended >>

leader == L_push \/ L_join \/ L_after \/ L_free \/ L_fallback

U_cancel == /\ pc[User] = "U_cancel"
            /\ \/ /\ TRUE
                  /\ UNCHANGED <<intr, cancelled>>
               \/ /\ pc[Leader] # "Done"
                  /\ /\ cancelled' = TRUE
                     /\ intr' = TRUE
            /\ pc' = [pc EXCEPT ![User] = "Done"]
            /\ UNCHANGED << key, pushed, active, next, membufClaimed, owner, 
                            cnt, temp, parts, out, merged, hasError, mainErr, 
                            failed, freed, tableFreed, uaf, res, final, 
                            fellBack, mb, u, won, tmp, p, ret, ok, matched, 
                            ended >>

user == U_cancel

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == /\ \A self \in ProcSet: pc[self] = "Done"
               /\ UNCHANGED vars

Next == leader \/ user
           \/ (\E self \in Workers: worker(self))
           \/ Terminating

Spec == /\ Init /\ [][Next]_vars
        /\ \A self \in Workers : WF_vars(worker(self))
        /\ WF_vars(leader)

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION

(* Inductive invariant of the correct variant (Mutant = "none"): checked by TLC
   on every reachable state (IndInv is in each pass cfg), from every IndInv state
   (PxHashJoin.inductive-*.cfg), and proved for any constants in PxHashJoin_proofs.tla.
   Conjuncts bind each variable before constraining it so TLC can enumerate IndInit. *)
\* the correct variant never reaches the mutant-only labels W_cas_write, W_fa_write, W_fl_write
WLabels == {"W_start", "W_check", "W_claim", "W_proc", "W_fl", "W_err", "W_swap", "W_rearm",
            "W_cleanup", "W_merge", "W_pclean", "W_end", "Done"}
LLabels == {"L_push", "L_join", "L_after", "L_free", "L_fallback", "Done"}
ULabels == {"U_cancel", "Done"}
ErrPc == {"W_err", "W_swap", "W_rearm", "W_cleanup", "W_pclean", "W_end", "Done"}
PostJoin == {"L_after", "L_free", "L_fallback", "Done"}
Returned == {"L_free", "L_fallback", "Done"}
TempVals == IF Phase = "split" THEN Units ELSE {}
WOutVals == IF Phase = "join" THEN Units \X {"ctx"}
            ELSE IF Phase = "probe" THEN Units \X {"b1", "-"} ELSE {}
Handed(v) == IF v <= NM THEN (IF owner # "none" /\ v < mb[owner] THEN 1 ELSE 0)
             ELSE (IF v < next THEN 1 ELSE 0)
IPc ==
  /\ pc \in [ProcSet -> WLabels \cup LLabels \cup ULabels]
  /\ \A w \in Workers : pc[w] \in WLabels
  /\ pc[Leader] \in LLabels
  /\ pc[User] \in ULabels
IKey ==
  /\ key \in [Units -> KeyVals]
  /\ Phase = "join" => key = [v \in Units |-> "k1"]
IPush ==
  /\ pushed \in SUBSET Workers
  /\ (pc[Leader] = "L_push" <=> pushed # Workers)
  /\ \A w \in Workers \ pushed : pc[w] = "W_start"
  /\ active = {w \in pushed : pc[w] # "Done"}
  /\ pc[Leader] \in PostJoin => active = {}
IFix ==
  /\ ended = [w \in Workers |-> FALSE]
  /\ tmp = [w \in Workers |-> 0]
  /\ matched = [w \in Workers |-> FALSE]
IErr ==
  /\ hasError \in BOOLEAN
  /\ failed \in [Workers -> ErrVals]
  /\ won \in [Workers -> BOOLEAN]
  /\ \A w \in Workers : failed[w] # "none" => pc[w] \in ErrPc
  /\ \A w \in Workers : pc[w] \in {"W_err", "W_swap", "W_rearm"} => failed[w] # "none"
  /\ \A w \in Workers : failed[w] # "none" /\ pc[w] # "W_err" => hasError
  /\ \A w \in Workers : won[w] => failed[w] # "none" /\ pc[w] \in ErrPc \ {"W_err"}
  /\ \A w, x \in Workers : won[w] /\ won[x] => w = x
  /\ hasError => \E w \in Workers : won[w]
IMain ==
  /\ mainErr \in ErrVals
  /\ \A w \in Workers : won[w] /\ pc[w] # "W_swap" => mainErr = failed[w]
  /\ (\A w \in Workers : ~won[w] \/ pc[w] = "W_swap") => mainErr = "none"
IIntr ==
  /\ intr \in BOOLEAN
  /\ cancelled \in BOOLEAN
  /\ cancelled => pc[User] = "Done"
  /\ ~cancelled /\ intr => hasError /\ pc[Leader] \in {"L_push", "L_join", "L_after"}
IFree ==
  /\ freed \in BOOLEAN
  /\ (freed <=> pc[Leader] \in {"L_fallback", "Done"})
  /\ tableFreed \in BOOLEAN
  /\ (tableFreed <=> freed)
  /\ uaf \in BOOLEAN
  /\ ~uaf
IRes ==
  /\ res = (IF pc[Leader] \in Returned THEN (IF hasError THEN mainErr ELSE "ok") ELSE "none")
  /\ fellBack \in BOOLEAN
  /\ fellBack => Phase = "split" /\ pc[Leader] = "Done"
  /\ final \in ErrVals \cup {"ok"}
  /\ (final # "none" <=> pc[Leader] = "Done")
IDisp ==
  /\ next \in (NM + 1)..(NU + 1)
  /\ membufClaimed \in BOOLEAN
  /\ owner \in Workers \cup {"none"}
  /\ mb \in [Workers -> -1..(NM + 1)]
  /\ (membufClaimed <=> owner # "none")
  /\ NM = 0 => ~membufClaimed
  /\ \A w \in Workers : w # owner => mb[w] \in {-1, 0}
  /\ owner # "none" => mb[owner] \in 1..(NM + 1)
  /\ \A w \in Workers : mb[w] = -1 /\ NM > 0 => membufClaimed
  /\ \A w \in Workers : pc[w] = "W_start" => mb[w] = 0
ICnt ==
  /\ cnt \in [Units -> {0, 1}]
  /\ \A v \in Units : cnt[v] = Handed(v)
ILocal ==
  /\ u \in [Workers -> Units]
  /\ p \in [Workers -> 0..NP]
  /\ ret \in [Workers -> {"check", "merge"}]
  /\ ok \in [Workers -> BOOLEAN]
  /\ \A w \in Workers : pc[w] \in {"W_fl", "W_merge"} => Phase = "split"
  /\ \A w \in Workers : pc[w] = "W_fl" => p[w] < NP
IStart ==
  \A w \in Workers : pc[w] = "W_start" => ~ok[w] /\ ~won[w] /\ failed[w] = "none"
IDataT ==
  /\ temp \in [Workers -> [Parts -> SUBSET TempVals]]
  /\ parts \in [Parts -> SUBSET TempVals]
  /\ out \in [Workers -> SUBSET WOutVals]
IMerged ==
  merged = (IF pc[Leader] \in Returned /\ ~hasError THEN UNION {out[w] : w \in Workers} ELSE {})
IndInv == IPc /\ IKey /\ IPush /\ IFix /\ IErr /\ IMain /\ IIntr /\ IFree /\ IRes /\ IDisp
          /\ ICnt /\ ILocal /\ IStart /\ IDataT
          /\ IMerged
IndInit == IndInv
=============================================================================
