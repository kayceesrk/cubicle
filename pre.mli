(**************************************************************************)
(*                                                                        *)
(*                              Cubicle                                   *)
(*                                                                        *)
(*                       Copyright (C) 2011-2014                          *)
(*                                                                        *)
(*                  Sylvain Conchon and Alain Mebsout                     *)
(*                       Universite Paris-Sud 11                          *)
(*                                                                        *)
(*                                                                        *)
(*  This file is distributed under the terms of the Apache Software       *)
(*  License version 2.0                                                   *)
(*                                                                        *)
(**************************************************************************)

open Ast
open Types

(** Pre-image computation *)
type reset_memo = unit -> unit
			    
val make_tau : transition_info -> transition_func * reset_memo
(** functional form of transition *)

val pre_image : transition list -> Node.t -> Node.t list * Node.t list
(** [pre-image tau n] returns the pre-image of [n] by the transition relation
    [tau] as a disjunction of cubes in the form of two lists of new nodes. The
    second list is used to store nodes to postpone depending on a predefined
    strategy. *)
