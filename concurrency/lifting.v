Require Import ssreflect fintype.

Add LoadPath "../concurrency" as concurrency.

Require Import compcert.common.Memory.
Require Import Globalenvs.

(* The concurrent machinery*)
Require Import concurrency.concurrent_machine.
Require Import concurrency.compcert_threads. Import Concur.

(* We assume, on each thread, a structured simulation *)
Require Import sepcomp.simulations. Import SM_simulation.

(* We lift to a whole-program simulation on the dry concurrency machine *)
Require Import sepcomp.wholeprog_simulations. Import Wholeprog_sim.

Module Type EFFSEM.
  Parameters F V C : Type.
  Notation G := (Genv.t F V).
  Parameter sem : @EffectSem G C.
End EFFSEM.  

Module Semantics_of_EFFSEM (e : EFFSEM) <: Semantics.
  Definition G := e.G.                                            
  Definition C := e.C.
  Definition M := Mem.mem.
  Definition richMem := Mem.mem.
  Definition Sem := (coopsem (sem e.sem)).
End Semantics_of_EFFSEM.  
  
Module lifting (eS eT : EFFSEM).
  Module mySchedule := ListScheduler NatTID.

  Module mySemS <: Semantics := Semantics_of_EFFSEM eS.
  Module MySemS := ShareMachineSig mySemS.
  Module mySemT <: Semantics := Semantics_of_EFFSEM eT.
  Module MySemT := ShareMachineSig mySemT.
  
  Module myCoarseSemanticsS := CoarseMachine NatTID mySchedule MySemS.
  Module myCoarseSemanticsT := CoarseMachine NatTID mySchedule MySemT.

  Definition source_concurrent_semantics := myCoarseSemanticsS.MachineSemantics.
  Definition target_concurrent_semantics := myCoarseSemanticsT.MachineSemantics.  
  
  Section lifting.
  Context {N : nat}. (** #threads *)

  Notation FS := (eS.F).
  Notation VS := (eS.V).
  Notation GS := (eS.G).
  
  Notation FT := (eT.F).
  Notation VT := (eT.V).
  Notation GT := (eT.G).    

  Notation semS := (eS.sem).
  Notation semT := (eT.sem).  

  Variables (gS : GS) (gT : GT).
  
  Variable thread_sims : 'I_N -> SM_simulation_inject semS semT gS gT.

  Definition ge_inv (geS : GS) (geT : GT) :=
    genvs_domain_eq geS geT.

  Definition init_inv j (geS : GS) valsS mS (geT : GT) valsT mT :=
      Mem.mem_inj j mS mT /\
      List.Forall2 (val_inject j) valsS valsT /\
      Events.meminj_preserves_globals geS j.

  Definition halt_inv mu (geS : GS) rv1 mS (geT : GT) rv2 mT :=
    Mem.mem_inj (as_inj mu) mS mT /\
    val_inject (as_inj mu) rv1 rv2.
  
  Lemma concur_sim main :
    Wholeprog_sim
      source_concurrent_semantics
      target_concurrent_semantics
      gS gT main
      ge_inv init_inv halt_inv.
  Proof. Admitted.
  End lifting.
End lifting.
      
                  


