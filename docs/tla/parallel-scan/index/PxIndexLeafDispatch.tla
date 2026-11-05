------------------------- MODULE PxIndexLeafDispatch -------------------------
(* Parallel index scan leaf dispatcher (develop e98bdd885,
   px_scan_index_leaf_page_dispatcher.cpp) against concurrent B-tree splits,
   vacuum merges and page reuse.

   Workers share one dispatcher. A worker asks for its next leaf while it still
   holds its current one; lock_holding releases that leaf before waiting for the
   dispatcher mutex unless it is the frontier (ascending: the last leaf handed
   out while the chain goes on), whose holder keeps it latched until the next
   leaf is fixed, so vacuum cannot merge that next leaf into it and free it.
   Descending: the dispatcher remembers the last leaf handed out (VPID, LSA, its
   smallest key); it fixes the saved left link only while that leaf still links
   back, and otherwise relocates the smallest key handed out (from the saved
   leaf if its LSA is unchanged, else from the root).

   The tree is one root over a chain of leaves; leaf p covers keys >= lo[p] up
   to the next leaf's lo. Writers latch top-down and left to right: root, the
   leaf, then its right neighbour (btree_split_node_and_advance,
   btree_merge_node_and_advance). A split moves the upper keys of a full leaf to
   a new right leaf; a merge moves an emptied right leaf's range into its left
   leaf and deallocates it; a freed page may be reused by the next split. *)
EXTENDS Naturals, FiniteSets

CONSTANTS Workers, Writer, Desc, Mutant, Fix, WriterOps, Cap, EarlyStop
ASSUME Assm ==
  /\ Workers # {} /\ Writer \notin Workers /\ Desc \in BOOLEAN /\ WriterOps \in Nat /\ Cap \in Nat \ {0}
  /\ Mutant \in {"none", "release_frontier", "trust_prev_link", "merge_right_first", "stop_keeps_chain"}
  /\ EarlyStop \in BOOLEAN              \* a worker may stop early (LIMIT reached, error): release_leaf
  /\ Fix \in {"none", "check_last_lsa"}   \* "check_last_lsa": the candidate fix for the VPID reuse below

Pages == 1..4
NoPage == 0
Stable == {2, 4}                 \* keys present for the whole scan
Churn == {1, 3, 5}               \* keys writers insert and delete
Keys == Stable \cup Churn
NoKey == 0
Inf == 99

(* --algorithm PxIndexLeafDispatch
variables
  inUse = [p \in Pages |-> p \in {1, 2, 3}],
  keys = [p \in Pages |-> CASE p = 1 -> {2} [] p = 2 -> {3} [] p = 3 -> {4} [] OTHER -> {}],
  lo = [p \in Pages |-> CASE p = 1 -> 0 [] p = 2 -> 3 [] p = 3 -> 4 [] OTHER -> 0],
  nxt = [p \in Pages |-> CASE p = 1 -> 2 [] p = 2 -> 3 [] OTHER -> NoPage],
  prv = [p \in Pages |-> CASE p = 2 -> 1 [] p = 3 -> 2 [] OTHER -> NoPage],
  lsa = [p \in Pages |-> 1],
  \* latches
  rootS = {}, rootX = FALSE,
  rd = [p \in Pages |-> {}], wx = {},
  \* dispatcher (m_leaf_mutex and what it protects)
  mutex = NoPage,                 \* holder: a worker or NoPage
  descentDone = FALSE, ended = FALSE, current = NoPage,
  frontier = NoPage,
  lastVpid = NoPage, lastLsa = 0, lastKey = NoKey,
  \* ghosts
  readCnt = [x \in Keys |-> 0],
  fixFreed = FALSE,
  stopped = FALSE;

define
  Chain == {p \in Pages : inUse[p]}
  First == CHOOSE p \in Chain : prv[p] = NoPage
  Last == CHOOSE p \in Chain : nxt[p] = NoPage
  LeafFor(x) == CHOOSE p \in Chain : lo[p] <= x /\ (nxt[p] = NoPage \/ lo[nxt[p]] > x)
  MinKey(S) == CHOOSE x \in S : \A j \in S : x <= j
  MaxKey(S) == CHOOSE x \in S : \A j \in S : x >= j
  XFree(p) == rd[p] = {} /\ p \notin wx
  SFree(p) == p \notin wx
  TypeOK == /\ inUse \in [Pages -> BOOLEAN] /\ keys \in [Pages -> SUBSET Keys]
            /\ nxt \in [Pages -> Pages \cup {NoPage}] /\ prv \in [Pages -> Pages \cup {NoPage}]
            /\ rd \in [Pages -> SUBSET Workers] /\ wx \subseteq Pages
            /\ readCnt \in [Keys -> Nat]
  AllDone == \A w \in Workers : pc[w] = "Done"
  \* C1: every key present for the whole scan is returned exactly once.
  StableOnce == AllDone /\ ~stopped => \A x \in Stable : readCnt[x] = 1
  NoStableDuplicate == \A x \in Stable : readCnt[x] <= 1
  \* C3: no worker or dispatcher fixes a deallocated leaf as a live one.
  NoFreedFix == ~fixFreed
  ScanFinishes == <>AllDone
  \* witnesses
  NotMergedDuringScan == ~(~AllDone /\ ~inUse[2] /\ \E w \in Workers : pc[w] # "W_start")
  NotSplitDuringScan == ~(~AllDone /\ inUse[4] /\ \E w \in Workers : pc[w] # "W_start")
end define;

fair process worker \in Workers
variables held = NoPage, out = NoPage, bound = Inf, cand = NoPage;
begin
  W_start:
    skip;
  W_ask:
    either
      await EarlyStop /\ held # NoPage;
      goto W_stop;
    or
      \* lock_holding: a held leaf that is not the frontier is released before waiting
      if held # NoPage /\ (held # frontier \/ Mutant = "release_frontier") then
        rd[held] := rd[held] \ {self} || held := NoPage;
      end if;
    end either;
  W_lock:
    await mutex = NoPage \/ (held # NoPage /\ held # frontier);
    if mutex # NoPage then
      \* the frontier moved on while this worker spun: release it and keep waiting
      rd[held] := rd[held] \ {self} || held := NoPage;
      goto W_lock;
    else
      mutex := self;
    end if;
  W_dispatch:
    if ~descentDone then
      goto D_root;
    elsif ended then
      mutex := NoPage;
      goto W_end;
    elsif ~Desc then
      goto D_fix_next;
    else
      goto D_fix_prev;
    end if;
  D_root:
    await ~rootX;
    rootS := rootS \cup {self};
  D_leaf:
    with p = IF Desc THEN Last ELSE First do
      await SFree(p);
      rd[p] := rd[p] \cup {self} || out := p || rootS := rootS \ {self} || bound := Inf;
      current := IF Desc THEN prv[p] ELSE nxt[p];
      ended := (IF Desc THEN prv[p] ELSE nxt[p]) = NoPage;
      descentDone := TRUE;
      if Desc then
        lastVpid := p || lastLsa := lsa[p] || lastKey := IF keys[p] # {} THEN MinKey(keys[p]) ELSE NoKey;
      end if;
    end with;
    goto D_publish;
  D_fix_next:
    \* ascending chain walk: pgbuf_fix (OLD_PAGE) of the saved right link
    await SFree(current);
    if ~inUse[current] then fixFreed := TRUE end if;
    rd[current] := rd[current] \cup {self} || out := current || bound := Inf;
    ended := nxt[current] = NoPage;
    current := IF nxt[current] = NoPage THEN current ELSE nxt[current];
    goto D_publish;
  D_fix_prev:
    \* descending: fix_prev_leaf (OLD_PAGE_MAYBE_DEALLOCATED), trusted only while it links back
    await SFree(current);
    if Mutant = "trust_prev_link"
       \/ (inUse[current] /\ nxt[current] = lastVpid
           \* candidate fix: the last leaf is still the leaf handed out (fixed left to right, as the serial scan does)
           /\ (Fix = "check_last_lsa" => inUse[lastVpid] /\ lsa[lastVpid] = lastLsa)) then
      \* before CBRD-27737 the saved link was fixed with OLD_PAGE and never checked
      fixFreed := fixFreed \/ ~inUse[current];
      rd[current] := rd[current] \cup {self} || out := current || bound := Inf;
      goto D_desc_take;
    elsif lastKey = NoKey then
      descentDone := FALSE;               \* nothing handed out in this range yet: restart it
      goto D_root;
    elsif inUse[lastVpid] /\ lsa[lastVpid] = lastLsa then
      cand := lastVpid;
      goto D_saved;
    else
      goto D_reroot;
    end if;
  D_saved:
    \* btree_locate_key_from_saved_leaf: the saved leaf is unchanged and was handed out whole;
    \* continue the chain from it
    await SFree(cand);
    if inUse[cand] /\ lsa[cand] = lastLsa then
      if prv[cand] = NoPage then
        ended := TRUE;
      else
        current := prv[cand];
      end if;
      goto W_retry;
    else
      goto D_reroot;
    end if;
  D_reroot:
    await ~rootX;
    rootS := rootS \cup {self};
  D_reroot_leaf:
    with p = LeafFor(lastKey) do
      await SFree(p);
      rootS := rootS \ {self};
      if \E key \in keys[p] : key < lastKey then
        \* hand out the located leaf from the slot below the last key
        rd[p] := rd[p] \cup {self} || out := p || bound := lastKey;
        goto D_desc_take;
      else
        \* nothing below the last key here: continue the chain from this leaf
        lastVpid := p || lastLsa := lsa[p];
        if prv[p] = NoPage then ended := TRUE else current := prv[p] end if;
        goto W_retry;
      end if;
    end with;
  W_retry:
    \* goto retry in dispatch_next_leaf, still under the mutex
    if ended then
      mutex := NoPage;
      goto W_end;
    else
      goto D_fix_prev;
    end if;
  D_desc_take:
    \* save_last_leaf, then the next left link
    if prv[out] = NoPage then ended := TRUE else current := prv[out] end if;
    lastVpid := out || lastLsa := lsa[out] || lastKey := IF keys[out] # {} THEN MinKey(keys[out]) ELSE lastKey;
  D_publish:
    \* ascending: out stays latched by its worker until its right leaf is fixed
    frontier := IF ~Desc /\ ~ended THEN out ELSE NoPage;
    mutex := NoPage;
    \* set_page: the previous leaf (the old frontier) is released once out is held
    rd := IF held # NoPage THEN [rd EXCEPT ![held] = @ \ {self}] ELSE rd;
    held := out || out := NoPage;
  W_read:
    readCnt := [key \in Keys |-> IF key \in keys[held] /\ key < bound THEN readCnt[key] + 1 ELSE readCnt[key]];
    goto W_ask;
  W_stop:
    \* release_leaf: a worker that stops while holding the frontier ends the chain under the mutex,
    \* so no worker fixes the frontier's right leaf unprotected
    if held = frontier /\ Mutant # "stop_keeps_chain" then
      await mutex = NoPage;
      ended := TRUE;
      frontier := NoPage;
    end if;
    rd[held] := rd[held] \ {self} || held := NoPage;
    stopped := TRUE;
    goto W_end;
  W_end:
    if held # NoPage then rd[held] := rd[held] \ {self} || held := NoPage end if;
end process;

\* Vacuum and DML on the same index, at most WriterOps operations; fair: a split or merge it starts, it finishes.
fair process writer = Writer
variables ops = WriterOps, l = NoPage, r = NoPage, rr = NoPage, k = NoKey, n = NoPage;
begin
  X_loop:
    while ops > 0 do
      ops := ops - 1;
      either
        \* insert a churn key; split its leaf when it is full
        with key \in {c \in Churn : \A p \in Chain : c \notin keys[p]} do
          await ~rootX /\ rootS = {};
          rootX := TRUE || k := key;
        end with;
  X_ins_leaf:
        with leaf = LeafFor(k) do
          await XFree(leaf);
          if Cardinality(keys[leaf]) < Cap then
            keys[leaf] := keys[leaf] \cup {k} || lsa[leaf] := lsa[leaf] + 1;
            rootX := FALSE;
            goto X_loop;
          elsif \A p \in Pages : inUse[p] then
            \* the model's page pool is used up (file_alloc would extend the file): skip this insert
            rootX := FALSE;
            goto X_loop;
          else
            l := leaf;
            wx := wx \cup {leaf};
          end if;
        end with;
  X_split_alloc:
        with fresh \in {p \in Pages : ~inUse[p]} do
          n := fresh;
        end with;
        r := nxt[l];
  X_split_right:
        if r # NoPage then
          await XFree(r);
          wx := wx \cup {r};
        end if;
  X_split_apply:
        with all = keys[l] \cup {k} do
          \* the upper key moves to the new right leaf
          keys := [keys EXCEPT ![l] = all \ {MaxKey(all)}, ![n] = {MaxKey(all)}];
          lo := [lo EXCEPT ![n] = MaxKey(all)];
        end with;
        inUse[n] := TRUE;
        nxt := [nxt EXCEPT ![l] = n, ![n] = r];
        prv := [p \in Pages |-> IF p = n THEN l ELSE IF p = r THEN n ELSE prv[p]];
        lsa := [p \in Pages |-> IF p \in {l, n, r} THEN lsa[p] + 1 ELSE lsa[p]];
        wx := {} || rootX := FALSE || l := NoPage || r := NoPage || n := NoPage;
      or
        \* vacuum: remove a dead churn key, then merge its leaf into the left one when empty
        with key \in {c \in Churn : \E p \in Chain : c \in keys[p]} do
          await ~rootX /\ rootS = {};
          rootX := TRUE || k := key;
        end with;
  X_del_leaf:
        with leaf = LeafFor(k) do
          if Mutant = "merge_right_first" then
            await XFree(leaf);
            wx := wx \cup {leaf};
          end if;
          r := leaf;
        end with;
  X_del_left:
        with left = prv[r] do
          if Cardinality(keys[r]) = 1 /\ left # NoPage then
            \* merge: the left leaf first, then the emptied right leaf, then its right neighbour
            await XFree(left);
            wx := wx \cup {left};
            l := left;
          else
            l := NoPage;
          end if;
        end with;
  X_del_right:
        if r \notin wx then
          await XFree(r);
          wx := wx \cup {r};
        end if;
        rr := IF l # NoPage THEN nxt[r] ELSE NoPage;
  X_del_rr:
        if rr # NoPage then
          await XFree(rr);
          wx := wx \cup {rr};
        end if;
  X_del_apply:
        keys[r] := keys[r] \ {k};
        if l # NoPage then
          inUse[r] := FALSE;               \* file_dealloc
          nxt := [nxt EXCEPT ![l] = rr, ![r] = NoPage];
          prv := [p \in Pages |-> IF p = rr THEN l ELSE IF p = r THEN NoPage ELSE prv[p]];
          lsa := [p \in Pages |-> IF p \in {l, r, rr} THEN lsa[p] + 1 ELSE lsa[p]];
        else
          lsa[r] := lsa[r] + 1;
        end if;
        wx := {} || rootX := FALSE || l := NoPage || r := NoPage || rr := NoPage;
      end either;
    end while;
end process;
end algorithm; *)
\* BEGIN TRANSLATION
VARIABLES inUse, keys, lo, nxt, prv, lsa, rootS, rootX, rd, wx, mutex, 
          descentDone, ended, current, frontier, lastVpid, lastLsa, lastKey, 
          readCnt, fixFreed, stopped, pc

(* define statement *)
Chain == {p \in Pages : inUse[p]}
First == CHOOSE p \in Chain : prv[p] = NoPage
Last == CHOOSE p \in Chain : nxt[p] = NoPage
LeafFor(x) == CHOOSE p \in Chain : lo[p] <= x /\ (nxt[p] = NoPage \/ lo[nxt[p]] > x)
MinKey(S) == CHOOSE x \in S : \A j \in S : x <= j
MaxKey(S) == CHOOSE x \in S : \A j \in S : x >= j
XFree(p) == rd[p] = {} /\ p \notin wx
SFree(p) == p \notin wx
TypeOK == /\ inUse \in [Pages -> BOOLEAN] /\ keys \in [Pages -> SUBSET Keys]
          /\ nxt \in [Pages -> Pages \cup {NoPage}] /\ prv \in [Pages -> Pages \cup {NoPage}]
          /\ rd \in [Pages -> SUBSET Workers] /\ wx \subseteq Pages
          /\ readCnt \in [Keys -> Nat]
AllDone == \A w \in Workers : pc[w] = "Done"

StableOnce == AllDone /\ ~stopped => \A x \in Stable : readCnt[x] = 1
NoStableDuplicate == \A x \in Stable : readCnt[x] <= 1

NoFreedFix == ~fixFreed
ScanFinishes == <>AllDone

NotMergedDuringScan == ~(~AllDone /\ ~inUse[2] /\ \E w \in Workers : pc[w] # "W_start")
NotSplitDuringScan == ~(~AllDone /\ inUse[4] /\ \E w \in Workers : pc[w] # "W_start")

VARIABLES held, out, bound, cand, ops, l, r, rr, k, n

vars == << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, rd, wx, mutex, 
           descentDone, ended, current, frontier, lastVpid, lastLsa, lastKey, 
           readCnt, fixFreed, stopped, pc, held, out, bound, cand, ops, l, r, 
           rr, k, n >>

ProcSet == (Workers) \cup {Writer}

Init == (* Global variables *)
        /\ inUse = [p \in Pages |-> p \in {1, 2, 3}]
        /\ keys = [p \in Pages |-> CASE p = 1 -> {2} [] p = 2 -> {3} [] p = 3 -> {4} [] OTHER -> {}]
        /\ lo = [p \in Pages |-> CASE p = 1 -> 0 [] p = 2 -> 3 [] p = 3 -> 4 [] OTHER -> 0]
        /\ nxt = [p \in Pages |-> CASE p = 1 -> 2 [] p = 2 -> 3 [] OTHER -> NoPage]
        /\ prv = [p \in Pages |-> CASE p = 2 -> 1 [] p = 3 -> 2 [] OTHER -> NoPage]
        /\ lsa = [p \in Pages |-> 1]
        /\ rootS = {}
        /\ rootX = FALSE
        /\ rd = [p \in Pages |-> {}]
        /\ wx = {}
        /\ mutex = NoPage
        /\ descentDone = FALSE
        /\ ended = FALSE
        /\ current = NoPage
        /\ frontier = NoPage
        /\ lastVpid = NoPage
        /\ lastLsa = 0
        /\ lastKey = NoKey
        /\ readCnt = [x \in Keys |-> 0]
        /\ fixFreed = FALSE
        /\ stopped = FALSE
        (* Process worker *)
        /\ held = [self \in Workers |-> NoPage]
        /\ out = [self \in Workers |-> NoPage]
        /\ bound = [self \in Workers |-> Inf]
        /\ cand = [self \in Workers |-> NoPage]
        (* Process writer *)
        /\ ops = WriterOps
        /\ l = NoPage
        /\ r = NoPage
        /\ rr = NoPage
        /\ k = NoKey
        /\ n = NoPage
        /\ pc = [self \in ProcSet |-> CASE self \in Workers -> "W_start"
                                        [] self = Writer -> "X_loop"]

W_start(self) == /\ pc[self] = "W_start"
                 /\ TRUE
                 /\ pc' = [pc EXCEPT ![self] = "W_ask"]
                 /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                 rd, wx, mutex, descentDone, ended, current, 
                                 frontier, lastVpid, lastLsa, lastKey, readCnt, 
                                 fixFreed, stopped, held, out, bound, cand, 
                                 ops, l, r, rr, k, n >>

W_ask(self) == /\ pc[self] = "W_ask"
               /\ \/ /\ EarlyStop /\ held[self] # NoPage
                     /\ pc' = [pc EXCEPT ![self] = "W_stop"]
                     /\ UNCHANGED <<rd, held>>
                  \/ /\ IF held[self] # NoPage /\ (held[self] # frontier \/ Mutant = "release_frontier")
                           THEN /\ /\ held' = [held EXCEPT ![self] = NoPage]
                                   /\ rd' = [rd EXCEPT ![held[self]] = rd[held[self]] \ {self}]
                           ELSE /\ TRUE
                                /\ UNCHANGED << rd, held >>
                     /\ pc' = [pc EXCEPT ![self] = "W_lock"]
               /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                               wx, mutex, descentDone, ended, current, 
                               frontier, lastVpid, lastLsa, lastKey, readCnt, 
                               fixFreed, stopped, out, bound, cand, ops, l, r, 
                               rr, k, n >>

W_lock(self) == /\ pc[self] = "W_lock"
                /\ mutex = NoPage \/ (held[self] # NoPage /\ held[self] # frontier)
                /\ IF mutex # NoPage
                      THEN /\ /\ held' = [held EXCEPT ![self] = NoPage]
                              /\ rd' = [rd EXCEPT ![held[self]] = rd[held[self]] \ {self}]
                           /\ pc' = [pc EXCEPT ![self] = "W_lock"]
                           /\ mutex' = mutex
                      ELSE /\ mutex' = self
                           /\ pc' = [pc EXCEPT ![self] = "W_dispatch"]
                           /\ UNCHANGED << rd, held >>
                /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                wx, descentDone, ended, current, frontier, 
                                lastVpid, lastLsa, lastKey, readCnt, fixFreed, 
                                stopped, out, bound, cand, ops, l, r, rr, k, n >>

W_dispatch(self) == /\ pc[self] = "W_dispatch"
                    /\ IF ~descentDone
                          THEN /\ pc' = [pc EXCEPT ![self] = "D_root"]
                               /\ mutex' = mutex
                          ELSE /\ IF ended
                                     THEN /\ mutex' = NoPage
                                          /\ pc' = [pc EXCEPT ![self] = "W_end"]
                                     ELSE /\ IF ~Desc
                                                THEN /\ pc' = [pc EXCEPT ![self] = "D_fix_next"]
                                                ELSE /\ pc' = [pc EXCEPT ![self] = "D_fix_prev"]
                                          /\ mutex' = mutex
                    /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, 
                                    rootX, rd, wx, descentDone, ended, current, 
                                    frontier, lastVpid, lastLsa, lastKey, 
                                    readCnt, fixFreed, stopped, held, out, 
                                    bound, cand, ops, l, r, rr, k, n >>

D_root(self) == /\ pc[self] = "D_root"
                /\ ~rootX
                /\ rootS' = (rootS \cup {self})
                /\ pc' = [pc EXCEPT ![self] = "D_leaf"]
                /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootX, rd, wx, 
                                mutex, descentDone, ended, current, frontier, 
                                lastVpid, lastLsa, lastKey, readCnt, fixFreed, 
                                stopped, held, out, bound, cand, ops, l, r, rr, 
                                k, n >>

D_leaf(self) == /\ pc[self] = "D_leaf"
                /\ LET p == IF Desc THEN Last ELSE First IN
                     /\ SFree(p)
                     /\ /\ bound' = [bound EXCEPT ![self] = Inf]
                        /\ out' = [out EXCEPT ![self] = p]
                        /\ rd' = [rd EXCEPT ![p] = rd[p] \cup {self}]
                        /\ rootS' = rootS \ {self}
                     /\ current' = IF Desc THEN prv[p] ELSE nxt[p]
                     /\ ended' = ((IF Desc THEN prv[p] ELSE nxt[p]) = NoPage)
                     /\ descentDone' = TRUE
                     /\ IF Desc
                           THEN /\ /\ lastKey' = (IF keys[p] # {} THEN MinKey(keys[p]) ELSE NoKey)
                                   /\ lastLsa' = lsa[p]
                                   /\ lastVpid' = p
                           ELSE /\ TRUE
                                /\ UNCHANGED << lastVpid, lastLsa, lastKey >>
                /\ pc' = [pc EXCEPT ![self] = "D_publish"]
                /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootX, wx, 
                                mutex, frontier, readCnt, fixFreed, stopped, 
                                held, cand, ops, l, r, rr, k, n >>

D_fix_next(self) == /\ pc[self] = "D_fix_next"
                    /\ SFree(current)
                    /\ IF ~inUse[current]
                          THEN /\ fixFreed' = TRUE
                          ELSE /\ TRUE
                               /\ UNCHANGED fixFreed
                    /\ /\ bound' = [bound EXCEPT ![self] = Inf]
                       /\ out' = [out EXCEPT ![self] = current]
                       /\ rd' = [rd EXCEPT ![current] = rd[current] \cup {self}]
                    /\ ended' = (nxt[current] = NoPage)
                    /\ current' = (IF nxt[current] = NoPage THEN current ELSE nxt[current])
                    /\ pc' = [pc EXCEPT ![self] = "D_publish"]
                    /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, 
                                    rootX, wx, mutex, descentDone, frontier, 
                                    lastVpid, lastLsa, lastKey, readCnt, 
                                    stopped, held, cand, ops, l, r, rr, k, n >>

D_fix_prev(self) == /\ pc[self] = "D_fix_prev"
                    /\ SFree(current)
                    /\ IF Mutant = "trust_prev_link"
                          \/ (inUse[current] /\ nxt[current] = lastVpid
                          
                              /\ (Fix = "check_last_lsa" => inUse[lastVpid] /\ lsa[lastVpid] = lastLsa))
                          THEN /\ fixFreed' = (fixFreed \/ ~inUse[current])
                               /\ /\ bound' = [bound EXCEPT ![self] = Inf]
                                  /\ out' = [out EXCEPT ![self] = current]
                                  /\ rd' = [rd EXCEPT ![current] = rd[current] \cup {self}]
                               /\ pc' = [pc EXCEPT ![self] = "D_desc_take"]
                               /\ UNCHANGED << descentDone, cand >>
                          ELSE /\ IF lastKey = NoKey
                                     THEN /\ descentDone' = FALSE
                                          /\ pc' = [pc EXCEPT ![self] = "D_root"]
                                          /\ cand' = cand
                                     ELSE /\ IF inUse[lastVpid] /\ lsa[lastVpid] = lastLsa
                                                THEN /\ cand' = [cand EXCEPT ![self] = lastVpid]
                                                     /\ pc' = [pc EXCEPT ![self] = "D_saved"]
                                                ELSE /\ pc' = [pc EXCEPT ![self] = "D_reroot"]
                                                     /\ cand' = cand
                                          /\ UNCHANGED descentDone
                               /\ UNCHANGED << rd, fixFreed, out, bound >>
                    /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, 
                                    rootX, wx, mutex, ended, current, frontier, 
                                    lastVpid, lastLsa, lastKey, readCnt, 
                                    stopped, held, ops, l, r, rr, k, n >>

D_saved(self) == /\ pc[self] = "D_saved"
                 /\ SFree(cand[self])
                 /\ IF inUse[cand[self]] /\ lsa[cand[self]] = lastLsa
                       THEN /\ IF prv[cand[self]] = NoPage
                                  THEN /\ ended' = TRUE
                                       /\ UNCHANGED current
                                  ELSE /\ current' = prv[cand[self]]
                                       /\ ended' = ended
                            /\ pc' = [pc EXCEPT ![self] = "W_retry"]
                       ELSE /\ pc' = [pc EXCEPT ![self] = "D_reroot"]
                            /\ UNCHANGED << ended, current >>
                 /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                 rd, wx, mutex, descentDone, frontier, 
                                 lastVpid, lastLsa, lastKey, readCnt, fixFreed, 
                                 stopped, held, out, bound, cand, ops, l, r, 
                                 rr, k, n >>

D_reroot(self) == /\ pc[self] = "D_reroot"
                  /\ ~rootX
                  /\ rootS' = (rootS \cup {self})
                  /\ pc' = [pc EXCEPT ![self] = "D_reroot_leaf"]
                  /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootX, rd, 
                                  wx, mutex, descentDone, ended, current, 
                                  frontier, lastVpid, lastLsa, lastKey, 
                                  readCnt, fixFreed, stopped, held, out, bound, 
                                  cand, ops, l, r, rr, k, n >>

D_reroot_leaf(self) == /\ pc[self] = "D_reroot_leaf"
                       /\ LET p == LeafFor(lastKey) IN
                            /\ SFree(p)
                            /\ rootS' = rootS \ {self}
                            /\ IF \E key \in keys[p] : key < lastKey
                                  THEN /\ /\ bound' = [bound EXCEPT ![self] = lastKey]
                                          /\ out' = [out EXCEPT ![self] = p]
                                          /\ rd' = [rd EXCEPT ![p] = rd[p] \cup {self}]
                                       /\ pc' = [pc EXCEPT ![self] = "D_desc_take"]
                                       /\ UNCHANGED << ended, current, 
                                                       lastVpid, lastLsa >>
                                  ELSE /\ /\ lastLsa' = lsa[p]
                                          /\ lastVpid' = p
                                       /\ IF prv[p] = NoPage
                                             THEN /\ ended' = TRUE
                                                  /\ UNCHANGED current
                                             ELSE /\ current' = prv[p]
                                                  /\ ended' = ended
                                       /\ pc' = [pc EXCEPT ![self] = "W_retry"]
                                       /\ UNCHANGED << rd, out, bound >>
                       /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootX, 
                                       wx, mutex, descentDone, frontier, 
                                       lastKey, readCnt, fixFreed, stopped, 
                                       held, cand, ops, l, r, rr, k, n >>

W_retry(self) == /\ pc[self] = "W_retry"
                 /\ IF ended
                       THEN /\ mutex' = NoPage
                            /\ pc' = [pc EXCEPT ![self] = "W_end"]
                       ELSE /\ pc' = [pc EXCEPT ![self] = "D_fix_prev"]
                            /\ mutex' = mutex
                 /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                 rd, wx, descentDone, ended, current, frontier, 
                                 lastVpid, lastLsa, lastKey, readCnt, fixFreed, 
                                 stopped, held, out, bound, cand, ops, l, r, 
                                 rr, k, n >>

D_desc_take(self) == /\ pc[self] = "D_desc_take"
                     /\ IF prv[out[self]] = NoPage
                           THEN /\ ended' = TRUE
                                /\ UNCHANGED current
                           ELSE /\ current' = prv[out[self]]
                                /\ ended' = ended
                     /\ /\ lastKey' = (IF keys[out[self]] # {} THEN MinKey(keys[out[self]]) ELSE lastKey)
                        /\ lastLsa' = lsa[out[self]]
                        /\ lastVpid' = out[self]
                     /\ pc' = [pc EXCEPT ![self] = "D_publish"]
                     /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, 
                                     rootX, rd, wx, mutex, descentDone, 
                                     frontier, readCnt, fixFreed, stopped, 
                                     held, out, bound, cand, ops, l, r, rr, k, 
                                     n >>

D_publish(self) == /\ pc[self] = "D_publish"
                   /\ frontier' = (IF ~Desc /\ ~ended THEN out[self] ELSE NoPage)
                   /\ mutex' = NoPage
                   /\ rd' = (IF held[self] # NoPage THEN [rd EXCEPT ![held[self]] = @ \ {self}] ELSE rd)
                   /\ /\ held' = [held EXCEPT ![self] = out[self]]
                      /\ out' = [out EXCEPT ![self] = NoPage]
                   /\ pc' = [pc EXCEPT ![self] = "W_read"]
                   /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, 
                                   rootX, wx, descentDone, ended, current, 
                                   lastVpid, lastLsa, lastKey, readCnt, 
                                   fixFreed, stopped, bound, cand, ops, l, r, 
                                   rr, k, n >>

W_read(self) == /\ pc[self] = "W_read"
                /\ readCnt' = [key \in Keys |-> IF key \in keys[held[self]] /\ key < bound[self] THEN readCnt[key] + 1 ELSE readCnt[key]]
                /\ pc' = [pc EXCEPT ![self] = "W_ask"]
                /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                rd, wx, mutex, descentDone, ended, current, 
                                frontier, lastVpid, lastLsa, lastKey, fixFreed, 
                                stopped, held, out, bound, cand, ops, l, r, rr, 
                                k, n >>

W_stop(self) == /\ pc[self] = "W_stop"
                /\ IF held[self] = frontier /\ Mutant # "stop_keeps_chain"
                      THEN /\ mutex = NoPage
                           /\ ended' = TRUE
                           /\ frontier' = NoPage
                      ELSE /\ TRUE
                           /\ UNCHANGED << ended, frontier >>
                /\ /\ held' = [held EXCEPT ![self] = NoPage]
                   /\ rd' = [rd EXCEPT ![held[self]] = rd[held[self]] \ {self}]
                /\ stopped' = TRUE
                /\ pc' = [pc EXCEPT ![self] = "W_end"]
                /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                wx, mutex, descentDone, current, lastVpid, 
                                lastLsa, lastKey, readCnt, fixFreed, out, 
                                bound, cand, ops, l, r, rr, k, n >>

W_end(self) == /\ pc[self] = "W_end"
               /\ IF held[self] # NoPage
                     THEN /\ /\ held' = [held EXCEPT ![self] = NoPage]
                             /\ rd' = [rd EXCEPT ![held[self]] = rd[held[self]] \ {self}]
                     ELSE /\ TRUE
                          /\ UNCHANGED << rd, held >>
               /\ pc' = [pc EXCEPT ![self] = "Done"]
               /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                               wx, mutex, descentDone, ended, current, 
                               frontier, lastVpid, lastLsa, lastKey, readCnt, 
                               fixFreed, stopped, out, bound, cand, ops, l, r, 
                               rr, k, n >>

worker(self) == W_start(self) \/ W_ask(self) \/ W_lock(self)
                   \/ W_dispatch(self) \/ D_root(self) \/ D_leaf(self)
                   \/ D_fix_next(self) \/ D_fix_prev(self) \/ D_saved(self)
                   \/ D_reroot(self) \/ D_reroot_leaf(self)
                   \/ W_retry(self) \/ D_desc_take(self) \/ D_publish(self)
                   \/ W_read(self) \/ W_stop(self) \/ W_end(self)

X_loop == /\ pc[Writer] = "X_loop"
          /\ IF ops > 0
                THEN /\ ops' = ops - 1
                     /\ \/ /\ \E key \in {c \in Churn : \A p \in Chain : c \notin keys[p]}:
                                /\ ~rootX /\ rootS = {}
                                /\ /\ k' = key
                                   /\ rootX' = TRUE
                           /\ pc' = [pc EXCEPT ![Writer] = "X_ins_leaf"]
                        \/ /\ \E key \in {c \in Churn : \E p \in Chain : c \in keys[p]}:
                                /\ ~rootX /\ rootS = {}
                                /\ /\ k' = key
                                   /\ rootX' = TRUE
                           /\ pc' = [pc EXCEPT ![Writer] = "X_del_leaf"]
                ELSE /\ pc' = [pc EXCEPT ![Writer] = "Done"]
                     /\ UNCHANGED << rootX, ops, k >>
          /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rd, wx, mutex, 
                          descentDone, ended, current, frontier, lastVpid, 
                          lastLsa, lastKey, readCnt, fixFreed, stopped, held, 
                          out, bound, cand, l, r, rr, n >>

X_ins_leaf == /\ pc[Writer] = "X_ins_leaf"
              /\ LET leaf == LeafFor(k) IN
                   /\ XFree(leaf)
                   /\ IF Cardinality(keys[leaf]) < Cap
                         THEN /\ /\ keys' = [keys EXCEPT ![leaf] = keys[leaf] \cup {k}]
                                 /\ lsa' = [lsa EXCEPT ![leaf] = lsa[leaf] + 1]
                              /\ rootX' = FALSE
                              /\ pc' = [pc EXCEPT ![Writer] = "X_loop"]
                              /\ UNCHANGED << wx, l >>
                         ELSE /\ IF \A p \in Pages : inUse[p]
                                    THEN /\ rootX' = FALSE
                                         /\ pc' = [pc EXCEPT ![Writer] = "X_loop"]
                                         /\ UNCHANGED << wx, l >>
                                    ELSE /\ l' = leaf
                                         /\ wx' = (wx \cup {leaf})
                                         /\ pc' = [pc EXCEPT ![Writer] = "X_split_alloc"]
                                         /\ rootX' = rootX
                              /\ UNCHANGED << keys, lsa >>
              /\ UNCHANGED << inUse, lo, nxt, prv, rootS, rd, mutex, 
                              descentDone, ended, current, frontier, lastVpid, 
                              lastLsa, lastKey, readCnt, fixFreed, stopped, 
                              held, out, bound, cand, ops, r, rr, k, n >>

X_split_alloc == /\ pc[Writer] = "X_split_alloc"
                 /\ \E fresh \in {p \in Pages : ~inUse[p]}:
                      n' = fresh
                 /\ r' = nxt[l]
                 /\ pc' = [pc EXCEPT ![Writer] = "X_split_right"]
                 /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                 rd, wx, mutex, descentDone, ended, current, 
                                 frontier, lastVpid, lastLsa, lastKey, readCnt, 
                                 fixFreed, stopped, held, out, bound, cand, 
                                 ops, l, rr, k >>

X_split_right == /\ pc[Writer] = "X_split_right"
                 /\ IF r # NoPage
                       THEN /\ XFree(r)
                            /\ wx' = (wx \cup {r})
                       ELSE /\ TRUE
                            /\ wx' = wx
                 /\ pc' = [pc EXCEPT ![Writer] = "X_split_apply"]
                 /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                 rd, mutex, descentDone, ended, current, 
                                 frontier, lastVpid, lastLsa, lastKey, readCnt, 
                                 fixFreed, stopped, held, out, bound, cand, 
                                 ops, l, r, rr, k, n >>

X_split_apply == /\ pc[Writer] = "X_split_apply"
                 /\ LET all == keys[l] \cup {k} IN
                      /\ keys' = [keys EXCEPT ![l] = all \ {MaxKey(all)}, ![n] = {MaxKey(all)}]
                      /\ lo' = [lo EXCEPT ![n] = MaxKey(all)]
                 /\ inUse' = [inUse EXCEPT ![n] = TRUE]
                 /\ nxt' = [nxt EXCEPT ![l] = n, ![n] = r]
                 /\ prv' = [p \in Pages |-> IF p = n THEN l ELSE IF p = r THEN n ELSE prv[p]]
                 /\ lsa' = [p \in Pages |-> IF p \in {l, n, r} THEN lsa[p] + 1 ELSE lsa[p]]
                 /\ /\ l' = NoPage
                    /\ n' = NoPage
                    /\ r' = NoPage
                    /\ rootX' = FALSE
                    /\ wx' = {}
                 /\ pc' = [pc EXCEPT ![Writer] = "X_loop"]
                 /\ UNCHANGED << rootS, rd, mutex, descentDone, ended, current, 
                                 frontier, lastVpid, lastLsa, lastKey, readCnt, 
                                 fixFreed, stopped, held, out, bound, cand, 
                                 ops, rr, k >>

X_del_leaf == /\ pc[Writer] = "X_del_leaf"
              /\ LET leaf == LeafFor(k) IN
                   /\ IF Mutant = "merge_right_first"
                         THEN /\ XFree(leaf)
                              /\ wx' = (wx \cup {leaf})
                         ELSE /\ TRUE
                              /\ wx' = wx
                   /\ r' = leaf
              /\ pc' = [pc EXCEPT ![Writer] = "X_del_left"]
              /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, rd, 
                              mutex, descentDone, ended, current, frontier, 
                              lastVpid, lastLsa, lastKey, readCnt, fixFreed, 
                              stopped, held, out, bound, cand, ops, l, rr, k, 
                              n >>

X_del_left == /\ pc[Writer] = "X_del_left"
              /\ LET left == prv[r] IN
                   IF Cardinality(keys[r]) = 1 /\ left # NoPage
                      THEN /\ XFree(left)
                           /\ wx' = (wx \cup {left})
                           /\ l' = left
                      ELSE /\ l' = NoPage
                           /\ wx' = wx
              /\ pc' = [pc EXCEPT ![Writer] = "X_del_right"]
              /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, rd, 
                              mutex, descentDone, ended, current, frontier, 
                              lastVpid, lastLsa, lastKey, readCnt, fixFreed, 
                              stopped, held, out, bound, cand, ops, r, rr, k, 
                              n >>

X_del_right == /\ pc[Writer] = "X_del_right"
               /\ IF r \notin wx
                     THEN /\ XFree(r)
                          /\ wx' = (wx \cup {r})
                     ELSE /\ TRUE
                          /\ wx' = wx
               /\ rr' = (IF l # NoPage THEN nxt[r] ELSE NoPage)
               /\ pc' = [pc EXCEPT ![Writer] = "X_del_rr"]
               /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                               rd, mutex, descentDone, ended, current, 
                               frontier, lastVpid, lastLsa, lastKey, readCnt, 
                               fixFreed, stopped, held, out, bound, cand, ops, 
                               l, r, k, n >>

X_del_rr == /\ pc[Writer] = "X_del_rr"
            /\ IF rr # NoPage
                  THEN /\ XFree(rr)
                       /\ wx' = (wx \cup {rr})
                  ELSE /\ TRUE
                       /\ wx' = wx
            /\ pc' = [pc EXCEPT ![Writer] = "X_del_apply"]
            /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, rd, 
                            mutex, descentDone, ended, current, frontier, 
                            lastVpid, lastLsa, lastKey, readCnt, fixFreed, 
                            stopped, held, out, bound, cand, ops, l, r, rr, k, 
                            n >>

X_del_apply == /\ pc[Writer] = "X_del_apply"
               /\ keys' = [keys EXCEPT ![r] = keys[r] \ {k}]
               /\ IF l # NoPage
                     THEN /\ inUse' = [inUse EXCEPT ![r] = FALSE]
                          /\ nxt' = [nxt EXCEPT ![l] = rr, ![r] = NoPage]
                          /\ prv' = [p \in Pages |-> IF p = rr THEN l ELSE IF p = r THEN NoPage ELSE prv[p]]
                          /\ lsa' = [p \in Pages |-> IF p \in {l, r, rr} THEN lsa[p] + 1 ELSE lsa[p]]
                     ELSE /\ lsa' = [lsa EXCEPT ![r] = lsa[r] + 1]
                          /\ UNCHANGED << inUse, nxt, prv >>
               /\ /\ l' = NoPage
                  /\ r' = NoPage
                  /\ rootX' = FALSE
                  /\ rr' = NoPage
                  /\ wx' = {}
               /\ pc' = [pc EXCEPT ![Writer] = "X_loop"]
               /\ UNCHANGED << lo, rootS, rd, mutex, descentDone, ended, 
                               current, frontier, lastVpid, lastLsa, lastKey, 
                               readCnt, fixFreed, stopped, held, out, bound, 
                               cand, ops, k, n >>

writer == X_loop \/ X_ins_leaf \/ X_split_alloc \/ X_split_right
             \/ X_split_apply \/ X_del_leaf \/ X_del_left \/ X_del_right
             \/ X_del_rr \/ X_del_apply

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == /\ \A self \in ProcSet: pc[self] = "Done"
               /\ UNCHANGED vars

Next == writer
           \/ (\E self \in Workers: worker(self))
           \/ Terminating

Spec == /\ Init /\ [][Next]_vars
        /\ \A self \in Workers : WF_vars(worker(self))
        /\ WF_vars(writer)

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION

\* ---- refinement of PxIndexFrontier (ascending) ----
\* Between fixing a leaf and publishing it, the dispatching worker's out is the new frontier.
Publishing == {w \in Workers : pc[w] = "D_publish"}
AbsFrontier == IF ended THEN NoPage
               ELSE IF Publishing # {} THEN out[CHOOSE w \in Publishing : TRUE]
               ELSE frontier
AbsCurrent == IF ~descentDone \/ ended THEN NoPage ELSE current
AbsProtected == AbsFrontier # NoPage => rd[AbsFrontier] # {}
AbsMutant == IF Mutant = "release_frontier" THEN Mutant ELSE "none"
Frontier == INSTANCE PxIndexFrontier
              WITH Leaves <- Pages, Mutant <- AbsMutant, started <- descentDone,
                   frontier <- AbsFrontier, current <- AbsCurrent, protected <- AbsProtected
FrontierSpec == Frontier!FSpec
=============================================================================
