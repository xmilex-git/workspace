-------------------------- MODULE DescLeafDispatch --------------------------
(* CBRD-27968: the descending parallel index scan dispatcher (develop b3feda176,
   px_scan_index_leaf_page_dispatcher.cpp) against concurrent B-tree splits,
   vacuum merges and page reuse.

   The dispatcher hands out leaves right to left under its mutex. It remembers
   the last leaf handed out (VPID, LSA, smallest key) and next fixes that leaf's
   left link L. fix_prev_leaf keeps L while L's right link still names the last
   leaf C; otherwise resume_after_last_key relocates the smallest key handed out
   (from the saved leaf, else from the root). The VPID comparison cannot tell C
   from a page reused after C was merged away and freed (H2); Fix chooses how the
   dispatcher proves that C is still the leaf it handed out.

   The tree is one root over a chain of leaves; leaf p covers keys >= lo[p] up to
   the next leaf's lo. Writers latch top-down and left to right: root, the leaf,
   then its right neighbour (btree_split_node_and_advance,
   btree_merge_node_and_advance). A split moves the upper key of a full leaf to a
   new right leaf; a merge moves an emptied right leaf's range into its left leaf
   and deallocates it; a freed page may be reused by the next split. Every page
   change is logged, so it advances that page's LSA (lsa), and a reused page is
   re-initialised by a logged RVBT_COPYPAGE (btree_split_node). *)
EXTENDS Naturals, FiniteSets

CONSTANTS Workers, Writer, Mutant, Fix, WriterOps, Cap, EarlyStop, Layout
ASSUME Assm ==
  /\ Workers # {} /\ Writer \notin Workers /\ WriterOps \in Nat /\ Cap \in Nat \ {0}
  \* "tight": each leaf's lower bound is its smallest key; "gap": the middle leaf's lower bound lies below its key (a key
  \* inserted there after the hand-out lands below the last key in the same leaf) and the leftmost leaf holds only a
  \* churn key (it can empty, and a merge into it can leave nothing below the last key)
  /\ Layout \in {"tight", "gap"}
  /\ EarlyStop \in BOOLEAN              \* a worker may stop early (LIMIT reached, error): release_leaf
  \* "none": the code at b3feda176 (VPID only); "lsa_held": with L held, fix C unconditionally and
  \* compare its LSA; "lsa_cond": the same with a conditional latch on C, a failed latch counting as changed
  \* "lsa_cond_root": the same, but a failed latch relocates the last key from the root, skipping the saved leaf
  /\ Fix \in {"none", "lsa_held", "lsa_cond", "lsa_cond_root"}
  /\ Mutant \in {"none", "trust_prev_link", "merge_right_first", "check_unheld", "check_right_first"}

Pages == 1..4
NoPage == 0
Keys == 1..5
Stable == IF Layout = "gap" THEN {4} ELSE {2, 4}   \* keys present for the whole scan
Churn == Keys \ Stable                             \* keys writers insert and delete
NoKey == 0
Inf == 99

(* --algorithm DescLeafDispatch
variables
  inUse = [p \in Pages |-> p \in {1, 2, 3}],
  keys = [p \in Pages |-> CASE p = 1 -> IF Layout = "gap" THEN {1} ELSE {2} [] p = 2 -> {3} [] p = 3 -> {4}
                              [] OTHER -> {}],
  lo = [p \in Pages |-> CASE p = 1 -> 0 [] p = 2 -> IF Layout = "gap" THEN 2 ELSE 3 [] p = 3 -> 4 [] OTHER -> 0],
  nxt = [p \in Pages |-> CASE p = 1 -> 2 [] p = 2 -> 3 [] OTHER -> NoPage],
  prv = [p \in Pages |-> CASE p = 2 -> 1 [] p = 3 -> 2 [] OTHER -> NoPage],
  lsa = [p \in Pages |-> 1],
  \* latches
  rootS = {}, rootX = FALSE, rootW = FALSE,   \* rootW: a writer waits to X-latch the root
  rd = [p \in Pages |-> {}], wx = {},
  xw = {},                        \* pages a writer waits to X-latch (waiter_exists): new readers queue behind it
  \* dispatcher (m_leaf_mutex and what it protects)
  mutex = NoPage,                 \* holder: a worker or NoPage
  descentDone = FALSE, ended = FALSE, current = NoPage,
  lastVpid = NoPage, lastLsa = 0, lastKey = NoKey,
  \* ghosts
  gen = [p \in Pages |-> IF p \in {1, 2, 3} THEN 1 ELSE 0],   \* allocations of each page
  lastGen = 0,
  readCnt = [x \in Keys |-> 0],
  fixFreed = FALSE,
  stopped = FALSE,
  reuseCaught = FALSE,            \* the check refused a reused last leaf that L links to
  benignReject = FALSE,           \* the check refused a last leaf changed in place (cost only)
  \* refinement ghosts (DescScan): stable keys handed out, the last key handed out, the end seen by a worker
  handedW = {}, absCpos = 0, seenEnd = FALSE;

define
  Chain == {p \in Pages : inUse[p]}
  Last == CHOOSE p \in Chain : nxt[p] = NoPage
  LeafFor(x) == CHOOSE p \in Chain : lo[p] <= x /\ (nxt[p] = NoPage \/ lo[nxt[p]] > x)
  MinKey(S) == CHOOSE x \in S : \A j \in S : x <= j
  MaxKey(S) == CHOOSE x \in S : \A j \in S : x >= j
  XFree(p) == rd[p] = {} /\ p \notin wx
  SFree(p) == p \notin wx /\ p \notin xw     \* pgbuf_latch_bcb_upon_fix: a READ request waits behind a waiter
  LastUnchanged == inUse[lastVpid] /\ lsa[lastVpid] = lastLsa
  \* the key a hand-out of leaf o, read below b, returns (a leaf holds at most Cap = 1 key)
  OutKey(o, b) == IF \E x \in keys[o] : x < b THEN MaxKey({x \in keys[o] : x < b}) ELSE NoKey
  TypeOK == /\ inUse \in [Pages -> BOOLEAN] /\ keys \in [Pages -> SUBSET Keys]
            /\ nxt \in [Pages -> Pages \cup {NoPage}] /\ prv \in [Pages -> Pages \cup {NoPage}]
            /\ rd \in [Pages -> SUBSET Workers] /\ wx \subseteq Pages
            /\ readCnt \in [Keys -> Nat]
  AllDone == \A w \in Workers : pc[w] = "Done"
  \* C1: every key present for the whole scan is returned exactly once.
  StableOnce == AllDone /\ ~stopped => \A x \in Stable : readCnt[x] = 1
  NoStableDuplicate == \A x \in Stable : readCnt[x] <= 1
  \* C3: no worker or the dispatcher fixes a deallocated leaf as a live one.
  NoFreedFix == ~fixFreed
  \* C2
  ScanFinishes == <>AllDone
  \* witnesses
  NotReuseCaught == ~reuseCaught
  NotBenignReject == ~benignReject
  \* the dispatcher, holding L and the mutex, must wait for C: a worker scans C and a writer queues for it
  NotStallOnLast == ~\E w \in Workers : pc[w] = "D_check_last" /\ lastVpid \in xw /\ rd[lastVpid] # {}
  \* the same wait when the dispatcher relocates the last key from the root: the leaf of the last key is C
  NotStallOnReroot == ~\E w \in Workers : pc[w] = "D_reroot_leaf" /\ LeafFor(lastKey) = lastVpid
                        /\ lastVpid \in xw /\ rd[lastVpid] # {}
  NotMergedDuringScan == ~(~AllDone /\ ~inUse[2] /\ \E w \in Workers : pc[w] # "W_start")
end define;

fair process worker \in Workers
variables held = NoPage, out = NoPage, bound = Inf, cand = NoPage, lastOk = TRUE, heldLast = FALSE,
          skipSaved = FALSE;
begin
  W_start:
    skip;
  W_ask:
    either
      await EarlyStop /\ held # NoPage;
      goto W_stop;
    or
      \* lock_holding: descending has no frontier, so the held leaf is released before waiting
      if held # NoPage then
        rd[held] := rd[held] \ {self} || held := NoPage;
      end if;
    end either;
  W_lock:
    await mutex = NoPage;
    mutex := self;
  W_dispatch:
    if ~descentDone then
      goto D_root;
    elsif ended then
      mutex := NoPage || seenEnd := TRUE;
      goto W_end;
    elsif Mutant = "check_unheld" then
      goto D_check_first;
    elsif Mutant = "check_right_first" then
      goto D_fix_last_first;
    else
      goto D_fix_prev;
    end if;
  D_root:
    await ~rootX /\ ~rootW;
    rootS := rootS \cup {self};
  D_leaf:
    \* descend_to_first_leaf, then save_last_leaf (new range)
    with p = Last do
      await SFree(p);
      rd[p] := rd[p] \cup {self} || out := p || rootS := rootS \ {self} || bound := Inf;
      current := prv[p];
      ended := prv[p] = NoPage;
      descentDone := TRUE;
      lastVpid := p || lastLsa := lsa[p] || lastGen := gen[p]
        || lastKey := IF keys[p] # {} THEN MinKey(keys[p]) ELSE NoKey;
    end with;
    goto D_publish;
  D_check_first:
    \* mutant: the last leaf's LSA is compared before L is fixed, no latch held across
    await SFree(lastVpid);
    lastOk := LastUnchanged;
    goto D_fix_prev;
  D_fix_last_first:
    \* mutant: the last leaf is fixed first and kept while L is fixed (right to left)
    await SFree(lastVpid);
    rd[lastVpid] := rd[lastVpid] \cup {self} || heldLast := TRUE;
    lastOk := LastUnchanged;
  D_fix_prev:
    \* fix_prev_leaf: OLD_PAGE_MAYBE_DEALLOCATED fix of the saved left link, kept only while it links back
    await SFree(current);
    if (Mutant = "trust_prev_link" \/ (inUse[current] /\ nxt[current] = lastVpid)) /\ lastOk then
      fixFreed := fixFreed \/ ~inUse[current];
      rd := [p \in Pages |-> IF p = current THEN rd[p] \cup {self}
                             ELSE IF heldLast /\ p = lastVpid THEN rd[p] \ {self} ELSE rd[p]];
      out := current || bound := Inf || heldLast := FALSE || lastOk := TRUE;
      if Fix # "none" /\ Mutant \in {"none", "merge_right_first"} then
        goto D_check_last;
      else
        goto D_desc_take;
      end if;
    else
      if heldLast then
        rd[lastVpid] := rd[lastVpid] \ {self} || heldLast := FALSE || lastOk := TRUE;
      else
        lastOk := TRUE;
      end if;
      goto D_resume;
    end if;
  D_check_last:
    \* the fix: with L still held, fix the last leaf (left to right), compare its LSA, unfix it
    if Fix \in {"lsa_cond", "lsa_cond_root"} /\ ~SFree(lastVpid) then
      \* PGBUF_CONDITIONAL_LATCH failed: counted as changed
      rd[out] := rd[out] \ {self} || out := NoPage || skipSaved := Fix = "lsa_cond_root";
      goto D_resume;
    else
      await SFree(lastVpid);
      if LastUnchanged then
        goto D_desc_take;
      else
        reuseCaught := reuseCaught \/ ~inUse[lastVpid] \/ gen[lastVpid] # lastGen;
        benignReject := benignReject \/ (inUse[lastVpid] /\ gen[lastVpid] = lastGen);
        rd[out] := rd[out] \ {self} || out := NoPage;
        goto D_resume;
      end if;
    end if;
  D_resume:
    \* resume_after_last_key
    if lastKey = NoKey then
      descentDone := FALSE || skipSaved := FALSE;   \* nothing handed out in this range yet: restart it
      goto D_root;
    elsif skipSaved then
      skipSaved := FALSE;
      goto D_reroot;
    else
      cand := lastVpid;
    end if;
  D_saved:
    \* btree_locate_key_from_saved_leaf: pgbuf_fix_if_not_deallocated of the saved leaf
    await SFree(cand);
    if inUse[cand] /\ lsa[cand] = lastLsa then
      \* unchanged: it was handed out whole; continue the chain from its left link
      if prv[cand] = NoPage then ended := TRUE else current := prv[cand] end if;
      goto W_retry;
    elsif inUse[cand] /\ \E a, b \in keys[cand] : a <= lastKey /\ lastKey <= b then
      \* changed but still holding the last key's place (BTREE_KEY_FOUND / BTREE_KEY_BETWEEN)
      if \E key \in keys[cand] : key < lastKey then
        rd[cand] := rd[cand] \cup {self} || out := cand || bound := lastKey;
        goto D_desc_take;
      else
        lastVpid := cand || lastLsa := lsa[cand] || lastGen := gen[cand];
        if prv[cand] = NoPage then ended := TRUE else current := prv[cand] end if;
        goto W_retry;
      end if;
    else
      goto D_reroot;
    end if;
  D_reroot:
    await ~rootX /\ ~rootW;
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
        lastVpid := p || lastLsa := lsa[p] || lastGen := gen[p];
        if prv[p] = NoPage then ended := TRUE else current := prv[p] end if;
        goto W_retry;
      end if;
    end with;
  W_retry:
    \* goto retry in dispatch_next_leaf, still under the mutex
    if ended then
      mutex := NoPage || seenEnd := TRUE;
      goto W_end;
    else
      goto D_fix_prev;
    end if;
  D_desc_take:
    \* save_last_leaf, then the next left link
    if prv[out] = NoPage then ended := TRUE else current := prv[out] end if;
    lastVpid := out || lastLsa := lsa[out] || lastGen := gen[out]
      || lastKey := IF keys[out] # {} THEN MinKey(keys[out]) ELSE lastKey;
  D_publish:
    mutex := NoPage;
    with y = OutKey(out, bound) do
      if y # NoKey then
        absCpos := y || handedW := handedW \cup ({y} \cap Stable);
      end if;
    end with;
    held := out || out := NoPage;
  W_read:
    readCnt := [key \in Keys |-> IF key \in keys[held] /\ key < bound THEN readCnt[key] + 1 ELSE readCnt[key]];
    goto W_ask;
  W_stop:
    \* release_leaf: descending has no frontier; the held leaf is released
    rd[held] := rd[held] \ {self} || held := NoPage;
    stopped := TRUE;
    goto W_end;
  W_end:
    if held # NoPage then rd[held] := rd[held] \ {self} || held := NoPage end if;
end process;

\* Vacuum and DML on the same index, at most WriterOps operations; fair: a split or merge it starts, it finishes.
\* A writer descends with a read latch on the root (nonleaf_latch_mode = PGBUF_LATCH_READ) and X-latches the leaf;
\* when the leaf needs a split or a merge it releases both and restarts from the root with write latches
\* (btree.c:32413, 32685, 35782: a failed promotion restarts the same way; a successful one is the restart without
\* the gap). A writer waiting for a latch is a waiter: new read requests queue behind it.
fair process writer = Writer
variables ops = WriterOps, l = NoPage, r = NoPage, rr = NoPage, k = NoKey, n = NoPage;
begin
  X_loop:
    while ops > 0 do
      ops := ops - 1;
      either
        \* insert a churn key; split its leaf when it is full
        with key \in {c \in Churn : \A p \in Chain : c \notin keys[p]} do
          await ~rootX /\ ~rootW;
          rootS := rootS \cup {Writer} || k := key;
        end with;
  X_ins_wait:
        l := LeafFor(k) || xw := xw \cup {LeafFor(k)};
  X_ins_leaf:
        await XFree(l);
        xw := xw \ {l};
        if Cardinality(keys[l]) < Cap then
          keys[l] := keys[l] \cup {k} || lsa[l] := lsa[l] + 1;
          rootS := rootS \ {Writer} || l := NoPage;
          goto X_loop;
        elsif \A p \in Pages : inUse[p] then
          \* the model's page pool is used up (file_alloc would extend the file): skip this insert
          rootS := rootS \ {Writer} || l := NoPage;
          goto X_loop;
        else
          \* a split: release, restart from the root with write latches
          rootS := rootS \ {Writer} || rootW := TRUE || l := NoPage;
        end if;
  X_ins_root:
        await rootS = {};
        rootX := TRUE || rootW := FALSE;
  X_ins_xwait:
        l := LeafFor(k) || xw := xw \cup {LeafFor(k)};
  X_ins_xleaf:
        await XFree(l);
        wx := wx \cup {l} || xw := xw \ {l};
  X_split_alloc:
        with fresh \in {p \in Pages : ~inUse[p]} do
          n := fresh;
        end with;
        r := nxt[l];
  X_split_rwait:
        if r # NoPage then xw := xw \cup {r} end if;
  X_split_right:
        if r # NoPage then
          await XFree(r);
          wx := wx \cup {r} || xw := xw \ {r};
        end if;
  X_split_apply:
        with all = keys[l] \cup {k} do
          \* the upper key moves to the new right leaf
          keys := [keys EXCEPT ![l] = all \ {MaxKey(all)}, ![n] = {MaxKey(all)}];
          lo := [lo EXCEPT ![n] = MaxKey(all)];
        end with;
        inUse[n] := TRUE;
        gen[n] := gen[n] + 1;
        nxt := [nxt EXCEPT ![l] = n, ![n] = r];
        prv := [p \in Pages |-> IF p = n THEN l ELSE IF p = r THEN n ELSE prv[p]];
        lsa := [p \in Pages |-> IF p \in {l, n, r} THEN lsa[p] + 1 ELSE lsa[p]];
        wx := {} || rootX := FALSE || l := NoPage || r := NoPage || n := NoPage;
      or
        \* vacuum: remove a dead churn key from its leaf; the leaf may empty (a later descent merges it)
        with key \in {c \in Churn : \E p \in Chain : c \in keys[p]} do
          await ~rootX /\ ~rootW;
          rootS := rootS \cup {Writer} || k := key;
        end with;
  X_del_wait:
        r := LeafFor(k) || xw := xw \cup {LeafFor(k)};
  X_del_leaf:
        await XFree(r);
        keys[r] := keys[r] \ {k} || lsa[r] := lsa[r] + 1;
        xw := xw \ {r} || rootS := rootS \ {Writer} || r := NoPage || k := NoKey;
        goto X_loop;
      or
        \* a descent into a leaf finds its right neighbour empty and merges it: restart with write latches
        \* (btree_merge_node_and_advance; a cold neighbour or a failed promotion skips the merge, so an empty leaf
        \* may stay in the chain)
        with e \in {p \in Chain : keys[p] = {} /\ prv[p] # NoPage} do
          await ~rootX /\ ~rootW;
          rootW := TRUE || r := e;
        end with;
  X_del_root:
        await rootS = {};
        rootX := TRUE || rootW := FALSE;
  X_del_mutant:
        if Mutant = "merge_right_first" then
          await XFree(r);
          wx := wx \cup {r};
        end if;
  X_del_lwait:
        \* merge: the left leaf first, then the emptied right leaf, then its right neighbour
        l := prv[r] || xw := xw \cup {prv[r]};
  X_del_left:
        await XFree(l);
        wx := wx \cup {l} || xw := xw \ {l};
  X_del_rwait:
        if r \notin wx then xw := xw \cup {r} end if;
  X_del_right:
        if r \notin wx then
          await XFree(r);
          wx := wx \cup {r} || xw := xw \ {r};
        end if;
        rr := nxt[r];
  X_del_rrwait:
        if rr # NoPage then xw := xw \cup {rr} end if;
  X_del_rr:
        if rr # NoPage then
          await XFree(rr);
          wx := wx \cup {rr} || xw := xw \ {rr};
        end if;
  X_del_apply:
        inUse[r] := FALSE;               \* file_dealloc
        nxt := [nxt EXCEPT ![l] = rr, ![r] = NoPage];
        prv := [p \in Pages |-> IF p = rr THEN l ELSE IF p = r THEN NoPage ELSE prv[p]];
        lsa := [p \in Pages |-> IF p \in {l, r, rr} THEN lsa[p] + 1 ELSE lsa[p]];
        wx := {} || rootX := FALSE || l := NoPage || r := NoPage || rr := NoPage;
      end either;
    end while;
end process;
end algorithm; *)
\* BEGIN TRANSLATION
VARIABLES inUse, keys, lo, nxt, prv, lsa, rootS, rootX, rootW, rd, wx, xw, 
          mutex, descentDone, ended, current, lastVpid, lastLsa, lastKey, gen, 
          lastGen, readCnt, fixFreed, stopped, reuseCaught, benignReject, 
          handedW, absCpos, seenEnd, pc

(* define statement *)
Chain == {p \in Pages : inUse[p]}
Last == CHOOSE p \in Chain : nxt[p] = NoPage
LeafFor(x) == CHOOSE p \in Chain : lo[p] <= x /\ (nxt[p] = NoPage \/ lo[nxt[p]] > x)
MinKey(S) == CHOOSE x \in S : \A j \in S : x <= j
MaxKey(S) == CHOOSE x \in S : \A j \in S : x >= j
XFree(p) == rd[p] = {} /\ p \notin wx
SFree(p) == p \notin wx /\ p \notin xw
LastUnchanged == inUse[lastVpid] /\ lsa[lastVpid] = lastLsa

OutKey(o, b) == IF \E x \in keys[o] : x < b THEN MaxKey({x \in keys[o] : x < b}) ELSE NoKey
TypeOK == /\ inUse \in [Pages -> BOOLEAN] /\ keys \in [Pages -> SUBSET Keys]
          /\ nxt \in [Pages -> Pages \cup {NoPage}] /\ prv \in [Pages -> Pages \cup {NoPage}]
          /\ rd \in [Pages -> SUBSET Workers] /\ wx \subseteq Pages
          /\ readCnt \in [Keys -> Nat]
AllDone == \A w \in Workers : pc[w] = "Done"

StableOnce == AllDone /\ ~stopped => \A x \in Stable : readCnt[x] = 1
NoStableDuplicate == \A x \in Stable : readCnt[x] <= 1

NoFreedFix == ~fixFreed

ScanFinishes == <>AllDone

NotReuseCaught == ~reuseCaught
NotBenignReject == ~benignReject

NotStallOnLast == ~\E w \in Workers : pc[w] = "D_check_last" /\ lastVpid \in xw /\ rd[lastVpid] # {}

NotStallOnReroot == ~\E w \in Workers : pc[w] = "D_reroot_leaf" /\ LeafFor(lastKey) = lastVpid
                      /\ lastVpid \in xw /\ rd[lastVpid] # {}
NotMergedDuringScan == ~(~AllDone /\ ~inUse[2] /\ \E w \in Workers : pc[w] # "W_start")

VARIABLES held, out, bound, cand, lastOk, heldLast, skipSaved, ops, l, r, rr, 
          k, n

vars == << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, rootW, rd, wx, xw, 
           mutex, descentDone, ended, current, lastVpid, lastLsa, lastKey, 
           gen, lastGen, readCnt, fixFreed, stopped, reuseCaught, 
           benignReject, handedW, absCpos, seenEnd, pc, held, out, bound, 
           cand, lastOk, heldLast, skipSaved, ops, l, r, rr, k, n >>

ProcSet == (Workers) \cup {Writer}

Init == (* Global variables *)
        /\ inUse = [p \in Pages |-> p \in {1, 2, 3}]
        /\ keys = [p \in Pages |-> CASE p = 1 -> IF Layout = "gap" THEN {1} ELSE {2} [] p = 2 -> {3} [] p = 3 -> {4}
                                       [] OTHER -> {}]
        /\ lo = [p \in Pages |-> CASE p = 1 -> 0 [] p = 2 -> IF Layout = "gap" THEN 2 ELSE 3 [] p = 3 -> 4 [] OTHER -> 0]
        /\ nxt = [p \in Pages |-> CASE p = 1 -> 2 [] p = 2 -> 3 [] OTHER -> NoPage]
        /\ prv = [p \in Pages |-> CASE p = 2 -> 1 [] p = 3 -> 2 [] OTHER -> NoPage]
        /\ lsa = [p \in Pages |-> 1]
        /\ rootS = {}
        /\ rootX = FALSE
        /\ rootW = FALSE
        /\ rd = [p \in Pages |-> {}]
        /\ wx = {}
        /\ xw = {}
        /\ mutex = NoPage
        /\ descentDone = FALSE
        /\ ended = FALSE
        /\ current = NoPage
        /\ lastVpid = NoPage
        /\ lastLsa = 0
        /\ lastKey = NoKey
        /\ gen = [p \in Pages |-> IF p \in {1, 2, 3} THEN 1 ELSE 0]
        /\ lastGen = 0
        /\ readCnt = [x \in Keys |-> 0]
        /\ fixFreed = FALSE
        /\ stopped = FALSE
        /\ reuseCaught = FALSE
        /\ benignReject = FALSE
        /\ handedW = {}
        /\ absCpos = 0
        /\ seenEnd = FALSE
        (* Process worker *)
        /\ held = [self \in Workers |-> NoPage]
        /\ out = [self \in Workers |-> NoPage]
        /\ bound = [self \in Workers |-> Inf]
        /\ cand = [self \in Workers |-> NoPage]
        /\ lastOk = [self \in Workers |-> TRUE]
        /\ heldLast = [self \in Workers |-> FALSE]
        /\ skipSaved = [self \in Workers |-> FALSE]
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
                                 rootW, rd, wx, xw, mutex, descentDone, ended, 
                                 current, lastVpid, lastLsa, lastKey, gen, 
                                 lastGen, readCnt, fixFreed, stopped, 
                                 reuseCaught, benignReject, handedW, absCpos, 
                                 seenEnd, held, out, bound, cand, lastOk, 
                                 heldLast, skipSaved, ops, l, r, rr, k, n >>

W_ask(self) == /\ pc[self] = "W_ask"
               /\ \/ /\ EarlyStop /\ held[self] # NoPage
                     /\ pc' = [pc EXCEPT ![self] = "W_stop"]
                     /\ UNCHANGED <<rd, held>>
                  \/ /\ IF held[self] # NoPage
                           THEN /\ /\ held' = [held EXCEPT ![self] = NoPage]
                                   /\ rd' = [rd EXCEPT ![held[self]] = rd[held[self]] \ {self}]
                           ELSE /\ TRUE
                                /\ UNCHANGED << rd, held >>
                     /\ pc' = [pc EXCEPT ![self] = "W_lock"]
               /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                               rootW, wx, xw, mutex, descentDone, ended, 
                               current, lastVpid, lastLsa, lastKey, gen, 
                               lastGen, readCnt, fixFreed, stopped, 
                               reuseCaught, benignReject, handedW, absCpos, 
                               seenEnd, out, bound, cand, lastOk, heldLast, 
                               skipSaved, ops, l, r, rr, k, n >>

W_lock(self) == /\ pc[self] = "W_lock"
                /\ mutex = NoPage
                /\ mutex' = self
                /\ pc' = [pc EXCEPT ![self] = "W_dispatch"]
                /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                rootW, rd, wx, xw, descentDone, ended, current, 
                                lastVpid, lastLsa, lastKey, gen, lastGen, 
                                readCnt, fixFreed, stopped, reuseCaught, 
                                benignReject, handedW, absCpos, seenEnd, held, 
                                out, bound, cand, lastOk, heldLast, skipSaved, 
                                ops, l, r, rr, k, n >>

W_dispatch(self) == /\ pc[self] = "W_dispatch"
                    /\ IF ~descentDone
                          THEN /\ pc' = [pc EXCEPT ![self] = "D_root"]
                               /\ UNCHANGED << mutex, seenEnd >>
                          ELSE /\ IF ended
                                     THEN /\ /\ mutex' = NoPage
                                             /\ seenEnd' = TRUE
                                          /\ pc' = [pc EXCEPT ![self] = "W_end"]
                                     ELSE /\ IF Mutant = "check_unheld"
                                                THEN /\ pc' = [pc EXCEPT ![self] = "D_check_first"]
                                                ELSE /\ IF Mutant = "check_right_first"
                                                           THEN /\ pc' = [pc EXCEPT ![self] = "D_fix_last_first"]
                                                           ELSE /\ pc' = [pc EXCEPT ![self] = "D_fix_prev"]
                                          /\ UNCHANGED << mutex, seenEnd >>
                    /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, 
                                    rootX, rootW, rd, wx, xw, descentDone, 
                                    ended, current, lastVpid, lastLsa, lastKey, 
                                    gen, lastGen, readCnt, fixFreed, stopped, 
                                    reuseCaught, benignReject, handedW, 
                                    absCpos, held, out, bound, cand, lastOk, 
                                    heldLast, skipSaved, ops, l, r, rr, k, n >>

D_root(self) == /\ pc[self] = "D_root"
                /\ ~rootX /\ ~rootW
                /\ rootS' = (rootS \cup {self})
                /\ pc' = [pc EXCEPT ![self] = "D_leaf"]
                /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootX, rootW, 
                                rd, wx, xw, mutex, descentDone, ended, current, 
                                lastVpid, lastLsa, lastKey, gen, lastGen, 
                                readCnt, fixFreed, stopped, reuseCaught, 
                                benignReject, handedW, absCpos, seenEnd, held, 
                                out, bound, cand, lastOk, heldLast, skipSaved, 
                                ops, l, r, rr, k, n >>

D_leaf(self) == /\ pc[self] = "D_leaf"
                /\ LET p == Last IN
                     /\ SFree(p)
                     /\ /\ bound' = [bound EXCEPT ![self] = Inf]
                        /\ out' = [out EXCEPT ![self] = p]
                        /\ rd' = [rd EXCEPT ![p] = rd[p] \cup {self}]
                        /\ rootS' = rootS \ {self}
                     /\ current' = prv[p]
                     /\ ended' = (prv[p] = NoPage)
                     /\ descentDone' = TRUE
                     /\ /\ lastGen' = gen[p]
                        /\ lastKey' = (IF keys[p] # {} THEN MinKey(keys[p]) ELSE NoKey)
                        /\ lastLsa' = lsa[p]
                        /\ lastVpid' = p
                /\ pc' = [pc EXCEPT ![self] = "D_publish"]
                /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootX, rootW, 
                                wx, xw, mutex, gen, readCnt, fixFreed, stopped, 
                                reuseCaught, benignReject, handedW, absCpos, 
                                seenEnd, held, cand, lastOk, heldLast, 
                                skipSaved, ops, l, r, rr, k, n >>

D_check_first(self) == /\ pc[self] = "D_check_first"
                       /\ SFree(lastVpid)
                       /\ lastOk' = [lastOk EXCEPT ![self] = LastUnchanged]
                       /\ pc' = [pc EXCEPT ![self] = "D_fix_prev"]
                       /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, 
                                       rootX, rootW, rd, wx, xw, mutex, 
                                       descentDone, ended, current, lastVpid, 
                                       lastLsa, lastKey, gen, lastGen, readCnt, 
                                       fixFreed, stopped, reuseCaught, 
                                       benignReject, handedW, absCpos, seenEnd, 
                                       held, out, bound, cand, heldLast, 
                                       skipSaved, ops, l, r, rr, k, n >>

D_fix_last_first(self) == /\ pc[self] = "D_fix_last_first"
                          /\ SFree(lastVpid)
                          /\ /\ heldLast' = [heldLast EXCEPT ![self] = TRUE]
                             /\ rd' = [rd EXCEPT ![lastVpid] = rd[lastVpid] \cup {self}]
                          /\ lastOk' = [lastOk EXCEPT ![self] = LastUnchanged]
                          /\ pc' = [pc EXCEPT ![self] = "D_fix_prev"]
                          /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, 
                                          rootS, rootX, rootW, wx, xw, mutex, 
                                          descentDone, ended, current, 
                                          lastVpid, lastLsa, lastKey, gen, 
                                          lastGen, readCnt, fixFreed, stopped, 
                                          reuseCaught, benignReject, handedW, 
                                          absCpos, seenEnd, held, out, bound, 
                                          cand, skipSaved, ops, l, r, rr, k, n >>

D_fix_prev(self) == /\ pc[self] = "D_fix_prev"
                    /\ SFree(current)
                    /\ IF (Mutant = "trust_prev_link" \/ (inUse[current] /\ nxt[current] = lastVpid)) /\ lastOk[self]
                          THEN /\ fixFreed' = (fixFreed \/ ~inUse[current])
                               /\ rd' = [p \in Pages |-> IF p = current THEN rd[p] \cup {self}
                                                         ELSE IF heldLast[self] /\ p = lastVpid THEN rd[p] \ {self} ELSE rd[p]]
                               /\ /\ bound' = [bound EXCEPT ![self] = Inf]
                                  /\ heldLast' = [heldLast EXCEPT ![self] = FALSE]
                                  /\ lastOk' = [lastOk EXCEPT ![self] = TRUE]
                                  /\ out' = [out EXCEPT ![self] = current]
                               /\ IF Fix # "none" /\ Mutant \in {"none", "merge_right_first"}
                                     THEN /\ pc' = [pc EXCEPT ![self] = "D_check_last"]
                                     ELSE /\ pc' = [pc EXCEPT ![self] = "D_desc_take"]
                          ELSE /\ IF heldLast[self]
                                     THEN /\ /\ heldLast' = [heldLast EXCEPT ![self] = FALSE]
                                             /\ lastOk' = [lastOk EXCEPT ![self] = TRUE]
                                             /\ rd' = [rd EXCEPT ![lastVpid] = rd[lastVpid] \ {self}]
                                     ELSE /\ lastOk' = [lastOk EXCEPT ![self] = TRUE]
                                          /\ UNCHANGED << rd, heldLast >>
                               /\ pc' = [pc EXCEPT ![self] = "D_resume"]
                               /\ UNCHANGED << fixFreed, out, bound >>
                    /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, 
                                    rootX, rootW, wx, xw, mutex, descentDone, 
                                    ended, current, lastVpid, lastLsa, lastKey, 
                                    gen, lastGen, readCnt, stopped, 
                                    reuseCaught, benignReject, handedW, 
                                    absCpos, seenEnd, held, cand, skipSaved, 
                                    ops, l, r, rr, k, n >>

D_check_last(self) == /\ pc[self] = "D_check_last"
                      /\ IF Fix \in {"lsa_cond", "lsa_cond_root"} /\ ~SFree(lastVpid)
                            THEN /\ /\ out' = [out EXCEPT ![self] = NoPage]
                                    /\ rd' = [rd EXCEPT ![out[self]] = rd[out[self]] \ {self}]
                                    /\ skipSaved' = [skipSaved EXCEPT ![self] = Fix = "lsa_cond_root"]
                                 /\ pc' = [pc EXCEPT ![self] = "D_resume"]
                                 /\ UNCHANGED << reuseCaught, benignReject >>
                            ELSE /\ SFree(lastVpid)
                                 /\ IF LastUnchanged
                                       THEN /\ pc' = [pc EXCEPT ![self] = "D_desc_take"]
                                            /\ UNCHANGED << rd, reuseCaught, 
                                                            benignReject, out >>
                                       ELSE /\ reuseCaught' = (reuseCaught \/ ~inUse[lastVpid] \/ gen[lastVpid] # lastGen)
                                            /\ benignReject' = (benignReject \/ (inUse[lastVpid] /\ gen[lastVpid] = lastGen))
                                            /\ /\ out' = [out EXCEPT ![self] = NoPage]
                                               /\ rd' = [rd EXCEPT ![out[self]] = rd[out[self]] \ {self}]
                                            /\ pc' = [pc EXCEPT ![self] = "D_resume"]
                                 /\ UNCHANGED skipSaved
                      /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, 
                                      rootX, rootW, wx, xw, mutex, descentDone, 
                                      ended, current, lastVpid, lastLsa, 
                                      lastKey, gen, lastGen, readCnt, fixFreed, 
                                      stopped, handedW, absCpos, seenEnd, held, 
                                      bound, cand, lastOk, heldLast, ops, l, r, 
                                      rr, k, n >>

D_resume(self) == /\ pc[self] = "D_resume"
                  /\ IF lastKey = NoKey
                        THEN /\ /\ descentDone' = FALSE
                                /\ skipSaved' = [skipSaved EXCEPT ![self] = FALSE]
                             /\ pc' = [pc EXCEPT ![self] = "D_root"]
                             /\ cand' = cand
                        ELSE /\ IF skipSaved[self]
                                   THEN /\ skipSaved' = [skipSaved EXCEPT ![self] = FALSE]
                                        /\ pc' = [pc EXCEPT ![self] = "D_reroot"]
                                        /\ cand' = cand
                                   ELSE /\ cand' = [cand EXCEPT ![self] = lastVpid]
                                        /\ pc' = [pc EXCEPT ![self] = "D_saved"]
                                        /\ UNCHANGED skipSaved
                             /\ UNCHANGED descentDone
                  /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                  rootW, rd, wx, xw, mutex, ended, current, 
                                  lastVpid, lastLsa, lastKey, gen, lastGen, 
                                  readCnt, fixFreed, stopped, reuseCaught, 
                                  benignReject, handedW, absCpos, seenEnd, 
                                  held, out, bound, lastOk, heldLast, ops, l, 
                                  r, rr, k, n >>

D_saved(self) == /\ pc[self] = "D_saved"
                 /\ SFree(cand[self])
                 /\ IF inUse[cand[self]] /\ lsa[cand[self]] = lastLsa
                       THEN /\ IF prv[cand[self]] = NoPage
                                  THEN /\ ended' = TRUE
                                       /\ UNCHANGED current
                                  ELSE /\ current' = prv[cand[self]]
                                       /\ ended' = ended
                            /\ pc' = [pc EXCEPT ![self] = "W_retry"]
                            /\ UNCHANGED << rd, lastVpid, lastLsa, lastGen, 
                                            out, bound >>
                       ELSE /\ IF inUse[cand[self]] /\ \E a, b \in keys[cand[self]] : a <= lastKey /\ lastKey <= b
                                  THEN /\ IF \E key \in keys[cand[self]] : key < lastKey
                                             THEN /\ /\ bound' = [bound EXCEPT ![self] = lastKey]
                                                     /\ out' = [out EXCEPT ![self] = cand[self]]
                                                     /\ rd' = [rd EXCEPT ![cand[self]] = rd[cand[self]] \cup {self}]
                                                  /\ pc' = [pc EXCEPT ![self] = "D_desc_take"]
                                                  /\ UNCHANGED << ended, 
                                                                  current, 
                                                                  lastVpid, 
                                                                  lastLsa, 
                                                                  lastGen >>
                                             ELSE /\ /\ lastGen' = gen[cand[self]]
                                                     /\ lastLsa' = lsa[cand[self]]
                                                     /\ lastVpid' = cand[self]
                                                  /\ IF prv[cand[self]] = NoPage
                                                        THEN /\ ended' = TRUE
                                                             /\ UNCHANGED current
                                                        ELSE /\ current' = prv[cand[self]]
                                                             /\ ended' = ended
                                                  /\ pc' = [pc EXCEPT ![self] = "W_retry"]
                                                  /\ UNCHANGED << rd, out, 
                                                                  bound >>
                                  ELSE /\ pc' = [pc EXCEPT ![self] = "D_reroot"]
                                       /\ UNCHANGED << rd, ended, current, 
                                                       lastVpid, lastLsa, 
                                                       lastGen, out, bound >>
                 /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                 rootW, wx, xw, mutex, descentDone, lastKey, 
                                 gen, readCnt, fixFreed, stopped, reuseCaught, 
                                 benignReject, handedW, absCpos, seenEnd, held, 
                                 cand, lastOk, heldLast, skipSaved, ops, l, r, 
                                 rr, k, n >>

D_reroot(self) == /\ pc[self] = "D_reroot"
                  /\ ~rootX /\ ~rootW
                  /\ rootS' = (rootS \cup {self})
                  /\ pc' = [pc EXCEPT ![self] = "D_reroot_leaf"]
                  /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootX, rootW, 
                                  rd, wx, xw, mutex, descentDone, ended, 
                                  current, lastVpid, lastLsa, lastKey, gen, 
                                  lastGen, readCnt, fixFreed, stopped, 
                                  reuseCaught, benignReject, handedW, absCpos, 
                                  seenEnd, held, out, bound, cand, lastOk, 
                                  heldLast, skipSaved, ops, l, r, rr, k, n >>

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
                                                       lastVpid, lastLsa, 
                                                       lastGen >>
                                  ELSE /\ /\ lastGen' = gen[p]
                                          /\ lastLsa' = lsa[p]
                                          /\ lastVpid' = p
                                       /\ IF prv[p] = NoPage
                                             THEN /\ ended' = TRUE
                                                  /\ UNCHANGED current
                                             ELSE /\ current' = prv[p]
                                                  /\ ended' = ended
                                       /\ pc' = [pc EXCEPT ![self] = "W_retry"]
                                       /\ UNCHANGED << rd, out, bound >>
                       /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootX, 
                                       rootW, wx, xw, mutex, descentDone, 
                                       lastKey, gen, readCnt, fixFreed, 
                                       stopped, reuseCaught, benignReject, 
                                       handedW, absCpos, seenEnd, held, cand, 
                                       lastOk, heldLast, skipSaved, ops, l, r, 
                                       rr, k, n >>

W_retry(self) == /\ pc[self] = "W_retry"
                 /\ IF ended
                       THEN /\ /\ mutex' = NoPage
                               /\ seenEnd' = TRUE
                            /\ pc' = [pc EXCEPT ![self] = "W_end"]
                       ELSE /\ pc' = [pc EXCEPT ![self] = "D_fix_prev"]
                            /\ UNCHANGED << mutex, seenEnd >>
                 /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                 rootW, rd, wx, xw, descentDone, ended, 
                                 current, lastVpid, lastLsa, lastKey, gen, 
                                 lastGen, readCnt, fixFreed, stopped, 
                                 reuseCaught, benignReject, handedW, absCpos, 
                                 held, out, bound, cand, lastOk, heldLast, 
                                 skipSaved, ops, l, r, rr, k, n >>

D_desc_take(self) == /\ pc[self] = "D_desc_take"
                     /\ IF prv[out[self]] = NoPage
                           THEN /\ ended' = TRUE
                                /\ UNCHANGED current
                           ELSE /\ current' = prv[out[self]]
                                /\ ended' = ended
                     /\ /\ lastGen' = gen[out[self]]
                        /\ lastKey' = (IF keys[out[self]] # {} THEN MinKey(keys[out[self]]) ELSE lastKey)
                        /\ lastLsa' = lsa[out[self]]
                        /\ lastVpid' = out[self]
                     /\ pc' = [pc EXCEPT ![self] = "D_publish"]
                     /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, 
                                     rootX, rootW, rd, wx, xw, mutex, 
                                     descentDone, gen, readCnt, fixFreed, 
                                     stopped, reuseCaught, benignReject, 
                                     handedW, absCpos, seenEnd, held, out, 
                                     bound, cand, lastOk, heldLast, skipSaved, 
                                     ops, l, r, rr, k, n >>

D_publish(self) == /\ pc[self] = "D_publish"
                   /\ mutex' = NoPage
                   /\ LET y == OutKey(out[self], bound[self]) IN
                        IF y # NoKey
                           THEN /\ /\ absCpos' = y
                                   /\ handedW' = (handedW \cup ({y} \cap Stable))
                           ELSE /\ TRUE
                                /\ UNCHANGED << handedW, absCpos >>
                   /\ /\ held' = [held EXCEPT ![self] = out[self]]
                      /\ out' = [out EXCEPT ![self] = NoPage]
                   /\ pc' = [pc EXCEPT ![self] = "W_read"]
                   /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, 
                                   rootX, rootW, rd, wx, xw, descentDone, 
                                   ended, current, lastVpid, lastLsa, lastKey, 
                                   gen, lastGen, readCnt, fixFreed, stopped, 
                                   reuseCaught, benignReject, seenEnd, bound, 
                                   cand, lastOk, heldLast, skipSaved, ops, l, 
                                   r, rr, k, n >>

W_read(self) == /\ pc[self] = "W_read"
                /\ readCnt' = [key \in Keys |-> IF key \in keys[held[self]] /\ key < bound[self] THEN readCnt[key] + 1 ELSE readCnt[key]]
                /\ pc' = [pc EXCEPT ![self] = "W_ask"]
                /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                rootW, rd, wx, xw, mutex, descentDone, ended, 
                                current, lastVpid, lastLsa, lastKey, gen, 
                                lastGen, fixFreed, stopped, reuseCaught, 
                                benignReject, handedW, absCpos, seenEnd, held, 
                                out, bound, cand, lastOk, heldLast, skipSaved, 
                                ops, l, r, rr, k, n >>

W_stop(self) == /\ pc[self] = "W_stop"
                /\ /\ held' = [held EXCEPT ![self] = NoPage]
                   /\ rd' = [rd EXCEPT ![held[self]] = rd[held[self]] \ {self}]
                /\ stopped' = TRUE
                /\ pc' = [pc EXCEPT ![self] = "W_end"]
                /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                rootW, wx, xw, mutex, descentDone, ended, 
                                current, lastVpid, lastLsa, lastKey, gen, 
                                lastGen, readCnt, fixFreed, reuseCaught, 
                                benignReject, handedW, absCpos, seenEnd, out, 
                                bound, cand, lastOk, heldLast, skipSaved, ops, 
                                l, r, rr, k, n >>

W_end(self) == /\ pc[self] = "W_end"
               /\ IF held[self] # NoPage
                     THEN /\ /\ held' = [held EXCEPT ![self] = NoPage]
                             /\ rd' = [rd EXCEPT ![held[self]] = rd[held[self]] \ {self}]
                     ELSE /\ TRUE
                          /\ UNCHANGED << rd, held >>
               /\ pc' = [pc EXCEPT ![self] = "Done"]
               /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                               rootW, wx, xw, mutex, descentDone, ended, 
                               current, lastVpid, lastLsa, lastKey, gen, 
                               lastGen, readCnt, fixFreed, stopped, 
                               reuseCaught, benignReject, handedW, absCpos, 
                               seenEnd, out, bound, cand, lastOk, heldLast, 
                               skipSaved, ops, l, r, rr, k, n >>

worker(self) == W_start(self) \/ W_ask(self) \/ W_lock(self)
                   \/ W_dispatch(self) \/ D_root(self) \/ D_leaf(self)
                   \/ D_check_first(self) \/ D_fix_last_first(self)
                   \/ D_fix_prev(self) \/ D_check_last(self)
                   \/ D_resume(self) \/ D_saved(self) \/ D_reroot(self)
                   \/ D_reroot_leaf(self) \/ W_retry(self)
                   \/ D_desc_take(self) \/ D_publish(self) \/ W_read(self)
                   \/ W_stop(self) \/ W_end(self)

X_loop == /\ pc[Writer] = "X_loop"
          /\ IF ops > 0
                THEN /\ ops' = ops - 1
                     /\ \/ /\ \E key \in {c \in Churn : \A p \in Chain : c \notin keys[p]}:
                                /\ ~rootX /\ ~rootW
                                /\ /\ k' = key
                                   /\ rootS' = (rootS \cup {Writer})
                           /\ pc' = [pc EXCEPT ![Writer] = "X_ins_wait"]
                           /\ UNCHANGED <<rootW, r>>
                        \/ /\ \E key \in {c \in Churn : \E p \in Chain : c \in keys[p]}:
                                /\ ~rootX /\ ~rootW
                                /\ /\ k' = key
                                   /\ rootS' = (rootS \cup {Writer})
                           /\ pc' = [pc EXCEPT ![Writer] = "X_del_wait"]
                           /\ UNCHANGED <<rootW, r>>
                        \/ /\ \E e \in {p \in Chain : keys[p] = {} /\ prv[p] # NoPage}:
                                /\ ~rootX /\ ~rootW
                                /\ /\ r' = e
                                   /\ rootW' = TRUE
                           /\ pc' = [pc EXCEPT ![Writer] = "X_del_root"]
                           /\ UNCHANGED <<rootS, k>>
                ELSE /\ pc' = [pc EXCEPT ![Writer] = "Done"]
                     /\ UNCHANGED << rootS, rootW, ops, r, k >>
          /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootX, rd, wx, xw, 
                          mutex, descentDone, ended, current, lastVpid, 
                          lastLsa, lastKey, gen, lastGen, readCnt, fixFreed, 
                          stopped, reuseCaught, benignReject, handedW, absCpos, 
                          seenEnd, held, out, bound, cand, lastOk, heldLast, 
                          skipSaved, l, rr, n >>

X_ins_wait == /\ pc[Writer] = "X_ins_wait"
              /\ /\ l' = LeafFor(k)
                 /\ xw' = (xw \cup {LeafFor(k)})
              /\ pc' = [pc EXCEPT ![Writer] = "X_ins_leaf"]
              /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                              rootW, rd, wx, mutex, descentDone, ended, 
                              current, lastVpid, lastLsa, lastKey, gen, 
                              lastGen, readCnt, fixFreed, stopped, reuseCaught, 
                              benignReject, handedW, absCpos, seenEnd, held, 
                              out, bound, cand, lastOk, heldLast, skipSaved, 
                              ops, r, rr, k, n >>

X_ins_leaf == /\ pc[Writer] = "X_ins_leaf"
              /\ XFree(l)
              /\ xw' = xw \ {l}
              /\ IF Cardinality(keys[l]) < Cap
                    THEN /\ /\ keys' = [keys EXCEPT ![l] = keys[l] \cup {k}]
                            /\ lsa' = [lsa EXCEPT ![l] = lsa[l] + 1]
                         /\ /\ l' = NoPage
                            /\ rootS' = rootS \ {Writer}
                         /\ pc' = [pc EXCEPT ![Writer] = "X_loop"]
                         /\ rootW' = rootW
                    ELSE /\ IF \A p \in Pages : inUse[p]
                               THEN /\ /\ l' = NoPage
                                       /\ rootS' = rootS \ {Writer}
                                    /\ pc' = [pc EXCEPT ![Writer] = "X_loop"]
                                    /\ rootW' = rootW
                               ELSE /\ /\ l' = NoPage
                                       /\ rootS' = rootS \ {Writer}
                                       /\ rootW' = TRUE
                                    /\ pc' = [pc EXCEPT ![Writer] = "X_ins_root"]
                         /\ UNCHANGED << keys, lsa >>
              /\ UNCHANGED << inUse, lo, nxt, prv, rootX, rd, wx, mutex, 
                              descentDone, ended, current, lastVpid, lastLsa, 
                              lastKey, gen, lastGen, readCnt, fixFreed, 
                              stopped, reuseCaught, benignReject, handedW, 
                              absCpos, seenEnd, held, out, bound, cand, lastOk, 
                              heldLast, skipSaved, ops, r, rr, k, n >>

X_ins_root == /\ pc[Writer] = "X_ins_root"
              /\ rootS = {}
              /\ /\ rootW' = FALSE
                 /\ rootX' = TRUE
              /\ pc' = [pc EXCEPT ![Writer] = "X_ins_xwait"]
              /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rd, wx, 
                              xw, mutex, descentDone, ended, current, lastVpid, 
                              lastLsa, lastKey, gen, lastGen, readCnt, 
                              fixFreed, stopped, reuseCaught, benignReject, 
                              handedW, absCpos, seenEnd, held, out, bound, 
                              cand, lastOk, heldLast, skipSaved, ops, l, r, rr, 
                              k, n >>

X_ins_xwait == /\ pc[Writer] = "X_ins_xwait"
               /\ /\ l' = LeafFor(k)
                  /\ xw' = (xw \cup {LeafFor(k)})
               /\ pc' = [pc EXCEPT ![Writer] = "X_ins_xleaf"]
               /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                               rootW, rd, wx, mutex, descentDone, ended, 
                               current, lastVpid, lastLsa, lastKey, gen, 
                               lastGen, readCnt, fixFreed, stopped, 
                               reuseCaught, benignReject, handedW, absCpos, 
                               seenEnd, held, out, bound, cand, lastOk, 
                               heldLast, skipSaved, ops, r, rr, k, n >>

X_ins_xleaf == /\ pc[Writer] = "X_ins_xleaf"
               /\ XFree(l)
               /\ /\ wx' = (wx \cup {l})
                  /\ xw' = xw \ {l}
               /\ pc' = [pc EXCEPT ![Writer] = "X_split_alloc"]
               /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                               rootW, rd, mutex, descentDone, ended, current, 
                               lastVpid, lastLsa, lastKey, gen, lastGen, 
                               readCnt, fixFreed, stopped, reuseCaught, 
                               benignReject, handedW, absCpos, seenEnd, held, 
                               out, bound, cand, lastOk, heldLast, skipSaved, 
                               ops, l, r, rr, k, n >>

X_split_alloc == /\ pc[Writer] = "X_split_alloc"
                 /\ \E fresh \in {p \in Pages : ~inUse[p]}:
                      n' = fresh
                 /\ r' = nxt[l]
                 /\ pc' = [pc EXCEPT ![Writer] = "X_split_rwait"]
                 /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                 rootW, rd, wx, xw, mutex, descentDone, ended, 
                                 current, lastVpid, lastLsa, lastKey, gen, 
                                 lastGen, readCnt, fixFreed, stopped, 
                                 reuseCaught, benignReject, handedW, absCpos, 
                                 seenEnd, held, out, bound, cand, lastOk, 
                                 heldLast, skipSaved, ops, l, rr, k >>

X_split_rwait == /\ pc[Writer] = "X_split_rwait"
                 /\ IF r # NoPage
                       THEN /\ xw' = (xw \cup {r})
                       ELSE /\ TRUE
                            /\ xw' = xw
                 /\ pc' = [pc EXCEPT ![Writer] = "X_split_right"]
                 /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                 rootW, rd, wx, mutex, descentDone, ended, 
                                 current, lastVpid, lastLsa, lastKey, gen, 
                                 lastGen, readCnt, fixFreed, stopped, 
                                 reuseCaught, benignReject, handedW, absCpos, 
                                 seenEnd, held, out, bound, cand, lastOk, 
                                 heldLast, skipSaved, ops, l, r, rr, k, n >>

X_split_right == /\ pc[Writer] = "X_split_right"
                 /\ IF r # NoPage
                       THEN /\ XFree(r)
                            /\ /\ wx' = (wx \cup {r})
                               /\ xw' = xw \ {r}
                       ELSE /\ TRUE
                            /\ UNCHANGED << wx, xw >>
                 /\ pc' = [pc EXCEPT ![Writer] = "X_split_apply"]
                 /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                 rootW, rd, mutex, descentDone, ended, current, 
                                 lastVpid, lastLsa, lastKey, gen, lastGen, 
                                 readCnt, fixFreed, stopped, reuseCaught, 
                                 benignReject, handedW, absCpos, seenEnd, held, 
                                 out, bound, cand, lastOk, heldLast, skipSaved, 
                                 ops, l, r, rr, k, n >>

X_split_apply == /\ pc[Writer] = "X_split_apply"
                 /\ LET all == keys[l] \cup {k} IN
                      /\ keys' = [keys EXCEPT ![l] = all \ {MaxKey(all)}, ![n] = {MaxKey(all)}]
                      /\ lo' = [lo EXCEPT ![n] = MaxKey(all)]
                 /\ inUse' = [inUse EXCEPT ![n] = TRUE]
                 /\ gen' = [gen EXCEPT ![n] = gen[n] + 1]
                 /\ nxt' = [nxt EXCEPT ![l] = n, ![n] = r]
                 /\ prv' = [p \in Pages |-> IF p = n THEN l ELSE IF p = r THEN n ELSE prv[p]]
                 /\ lsa' = [p \in Pages |-> IF p \in {l, n, r} THEN lsa[p] + 1 ELSE lsa[p]]
                 /\ /\ l' = NoPage
                    /\ n' = NoPage
                    /\ r' = NoPage
                    /\ rootX' = FALSE
                    /\ wx' = {}
                 /\ pc' = [pc EXCEPT ![Writer] = "X_loop"]
                 /\ UNCHANGED << rootS, rootW, rd, xw, mutex, descentDone, 
                                 ended, current, lastVpid, lastLsa, lastKey, 
                                 lastGen, readCnt, fixFreed, stopped, 
                                 reuseCaught, benignReject, handedW, absCpos, 
                                 seenEnd, held, out, bound, cand, lastOk, 
                                 heldLast, skipSaved, ops, rr, k >>

X_del_wait == /\ pc[Writer] = "X_del_wait"
              /\ /\ r' = LeafFor(k)
                 /\ xw' = (xw \cup {LeafFor(k)})
              /\ pc' = [pc EXCEPT ![Writer] = "X_del_leaf"]
              /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                              rootW, rd, wx, mutex, descentDone, ended, 
                              current, lastVpid, lastLsa, lastKey, gen, 
                              lastGen, readCnt, fixFreed, stopped, reuseCaught, 
                              benignReject, handedW, absCpos, seenEnd, held, 
                              out, bound, cand, lastOk, heldLast, skipSaved, 
                              ops, l, rr, k, n >>

X_del_leaf == /\ pc[Writer] = "X_del_leaf"
              /\ XFree(r)
              /\ /\ keys' = [keys EXCEPT ![r] = keys[r] \ {k}]
                 /\ lsa' = [lsa EXCEPT ![r] = lsa[r] + 1]
              /\ /\ k' = NoKey
                 /\ r' = NoPage
                 /\ rootS' = rootS \ {Writer}
                 /\ xw' = xw \ {r}
              /\ pc' = [pc EXCEPT ![Writer] = "X_loop"]
              /\ UNCHANGED << inUse, lo, nxt, prv, rootX, rootW, rd, wx, mutex, 
                              descentDone, ended, current, lastVpid, lastLsa, 
                              lastKey, gen, lastGen, readCnt, fixFreed, 
                              stopped, reuseCaught, benignReject, handedW, 
                              absCpos, seenEnd, held, out, bound, cand, lastOk, 
                              heldLast, skipSaved, ops, l, rr, n >>

X_del_root == /\ pc[Writer] = "X_del_root"
              /\ rootS = {}
              /\ /\ rootW' = FALSE
                 /\ rootX' = TRUE
              /\ pc' = [pc EXCEPT ![Writer] = "X_del_mutant"]
              /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rd, wx, 
                              xw, mutex, descentDone, ended, current, lastVpid, 
                              lastLsa, lastKey, gen, lastGen, readCnt, 
                              fixFreed, stopped, reuseCaught, benignReject, 
                              handedW, absCpos, seenEnd, held, out, bound, 
                              cand, lastOk, heldLast, skipSaved, ops, l, r, rr, 
                              k, n >>

X_del_mutant == /\ pc[Writer] = "X_del_mutant"
                /\ IF Mutant = "merge_right_first"
                      THEN /\ XFree(r)
                           /\ wx' = (wx \cup {r})
                      ELSE /\ TRUE
                           /\ wx' = wx
                /\ pc' = [pc EXCEPT ![Writer] = "X_del_lwait"]
                /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                rootW, rd, xw, mutex, descentDone, ended, 
                                current, lastVpid, lastLsa, lastKey, gen, 
                                lastGen, readCnt, fixFreed, stopped, 
                                reuseCaught, benignReject, handedW, absCpos, 
                                seenEnd, held, out, bound, cand, lastOk, 
                                heldLast, skipSaved, ops, l, r, rr, k, n >>

X_del_lwait == /\ pc[Writer] = "X_del_lwait"
               /\ /\ l' = prv[r]
                  /\ xw' = (xw \cup {prv[r]})
               /\ pc' = [pc EXCEPT ![Writer] = "X_del_left"]
               /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                               rootW, rd, wx, mutex, descentDone, ended, 
                               current, lastVpid, lastLsa, lastKey, gen, 
                               lastGen, readCnt, fixFreed, stopped, 
                               reuseCaught, benignReject, handedW, absCpos, 
                               seenEnd, held, out, bound, cand, lastOk, 
                               heldLast, skipSaved, ops, r, rr, k, n >>

X_del_left == /\ pc[Writer] = "X_del_left"
              /\ XFree(l)
              /\ /\ wx' = (wx \cup {l})
                 /\ xw' = xw \ {l}
              /\ pc' = [pc EXCEPT ![Writer] = "X_del_rwait"]
              /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                              rootW, rd, mutex, descentDone, ended, current, 
                              lastVpid, lastLsa, lastKey, gen, lastGen, 
                              readCnt, fixFreed, stopped, reuseCaught, 
                              benignReject, handedW, absCpos, seenEnd, held, 
                              out, bound, cand, lastOk, heldLast, skipSaved, 
                              ops, l, r, rr, k, n >>

X_del_rwait == /\ pc[Writer] = "X_del_rwait"
               /\ IF r \notin wx
                     THEN /\ xw' = (xw \cup {r})
                     ELSE /\ TRUE
                          /\ xw' = xw
               /\ pc' = [pc EXCEPT ![Writer] = "X_del_right"]
               /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                               rootW, rd, wx, mutex, descentDone, ended, 
                               current, lastVpid, lastLsa, lastKey, gen, 
                               lastGen, readCnt, fixFreed, stopped, 
                               reuseCaught, benignReject, handedW, absCpos, 
                               seenEnd, held, out, bound, cand, lastOk, 
                               heldLast, skipSaved, ops, l, r, rr, k, n >>

X_del_right == /\ pc[Writer] = "X_del_right"
               /\ IF r \notin wx
                     THEN /\ XFree(r)
                          /\ /\ wx' = (wx \cup {r})
                             /\ xw' = xw \ {r}
                     ELSE /\ TRUE
                          /\ UNCHANGED << wx, xw >>
               /\ rr' = nxt[r]
               /\ pc' = [pc EXCEPT ![Writer] = "X_del_rrwait"]
               /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                               rootW, rd, mutex, descentDone, ended, current, 
                               lastVpid, lastLsa, lastKey, gen, lastGen, 
                               readCnt, fixFreed, stopped, reuseCaught, 
                               benignReject, handedW, absCpos, seenEnd, held, 
                               out, bound, cand, lastOk, heldLast, skipSaved, 
                               ops, l, r, k, n >>

X_del_rrwait == /\ pc[Writer] = "X_del_rrwait"
                /\ IF rr # NoPage
                      THEN /\ xw' = (xw \cup {rr})
                      ELSE /\ TRUE
                           /\ xw' = xw
                /\ pc' = [pc EXCEPT ![Writer] = "X_del_rr"]
                /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                                rootW, rd, wx, mutex, descentDone, ended, 
                                current, lastVpid, lastLsa, lastKey, gen, 
                                lastGen, readCnt, fixFreed, stopped, 
                                reuseCaught, benignReject, handedW, absCpos, 
                                seenEnd, held, out, bound, cand, lastOk, 
                                heldLast, skipSaved, ops, l, r, rr, k, n >>

X_del_rr == /\ pc[Writer] = "X_del_rr"
            /\ IF rr # NoPage
                  THEN /\ XFree(rr)
                       /\ /\ wx' = (wx \cup {rr})
                          /\ xw' = xw \ {rr}
                  ELSE /\ TRUE
                       /\ UNCHANGED << wx, xw >>
            /\ pc' = [pc EXCEPT ![Writer] = "X_del_apply"]
            /\ UNCHANGED << inUse, keys, lo, nxt, prv, lsa, rootS, rootX, 
                            rootW, rd, mutex, descentDone, ended, current, 
                            lastVpid, lastLsa, lastKey, gen, lastGen, readCnt, 
                            fixFreed, stopped, reuseCaught, benignReject, 
                            handedW, absCpos, seenEnd, held, out, bound, cand, 
                            lastOk, heldLast, skipSaved, ops, l, r, rr, k, n >>

X_del_apply == /\ pc[Writer] = "X_del_apply"
               /\ inUse' = [inUse EXCEPT ![r] = FALSE]
               /\ nxt' = [nxt EXCEPT ![l] = rr, ![r] = NoPage]
               /\ prv' = [p \in Pages |-> IF p = rr THEN l ELSE IF p = r THEN NoPage ELSE prv[p]]
               /\ lsa' = [p \in Pages |-> IF p \in {l, r, rr} THEN lsa[p] + 1 ELSE lsa[p]]
               /\ /\ l' = NoPage
                  /\ r' = NoPage
                  /\ rootX' = FALSE
                  /\ rr' = NoPage
                  /\ wx' = {}
               /\ pc' = [pc EXCEPT ![Writer] = "X_loop"]
               /\ UNCHANGED << keys, lo, rootS, rootW, rd, xw, mutex, 
                               descentDone, ended, current, lastVpid, lastLsa, 
                               lastKey, gen, lastGen, readCnt, fixFreed, 
                               stopped, reuseCaught, benignReject, handedW, 
                               absCpos, seenEnd, held, out, bound, cand, 
                               lastOk, heldLast, skipSaved, ops, k, n >>

writer == X_loop \/ X_ins_wait \/ X_ins_leaf \/ X_ins_root \/ X_ins_xwait
             \/ X_ins_xleaf \/ X_split_alloc \/ X_split_rwait
             \/ X_split_right \/ X_split_apply \/ X_del_wait \/ X_del_leaf
             \/ X_del_root \/ X_del_mutant \/ X_del_lwait \/ X_del_left
             \/ X_del_rwait \/ X_del_right \/ X_del_rrwait \/ X_del_rr
             \/ X_del_apply

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

\* ---- refinement into DescScan (CBRD-27848): the scan is the sequence of keys handed out ----
\* A hand-out returns its leaf's key (Read); the next record to read is the pending hand-out's key, else the
\* largest key below the last one handed out (other transactions move it across churn keys only: Shift).
IndexKeys == UNION {keys[p] : p \in Chain}
MaxBelow(c) == IF \E x \in IndexKeys : x < c THEN MaxKey({x \in IndexKeys : x < c}) ELSE 0
Pending == {w \in Workers : pc[w] \in {"D_desc_take", "D_publish"}}
PendKey == IF Pending = {} THEN NoKey ELSE LET w == CHOOSE v \in Pending : TRUE IN OutKey(out[w], bound[w])
AbsPc == IF ~descentDone THEN "start" ELSE IF seenEnd THEN "done" ELSE "scan"
AbsG == IF AbsPc # "scan" THEN 0
        ELSE IF PendKey # NoKey THEN PendKey
        ELSE IF ended THEN 0
        ELSE MaxBelow(IF absCpos = 0 THEN Inf ELSE absCpos)
Abs == INSTANCE DescScan WITH N <- 5, W <- Stable, Top <- 5, pc <- AbsPc, g <- AbsG, emitted <- handedW,
                              hasCur <- absCpos # 0, cpos <- absCpos
AbsSpec == Abs!Spec
=============================================================================
