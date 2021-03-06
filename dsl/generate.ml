(* Copyright (C) 2019 Types Logics Cats.

   This Source Code Form is subject to the terms of the Mozilla Public
   License, v. 2.0. If a copy of the MPL was not distributed with this
   file, You can obtain one at http://mozilla.org/MPL/2.0/. *)

open Base

type t = {
    buf : Buffer.t;
    mutable indentation : int;
    indent : string;
    mutable line : int;
    out_file_name : string;
  }

let indent t f =
  t.indentation <- t.indentation + 1;
  f t;
  t.indentation <- t.indentation - 1

let count_newlines =
  let rec f acc idx str =
    if idx = String.length str then
      acc
    else if Char.equal (String.get str idx) '\n' then
      f (acc + 1) (idx + 1) str
    else
      f acc (idx + 1) str
  in f 0 0

let add_string t str =
  t.line <- t.line + count_newlines str;
  Buffer.add_string t.buf str

let add_char t c =
  if Char.equal c '\n' then
    t.line <- t.line + 1;
  Buffer.add_char t.buf c

let add_newline t =
  t.line <- t.line + 1;
  Buffer.add_char t.buf '\n'

let tab t =
  for _ = 1 to t.indentation do
    add_string t t.indent
  done

let print_line t f =
  tab t;
  let r = f t in
  add_newline t;
  r

let print_strln t str =
  print_line t (fun t -> add_string t str)

let rec print_concat ?(sep="") t = function
  | [] -> ()
  | [str] -> add_string t str
  | str :: strs ->
     add_string t str;
     print_concat ~sep t strs

let print_concatln ?sep t strs =
  print_line t (fun t -> print_concat ?sep t strs)

let get_arity symbols =
  List.fold symbols ~init:0 ~f:(fun acc next ->
      match next with
      | Syntax.Nonterminal _ | Input _ -> acc + 1
      | _ -> acc
    )

let getter ~arity ~idx =
  let rec gen_pattern str i target_index = function
    | 0 -> str ^ ")"
    | 1 -> str ^ if i = target_index then "x)" else "_)"
    | n ->
       let p = if i = target_index then "x" else "_" in
       gen_pattern (str ^ p ^ ", ") (i + 1) target_index (n - 1)
  in "fun " ^ (gen_pattern "(" 0 idx arity) ^ " -> x"

let arity =
  List.fold ~init:0 ~f:(fun acc next ->
      match next with
      | Syntax.Nonterminal _ | Input _ -> acc + 1
      | _ -> acc
    )

let emit_inputs t =
  let rec f idx = function
    | [] -> ()
    | (Syntax.Input default) :: xs ->
       print_line t (fun t ->
           List.iter ~f:(add_string t)
             [ "let input"
             ; Int.to_string idx
             ; " = Bexp.Widget.create_text_input \""
             ; String.escaped default
             ; "\" in" ]
         );
       f (idx + 1) xs
    | _ :: xs -> f idx xs
  in f 0

let emit_symbols t arity =
  let print_symbol idx input_idx = function
    | Syntax.String str ->
       add_string t "Bexp.Syntax.text \"";
       add_string t (String.escaped str);
       add_char t '"';
       idx, input_idx
    | Nonterminal name ->
       List.iter ~f:(add_string t)
         [ "Bexp.Syntax.nt "
         ; "(" ^ getter ~arity ~idx ^ ")"
         ; " "; name; "_data" ];
       idx + 1, input_idx
    | Input _ ->
       List.iter ~f:(add_string t)
         [ "Bexp.Syntax.widget input"
         ; Int.to_string input_idx
         ; " ("
         ; getter ~arity ~idx
         ; ")" ];
       idx + 1, input_idx + 1
    | Tab ->
       add_string t "Bexp.Syntax.tab";
       idx, input_idx
    | Newline ->
       add_string t "Bexp.Syntax.newline";
       idx, input_idx
  in
  let rec print_symbols idx input_idx = function
    | [] ->
       add_string t "]"
    | [symbol] ->
       let _ = print_symbol idx input_idx symbol in
       add_string t " ]"
    | symbol :: next ->
       let idx, input_idx = print_symbol idx input_idx symbol in
       add_char t '\n';
       tab t;
       add_string t "; ";
       print_symbols idx input_idx next
  in
  add_string t "[ ";
  print_symbols 0 0

let filter_args =
  List.filter ~f:(function
      | Syntax.Input _ | Nonterminal _ -> true
      | _ -> false
    )

let emit_create t list =
  let print_elem t idx input_idx symbol f = match symbol with
    | Syntax.Input _ ->
       List.iter ~f:(add_string t)
         [ "Bexp.Widget.create_text_input input"
         ; Int.to_string input_idx
         ; "#value" ];
       f t;
       idx + 1, input_idx + 1
    | Nonterminal name ->
       List.iter ~f:(add_string t)
         [ "Bexp.Hole.create get_"; name; " "; name; "_data" ];
       f t;
       idx + 1, input_idx
    | _ -> idx, input_idx
  in
  let rec print_create t idx input_idx = function
    | [] -> add_char t ')'
    | [symbol] ->
       let _ = print_elem t idx input_idx symbol (fun _t -> ()) in
       add_string t " )"
    | symbol :: next ->
       let idx, input_idx =
         print_elem t idx input_idx symbol (fun t ->
             add_newline t;
             tab t;
             add_string t ", "
           ) in
       print_create t idx input_idx next
  in
  add_string t "fun () ->\n";
  indent t (fun t ->
      tab t;
      add_string t "( ";
      print_create t 0 0 (filter_args list)
    )

let emit_action t action =
  add_string t "\n# ";
  add_string t (Int.to_string action.Syntax.action_pos.Lexing.pos_lnum);
  add_string t " \"";
  add_string t (String.escaped action.action_pos.Lexing.pos_fname);
  add_string t "\"\n";
  add_string t action.action_str;
  add_string t "\n# ";
  add_string t (Int.to_string t.line);
  add_string t " \"";
  add_string t (String.escaped t.out_file_name);
  add_string t "\"\n"

let emit_prod t nt_name prod =
  print_line t (fun t ->
      add_string t "let ";
      add_string t prod.Syntax.prod_name;
      add_string t "_def ="
    );
  indent t (fun t ->
      emit_inputs t prod.Syntax.symbols;
      print_strln t "Bexp.Syntax.create";
      indent t (fun t ->
          let arity = arity prod.symbols in
          print_line t (fun t -> emit_symbols t arity prod.symbols);
          print_line t (fun t ->
              add_string t "~create:(";
              emit_create t prod.symbols;
              add_char t ')'
            );
          print_line t (fun t ->
              add_string t "~to_term:(";
              emit_action t prod.action;
              add_char t ')');
          print_line t (fun t ->
              add_string t "~symbol_of_term:symbol_of_";
              add_string t nt_name)))

let emit_deflist t =
  let rec f = function
    | [] -> add_string t " ]"
    | [prod] ->
       add_string t
         ("Bexp.Syntax " ^ prod.Syntax.prod_name ^ "_def ]")
    | prod :: next ->
       add_string t
         ("Bexp.Syntax " ^ prod.Syntax.prod_name ^ "_def");
       add_string t "; ";
       f next
  in
  add_string t "[";
  f

let emit_nonterminal t nt =
  List.iter nt.Syntax.productions ~f:(fun prod ->
      print_line t (fun t -> emit_prod t nt.Syntax.nt_name prod);
    )

let emit_palette t prev nt =
  print_strln t ("let " ^ nt.Syntax.nt_name ^ "_palette =");
  indent t (fun t ->
      print_strln t ("Bexp.Palette.create ctx " ^ prev);
      indent t (fun t ->
          print_strln t (nt.nt_name ^ "_data");
          print_line t (fun t ->
              emit_deflist t nt.productions
            )
        )
    )

let emit_toplevel out_file_name file =
  let t =
    { buf = Buffer.create 1000
    ; indentation = 0
    ; indent = "  "
    ; line = 1
    ; out_file_name } in
  emit_action t file.Syntax.op;
  let nt's_rev =
    let rec f acc = function
      | [] -> acc
      | nt :: nt's ->
         emit_nonterminal t nt;
         f (nt :: acc) nt's
    in f [] file.Syntax.nonterminals
  in
  let rec f prev = function
    | [] -> ()
    | nt :: nt's ->
       emit_palette t prev nt;
       f ("(Some (Bexp.Palette " ^ nt.nt_name ^ "_palette))") nt's
  in
  f "None" nt's_rev;
  emit_action t file.ed;
  t.buf
