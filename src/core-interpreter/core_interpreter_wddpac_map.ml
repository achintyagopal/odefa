open Batteries;;
open Jhupllib;;

open Core_ast;;
(* open Core_ast_pp;; *)

open Unbounded_context_stack_map;;
open Wddpac_graph_map;;

let lazy_logger = Logger_utils.make_lazy_logger "Interpreter";;

module Environment = Var_hashtbl;;

exception Evaluation_failure of string;;

let rv body =
  match body with
  | [] -> raise @@ Utils.Invariant_failure "empty function body provided to rv"
  | _ -> let Clause(x,_) = List.last body in x
;;

let rec initialize_graph cls graph =
  match cls with
  | [] -> ()
  | (Clause(x, cl2) as cl) :: tl ->
    begin
      match cl2 with
      | Value_body(Value_function(Function_value(x', Expr(e))) as f) ->

        Wddpac_graph_map.add_edge (x', Start_clause(Some(x'))) graph;
        initialize_graph e graph;

        Wddpac_graph_map.add_edge (x, Function(x', rv e, f)) graph;
        initialize_graph tl graph

      | Conditional_body(xc,p, Function_value(x1, Expr(e1)), Function_value(x2, Expr(e2))) ->

        Wddpac_graph_map.add_edge (x1, Start_clause(Some(x1))) graph;
        initialize_graph e1 graph;

        Wddpac_graph_map.add_edge (x2, Start_clause(Some(x2))) graph;
        initialize_graph e2 graph;

        Wddpac_graph_map.add_edge (x, Conditional_clause(xc,p,x1,rv e1, x2, rv e2)) graph;
        initialize_graph tl graph

      | _ ->
        Wddpac_graph_map.add_edge (x, Unannotated_clause(cl)) graph;
        initialize_graph tl graph
    end
;;

let rec matches v p =
  match v,p with
  | _,Any_pattern -> true
  | Return_function _,Fun_pattern
  | Return_int _,Int_pattern ->
    true
  | Return_bool actual_boolean,Bool_pattern pattern_boolean ->
    actual_boolean = pattern_boolean
  | _ -> false
;;

let rec lookup graph var context_stack call_by_need =
  (* Align *)
  let Graph_node(node) = Wddpac_graph_map.lookup var graph in

  (* Process Graph Node *)
  begin
    match node with

    | Unannotated_clause(Clause(x, cl)) ->
      if x <> var then (
        raise @@ Utils.Invariant_failure ("Found no definitions for variable from exit clause 1" )
      )
      else
        begin
          match cl with
          | Var_body(x') ->
            (* print_endline "Alias";  *)
            lookup graph x' context_stack call_by_need
          | Value_body(Value_int(v)) ->
            Return_int(v)
          | Value_body(Value_bool(v)) ->
            Return_bool(v)
          | Appl_body(xf, xv) ->
            (* print_endline "Lookup function"; *)
            let fn = lookup graph xf context_stack call_by_need in

            begin
              match fn with
              | Return_function(fn_ctx, rx, _, cfn_stack) ->
                  if call_by_need then lookup graph rx (Context_table.add fn_ctx (ref (Context_var_table(xv, context_stack))) cfn_stack) call_by_need
                  else (
                    let v = lookup graph xv context_stack call_by_need in
                    lookup graph rx (Context_table.add fn_ctx (ref (Return_type(v))) cfn_stack) call_by_need
                  )
              | _ -> raise @@ Utils.Invariant_failure "Found incorrect definitions for function 2"
            end
          | Binary_operation_body(x1,Binary_operator_plus,x2) ->
            let v1 = lookup graph x1 context_stack call_by_need in
            let v2 = lookup graph x2 context_stack call_by_need in
            begin
              match v1, v2 with
              | Return_int(n1), Return_int(n2) -> Return_int(n1 + n2)
              | _,_ ->
               raise @@ Evaluation_failure "Can only add integers"
            end
          | Binary_operation_body(x1,Binary_operator_uint_plus,x2) ->
            let v1 = lookup graph x1 context_stack call_by_need in
            let v2 = lookup graph x2 context_stack call_by_need in
            begin
              match v1, v2 with
              | Return_uint(n1), Return_uint(n2) -> Return_uint(n1 + n2)
              | _,_ ->
               raise @@ Evaluation_failure "Can only add integers"
            end
          | Binary_operation_body(x1,Binary_operator_int_minus,x2) ->
            let v1 = lookup graph x1 context_stack call_by_need in
            let v2 = lookup graph x2 context_stack call_by_need in
            begin
              match v1, v2 with
              | Return_int(n1), Return_int(n2) -> Return_int(n1 - n2)
              | _,_ ->
               raise @@ Evaluation_failure "Can only subtract integers"
            end
          | Binary_operation_body(x1,Binary_operator_uint_minus,x2) ->
            let v1 = lookup graph x1 context_stack call_by_need in
            let v2 = lookup graph x2 context_stack call_by_need in
            begin
              match v1, v2 with
              | Return_uint(n1), Return_uint(n2) ->
                if n1 - n2 < 0 then Return_uint(0) else Return_uint(n1 - n2)
              | _,_ ->
               raise @@ Evaluation_failure "Can only subtract integers"
            end
          | Binary_operation_body(x1,Binary_operator_equal_to,x2) ->
            let v1 = lookup graph x1 context_stack call_by_need in
            let v2 = lookup graph x2 context_stack call_by_need in
            begin
              match v1, v2 with
              | Return_int(n1), Return_int(n2) -> Return_bool(n1 == n2)
              | _,_ ->
               raise @@ Evaluation_failure "Can only equate integers"
            end
          | Binary_operation_body(x1,Binary_operator_uint_equal_to,x2) ->
            let v1 = lookup graph x1 context_stack call_by_need in
            let v2 = lookup graph x2 context_stack call_by_need in
            begin
              match v1, v2 with
              | Return_uint(n1), Return_uint(n2) -> Return_bool(n1 == n2)
              | _,_ ->
               raise @@ Evaluation_failure "Can only equate integers"
            end
          | Binary_operation_body(x1,Binary_operator_int_less_than,x2) ->
            let v1 = lookup graph x1 context_stack call_by_need in
            let v2 = lookup graph x2 context_stack call_by_need in
            begin
              match v1, v2 with
              | Return_int(n1), Return_int(n2) -> Return_bool(n1 < n2)
              | _,_ ->
               raise @@ Evaluation_failure "Can only compare less than on integers"
            end
          | Binary_operation_body(x1,Binary_operator_uint_less_than,x2) ->
            let v1 = lookup graph x1 context_stack call_by_need in
            let v2 = lookup graph x2 context_stack call_by_need in
            begin
              match v1, v2 with
              | Return_uint(n1), Return_uint(n2) -> Return_bool(n1 < n2)
              | _,_ ->
               raise @@ Evaluation_failure "Can only compare less than on integers"
            end

          | Binary_operation_body(x1, Binary_operator_int_less_than_or_equal_to, x2) ->
            let v1 = lookup graph x1 context_stack call_by_need in
            let v2 = lookup graph x2 context_stack call_by_need in
            begin
              match v1, v2 with
              | Return_int(n1), Return_int(n2) -> Return_bool(n1 <= n2)
              | _,_ ->
               raise @@ Evaluation_failure "Can only compare less than or equal to on integers"
            end
          | Binary_operation_body(x1, Binary_operator_uint_less_than_or_equal_to, x2) ->
            let v1 = lookup graph x1 context_stack call_by_need in
            let v2 = lookup graph x2 context_stack call_by_need in
            begin
              match v1, v2 with
              | Return_uint(n1), Return_uint(n2) -> Return_bool(n1 <= n2)
              | _,_ ->
               raise @@ Evaluation_failure "Can only compare less than or equal to on integers"
            end
          | Binary_operation_body(x1,Binary_operator_bool_and,x2) ->
            begin
              match lookup graph x1 context_stack call_by_need with
              | Return_bool(b) ->
                if not b then Return_bool(false) else
                  begin
                    match lookup graph x2 context_stack call_by_need with
                    | Return_bool(b) -> Return_bool(b)
                    | _ ->
                     raise @@ Evaluation_failure "Can only and booleans"
                  end
              | _ ->
               raise @@ Evaluation_failure "Can only and booleans"
            end
          | Binary_operation_body(x1,Binary_operator_bool_or,x2) ->
            begin
              match lookup graph x1 context_stack call_by_need with
              | Return_bool(b) ->
                if b then Return_bool(true) else
                  begin
                    match lookup graph x2 context_stack call_by_need with
                    | Return_bool(b) -> Return_bool(b)
                    | _ ->
                     raise @@ Evaluation_failure "Can only or booleans"
                  end
              | _ ->
               raise @@ Evaluation_failure "Can only or booleans"
            end
          | Unary_operation_body(op,x1) ->
            let v1 = lookup graph x1 context_stack call_by_need in
            begin
              match op, v1 with
              | Unary_operator_bool_not, Return_bool(b1) -> Return_bool(not b1)
              | _,_ ->
               raise @@ Evaluation_failure "Incorrect unary operation"
            end

          | _ -> raise @@ Utils.Invariant_failure "Usage of not implemented clause"
        end
    | Start_clause(None) ->
      raise @@ Utils.Invariant_failure ("Found no definitions for variable 4")
    | Start_clause(Some(x0)) ->
      (* print_endline "Start Clause"; *)
      let x = Context_table.find x0 context_stack in
      begin
        match !x with
        | Return_type(v) -> v
        | Context_var_table(xv, ctx_stack) ->
          let v = lookup graph xv ctx_stack call_by_need in
          x := Return_type(v);
          v
      end
    | Function(x0,rx, f) ->
      Return_function(x0, rx, f, context_stack)
    | Conditional_clause(xc, p, x1,rx1,x2,rx2) ->
      let v = lookup graph xc context_stack call_by_need in
      let fn_ctx, rx = if matches v p then (x1,rx1) else (x2,rx2) in
      lookup graph rx (Context_table.add fn_ctx (ref (Return_type(v))) context_stack) call_by_need
  end
;;

let rec substitute_return v graph env call_by_need =
  match v with
  | Return_bool(v) -> Value_bool(v)
  | Return_int(v) -> Value_int(v)
  | Return_uint(v) -> Value_uint(v)
  | Return_function(_, _,f,  context_stack) -> substitute f graph context_stack env call_by_need
and substitute v graph context_stack env call_by_need =
  match v with
  | Value_function(Function_value(x, Expr(e))) ->
    Var_hashtbl.add env x "0";
    Value_function(Function_value(x, Expr(substitute_expr e graph context_stack env call_by_need)))
  | _ -> v
and substitute_expr e graph context_stack env call_by_need =
  match e with
  | Clause(x, Value_body(v)) :: tl ->

    let v = substitute v graph context_stack env call_by_need in
    Var_hashtbl.add env x "0";
    Clause(x, Value_body(v)) :: substitute_expr tl graph context_stack env call_by_need

  | (Clause(x, Unary_operation_body(_,x')) as hd) :: tl
  | (Clause(x, Var_body(x')) as hd) :: tl ->

      let assignments = process_vars (x' :: []) graph context_stack env call_by_need in
      Var_hashtbl.add env x "0";
      (assignments @ [hd]) @ substitute_expr tl graph context_stack env call_by_need
  | (Clause(x, Binary_operation_body(x',_,x'')) as hd) :: tl
  | (Clause(x, Appl_body(x', x'')) as hd) :: tl ->

      let assignments = process_vars (x' :: x'' :: []) graph context_stack env call_by_need in
      Var_hashtbl.add env x "0";
      (assignments @ [hd]) @ substitute_expr tl graph context_stack env call_by_need

  | Clause(x, Conditional_body(x',op,f1,f2)) :: tl ->
    let assignments = process_vars (x' :: []) graph context_stack env call_by_need in
    let f1 = substitute (Value_function(f1)) graph context_stack env call_by_need in
    let f2 = substitute (Value_function(f2)) graph context_stack env call_by_need in
    Var_hashtbl.add env x "0";
    begin
      match f1,f2 with
      | Value_function(f1), Value_function(f2) ->
        (assignments @ ([Clause(x, Conditional_body(x',op,f1,f2))])) @ substitute_expr tl graph context_stack env call_by_need
      | _, _ -> raise @@ Utils.Invariant_failure "Incorrect substitution of function"
    end
  | _ -> []
and process_vars vars graph context_stack env call_by_need =
  List.enum vars
  |> Enum.filter (fun x -> not (Var_hashtbl.mem env x))
  |> Enum.map (fun x ->
      let v = lookup graph x context_stack call_by_need in
      Var_hashtbl.add env x "0";
      Clause(x, Value_body(substitute_return v graph (Var_hashtbl.create 10) call_by_need)))
  |> List.of_enum
;;

let eval (Expr(cls)) call_by_need : Core_ast.var * value Core_interpreter.Environment.t =
  let context_stack = Context_table.empty in
  let graph = Wddpac_graph_map.empty in
  initialize_graph cls graph;
  let rx = rv cls in
  let v = lookup graph rx context_stack call_by_need in
  let v = substitute_return v graph (Var_hashtbl.create 10) call_by_need in
  let env = Core_interpreter.Environment.create 10 in
  Core_interpreter.Environment.add env (rv cls) v;
  (rv cls), env
;;
