Require Import compcert.common.Memory.
Require Import compcert.common.AST.     (*for typ*)
Require Import compcert.common.Values. (*for val*)
Require Import compcert.common.Globalenvs. 
Require Import compcert.lib.Integers.
Require Import Coq.ZArith.ZArith.
Require Import sepcomp.semantics.
Load scheduler.

Require Import Coq.Program.Program.
Require Import ssreflect seq.

(* This module represents the arguments
   to build a CoreSemantics with 
   compcert mem. This is used by BOTH
   Juicy machine and dry machine. *)
Module Type Semantics.
  Parameter G: Type.
  Parameter C: Type.
  Definition M: Type:= mem.
  Parameter Sem: CoreSemantics G C M.
End Semantics.

Notation EXIT := 
  (EF_external "EXIT" (mksignature (AST.Tint::nil) None)). 

Notation CREATE_SIG := (mksignature (AST.Tint::AST.Tint::nil) (Some AST.Tint) cc_default).
Notation CREATE := (EF_external "CREATE" CREATE_SIG).

Notation READ := 
  (EF_external "READ"
               (mksignature (AST.Tint::AST.Tint::AST.Tint::nil) (Some AST.Tint) cc_default)).
Notation WRITE := 
  (EF_external "WRITE"
               (mksignature (AST.Tint::AST.Tint::AST.Tint::nil) (Some AST.Tint) cc_default)).

Notation MKLOCK := 
  (EF_external "MKLOCK" (mksignature (AST.Tint::nil) (Some AST.Tint) cc_default)).
Notation FREE_LOCK := 
  (EF_external "FREE_LOCK" (mksignature (AST.Tint::nil) (Some AST.Tint) cc_default)).

Notation LOCK_SIG := (mksignature (AST.Tint::nil) (Some AST.Tint) cc_default).
Notation LOCK := (EF_external "LOCK" LOCK_SIG).
Notation UNLOCK_SIG := (mksignature (AST.Tint::nil) (Some AST.Tint) cc_default).
Notation UNLOCK := (EF_external "UNLOCK" UNLOCK_SIG).

Notation block  := Values.block.
Notation address:= (block * Z)%type.
Definition b_ofs2address b ofs : address:=
  (b, Int.intval ofs).

Inductive ctl {cT:Type} : Type :=
| Krun : cT -> ctl
| Kstop : cT -> ctl
| Kresume : cT -> ctl.

Definition EqDec: Type -> Type := 
  fun A : Type => forall a a' : A, {a = a'} + {a <> a'}.

Module Type ThreadPoolSig (TID: ThreadID).
  Import TID.

  Parameter code : Type.
  Parameter res : Type.
  Parameter LockPool : Type.
  Parameter t : Type.

  Parameter lpool : t -> LockPool.

  Notation ctl := (@ctl code).
  
  Parameter containsThread : t -> tid -> Prop.
  Parameter getThreadC : forall {tid tp}, containsThread tp tid -> ctl.
  Parameter getThreadR : forall {tid tp}, containsThread tp tid -> res.

  Parameter addThread : t -> code -> res -> t.
  Parameter updThreadC : forall {tid tp}, containsThread tp tid -> ctl -> t.
  Parameter updThreadR : forall {tid tp}, containsThread tp tid -> res -> t.
  Parameter updThread : forall {tid tp}, containsThread tp tid -> ctl -> res -> t.

  Parameter gssThreadCode :
    forall {tid tp} (cnt: containsThread tp tid) c' p'
      (cnt': containsThread (updThread cnt c' p') tid), getThreadC cnt' = c'.

  Parameter gssThreadRes:
    forall {tid tp} (cnt: containsThread tp tid) c' p'
      (cnt': containsThread (updThread cnt c' p') tid),
      getThreadR cnt' = p'.

  Parameter gssThreadCC:
    forall {tid tp} (cnt: containsThread tp tid) c'
      (cnt': containsThread (updThreadC cnt c') tid),
      getThreadC cnt' = c'.

  Parameter gssThreadCR:
    forall {tid tp} (cnt: containsThread tp tid) c'
      (cnt': containsThread (updThreadC cnt c') tid),
      getThreadR cnt = getThreadR cnt'.
End ThreadPoolSig.

Module Type ConcurrentMachineSig (TID : ThreadID)
       (ThreadPool: ThreadPoolSig TID).
  Import ThreadPool.

  Notation thread_pool := ThreadPool.t.
  (** Memories*)
  Parameter richMem: Type.
  Parameter dryMem: richMem -> mem.
  
  (** Environment and Threadwise semantics *)
  Parameter G: Type.
  Parameter Sem : CoreSemantics G code mem. 

  (** The thread pool respects the memory*)
  Parameter mem_compatible: thread_pool -> mem -> Prop.
  Parameter invariant: thread_pool -> Prop.

  (** Step relations *)
  Parameter cstep:
    G -> forall {tid0 ms m},
      containsThread ms tid0 -> mem_compatible ms m -> thread_pool -> mem  -> Prop.

  Parameter conc_call:
    G -> forall {tid0 ms m},
      containsThread ms tid0 -> mem_compatible ms m -> thread_pool -> mem -> Prop.
  
  Parameter threadHalted:
    forall {tid0 ms},
      containsThread ms tid0 -> Prop.

  Parameter init_mach : G -> val -> list val -> option thread_pool.
  
End ConcurrentMachineSig.


Module CoarseMachine (TID: ThreadID)(SCH:Scheduler TID)
       (TP: ThreadPoolSig TID) (SIG : ConcurrentMachineSig TID TP).
  Import TID SCH TP SIG.
  
  Notation Sch:=schedule.
  Notation machine_state := TP.t.
  
  (** Resume and Suspend: threads running must be preceded by a Resume
     and followed by Suspend.  This functions wrap the state to
     indicate it's ready to take a syncronisation step or resume
     running. (This keeps the invariant that at most one thread is not
     at_external) *)
  
  Inductive resume_thread': forall {tid0} {ms:machine_state},
      containsThread ms tid0 -> machine_state -> Prop:=
  | ResumeThread: forall tid0 ms ms' c
                    (ctn: containsThread ms tid0)
                    (Hcode: getThreadC ctn = Kresume c)
                    (Hinv: invariant ms)
                    (Hms': updThreadC ctn (Krun c)  = ms'),
      resume_thread' ctn ms'.
  Definition resume_thread: forall {tid0 ms},
      containsThread ms tid0 -> machine_state -> Prop:=
    @resume_thread'.

  Inductive suspend_thread': forall {tid0} {ms:machine_state},
      containsThread ms tid0 -> machine_state -> Prop:=
  | SuspendThread: forall tid0 ms ms' c ef sig args
                     (ctn: containsThread ms tid0)
                     (Hcode: getThreadC ctn = Krun c)
                     (Hat_external: at_external Sem c = Some (ef, sig, args))
                     (Hinv: invariant ms)
                     (Hms': updThreadC ctn (Kstop c) = ms'),
      suspend_thread' ctn ms'.
  Definition suspend_thread : forall {tid0 ms},
      containsThread ms tid0 -> machine_state -> Prop:=
    @suspend_thread'.
  
  Inductive machine_step {genv:G}:
    Sch -> machine_state -> mem -> Sch -> machine_state -> mem -> Prop :=
  | resume_step:
      forall tid U ms ms' m
        (HschedN: schedPeek U = Some tid)
        (Htid: containsThread ms tid)
        (Hcmpt: mem_compatible ms m)
        (Htstep: resume_thread Htid ms'),
        machine_step U ms m U ms' m
  | core_step:
      forall tid U ms ms' m m'
        (HschedN: schedPeek U = Some tid)
        (Htid: containsThread ms tid)
        (Hcmpt: mem_compatible ms m)
        (Htstep: cstep genv Htid Hcmpt ms' m'),
        machine_step U ms m U ms' m'
  | suspend_step:
      forall tid U U' ms ms' m
        (HschedN: schedPeek U = Some tid)
        (HschedS: schedSkip U = U')        (*Schedule Forward*)
        (Htid: containsThread ms tid)
        (Hcmpt: mem_compatible ms m)
        (Htstep:suspend_thread Htid ms'),
        machine_step U ms m U' ms' m
  | conc_step:
      forall tid U U' ms ms' m m'
        (HschedN: schedPeek U = Some tid)
        (HschedS: schedSkip U = U')        (*Schedule Forward*)
        (Htid: containsThread ms tid)
        (Hcmpt: mem_compatible ms m)
        (Htstep: conc_call genv  Htid Hcmpt ms' m'),
        machine_step U ms m U' ms' m'           
  | step_halted:
      forall tid U U' ms m
        (HschedN: schedPeek U = Some tid)
        (HschedS: schedSkip U = U')        (*Schedule Forward*)
        (Htid: containsThread ms tid)
        (Hcmpt: mem_compatible ms m)
        (Hhalted: threadHalted Htid),
        machine_step U ms m U' ms m
  | schedfail :
      forall tid U U' ms m
        (HschedN: schedPeek U = Some tid)
        (Htid: ~ containsThread ms tid)
        (Hinv: invariant ms)
        (HschedS: schedSkip U = U'),        (*Schedule Forward*)
        machine_step U ms m U' ms m.

  Definition MachState: Type := (Sch * machine_state)%type.

  Definition MachStep G (c:MachState) (m:mem) (c' :MachState) (m':mem) :=
    @machine_step  G (fst c) (snd c) m (fst c') (snd c') m'.
  
  Definition at_external (st : MachState)
    : option (external_function * signature * list val) := None.
  
  Definition after_external (ov : option val) (st : MachState) :
    option (MachState) := None.

  (*not clear what the value of halted should be*)
  (*Nick: IMO, the machine should be halted when the schedule is empty.
            The value is probably unimportant? *)
  Definition halted (st : MachState) : option val :=
    match schedPeek (fst st) with
    | Some _ => None
    | _ => Some Vundef
    end.

  Variable U: Sch.
  Definition init_machine the_ge (f : val) (args : list val) : option MachState :=
    match init_mach the_ge f args with
    |None => None
    | Some c => Some (U, c)
    end.
  
  Program Definition MachineSemantics :
    CoreSemantics G MachState mem.
  intros.
  apply (@Build_CoreSemantics _ MachState _
                              init_machine 
                              at_external
                              after_external
                              halted
                              MachStep
        );
    unfold at_external, halted; try reflexivity.
  intros. inversion H; subst; rewrite HschedN; reflexivity.
  auto.
  Defined.
  
End CoarseMachine.

Module FineMachine (TID: ThreadID)(SCH:Scheduler TID)
       (TP: ThreadPoolSig TID) (SIG : ConcurrentMachineSig TID TP).
  Import TID SCH TP SIG.
  
  Notation Sch:=schedule.
  Notation machine_state := TP.t.

  Inductive resume_thread': forall {tid0} {ms:machine_state},
      containsThread ms tid0 -> machine_state -> Prop:=
  | ResumeThread: forall tid0 ms ms' c
                    (ctn: containsThread ms tid0)
                    (HC: getThreadC ctn = Kresume c)
                    (Hms': updThreadC ctn (Krun c)  = ms'),
      resume_thread' ctn ms'.
  Definition resume_thread: forall {tid0 ms},
      containsThread ms tid0 -> machine_state -> Prop:=
    @resume_thread'.

  Inductive suspend_thread': forall {tid0} {ms:machine_state},
      containsThread ms tid0 -> machine_state -> Prop:=
  | SuspendThread: forall tid0 ms ms' c ef sig args
                     (ctn: containsThread ms tid0)
                     (HC: getThreadC ctn = Krun c)
                     (Hat_external: at_external Sem c = Some (ef, sig, args))
                     (Hms': updThreadC ctn (Kstop c)  = ms'),
      suspend_thread' ctn ms'.
  Definition suspend_thread : forall {tid0 ms},
      containsThread ms tid0 -> machine_state -> Prop:=
    @suspend_thread'.
  
  Inductive machine_step {genv:G}:
    Sch -> machine_state -> mem -> Sch -> machine_state -> mem -> Prop :=
  | resume_step:
      forall tid U U' ms ms' m
        (HschedN: schedPeek U = Some tid)
        (HschedS: schedSkip U = U')        (*Schedule Forward*)
        (Htid: containsThread ms tid)
        (Hcmpt: mem_compatible ms m)
        (Htstep: resume_thread Htid ms'),
        machine_step U ms m U' ms' m
  | core_step:
      forall tid U U' ms ms' m m'
        (HschedN: schedPeek U = Some tid)
        (HschedS: schedSkip U = U')        (*Schedule Forward*)
        (Htid: containsThread ms tid)
        (Hcmpt: mem_compatible ms m)
        (Htstep: cstep genv Htid Hcmpt ms' m'),
        machine_step U ms m U' ms' m'
  | suspend_step:
      forall tid U U' ms ms' m
        (HschedN: schedPeek U = Some tid)
        (HschedS: schedSkip U = U')        (*Schedule Forward*)
        (Htid: containsThread ms tid)
        (Hcmpt: mem_compatible ms m)
        (Htstep: suspend_thread Htid ms'),
        machine_step U ms m U' ms' m
  | conc_step:
      forall tid U U' ms ms' m m'
        (HschedN: schedPeek U = Some tid)
        (HschedS: schedSkip U = U')        (*Schedule Forward*)
        (Htid: containsThread ms tid)
        (Hcmpt: mem_compatible ms m)
        (Htstep: conc_call genv Htid Hcmpt ms' m'),
        machine_step U ms m U' ms' m'           
  | step_halted:
      forall tid U U' ms m
        (HschedN: schedPeek U = Some tid)
        (HschedS: schedSkip U = U')        (*Schedule Forward*)
        (Htid: containsThread ms tid)
        (Hcmpt: mem_compatible ms m)
        (Hhalted: threadHalted Htid),
        machine_step U ms m U' ms m
  | schedfail :
      forall tid U U' ms m
        (HschedN: schedPeek U = Some tid)
        (HschedS: schedSkip U = U')        (*Schedule Forward*)
        (Htid: ~ containsThread ms tid),
        machine_step U ms m U' ms m.

  Definition MachState: Type := (Sch * machine_state)%type.

  Definition MachStep G (c:MachState) (m:mem) (c' :MachState) (m':mem) :=
    @machine_step G (fst c) (snd c) m (fst c') (snd c') m'.

  Definition at_external (st : MachState)
    : option (external_function * signature * list val) := None.
  
  Definition after_external (ov : option val) (st : MachState) :
    option (MachState) := None.
  
  (*not clear what the value of halted should be*)
  Definition halted (st : MachState) : option val := None.
  
  Variable U: Sch.
  Definition init_machine the_ge (f : val) (args : list val) : option MachState :=
    match init_mach the_ge f args with
    | None => None
    | Some c => Some (U, c)
    end.
  
  Program Definition MachineSemantics :
    CoreSemantics G MachState mem.
  intros.
  apply (@Build_CoreSemantics _ MachState _
                              init_machine 
                              at_external
                              after_external
                              halted
                              MachStep
        );
    unfold at_external, halted; try reflexivity.
  auto.
  Defined.

End FineMachine.