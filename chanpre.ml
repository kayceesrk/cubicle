

open Channels
open Chanevent
open Types
open Util

exception UnsatisfiableRecv



let compatible_consts c1 cop c2 =
  let c = Types.compare_constants c1 c2 in
  match cop with
  | CEq -> c = 0
  | CNeq -> c <> 0
  | CLt -> c < 0
  | CLe -> c <= 0
  | CGt -> c > 0
  | CGe -> c >= 0

(* True means maybe, False means no *)
let compatible_terms st cop rt = match st, rt with
  | Const c1, Const c2 -> compatible_consts c1 cop c2
  | Elem (c1, Constr), Elem (c2, Constr) ->
     if cop = CEq then H.equal c1 c2
     else if cop = CNeq then not (H.equal c1 c2)
     else failwith "Chanpre.compatible_terms : invalid op on Constr"
  | Elem (p1, Var), Elem (p2, Var) ->
     if cop = CEq then H.equal p1 p2
     else if cop = CNeq || cop = CLt || cop = CGt then not (H.equal p1 p2)
     else true (* CLe, CGe -> anything is potentially compatible *)
  | Elem (v1, Glob), Elem (v2, Glob) ->
     if cop = CNeq || cop = CLt || cop = CGt then not (H.equal v1 v2)
     else true (* CEq, CLe, CGe -> anything is potentially compatible *)
  (* | Access (v1, vi1), Access (v2, vi2) -> TODO *)
  | Arith (t1, c1), Arith (t2, c2) ->
     if not (Term.equal t1 t2) then true
     else compatible_consts c1 cop c2
  | _ ->
     if cop = CNeq || cop = CLt || cop = CGt then not (Term.equal st rt)
     else true

let compat_val stl vals =
  List.for_all (fun st ->
    List.for_all (fun (cop, t) -> compatible_terms st cop t) vals
  ) stl

let is_satisfied = function [] -> true | _ -> false

let get_send_on sends ed =
  try Some (HEvtMap.findp (fun eds _ -> same_chan eds ed) sends)
  with Not_found -> None
(*
let remove_write_on writes ed =
  HEvtMap.filter (fun edw _ -> not (same_var edw ed)) writes
let unsat_reads edw pevts =
  List.exists (fun (_, (ed, vals)) -> same_var edw ed && vals <> []) pevts
              
let skip_incompatible writes pevts = (* wtl may contain more than 1 element *)
  let rec aux ((wr, ird, srd, urd) as reason) = function
    | [] -> reason, []
    | ((_, (ed, vals)) as e) :: pevts ->
       begin match get_write_on writes ed with
       | None -> aux reason pevts (* not same var : no problem *)
       | Some (edw, (_, wtl)) ->
          if is_write ed then
            aux (true, ird, srd, urd || unsat_reads edw pevts) pevts
          else if is_satisfied vals then
            aux (wr, ird, true, urd || unsat_reads edw pevts) pevts
          else if not (compat_val wtl vals) then
            aux (wr, true, srd, urd) pevts (* urd <- true ? *)
          else
            (wr, ird, srd, urd), e :: pevts (* compatible = go on *)
       end
  in
  aux (false, false, false, false) pevts
let get_read_chunk writes pevts =
  let rec aux chunk writes cut = function
    | [] -> List.rev chunk, cut
    | ((_, (ed, vals)) as e) :: pevts ->
       begin match get_write_on writes ed with
       | None -> aux chunk writes cut pevts
       | Some (edw, (_, wtl)) ->
          if is_write ed || is_satisfied vals || not (compat_val wtl vals)
          then begin
            let cut = if cut = [] then e :: pevts else cut in
            let writes = remove_write_on writes ed in
            if HEvtMap.cardinal writes = 0 then List.rev chunk, cut
            else aux chunk writes cut pevts
          end
          else aux (e :: chunk) writes cut pevts
       end
  in
  aux [] writes [] pevts
let read_chunks_for_writes same_thread writes pevts =
  let rec aux chunks = function
    | [] -> List.rev chunks
    | pevts ->
       let chunk, pevts = get_read_chunk writes pevts in
       let (wr, ird, srd, urd), pevts = skip_incompatible writes pevts in
       let chunk = if ird then [] else chunk in
       if same_thread then begin
         if ird || urd then raise UnsatisfiableRead;
         if chunk = [] then [] else [chunk]
       end else if wr || srd then begin
         if urd then raise UnsatisfiableRead;
         if chunk = [] then List.rev chunks
         else List.rev (chunk :: chunks)
       end else (* ird or no more events *) begin assert (ird || pevts = []);
         if ird || chunk = [] then aux chunks pevts
         else aux (chunk :: chunks) pevts
       end
  in
  aux [] pevts
 *)



let recv_chunks_for_sends same_thread sends pevts =
  let rec aux chunk = function
    | [] -> chunk
    | ((_, (ed, vals)) as e) :: pevts ->
       (* should fail if write or sat read on same thread with n/e chunk *)
       if is_send ed || is_satisfied vals then aux chunk pevts
       else
         begin match get_send_on sends ed with
         | None -> aux chunk pevts
         | Some (eds, (_, stl)) ->
            if compat_val stl vals then aux (e :: chunk) pevts
            else if same_thread then raise UnsatisfiableRecv
            else chunk
         end
  in
  (* aux [] (List.rev pevts) *)
  let chk = aux [] (List.rev pevts) in
  if chk = [] then [] else [chk]
      
let recv_chunks_by_thread_for_sends sends evts = (* evts by thread *)
  try
    let (_, sp, _, _), _ = HEvtMap.choose sends in
    if not (HEvtMap.for_all (fun (_, p, _, _) _ -> H.equal p sp) sends) then
      failwith "Invalid proc\n";
    let res = HMap.fold (fun p pevts rct ->
      let rc = recv_chunks_for_sends (H.equal sp p) sends pevts in
      if rc = [] then rct else (p, rc) :: rct
    ) evts [] in
    res
  with Not_found -> []

let recv_combs same_thread rl =
  let rec aux = function
  | [] -> failwith "Chanpre.recv_combs : internal error" (*[[]], []*)
  | [r] -> if same_thread then [[r]], [[r]] else [[r] ; []], [[r]]
  | r :: rl ->
     let combs, new_combs = aux rl in
     let combs, new_combs = List.fold_left (fun (combs, new_combs) nc ->
       let nc = (r :: nc) in
       nc :: combs, nc :: new_combs
     ) (if same_thread then [], [] else combs, []) new_combs in
     combs, new_combs
  in
  fst (aux rl)

let recv_combs_by_thread_for_sends sends rct =
  try
    let (_, sp, _, _), _ = HEvtMap.choose sends in
    if not (HEvtMap.for_all (fun (_, p, _, _) _ -> H.equal p sp) sends) then
      failwith "Invalid proc\n";
    List.fold_left (fun rct (p, rc) ->
      let rc = List.fold_left (fun rc rl ->
        (recv_combs (H.equal sp p) rl) @ rc
      ) [] rc in (* rc <- all read combinations for this thread *)
      (p, rc) :: rct (* source rc is a list of chunks *)
    ) [] rct
  with Not_found -> []

let recv_combs_for_sends sends rct =
  List.fold_left (fun lrc (p, rcl) ->
    cartesian_product (fun rc1 rc2 -> rc1 @ rc2) lrc rcl
  ) [[]] rct (* if no combination, we want to keep the write *)
               (* we just say that it satisfies no reads *)

let all_combinations sends rcl =
  List.map (fun rc -> HEvtMap.fold (fun eds stl src ->
    ((eds, stl), List.filter (fun (_, (edr, _)) -> same_chan eds edr) rc) :: src
  ) sends []) rcl




let make_recv_send_combinations sends evts_bt urevts ghb =

  (* TimeBuildRW.start (); *)

  let srcp = try
    let rct = recv_chunks_by_thread_for_sends sends evts_bt in
    let rct = recv_combs_by_thread_for_sends sends rct in
    let rcl = recv_combs_for_sends sends rct in
    all_combinations sends rcl
  with UnsatisfiableRecv -> [] in

  (* TimeBuildRW.pause (); *)

  (* List.iter (fun wrcl ->
   *   List.iter (fun (((wp, wd, wv, wvi), (we, wt)), rcl) ->
   *     Format.eprintf "(%a,%a,%a,%a) (%a,%a) -> (%a)\n"
   *       H.print wp H.print wd H.print wv (H.print_list ".") wvi
   *       H.print we
   *       (fun fmt lt ->
   *         List.iter (Format.fprintf fmt " %a" Term.print) lt
   *       ) wt
   *       (fun fmt rc ->
   *         List.iter (fun (re, (red, rvals)) ->
   *             Format.fprintf fmt " %a" H.print re) rc
   *       ) rcl
   *   ) wrcl
   * ) wrcp;
   * Format.print_flush (); *)
  
  (* TimeFilterRW.start (); *)

  (* Filter out combinations that lead to cyclic relations *)
  let srcp = List.fold_left (fun srcp srcl ->

    (* Remove satisfied reads from unsatisfied set *)
    let urevts = List.fold_left (fun urevts ((sed, _), rcl) ->
      List.fold_left (fun urevts (re, ((p, d, v, vi), _)) ->
        HMap.remove re urevts) urevts rcl
    ) urevts srcl in

    (* Adjust ghb for this combination *)
    let ghb = List.fold_left (fun ghb (((_,sp,_,_) as sed, (se,_)), rcl) ->
      let ghb = List.fold_left (fun ghb (re, (red, _)) -> (* rfe *)
        if same_thr sed red then ghb
        else Chanrel.Rel.add_lt se re ghb
      ) ghb rcl in
      let ghb = HMap.fold (fun ure (ured, _) ghb -> (* fr(e) *)
        if not (same_thr sed ured) then ghb
        else begin
          if same_thr sed ured then
            failwith ("Chanpre.mk_combs : invalid fr : " ^
                        (H.view ure) ^ " -> " ^ (H.view se))
          else Chanrel.Rel.add_lt ure se ghb
        end
      ) urevts ghb in
      ghb
    ) ghb srcl in

    if Chanrel.Rel.acyclic ghb then
      (srcl, ghb, urevts) :: srcp
    else srcp
  ) [] srcp in

  (* TimeFilterRW.pause (); *)

  srcp





let subst_event_val sfun sa =
  let rec process_t = function
    | Access (f, [e]) as t when is_value f -> sfun t e
    | Arith (t, c) ->
       let ntl = process_t t in
       begin match ntl with
       | [] -> failwith "Chanpre.subst_event_val : ntl can't be empty"
       | [nt] when nt == t -> [t]
       | _ -> List.map (fun nt -> Arith (nt, c)) ntl
       end
    | t -> [t]
  in
  SAtom.fold (fun at sa -> match at with
    | Atom.Comp (t1, op, t2) ->
       let ntl1 = process_t t1 in
       let ntl2 = process_t t2 in
       begin match ntl1, ntl2 with
       | [], _ | _, [] ->
          failwith "Chanpre.subst_event_val : ntl can't be empty"
       | [nt1], [nt2] when nt1 == t1 && nt2 == t2 -> SAtom.add at sa
       | _, _ ->
          List.fold_left (fun sa nt1 ->
            List.fold_left (fun sa nt2 ->
              SAtom.add (Atom.Comp (nt1, op, nt2)) sa
            ) sa ntl2
          ) sa ntl1 (* ntl probably haev a single element *)
       end
    | Atom.Ite _ ->
       failwith "Chanpre.subst_event_val : Ite should not be there"
    | _ -> SAtom.add at sa
  ) sa SAtom.empty

let rec subst_ievent ievts t = match t with
  | Recv (p, q, ch) ->
     let _, tval, _ = HEvtMap.find (hR, p, q, mk_hC ch) ievts in
     tval
  | Arith (t, c) -> Arith (subst_ievent ievts t, c)
  | _ -> t

let add_ievts_rels rel ievts f =
  HEvtMap.fold (fun ied (ie, _) rel -> match f ied ie with
    | None -> rel | Some e -> Chanrel.Rel.add_lt ie e rel
  ) ievts rel

let add_recvs_to_sa irds sa =
  (* That might generate duplicate (opposite direction) atoms *)
  HEvtMap.fold (fun dpqch (e, lt, vals) sa ->
    List.fold_left (fun sa (cop, rt) ->
      let rt = subst_ievent irds rt in
      let a = match cop with
        | CEq -> Atom.Comp (lt, Eq, rt)
        | CNeq -> Atom.Comp (lt, Neq, rt)
        | CLt -> Atom.Comp (lt, Lt, rt)
        | CLe -> Atom.Comp (lt, Le, rt)
        | CGt -> Atom.Comp (rt, Lt, lt)
        | CGe -> Atom.Comp (rt, Le, lt)
      in
      SAtom.add a sa
    ) sa vals
  ) irds sa

let ghb_before_urd ghb urd e =
  HMap.exists (fun re _ ->
    Chanrel.Rel.mem_lt e re ghb || Chanrel.Rel.mem_eq e re ghb) urd

let mk_pred pred pl =
  Atom.Comp (Access (pred, pl), Eq, Elem (Term.htrue, Constr))

let add_ghb_lt_atoms ghb sa =
  Chanrel.Rel.fold_lt (fun ef et sa ->
    SAtom.add (mk_pred hGhb [ef; et]) sa) ghb sa

let add_ghb_eq_atoms ghb sa =
  Chanrel.Rel.fold_eq (fun e1 e2 sa ->
    SAtom.add (mk_pred hSync [e1; e2]) sa) ghb sa

let mk_pairs l =
  let rec aux acc = function
    | [] | [_] -> acc
    | e1 :: el -> aux (List.fold_left (fun acc e2 -> (e1, e2) :: acc) acc el) el
  in
  aux [] l





(* Retrieve the maximum event id for this proc *)
let max_proc_eid eids p =
  try IntSet.max_elt (HMap.find p eids) with Not_found -> 0

(* Generate a fresh event id for this proc *)
let fresh_eid eids p =
  let eid = 1 + HMap.fold (fun _ peids maxeid ->
    max maxeid (IntSet.max_elt peids)) eids 0 in
  let peids = try HMap.find p eids with Not_found -> IntSet.empty in
  eid, HMap.add p (IntSet.add eid peids) eids

(* Compute the difference between event id sets by proc *)
let eid_diff eids_high eids_low =
  HMap.merge (fun _ h l ->
    match h, l with
    | Some h, Some l -> Some (IntSet.diff h l)
    | Some h, None -> Some h
    | _ -> failwith "Chanevent.eid_diff : internal error"
  ) eids_high eids_low

(* Build an event *)
let build_event e d p q ch = (* ch with _C prefix *)
  let _, vt = Channels.chan_type ch in
  let tval = Access (mk_hVal vt, [e]) in
  let adir = Atom.Comp (Access (hDir, [e]), Eq, Elem (d, Constr)) in
  let athr = Atom.Comp (Access (hThr, [e]), Eq, Elem (p, Var)) in
  let apeer = Atom.Comp (Access (hPeer, [e]), Eq, Elem (q, Var)) in
  let achan = Atom.Comp (Access (hChan, [e]), Eq, Elem (ch, Constr)) in
  let sa = SAtom.add achan (SAtom.add apeer
             (SAtom.add athr (SAtom.singleton adir))) in
  sa, tval





let satisfy_recvs sa =

  (* TimeSatRead.start (); *)

  let sa, rcs, sds, eids, evts = Chanevent.extract_events_set sa in
  let evts_bt = Chanevent.events_by_thread evts in
  let sevts = Chanevent.send_events evts in (* only for co/fr *)
  let urevts = Chanevent.unsat_recv_events evts in (* to associate to wts *)
  let ghb = Chanrel.extract_rels_set sa in (* for acyclicity *)


(*

  (* Get first write on each var *)
  let gfw = HMap.fold (fun we ((_, _, v, vi), _) gfw ->
    let cwe = try HVarMap.find (v, vi) gfw with Not_found -> hE0 in
    if H.compare we cwe > 0 then HVarMap.add (v, vi) we gfw else gfw
  ) wevts HVarMap.empty in

  (* Get first read and first write of each thread *)
  (* Writes and fences are grouped together for simplicity *)
  let freads, fwrites = HMap.fold (fun p pevts (freads, fwrites) ->
    let freads = try
        let (re, _) = List.find (fun (_, (ed, _)) -> is_read ed) pevts in
        HMap.add p re freads
      with Not_found -> freads in
    let fwrites = try
        let (we, _) = List.find (fun (_, (ed, _)) -> is_write ed) pevts in
        let cwe = try HMap.find p fwrites with Not_found -> hE0 in
        if H.compare we cwe >= 0 then HMap.add p we fwrites else fwrites
      with Not_found -> fwrites in
    freads, fwrites
  ) evts_bt (HMap.empty, ffces) in



  (* Remember eids before *)
  let eids_before = eids in

  (* Generate an id for each new write event *)
  let iwts, eids = HEvtMap.fold (fun ((p,_,_,_) as pdvvi) vals (iwts, eids) ->
    let eid, eids = fresh_eid eids p in
    HEvtMap.add pdvvi (mk_hE eid, vals) iwts, eids
  ) wts (HEvtMap.empty, eids) in

  (* Generate an id for each new read event *)
  let irds, eids = HEvtMap.fold (fun ((p,_,_,_) as pdvvi) vals (irds, eids) ->
    let eid, eids = fresh_eid eids p in
    HEvtMap.add pdvvi (mk_hE eid, vals) irds, eids
  ) rds (HEvtMap.empty, eids) in

  (* Generate sync for synchronous events *)
  let sync = HMap.fold (fun _ peids sync ->
    IntSet.fold (fun eid sync -> (mk_hE eid) :: sync
  ) peids sync) (eid_diff eids eids_before) [] in
  let ghb' = List.fold_left (fun ghb' (e1, e2) ->
    Weakrel.Rel.add_eq e1 e2 ghb') ghb (mk_pairs sync) in



  (* Add co from new writes to first old write on same variable *)
  let ghb' = add_ievts_rels ghb' iwts (fun (_, _, v, vi) _ ->
    try Some (HVarMap.find (v, vi) gfw) with Not_found -> None) in
  
  (* Add fr from new reads to first old write on same variable *)
  let ghb' = add_ievts_rels ghb' irds (fun (_, _, v, vi) _ ->
    try Some (HVarMap.find (v, vi) gfw) with Not_found -> None) in

  (* Add ppo from new reads to first old read of same thread *)
  let ghb' = add_ievts_rels ghb' irds (fun (p, _, _, _) _ ->
    try Some (HMap.find p freads) with Not_found -> None) in

  (* Add ppo from new reads to first old write of same thread *)
  let ghb' = add_ievts_rels ghb' irds (fun (p, _, _, _) _ ->
    try Some (HMap.find p fwrites) with Not_found -> None) in

  (* Add ppo/fence from new writes to first old write (or fence) *)
  (* However, if it's an atomic RMW, then consider first old read instead *)
  (* No need to split the RMW case if reads exists. But it might be useful
     in fact since we could add the lock prefix to the transition
     syntactically to avoir missing reads causing instr to be not locked *)
  let ghb' = add_ievts_rels ghb' iwts (fun (p, _, _, _) _ ->
    let fevts = if HEvtMap.is_empty irds then fwrites else freads in
    try Some (HMap.find p fevts) with Not_found -> None) in

  

  (* Build the relevant read-write combinations *)
  let wrcp = make_read_write_combinations iwts evts_bt urevts ghb' in

  let pres = if wrcp = [] then [] else begin



  (* Instantiate write events *)
  let iwts, sa = HEvtMap.fold (fun (p, d, v, vi) (e, vals) (iwts, sa) ->
    let na, _ = build_event e p d v vi in
    (HEvtMap.add (p, d, v, vi) (e, vals) iwts, SAtom.union na sa)
  ) iwts (HEvtMap.empty, sa) in

  (* Instantiate read events *)
  let irds, sa = HEvtMap.fold (fun (p, d, v, vi) (e, vals) (irds, sa) ->
    let na, tval = build_event e p d v vi in
    (HEvtMap.add (p, d, v, vi) (e, tval, vals) irds, SAtom.union na sa)
  ) irds (HEvtMap.empty, sa) in

  (* Add reads with their values (which may be reads too) *)
  let sa = add_reads_to_sa irds sa in

  (* Generate new fences (and remove older ones) *)
  let sa = List.fold_left (fun sa p ->
    let eid = max_proc_eid eids p in
    if eid <= 0 then sa else
      let sa = SAtom.filter (function
        | Atom.Comp (Access (a, [px; _]), Eq, Elem _)
        | Atom.Comp (Elem _, Eq, Access (a, [px; _]))
             when H.equal a hFence && H.equal p px -> false
        | _ -> true) sa in
      SAtom.add (mk_pred hFence [p; mk_hE eid]) sa
  ) sa fces in

  (* Update the set of atoms with relations computed so far *)
  let d = Weakrel.Rel.diff ghb' ghb in
  let sa = add_ghb_lt_atoms d sa in
  let sa = add_ghb_eq_atoms d sa in
  let ghb = ghb' in



  (* Update first write on each var *)
  let gfw' =  HEvtMap.fold (fun (_, _, v, vi) (we, _) gfw ->
    let cwe = try HVarMap.find (v, vi) gfw with Not_found -> hE0 in
    if H.compare we cwe > 0 then HVarMap.add (v, vi) we gfw else gfw
  ) iwts gfw in

  (* Update first reads by thread  *)
  let freads' = HEvtMap.fold (fun (p, _, _, _) (re, _, _) freads ->
    HMap.add p re freads
  ) irds freads in

  (* Update first fences by thread (considered as writes) *)
  let fwrites' = List.fold_left (fun ffces p ->
    let eid = max_proc_eid eids p in
    if eid > 0 then HMap.add p (mk_hE eid) ffces else ffces
  ) fwrites fces in

  (* Update first writes by thread  *)
  let fwrites' = HEvtMap.fold (fun (p, _, _, _) (we, _) fwrites ->
    let cwe = try HMap.find p fwrites with Not_found -> hE0 in
    if H.compare we cwe >= 0 then HMap.add p we fwrites else fwrites
  ) iwts fwrites' in



  (* Make set of events to keep ("entry points") *)
  (* We keep the following events, provided they are
     ghb-before or sync with an unsat read (or are an unsat read) :
       1st W on each var          gfw'     (for other W on same var)
       1st R of each thread       freads'  (for R by same thread)
       1st W/F of each thread     fwrites' (for RW by same thread)
       all unsat R                urevts   (for W by any thread) *)
  (* No need to keep non-first writes sync with unsat reads for atomic RMW :
     the first W will be ghb-before them, thus protecting them from cycles
     caused by adding the fr relation *)
  let kgfw = HVarMap.fold (fun _ e keep -> HSet.add e keep) gfw' HSet.empty in
  let kfrd = HMap.fold (fun _ e keep -> HSet.add e keep) freads' HSet.empty in
  let kfwt = HMap.fold (fun _ e keep -> HSet.add e keep) fwrites' HSet.empty in

  (* Relations to keep on "entry points" *)
  (* W entry points : don't keep ghb-before pairs (first W by var suffices *)
  (* R entry points : keep ghb-before pairs on unsat reads only *)
  (* However, keep WR/RW syncs in all cases (for atomic RMW) *)
  (* WW / RR syncs are most probably needed too *)
  (* In fact, simpler : don't keep ghb-before pairs to events not urd *)

  (* Variables to keep on "entry points" *)
  (* W entry points : keep var only on first W by var *)
  (* R entry points : keep var only if unsat R *)

  (* Generate the atom sets for each combination *)
  let pres = List.fold_left (fun pres (wrcl, ghb', urevts') ->

    (* Substitute the satisfied read value with the write value *)
    let sa = List.fold_left (fun sa ((_, (_, wtl)), rcl) ->
      let wtl = List.map (subst_ievent irds) wtl in
      List.fold_left (fun sa (re, _) ->
        subst_event_val (fun t e -> if H.equal e re then wtl else [t]) sa
      ) sa rcl
    ) sa wrcl in

    (* Update the set of atoms with the remaining relations (rf / fr) *)
    let sa = add_ghb_lt_atoms (Weakrel.Rel.diff ghb' ghb) sa in

    (* Determine which reads were satisfied *)
   (* let satrd = HMap.filter (fun e _ -> not (HMap.mem e urevts')) urevts in *)

    (* Add instantiated reads to unsatisfied reads *) (* merge with following*)
    let urevts' = HEvtMap.fold (fun red (re, _, rvals) urevts' ->
      HMap.add re (red, rvals) urevts'
    ) irds urevts' in

    (* Keep unsatisfied reads *)
    let kurd = HMap.fold (fun e _ keep -> HSet.add e keep) urevts' HSet.empty in

    (* Keep only events that are ghb-before or sync with an unsatisfied read *)
    let kgfw = HSet.filter (ghb_before_urd ghb' urevts') kgfw in
    let kfrd = HSet.filter (ghb_before_urd ghb' urevts') kfrd in
    let kfwt = HSet.filter (ghb_before_urd ghb' urevts') kfwt in

    (* Generate keep set *)
    let keep = HSet.union (HSet.union kgfw kfwt) (HSet.union kfrd kurd) in

    (* Here, remove events that do not satisfy criterion to stay *)
    let sa = SAtom.filter (function
      | Atom.Comp (Access (a, [_; e]), _, _)
      | Atom.Comp (_, _, Access (a, [_; e]))
           when H.equal a hFence -> HSet.mem e keep
      | Atom.Comp (Access (a, [ef; et]), _, _)
      | Atom.Comp (_, _, Access (a, [ef; et]))
           when (H.equal a hGhb || H.equal a hSync) &&
             not (HSet.mem ef keep && HSet.mem et keep) -> false
      | Atom.Comp (Access (a, [ef; et]), _, _)
      | Atom.Comp (_, _, Access (a, [ef; et]))
           when H.equal a hGhb && not (HSet.mem et kurd) -> false (*
         not (HSet.mem et kfwt || HSet.mem et kgfw || HSet.mem et kfrd)*)
       (* not (HMap.mem et wevts *)
       (*     || HEvtMap.exists (fun _ (e, _) -> H.equal e et) iwts) *)
      | Atom.Comp (Access (f, [e]), _, _)
      | Atom.Comp (_, _, Access (f, [e])) when (H.equal f hVar || is_param f) ->
         (* HSet.mem e keep && (HSet.mem e kurd || HSet.mem e kgfw) *)
         HSet.mem e keep && (HSet.mem e kurd ||
                             HSet.mem e kgfw || HSet.mem e kfwt)

      (*    HSet.mem e keep && (HVarMap.exists (fun _ we -> H.equal e we) gfw' || *)
      (*      HMap.exists (fun re _ -> H.equal e re) urevts') *) (* more nodes on peterson, same on dekker *)
      | Atom.Comp (Access (a, [e]), _, _)
      | Atom.Comp (_, _, Access (a, [e]))
           when is_event a -> HSet.mem e keep
      | Atom.Comp (t1, _, t2) ->
         let k1 = match t1 with
         | Access (f, [e]) | Arith (Access (f, [e]), _)
              when is_value f -> HSet.mem e keep
         | _ -> true in
         let k2 = match t2 with
         | Access (f, [e]) | Arith (Access (f, [e]), _)
              when is_value f -> HSet.mem e keep
         | _ -> true in
         k1 && k2
      | _ -> true
    ) sa in

    (* Simplify here in case adding reads added duplicates *)
    try (Cube.simplify_atoms sa) :: pres (* Cube.create_normal ? *)
    with Exit -> pres

  ) [] wrcp in pres

end in

  (* TimeSatRead.pause (); *)

  pres
  *)

  [sa]




(* Make check for unsatisifed recv : can't be sat from init *)



        
