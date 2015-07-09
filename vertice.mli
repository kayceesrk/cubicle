type t
(* conjonction of universally quantified clauses, world*)
type ucnf
(* disjunction of exisentially quantified conjunctions, bad *)
type ednf

type t_kind

type res_ref =
  | Bad_Parent of (int * Cube.t list)
  | Covered of t
  | Extrapolated of t

val create_world : (Variable.t list * Types.SAtom.t) list -> ucnf
val create_bad : (Variable.t list * Types.SAtom.t) list -> ednf

val create : ?is_root:bool -> ?creation:(t * Ast.transition * t) -> ucnf -> 
  Cube.t -> t_kind -> Types.SAtom.t ->  Cube.t option -> t
val delete_parent : t -> t * Ast.transition -> bool
val add_parent : t -> t * Ast.transition -> unit
val get_subsume : t -> (t * Ast.transition) list

val update_bad_from : t -> Ast.transition -> t -> unit
val update_world_from : t -> t -> unit

(* hashtype signature *)
val hash : t -> int
val equal : t -> t -> bool

(* orderedtype signature *)
val compare : t -> t -> int

(* display functions *)
val print_vertice : Format.formatter -> t -> unit
val save_vertice : Format.formatter -> t -> unit
val print_id : Format.formatter -> t -> unit
val save_id : Format.formatter -> t -> unit
val print_bad : Format.formatter -> t -> unit

(* Interface with dot *)
val add_node_dot : t -> unit
val add_node_extra : t -> unit
val add_node_step : t -> string -> unit
val add_subsume_dot : t -> unit
val add_subsume_step : t -> unit
  
val add_relation_step : ?color:string -> ?style:string -> 
  t -> t -> Ast.transition -> unit
val add_relation_extra : t -> unit

(* ic3 base functions *)
  
(* Create a list of nodes from the node
   w.r.t the Ast.transitions *)
val expand : t -> Ast.transition list -> Ast.transition list 
  
val refine : t -> t -> Ast.transition -> t list -> res_ref

(* If bad is empty, our node is safe,
   else, our node is unsafe *)
val is_bad : t -> bool
