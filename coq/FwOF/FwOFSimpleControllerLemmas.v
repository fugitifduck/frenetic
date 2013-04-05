Set Implicit Arguments.

Require Import Coq.Lists.List.
Require Import Common.Types.
Require Import Common.Bisimulation.
Require Import Bag.TotalOrder.
Require Import Bag.Bag2.
Require Import FwOF.FwOFSignatures.
Require Import Common.Bisimulation.
Require Import Common.AllDiff.
Require FwOF.FwOFMachine.
Require FwOF.FwOFSimpleController.

Local Open Scope list_scope.
Local Open Scope bag_scope.

Module MakeController (NetAndPol : NETWORK_AND_POLICY) <: ATOMS_AND_CONTROLLER.
  Module Import Atoms := FwOF.FwOFSimpleController.Make (NetAndPol).
  Module Import Machine := FwOF.FwOFMachine.Make (Atoms).
  Require Import Bag.Bag2.

  Inductive NotPacketOut : fromController -> Prop :=
  | BarrierRequest_NotPacketOut : forall xid,
      NotPacketOut (BarrierRequest xid)
  | FlowMod_NotPacketOut : forall fm,
      NotPacketOut (FlowMod fm).

  Hint Constructors NotPacketOut NotFlowMod.

  Inductive Alternating : bool -> list fromController -> Prop :=
  | Alternating_Nil : forall b, Alternating b nil
  | Alternating_PacketOut : forall b pt pk lst,
      Alternating b lst ->
      Alternating b (PacketOut pt pk :: lst)
  | Alternating_FlowMod : forall f lst,
      Alternating true lst ->
      Alternating false (FlowMod f :: lst)
  | Alternating_BarrierRequest : forall b n lst,
      Alternating false lst ->
      Alternating b (BarrierRequest n :: lst).

  Inductive Approximating : switchId -> flowTable -> list fromController -> Prop :=
  | Approximating_Nil : forall sw tbl, Approximating sw tbl nil
  | Approximating_FlowMod : forall sw f tbl lst,
     FlowTableSafe sw (modify_flow_table f tbl) ->
     Approximating sw (modify_flow_table f tbl) lst ->
     Approximating sw tbl (lst ++ [FlowMod f])
  | Approximating_PacketOut : forall sw pt pk tbl lst,
     Approximating sw tbl lst ->
     Approximating sw tbl (lst ++ [PacketOut pt pk])
  | Approximating_BarrierRequest : forall sw n tbl lst,
     Approximating sw tbl lst ->
     Approximating sw tbl (lst ++ [BarrierRequest n]).

  Inductive Barriered : switchId -> list fromController -> flowTable  -> bag fromController_le -> Prop :=
  | Barriered_NoFlowMods : forall swId lst ctrlm tbl,
    (forall msg, In msg (to_list ctrlm) -> NotFlowMod msg) ->
    Alternating false lst ->
    Approximating swId tbl lst ->
    FlowTableSafe swId tbl ->
    Barriered swId lst tbl ctrlm
  | Barriered_OneFlowMod  : forall swId lst ctrlm f tbl,
    (forall msg, In msg (to_list ctrlm) -> NotFlowMod msg) ->
    Alternating false (lst ++ [FlowMod f]) ->
   Approximating swId tbl (lst ++ [FlowMod f]) ->
    FlowTableSafe swId tbl ->
    Barriered swId lst tbl (({|FlowMod f|}) <+> ctrlm).

  Inductive Invariant : bag switch_le ->  list openFlowLink -> controller -> Prop :=
  | MkP : forall sws ofLinks swsts pktOuts,
      AllDiff theSwId swsts ->
      (forall sw swId0 switchmLst ctrlmLst,
         In sw (to_list sws) ->
         In (OpenFlowLink swId0 switchmLst ctrlmLst) ofLinks ->
         swId sw = swId0 ->
         exists pendingMsgs,
           In (SwitchState swId0 pendingMsgs) swsts /\
           (forall msg, In msg pendingMsgs -> NotPacketOut msg) /\
           Barriered swId0 (rev pendingMsgs ++ ctrlmLst) (tbl sw) (ctrlm sw)) ->
      Invariant sws ofLinks (Atoms.State pktOuts swsts).

  Hint Constructors Invariant.

  Section Lemmas.

    Hint Constructors Alternating Approximating.

    (* We don't need alternating_push, if we precompute the sequence! *)
    Lemma alternating_pop : forall b x xs,
      Alternating b (xs ++ [x]) -> Alternating b xs.
    Proof with auto with datatypes.
      intros b x xs H.
      generalize dependent b.
      induction xs; intros...
      simpl in H.
      inversion H...
    Qed.

    Lemma alternating_fm_fm_false : forall b lst f f0,
      Alternating b ((lst ++ [FlowMod f]) ++ [FlowMod f0]) ->
      False.
    Proof with eauto with datatypes.
      intros b lst f f0 H.
      generalize dependent b.
      induction lst; intros...
      + simpl in H.
        inversion H; subst...
        inversion H2.
      + simpl in H.
        inversion H; subst...
    Qed.

    Lemma approximating_pop_FlowMod : forall sw tbl lst f,
      Approximating sw tbl (lst ++ [FlowMod f]) ->
      Approximating sw (modify_flow_table f tbl) lst.
    Proof with auto with datatypes.
      intros.
      inversion H; subst.
      + destruct lst; simpl in H3; inversion H3.
      + apply cons_tail in H0. destruct H0. inversion H2; subst...
      + apply cons_tail in H0. destruct H0. inversion H1...
      + apply cons_tail in H0. destruct H0. inversion H1...
    Qed.

    Lemma approximating_pop_BarrierRequest : forall sw tbl lst n,
      Approximating sw tbl (lst ++ [BarrierRequest n]) ->
      Approximating sw tbl lst.
    Proof with auto with datatypes.
      intros.
      inversion H; subst.
      + destruct lst; simpl in H3; inversion H3.
      + apply cons_tail in H0. destruct H0. inversion H2.
      + apply cons_tail in H0. destruct H0. inversion H1.
      + apply cons_tail in H0. destruct H0. inversion H1; subst...
    Qed.

    Lemma approximating_pop_PacketOut : forall sw tbl lst pt pk,
      Approximating sw tbl (lst ++ [PacketOut pt pk]) ->
      Approximating sw tbl lst.
    Proof with auto with datatypes.
      intros.
      inversion H; subst.
      + destruct lst; simpl in H3; inversion H3.
      + apply cons_tail in H0. destruct H0. inversion H2.
      + apply cons_tail in H0. destruct H0. inversion H1; subst...
      + apply cons_tail in H0. destruct H0. inversion H1.
    Qed.

    Lemma approximating_pop_FlowMod_safe : forall sw tbl lst f,
      Approximating sw tbl (lst ++ [FlowMod f]) ->
      FlowTableSafe sw (modify_flow_table f tbl).
    Proof with auto with datatypes.
      intros sw tbl lst f H.
      inversion H; subst.
      + destruct lst; simpl in H3; inversion H3.
      + apply cons_tail in H0. destruct H0. inversion H2; subst...
      + apply cons_tail in H0. destruct H0. inversion H1...
      + apply cons_tail in H0. destruct H0. inversion H1...
    Qed.

    Lemma Barriered_entails_FlowModSafe : forall swId lst tbl ctrlm,
      Barriered swId lst tbl ctrlm ->
      FlowModSafe swId tbl ctrlm.
    Proof with eauto with datatypes.
      intros.
      inversion H; subst...
      + eapply NoFlowModsInBuffer...
      + eapply OneFlowModsInBuffer...
        inversion H2; subst...
        - destruct lst; simpl in H7; inversion H7.
        - apply cons_tail in H4.
          destruct H4; subst.
          inversion H6; subst...
        - apply cons_tail in H4.
          destruct H4.
          inversion H5.
        - apply cons_tail in H4.
          destruct H4.
          inversion H5.
    Qed.

    Lemma barriered_pop_BarrierRequest : forall swId xid lst tbl ctrlm,
      Barriered swId (lst ++ [BarrierRequest xid]) tbl ctrlm ->
      (forall msg, In msg (to_list ctrlm) -> NotFlowMod msg) ->
      Barriered swId lst tbl ctrlm.
    Proof with eauto with datatypes.
      intros.
      rename H0 into X.
      inversion H; subst.
      + apply Barriered_NoFlowMods...
        apply alternating_pop in H1...
        apply approximating_pop_BarrierRequest in H2...
      + assert (NotFlowMod (FlowMod f)).
        apply X.
        apply Bag.in_union; simpl...
        inversion H4.
    Qed.

    Lemma alternating_splice_PacketOut : forall b lst1 pt pk lst2,
      Alternating b (lst1 ++ PacketOut pt pk :: lst2) <->
      Alternating b (lst1 ++ lst2).
    Proof with auto with datatypes.
      intros b lst1 pt pk lst2.
      split.
      + intros H.
        generalize dependent b.
        induction lst1; intros; simpl in *; inversion H...
      + intros H.
        generalize dependent b.
        induction lst1; intros...
        - simpl in *...
        - simpl in *.
          inversion H; subst...
    Qed.

    Hint Resolve alternating_pop approximating_pop_PacketOut approximating_pop_FlowMod
         approximating_pop_BarrierRequest.

    Lemma approximating_splice_PacketOut : forall sw tbl lst1 pt pk lst2,
      Approximating sw tbl (lst1 ++ PacketOut pt pk :: lst2) <->
      Approximating sw tbl (lst1 ++ lst2).
    Proof with eauto with datatypes.
      intros sw tbl lst1 pt pk lst2.
      split.
      + intros H.
        generalize dependent tbl.
        induction lst2 using rev_ind; intros.
        - rewrite -> app_nil_r...
        - rewrite -> app_comm_cons in H.
          rewrite -> app_assoc in H.
          rewrite -> app_assoc.
          destruct x...
          assert (FlowTableSafe sw (modify_flow_table f tbl0)).
          { eapply approximating_pop_FlowMod_safe... }
          eauto.
      + intros H.
        generalize dependent tbl.
        induction lst2 using rev_ind; intros.
        - rewrite -> app_nil_r in H...
        - rewrite -> app_comm_cons.
          rewrite -> app_assoc.
          rewrite -> app_assoc in H.
          destruct x...
          assert (FlowTableSafe sw (modify_flow_table f tbl0)) as X...
          { eapply approximating_pop_FlowMod_safe... }
      Grab Existential Variables.
      exact 0.
    Qed.

    Hint Resolve alternating_splice_PacketOut approximating_splice_PacketOut.

    Lemma barriered_pop_PacketOut : forall sw pt pk lst tbl ctrlm,
      Barriered sw (lst ++ [PacketOut pt pk]) tbl ctrlm ->
      Barriered sw lst tbl (({|Atoms.PacketOut pt pk|}) <+> ctrlm).
    Proof with eauto with datatypes.
      intros sw pt pk lst tbl ctrlm H.
      inversion H; subst.
      + apply Barriered_NoFlowMods...
        - intros.
          apply Bag.in_union in H4; simpl in H4.
          destruct H4 as [[H4 | H4] | H4]; subst...
          inversion H4.
      + rewrite <-  Bag.union_assoc.
        rewrite <- (Bag.union_comm _ ({|FlowMod f|})).
        rewrite -> Bag.union_assoc.
        apply Barriered_OneFlowMod...
        - intros.
          apply Bag.in_union in H4; simpl in H4.
          destruct H4 as [[H4 | H4] | H4]; subst...
          inversion H4.
        - rewrite <- app_assoc in H1.
          simpl in H1.
          apply alternating_splice_PacketOut in H1...
        - rewrite <- app_assoc in H2.
          simpl in H2.
          apply approximating_splice_PacketOut in H2...
          Grab Existential Variables. exact 0.
    Qed.

    Lemma barriered_splice_PacketOut : forall sw lst1 pt pk lst2 tbl ctrlm,
      Barriered sw (lst1 ++ lst2) tbl ctrlm ->
      Barriered sw (lst1 ++ PacketOut pt pk :: lst2) tbl ctrlm.
    Proof with eauto with datatypes.
      intros sw lst1 pt pk lst2 tbl ctrlm H.
      inversion H; subst.
      + eapply Barriered_NoFlowMods...
        - eapply alternating_splice_PacketOut...
        - eapply approximating_splice_PacketOut...
      + eapply Barriered_OneFlowMod...
        - rewrite <- app_assoc.
          rewrite <- app_comm_cons.
          apply alternating_splice_PacketOut...
          rewrite -> app_assoc...
        - rewrite <- app_assoc.
          rewrite <- app_comm_cons.
          apply approximating_splice_PacketOut...
          rewrite -> app_assoc...
    Qed.

    Lemma barriered_process_PacketOut : forall sw lst tbl pt pk ctrlm,
      Barriered sw lst tbl (({|PacketOut pt pk|}) <+> ctrlm) ->
      Barriered sw lst tbl ctrlm.
    Proof with eauto with datatypes.
      intros.
      inversion H; subst.
      + eapply Barriered_NoFlowMods...
        intros. apply H0. apply Bag.in_union...
      + apply Bag.union_from_ordered in H0.
        assert (In (FlowMod f) (to_list ctrlm0)) as J.
        { assert (In (FlowMod f) (to_list (({|PacketOut pt pk|}) <+> ctrlm0))) as J.
          rewrite <- H0. apply Bag.in_union; simpl...
          apply Bag.in_union in J. simpl in J.
          destruct J as [[J|J]|J]...
          + inversion J.
          + inversion J. }
        eapply Bag.in_split in J.
        destruct J as [ctrlm2 HEq].
        rewrite -> HEq.
        eapply Barriered_OneFlowMod...
        intros.
        subst.
        rewrite <- Bag.union_assoc in H0.
        rewrite -> (Bag.union_comm _ ({|PacketOut pt pk|})) in H0.
        rewrite -> Bag.union_assoc in H0.
        apply Bag.pop_union_l in H0.
        subst.
        eapply H1.
        apply Bag.in_union...
    Qed.

    Lemma barriered_pop_FlowMod : forall sw f tbl lst ctrlm,
      (forall x, In x (to_list ctrlm) -> NotFlowMod x) ->
      Barriered sw (lst ++ [FlowMod f]) tbl ctrlm ->
      Barriered sw lst tbl (({|FlowMod f|}) <+> ctrlm).
    Proof with eauto with datatypes.
      intros sw f tbl lst ctrlm H H0.
      inversion H0; subst.
      + apply Barriered_OneFlowMod...
      + assert (NotFlowMod (FlowMod f0)) as X.
        apply H. apply Bag.in_union; simpl...
        inversion X.
    Qed.

  End Lemmas.

  Hint Resolve alternating_pop Barriered_entails_FlowModSafe approximating_pop_FlowMod.

  (* Also need to show that messages can be popped off. *)
  Lemma P_entails_FlowTablesSafe : forall sws ofLinks ctrl,
    Invariant sws ofLinks ctrl ->
    SwitchesHaveOpenFlowLinks sws ofLinks ->
    FlowTablesSafe sws.
  Proof with eauto with datatypes.
    intros.
    unfold FlowTablesSafe.
    intros.
    inversion H; subst.
    edestruct H0 as [lnk [HIn HIdEq]]...
    simpl...
    destruct lnk.
    simpl in HIdEq. subst...
    rename of_to0 into swId0.
    inversion H; subst...
    edestruct H3 as [pendingMsgs [J [J0 J1]]]...
  Qed.

  Lemma controller_recv_pres_P : forall sws ofLinks0 ofLinks1
    ctrl0 ctrl1 swId msg switchm ctrlm,
    Recv ctrl0 swId msg ctrl1 ->
    Invariant sws
              (ofLinks0 ++ (OpenFlowLink swId (switchm ++ [msg]) ctrlm) :: ofLinks1)
              ctrl0 ->
    Invariant sws 
              (ofLinks0 ++ (OpenFlowLink swId switchm ctrlm) :: ofLinks1)
              ctrl1.
  Proof with eauto with datatypes.
    intros.
    inversion H; subst.
    + inversion H0; subst.
      eapply MkP...
      intros.
      apply in_app_iff in H4. simpl in H4.
      destruct H4 as [H4 | [H4 | H4]]...
      inversion H4; subst; clear H4.
      edestruct H2 as [msgs [HInSw [HNotPktOuts HBarriered]]]...
    + inversion H0; subst.
      eapply MkP...
      intros.
      eapply in_app_iff in H2; simpl in H2.
      destruct H2 as [H2 | [H2 | H2]]...
      inversion H2; subst; clear H2...
  Qed.

  Lemma controller_send_pres_P : forall sws ofLinks0 ofLinks1
    ctrl0 ctrl1 swId0 msg switchm ctrlm,
    Send ctrl0 ctrl1 swId0 msg  ->
    AllDiff of_to (ofLinks0 ++ (OpenFlowLink swId0 switchm ctrlm) :: ofLinks1) ->
    AllDiff swId (to_list sws) ->
    Invariant sws
              (ofLinks0 ++ (OpenFlowLink swId0 switchm ctrlm) :: ofLinks1)
              ctrl0 ->
    Invariant sws 
              (ofLinks0 ++ (OpenFlowLink swId0 switchm (msg :: ctrlm)) :: ofLinks1)
              ctrl1.
  Proof with eauto with datatypes.
    intros sws ofLinks0 ofLinks1 ctrl0 ctrl1 swId0 msg switchm0 ctrlm0 H Hdiff HdiffSws H0.
    inversion H; subst.
    + inversion H0; subst.
      eapply MkP...
      intros.
      apply in_app_iff in H2; simpl in H2.
      destruct H2 as [H2 | [H2 | H2]]...
      inversion H2; subst.
      edestruct H6 as [pendingMsgs [HIn [HNotPktOuts HBarriered]]]...
      exists pendingMsgs.
      split...
      split...
      apply barriered_splice_PacketOut...
    + inversion H0; subst.
      eapply MkP.
      eapply AllDiff_preservation...
      do 2 rewrite -> map_app...
      intros.
      destruct (eqdec swId1 swId0)...
      - destruct sw; simpl in *; subst...
        assert (AllDiff of_to (ofLinks0 ++ OpenFlowLink swId0 switchm0 (msg::ctrlm0) :: ofLinks1)) as Hdiff0.
        { eapply AllDiff_preservation... do 2 rewrite -> map_app... }
        assert (OpenFlowLink swId0 switchmLst ctrlmLst  = OpenFlowLink swId0 switchm0 (msg::ctrlm0)).
        { eapply AllDiff_uniq... }
        inversion H3; subst; clear H3.
        edestruct H6 as [pendingMsgs [HIn [HNotPktOuts HBarriered]]]...
        assert (msg :: msgs = pendingMsgs) as X.
        { assert (SwitchState swId0 (msg::msgs) = SwitchState swId0 pendingMsgs).
          eapply AllDiff_uniq...
          inversion H3; subst... }
        inversion X; subst.
        simpl in *.
        exists msgs...
        split...
        split...
        rewrite <- app_assoc in HBarriered.
        simpl in HBarriered...
      - destruct sw; subst; simpl in *.
        apply in_app_iff in H2; simpl in H2.
        { destruct H2 as [H2|[H2|H2]].
          + edestruct H6 with (swId1 := swId2) as [pendingMsgs [HIn [HNotPktOuts HBarriered]]]...
            simpl in *.
            exists pendingMsgs...
            split...
            apply in_app_iff in HIn; simpl in HIn.
            destruct HIn as [HIn|[HIn|HIn]]...
            inversion HIn; subst.
            contradiction n...
          + inversion H2; subst.
            contradiction n...
          + edestruct H6 with (swId1 := swId2) as [pendingMsgs [HIn [HNotPktOuts HBarriered]]]...
            simpl in *.
            exists pendingMsgs...
            split...
            apply in_app_iff in HIn; simpl in HIn.
            destruct HIn as [HIn|[HIn|HIn]]...
            inversion HIn; subst.
            contradiction n... }
  Qed.

  Lemma controller_step_pres_P : forall sws ofLinks ctrl0 ctrl1,
    Step ctrl0 ctrl1 ->
    Invariant sws ofLinks ctrl0 ->
    Invariant sws ofLinks ctrl1.
  Proof.
    intros.
    inversion H.
  Qed.

  Local Open Scope bag_scope.
  Hint Constructors NotFlowMod.

  Lemma Invariant_ofLink_vary : forall sws swId switchm0 switchm1 ctrlm 
                                   ofLinks0 ofLinks1 ctrl,
    Invariant sws 
              (ofLinks0 ++ OpenFlowLink swId switchm0 ctrlm :: ofLinks1)
              ctrl ->
    Invariant sws 
              (ofLinks0 ++ OpenFlowLink swId switchm1 ctrlm :: ofLinks1)
              ctrl.
  Proof with eauto with datatypes.
    intros.
    inversion H; subst.
    eapply MkP...
    intros.
    apply in_app_iff in H3; simpl in H2.
    destruct H3 as [H3 | [H3 | H3]]...
    destruct sw. simpl in *. subst.
    inversion H3; clear H3; subst...
    edestruct H1 as [pendingMsgs0 [HIn [HNotPktOuts HBarriered]]]...
  Qed.

  Lemma Invariant_sw_vary : forall swId pts tbl inp outp cms sms sws
                                   ofLinks ctrl inp' outp' sms',
    Invariant (({|Switch swId pts tbl inp outp cms sms|}) <+> sws)
              ofLinks
              ctrl ->
    Invariant (({|Switch swId pts tbl inp' outp' cms sms'|}) <+> sws)
              ofLinks
              ctrl.
  Proof with eauto with datatypes.
    intros.
    inversion H; subst.
    eapply MkP...
    intros.
    apply Bag.in_union in H2; simpl in H2.
    destruct H2 as [[H2 | H2] | H2]...
    - subst. simpl in *.
      remember (Switch swId0 pts0 tbl0 inp0 outp0 cms sms) as sw.
      assert (swId0 = swId sw) as X.
      { subst. simpl... }
      edestruct H1 as [msgs [HIn [HNotPktOuts HBarriered]]]...
      { apply Bag.in_union. left. simpl... }
      exists msgs...
      split...
      split...
      destruct sw; subst; simpl in *.
      inversion Heqsw; subst...
    - inversion H2.
    - destruct sw. simpl in *; subst.
      edestruct H1 as [msgs [HIn [HNotPktOuts HBarriered]]]...
      { apply Bag.in_union. right... }
      simpl...
      exists msgs...
  Qed.

  Lemma step_preserves_P : forall sws0 sws1 links0 links1 ofLinks0 ofLinks1 
    ctrl0 ctrl1 obs,
    AllDiff of_to ofLinks0 ->
    AllDiff swId (to_list sws0) ->
    step (State sws0 links0 ofLinks0 ctrl0)
         obs
         (State sws1 links1 ofLinks1 ctrl1) ->
    Invariant sws0 ofLinks0 ctrl0 ->
    Invariant sws1 ofLinks1 ctrl1.
  Proof with eauto with datatypes.
    intros sws0 sws1 links0 links1 ofLinks0 ofLinks1 ctrl0 ctrl1 obs HdiffOfLinks HdiffSws H H0.
    destruct ctrl1.
    inversion H0; subst.
    rename H0 into HInvariant.
    inversion H; subst.
    + eapply Invariant_sw_vary...
    + eapply MkP...
      intros.
      apply Bag.in_union in H0; simpl in H0.
      destruct H0 as [[H0 | H0] | H0]...
      - subst; simpl in *.
        edestruct H2 as [msgs [HIn [HNotPktOuts HBarriered]]]...
        apply Bag.in_union. simpl. left. left. reflexivity. simpl...
        simpl in *.
        inversion HBarriered; subst.
        * assert (NotFlowMod (FlowMod fm)) as X.
          apply H0.
          apply Bag.in_union; simpl...
          inversion X.
        * exists msgs...
          split...
          split...
          apply Bag.union_from_ordered in H0.
          assert (FlowMod fm = FlowMod f /\ ctrlm0 = ctrlm1) as HEq.
          { eapply Bag.singleton_union_disjoint.
            symmetry...
            intros. 
            assert (NotFlowMod (FlowMod fm)) as X...
            inversion X. }
          destruct HEq as [HEq HEq0].
          inversion HEq; subst.
          eapply Barriered_NoFlowMods...
          apply approximating_pop_FlowMod_safe in H6...
      - inversion H0.
      - subst; simpl in *.
        edestruct H2 as [msgs [HIn [HNotPktOuts HBarriered]]]...
        apply Bag.in_union...
    + (* processing a packet produces ctrlm messges. *)
      eapply MkP...
      intros.
      destruct sw.
      simpl in *.
      subst.
      apply Bag.in_union in H0. simpl in H0.
      destruct H0 as [[H0|H0]|H0]...
      - subst. simpl in *.
        inversion H0; subst...
        edestruct H2 as [msgs [HIn [HNotPktOuts HBarriered]]]...
        simpl.
        apply Bag.in_union. left. simpl. left. reflexivity.
        simpl...
        eexists msgs...
        split...
        split...
        simpl in HBarriered...
        eapply barriered_process_PacketOut...
    - inversion H0.
    - edestruct H2 as [msgs [HIn [HNotPktOuts HBarriered]]]...
      { apply Bag.in_union. right... }
      simpl...
      exists msgs...
    + eapply Invariant_sw_vary...
    + eapply Invariant_sw_vary...
    + eapply controller_step_pres_P...
    + eapply controller_recv_pres_P...
    + eapply controller_send_pres_P...
    + eapply Invariant_sw_vary...
      eapply Invariant_ofLink_vary...
    + eapply MkP...
      intros.
      destruct sw; subst; simpl in *.
      destruct (TotalOrder.eqdec swId0 swId2).
      - subst.
        assert (OpenFlowLink swId2 switchmLst ctrlmLst = 
                OpenFlowLink swId2 fromSwitch0 fromCtrl) as X.
        { assert (AllDiff of_to (ofLinks2 ++ OpenFlowLink swId2 fromSwitch0 fromCtrl :: ofLinks3)).
          eapply AllDiff_preservation...
          do 2 rewrite -> map_app...
          eapply AllDiff_uniq... }
        inversion X; clear H2; subst; clear X.
        assert (Switch swId2 pts0 tbl0 inp0 outp0 ({||}) (({|BarrierReply xid|})<+>switchm0) =
                Switch swId2 pts1 tbl1 inp1 outp1 ctrlm0 switchm1) as X.
        { assert (AllDiff swId (to_list (({|Switch swId2 pts0 tbl0 inp0 outp0 ({||}) ({|BarrierReply xid|} <+> switchm0)|}) <+> sws))). 
          { eapply Bag.AllDiff_preservation... }
          clear HdiffSws.
          eapply AllDiff_uniq...
          apply Bag.in_union; simpl... }
        inversion X; clear H0; subst; clear X.
        inversion HInvariant; subst.
        edestruct H7 as [msgs [HIn [HNotPktOuts HBarriered]]]...
        { apply Bag.in_union. left. simpl. left. reflexivity. }
        { simpl... }
        simpl in *.
        exists msgs...
        split...
        split...
        eapply barriered_pop_BarrierRequest...
        rewrite -> app_assoc in HBarriered...
        intros.
        simpl in H0.
        inversion H0.
      - apply Bag.in_union in H0; simpl in H0.
        destruct H0 as [[H0|H0]|H0].
        * inversion H0; subst. contradiction n...
        * inversion H0.
        * edestruct H2 with (swId1:=swId2) as [msgs [HIn [HNotPktOuts HBarriered]]]...
          apply Bag.in_union...
          apply in_app_iff in H3; simpl in H3.
          destruct H3 as [H3|[H3|H3]]...
          inversion H3; subst; contradiction n...
          simpl...
          exists msgs...
    + eapply MkP...
      intros.
      destruct sw; subst; simpl in *.
      destruct (TotalOrder.eqdec swId0 swId2).
      - subst.
        assert (OpenFlowLink swId2 switchmLst ctrlmLst = 
                OpenFlowLink swId2 fromSwitch0 fromCtrl) as X.
        { assert (AllDiff of_to (ofLinks2 ++ OpenFlowLink swId2 fromSwitch0 fromCtrl :: ofLinks3)).
          eapply AllDiff_preservation...
          do 2 rewrite -> map_app...
          eapply AllDiff_uniq... }
        inversion X; clear H2; subst; clear X.
        assert (Switch swId2 pts1 tbl1 inp1 outp1 ctrlm1 switchm1 =
                Switch swId2 pts0 tbl0 inp0 outp0 ({|msg|} <+> ctrlm0) switchm0) as X.
        { assert (AllDiff swId (to_list (({|Switch swId2 pts0 tbl0 inp0 outp0 (({|msg|})<+> ctrlm0) switchm0|}) <+> sws))).
          { eapply Bag.AllDiff_preservation... }
          clear HdiffSws.
          eapply AllDiff_uniq...
          apply Bag.in_union; simpl... }
        inversion X; clear H0; subst; clear X.
        inversion HInvariant; subst.
        edestruct H8 as [msgs [HIn [HNotPktOuts HBarriered]]]...
        { apply Bag.in_union. left. simpl. left. reflexivity. }
        { simpl... }
        simpl in *.
        exists msgs...
        split...
        split...
        destruct msg.
        * eapply barriered_pop_PacketOut...
          rewrite -> app_assoc in HBarriered...
        * inversion H7.
        * { inversion HBarriered; subst.
            + eapply barriered_pop_FlowMod...
              rewrite <- app_assoc...
            + clear H HInvariant H1.  move H2 after HBarriered.
              rewrite -> app_assoc in H2.
              apply alternating_fm_fm_false in H2.
              inversion H2.
          }
      - intros.
        apply Bag.in_union in H0; simpl in H0.
        destruct H0 as [[H0|H0]|H0].
        * inversion H0; subst. contradiction n...
        * inversion H0.
        * edestruct H2 with (swId1:=swId2) as [msgs [HIn [HNotPktOuts HBarriered]]]...
          apply Bag.in_union...
          apply in_app_iff in H3; simpl in H3.
          destruct H3 as [H3|[H3|H3]]...
          inversion H3; subst; contradiction n...
          simpl...
          exists msgs...
  Qed.

  Definition relate_helper (sd : srcDst) : swPtPks :=
    match topo (pkSw sd,dstPt sd) with
      | None => {| |}
      | Some (sw',pt') => {| (sw',pt',dstPk sd) |}
    end.

  Definition relate_controller (st : controller) := 
    unions (map relate_helper (pktsToSend st)).

  Lemma ControllerRemembersPackets :
    forall (ctrl ctrl' : controller),
      controller_step ctrl ctrl' ->
      relate_controller ctrl = relate_controller ctrl'.
  Proof with auto.
    intros. inversion H.
  Qed.

  Lemma ControllerSendForgetsPackets : forall ctrl ctrl' sw msg,
    controller_send ctrl ctrl' sw msg ->
    relate_controller ctrl = select_packet_out sw msg <+>
    relate_controller ctrl'.
  Proof with auto.
    intros.
    inversion H; subst.
    + unfold relate_controller.
      simpl.
      unfold relate_helper.
      simpl.
      rewrite -> Bag.unions_cons.
      reflexivity.
    + simpl.
      unfold relate_controller.
      simpl.
      { destruct msg.
        - idtac "TODO(arjun): Cannot pre-emit packetouts (need P here).".
          admit.
        - simpl. rewrite -> Bag.union_empty_l...
        - simpl. rewrite -> Bag.union_empty_l... }
  Qed.

  Lemma like_transfer : forall srcPt srcPk sw ptpk,
    relate_helper (mkPktOuts_body sw srcPt srcPk ptpk) =
    transfer sw ptpk.
  Proof with auto.
    intros.
    unfold mkPktOuts_body.
    unfold relate_helper.
    unfold transfer.
    destruct ptpk.
    simpl.
    reflexivity.
  Qed.

  Lemma like_transfer_abs : forall sw pt pk lst,
    map
      (fun x : portId * packet => relate_helper (mkPktOuts_body sw pt pk x))
      lst =
    map (transfer sw) lst.
  Proof with auto.
    intros.
    induction lst...
    simpl.
    rewrite -> like_transfer.
    rewrite -> IHlst.
    reflexivity.
  Qed.

  Lemma ControllerRecvRemembersPackets : forall ctrl ctrl' sw msg,
    controller_recv ctrl sw msg ctrl' ->
    relate_controller ctrl' = select_packet_in sw msg <+> 
    (relate_controller ctrl).
  Proof with auto.
    intros.
    inversion H; subst.
    (* receive barrierreply *)
    unfold relate_controller.
    simpl. 
    rewrite -> Bag.union_empty_l...
    (* case packetin *)
    unfold relate_controller.
    simpl.
    rewrite -> map_app.
    rewrite -> Bag.unions_app.
    apply Bag.pop_union_r.
    unfold mkPktOuts.
    rewrite -> map_map.
    rewrite -> like_transfer_abs...
  Qed.
  
  Definition P := Invariant.

  Axiom ControllerLiveness : forall sw pt pk ctrl0 sws0 links0 
                                        ofLinks0,
    In (sw,pt,pk) (to_list (relate_controller ctrl0)) ->
    exists  ofLinks10 ofLinks11 ctrl1 swTo ptTo switchmLst ctrlmLst,
      (multistep 
         step (State sws0 links0 ofLinks0 ctrl0) nil
         (State sws0 links0
                (ofLinks10 ++ 
                 (OpenFlowLink swTo switchmLst 
                  (PacketOut ptTo pk :: ctrlmLst)) ::
                 ofLinks11) 
                ctrl1)) /\
      select_packet_out swTo (PacketOut ptTo pk) = ({|(sw,pt,pk)|}).
  (* Idiotic pre-conditions needed. 
    Proof with auto with datatypes.
      intros.
      destruct ctrl0.
      unfold relate_controller in H.
      simpl in H.
      apply Bag.in_unions in H.
      destruct H as [b [HBagIn HpkIn]].
      apply in_map_iff in HBagIn.
      destruct HBagIn as [srcDst0 [Hhelper HtoSend]].
      destruct srcDst0.
      unfold relate_helper in Hhelper.
      simpl in Hhelper.
      destruct (topo
      *)

  Lemma ControllerRecvLiveness : forall sws0 links0 ofLinks0 sw switchm0 m 
    ctrlm0 ofLinks1 ctrl0,
     exists ctrl1,
      (multistep 
         step
         (State 
            sws0 links0 
            (ofLinks0 ++ (OpenFlowLink sw (switchm0 ++ [m]) ctrlm0) :: ofLinks1)
            ctrl0)
         nil
         (State 
            sws0 links0 
            (ofLinks0 ++ (OpenFlowLink sw switchm0 ctrlm0) :: ofLinks1)
            ctrl1)) /\
       exists (lps : swPtPks),
         (select_packet_in sw m) <+> lps = relate_controller ctrl1.
  Proof with eauto with datatypes.
    intros.
    destruct ctrl0.
    destruct m.
    + eexists.
      split.
      eapply multistep_tau.
      apply ControllerRecv.
      apply RecvPacketIn.
      apply multistep_nil.
      exists (relate_controller (Atoms.State pktsToSend0 switchStates0)).
      simpl.
      unfold relate_controller.
      simpl.
      autorewrite with bag using simpl.
      unfold mkPktOuts.
      rewrite -> map_map.
      rewrite -> like_transfer_abs...
    + eexists.
      split.
      eapply multistep_tau.
      apply ControllerRecv.
      apply RecvBarrierReply.
      apply multistep_nil.
      simpl.
      eexists.
      rewrite -> Bag.union_empty_l.
      reflexivity.
  Qed.

End MakeController.