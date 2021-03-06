Require Import ssreflect seq ssrbool
        ssrnat ssrfun eqtype seq fintype finfun.

Set Implicit Arguments.
Add LoadPath "../concurrency" as concurrency.
Require Import concurrency.threads_lemmas.
Require Import compcert.common.Memory.
Require Import compcert.common.Values. (*for val*)
Require Import compcert.lib.Integers.
Require Import Coq.ZArith.ZArith.
Require Import veric.shares juicy_mem.
Require Import msl.msl_standard.
Import cjoins.

Definition access_map := Maps.PMap.t (Z -> option permission).
Definition delta_map := Maps.PMap.t (Z -> option (option permission)).

Section permMapDefs.
  
  Definition empty_map : access_map :=
    (fun z => None, Maps.PTree.empty (Z -> option permission)).

  Definition permission_at (m : mem) (b : block) (ofs : Z) (k : perm_kind) :=
    Maps.PMap.get b (Mem.mem_access m) ofs k.
 
  (* Some None represents the empty permission. None is used for
  permissions that conflict/race. *)
     
  Definition perm_union (p1 p2 : option permission) : option (option permission) :=
    match p1,p2 with
      | None, _ => Some p2
      | _, None => Some p1
      | Some p1', Some p2' =>
        match p1', p2' with
          | Freeable, _ => None
          | _, Freeable => None
          | Nonempty, _ => Some p2
          | _, Nonempty => Some p1
          | Writable, _ => None
          | _, Writable => None
          | Readable, Readable => Some (Some Readable)
        end
    end.

  Lemma perm_union_comm :
    forall p1 p2,
      perm_union p1 p2 = perm_union p2 p1.
  Proof.
    intros. destruct p1 as [p1|];
      destruct p2 as [p2|];
    try destruct p1, p2; simpl in *; reflexivity.
  Defined.

  Lemma perm_union_result : forall p1 p2 pu (Hunion: perm_union p1 p2 = Some pu),
                              pu = p1 \/ pu = p2.
  Proof.
    intros. destruct p1 as [p1|]; destruct p2 as [p2|];
            try destruct p1, p2; simpl in Hunion; try discriminate;
            try inversion Hunion; subst; auto.
  Defined.

  Lemma perm_union_ord : forall p1 p2 pu (Hunion: perm_union p1 p2 = Some pu),
                           Mem.perm_order'' pu p1 /\ Mem.perm_order'' pu p2.
  Proof.
    intros. destruct p1 as [p1|]; destruct p2 as [p2|];
            try destruct p1, p2; simpl in Hunion; try discriminate;
            try inversion Hunion; subst; unfold Mem.perm_order''; split; constructor.
  Defined.

  Inductive not_racy : option permission -> Prop :=
  | empty : not_racy None.

  Inductive racy : option permission -> Prop :=
  | freeable : racy (Some Freeable).

  Lemma not_racy_union :
    forall p1 p2 (Hnot_racy: not_racy p1),
    exists pu, perm_union p1 p2 = Some pu.
  Proof. intros. destruct p2 as [o |]; [destruct o|]; inversion Hnot_racy; subst; 
                 simpl; eexists; reflexivity.
  Qed.

  Lemma no_race_racy : forall p1 p2 (Hracy: racy p1)
                              (Hnorace: exists pu, perm_union p1 p2 = Some pu),
                         not_racy p2.
  Proof.
    intros.
    destruct p2 as [o|]; [destruct o|];
    inversion Hracy; subst;
    simpl in *; inversion Hnorace;
    (discriminate || constructor).
  Qed.
    
  Definition perm_max (p1 p2 : option permission) : option permission :=
    match p1,p2 with
      | Some Freeable, _ => p1
      | _, Some Freeable => p2
      | Some Writable, _ => p1
      | _, Some Writable => p2
      | Some Readable, _ => p1
      | _, Some Readable => p2
      | Some Nonempty, _ => p1
      | _, Some Nonempty => p2
      | None, None => None
    end.

  Lemma perm_max_comm :
    forall p1 p2,
      perm_max p1 p2 = perm_max p2 p1.
  Proof.
    intros. destruct p1 as [p1|];
      destruct p2 as [p2|];
    try destruct p1, p2; simpl in *; reflexivity.
  Defined.

  Lemma perm_max_result : forall p1 p2 pu (Hmax: perm_max p1 p2 = pu),
                            pu = p1 \/ pu = p2.
  Proof.
    intros. destruct p1 as [p1|]; destruct p2 as [p2|];
            try destruct p1, p2; simpl in Hmax; try rewrite Hmax; auto.
    destruct p1; auto. destruct p2; auto.
  Defined.

  Lemma perm_max_ord : forall p1 p2 pu (Hmax: perm_max p1 p2 = pu),
                           Mem.perm_order'' pu p1 /\ Mem.perm_order'' pu p2.
  Proof.
    intros. destruct p1 as [p1|]; destruct p2 as [p2|];
            try destruct p1; try destruct p2; simpl in Hmax;
            try discriminate; subst; unfold Mem.perm_order'';
    split; constructor.
  Defined.

  Lemma permOrd_monotonic :
    forall p1c p1m p2c p2m pu
           (Hp1: Mem.perm_order'' p1m p1c)
           (Hp2: Mem.perm_order'' p2m p2c)
           (Hpu: perm_union p1c p2c = Some pu),
      Mem.perm_order'' (perm_max p1m p2m) pu.
  Admitted.

  Definition getMaxPerm (m : mem) : access_map :=
    Maps.PMap.map (fun f => fun ofs => f ofs Max) (Mem.mem_access m).

  Definition getCurPerm (m : mem) : access_map :=
    Maps.PMap.map (fun f => fun ofs => f ofs Cur) (Mem.mem_access m).

  Definition getPermMap (m : mem) : Maps.PMap.t (Z -> perm_kind -> option permission) :=
    Mem.mem_access m.

  Lemma getCur_Max : forall m b ofs,
                       Mem.perm_order'' (Maps.PMap.get b (getMaxPerm m) ofs)
                                        (Maps.PMap.get b  (getCurPerm m) ofs).
  Proof.
    intros. 
    assert (Hlt:= Mem.access_max m b ofs).
    unfold Mem.perm_order'' in *.
    unfold getMaxPerm, getCurPerm.
    do 2 rewrite Maps.PMap.gmap.
    auto.
  Qed.
  
  Lemma getMaxPerm_correct :
    forall m b ofs,
      Maps.PMap.get b (getMaxPerm m) ofs = permission_at m b ofs Max.
  Proof.
    intros. unfold getMaxPerm. by rewrite Maps.PMap.gmap.
  Qed.

  Lemma getCurPerm_correct :
    forall m b ofs,
      Maps.PMap.get b (getCurPerm m) ofs = permission_at m b ofs Cur.
  Proof.
    intros. unfold getCurPerm. by rewrite Maps.PMap.gmap.
  Qed.
 
  Definition permMapsDisjoint (pmap1 pmap2 : access_map) : Prop :=
    forall b ofs, exists pu,
      perm_union ((Maps.PMap.get b pmap1) ofs)
                 ((Maps.PMap.get b pmap2) ofs) = Some pu.
  
  Lemma permMapsDisjoint_comm :
    forall pmap1 pmap2
      (Hdis: permMapsDisjoint pmap1 pmap2),
      permMapsDisjoint pmap2 pmap1.
  Proof.
    unfold permMapsDisjoint in *.
    intros. destruct (Hdis b ofs) as [pu Hpunion].
    rewrite perm_union_comm in Hpunion.
    eexists; eauto.
  Qed.

  Lemma disjoint_norace:
    forall (mi mj : mem) (b : block) (ofs : Z)
      (Hdisjoint: permMapsDisjoint (getCurPerm mi) (getCurPerm mj))
      (Hpermj: Mem.perm mj b ofs Cur Readable)
      (Hpermi: Mem.perm mi b ofs Cur Writable),
      False.
  Proof.
    intros.
    unfold Mem.perm, Mem.perm_order' in *.
    unfold permMapsDisjoint, getCurPerm in Hdisjoint. simpl in Hdisjoint.
    destruct (Hdisjoint b ofs) as [pu Hunion].
    clear Hdisjoint.
    do 2 rewrite Maps.PMap.gmap in Hunion.
    destruct (Maps.PMap.get b (Mem.mem_access mj) ofs Cur) as [pj|] eqn:Hpj;
      auto.
    destruct (Maps.PMap.get b (Mem.mem_access mi) ofs Cur) as [pi|] eqn:Hpi;
      auto.
    inversion Hpermi; inversion Hpermj; subst; simpl in Hunion;
    discriminate.
  Qed.

  Definition isCanonical (pmap : access_map) := pmap.1 = fun _ => None.
  
  Definition permMapLt (pmap1 pmap2 : access_map) : Prop :=
    forall b ofs,
      Mem.perm_order'' (Maps.PMap.get b pmap2 ofs)
                       (Maps.PMap.get b pmap1 ofs).
  
  Definition setPerm (p : option permission) (b : block)
             (ofs : Z) (pmap : access_map) : access_map :=
    Maps.PMap.set b (fun ofs' => if Coqlib.zeq ofs ofs' then
                                p
                              else
                                Maps.PMap.get b pmap ofs')
                  pmap.
  
  Definition computeMap (pmap : access_map) (delta : delta_map) : access_map :=
    (fun ofs => None,
             Maps.PTree.map 
               (fun b f => 
                  fun ofs =>
                    match (Maps.PMap.get b delta) ofs with
                    | None => f ofs
                    | Some p => p
                    end) pmap.2).

  Import Maps BlockList.
  
  Definition maxF (f : Z -> perm_kind -> option permission) :=
    fun ofs k => match k with
              | Max => Some Freeable
              | Cur => f ofs k
              end.
  
  Fixpoint PList l m : list (positive * (Z -> perm_kind -> option permission)) :=
    match l with
      | nil => nil
      | x :: l =>
        (Pos.of_nat x, maxF (PMap.get (Pos.of_nat x) m)) :: (PList l m)
  end.
  
  Lemma PList_app :
    forall l m x,
      (PList l m) ++ ((Pos.of_nat x,
                                maxF (PMap.get (Pos.of_nat x) m)) :: nil) =
      PList (l ++ (x :: nil)) m.
  Proof.
    intro l. induction l; intros.
    reflexivity.
    simpl. apply f_equal.
    auto.
  Qed.

  Lemma PList_cons :
    forall l m x,
      (Pos.of_nat x, maxF (PMap.get (Pos.of_nat x) m)) :: (PList l m) =
      PList (x :: l) m.
  Proof.
    reflexivity.
  Qed.

  Lemma PList_correct :
    forall l m k v
           (HInl: List.In k l)
           (HInMap: List.In (Pos.of_nat k, v) (PTree.elements m.2)),
      List.In (Pos.of_nat k, maxF v) (PList l m).
  Proof.
    intros l m. induction l; intros; inversion HInl.
    - subst. simpl. apply PTree.elements_complete in HInMap.
      unfold PMap.get. rewrite HInMap. now left.
    - simpl. right. auto.
  Qed.

  Lemma PList_mkBlock_complete :
    forall k v m n
           (Hk: k > 0)
           (HIn1: List.In (Pos.of_nat k, v) (PList (mkBlockList n) m)),
      List.In k (mkBlockList n).
  Proof.
    intros.
    induction n.
    simpl in *. auto.
    destruct n. simpl in HIn1. auto.
    rewrite <- mkBlockList_unfold' in HIn1.
    rewrite <- PList_cons in HIn1.
    apply List.in_inv in HIn1.
    destruct HIn1 as [Heq | HIn1].
    assert (Heqn: Pos.of_nat (S n) = Pos.of_nat k) by (inversion Heq; auto).
    apply Nat2Pos.inj_iff in Heqn.
    subst. simpl; auto.
    auto. intro Hcontra. subst. auto.
    rewrite <- mkBlockList_unfold'.
    right. auto.
  Qed.
  
  Lemma PList_mkBlock_det :
    forall n k v v' m
           (HIn1: List.In (Pos.of_nat k, v) (PList (mkBlockList n) m))
           (HIn2: List.In (Pos.of_nat k, v') (PList (mkBlockList n) m)),
      v = v'.
  Proof.
    intros n. induction n.
    - simpl. intros. exfalso. auto.
    - intros.
      destruct n. simpl in HIn1. exfalso; auto.
      destruct n. simpl in HIn1, HIn2.
      destruct HIn1 as [HIn1 | HIn1];
        destruct HIn2 as [HIn2 | HIn2];
        inversion HIn1; inversion HIn2; now subst.
      rewrite <- mkBlockList_unfold' in HIn1, HIn2.
      rewrite <- PList_cons in HIn1, HIn2.
      apply List.in_inv in HIn1.
      apply List.in_inv in HIn2.
      destruct HIn1 as [Heq1 | HIn1].
      + destruct HIn2 as [Heq2 | HIn2].
        inversion Heq1; inversion Heq2. reflexivity.
        assert (Heq:Pos.of_nat (S (S n)) =
                    Pos.of_nat k /\ maxF (m !! (Pos.of_nat (S (S n)))) = v)
          by (inversion Heq1; auto).
        destruct Heq as [HEqk Hv].
        rewrite <- HEqk in HIn2.
        exfalso.
        clear Hv HEqk Heq1 IHn v k.
        apply PList_mkBlock_complete in HIn2.
        eapply mkBlockList_not_in in HIn2; eauto. auto.
      + destruct HIn2 as [Heq | HIn2].
        assert (Heq':Pos.of_nat (S (S n)) = Pos.of_nat k) by (inversion Heq; auto).
        rewrite <- Heq' in HIn1.
        apply PList_mkBlock_complete in HIn1; auto.
        apply mkBlockList_not_in in HIn1; auto. now exfalso.
        eauto.
  Qed.
  
  Fixpoint canonicalPTree (l : list (positive * (Z -> perm_kind -> option permission))) :=
    match l with
      | nil => PTree.empty _
      | x :: l =>
        PTree.set (fst x) (snd x) (canonicalPTree l)
    end.

  Lemma canonicalPTree_elements :
    forall l x
           (Hin: List.In x (PTree.elements (canonicalPTree l))),
      List.In x l.
  Proof.
    intro l.
    induction l; intros; auto.
    simpl.
    simpl in Hin.
    unfold PTree.elements in Hin.
    destruct x as [p o].
    apply PTree.elements_complete in Hin.
    destruct (Pos.eq_dec a.1 p).
    - subst. rewrite PTree.gss in Hin. inversion Hin; subst.
      left.  destruct a; reflexivity.
    - rewrite PTree.gso in Hin; auto.
      apply PTree.elements_correct in Hin. right. auto.
  Qed.

  Lemma canonicalPTree_get_complete :
    forall l m k f
           (HGet: (canonicalPTree (PList l m)) ! k = Some f),
      List.In (k, f) (PList l m).
  Proof.
    intro l. induction l.
    simpl. intros. rewrite PTree.gempty in HGet. discriminate.
    intros.
    rewrite <- PList_cons in HGet.
    apply PTree.elements_correct in HGet.
    apply canonicalPTree_elements in HGet.
    destruct (List.in_inv HGet) as [Heq | Hin].
    inversion Heq; subst. simpl; auto.
    auto.
  Qed.
  
  Lemma canonicalPTree_get_sound :
    forall n m k
           (Hk: k > 0)
           (Hn: n > 1)
           (HGet: (canonicalPTree (PList (mkBlockList n) m)) ! (Pos.of_nat k) = None),
      ~ List.In k (mkBlockList n).
  Proof.
    intros.
    destruct n. simpl; auto.
    induction n. simpl; auto.
    intro HIn.
    rewrite <- mkBlockList_unfold' in HGet, HIn.
    destruct (List.in_inv HIn) as [? | HIn']; subst.
    rewrite <- PList_cons in HGet.
    unfold canonicalPTree in HGet. fold canonicalPTree in HGet.
    rewrite PTree.gss in HGet. discriminate.
    destruct n. simpl in *; auto.
    apply IHn. auto. rewrite <- PList_cons in HGet.
    unfold canonicalPTree in HGet. fold canonicalPTree in HGet.
    apply mkBlockList_range in HIn'.
    assert (k <> S (S n)). destruct HIn'. intros Hcontra; subst. auto.
    rewrite ltnn in H. auto.
    rewrite PTree.gso in HGet.
    assumption.
    intros HContra.
    unfold fst in HContra.
    apply Nat2Pos.inj_iff in HContra. auto. intros ?; subst; auto.
    intros ?; subst. discriminate.
    assumption.
  Qed.
  
  Definition canonicalPMap n m : Maps.PMap.t (Z -> perm_kind -> option permission) :=
    let l := mkBlockList n in
    (fun _ _ => None, canonicalPTree (PList l m)).

  Lemma canonicalPMap_sound :
    forall k n m
           (Hk : k > 0)
           (Hkn : k < n),
      maxF (m !! (Pos.of_nat k)) = (canonicalPMap n m) !! (Pos.of_nat k).
  Proof.
    intros.
    unfold PMap.get.
    destruct (((canonicalPMap n m).2) ! (Pos.of_nat k)) as [f|] eqn:HGet.
    - apply PTree.elements_correct in HGet.
      unfold canonicalPMap in HGet.  simpl in HGet.
      destruct ((m.2) ! (Pos.of_nat k)) eqn:HGet'.
      + apply PTree.elements_correct in HGet'.
        apply canonicalPTree_elements in HGet.
        apply PList_correct with (l := mkBlockList n) in HGet'.
        eapply PList_mkBlock_det; eauto.
        apply PList_mkBlock_complete in HGet. assumption.
        assumption.
      + apply PTree.elements_complete in HGet.
        apply canonicalPTree_get_complete in HGet.
        induction (mkBlockList n). simpl in HGet. by exfalso.
        simpl in HGet. destruct HGet as [Heq | Hin].
        inversion Heq; subst.
        unfold PMap.get. rewrite <- H0 in HGet'. rewrite HGet'. reflexivity.
        auto.
    - unfold canonicalPMap in HGet. simpl in HGet.
      apply canonicalPTree_get_sound in HGet.
      destruct n. exfalso. auto. destruct n. exfalso. ssromega.
      exfalso. apply HGet. apply mkBlockList_include; auto.
      assumption. clear HGet.
      eapply leq_ltn_trans; eauto.
  Qed.

  Lemma canonicalPMap_default :
    forall n k m
           (Hkn : k >= n),
      (canonicalPMap n m) !! (Pos.of_nat k) = fun _ _ => None.
  Proof.
    intro. induction n; intros. unfold canonicalPMap. simpl.
    unfold PMap.get.
    rewrite PTree.gempty. reflexivity.
    assert (Hkn': n <= k) by ssromega.
    unfold canonicalPMap.
    destruct n. simpl. unfold PMap.get. simpl. rewrite PTree.gempty. reflexivity.
    unfold PMap.get.
    rewrite <- mkBlockList_unfold'. rewrite <- PList_cons.
    unfold canonicalPTree.
    rewrite PTree.gso. fold canonicalPTree.
    specialize (IHn _ m Hkn').
    unfold canonicalPMap, PMap.get, snd in IHn.
    destruct ((canonicalPTree (PList (mkBlockList n.+1) m)) ! (Pos.of_nat k)); auto.
    unfold fst. intros HContra. apply Nat2Pos.inj_iff in HContra; subst; ssromega.
  Qed.

  Definition setMaxPerm (m : mem) : mem.
  Proof.
    refine (Mem.mkmem (Mem.mem_contents m)
                      (canonicalPMap (Pos.to_nat (Mem.nextblock m))
                                     (Mem.mem_access m))
                      (Mem.nextblock m) _ _ _).
      { intros.
        replace b with (Pos.of_nat (Pos.to_nat b)) by (rewrite Pos2Nat.id; done).
        destruct (leq (Pos.to_nat (Mem.nextblock m)) (Pos.to_nat b)) eqn:Hbn.
          by rewrite canonicalPMap_default.
          erewrite <- canonicalPMap_sound. simpl.
          match goal with
          | [|- match ?Expr with _ => _ end] => destruct Expr
          end; constructor.
          apply/ltP/Pos2Nat.is_pos.
          ssromega. }
      { intros b ofs k H.
        replace b with (Pos.of_nat (Pos.to_nat b)) by (rewrite Pos2Nat.id; done).
        erewrite canonicalPMap_default. reflexivity.
        apply Pos.le_nlt in H.
        apply/leP.
        now apply Pos2Nat.inj_le.
      }
      { apply Mem.contents_default. }
  Defined.

  Lemma setMaxPerm_Max :
    forall m b ofs,
      (Mem.valid_block m b ->
       permission_at (setMaxPerm m) b ofs Max = Some Freeable) /\
      (~Mem.valid_block m b ->
       permission_at (setMaxPerm m) b ofs Max = None).
  Proof.
    intros.
    assert (Hb : b = Pos.of_nat (Pos.to_nat b))
      by (by rewrite Pos2Nat.id).
    split.
    { intros Hvalid. unfold permission_at,  setMaxPerm. simpl.
      rewrite Hb.
      rewrite <- canonicalPMap_sound.
      reflexivity.
      assert (H := Pos2Nat.is_pos b). ssromega.
      apply Pos2Nat.inj_lt in Hvalid. ssromega.
    }
    { intros Hinvalid.
      unfold permission_at, setMaxPerm. simpl.
      rewrite Hb.
      rewrite canonicalPMap_default. reflexivity.
      apply Pos.le_nlt in Hinvalid.
      apply Pos2Nat.inj_le in Hinvalid. ssromega.
    }
  Qed.

  Lemma setMaxPerm_Cur :
    forall m b ofs,
      permission_at (setMaxPerm m) b ofs Cur = permission_at m b ofs Cur.
  Proof.
    intros. unfold setMaxPerm, permission_at. simpl.
    assert (Hb : b = Pos.of_nat (Pos.to_nat b))
      by (by rewrite Pos2Nat.id).
    rewrite Hb.
    destruct (Coqlib.plt b (Mem.nextblock m)) as [Hvalid | Hinvalid].
    rewrite <- canonicalPMap_sound. reflexivity.
    assert (H := Pos2Nat.is_pos b). ssromega.
    apply Pos2Nat.inj_lt in Hvalid. ssromega.
    rewrite canonicalPMap_default.
    apply Mem.nextblock_noaccess with (ofs := ofs) (k := Cur) in Hinvalid.
    rewrite <- Hb.
    rewrite Hinvalid. reflexivity.
    apply Pos.le_nlt in Hinvalid.
    apply Pos2Nat.inj_le in Hinvalid. ssromega.
  Qed.

  Definition restrPermMap p' m (Hlt: permMapLt p' (getMaxPerm m)) : mem.
  Proof.
    refine ({|
               Mem.mem_contents := Mem.mem_contents m;
               Mem.mem_access :=
                 (fun ofs k =>
                    match k with
                      | Cur => None
                      | Max => fst (Mem.mem_access m) ofs k
                    end, Maps.PTree.map (fun b f =>
                                           fun ofs k =>
                                             match k with
                                               | Cur =>
                                                 (Maps.PMap.get b p') ofs
                                               | Max =>
                                                 f ofs Max
                                             end) (Mem.mem_access m).2);
               Mem.nextblock := Mem.nextblock m;
               Mem.access_max := _;
               Mem.nextblock_noaccess := _;
               Mem.contents_default := Mem.contents_default m |}).
    - unfold permMapLt in Hlt.
      assert (Heq: forall b ofs, Maps.PMap.get b (getMaxPerm m) ofs =
                            Maps.PMap.get b (Mem.mem_access m) ofs Max).
      { unfold getMaxPerm. intros.
        rewrite Maps.PMap.gmap. reflexivity. }
      intros.
      specialize (Hlt b ofs).
      specialize (Heq b ofs).
      unfold getMaxPerm in Hlt.
      unfold Maps.PMap.get in *. simpl in *.
      rewrite Maps.PTree.gmap; simpl.
      match goal with
        | [|- context[match Coqlib.option_map ?Expr1 ?Expr2  with _ => _ end]] =>
          destruct (Coqlib.option_map Expr1 Expr2) as [f|] eqn:?
      end; auto; unfold Coqlib.option_map in Heqo.
      destruct (Maps.PTree.get b (Mem.mem_access m).2) eqn:?; try discriminate.
      + inversion Heqo; subst; clear Heqo.
        rewrite Heq in Hlt. auto.
      + unfold Mem.perm_order''. by destruct ((Mem.mem_access m).1 ofs Max).
    - intros b ofs k Hnext.
    - unfold permMapLt in Hlt.
      assert (Heq: forall b ofs, Maps.PMap.get b (getMaxPerm m) ofs =
                            Maps.PMap.get b (Mem.mem_access m) ofs Max).
      { unfold getMaxPerm. intros.
        rewrite Maps.PMap.gmap. reflexivity. }
      specialize (Hlt b ofs).
      specialize (Heq b ofs).
      unfold Maps.PMap.get in *.
      simpl in *.
      rewrite Maps.PTree.gmap; simpl.
      assert (H := Mem.nextblock_noaccess m).
      specialize (H b). unfold Maps.PMap.get in H.
      match goal with
        | [|- context[match Coqlib.option_map ?Expr1 ?Expr2  with _ => _ end]] =>
          destruct (Coqlib.option_map Expr1 Expr2) as [f|] eqn:?
      end; auto; unfold Coqlib.option_map in Heqo;
      destruct (Maps.PTree.get b (Mem.mem_access m).2) eqn:Heqo2; try discriminate.
      inversion Heqo. subst f. clear Heqo.
      destruct k; auto.
      rewrite Heq in Hlt.
      specialize (H ofs Max). rewrite H in Hlt; auto.
      unfold Mem.perm_order'' in Hlt. destruct (Maps.PTree.get b p'.2).
      destruct (o0 ofs); tauto.
      destruct (p'.1 ofs); tauto.
      rewrite H; auto. destruct k; auto.
  Defined.
  
  Lemma restrPermMap_nextblock :
    forall p' m (Hlt: permMapLt p' (getMaxPerm m)),
      Mem.nextblock (restrPermMap Hlt) = Mem.nextblock m.
  Proof.
    intros. unfold restrPermMap. reflexivity.
  Qed.

  Lemma restrPermMap_irr : forall p' p'' m
                             (Hlt : permMapLt p' (getMaxPerm m))
                             (Hlt': permMapLt p'' (getMaxPerm m))
                             (Heq_new: p' = p''),
                             restrPermMap Hlt = restrPermMap Hlt'.
  Proof.
    intros. subst.
    apply f_equal. by apply proof_irr.
  Qed.

  Lemma restrPermMap_disjoint_inv:
    forall (mi mj m : mem) (pi pj : access_map)
      (Hcan_m: isCanonical (getMaxPerm m))
      (Hltj: permMapLt pj (getMaxPerm m))
      (Hlti: permMapLt pi (getMaxPerm m))
      (Hdisjoint: permMapsDisjoint pi pj)
      (Hrestrj: restrPermMap Hltj = mj)
      (Hrestri: restrPermMap Hlti = mi),
      permMapsDisjoint (getCurPerm mi) (getCurPerm mj).
  Proof.
    intros. rewrite <- Hrestri. rewrite <- Hrestrj.
    unfold restrPermMap, getCurPerm, permMapsDisjoint. simpl in *.
    intros b ofs.
    do 2 rewrite Maps.PMap.gmap.
    clear Hrestrj Hrestri.
    unfold permMapLt, Mem.perm_order'' in *.
    specialize (Hltj b ofs); specialize (Hlti b ofs).
    unfold getMaxPerm in *; simpl in *.
    rewrite Maps.PMap.gmap in Hlti, Hltj.
    unfold permMapsDisjoint, Maps.PMap.get in *; simpl in *.
    do 2 rewrite Maps.PTree.gmap. unfold Coqlib.option_map.
    specialize (Hdisjoint b ofs).
    assert (Hnone: (Mem.mem_access m).1 ofs Max = None)
      by (unfold isCanonical in Hcan_m; simpl in Hcan_m;
            by apply equal_f with (x:=ofs) in Hcan_m).
    destruct (Maps.PTree.get b (Mem.mem_access m).2) eqn:?; auto.
    rewrite Hnone in Hlti, Hltj;
      destruct (Maps.PTree.get b pi.2)
      as [f1 |] eqn:?;
                destruct (Maps.PTree.get b pj.2) as [f2|] eqn:?;
      repeat match goal with
               | [H: match ?Expr with _ => _ end |- _] => destruct Expr
             end; tauto.
  Qed.

  Lemma restrPermMap_correct :
    forall p' m (Hlt: permMapLt p' (getMaxPerm m))
      (Hcan_p' : isCanonical p')
      (Hcan_m : isCanonical (getMaxPerm m))
      b ofs,
      permission_at (restrPermMap Hlt) b ofs Max =
      Maps.PMap.get b (getMaxPerm m) ofs /\
      permission_at (restrPermMap Hlt) b ofs Cur =
      Maps.PMap.get b p' ofs.
  Proof.
    intros. unfold restrPermMap, getMaxPerm, permission_at. simpl.
    rewrite Maps.PMap.gmap. split;
      unfold permMapLt in Hlt; specialize (Hlt b ofs);
      unfold Maps.PMap.get; simpl; rewrite Maps.PTree.gmap;
      unfold Coqlib.option_map; simpl;
      destruct (Maps.PTree.get b (Mem.mem_access m).2) eqn:?; auto.
    unfold Maps.PMap.get in Hlt.
    unfold isCanonical in *. 
    destruct (Maps.PTree.get b p'.2) eqn:?; [| by rewrite Hcan_p'].
    rewrite Hcan_m in Hlt.
    unfold getMaxPerm in Hlt. rewrite Maps.PTree.gmap1 in Hlt.
    unfold Coqlib.option_map in Hlt.
    rewrite Heqo in Hlt. simpl in Hlt.
    destruct (o ofs); tauto.
  Qed.

  Lemma restrPermMap_can : forall (p : access_map) (m m': mem)
                             (Hcanonical: isCanonical p)
                             (Hlt: permMapLt p (getMaxPerm m))
                             (Hrestrict: restrPermMap Hlt = m'),
      isCanonical (getCurPerm m').
  Proof.
    intros. subst.
    unfold restrPermMap, getCurPerm, isCanonical in *. simpl in *.
    auto.
  Defined.

  Lemma restrPermMap_can_max : forall (p : access_map) (m m': mem)
                                 (Hcanonical: isCanonical (getMaxPerm m))
                                 (Hlt: permMapLt p (getMaxPerm m))
                                 (Hrestrict: restrPermMap Hlt = m'),
      isCanonical (getMaxPerm m').
  Proof.
    intros. subst.
    unfold restrPermMap, getMaxPerm, isCanonical in *. simpl in *.
    auto.
  Defined.
  
End permMapDefs.

Section ShareMaps.

  Definition share_map := Maps.PTree.t (Z -> share).

  Definition empty_share_map := Maps.PTree.empty (Z -> share).
  
  Definition mkShare_map sh_tree : Maps.PMap.t (Z -> share) :=
    (fun ofs => Share.bot, sh_tree).

  Definition share_split sh :=
    (Share.unrel Share.Lsh sh, Share.unrel Share.Rsh sh).

  Definition share_to_perm sh :=
    perm_of_sh (share_split sh).1 (share_split sh).2.

  Definition share_to_access_map (smap : share_map) : access_map :=
    (fun ofs => None, Maps.PTree.map1 (fun f => fun ofs =>
                                            share_to_perm (f ofs)) smap).

  Definition setShare (sh : share) b ofs (smap : share_map) : share_map :=
    Maps.PTree.set b (fun ofs' => if is_left (Coqlib.zeq ofs ofs') then sh else
                                 match (Maps.PTree.get b smap) with
                                 | Some f => f ofs'
                                 | None => Share.bot
                                 end) smap.

  Definition access_to_share_map (smap : share_map) (pmap : access_map): share_map :=
    Maps.PTree.combine
      (fun o1 o2 =>
         match o1 with
         | Some f1 =>
           Some(
               match o2 with
               | Some f2 =>
                 fun ofs => match f2 ofs with
                         | Some Freeable => Share.top
                         | Some _ => f1 ofs
                         | None => Share.bot
                         end
               | None => fun ofs => Share.bot
               end)
         | None =>
           match o2 with
           | Some f2 => Some (fun ofs => match f2 ofs with
                                     | Some Freeable => Share.top
                                     | Some _ => Share.bot (* bogus value *)
                                     | None => Share.bot
                                     end)
           | None => None
           end
         end) smap pmap.2.
     
  Definition decay m_before m_after := forall b ofs, 
      (~Mem.valid_block m_before b ->
       forall p, Mem.perm m_after b ofs Cur p -> Mem.perm m_after b ofs Cur Freeable) /\
      (Mem.perm m_before b ofs Cur Freeable ->
       forall p, Mem.perm m_after b ofs Cur p -> Mem.perm m_after b ofs Cur Freeable) /\
      (~Mem.perm m_before b ofs Cur Freeable ->
       forall p, Mem.perm m_before b ofs Cur p -> Mem.perm m_after b ofs Cur p) /\
      (Mem.valid_block m_before b ->
       forall p, Mem.perm m_after b ofs Cur p -> Mem.perm m_before b ofs Cur p).
  
  Definition map_decay (pmap pmap' : access_map) :=
    forall b ofs, (Maps.PMap.get b pmap) ofs = (Maps.PMap.get b pmap') ofs \/
             ((Maps.PMap.get b pmap) ofs = Some Freeable /\
              (Maps.PMap.get b pmap') ofs = None) \/
             ((Maps.PMap.get b pmap) ofs = None /\
              (Maps.PMap.get b pmap') ofs = Some Freeable).

  Definition decay' m_before m_after := forall b ofs, 
      (~Mem.valid_block m_before b ->
       Mem.valid_block m_after b ->
       Maps.PMap.get b (Mem.mem_access m_after) ofs Cur = Some Freeable) /\
      (Mem.valid_block m_before b ->
       ((Maps.PMap.get b (Mem.mem_access m_before) ofs Cur = Some Freeable /\
         Maps.PMap.get b (Mem.mem_access m_after) ofs Cur = None)) \/
       (Maps.PMap.get b (Mem.mem_access m_before) ofs Cur =
             Maps.PMap.get b (Mem.mem_access m_after) ofs Cur)).

  Lemma decay_decay' :
    forall m m',
      decay m m' ->
      decay' m m'.
  Admitted.
       
  
  (*Lemma mem_map_decay :
    forall m m',
      decay m m' ->
      map_decay (getCurPerm m) (getCurPerm m').
  Proof.
    intros m m' Hdecay.
    intros b ofs.
    destruct (Hdecay b ofs) as [H1 [H2 [H3 H4]]].
    unfold Mem.valid_block in *.
    destruct (Coqlib.plt b (Mem.nextblock m)) as [Hlt | Hlt].
    - specialize (H4 Hlt). clear H1.
      destruct (Maps.PMap.get b (getCurPerm m') ofs) as [p'|] eqn:Hperm';
        destruct (Maps.PMap.get b (getCurPerm m) ofs) as [p|] eqn:Hperm; auto;
        rewrite getCurPerm_correct in Hperm;
        rewrite getCurPerm_correct in Hperm'.
      { destruct p eqn:Hp;
        [ assert (Hperm_freeable: Mem.perm m b ofs Cur Freeable)
            by (unfold Mem.perm, Mem.perm_order'; subst; rewrite Hperm; constructor);
          assert (Hmem_perm': Mem.perm m' b ofs Cur p')
            by (unfold Mem.perm, Mem.perm_order'; subst; rewrite Hperm'; constructor);
          specialize (H2 Hperm_freeable _ Hmem_perm');
          unfold Mem.perm in H2;
          rewrite Hperm' in H2; simpl in H2; inversion H2; subst; auto| | |];
          assert (Hnot_freeable: ~ Mem.perm m b ofs Cur Freeable)
            by (unfold Mem.perm, Mem.perm_order';
                 rewrite Hperm; intro Hcontra; inversion Hcontra);
            specialize (H3 Hnot_freeable);
            specialize (H3 p);
            assert (Hmem_perm: Mem.perm m b ofs Cur p) by
              (unfold Mem.perm, Mem.perm_order';
                rewrite Hperm; subst; constructor);
          specialize (H3 Hmem_perm);
          unfold Mem.perm, Mem.perm_order' in H3; subst;
          rewrite Hperm' in H3;
          inversion H3; subst; auto;
          try (assert (Hp'_ord: Mem.perm m' b ofs Cur Freeable) by
              (unfold Mem.perm, Mem.perm_order'; rewrite Hperm'; constructor);
                specialize (H4 Freeable Hp'_ord); tauto).
        assert  (Hp'_ord: Mem.perm m' b ofs Cur Writable) by
            (unfold Mem.perm, Mem.perm_order'; rewrite Hperm'; constructor).
        specialize (H4 _ Hp'_ord).
        unfold Mem.perm, Mem.perm_order' in H4.
        rewrite Hperm in H4. inversion H4.
        destruct p' eqn:Hp'; auto;
        assert  (Hp'_ord: Mem.perm m' b ofs Cur p') by
            (unfold Mem.perm, Mem.perm_order'; rewrite Hperm'; subst; constructor);
        specialize (H4 _ Hp'_ord);
        unfold Mem.perm, Mem.perm_order' in H4;
        rewrite Hperm in H4; subst; inversion H4.
      }
      { exfalso.
        assert (Hmem_perm': Mem.perm m' b ofs Cur p')
          by (unfold Mem.perm, Mem.perm_order'; rewrite Hperm'; constructor).
        specialize (H4 _ Hmem_perm').
        unfold Mem.perm, Mem.perm_order' in H4;
          now rewrite Hperm in H4.
      }
      { destruct p eqn:Hp; auto;
        assert (Hnot_freeable: ~ Mem.perm m b ofs Cur Freeable)
          by
            (unfold Mem.perm, Mem.perm_order';
             rewrite Hperm; intro Hcontra; inversion Hcontra);
        specialize (H3 Hnot_freeable);
        specialize (H3 p);
        assert (Hmem_perm: Mem.perm m b ofs Cur p) by
            (unfold Mem.perm, Mem.perm_order';
             rewrite Hperm; subst; constructor);
        specialize (H3 Hmem_perm);
        unfold Mem.perm, Mem.perm_order' in *; subst;
        rewrite Hperm' in H3; tauto. }
    - specialize (H1 Hlt).
      assert (Hperm: Maps.PMap.get b (Mem.mem_access m) ofs Cur = None)
        by (now apply Mem.nextblock_noaccess).
      do 2 rewrite getCurPerm_correct. rewrite Hperm.
      clear H4.
      destruct (Maps.PMap.get b (Mem.mem_access m') ofs Cur) as [p'|] eqn:Hperm';
        auto.
      assert (Hmem_perm': Mem.perm m' b ofs Cur p')
        by (unfold Mem.perm, Mem.perm_order'; rewrite Hperm'; simpl; constructor).
      specialize (H1 _ Hmem_perm').
      assert (Hp': p' = Freeable)
        by  (unfold Mem.perm, Mem.perm_order' in H1; rewrite Hperm' in H1;
             inversion H1; auto); subst. auto.
  Qed.*)

  Definition shareMapsJoin (smap1 smap2 smap3 : share_map) : Prop :=
    forall b ofs,
      join ((Maps.PMap.get b (mkShare_map smap1)) ofs)
            ((Maps.PMap.get b (mkShare_map smap2)) ofs)
            ((Maps.PMap.get b (mkShare_map smap3)) ofs).
  
  
  Definition shareMapsJoins (smap1 smap2 : share_map) : Prop :=
    forall b ofs,
      joins ((Maps.PMap.get b (mkShare_map smap1)) ofs)
            ((Maps.PMap.get b (mkShare_map smap2)) ofs).
  
  Lemma shareMapsJoins_comm : forall smap1 smap2,
      shareMapsJoins smap1 smap2 ->
      shareMapsJoins smap2 smap1.
  Proof.
    intros smap1 smap2 Hjoin. unfold shareMapsJoins in *. intros.
    specialize (Hjoin b ofs).
    now apply joins_comm in Hjoin.
  Qed.
                       
End ShareMaps. 

(* Computation of a canonical form of permission maps where the
     default element is a function to the empty permission *)
(*
Section CanonicalPMap.

  Import Maps BlockList.
  
  Fixpoint canonicalPList l m : list (positive * (Z -> perm_kind -> option permission)) :=
    match l with
      | nil => nil
      | x :: l =>
        (Pos.of_nat x, PMap.get (Pos.of_nat x) m) :: (canonicalPList l m)
  end.
  
  Lemma canonicalPList_app :
    forall l m x,
      (canonicalPList l m) ++ ((Pos.of_nat x,
                                PMap.get (Pos.of_nat x) m) :: nil) =
      canonicalPList (l ++ (x :: nil)) m.
  Proof.
    intro l. induction l; intros.
    reflexivity.
    simpl. apply f_equal.
    auto.
  Qed.

  Lemma canonicalPList_cons :
    forall l m x,
      (Pos.of_nat x, PMap.get (Pos.of_nat x) m) :: (canonicalPList l m) =
      canonicalPList (x :: l) m.
  Proof.
    reflexivity.
  Qed.

  Lemma canonicalPList_correct :
    forall l m k v
           (HInl: List.In k l)
           (HInMap: List.In (Pos.of_nat k, v) (PTree.elements m.2)),
      List.In (Pos.of_nat k, v) (canonicalPList l m).
  Proof.
    intros l m. induction l; intros; inversion HInl.
    - subst. simpl. apply PTree.elements_complete in HInMap.
      unfold PMap.get. rewrite HInMap. now left.
    - simpl. right. auto.
  Qed.

  Lemma canonicalPList_mkBlock_complete :
    forall k v m n
           (Hk: k > 0)
           (HIn1: List.In (Pos.of_nat k, v) (canonicalPList (mkBlockList n) m)),
      List.In k (mkBlockList n).
  Proof.
    intros.
    induction n.
    simpl in *. auto.
    destruct n. simpl in HIn1. auto.
    rewrite <- mkBlockList_unfold' in HIn1.
    rewrite <- canonicalPList_cons in HIn1.
    apply List.in_inv in HIn1.
    destruct HIn1 as [Heq | HIn1].
    assert (Heqn: Pos.of_nat (S n) = Pos.of_nat k) by (inversion Heq; auto).
    apply Nat2Pos.inj_iff in Heqn.
    subst. simpl; auto.
    auto. intro Hcontra. subst. auto.
    rewrite <- mkBlockList_unfold'.
    right. auto.
  Qed.
  
  Lemma canonicalPList_mkBlock_det :
    forall n k v v' m
           (HIn1: List.In (Pos.of_nat k, v) (canonicalPList (mkBlockList n) m))
           (HIn2: List.In (Pos.of_nat k, v') (canonicalPList (mkBlockList n) m)),
      v = v'.
  Proof.
    intros n. induction n.
    - simpl. intros. exfalso. auto.
    - intros.
      destruct n. simpl in HIn1. exfalso; auto.
      destruct n. simpl in HIn1, HIn2.
      destruct HIn1 as [HIn1 | HIn1];
        destruct HIn2 as [HIn2 | HIn2];
        inversion HIn1; inversion HIn2; now subst.
      rewrite <- mkBlockList_unfold' in HIn1, HIn2.
      rewrite <- canonicalPList_cons in HIn1, HIn2.
      apply List.in_inv in HIn1.
      apply List.in_inv in HIn2.
      destruct HIn1 as [Heq1 | HIn1].
      + destruct HIn2 as [Heq2 | HIn2].
        inversion Heq1; inversion Heq2. reflexivity.
        assert (Heq:Pos.of_nat (S (S n)) = Pos.of_nat k /\ m !! (Pos.of_nat (S (S n))) = v)
          by (inversion Heq1; auto).
        destruct Heq as [HEqk Hv].
        rewrite <- HEqk in HIn2.
        exfalso.
        clear Hv HEqk Heq1 IHn v k.
        apply canonicalPList_mkBlock_complete in HIn2.
        eapply mkBlockList_not_in in HIn2; eauto. auto.
      + destruct HIn2 as [Heq | HIn2].
        assert (Heq':Pos.of_nat (S (S n)) = Pos.of_nat k) by (inversion Heq; auto).
        rewrite <- Heq' in HIn1.
        apply canonicalPList_mkBlock_complete in HIn1; auto.
        apply mkBlockList_not_in in HIn1; auto. now exfalso.
        eauto.
  Qed.
  
  Fixpoint canonicalPTree (l : list (positive * (Z -> perm_kind -> option permission))) :=
    match l with
      | nil => PTree.empty _
      | x :: l =>
        PTree.set (fst x) (snd x) (canonicalPTree l)
    end.

  Lemma canonicalPTree_elements :
    forall l x
           (Hin: List.In x (PTree.elements (canonicalPTree l))),
      List.In x l.
  Proof.
    intro l.
    induction l; intros; auto.
    simpl.
    simpl in Hin.
    unfold PTree.elements in Hin.
    destruct x as [p o].
    apply PTree.elements_complete in Hin.
    destruct (Pos.eq_dec a.1 p).
    - subst. rewrite PTree.gss in Hin. inversion Hin; subst.
      left.  destruct a; reflexivity.
    - rewrite PTree.gso in Hin; auto.
      apply PTree.elements_correct in Hin. right. auto.
  Qed.

  Lemma canonicalPTree_get_complete :
    forall l m k f
           (HGet: (canonicalPTree (canonicalPList l m)) ! k = Some f),
      List.In (k, f) (canonicalPList l m).
  Proof.
    intro l. induction l.
    simpl. intros. rewrite PTree.gempty in HGet. discriminate.
    intros.
    rewrite <- canonicalPList_cons in HGet.
    apply PTree.elements_correct in HGet.
    apply canonicalPTree_elements in HGet.
    destruct (List.in_inv HGet) as [Heq | Hin].
    inversion Heq; subst. simpl; auto.
    auto.
  Qed.
  
  Lemma canonicalPTree_get_sound :
    forall n m k
           (Hk: k > 0)
           (Hn: n > 1)
           (HGet: (canonicalPTree (canonicalPList (mkBlockList n) m)) ! (Pos.of_nat k) = None),
      ~ List.In k (mkBlockList n).
  Proof.
    intros.
    destruct n. simpl; auto.
    induction n. simpl; auto.
    intro HIn.
    rewrite <- mkBlockList_unfold' in HGet, HIn.
    destruct (List.in_inv HIn) as [? | HIn']; subst.
    rewrite <- canonicalPList_cons in HGet.
    unfold canonicalPTree in HGet. fold canonicalPTree in HGet.
    rewrite PTree.gss in HGet. discriminate.
    destruct n. simpl in *; auto.
    apply IHn. auto. rewrite <- canonicalPList_cons in HGet.
    unfold canonicalPTree in HGet. fold canonicalPTree in HGet.
    apply mkBlockList_range in HIn'.
    assert (k <> S (S n)). destruct HIn'. intros Hcontra; subst. auto. rewrite ltnn in H. auto.
    rewrite PTree.gso in HGet.
    assumption.
    intros HContra.
    unfold fst in HContra.
    apply Nat2Pos.inj_iff in HContra. auto. intros ?; subst; auto.
    intros ?; subst. discriminate.
    assumption.
  Qed.
  
  Definition canonicalPMap n m : access_map :=
    let l := mkBlockList n in
    (fun _ _ => None, canonicalPTree (canonicalPList l m)).

  Lemma canonicalPMap_sound :
    forall k n m
           (Hk : k > 0)
           (Hkn : k < n),
      m !! (Pos.of_nat k) = (canonicalPMap n m) !! (Pos.of_nat k).
  Proof.
    intros.
    unfold PMap.get.
    destruct (((canonicalPMap n m).2) ! (Pos.of_nat k)) as [f|] eqn:HGet.
    - apply PTree.elements_correct in HGet.
      unfold canonicalPMap in HGet.  simpl in HGet.
      destruct ((m.2) ! (Pos.of_nat k)) eqn:HGet'.
      + apply PTree.elements_correct in HGet'.
        apply canonicalPTree_elements in HGet.
        apply canonicalPList_correct with (l := mkBlockList n) in HGet'.
        eapply canonicalPList_mkBlock_det; eauto.
        apply canonicalPList_mkBlock_complete in HGet. assumption.
        assumption.
      + apply PTree.elements_complete in HGet.
        apply canonicalPTree_get_complete in HGet.
        induction (mkBlockList n). simpl in HGet. by exfalso.
        simpl in HGet. destruct HGet as [Heq | Hin].
        inversion Heq; subst.
        unfold PMap.get. rewrite <- H0 in HGet'. rewrite HGet'. reflexivity.
        auto.
    - unfold canonicalPMap in HGet. simpl in HGet.
      apply canonicalPTree_get_sound in HGet.
      destruct n. exfalso. auto. destruct n. exfalso. ssromega.
      exfalso. apply HGet. apply mkBlockList_include; auto.
      assumption. clear HGet.
      eapply leq_ltn_trans; eauto.
  Qed.

  Lemma canonicalPMap_default :
    forall n k m
           (Hkn : k >= n),
      (canonicalPMap n m) !! (Pos.of_nat k) = fun _ _ => None.
  Proof.
    intro. induction n; intros. unfold canonicalPMap. simpl.
    unfold PMap.get.
    rewrite PTree.gempty. reflexivity.
    assert (Hkn': n <= k) by ssromega.
    unfold canonicalPMap.
    destruct n. simpl. unfold PMap.get. simpl. rewrite PTree.gempty. reflexivity.
    unfold PMap.get.
    rewrite <- mkBlockList_unfold'. rewrite <- canonicalPList_cons.
    unfold canonicalPTree.
    rewrite PTree.gso. fold canonicalPTree.
    specialize (IHn _ m Hkn').
    unfold canonicalPMap, PMap.get, snd in IHn.
    destruct ((canonicalPTree (canonicalPList (mkBlockList n.+1) m)) ! (Pos.of_nat k)); auto.
    unfold fst. intros HContra. apply Nat2Pos.inj_iff in HContra; subst; ssromega.
  Qed.
  
  Definition canonicalPermMap (p1 : PermMap.t) : PermMap.t.
    refine ({| PermMap.next := PermMap.next p1;
               PermMap.map := canonicalPMap
                                (Pos.to_nat (PermMap.next p1)) (PermMap.map p1);
               PermMap.max := _;
               PermMap.nextblock := _
            |}).
    Proof.
      { intros.
        replace b with (Pos.of_nat (Pos.to_nat b)) by (rewrite Pos2Nat.id; done).
        destruct (leq (Pos.to_nat (PermMap.next p1)) (Pos.to_nat b)) eqn:Hbn.
          by rewrite canonicalPMap_default.
          erewrite <- canonicalPMap_sound. destruct p1. auto.
          apply/ltP/Pos2Nat.is_pos.
          ssromega. }
      { intros b ofs k H.
        replace b with (Pos.of_nat (Pos.to_nat b)) by (rewrite Pos2Nat.id; done).
        erewrite canonicalPMap_default. reflexivity.
        apply Pos.le_nlt in H.
        apply/leP.
        now apply Pos2Nat.inj_le.
      }
    Defined.

End CanonicalPMap. *)
