(*
 * Copyright 2020, Data61, CSIRO (ABN 41 687 119 230)
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *)

(* Reader option monad syntax plus the connection between the reader option monad and the nondet monad *)

theory Reader_Option_ND
imports
  Nondet_Lemmas
  Reader_Option_Monad
begin

(* FIXME: remove this syntax, standardise on do {..} instead *)
(* Syntax defined here so we can reuse Nondet_Monad definitions *)
syntax
  "_doO" :: "[dobinds, 'a] => 'a"  ("(DO (_);//   (_)//OD)" 100)

translations
  "_doO (_dobinds b bs) e" == "_doO b (_doO bs e)"
  "_doO (_nobind b) e"     == "b |>> (CONST K_bind e)"
  "DO x <- a; e OD"        == "a |>> (\<lambda>x. e)"


lemma ogets_def:
  "ogets f = (\<lambda>s. Some (f s))"
  by (clarsimp simp: asks_def obind_def)

definition
  ocatch :: "('s,('e + 'a)) lookup \<Rightarrow> ('e \<Rightarrow> ('s,'a) lookup) \<Rightarrow> ('s, 'a) lookup"
  (infix "<ocatch>" 10)
where
  "f <ocatch> handler \<equiv> do {
     x \<leftarrow> f;
     case x of Inr b \<Rightarrow> oreturn b | Inl e \<Rightarrow> handler e
   }"


definition
  odrop :: "('s, 'e + 'a) lookup \<Rightarrow> ('s, 'a) lookup"
where
  "odrop f \<equiv> do {
     x \<leftarrow> f;
     case x of Inr b \<Rightarrow> oreturn b | Inl e \<Rightarrow> ofail
   }"

definition
  osequence_x :: "('s, 'a) lookup list \<Rightarrow> ('s, unit) lookup"
where
  "osequence_x xs \<equiv> foldr (\<lambda>x y. do { x; y }) xs (oreturn ())"

definition
  osequence :: "('s, 'a) lookup list \<Rightarrow> ('s, 'a list) lookup"
where
  "osequence xs \<equiv> let mcons = (\<lambda>p q. p |>> (\<lambda>x. q |>> (\<lambda>y. oreturn (x#y))))
                 in foldr mcons xs (oreturn [])"

definition
  omap :: "('a \<Rightarrow> ('s,'b) lookup) \<Rightarrow> 'a list \<Rightarrow> ('s, 'b list) lookup"
where
  "omap f xs \<equiv> osequence (map f xs)"

definition
  opt_cons :: "'a option \<Rightarrow> 'a list \<Rightarrow> 'a list" (infixr "o#" 65)
where
  "opt_cons x xs \<equiv> case x of None \<Rightarrow> xs | Some x' \<Rightarrow> x' # xs"

lemmas monad_simps =
  gets_the_def bind_def assert_def assert_opt_def
  simpler_gets_def fail_def return_def

lemma gets_the_opt_map:
  "gets_the (f |> g) = do x \<leftarrow> gets_the f; assert_opt (g x) od"
  by (rule ext) (simp add: monad_simps opt_map_def split: option.splits)

lemma gets_the_opt_o:
  "gets_the (f |> Some o g) = do x \<leftarrow> gets_the f; return (g x) od"
  by (simp add: gets_the_opt_map assert_opt_Some)

lemma gets_the_obind:
  "gets_the (f |>> g) = gets_the f >>= (\<lambda>x. gets_the (g x))"
  by (rule ext) (simp add: monad_simps obind_def split: option.splits)

lemma gets_the_return:
  "gets_the (oreturn x) = return x"
  by (simp add: monad_simps oreturn_def)

lemma gets_the_fail:
  "gets_the ofail = fail"
  by (simp add: monad_simps ofail_def)

lemma gets_the_ogets:
  "gets_the (ogets s) = gets s"
  by (clarsimp simp: monad_simps ogets_def)

lemma gets_the_returnOk:
  "gets_the (oreturnOk x) = returnOk x"
  by (simp add: monad_simps oreturnOk_def returnOk_def)

lemma gets_the_throwError:
  "gets_the (othrow e) = throwError e"
  by (simp add: monad_simps othrow_def throwError_def)

lemma gets_the_assert:
  "gets_the (oassert P) = assert P"
  by (simp add: oassert_def assert_def gets_the_fail gets_the_return)

lemma gets_the_if_distrib:
  "gets_the (if P then f else g) = (if P then gets_the f else gets_the g)"
  by simp

lemma gets_the_oapply_comp:
  "gets_the (oapply x \<circ> f) = gets_map f x"
  by (fastforce simp: gets_map_def gets_the_def o_def gets_def)

lemma gets_the_Some:
  "gets_the (\<lambda>_. Some x) = return x"
  by (simp add: gets_the_def assert_opt_Some)

lemma gets_the_oapply2_comp:
  "gets_the (oapply2 y x \<circ> f) = gets_map (swp f y) x"
  by (clarsimp simp: gets_map_def gets_the_def o_def gets_def)

lemma gets_obind_bind_eq:
  "(gets (f |>> (\<lambda>x. g x))) =
   (gets f >>= (\<lambda>x. case x of None \<Rightarrow> return None | Some y \<Rightarrow> gets (g y)))"
  by (auto simp: simpler_gets_def bind_def obind_def return_def split: option.splits)

lemma fst_assert_opt:
  "fst (assert_opt opt s) = (if opt = None then {} else {(the opt,s)})"
  by (clarsimp simp: assert_opt_def fail_def return_def split: option.split)


lemmas omonad_simps [simp] =
  gets_the_opt_map assert_opt_Some gets_the_obind
  gets_the_return gets_the_fail gets_the_returnOk
  gets_the_throwError gets_the_assert gets_the_Some
  gets_the_oapply_comp

lemmas in_omonad = bind_eq_Some_conv in_obind_eq in_opt_map_eq in_opt_pred Let_def


section "Relation between option monad loops and non-deterministic monad loops."

(* Option monad whileLoop formalisation thanks to Lars Noschinski <noschinl@in.tum.de>. *)

lemma gets_the_conv:
  "(gets_the B s) = (case B s of Some r' \<Rightarrow> ({(r', s)}, False) | _ \<Rightarrow> ({}, True))"
  by (auto simp: gets_the_def gets_def get_def bind_def return_def fail_def assert_opt_def split: option.splits)

lemma gets_the_loop_terminates:
  "whileLoop_terminates C (\<lambda>a. gets_the (B a)) r s
    \<longleftrightarrow> (\<exists>rs'. (Some r, rs') \<in> option_while' (\<lambda>a. C a s) (\<lambda>a. B a s))" (is "?L \<longleftrightarrow> ?R")
proof
  assume ?L then show ?R
  proof (induct rule: whileLoop_terminates.induct[case_names 1 2])
    case (2 r s) then show ?case
      by (cases "B r s") (auto simp: gets_the_conv intro: option_while'.intros)
  qed (auto intro: option_while'.intros)
next
  assume ?R then show ?L
  proof (elim exE)
    fix rs' assume "(Some r, rs') \<in> option_while' (\<lambda>a. C a s) (\<lambda>a. B a s)"
    then have "whileLoop_terminates C (\<lambda>a. gets_the (B a)) (the (Some r)) s"
      by induct (auto intro: whileLoop_terminates.intros simp: gets_the_conv)
    then show ?thesis by simp
  qed
qed

lemma gets_the_whileLoop:
  fixes C :: "'a \<Rightarrow> 's \<Rightarrow> bool"
  shows "whileLoop C (\<lambda>a. gets_the (B a)) r = gets_the (owhile C B r)"
proof -
  { fix r s r' s' assume "(Some (r,s), Some (r', s')) \<in> whileLoop_results C (\<lambda>a. gets_the (B a))"
    then have "s = s' \<and> (Some r, Some r') \<in> option_while' (\<lambda>a. C a s) (\<lambda>a. B a s)"
    by (induct "Some (r, s)" "Some (r', s')" arbitrary: r s)
       (auto intro: option_while'.intros simp: gets_the_conv split: option.splits) }
  note wl'_Inl = this

  { fix r s assume "(Some (r,s), None) \<in> whileLoop_results C (\<lambda>a. gets_the (B a))"
    then have "(Some r, None) \<in> option_while' (\<lambda>a. C a s) (\<lambda>a. B a s)"
      by (induct "Some (r, s)" "None :: (('a \<times> 's) option)" arbitrary: r s)
         (auto intro: option_while'.intros simp: gets_the_conv split: option.splits) }
  note wl'_Inr = this

  { fix r s r' assume "(Some r, Some r') \<in> option_while' (\<lambda>a. C a s) (\<lambda>a. B a s)"
    then have "(Some (r,s), Some (r',s)) \<in> whileLoop_results C (\<lambda>a. gets_the (B a))"
    by (induct "Some r" "Some r'" arbitrary: r)
       (auto intro: whileLoop_results.intros simp: gets_the_conv) }
  note option_while'_Some = this

  { fix r s assume "(Some r, None) \<in> option_while' (\<lambda>a. C a s) (\<lambda>a. B a s)"
    then have "(Some (r,s), None) \<in> whileLoop_results C (\<lambda>a. gets_the (B a))"
    by (induct "Some r" "None :: 'a option" arbitrary: r)
       (auto intro: whileLoop_results.intros simp: gets_the_conv) }
  note option_while'_None = this

  have "\<And>s. owhile C B r s = None
      \<Longrightarrow> whileLoop C (\<lambda>a. gets_the (B a)) r s = ({}, True)"
    by (auto simp: whileLoop_def owhile_def option_while_def option_while'_THE gets_the_loop_terminates
      split: if_split_asm dest: option_while'_None wl'_Inl option_while'_inj)
  moreover
  have "\<And>s r'. owhile C B r s = Some r'
      \<Longrightarrow> whileLoop C (\<lambda>a. gets_the (B a)) r s = ({(r', s)}, False)"
    by (auto simp: whileLoop_def owhile_def option_while_def option_while'_THE gets_the_loop_terminates
      split: if_split_asm dest: wl'_Inl wl'_Inr option_while'_inj intro: option_while'_Some)
  ultimately
  show ?thesis
    by (auto simp: fun_eq_iff gets_the_conv split: option.split)
qed

end
