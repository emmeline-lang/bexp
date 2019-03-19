open Core_kernel
open Js_of_ocaml
open Types

let create ?x ?y ~width ~height  =
  let doc = Dom_svg.document in
  let group = new Widget.group ?x ?y ~width ~height doc in
  { toolbox_group = group
  ; palette = None }

let set_palette toolbox palette =
  toolbox.palette <- Some (Palette palette);
  ignore
    (toolbox.toolbox_group#element##appendChild
       (palette.palette_group#element :> Dom.node Js.t))

let render toolbox =
  Option.iter toolbox.palette ~f:(fun palette ->
      let width, _ = Palette.render palette in
      toolbox.toolbox_group#set_width width
    )