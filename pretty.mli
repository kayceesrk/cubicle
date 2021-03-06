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

open Format

(** Pretty printing functions *)

val vt_width : int
(** Width of the virtual terminal (80 if cannot be detected) *)

val print_line : formatter -> unit -> unit
(** prints separating line *)

val print_double_line : formatter -> unit -> unit
(** prints separating double line *)

val print_title : formatter -> string -> unit
(** prints section title for stats *)

val print_list :
  (formatter -> 'a -> unit) ->
  ('b, formatter, unit) format -> formatter -> 'a list -> unit
(** [print_list f sep fmt l] prints list [l] whose elements are printed with
    [f], each of them being separated by the separator [sep]. *)
