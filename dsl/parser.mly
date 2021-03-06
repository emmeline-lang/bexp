(* Copyright (C) 2019 Types Logics Cats.

   This Source Code Form is subject to the terms of the Mozilla Public
   License, v. 2.0. If a copy of the MPL was not distributed with this
   file, You can obtain one at http://mozilla.org/MPL/2.0/. *)

%{
%}

%token BAR
%token COLON
%token QUESTION
%token SEMICOLON

%token EOF

%token NEWLINE_COMMAND
%token TAB_COMMAND

%token <string> IDENT
%token <string> OCAML_CODE
%token <string> STRING_LIT

%start <Syntax.t> file

%%

let symbol :=
  | ident = IDENT; { Syntax.Nonterminal ident }
  | string = STRING_LIT; { Syntax.String string }
  | QUESTION; default = STRING_LIT; { Syntax.Input default }
  | NEWLINE_COMMAND; { Syntax.Newline }
  | TAB_COMMAND; { Syntax.Tab }

let production :=
  | prod_name = IDENT; COLON; symbols = list(symbol); action_str = OCAML_CODE;
    { { Syntax.prod_name; symbols
      ; action = { action_str; action_pos = $startpos(action_str) } } }

let nonterminal :=
  | nt_name = IDENT; COLON;
    option(BAR); productions = separated_list(BAR, production); SEMICOLON;
    { { Syntax.nt_name; productions } }

let file :=
  | op = OCAML_CODE;
    nonterminals = list(nonterminal);
    ed = OCAML_CODE;
    EOF;
    { { Syntax.op = { action_str = op; action_pos = $startpos(op) }
      ; nonterminals
      ; ed = { action_str = ed; action_pos = $startpos(ed) } } }
