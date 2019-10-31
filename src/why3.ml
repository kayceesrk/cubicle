open Format

open Ast
open Types

let tbool = Hstring.make "mbool"

let mytrue = Hstring.make "@MTrue"
let myfalse = Hstring.make "@MFalse"

let maxprocs = "maxprocs"

let capitalize h =
  Hstring.make @@ String.capitalize_ascii @@ Hstring.view h

let uncapitalize h =
  Hstring.make @@ String.uncapitalize_ascii @@ Hstring.view h

let pp_hstring_cap fmt h = Hstring.print fmt @@ capitalize h

let pp_hstring_uncap fmt h = Hstring.print fmt @@ uncapitalize h

let pp_cut_if_nempty l =
  if List.compare_length_with l 0 > 0 then print_cut ()

let pp_sep_pipe fmt () = fprintf fmt " |@ "

let pp_sep_and_ml fmt () = fprintf fmt " &&@ "
let pp_sep_and_log fmt () = fprintf fmt " /\\@ "

let pp_sep_nil fmt () = fprintf fmt ""
let pp_sep_space fmt () = fprintf fmt " "
(* let pp_sep_implies fmt () = fprintf fmt " ->@ " *)

let pp_length_array fmt u =
  fprintf fmt "s.%a.length - 1" pp_hstring_uncap u.up_arr

(* for loop on an array *)
let pp_for fmt u =
  fprintf fmt "for %a = 0 to s.%a.length - 1 do"
    Variable.print_vars u.up_arg pp_length_array u

(* print the constructors *)
let pp_list_const fmt cl =
  pp_print_list ~pp_sep:pp_sep_pipe Hstring.print fmt cl

(* used to print the pairs of constructors for the equality *)
let pp_list_pairs fmt cl =
  pp_print_list ~pp_sep:pp_sep_pipe (
    fun fmc c -> fprintf fmt "%a, %a" Hstring.print c Hstring.print c)
    fmt cl

(* if the term is a variable or an array and syst is true,
   the term is a field of the system, hence the s.*
*)
let rec pp_term ?(syst=false) sub fmt t =
  if syst then
    (match t with
      | Elem (_, Glob) | Access _ -> fprintf fmt "s."
      | _ -> ());
  match t with
    | Elem (x, s) ->
      if Hstring.equal x mytrue then fprintf fmt "true"
      else if Hstring.equal x myfalse then fprintf fmt "false"
      else fprintf fmt "%a" Hstring.print (
        match s with
          | Constr -> x
          | Glob -> uncapitalize x
          | Var -> Variable.subst sub x
      )
    | Access (id, vl) ->
      let vl = List.map (Variable.subst sub) vl in
      fprintf fmt "%a[%a]" pp_hstring_uncap id Variable.print_vars vl
    | Arith (t, cs) ->
      fprintf fmt "%a%a" (pp_term ~syst sub) t (Term.print_cs false) cs
    | t -> fprintf fmt "%a" Term.print t

let pp_term_syst = pp_term ~syst:true

(* print a term associated to its value at a certain label *)
let pp_term_at sub lbl fmt t =
  match t with
    | Elem (_, Glob) | Access _ ->
      fprintf fmt "(%a at %a)" (pp_term_syst sub) t pp_hstring_cap lbl
    | _ -> pp_term sub fmt t

(* if the atom is in a condition, no need to print
   bool = true or false
   if it's not, it means that we are giving a value to a variable *)
let pp_atom ?(syst=false) ?(cond=false) sub fmt = function
  | Atom.Comp (t1, op, t2) ->
    if cond then
      match t2, op with
        | Elem (x, _), Eq when Hstring.equal x mytrue ->
          fprintf fmt "%a" (pp_term ~syst sub) t1
        | Elem (x, _), Eq when Hstring.equal x myfalse ->
          fprintf fmt "not %a" (pp_term ~syst sub) t1
        | Elem (x, _), Neq when Hstring.equal x mytrue ->
          fprintf fmt "not %a" (pp_term ~syst sub) t1
        | Elem (x, _), Neq when Hstring.equal x myfalse ->
          fprintf fmt "%a" (pp_term ~syst sub) t1
        | _ ->
          fprintf fmt "%a %a %a"
            (pp_term ~syst sub) t1 print_op op (pp_term ~syst sub) t2
    else  fprintf fmt "%a %a %a"
        (pp_term ~syst sub) t1 print_op op (pp_term ~syst sub) t2
  | a -> fprintf fmt "%a" Atom.print a

let pp_atom_syst = pp_atom ~syst:true

(* prints a set of atoms (by default as a conjunction of atoms) *)
let pp_satom ?(syst=true) ?(cond=false) ?(pp_sep=pp_sep_and_ml) sub fmt sa =
  fprintf fmt "@[<hov>%a@]"
    (pp_print_list ~pp_sep (pp_atom ~syst ~cond sub)) (SAtom.elements sa)

let pp_satom_syst = pp_satom ~syst:true

(* prints a conjunction of atoms in a conjunction leading to an implication
   for better readability
   In case of universal unsafe, it's an implication leading to a
   conjunction *)
let pp_satom_nlast ?(uu=false) bvars fmt sa =
  fprintf fmt "@[<hov>";
  let aux fmt l =
    let rec aux fmt = function
      | [a] ->
        fprintf fmt " %s@ %a%s" (if uu then "\\/" else "->")
          (pp_atom_syst ~cond:true []) (Atom.neg a) (if uu then ")" else "")
      | hd :: tl ->
        let a = if uu then Atom.neg hd else hd in
        fprintf fmt " %s@ %a%a" (if uu then "\\/" else "/\\")
          (pp_atom_syst ~cond:true []) a aux tl
      | _ -> assert false
    in match l with
      | [a] ->
        fprintf fmt "%s@ %a" (
          if bvars then
            if uu then " /\\"
            else " ->"
          else "")
          (pp_atom_syst ~cond:true []) (Atom.neg a)
      | hd :: tl ->
        let a = if uu then Atom.neg hd else hd in
        fprintf fmt "%s@ %s%a%a" (if bvars then " /\\" else "")
          (if uu then "(" else "")
          (pp_atom_syst ~cond:true []) a aux tl
      | _ -> assert false
  in aux fmt @@ SAtom.elements sa;
  fprintf fmt "@]"

(* Transforms type declarations in scopes with definition of equality
   between each constructor *)
let pp_trad_type_defs fmt tdl =
  let pp_trad_type_def fmt (_, (t, cl)) =
    if not @@ Hstring.equal t tbool then
      fprintf fmt "@[<v 2>scope import %a@,\
                   @,\
                   type %a = @[<hov 2>%a@]@,\
                   @,\
                   @[<v 2>let (=) (a b: %a): bool@,\
                   ensures {result <-> a = b}@,\
                   = @[<v 0>match a, b with@,\
                   | @[<hov>%a@] -> true@,\
                   | _ -> false\
                   @]@]@ end@,@]@,\
                   end@,\
                  "
        pp_hstring_cap t Hstring.print t
        pp_list_const cl Hstring.print t
        pp_list_pairs cl
  in
  pp_print_list pp_trad_type_def fmt tdl

let pp_type fmt t =
  if Hstring.equal t tbool then fprintf fmt "bool"
  else fprintf fmt "%a" Hstring.print t

(* transforms a global variable in a mutable field of the system record *)
let pp_global_to_field fmt (_, id, ty) =
  fprintf fmt "@[mutable %a : %a;@]" pp_hstring_uncap id pp_type ty

(* transforms an array in a field of the system record *)
let pp_array_to_field fmt (_, id, (ktl, ty)) =
  assert (List.compare_length_with ktl 1 = 0);
  fprintf fmt "@[%a : array %a;@]" pp_hstring_uncap id pp_type ty

let pp_system_to_type fmt s =
  pp_print_list pp_global_to_field fmt s.globals;
  pp_cut_if_nempty s.arrays;
  pp_print_list pp_array_to_field fmt s.arrays

module HM = Map.Make(Hstring)
module HSet = Hstring.HSet

let pp_init fmt {globals; arrays; init = (_, _, dnf)} =
  let open Atom in
  let elems = List.fold_left (fun acc (_, id, t) -> HM.add id t acc)
      HM.empty globals in
  let arrays = List.fold_left (fun acc (_, id, (_, t)) -> HM.add id t acc)
      HM.empty arrays in
  let init_elems, init_arrays = List.fold_left (fun acc sa ->
    SAtom.fold (fun a (elems, arrays) ->
      match a with
        | Comp (t1, Eq, t2) ->
          begin match t1 with
            | Elem (id, _) ->
              let acc = HSet.add id elems, arrays in
              fprintf fmt "@,%a = %a;" pp_hstring_uncap id (pp_term []) t2;
              acc
            | Access (id, _) ->
              let acc = elems, HSet.add id arrays in
              fprintf fmt "@,%a = Array.make %s %a;"
                pp_hstring_uncap id maxprocs (pp_term []) t2;
              acc
            | _ -> assert false
          end;
        | Comp (t1, Neq, _) ->
          begin match t1 with
            | Elem (id, _) ->
              let acc = HSet.add id elems, arrays in
              fprintf fmt "@,%a = -1;" pp_hstring_uncap id;
              acc
            | Access (id, _) -> assert false
            | _ -> assert false
          end
        | _ -> assert false
    ) sa acc
  ) (HSet.empty, HSet.empty) dnf in
  let ninit_elems =
    HM.filter (fun e _ -> not @@ HSet.mem e init_elems) elems in
  let ninit_arrays =
    HM.filter (fun e _ -> not @@ HSet.mem e init_arrays) arrays in
  let typed_random id t =
    let open Smt.Type in
    if t = type_int || t = type_proc then
      (sprintf "Random.random_int %s" maxprocs)
    else if t = tbool then "Random.random_bool ()"
    else (eprintf "%a, %a@." Hstring.print id Hstring.print t; assert false)
  in
  HM.iter (fun e t ->
    fprintf fmt "@,%a = %s;"
      pp_hstring_uncap e (typed_random e t)
  ) ninit_elems;
  HM.iter (fun a t ->
    fprintf fmt "@,%a = Array.make %s (%s);"
      pp_hstring_uncap a maxprocs (typed_random a t)
  ) ninit_arrays


let pp_asserts_arrays mb fmt {init = (_, _, dnf)} =
  List.iter (fun sa ->
    SAtom.iter (fun a ->
      match a with
        | Comp (Access (id, _), Eq, t2) ->
          for i = 0 to mb do
            fprintf fmt "@,assert {s.%a[%d] = %a};"
              pp_hstring_uncap id i (pp_term []) t2
          done;
        | _ -> ()
        ) sa
    ) dnf

(* Can be replaced with List.init but Functory is not compatible
   with the last versions of OCaml *)
let init n f =
  let rec aux i acc =
    if i = n then List.rev acc
    else aux (i+1) (f i :: acc)
  in aux 0 []

let new_procs a =
  init a (fun i -> Hstring.make @@ Printf.sprintf "_p%d" i)

let pp_sep_diff fmt () = fprintf fmt " <> "

let pp_print_distincts fmt l =
  pp_print_list ~pp_sep:pp_sep_diff Hstring.print fmt l

let pp_newprocs fmt l =
  fprintf fmt "let procs = k_random %d %s in@," (List.length l) maxprocs;
  List.iteri (fun i hs ->
    fprintf fmt "let %a = procs[%d] in@,"
      Hstring.print hs i) l;
  if List.compare_length_with l 1 > 0 then
    fprintf fmt "assert { %a };" pp_print_distincts l



let pp_guard sub fmt g =
  if not @@ SAtom.is_empty g then fprintf fmt "@ &&@ ";
  pp_satom_syst ~cond:true sub fmt g

let pp_uguards pl fmt t =
  let cpt = ref 0 in
  let pp_proc fmt p = fprintf fmt "(%a : proc)" Hstring.print p in
  let pp_uguard fmt u =
    fprintf fmt "forall_other_%a%d %a"
      pp_hstring_uncap t.tr_name !cpt (pp_print_list pp_proc) pl;
    incr cpt
  in
  if t.tr_ureq <> [] then fprintf fmt " &&@ ";
  pp_print_list ~pp_sep:pp_sep_and_ml pp_uguard fmt t.tr_ureq

let map_procs args pl =
  let rec aux acc = function
    | [], _ -> acc
    | hd1 :: tl1, hd2 :: tl2 -> aux ((hd1, hd2) :: acc) (tl1, tl2)
    | _ -> assert false
  in aux [] (args, pl)

let pp_arr_access sub fmt u =
  let vl = List.map (Variable.subst sub) u.up_arg in
  fprintf fmt "%a[%a]" pp_hstring_uncap u.up_arr Variable.print_vars vl

let pp_assigns sub fmt al =
  let pp_upd fmt = function
    | UTerm t -> fprintf fmt "%a" (pp_term_syst sub) t
    | _ -> eprintf "pp_assigns@."; assert false
  in
  let pp_assign fmt (id, upd) =
    fprintf fmt "s.%a <- %a;@," pp_hstring_uncap id pp_upd upd
  in
  fprintf fmt "@[<v 0>%a@]"
    (pp_print_list ~pp_sep:pp_sep_nil pp_assign) al

let is_true sa = SAtom.equal sa (SAtom.singleton Atom.True)

let pp_updates plist sub lbl fmt ul =
  let pp_upd fmt u =
    match u.up_swts with
      | [(sa, t); _] ->
        let sub' = Variable.build_subst u.up_arg plist @ sub in
        fprintf fmt "@[<v 2>s.%a <- %a;@]"
          (pp_arr_access sub') u (pp_term_syst sub') t
      | _ ->
        let sub' = Variable.build_subst u.up_arg [Hstring.make "_p"] @ sub in
        let pp_swt ?(cond="else if") fmt (sa, t) =
          if is_true sa then
            fprintf fmt "else %a)" (pp_term_syst sub) t
          else fprintf fmt "%s %a then %a"
              cond (pp_satom sub) sa (pp_term_syst sub) t
        in
        let pp_swts fmt swts =
          fprintf fmt "@[<v 0>";
          (match swts with
            | [(_, t)] -> fprintf fmt "%a" (pp_term_syst sub) t
            | hd :: tl ->
              fprintf fmt "%a@," (pp_swt ~cond:"(if") hd;
              pp_print_list pp_swt fmt tl
            | _ -> assert false);
          fprintf fmt "@]"
        in
        let pp_prev fmt prev =
          fprintf fmt "@[<v 0>%a@]"
            (pp_print_list ~pp_sep:pp_sep_and_log
               (pp_satom ~pp_sep:pp_sep_and_log sub')) prev
        in
        let pp_invariant ?(last=false) prev u fmt (inv, t) =
          if last then fprintf fmt "(%a" pp_prev prev
          else
            fprintf fmt "(%a%s%a"
              (pp_satom ~pp_sep:pp_sep_and_log sub') inv
              (if prev <> [] then " /\\ " else "") pp_prev prev;
          fprintf fmt "%ss.%a = %a)"
            (if prev = [] && is_true inv then "" else " -> ")
            (pp_arr_access sub') u (pp_term_at sub' lbl) t
        in
        let pp_invariants fmt u =
          fprintf fmt "invariant { @[<v 2>forall _p:proc. 0 <= _p < %a ->@,"
            Variable.print_vars u.up_arg;
          let rec aux prev fmt = function
            | [upd] -> pp_invariant ~last:true prev u fmt upd
            | ((inv, _) as upd) :: tl -> pp_invariant prev u fmt upd;
              fprintf fmt " /\\@,";
              aux (SAtom.map Atom.neg inv :: prev) fmt tl
            | _ -> assert false
          in
          let pp_inv_array lbl fmt u =
            fprintf fmt "s.%a = (s.%a at %a)"
              (pp_arr_access sub') u (pp_arr_access sub') u pp_hstring_cap lbl
          in
          aux [] fmt u.up_swts;
          fprintf fmt " }@]@,";
          fprintf fmt "invariant { @[<v 2>forall _p:proc. %a <= _p < %s ->@,\
                       %a }@]@,@,"
            Variable.print_vars u.up_arg maxprocs (pp_inv_array lbl) u;
        in
        fprintf fmt "@[<v 2>%a@,%as.%a <- %a@]@,done;"
          pp_for u pp_invariants u (pp_arr_access sub) u pp_swts u.up_swts
  in
  fprintf fmt "@[<v 0>%a@]" (pp_print_list pp_upd) ul

let pp_transitions pl fmt s =
  let pp_transition ?(cond="else if") pl fmt t =
    let sub = map_procs t.tr_args pl in
    fprintf fmt "(*%a*)@,\
                 @[<hov 2>%s coin ()%a%a@]@ \
                 @[<v 2>then begin@,label %a in@,%a%a@]@,end@,"
      Hstring.print t.tr_name cond
      (pp_guard sub) t.tr_reqs (pp_uguards pl) t
      pp_hstring_cap t.tr_name
      (pp_assigns sub) t.tr_assigns (pp_updates pl sub t.tr_name) t.tr_upds
      (* (pp_nondets map) t.tr_nondets *)
  in
  match s.trans with
    | hd :: tl ->
      fprintf fmt "%a@," (pp_transition ~cond:"if" pl) hd;
      pp_print_list (pp_transition pl) fmt tl
    | _ -> assert false

let pp_vars fmt vl =
  if List.compare_length_with vl 0 > 0 then
    Format.fprintf fmt "forall %a : int. "
      (pp_print_list ~pp_sep:pp_sep_space Hstring.print) vl

let pp_vars_exists fmt vl =
  if List.compare_length_with vl 0 > 0 then
    Format.fprintf fmt "exists %a : int. "
      (pp_print_list ~pp_sep:pp_sep_space Hstring.print) vl

let pp_vars_forall fmt vl =
  if List.compare_length_with vl 0 > 0 then
    Format.fprintf fmt "forall %a : int. "
      (pp_print_list ~pp_sep:pp_sep_space Hstring.print) vl

let pp_vars_bound ?(neg=false) () fmt vl =
  let pp_v_b fmt v =
    fprintf fmt "%s0 <= %a < %s" (if neg then "not " else "") Hstring.print v
      maxprocs
  in
  pp_print_list ~pp_sep:pp_sep_and_log pp_v_b fmt vl

let pp_vars_distinct fmt vl =
  let pp_diff v1 fmt v2 =
    fprintf fmt "%a <> %a" Hstring.print v1 Hstring.print v2
  in
  let pp_v_dist_vl v fmt vl =
    pp_print_list ~pp_sep:pp_sep_and_log (pp_diff v) fmt vl
  in
  let rec aux = function
    | [] -> ()
    | hd :: tl ->
      pp_v_dist_vl hd fmt tl;
      if List.compare_length_with tl 1 > 0 then pp_sep_and_log fmt ();
      aux tl
  in
  if List.compare_length_with vl 1 > 0 then fprintf fmt " /\\@ ";
  aux vl

let pp_ensures fmt s =
  let pp_univ_ensure fmt (_, vl, v, sa) =
    fprintf fmt "@[ensures { @[<hov 2>%a%a%a%a@] }@]"
      pp_vars_exists vl (pp_vars_bound ()) (v :: vl) pp_vars_distinct (v :: vl)
      (pp_satom_nlast (vl <> [])) sa
  in
  let pp_ensure fmt (_, vl, sa) =
    fprintf fmt "@[ensures { @[<hov 2>%a%a%a%a@] }@]"
      pp_vars vl (pp_vars_bound ()) vl pp_vars_distinct vl
      (pp_satom_nlast (vl <> [])) sa
  in
  pp_print_list pp_ensure fmt s.unsafe;
  fprintf fmt (if List.compare_length_with s.univ_unsafe 0 = 0 then "" else "@,");
  pp_print_list pp_univ_ensure fmt s.univ_unsafe

let pp_proc_bounds fmt s =
  let pp_proc_bound fmt (_, h, _) =
      Format.fprintf fmt "@[invariant { 0 <= s.%a < %s }@]"
        pp_hstring_uncap h maxprocs
  in pp_print_list pp_proc_bound fmt
    (List.filter (fun (_, _, t) -> t = Smt.Type.type_proc) s.globals)

let pp_invariants invs fmt s =
  let pp_invariant fmt (vl, sa) =
    fprintf fmt "@[invariant { @[<hov 2>%a%a%a%a@] }@]"
      pp_vars vl (pp_vars_bound ()) vl pp_vars_distinct vl
      (pp_satom_nlast (vl <> [])) sa
  in
  let sinvs = if Options.only_brab_invs then s.invs else [] in
  let sinvs = List.map (
    fun (_, vl, sa) -> (vl, sa)
  ) (s.whyinvs @ sinvs @ s.unsafe)
  in
  let invs = if Options.why3_cub_invs then List.map (
    fun {Ast.cube = {Cube.vars; Cube.litterals}} ->
      let wvars = List.map Variable.(subst subst_ptowp) vars in
      let wlit = SAtom.subst Variable.subst_ptowp litterals in
      (wvars, wlit)) invs else [] in
  pp_print_list pp_invariant fmt (invs @ sinvs)

let simpl_satom uvl ev sa =
  SAtom.subst Variable.subst_ptowp @@ SAtom.filter (fun a ->
    Atom.has_var ev a ||
    (List.exists (fun v -> Atom.has_var v a) uvl) ||
    Atom.has_no_vars a
  ) sa

let pp_univ_unsafes fmt uul =
  let module VS = Variable.Set in
  let pp_univ_unsafe fmt n =
    (* Existential variables in Cubicle turn to universal variables in Why3 *)
    let uvl = VS.elements n.evars in
    (* Universal variable in Cubicle turns to existential variable in Why3 *)
    let ev = VS.min_elt (VS.diff (VS.of_list n.cube.vars) n.evars) in
    let sa = simpl_satom uvl ev n.cube.litterals in
    let uvl = List.map (Variable.(subst subst_ptowp)) uvl in
    let ev = Variable.(subst subst_ptowp ev) in
    let sa = SAtom.subst Variable.subst_ptowp sa in
    let vars = List.rev (ev :: uvl) in
    fprintf fmt "@[invariant { @[<hov 2>%a%a%a%s%a%a%a@] }@]"
      pp_vars_forall uvl pp_vars_exists [ev] (pp_vars_bound ~neg:true ()) uvl
      (if uvl <> [] then " \\/ " else "")
      (pp_vars_bound ()) [ev] pp_vars_distinct vars
      (pp_satom_nlast ~uu:true (vars <> [])) sa
  in
  pp_print_list pp_univ_unsafe fmt uul

let pp_forall_others pl fmt tl =
  let pl' = List.map (fun h -> Hstring.make ((Hstring.view h)^"'")) pl in
  let pp_dnf sub fmt sal =
    pp_print_list (pp_satom_syst ~cond:true sub) fmt sal
  in
  let pp_list fmt t =
    let cpt = ref 0 in
    let pp_fall_oth fmt (v, dnf) =
      let subinv = map_procs [v] pl' in
      let subml = map_procs (v :: t.tr_args) (Hstring.make "_fi" :: pl) in

      let vs = asprintf "%a" Variable.print_vars pl in
      fprintf fmt
        "@[<v 2>let forall_other_%a%d (%s : proc)@,\
         requires { 0 <= %s < %s }@,\
         ensures { @[<hov 0>result = True <->@ forall %s':proc.@ \
         0 <= %s' < %s /\\@ %s' <> %s@ ->@ %a}@]@]@,\
         @[<v 2>=@,\
         let res = ref true in@,\
         @[<v 2>for _fi = 0 to %s - 1 do@,\
         invariant { @[<hov 0>!res = True <->@ forall %s':proc.@ \
         0 <= %s' < _fi /\\@ %s' <> %s -> %a}@]@,\
         if _fi <> %s && %a then res := false@]@,\
         done;@,!res@]@,in@,"
        pp_hstring_uncap t.tr_name !cpt vs vs maxprocs vs vs vs maxprocs vs
        (pp_dnf subinv) dnf maxprocs vs vs vs vs (pp_dnf subinv) dnf vs
        (pp_dnf subml) (List.map (fun sa -> SAtom.map Atom.neg sa) dnf)
      ;
      incr cpt
    in
    if t.tr_ureq <> [] then
      pp_print_list pp_fall_oth fmt t.tr_ureq
  in
  pp_print_list ~pp_sep:pp_print_if_newline pp_list fmt tl

(* Transforms a Cubicle program in a whyml one *)

let replay_invs system invs =
  List.fold_left (fun acc inv ->
    let inv =
      match Approx.Selected.good inv with
        | None -> inv
        | Some c ->
          try
            Safety.check system c;
            c
          with Safety.Unsafe _ -> inv
    in
    match Bwd.Selected.aux_search ~invariants:[] ~candidates:[] system [inv] with
      | Unsafe _ | TimeOut _ -> acc
      | Safe (vis, cand) -> inv :: acc) [] invs

let get_min_bound s =
  List.fold_left (fun acc (_, vl, _, _) ->
    let l = List.length vl in
    if l > acc then l else acc
  ) 0 s.univ_unsafe

let cub_to_whyml t_syst syst invs fmt file =
  (* eprintf "Invs : @.";
   * List.iter (fun n ->
   *   eprintf "%a@.(%a)@.@." Node.print n Variable.print_vars (Variable.Set.elements n.evars)) invs; *)
  (* eprintf "Replay : @."; *)
  let invs = replay_invs t_syst invs in
  (* eprintf "Replayed : @."; *)
  (* List.iter (eprintf "%a@.@." Node.print) invs; *)
  let mb = get_min_bound syst in
  let name = Filename.(remove_extension @@ basename file) in
  let plist = new_procs syst.max_arity in
  fprintf fmt "@[<v>\
               module %s@,\
               @,\
               use array.Array@,\
               use int.Int@,\
               use ref.Refint@,\
               use random.Random@,\
              " (String.capitalize_ascii name);
  fprintf fmt "%a" pp_trad_type_defs syst.type_defs;
  fprintf fmt "@,val coin () : bool@,";
  fprintf fmt "@[<v 2>val k_random (k:int) (n:int) : (result:array int)@,\
               requires { 0 <= k }@,\
               requires { k <= n }@,\
               ensures { length result = k }@,\
               ensures { forall i j:int. 0 <= i < n /\\ 0 <= j < n /\\ i <> j -> result[i] <> result[j] }@,\
               ensures { forall i:int. 0 <= i < n -> 0 <= result[i] < n }@]@,";

  fprintf fmt "@,type proc = int@,";

  fprintf fmt "@,@[<v 2>type system = {@,%a@]@,}@,"
    pp_system_to_type syst;
  fprintf fmt "@,@[<v 2>let %s (%s : int) (maxsteps : int) : system@,\
               requires { %d < %s }@,\
               @[<v 2>=@,"
    name maxprocs mb maxprocs;
  fprintf fmt "@[<v 2>let s = {%a@]@,} in@,%a@,@,let nbsteps = ref 0 in@,"
    pp_init syst (pp_asserts_arrays mb) syst;
  fprintf fmt "%a" (pp_forall_others plist) syst.trans;
  fprintf fmt "@,@[<v 2>while ( !nbsteps < maxsteps ) do@,";
  fprintf fmt "@[<v 0>@[variant { maxsteps - !nbsteps }@]@,%a@,%a@]"
    pp_proc_bounds syst (pp_invariants invs) syst;
  fprintf fmt "@,@[<v 0>%a@]" pp_univ_unsafes t_syst.t_univ_unsafe;
  fprintf fmt "@,@,incr nbsteps;@,@,%a@," pp_newprocs plist;
  fprintf fmt "@,%a" (pp_transitions plist) syst;
  fprintf fmt "@]@,done;@,s@]@,end";
  fprintf fmt "@.";
  exit 0
