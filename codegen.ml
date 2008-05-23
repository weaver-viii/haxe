(*
 *  Haxe Compiler
 *  Copyright (c)2005-2008 Nicolas Cannasse
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *)
 
open Ast
open Type
open Common
open Typecore

(* -------------------------------------------------------------------------- *)
(* REMOTING PROXYS *)

let rec reverse_type t =
	match t with
	| TEnum (e,params) ->
		TPNormal { tpackage = fst e.e_path; tname = snd e.e_path; tparams = List.map reverse_param params }
	| TInst (c,params) ->
		TPNormal { tpackage = fst c.cl_path; tname = snd c.cl_path; tparams = List.map reverse_param params }
	| TType (t,params) ->
		TPNormal { tpackage = fst t.t_path; tname = snd t.t_path; tparams = List.map reverse_param params }
	| TFun (params,ret) ->
		TPFunction (List.map (fun (_,_,t) -> reverse_type t) params,reverse_type ret)
	| TAnon a ->
		TPAnonymous (PMap.fold (fun f acc ->
			(f.cf_name , Some f.cf_public, AFVar (reverse_type f.cf_type), null_pos) :: acc
		) a.a_fields [])
	| TDynamic t2 ->
		TPNormal { tpackage = []; tname = "Dynamic"; tparams = if t == t2 then [] else [TPType (reverse_type t2)] }
	| _ ->
		raise Exit

and reverse_param t =
	TPType (reverse_type t)

(*/*
let extend_remoting ctx c t p async prot =
	if c.cl_super <> None then error "Cannot extend several classes" p;
	if ctx.isproxy then
		() (* skip this proxy generation, we shouldn't need it anyway *)
	else
	let ctx2 = context ctx.com in
	(* remove forbidden packages *)
	let rules = ctx.com.package_rules in
	ctx.com.package_rules <- PMap.foldi (fun key r acc -> match r with Forbidden -> acc | _ -> PMap.add key r acc) rules PMap.empty;
	ctx2.isproxy <- true;
	let ct = (try load_normal_type ctx2 t p false with e -> ctx.com.package_rules <- rules; raise e) in
	ctx.com.package_rules <- rules;
	let tvoid = TPNormal { tpackage = []; tname = "Void"; tparams = [] } in
	let make_field name args ret =
		try
			let targs = List.map (fun (a,o,t) -> a, o, Some (reverse_type t)) args in
			let tret = reverse_type ret in
			let eargs = [EArrayDecl (List.map (fun (a,_,_) -> (EConst (Ident a),p)) args),p] in
			let targs , tret , eargs = if async then
				match tret with
				| TPNormal { tpackage = []; tname = "Void" } -> targs , tvoid , eargs @ [EConst (Ident "null"),p]
				| _ -> targs @ ["__callb",true,Some (TPFunction ([tret],tvoid))] , tvoid , eargs @ [EUntyped (EConst (Ident "__callb"),p),p]
			else
				targs, tret , eargs
			in
			let idname = EConst (String name) , p in
			(FFun (name,None,[APublic],[], {
				f_args = targs;
				f_type = Some tret;
				f_expr = (EBlock [
					(EReturn (Some (EUntyped (ECall (
						(EField (
							(ECall (
								(EField ((EConst (Ident "__cnx"),p),"resolve"),p),
								[if prot then idname else ECall ((EConst (Ident "__unprotect__"),p),[idname]),p]
							),p)
						,"call"),p),eargs
					),p),p)),p)
				],p);
			}),p)
		with
			Exit -> error ("Field " ^ name ^ " type is not complete and cannot be used by RemotingProxy") p
	in
	let class_fields = (match ct with
		| TInst (c,params) ->
			(FVar ("__cnx",None,[],Some (TPNormal { tpackage = ["haxe";"remoting"]; tname = if async then "AsyncConnection" else "Connection"; tparams = [] }),None),p) ::
			(FFun ("new",None,[APublic],[],{ f_args = ["c",false,None]; f_type = None; f_expr = (EBinop (OpAssign,(EConst (Ident "__cnx"),p),(EConst (Ident "c"),p)),p) }),p) ::
			PMap.fold (fun f acc ->
				if not f.cf_public then
					acc
				else match follow f.cf_type with
				| TFun (args,ret) when f.cf_get = NormalAccess && (f.cf_set = NormalAccess || f.cf_set = MethodCantAccess) && f.cf_params = [] ->
					make_field f.cf_name args ret :: acc
				| _ -> acc
			) c.cl_fields []
		| _ ->
			error "Remoting type parameter should be a class" p
	) in
	let class_decl = (EClass {
		d_name = t.tname;
		d_doc = None;
		d_params = [];
		d_flags = [];
		d_data = class_fields;
	},p) in
	let m = (try Hashtbl.find ctx2.modules (t.tpackage,t.tname) with Not_found -> assert false) in
	let mdecl = (List.map (fun (m,t) -> (EImport (fst m.mpath, snd m.mpath, t),p)) m.mimports) @ [class_decl] in
	let m = (!type_module_ref) ctx ("Remoting" :: t.tpackage,t.tname) mdecl p in
	c.cl_super <- Some (match m.mtypes with
		| [TClassDecl c] -> (c,[])
		| _ -> assert false
	)
*/*)

(* -------------------------------------------------------------------------- *)
(* HAXE.RTTI.GENERIC *)

let build_generic ctx c p tl =
	let pack = fst c.cl_path in
	let recurse = ref false in
	let rec check_recursive t =
		match follow t with
		| TInst (c,tl) ->
			if c.cl_kind = KTypeParameter then recurse := true;
			List.iter check_recursive tl;
		| _ ->
			()
	in
	let name = String.concat "_" (snd c.cl_path :: (List.map (fun t ->
		check_recursive t;
		let path = (match follow t with
			| TInst (c,_) -> c.cl_path
			| TEnum (e,_) -> e.e_path
			| _ -> error "Type parameter must be a class or enum instance" p
		) in
		match path with
		| [] , name -> name
		| l , name -> String.concat "_" l ^ "_" ^ name
	) tl)) in
	if !recurse then begin
		TInst (c,tl)
	end else try
		Typeload.load_normal_type ctx { tpackage = pack; tname = name; tparams = [] } p false
	with Error(Module_not_found path,_) when path = (pack,name) ->
		(* try to find the module in which the generic class was originally defined *)
		let mpath = (if c.cl_private then match List.rev (fst c.cl_path) with [] -> assert false | x :: l -> List.rev l, String.sub x 1 (String.length x - 1) else c.cl_path) in
		let mtypes = try (Hashtbl.find ctx.modules mpath).mtypes with Not_found -> [] in
		let ctx = { ctx with local_types = mtypes @ ctx.local_types } in
		let cg = mk_class (pack,name) c.cl_pos None false in
		let mg = {
			mpath = cg.cl_path;
			mtypes = [TClassDecl cg];
			mimports = [];
		} in
		Hashtbl.add ctx.modules mg.mpath mg;
		let rec loop l1 l2 =
			match l1, l2 with
			| [] , [] -> []
			| (x,TLazy f) :: l1, _ -> loop ((x,(!f)()) :: l1) l2
			| (_,t1) :: l1 , t2 :: l2 -> (t1,t2) :: loop l1 l2
			| _ -> assert false
		in
		let subst = loop c.cl_types tl in
		let rec build_type t =
			match t with
			| TInst ({ cl_kind = KGeneric } as c,tl) ->
				(* maybe loop, or generate cascading generics *)
				Typeload.load_type ctx p (reverse_type (TInst (c,List.map build_type tl)))
			| _ ->
				try List.assq t subst with Not_found -> Type.map build_type t
		in
		let rec build_expr e =
			let t = build_type e.etype in
			match e.eexpr with
			| TFunction f ->
				{
					eexpr = TFunction {
						tf_args = List.map (fun (n,o,t) -> n, o, build_type t) f.tf_args;
						tf_type = build_type f.tf_type;
						tf_expr = build_expr f.tf_expr;
					};
					etype = t;
					epos = e.epos;
				}
			| TNew (c,tl,el) ->
				let c, tl = (match follow t with TInst (c,tl) -> c, tl | _ -> assert false) in
				{
					eexpr = TNew (c,tl,List.map build_expr el);
					etype = t;
					epos = e.epos;
				};
			| TVars vl ->
				{
					eexpr = TVars (List.map (fun (v,t,eo) ->
						v, build_type t, (match eo with None -> None | Some e -> Some (build_expr e))
					) vl);
					etype = t;
					epos = e.epos;
				}
			(* there's still some 't' lefts in TFor, TMatch and TTry *)
			| _ ->
				Type.map_expr build_expr { e with etype = t }
		in
		let build_field f =
			let t = build_type f.cf_type in
			{ f with cf_type = t; cf_expr = (match f.cf_expr with None -> None | Some e -> Some (build_expr e)) }
		in
		if c.cl_super <> None || c.cl_init <> None || c.cl_dynamic <> None then error "This class can't be generic" p;
		if c.cl_ordered_statics <> [] then error "A generic class can't have static fields" p;
		cg.cl_kind <- KGenericInstance (c,tl);
		cg.cl_constructor <- (match c.cl_constructor with None -> None | Some c -> Some (build_field c));
		cg.cl_implements <- List.map (fun (i,tl) -> i, List.map build_type tl) c.cl_implements;
		cg.cl_ordered_fields <- List.map (fun f ->
			let f = build_field f in
			cg.cl_fields <- PMap.add f.cf_name f cg.cl_fields;
			f
		) c.cl_ordered_fields;
		TInst (cg,[])

(* -------------------------------------------------------------------------- *)
(* HAXE.XML.PROXY *)

let extend_xml_proxy ctx c t file p =
	let t = Typeload.load_type ctx p t in
	let file = (try Common.find_file ctx.com file with Not_found -> file) in
	try
		let rec loop = function
			| Xml.Element (_,attrs,childs) ->
				(try
					let id = List.assoc "id" attrs in
					if PMap.mem id c.cl_fields then error ("Duplicate id " ^ id) p;
					let f = {
						cf_name = id;
						cf_type = t;
						cf_public = true;
						cf_doc = None;
						cf_get = ResolveAccess;
						cf_set = NoAccess;
						cf_params = [];
						cf_expr = None;
					} in
					c.cl_fields <- PMap.add id f c.cl_fields;
				with
					Not_found -> ());
				List.iter loop childs;
			| Xml.PCData _ -> ()
		in
		loop (Xml.parse_file file)
	with
		| Xml.Error e -> error ("XML error " ^ Xml.error e) p
		| Xml.File_not_found f -> error ("XML File not found : " ^ f) p

(* -------------------------------------------------------------------------- *)
(* API EVENTS *)

let build_instance ctx mtype p =
	match mtype with
	| TClassDecl c ->
		c.cl_types , c.cl_path , (match c.cl_kind with KGeneric -> build_generic ctx c p | _ -> (fun t -> TInst (c,t)))
	| TEnumDecl e ->
		e.e_types , e.e_path , (fun t -> TEnum (e,t))
	| TTypeDecl t ->
		t.t_types , t.t_path , (fun tl -> TType(t,tl))

let on_inherit ctx c p h =
	match h with
(*/*
	| HExtends { tpackage = ["haxe";"remoting"]; tname = "Proxy"; tparams = [TPType(TPNormal t)] } ->
		extend_remoting ctx c t p false true;
		false
	| HExtends { tpackage = ["haxe";"remoting"]; tname = "AsyncProxy"; tparams = [TPType(TPNormal t)] } ->
		extend_remoting ctx c t p true true;
		false
	| HExtends { tpackage = ["mt"]; tname = "AsyncProxy"; tparams = [TPType(TPNormal t)] } ->
		extend_remoting ctx c t p true false;
		false
*/*)
	| HImplements { tpackage = ["haxe";"rtti"]; tname = "Generic"; tparams = [] } ->
		c.cl_kind <- KGeneric;
		false
	| HExtends { tpackage = ["haxe";"xml"]; tname = "Proxy"; tparams = [TPConst(String file);TPType t] } ->
		extend_xml_proxy ctx c t file p;
		true
	| _ ->
		true

let rec has_rtti c =
	List.exists (function (t,pl) ->
		match t, pl with
		| { cl_path = ["haxe";"rtti"],"Infos" },[] -> true
		| _ -> false
	) c.cl_implements || (match c.cl_super with None -> false | Some (c,_) -> has_rtti c)

let on_generate ctx t =
	match t with
	| TClassDecl c when has_rtti c ->
		let f = mk_field "__rtti" ctx.api.tstring in
		let str = Genxml.gen_type_string ctx.com t in
		f.cf_expr <- Some (mk (TConst (TString str)) f.cf_type c.cl_pos);
		c.cl_ordered_statics <- f :: c.cl_ordered_statics;
		c.cl_statics <- PMap.add f.cf_name f c.cl_statics;
	| _ ->
		()

(* -------------------------------------------------------------------------- *)
(* PER-BLOCK VARIABLES *)

(*
	This algorithm ensure that variables used in loop sub-functions are captured
	by value. It transforms the following expression :

	for( x in array )
		funs.push(function() return x);

	Into the following :

	for( x in array )
		funs.push(function(x) { function() return x; }(x));

	This way, each value is captured independantly.	
*)

let block_vars e =
	let add_var map v d = map := PMap.add v d (!map) in
	let wrap e used =
		match PMap.foldi (fun v _ acc -> v :: acc) used [] with
		| [] -> e
		| vars ->
			mk (TCall (
				(mk (TFunction {
					tf_args = List.map (fun v -> v , false, t_dynamic) vars;
					tf_type = t_dynamic;
					tf_expr = mk (TReturn (Some e)) t_dynamic e.epos;
				}) t_dynamic e.epos),
				List.map (fun v -> mk (TLocal v) t_dynamic e.epos) vars)
			) t_dynamic e.epos
	in
	let rec in_fun vars depth used_locals e =
		match e.eexpr with
		| TLocal v ->
			(try
				if PMap.find v vars = depth then add_var used_locals v depth;				
			with
				Not_found -> ())
		| _ ->
			iter (in_fun vars depth used_locals) e

	and in_loop vars depth e =
		match e.eexpr with
		| TVars l ->
			{ e with eexpr = TVars (List.map (fun (v,t,e) ->
				let e = (match e with None -> None | Some e -> Some (in_loop vars depth e)) in
				add_var vars v depth;
				v, t, e
			) l) }
		| TFor (v,t,i,e1) ->
			let new_vars = PMap.add v depth (!vars) in
			{ e with eexpr = TFor (v,t,in_loop vars depth i,in_loop (ref new_vars) depth e1) }
		| TTry (e1,cases) ->
			let e1 = in_loop vars depth e1 in
			let cases = List.map (fun (v,t,e) ->
				let new_vars = PMap.add v depth (!vars) in
				v , t, in_loop (ref new_vars) depth e
			) cases in
			{ e with eexpr = TTry (e1,cases) }
		| TMatch (e1,t,cases,def) ->
			let e1 = in_loop vars depth e1 in
			let cases = List.map (fun (cl,params,e) ->
				let e = (match params with
					| None -> in_loop vars depth e
					| Some l ->
						let new_vars = List.fold_left (fun acc (v,t) ->
							match v with
							| None -> acc
							| Some name -> PMap.add name depth acc
						) (!vars) l in
						in_loop (ref new_vars) depth e
				) in
				cl , params, e
			) cases in
			let def = (match def with None -> None | Some e -> Some (in_loop vars depth e)) in
			{ e with eexpr = TMatch (e1, t, cases, def) }
		| TBlock l ->
			let new_vars = (ref !vars) in
			map_expr (in_loop new_vars depth) e
		| TFunction _ ->
			let new_vars = !vars in
			let used = ref PMap.empty in
			iter (in_fun new_vars depth used) e;
			let e = wrap e (!used) in
			let new_vars = ref (PMap.foldi (fun v _ acc -> PMap.remove v acc) (!used) new_vars) in
			map_expr (in_loop new_vars (depth + 1)) e
		| _ ->
			map_expr (in_loop vars depth) e
	and out_loop e =
		match e.eexpr with
		| TFor _ | TWhile _ ->
			in_loop (ref PMap.empty) 0 e
		| _ ->
			map_expr out_loop e
	in
	out_loop e

(* -------------------------------------------------------------------------- *)
(* STACK MANAGEMENT EMULATION *)

let emk e = mk e (mk_mono()) null_pos

let stack_var = "$s"
let exc_stack_var = "$e"
let stack_var_pos = "$spos"
let stack_e = emk (TLocal stack_var)
let stack_pop = emk (TCall (emk (TField (stack_e,"pop")),[]))

let stack_push useadd (c,m) =
	emk (TCall (emk (TField (stack_e,"push")),[
		if useadd then
			emk (TBinop (
				OpAdd,
				emk (TConst (TString (s_type_path c.cl_path ^ "::"))),
				emk (TConst (TString m))
			))
		else
			emk (TConst (TString (s_type_path c.cl_path ^ "::" ^ m)))
	]))

let stack_save_pos =
	emk (TVars [stack_var_pos, t_dynamic, Some (emk (TField (stack_e,"length")))])

let stack_restore_pos =
	let ev = emk (TLocal exc_stack_var) in
	[
	emk (TBinop (OpAssign, ev, emk (TArrayDecl [])));
	emk (TWhile (
		emk (TBinop (OpGte,
			emk (TField (stack_e,"length")),
			emk (TLocal stack_var_pos)
		)),
		emk (TCall (
			emk (TField (ev,"unshift")),
			[emk (TCall (
				emk (TField (stack_e,"pop")),
				[]
			))]
		)),
		NormalWhile
	));
	emk (TCall (emk (TField (stack_e,"push")),[ emk (TArray (ev,emk (TConst (TInt 0l)))) ]))
	]

let rec stack_block_loop e =
	match e.eexpr with
	| TFunction _ ->
		e
	| TReturn None | TReturn (Some { eexpr = TConst _ }) | TReturn (Some { eexpr = TLocal _ }) ->
		mk (TBlock [
			stack_pop;
			e;
		]) e.etype e.epos
	| TReturn (Some e) ->
		mk (TBlock [
			mk (TVars ["$tmp", t_dynamic, Some (stack_block_loop e)]) t_dynamic e.epos;
			stack_pop;
			mk (TReturn (Some (mk (TLocal "$tmp") t_dynamic e.epos))) t_dynamic e.epos
		]) e.etype e.epos
	| TTry (v,cases) ->
		let v = stack_block_loop v in
		let cases = List.map (fun (n,t,e) ->
			let e = stack_block_loop e in
			let e = (match (mk_block e).eexpr with
				| TBlock l -> mk (TBlock (stack_restore_pos @ l)) e.etype e.epos
				| _ -> assert false
			) in
			n , t , e
		) cases in
		mk (TTry (v,cases)) e.etype e.epos
	| _ ->
		map_expr stack_block_loop e

let stack_block ?(useadd=false) ctx e =	
	match (mk_block e).eexpr with
	| TBlock l -> mk (TBlock (stack_push useadd ctx :: stack_save_pos :: List.map stack_block_loop l @ [stack_pop])) e.etype e.epos
	| _ -> assert false

(* -------------------------------------------------------------------------- *)
(* MISC FEATURES *)

let local_find flag vname e =
	let rec loop2 e =
		match e.eexpr with
		| TFunction f ->
			if not flag && not (List.exists (fun (a,_,_) -> a = vname) f.tf_args) then loop2 f.tf_expr
		| TBlock _ ->
			(try
				Type.iter loop2 e;
			with
				Not_found -> ())
		| TVars vl ->
			List.iter (fun (v,t,e) ->
				(match e with
				| None -> ()
				| Some e -> loop2 e);
				if v = vname then raise Not_found;
			) vl
		| TConst TSuper ->
			if vname = "super" then raise Exit
		| TLocal v ->
			if v = vname then raise Exit
		| _ ->
			iter loop2 e
	in
	let rec loop e =
		match e.eexpr with
		| TFunction f ->
			if not (List.exists (fun (a,_,_) -> a = vname) f.tf_args) then loop2 f.tf_expr
		| TBlock _ ->
			(try
				iter loop e;
			with
				Not_found -> ())
		| TVars vl ->
			List.iter (fun (v,t,e) ->
				(match e with
				| None -> ()
				| Some e -> loop e);
				if v = vname then raise Not_found;
			) vl
		| _ ->
			iter loop e
	in
	try
		(if flag then loop2 else loop) e;
		false
	with
		Exit ->
			true

let rec is_volatile t =
	match t with
	| TMono r ->
		(match !r with
		| Some t -> is_volatile t
		| _ -> false)
	| TLazy f ->
		is_volatile (!f())
	| TType (t,tl) ->
		(match t.t_path with
		| ["mt";"flash"],"Volatile" -> true
		| _ -> is_volatile (apply_params t.t_types tl t.t_type))
	| _ ->
		false
