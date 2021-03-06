Require Import compcert.lib.Axioms.

Add LoadPath "../concurrency" as concurrency.

Require Import sepcomp. Import SepComp.
Require Import sepcomp.semantics_lemmas.

Require Import concurrency.pos.
Require Import concurrency.concurrent_machine.
Require Import concurrency.pos.
Require Import Coq.Program.Program.
Require Import ssreflect ssrbool ssrnat ssrfun eqtype seq fintype finfun.
Set Implicit Arguments.

(*NOTE: because of redefinition of [val], these imports must appear 
  after Ssreflect eqtype.*)
Require Import compcert.common.AST.     (*for typ*)
Require Import compcert.common.Values. (*for val*)
Require Import compcert.common.Globalenvs. 
Require Import compcert.common.Memory.
Require Import compcert.lib.Integers.
Require Import threads_lemmas.

Require Import Coq.ZArith.ZArith.

Notation EXIT := 
  (EF_external "EXIT" (mksignature (AST.Tint::nil) None)). 

Notation CREATE_SIG :=
  (mksignature (AST.Tint::AST.Tint::nil) (Some AST.Tint) cc_default).
Notation CREATE := (EF_external "CREATE" CREATE_SIG).

Notation READ := 
  (EF_external "READ" (mksignature (AST.Tint::AST.Tint::AST.Tint::nil)
                                   (Some AST.Tint) cc_default)).
Notation WRITE := 
  (EF_external "WRITE" (mksignature (AST.Tint::AST.Tint::AST.Tint::nil)
                                    (Some AST.Tint) cc_default)).

Notation MKLOCK := 
  (EF_external "MKLOCK" (mksignature (AST.Tint::nil)
                                     (Some AST.Tint) cc_default)).
Notation FREE_LOCK := 
  (EF_external "FREE_LOCK" (mksignature (AST.Tint::nil)
                                        (Some AST.Tint) cc_default)).

Notation LOCK_SIG := (mksignature (AST.Tint::nil) (Some AST.Tint) cc_default).
Notation LOCK := (EF_external "LOCK" LOCK_SIG).
Notation UNLOCK_SIG := (mksignature (AST.Tint::nil) (Some AST.Tint) cc_default).
Notation UNLOCK := (EF_external "UNLOCK" UNLOCK_SIG).

Require Import concurrency.permissions.

Module ThreadPool <: ThreadPoolSig NatTID.

  Variable code : Type.
  Definition res := access_map.
  Definition LockPool := access_map.
  
  Record t' := mk
                 { num_threads : pos
                   ; pool :> 'I_num_threads -> @ctl code
                   ; perm_maps : 'I_num_threads -> res
                 }.
  
  Definition t := t'.

  Lemma contains0 :
    forall (n : pos), 0 < n.
  Proof.
    intros; destruct n; simpl; by apply/ltP.
  Qed.
  
  Definition lpool (tp : t) :=
    (perm_maps tp) (Ordinal (contains0 (num_threads tp))).

  Definition containsThread (tp : t) (i : NatTID.tid) : Prop:=
    i < num_threads tp.

  Definition getThreadC {i tp} (cnt: containsThread tp i) : ctl :=
    tp (Ordinal cnt).
  
  Definition getThreadR {i tp} (cnt: containsThread tp i) : res :=
    (perm_maps tp) (Ordinal cnt).

  Definition addThread (tp : t) (c : code) (pmap : res) : t :=
    let: new_num_threads := pos_incr (num_threads tp) in
    let: new_tid := ordinal_pos_incr (num_threads tp) in
    mk new_num_threads
        (fun (n : 'I_new_num_threads) => 
           match unlift new_tid n with
           | None => Kresume c (*Could be a new state Kinit?? *)
           | Some n' => tp n'
           end)
        (fun (n : 'I_new_num_threads) => 
           match unlift new_tid n with
           | None => pmap
           | Some n' => (perm_maps tp) n'
           end).
  
  Definition updThreadC {tid tp} (cnt: containsThread tp tid) (c' : ctl) : t :=
    mk (num_threads tp)
       (fun n => if n == (Ordinal cnt) then c' else (pool tp)  n)
       (perm_maps tp).

  Definition updThreadR {tid tp} (cnt: containsThread tp tid)
             (pmap' : res) : t :=
    mk (num_threads tp) (pool tp)
       (fun n =>
          if n == (Ordinal cnt) then pmap' else (perm_maps tp) n).

  Definition updThread {tid tp} (cnt: containsThread tp tid) (c' : ctl)
             (pmap : res) : t :=
    mk (num_threads tp)
       (fun n =>
          if n == (Ordinal cnt) then c' else tp n)
       (fun n =>
          if n == (Ordinal cnt) then pmap else (perm_maps tp) n).

  Lemma gssThreadCode {tid tp} (cnt: containsThread tp tid) c' p'
        (cnt': containsThread (updThread cnt c' p') tid) :
    getThreadC cnt' = c'.
  Proof.
    simpl. rewrite if_true; auto.
    unfold updThread, containsThread in *. simpl in *.
    apply/eqP. apply f_equal.
    apply proof_irr.
  Qed.

  Lemma gssThreadRes {tid tp} (cnt: containsThread tp tid) c' p'
        (cnt': containsThread (updThread cnt c' p') tid) :
    getThreadR cnt' = p'.
  Proof.
    simpl. rewrite if_true; auto.
    unfold updThread, containsThread in *. simpl in *.
    apply/eqP. apply f_equal.
    apply proof_irr.
  Qed.

  Lemma gssThreadCC {tid tp} (cnt: containsThread tp tid) c'
        (cnt': containsThread (updThreadC cnt c') tid) :
    getThreadC cnt' = c'.
  Proof.
    simpl. rewrite if_true; auto.
    unfold updThreadC, containsThread in *. simpl in *.
    apply/eqP. apply f_equal.
    apply proof_irr.
  Qed.

  Lemma gssThreadCR {tid tp} (cnt: containsThread tp tid) c'
        (cnt': containsThread (updThreadC cnt c') tid) :
    getThreadR cnt = getThreadR cnt'.
  Proof.
    simpl.
    unfold getThreadR. 
    unfold updThreadC, containsThread in *. simpl in *.
    do 2 apply f_equal.
    apply proof_irr.
  Qed.
  
End ThreadPool.


Module Concur.
  (* Module Type DrySemantics. *)
  (*   Parameter G: Type. *)
  (*   Parameter C: Type. *)
  (*   Definition M: Type:= mem. *)
  (*   Parameter Sem: CoreSemantics G C M. *)
  (* End DrySemantics. *)
  
  Module DryMachine <: ConcurrentMachineSig NatTID ThreadPool.

    Notation tid := NatTID.tid.
    Import ThreadPool.
    (** Memories*)
    Definition richMem: Type:= mem.
    Definition dryMem: richMem -> mem:= id.
    
    (** Environment and Threadwise semantics *)
    Parameter G: Type.
    Parameter Sem : CoreSemantics G code richMem.

    Notation thread_pool := (ThreadPool.t).
    Notation perm_map := ThreadPool.res.
    
    Definition lp_id := 0.
    
    (** The state respects the memory*)
    Definition perm_compatible (tp : thread_pool) p :=
      forall {tid} (cnt: containsThread tp tid),
        permMapLt (getThreadR cnt) p.

    Record mem_compatible' (tp : thread_pool) m :=
      { perm_comp: perm_compatible tp (getMaxPerm m);
        perm_max: forall b ofs, Mem.valid_block m b ->
                           permission_at m b ofs Max = Some Freeable;
        mem_canonical: isCanonical (getMaxPerm m)
      }.
    Definition mem_compatible : thread_pool -> mem -> Prop:=
      mem_compatible'.

    (** Per-thread disjointness definition*)
    Definition race_free (tp : thread_pool) :=
      forall i j (cnti : containsThread tp i)
        (cntj : containsThread tp j) (Hneq: i <> j),
        permMapsDisjoint (getThreadR cnti)
                         (getThreadR cntj).

    Record invariant' tp :=
      { canonical : forall tid (pf : containsThread tp tid),
          isCanonical (getThreadR pf);
        no_race : race_free tp;
        lock_pool : forall (cnt : containsThread tp 0), exists c,
              getThreadC cnt = Krun c /\
              halted Sem c
      }.

    Definition invariant := invariant'.
  
    (** Steps*)
    Inductive dry_step genv {tid0 tp m} (cnt: containsThread tp tid0)
              (Hcompatible: mem_compatible tp m) : thread_pool -> mem  -> Prop :=
    | step_dry :
        forall (tp':thread_pool) c m1 m' can_m' (c' : code),
        forall (Hrestrict_pmap:
             restrPermMap ((perm_comp Hcompatible) tid0 cnt) = m1)
          (Hinv : invariant tp)
          (Hcode: getThreadC cnt = Krun c)
          (Hcorestep: corestep Sem genv c m1 c' m')
          (Hm': can_m' = setMaxPerm m')
          (Htp': tp' = updThread cnt (Krun c') (getCurPerm can_m')),
          dry_step genv cnt Hcompatible tp' can_m'.

    (*missing lock-ranges*)
    Inductive ext_step genv {tid0 tp m}
              (cnt0:containsThread tp tid0)(Hcompat:mem_compatible tp m):
      thread_pool -> mem -> Prop :=
    | step_lock :
        forall (tp':thread_pool) m1 c c' m' b ofs virtue
          (cnt_lp: containsThread tp lp_id),
        forall
          (Hinv : invariant tp)
          (Hcode: getThreadC cnt0 = Kstop c)
          (Hat_external: at_external Sem c =
                         Some (LOCK, ef_sig LOCK, Vptr b ofs::nil))
          (Hcompatible: mem_compatible tp m)
          (Hrestrict_pmap:
             restrPermMap ((perm_comp Hcompatible) lp_id cnt_lp) = m1)
          (Hload: Mem.load Mint32 m1 b (Int.intval ofs) = Some (Vint Int.one))
          (Hstore:
             Mem.store Mint32 m1 b (Int.intval ofs) (Vint Int.zero) = Some m')
          (Hat_external:
             after_external Sem (Some (Vint Int.zero)) c = Some c')
          (Htp': tp' = updThread cnt0 (Kresume c')
                                 (computeMap (getThreadR cnt0) virtue)),
          ext_step genv cnt0 Hcompat tp' m' 
                   
    | step_unlock :
        forall  (tp':thread_pool) m1 c c' m' b ofs virtue
           (cnt_lp: containsThread tp lp_id),
        forall
          (Hinv : invariant tp)
          (Hcode: getThreadC cnt0 = Kstop c)
          (Hat_external: at_external Sem c =
                         Some (UNLOCK, ef_sig UNLOCK, Vptr b ofs::nil))
          (Hrestrict_pmap:
             restrPermMap ((perm_comp Hcompat) lp_id cnt_lp) = m1)
          (Hload:
             Mem.load Mint32 m1 b (Int.intval ofs) = Some (Vint Int.zero))
          (Hstore:
             Mem.store Mint32 m1 b (Int.intval ofs) (Vint Int.one) = Some m')
          (* what does the return value denote?*)
          (Hat_external: after_external Sem (Some (Vint Int.zero)) c = Some c')
          (Htp': tp' = updThread cnt0 (Kresume c')
                                 (computeMap (getThreadR cnt0) virtue)),
          ext_step genv cnt0 Hcompat tp' m' 
                   
    | step_create :
        forall  (tp_upd tp':thread_pool) c c' c_new vf arg virtue1 virtue2,
        forall
          (Hinv : invariant tp)
          (Hcode: getThreadC cnt0 = Kstop c)
          (Hat_external: at_external Sem c =
                         Some (CREATE, ef_sig CREATE, vf::arg::nil))
          (Hinitial: initial_core Sem genv vf (arg::nil) = Some c_new)
          (Hafter_external: after_external Sem
                                           (Some (Vint Int.zero)) c = Some c')
          (Htp_upd: tp_upd = updThread cnt0 (Kresume c')
                                       (computeMap (getThreadR cnt0) virtue1))
          (Htp': tp' = addThread tp_upd c_new
                                 (computeMap empty_map virtue2)),
          ext_step genv cnt0 Hcompat tp' m
                   
    | step_mklock :
        forall  (tp' tp'': thread_pool) m1 c c' m' b ofs pmap_tid' pmap_lp
           (cnt_lp': containsThread tp' lp_id)
           (cnt_lp: containsThread tp lp_id),
          let: pmap_tid := getThreadR cnt0 in
          forall
            (Hinv : invariant tp)
            (Hcode: getThreadC cnt0 = Kstop c)
            (Hat_external: at_external Sem c =
                           Some (MKLOCK, ef_sig MKLOCK, Vptr b ofs::nil))
            (Hrestrict_pmap: restrPermMap
                               ((perm_comp Hcompat) tid0 cnt0) = m1)
            (Hstore: Mem.store Mint32 m1 b (Int.intval ofs) (Vint Int.zero) = Some m')
            (Hdrop_perm:
               setPerm (Some Nonempty) b (Int.intval ofs) pmap_tid = pmap_tid')
            (Hlp_perm: setPerm (Some Writable)
                               b (Int.intval ofs) (getThreadR cnt_lp) = pmap_lp)
            (Hfter_external: after_external
                               Sem (Some (Vint Int.zero)) c = Some c')
            (Htp': tp' = updThread cnt0 (Kresume c') pmap_tid')
            (Htp'': tp'' = updThreadR cnt_lp' pmap_lp),
            ext_step genv cnt0 Hcompat tp'' m' 
                     
    | step_freelock :
        forall  (tp' tp'': thread_pool) c c' b ofs pmap_lp' virtue
           (cnt_lp': containsThread tp' lp_id)
           (cnt_lp: containsThread tp lp_id),
          let: pmap_lp := getThreadR cnt_lp in
          forall
            (Hinv : invariant tp)
            (Hcode: getThreadC cnt0 = Kstop c)
            (Hat_external: at_external Sem c =
                           Some (FREE_LOCK, ef_sig FREE_LOCK, Vptr b ofs::nil))
            (Hdrop_perm:
               setPerm None b (Int.intval ofs) pmap_lp = pmap_lp')
            (Hat_external:
               after_external Sem (Some (Vint Int.zero)) c = Some c')
            (Htp': tp' = updThread cnt0 (Kresume c')
                                   (computeMap (getThreadR cnt0) virtue))
            (Htp'': tp'' = updThreadR cnt_lp' pmap_lp'),
            ext_step genv cnt0 Hcompat  tp'' m 
                     
    | step_lockfail :
        forall  c b ofs m1
           (cnt_lp: containsThread tp lp_id),
        forall
          (Hinv : invariant tp)
          (Hcode: getThreadC cnt0 = Kstop c)
          (Hat_external: at_external Sem c =
                         Some (LOCK, ef_sig LOCK, Vptr b ofs::nil))
          (Hrestrict_pmap: restrPermMap
                             ((perm_comp Hcompat) lp_id cnt_lp) = m1)
          (Hload: Mem.load Mint32 m1 b (Int.intval ofs) = Some (Vint Int.zero)),
          ext_step genv cnt0 Hcompat tp m.
    
    Definition cstep (genv : G): forall {tid0 ms m},
        containsThread ms tid0 -> mem_compatible ms m ->
        thread_pool -> mem -> Prop:=
      @dry_step genv.
    
    Definition conc_call (genv :G) :
      forall {tid0 ms m},
        containsThread ms tid0 -> mem_compatible ms m ->
        thread_pool -> mem -> Prop:=
      @ext_step genv.

    Inductive threadHalted': forall {tid0 ms},
                               containsThread ms tid0 -> Prop:=
    | thread_halted':
        forall tp c tid0
          (cnt: containsThread tp tid0)
          (Hinv: invariant tp)
          (Hcode: getThreadC cnt = Krun c)
          (Hcant: halted Sem c),
          threadHalted' cnt.
    
    Definition threadHalted: forall {tid0 ms},
                               containsThread ms tid0 -> Prop:= @threadHalted'.

    Parameter init_core : G -> val -> list val -> option thread_pool.

    Lemma onePos: (0<1)%coq_nat. auto. Qed.
    
    Definition initial_machine c:=
      mk (mkPos onePos) (fun _ => c) (fun _ => empty_map).
    
    Definition init_mach (genv:G)(v:val)(args:list val):option thread_pool :=
      match initial_core Sem genv v args with
      | Some c => Some (initial_machine (Kresume c))
      | None => None
      end.
    
  End DryMachine.

  (* Here I make the core semantics*)
  Module mySchedule := ListScheduler NatTID.
  Module myCoarseSemantics :=
    CoarseMachine NatTID mySchedule ThreadPool DryMachine.
  Module myFineSemantics :=
    FineMachine NatTID mySchedule ThreadPool DryMachine.

  Definition coarse_semantics:=
    myCoarseSemantics.MachineSemantics.
  Definition fine_semantics:=
    myFineSemantics.MachineSemantics.
  
End Concur.



(* After this there needs to be some cleaning. *)










(* Section InitialCore. *)

(*   Context {cT G : Type} {the_sem : CoreSemantics G cT Mem.mem}. *)
(*   Import ThreadPool. *)

  
(*   Notation thread_pool := (t cT). *)
(*   Notation perm_map := access_map. *)
  
(*   Definition at_external (st : (list nat) * thread_pool) *)
(*   : option (external_function * signature * seq val) := None. *)

(*   Definition after_external (ov : option val) (st : list nat * thread_pool) : *)
(*     option (list nat * thread_pool) := None. *)

(*   Definition two_pos : pos := mkPos NPeano.Nat.lt_0_2. *)
  
(*   Definition ord1 := Ordinal (n := two_pos) (m := 1) (leqnn two_pos). *)

(*   (*not clear what the value of halted should be*) *)
(*   Definition halted (st : list nat * thread_pool) : option val := None. *)

(*   Variable compute_init_perm : G -> access_map. *)
(*   Variable lp_code : cT. *)
(*   Variable sched : list nat. *)

(*   Definition initial_core the_ge (f : val) (args : list val) : option (list nat * thread_pool) := *)
(*     match initial_core the_sem the_ge f args with *)
(*       | None => None *)
(*       | Some c => *)
(*         Some (sched, ThreadPool.mk *)
(*                        two_pos *)
(*                        (fun tid => if tid == ord0 then lp_code *)
(*                                 else if tid == ord1 then c *)
(*                                      else c (*bogus value; can't occur*)) *)
(*                        (fun tid => if tid == ord0 then empty_map else *)
(*                                   if tid == ord1 then compute_init_perm the_ge *)
(*                                   else empty_map) *)
(*                        0) *)
(*     end. *)

(*   Variable aggelos : nat -> access_map. *)

(*   Definition cstep (the_ge : G) (st : list nat * thread_pool) m *)
(*              (st' : list nat * thread_pool) m' := *)
(*     @step cT G the_sem the_ge aggelos (@coarse_step cT G the_sem the_ge) *)
(*           (fst st) (snd st) m (fst st') (snd st') m'. *)

(*   Definition fstep (the_ge : G) (st : list nat * thread_pool) m *)
(*              (st' : list nat * thread_pool) m' := *)
(*     @step cT G the_sem the_ge aggelos (@fine_step cT G the_sem the_ge) *)
(*           (fst st) (snd st) m (fst st') (snd st') m'. *)
  
(*   Program Definition coarse_semantics : *)
(*     CoreSemantics G (list nat * thread_pool) mem := *)
(*     Build_CoreSemantics _ _ _ *)
(*                         initial_core *)
(*                         at_external *)
(*                         after_external *)
(*                         halted *)
(*                         cstep *)
(*                         _ _ _. *)

(*   Program Definition fine_semantics : *)
(*     CoreSemantics G (list nat * thread_pool) mem := *)
(*     Build_CoreSemantics _ _ _ *)
(*                         initial_core *)
(*                         at_external *)
(*                         after_external *)
(*                         halted *)
(*                         fstep *)
(*                         _ _ _. *)

(* End InitialCore. *)
(* End Concur. *)