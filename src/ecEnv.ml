(* -------------------------------------------------------------------- *)
open EcUtils
open EcSymbols
open EcPath
open EcTypes
open EcFol
open EcMemory
open EcDecl
open EcModules
open EcTheory
open EcWhy3
open EcBaseLogic
(* -------------------------------------------------------------------- *)
module Ssym = EcSymbols.Ssym
module Msym = EcSymbols.Msym
module Mp   = EcPath.Mp
module Mid  = EcIdent.Mid

(* -------------------------------------------------------------------- *)
type ctheory_w3 = {
  cth3_rebind : EcWhy3.rebinding;
  cth3_theory : ctheory;
}

let ctheory_of_ctheory_w3 (cth : ctheory_w3) =
  cth.cth3_theory

(* -------------------------------------------------------------------- *)
type 'a suspension = {
  sp_target : 'a;
  sp_params : (EcIdent.t * module_type) list;
}

exception IsSuspended

let suspend (x : 'a) params =
  { sp_target = x;
    sp_params = params; }

let sp_target { sp_target = x } = x

let is_suspended (x : 'a suspension) =
  x.sp_params <> []

let check_not_suspended (x : 'a suspension) =
  if is_suspended x then raise IsSuspended;
  x.sp_target

let unsuspend f (x : 'a suspension) (args : mpath list) =
  try
    let s =
      List.fold_left2
        (fun s (x, _) a -> EcSubst.add_module s x a)
        EcSubst.empty x.sp_params args
    in
     f s x.sp_target

  with Invalid_argument "List.fold_left2" ->
    assert false

(* -------------------------------------------------------------------- *)
type lookup_failure = [
  | `Path    of path
  | `QSymbol of qsymbol
]

exception LookupFailure of lookup_failure
exception DuplicatedBinding of symbol

let try_lf (f : unit -> 'a) =
  try Some (f ()) with LookupFailure _ -> None

(* -------------------------------------------------------------------- *)
type ipath =[
  | `Abstract of EcIdent.t
  | `Concrete of EcPath.path
]

module IPathComparable = struct
  type t = ipath

  let compare (ip1 : ipath) (ip2 : ipath) =
    match ip1, ip2 with
    | `Abstract x1, `Abstract x2 ->
        EcIdent.id_compare x1 x2

    | `Concrete p1, `Concrete p2 ->
        EcPath.p_compare p1 p2

    | `Abstract _, `Concrete _ -> -1
    | `Concrete _, `Abstract _ ->  1
end

module IPath = struct

end

module Mip = EcMaps.Map.Make(IPathComparable)

(* -------------------------------------------------------------------- *)
type varbind = {
  vb_type  : EcTypes.ty;
  vb_kind  : EcTypes.pvar_kind;
}

type preenv = {
  env_scope    : path * modenv option;
  env_current  : actmc;
  env_comps    : mc Mip.t;
  env_locals   : (EcIdent.t * EcTypes.ty) MMsym.t;
  env_memories : EcMemory.memenv MMsym.t;
  env_actmem   : EcMemory.memory option;
  env_w3       : EcWhy3.env;
  env_rb       : EcWhy3.rebinding;        (* in reverse order *)
  env_item     : ctheory_item list        (* in reverse order *)
}

and thmc = {
  thmc_modules    : (mpath * EcModules.module_expr)  Msym.t;
  thmc_modtypes   : ( path * EcModules.module_sig)   Msym.t;
  thmc_typedecls  : ( path * EcDecl.tydecl)          Msym.t;
  thmc_operators  : ( path * EcDecl.operator)        Msym.t;
  thmc_axioms     : ( path * EcDecl.axiom)           Msym.t;
  thmc_theories   : ( path * ctheory)                Msym.t;
  thmc_components : path Msym.t;
}

and modmc = {
  modmc_variables  : (xpath * varbind)               Msym.t;
  modmc_functions  : (xpath * EcModules.function_)   Msym.t;
  modmc_modules    : (mpath * EcModules.module_expr) Msym.t;
  modmc_components : path Msym.t;
}

and actmc = {
  amc_modules    : (mpath * EcModules.module_expr) MMsym.t;
  amc_modtypes   : ( path * EcModules.module_sig)  MMsym.t;
  amc_typedecls  : ( path * EcDecl.tydecl)         MMsym.t;
  amc_operators  : ( path * EcDecl.operator)       MMsym.t;
  amc_axioms     : ( path * EcDecl.axiom)          MMsym.t;
  amc_theories   : ( path * ctheory)               MMsym.t;
  amc_variables  : (xpath * varbind)               MMsym.t;
  amc_functions  : (xpath * EcModules.function_)   MMsym.t;
  amc_components : ipath MMsym.t;
}

and mc = [
  | `Theory of path * thmc
  | `Module of mpath_top * (EcIdent.t * module_type) list * modmc
]

and modenv = EcPath.path

type gmc = [`ActMc of actmc | `Mc of mc]

(* -------------------------------------------------------------------- *)
type env = preenv

(* -------------------------------------------------------------------- *)
let empty_thmc = {
  thmc_modules    = Msym.empty;
  thmc_modtypes   = Msym.empty;
  thmc_typedecls  = Msym.empty;
  thmc_operators  = Msym.empty;
  thmc_axioms     = Msym.empty;
  thmc_theories   = Msym.empty;
  thmc_components = Msym.empty;
}

and empty_modmc = {
  modmc_variables  = Msym.empty;
  modmc_functions  = Msym.empty;
  modmc_modules    = Msym.empty;
  modmc_components = Msym.empty;
}

and empty_actmc = {
  amc_modules    = MMsym.empty;
  amc_modtypes   = MMsym.empty;
  amc_typedecls  = MMsym.empty;
  amc_operators  = MMsym.empty;
  amc_axioms     = MMsym.empty;
  amc_theories   = MMsym.empty;
  amc_variables  = MMsym.empty;
  amc_functions  = MMsym.empty;
  amc_components = MMsym.empty;
}

(* -------------------------------------------------------------------- *)
let empty =
  let path = EcPath.psymbol EcCoreLib.id_top
  and name = EcCoreLib.id_top in
  let env  =
    { env_scope    = (path, None);
      env_current  = { empty_actmc with
                         amc_components =
                           MMsym.add name (`Concrete path) MMsym.empty; };
      env_comps    = Mip.singleton (`Concrete path) (`Theory (path, empty_thmc));
      env_locals   = MMsym.empty;
      env_memories = MMsym.empty;
      env_actmem   = None;
      env_w3       = EcWhy3.empty;
      env_rb       = [];
      env_item     = [];
    }
  in
    env

(* -------------------------------------------------------------------- *)
let preenv (env : preenv) : env = env

(* -------------------------------------------------------------------- *)
module MC = struct
  let top_path = EcPath.psymbol EcCoreLib.id_top

  (* ------------------------------------------------------------------ *)
  let path_of_qn (top : EcPath.path) (qn : symbol list) =
    List.fold_left EcPath.pqname top qn

  let lookup_mc (qn : symbol list) (env : env) : gmc option =
    match qn with
    | [] -> Some (`ActMc env.env_current)

    | top :: qn -> begin
        match MMsym.last top env.env_current.amc_components with
        | None -> None
        | Some p -> begin
            match
              match p with
              | `Abstract _ when qn = [] -> Some p
              | `Abstract _ -> None
              | `Concrete p -> Some (`Concrete (path_of_qn p qn))
            with
            | None   -> None
            | Some p -> omap (Mip.find_opt p env.env_comps) (fun x -> `Mc x)
          end
      end

  (* ------------------------------------------------------------------ *)
  module Px = struct
    type ('mc, 'path, 'a) px = {
      px_get      : 'mc -> ('path * 'a) Msym.t;
      px_set      : ('path * 'a) Msym.t -> 'mc -> 'mc;
      px_act_get  : actmc -> ('path * 'a) MMsym.t;
      px_act_set  : ('path * 'a) MMsym.t -> actmc -> actmc;
      px_basename : 'path -> symbol;
    }

    (* ---------------------------------------------------------------- *)
    let for_variable : (modmc, xpath, varbind) px = {
      px_get = (fun mc -> mc.modmc_variables);
      px_set = (fun map mc -> { mc with modmc_variables = map });
      px_act_get = (fun mc -> mc.amc_variables);
      px_act_set = (fun map mc -> { mc with amc_variables = map });
      px_basename = (fun xp -> EcPath.basename xp.EcPath.x_sub);
    }

    (* ---------------------------------------------------------------- *)
    let for_function : (modmc, xpath, function_) px = {
      px_get = (fun mc -> mc.modmc_functions);
      px_set = (fun map mc -> { mc with modmc_functions = map });
      px_act_get = (fun mc -> mc.amc_functions);
      px_act_set = (fun map mc -> { mc with amc_functions = map });
      px_basename = (fun xp -> EcPath.basename xp.EcPath.x_sub);
    }

    (* ---------------------------------------------------------------- *)
    let for_module_modmc : (modmc, mpath, module_expr) px = {
      px_get = (fun mc -> mc.modmc_modules);
      px_set = (fun map mc -> { mc with modmc_modules = map });
      px_act_get = (fun mc -> mc.amc_modules);
      px_act_set = (fun map mc -> { mc with amc_modules = map });

      px_basename = (function p ->
        match p.EcPath.m_top with
        | `Abstract x -> EcIdent.name x
        | `Concrete (p, None) -> EcPath.basename p
        | `Concrete (_, Some p) -> EcPath.basename p);
    }

    (* ---------------------------------------------------------------- *)
    let for_module_thmc : (thmc, mpath, module_expr) px = {
      px_get = (fun mc -> mc.thmc_modules);
      px_set = (fun map mc -> { mc with thmc_modules = map });
      px_act_get = (fun mc -> mc.amc_modules);
      px_act_set = (fun map mc -> { mc with amc_modules = map });

      px_basename = (function p ->
        match p.EcPath.m_top with
        | `Abstract x -> EcIdent.name x
        | `Concrete (p, None) -> EcPath.basename p
        | `Concrete (_, Some p) -> EcPath.basename p);
    }

    (* ---------------------------------------------------------------- *)
    let for_modtype : (thmc, path, module_sig) px = {
      px_get = (fun mc -> mc.thmc_modtypes);
      px_set = (fun map mc -> { mc with thmc_modtypes = map });
      px_act_get = (fun mc -> mc.amc_modtypes);
      px_act_set = (fun map mc -> { mc with amc_modtypes = map });
      px_basename = EcPath.basename
    }

    (* ---------------------------------------------------------------- *)
    let for_typedecl : (thmc, path, tydecl) px = {
      px_get = (fun mc -> mc.thmc_typedecls);
      px_set = (fun map mc -> { mc with thmc_typedecls = map });
      px_act_get = (fun mc -> mc.amc_typedecls);
      px_act_set = (fun map mc -> { mc with amc_typedecls = map });
      px_basename = EcPath.basename
    }

    (* ---------------------------------------------------------------- *)
    let for_operator : (thmc, path, operator) px = {
      px_get = (fun mc -> mc.thmc_operators);
      px_set = (fun map mc -> { mc with thmc_operators = map });
      px_act_get = (fun mc -> mc.amc_operators);
      px_act_set = (fun map mc -> { mc with amc_operators = map });
      px_basename = EcPath.basename
    }

    (* ---------------------------------------------------------------- *)
    let for_axiom : (thmc, path, axiom) px = {
      px_get = (fun mc -> mc.thmc_axioms);
      px_set = (fun map mc -> { mc with thmc_axioms = map });
      px_act_get = (fun mc -> mc.amc_axioms);
      px_act_set = (fun map mc -> { mc with amc_axioms = map });
      px_basename = EcPath.basename
    }

    (* ---------------------------------------------------------------- *)
    let for_theory : (thmc, path, ctheory) px = {
      px_get = (fun mc -> mc.thmc_theories);
      px_set = (fun map mc -> { mc with thmc_theories = map });
      px_act_get = (fun mc -> mc.amc_theories);
      px_act_set = (fun map mc -> { mc with amc_theories = map });
      px_basename = EcPath.basename
    }
  end

  (* ------------------------------------------------------------------ *)
  let mc_lookup1 px x mc =
    match mc with
    | `Mc mc ->
        Msym.find_opt x (px.Px.px_get mc)

    | `ActMc mc ->
        MMsym.last x (px.Px.px_act_get mc)

  let mc_lookupall px x mc =
    match mc with
    | `Mc mc ->
        otolist (Msym.find_opt x (px.Px.px_get mc))

    | `ActMc mc ->
        MMsym.all x (px.Px.px_act_get mc)

  (* ------------------------------------------------------------------ *)
  let _params_of_mc (gmc : gmc) =
    match gmc with
    | `ActMc _
    | `Mc (`Theory _) -> []
    | `Mc (`Module (_, a, _)) -> a

  let lookup px ((qn, x) : qsymbol) (env : env) =
    match lookup_mc qn env with
    | None ->
        raise (LookupFailure (`QSymbol (qn, x)))

    | Some mc -> begin
        match mc_lookup1 px x mc with
        | None ->
            raise (LookupFailure (`QSymbol (qn, x)))

        | Some (p, obj) ->
            (p, suspend obj (_params_of_mc mc))
      end

  let lookupall px ((qn, x) : qsymbol) (env : env) =
    match lookup_mc qn env with
    | None -> raise (LookupFailure (`QSymbol (qn, x)))
    | Some mc ->
        List.map
          (fun (p, obj) -> (p, suspend obj (_params_of_mc mc)))
          (mc_lookupall px x mc)

  (* ------------------------------------------------------------------ *)
  let modmc_bind_raw px name path obj mc =
    let map = px.Px.px_get mc in
      match Msym.find_opt name map with
      | Some _ -> raise (DuplicatedBinding name)
      | None   -> px.Px.px_set (Msym.add name (path, obj) map) mc

  let modmc_bind px path obj mc =
    modmc_bind_raw px (px.Px.px_basename path) path obj mc

  let thmc_bind_raw px name path obj mc =
    let map = px.Px.px_get mc in
      match Msym.find_opt name map with
      | Some _ -> raise (DuplicatedBinding name)
      | None   -> px.Px.px_set (Msym.add name (path, obj) map) mc

  let thmc_bind px path obj mc =
    thmc_bind_raw px (px.Px.px_basename path) path obj mc

  let modmc_bind_variable path obj mc = modmc_bind Px.for_variable path obj mc
  let modmc_bind_function path obj mc = modmc_bind Px.for_function path obj mc
  let modmc_bind_module   path obj mc = modmc_bind Px.for_module_modmc path obj mc
  let thmc_bind_module    path obj mc = thmc_bind  Px.for_module_thmc  path obj mc
  let thmc_bind_modtype   path obj mc = thmc_bind  Px.for_modtype  path obj mc
  let thmc_bind_typedecl  path obj mc = thmc_bind  Px.for_typedecl path obj mc
  let thmc_bind_operator  path obj mc = thmc_bind  Px.for_operator path obj mc
  let thmc_bind_axiom     path obj mc = thmc_bind  Px.for_axiom    path obj mc
  let thmc_bind_theory    path obj mc = thmc_bind  Px.for_theory   path obj mc

  let modmc_bind_mc (path : EcPath.path) mc =
    let name = EcPath.basename path in
      if Msym.find_opt name mc.modmc_components <> None then
        raise (DuplicatedBinding name);
      { mc with
          modmc_components = Msym.add name path mc.modmc_components; }

  let thmc_bind_mc (path : EcPath.path) mc =
    let name = EcPath.basename path in
      if Msym.find_opt name mc.thmc_components <> None then
        raise (DuplicatedBinding name);
      { mc with
          thmc_components = Msym.add name path mc.thmc_components; }

  let amc_bind px x path obj mc =
    let map = px.Px.px_act_get mc in
    let obj = (path, obj) in
      px.Px.px_act_set (MMsym.add x obj map) mc

  let amc_bind_mc (path : ipath) mc =
    let name =
      match path with
      | `Abstract x -> EcIdent.name x
      | `Concrete p -> EcPath.basename p
    in
      { mc with
          amc_components = MMsym.add name path mc.amc_components; }

  (* ------------------------------------------------------------------ *)
  let rec mc_of_module_r (scope : path) (sub : (mpath list * path) option) (me : module_expr) =
    assert (me.me_sig.mis_params = [] || sub <> None);

    let params = me.me_sig.mis_params in
    let params = List.map (fun (x, _) -> EcPath.mpath_abs x []) params in

    let (params, sub) =
      match sub with
      | None -> (params, None)
      | Some (params, sub) -> (params, Some sub)
    in

    let xpath x =
      EcPath.xpath (EcPath.mpath_crt scope params sub) (EcPath.psymbol x)
    in

    let mc1_of_module (mc : modmc) = function
    | MI_Module subme ->
        let submcs =
          mc_of_module_r scope
            (Some (params, EcPath.pqoname sub me.me_name)) subme
        and mepath =
          EcPath.mpath_crt scope params (Some (EcPath.pqoname sub me.me_name))
        in
          (modmc_bind_module mepath subme
             (modmc_bind_mc (path_of_mpath mepath) mc),
           Some submcs)

    | MI_Variable v ->
        let vty =
          { vb_type = v.v_type;
            vb_kind = PVglob; }
        in
          (modmc_bind_variable (xpath v.v_name) vty mc, None)

    | MI_Function f ->
        (modmc_bind_function (xpath f.f_name) f mc, None)

    in

    let (mc, submcs) =
      List.map_fold mc1_of_module empty_modmc me.me_comps
    in
      (me.me_name, `Module (mc, List.prmap (fun x -> x) submcs))

  let mc_of_module (env : env) (me : module_expr) =
    mc_of_module_r (fst env.env_scope) None me

  (* ------------------------------------------------------------------ *)
  let mc_of_module_param (mid : EcIdent.t) (me : module_expr) =
    let params = me.me_sig.mis_params in
    let params = List.map (fun (x, _) -> EcPath.mpath_abs x []) params in

    let xpath (x : symbol) =
      EcPath.xpath (mpath_abs mid params) (EcPath.psymbol x)
    in

    let mc1_of_module (mc : modmc) = function
      | MI_Module _ -> assert false

      | MI_Variable v ->
          let vty =
            { vb_type = v.v_type;
              vb_kind = PVglob; }
          in
            modmc_bind_raw Px.for_variable v.v_name (xpath v.v_name) vty mc


      | MI_Function f ->
          modmc_bind_raw Px.for_function f.f_name (xpath f.f_name) f mc
    in
      List.fold_left mc1_of_module empty_modmc me.me_comps

  (* ------------------------------------------------------------------ *)
  let rec mc_of_ctheory_r (scope : EcPath.path) (x, th) =
    let subscope = EcPath.pqname scope x in
    let expath = fun x -> EcPath.pqname subscope x in

    let mc1_of_ctheory (mc : thmc) = function
      | CTh_type (xtydecl, tydecl) ->
          (thmc_bind_typedecl (expath xtydecl) tydecl mc, None)

      | CTh_operator (xop, op) ->
          (thmc_bind_operator (expath xop) op mc, None)

      | CTh_axiom (xax, ax) ->
          (thmc_bind_axiom (expath xax) ax mc, None)

      | CTh_modtype (xmodty, modty) ->
          (thmc_bind_modtype (expath xmodty) modty mc, None)

      | CTh_module subme ->
          let xpath  = expath subme.me_name in
          let submcs = mc_of_module_r subscope None subme in
          (thmc_bind_module (mpath_crt xpath [] None) subme
             (thmc_bind_mc xpath mc),
           Some submcs)

      | CTh_theory (xsubth, subth) ->
          let xpath = expath xsubth in
          let submcs =
            mc_of_ctheory_r subscope (xsubth, subth)
          in
            (thmc_bind_theory xpath subth (thmc_bind_mc xpath mc), Some submcs)

      | CTh_export _ -> (mc, None)
    in

    let (mc, submcs) =
      List.map_fold mc1_of_ctheory empty_thmc th.cth_struct
    in
      (x, `Theory (mc, List.prmap (fun x -> x) submcs))

  let mc_of_ctheory (env : env) (x : symbol) (th : ctheory) =
    mc_of_ctheory_r (fst env.env_scope) (x, th)

  (* ------------------------------------------------------------------ *)
  let thmc_bind px env path obj =
    let name = px.Px.px_basename path in

    { env with
        env_current =
          amc_bind px name path obj env.env_current;
        env_comps =
          Mip.change
            (function
             | Some (`Theory (p, mc)) ->
                 Some (`Theory (p, thmc_bind px path obj mc))
             | _ -> assert false)
            (`Concrete (fst env.env_scope))
            env.env_comps; }

  (* ------------------------------------------------------------------ *)
  let modmc_bind px env name obj =
    let path = EcPath.pqname (fst env.env_scope) name in

      { env with
          env_current =
            amc_bind px name path obj env.env_current;
          env_comps =
            Mip.change
              (function
               | Some (`Module (p, a, mc)) ->
                   Some (`Module (p, a, modmc_bind px path obj mc))
               | _ -> assert false)
              (`Concrete (fst env.env_scope))
              env.env_comps; }

  (* -------------------------------------------------------------------- *)
  let thmc_bind_mc env name comps =
    let env_scope = fst env.env_scope in
    let path = EcPath.pqname env_scope name
    in

      if Mip.find_opt (`Concrete path) env.env_comps <> None then
        raise (DuplicatedBinding name);

      { env with
          env_current = amc_bind_mc (`Concrete path) env.env_current;
          env_comps =
            Mip.change
              (function
               | Some (`Theory (p, mc)) ->
                   Some (`Theory (p, thmc_bind_mc path mc))
               | _ -> assert false)
              (`Concrete env_scope)
              (Mip.add (`Concrete path) comps env.env_comps); }

  (* -------------------------------------------------------------------- *)
  let import px env path obj =
    let bname = EcPath.basename (EcPath.path_of_mpath path) in
      { env with
          env_current = amc_bind px bname path obj env.env_current; }

  (* ------------------------------------------------------------------ *)
  let rec bind_submc env path ((name, mc), submcs) =
    let path = EcPath.pqname path name in

    if Mip.find_opt (`Concrete path) env.env_comps <> None then
      raise (DuplicatedBinding (EcPath.basename path));

    bind_submcs
      { env with env_comps = Mip.add (`Concrete path) mc env.env_comps }
      path submcs

  and bind_submcs env path submcs =
    List.fold_left (bind_submc^~ path) env submcs

  let bind_module x me env =
    let path = EcPath.pqname (fst env.env_scope) x in
    let mpath = EcPath.mpath_crt path [] None in

    let (_, `Module (mc, _submcs)) = mc_of_module env me in
    let env = thmc_bind Px.for_module_thmc env mpath me in
    let env =
      let path = `Concrete (path, None) in
        thmc_bind_mc env me.me_name (`Module (path, me.me_sig.mis_params, mc))
    in
      env
(*
    bind_submcs env
      (EcPath.pqname (EcPath.path_of_mpath env.env_scope) me.me_name)
      submcs
*)

  and bind_modtype x tymod env =
    assert (snd env.env_scope = None);

    let path = EcPath.pqname (fst env.env_scope) x in
      thmc_bind Px.for_modtype env path tymod

  and bind_typedecl x tydecl env =
    assert (snd env.env_scope = None);

    let path = EcPath.pqname (fst env.env_scope) x in
      thmc_bind Px.for_typedecl env path tydecl

  and bind_operator x op env =
    assert (snd env.env_scope = None);

    let path = EcPath.pqname (fst env.env_scope) x in
      thmc_bind Px.for_operator env path op

  and bind_axiom x ax env =
    assert (snd env.env_scope = None);

    let path = EcPath.pqname (fst env.env_scope) x in
      thmc_bind Px.for_axiom env path ax

  and bind_theory x cth env =
    assert (snd env.env_scope = None);

    let path = EcPath.pqname (fst env.env_scope) x in

    let (_, mc, _submcs) =
      match mc_of_ctheory env x cth with
      | (x, `Theory (mc, submcs)) -> (x, mc, submcs)
      | _ -> assert false
    in
    let env = thmc_bind Px.for_theory env path cth in
    let env = thmc_bind_mc env x (`Theory (path, mc)) in
      env

(*    bind_submcs env
      (EcPath.pqname (EcPath.path_of_mpath env.env_scope) x)
      submcs *)
end

(* -------------------------------------------------------------------- *)
let enter_theory (name : symbol) (env : env) =
  assert (snd env.env_scope = None);

  { env with
      env_scope = (EcPath.pqname (fst env.env_scope) name, None);
      env_rb    = [];
      env_item  = []; }

let enter_module (name : symbol) (env : env) =
  assert (snd env.env_scope = None);

  { env with
      env_scope = (fst env.env_scope, Some (EcPath.psymbol name));
      env_rb    = [];
      env_item  = []; }

(* -------------------------------------------------------------------- *)
type meerror =
| UnknownMemory of [`Symbol of symbol | `Memory of memory]

exception MEError of meerror

(* -------------------------------------------------------------------- *)
module Memory = struct

  let byid (me : memory) (env : env) =
    let memories = MMsym.all (EcIdent.name me) env.env_memories in
    let memories =
      List.filter
        (fun me' -> EcIdent.id_equal me (EcMemory.memory me'))
        memories
    in
      match memories with
      | []     -> None
      | m :: _ -> Some m

  let lookup (me : symbol) (env : env) =
    MMsym.last me env.env_memories

  let set_active (me : memory) (env : env) =
    match byid me env with
    | None   -> raise (MEError (UnknownMemory (`Memory me)))
    | Some _ -> { env with env_actmem = Some me }

  let get_active (env : env) =
    env.env_actmem

  let current (env : env) =
    match env.env_actmem with
    | None    -> None
    | Some me -> Some (oget (byid me env))

  let push (me : EcMemory.memenv) (env : env) =
    (* FIXME: assert (byid (EcMemory.memory me) env = None); *)

    let id = EcMemory.memory me in
    let maps =
      MMsym.add (EcIdent.name id) me env.env_memories
    in
      { env with env_memories = maps }

  let push_all memenvs env =
    List.fold_left
      (fun env m -> push m env)
      env memenvs

  let push_active memenv env =
    set_active (EcMemory.memory memenv)
      (push memenv env)
end

(* -------------------------------------------------------------------- *)
module Var = struct
  module Px = MC.Px

  type t = varbind

  let by_path (p : EcPath.path) (env : env) =
    MC.lookup_by_path Px.for_variable.Px.px_premc p env

  let by_path_opt (p : EcPath.path) (env : env) =
    try_lf (fun () -> by_path p env)

  let by_mpath (p : EcPath.mpath) (env : env) =
    let subst _s (x : varbind) = x in
    let x = by_path (EcPath.path_of_mpath p) env in
      unsuspend subst x (EcPath.args_of_mpath p)

  let by_mpath_opt (p : EcPath.mpath) (env : env) =
    try_lf (fun () -> by_mpath p env)

  let lookup_locals name env =
    MMsym.all name env.env_locals

  let lookup_local name env =
    match MMsym.last name env.env_locals with
    | None   -> raise (LookupFailure (`QSymbol ([], name)))
    | Some x -> x

  let lookup_local_opt name env =
    MMsym.last name env.env_locals

  let lookup_progvar ?side qname env =
    let inmem side =
      match fst qname with
      | [] ->
        let memenv = oget (Memory.byid side env) in
        if EcMemory.memtype memenv = None then None
        else
          let mp = EcMemory.mpath memenv in
          begin match EcMemory.lookup (snd qname) memenv with
          | None    -> None
          | Some ty ->
            let pv =
              { pv_name = EcPath.mqname mp EcPath.PKother (snd qname) [];
                pv_kind = PVloc; } in
            Some (pv, ty)
          end

      | _ -> None
    in
      match obind side inmem with
      | None -> begin
          let (p, x) = MC.lookup Px.for_variable qname env in
            if is_suspended x then
              raise (LookupFailure (`QSymbol qname));
            let x = x.sp_target in
              ({ pv_name = p; pv_kind = x.vb_kind }, x.vb_type)
        end

      | Some (pv, ty) -> (pv, ty)

  let lookup_progvar_opt ?side name env =
    try_lf (fun () -> lookup_progvar ?side name env)

  let bind name pvkind ty env =
    let vb = { vb_type = ty; vb_kind = pvkind; } in
      MC.bind_variable name vb env

  let bindall bindings pvkind env =
    List.fold_left
      (fun env (name, ty) -> bind name pvkind ty env)
      env bindings

   let bind_local name ty env =
     let s = EcIdent.name name in
       { env with
           env_locals = MMsym.add s (name, ty) env.env_locals }

   let bind_locals bindings env =
     List.fold_left
       (fun env (name, ty) -> bind_local name ty env)
       env bindings

  let add (path : EcPath.path) (env : env) =
    let obj = (by_path path env).sp_target in
      MC.import Px.for_variable env (EcPath.mpath_of_path path) obj
end

(* -------------------------------------------------------------------- *)
module Fun = struct
  module Px = MC.Px

  type t = EcModules.function_

  let by_path (p : EcPath.path) (env : env) =
    MC.lookup_by_path Px.for_function.Px.px_premc p env

  let by_path_opt (p : EcPath.path) (env : env) =
    try_lf (fun () -> by_path p env)

  let by_mpath (p : EcPath.mpath) (env : env) =
    let x = by_path (EcPath.path_of_mpath p) env in
    unsuspend EcSubst.subst_function x (EcPath.args_of_mpath p)

  let by_mpath_opt (p : EcPath.mpath) (env : env) =
    try_lf (fun () -> by_mpath p env)

  let lookup name (env : env) =
    let (p, x) = MC.lookup Px.for_function name env in
      if is_suspended x then
        raise (LookupFailure (`QSymbol name));
      (p, x.sp_target)

  let lookup_opt name env =
    try_lf (fun () -> lookup name env)

  let sp_lookup name (env : env) =
    let (p, x) = MC.lookup Px.for_function name env in
      (EcPath.path_of_mpath p, x)

  let sp_lookup_opt name env =
    try_lf (fun () -> sp_lookup name env)

  let lookup_path name env =
    fst (lookup name env)

  let bind name fun_ env =
    MC.bind_function name fun_ env

  let add (path : EcPath.path) (env : env) =
    let obj = (by_path path env).sp_target in
      MC.import Px.for_function env (EcPath.mpath_of_path path) obj

  let add_in_memenv memenv vd =
    EcMemory.bind vd.v_name vd.v_type memenv

  let adds_in_memenv = List.fold_left add_in_memenv

  let actmem_pre me path fun_ =
    let mem = EcMemory.empty_local me path in
    adds_in_memenv mem (fst fun_.f_sig.fs_sig)

  let actmem_post me path fun_ =
    let mem = EcMemory.empty_local me path in
    add_in_memenv mem {v_name = "res"; v_type = snd fun_.f_sig.fs_sig}

  let actmem_body me path fun_ =
    let mem = actmem_pre me path fun_ in
    match fun_.f_def with
    | None -> assert false (* FIXME error message *)
    | Some fd -> fd, adds_in_memenv mem fd.f_locals

  let actmem_body_anonym me path locals =
    let mem = EcMemory.empty_local me path in
    adds_in_memenv mem locals

  let prF path env =
    let fun_ = by_mpath path env in
    let post = actmem_post EcFol.mhr path fun_ in
    Memory.push_active post env

  let hoareF_memenv path env = 
    let fun_ = (by_path (EcPath.path_of_mpath path) env).sp_target in
    let pre = actmem_pre EcFol.mhr path fun_ in 
    let post = actmem_post EcFol.mhr path fun_ in 
    pre,post
    
  let hoareF path env = 
    let pre,post = hoareF_memenv path env in
    Memory.push_active pre env, Memory.push_active post env  

  let hoareS path env =
    let fun_ = by_mpath path env in
    let fd, memenv = actmem_body EcFol.mhr path fun_ in
    memenv, fd, Memory.push_active memenv env

  let hoareS_anonym locals env =
    let path = env.env_scope in
    let memenv = actmem_body_anonym EcFol.mhr path locals in
    memenv, Memory.push_active memenv env

  let equivF_memenv path1 path2 env = 
    let fun1 = (by_path (EcPath.path_of_mpath path1) env).sp_target in
    let fun2 = (by_path (EcPath.path_of_mpath path2) env).sp_target in
    let pre1 = actmem_pre EcFol.mleft path1 fun1 in
    let pre2 = actmem_pre EcFol.mright path2 fun2 in
    let post1 = actmem_post EcFol.mleft path1 fun1 in 
    let post2 = actmem_post EcFol.mright path2 fun2 in
    (pre1,pre2), (post1,post2)

  let equivF path1 path2 env = 
    let (pre1,pre2),(post1,post2) = equivF_memenv path1 path2 env in
    Memory.push_all [pre1; pre2] env,
    Memory.push_all [post1; post2] env

  let equivS path1 path2 env =
    let fun1 = by_mpath path1 env in
    let fun2 = by_mpath path2 env in
    let fd1, mem1 = actmem_body EcFol.mleft path1 fun1 in
    let fd2, mem2 = actmem_body EcFol.mright path2 fun2 in
    mem1, fd1, mem2, fd2, Memory.push_all [mem1; mem2] env

  let equivS_anonym locals1 locals2 env =
    let path1, path2 = env.env_scope, env.env_scope in
    let mem1 = actmem_body_anonym EcFol.mleft path1 locals1 in
    let mem2 = actmem_body_anonym EcFol.mright path2 locals2 in
    mem1, mem2, Memory.push_all [mem1; mem2] env

  let enter name env =
    enter name EcPath.PKother [] env
end

(* -------------------------------------------------------------------- *)
module Ty = struct
  module Px = MC.Px

  type t = EcDecl.tydecl

  let by_path (p : EcPath.path) (env : env) =
    check_not_suspended
      (MC.lookup_by_path Px.for_typedecl.Px.px_premc p env)

  let by_path_opt (p : EcPath.path) (env : env) =
    try_lf (fun () -> by_path p env)

  let lookup name (env : env) =
    let (p, x) = MC.lookup Px.for_typedecl name env in
    (EcPath.path_of_mpath p, check_not_suspended x)

  let lookup_opt name env =
    try_lf (fun () -> lookup name env)

  let lookup_path name env =
    fst (lookup name env)

  let add (path : EcPath.path) (env : env) =
    let obj = by_path path env in
    MC.import Px.for_typedecl env (EcPath.mpath_of_path path) obj

  let bind name ty env =
    let env = MC.bind_typedecl name ty env in
    let (w3, rb) =
        EcWhy3.add_ty env.env_w3
          (EcPath.pqname (EcPath.path_of_mpath env.env_scope) name) ty
    in
      { env with
          env_w3   = w3;
          env_rb   = rb @ env.env_rb;
          env_item = CTh_type (name, ty) :: env.env_item; }

  let rebind name ty env =
    MC.bind_typedecl name ty env

  let defined (name : EcPath.path) (env : env) =
    match by_path_opt name env with
    | Some { tyd_type = Some _ } -> true
    | _ -> false

  let unfold (name : EcPath.path) (args : EcTypes.ty list) (env : env) =
    match by_path_opt name env with
    | Some ({ tyd_type = Some body} as tyd) ->
        EcTypes.Tvar.subst (EcTypes.Tvar.init tyd.tyd_params args) body
    | _ -> raise (LookupFailure (`Path name))
end

(* -------------------------------------------------------------------- *)
module Mod = struct
  type t = module_expr

  module Px = MC.Px

  let by_path (p : EcPath.path) (env : env) =
    MC.lookup_by_path Px.for_module.Px.px_premc p env

  let by_path_opt (p : EcPath.path) (env : env) =
    try_lf (fun () -> by_path p env)

  let by_mpath (p : EcPath.mpath) (env : env) =
    let x = by_path (EcPath.path_of_mpath p) env in
      unsuspend EcSubst.subst_module x (EcPath.args_of_mpath p)

  let by_mpath_opt (p : EcPath.mpath) (env : env) =
    try_lf (fun () -> by_mpath p env)

  let lookup name (env : env) =
    let (p, x) = MC.lookup Px.for_module name env in
      if is_suspended x then
        raise (LookupFailure (`QSymbol name));
      (p, x.sp_target)

  let lookup_opt name env =
    try_lf (fun () -> lookup name env)

  let lookup_path name env =
    fst (lookup name env)

  let sp_lookup name (env : env) =
    let (p, x) = MC.lookup Px.for_module name env in
      (p, x)

  let sp_lookup_opt name env =
    try_lf (fun () -> sp_lookup name env)

  let bind name me env =
    assert (me.me_name = name);
    let env = MC.bind_module name me env in
    let (w3, rb) =
      EcWhy3.add_mod_exp env.env_w3
          (EcPath.pqname (EcPath.path_of_mpath env.env_scope) name) me in
    { env with
      env_w3 = w3;
      env_rb = rb @ env.env_rb;
      env_item = CTh_module me :: env.env_item }

  let bind_local name modty env =
    let modsig =
      let modsig =
        check_not_suspended
          (MC.lookup_by_path
             Px.for_modtype.Px.px_premc modty.mt_name env)
      in
        match modty.mt_args with
        | None -> modsig
        | Some args -> begin
          assert (List.length modsig.mis_params = List.length args);
          let subst =
            List.fold_left2
              (fun s (mid, _) arg ->
                EcSubst.add_module s mid arg)
              EcSubst.empty modsig.mis_params args
          in
            { (EcSubst.subst_modsig subst modsig) with mis_params = []; }
        end
    in

    let me    = module_expr_of_module_sig name modty modsig in
    let path  = EcPath.pident name in
    let comps = MC.mc_of_module_param name me  in

    let env =
      { env with
          env_current = (
            let current = env.env_current in
            let current = MC.amc_bind_mc path current in
            let current = MC.amc_bind Px.for_module
                            (EcIdent.name name) (EcPath.mident name)
                            me current
            in
              current);
          env_comps = Mp.add path comps env.env_comps; }
    in
      env

  let bind_locals bindings env =
    List.fold_left
      (fun env (name, me) -> bind_local name me env)
      env bindings

  let add (path : EcPath.path) (env : env) =
    let obj = (by_path path env).sp_target in
      MC.import Px.for_module env (EcPath.mpath_of_path path) obj

  let enter name params env =
    let env = enter name EcPath.PKmodule (List.map fst params) env in
    bind_locals params env

end

(* -------------------------------------------------------------------- *)
module NormMp = struct
  let rec norm_mpath env p =
    match oget (List.ohead p.EcPath.m_kind) with
    | EcPath.PKother  -> p
    | EcPath.PKmodule -> begin
        match Mod.by_path_opt (EcPath.path_of_mpath p) env with
        | Some ({ sp_target = { me_body = ME_Alias alias } } as def) ->
            let alias = { def with sp_target = alias } in
            let args  = EcPath.args_of_mpath p in
            let alias = unsuspend EcSubst.subst_mpath alias args in
              norm_mpath env alias

        | _ -> begin
            match EcPath.m_split p with
            | None -> p

            | Some(prefix, k, x, args) -> 
                let args = List.map (norm_mpath env) args in
                  EcPath.mqname (norm_mpath env prefix) k x args
          end
      end

  let norm_mpath env p =
    match EcPath.m_split p with
    | Some (prefix, (PKother as k), x, args) ->
        assert (args = []);
        EcPath.mqname (norm_mpath env prefix) k x []

    | None | Some (_, PKmodule, _, _) ->
        norm_mpath env p

  let norm_pvar env pv = 
    let p = norm_mpath env pv.pv_name in
    if m_equal p pv.pv_name then pv else { pv_name = p; pv_kind = pv.pv_kind }

  let norm_form env =
    let norm_mp = EcPath.Hm.memo 107 (norm_mpath env) in
    let norm_pv pv =
      let p = norm_mp pv.pv_name in
      if m_equal p pv.pv_name then pv else { pv_name = p; pv_kind = pv.pv_kind } in
    let norm_form =
      EcFol.Hf.memo_rec 107 (fun aux f ->
        match f.f_node with
        | Fquant(q,bd,f) ->               (* FIXME: norm module_type *)
          f_quant q bd (aux f)

        | Fpvar(p,m) ->
          let p' = norm_pv p in
          if p == p' then f else
            f_pvar p' f.f_ty m

        | FhoareF hf ->
          let pre' = aux hf.hf_pr and p' = norm_mp hf.hf_f
          and post' = aux hf.hf_po in
          if hf.hf_pr == pre' && hf.hf_f == p' && hf.hf_po == post' then f else
          f_hoareF pre' p' post'

(*        | FhoareS _ -> assert false (* FIXME ? Not implemented *) *)

        | FequivF ef ->
          let pre' = aux ef.ef_pr and l' = norm_mp ef.ef_fl
          and r' = norm_mp ef.ef_fr and post' = aux ef.ef_po in
          if ef.ef_pr == pre' && ef.ef_fl == l' &&
            ef.ef_fr == r' && ef.ef_po == post' then f else
          f_equivF pre' l' r' post'

(*        | FequivS _ -> assert false (* FIXME ? Not implemented *) *)

        | Fpr(m,p,args,e) ->
          let p' = norm_mp p in
          let args' = List.smart_map aux args in
          let e' = aux e in
          if p == p' && args == args' && e == e' then f else
          f_pr m p' args' e'

        | _ -> EcFol.f_map (fun ty -> ty) aux f) in
    norm_form

  let norm_op env op =
    match op.op_kind with
    | OB_pred (Some f) ->
      { op with op_kind = OB_pred (Some(norm_form env f)) }
    | _ -> op

  let norm_ax env ax =
    { ax with ax_spec = omap ax.ax_spec (norm_form env) }

end

(* -------------------------------------------------------------------- *)
module ModTy = struct
  module Px = MC.Px

  type t = module_sig

  let by_path (p : EcPath.path) (env : env) =
    check_not_suspended
      (MC.lookup_by_path Px.for_modtype.Px.px_premc p env)

  let by_path_opt (p : EcPath.path) (env : env) =
    try_lf (fun () -> by_path p env)

  let lookup name (env : env) =
    let (p, x) = MC.lookup Px.for_modtype name env in
    (EcPath.path_of_mpath p, check_not_suspended x)

  let lookup_opt name env =
    try_lf (fun () -> lookup name env)

  let lookup_path name env =
    fst (lookup name env)

  let bind name modty env =
    let env = MC.bind_modtype name modty env in
    { env with
      env_item = CTh_modtype (name, modty) :: env.env_item }

  let add (path : EcPath.path) (env : env) =
    let obj = by_path path env in
    MC.import Px.for_modtype env (EcPath.mpath_of_path path) obj

  let mtype_string (m : module_type) =
    Printf.sprintf "%s(%s)"
      (EcPath.tostring m.mt_name)
      (String.concat ", " (List.map EcPath.m_tostring (odfl [] m.mt_args)))

  let mod_type_equiv (env : env) (mty1 : module_type) (mty2 : module_type) =
       (EcPath.p_equal mty1.mt_name mty2.mt_name)
    && oall2
         (List.all2
            (fun m1 m2 ->
               let m1 = NormMp.norm_mpath env m1 in
               let m2 = NormMp.norm_mpath env m2 in
                 EcPath.m_equal m1 m2))
         mty1.mt_args mty2.mt_args

  let has_mod_type (env : env) (dst : module_type list) (src : module_type) =
    List.exists (mod_type_equiv env src) dst
end

(* -------------------------------------------------------------------- *)
module Op = struct
  module Px = MC.Px

  type t = EcDecl.operator

  let by_path (p : EcPath.path) (env : env) =
    check_not_suspended
      (MC.lookup_by_path Px.for_operator.Px.px_premc p env)

  let by_path_opt (p : EcPath.path) (env : env) =
    try_lf (fun () -> by_path p env)

  let lookup name (env : env) =
    let (p, x) = MC.lookup Px.for_operator name env in
    (EcPath.path_of_mpath p, check_not_suspended x)

  let lookup_opt name env =
    try_lf (fun () -> lookup name env)

  let lookup_path name env =
    fst (lookup name env)

  let add (path : EcPath.path) (env : env) =
    let obj = by_path path env in
    MC.import Px.for_operator env (EcPath.mpath_of_path path) obj

  let bind name op env =
    let env = MC.bind_operator name op env in
    let op = NormMp.norm_op env op in
    let (w3, rb) =
        EcWhy3.add_op env.env_w3
          (EcPath.pqname (EcPath.path_of_mpath env.env_scope) name) op
    in
      { env with
          env_w3   = w3;
          env_rb   = rb @ env.env_rb;
          env_item = CTh_operator(name, op) :: env.env_item; }

  (* This version does not create a Why3 binding. *)
  let bind_logical name op env =
    let env = MC.bind_operator name op env in
      { env with
          env_item = CTh_operator (name, op) :: env.env_item }

  let rebind name op env =
    MC.bind_operator name op env

  let all filter (qname : qsymbol) (env : env) =
    let ops = MC.lookupall MC.Px.for_operator qname env in
    let ops =
      List.map
        (fun (p, op) ->
          (EcPath.path_of_mpath p, check_not_suspended op)) ops
    in
      List.filter (fun (_, op) -> filter op) ops

  let reducible env p =
    try
      let op = by_path p env in
      match op.op_kind with
      | OB_oper(Some _) | OB_pred(Some _) -> true
      | _ -> false
    with _ -> false

  let reduce env p tys =
    let op = try by_path p env with _ -> assert false in
    let s = 
      EcFol.Fsubst.init_subst_tvar (EcTypes.Tvar.init op.op_tparams tys) in
    let f = 
      match op.op_kind with
      | OB_oper(Some e) -> EcFol.form_of_expr EcFol.mhr e
      | OB_pred(Some idsf) -> idsf
      | _ -> raise NotReducible in
    EcFol.f_subst s f
end

(* -------------------------------------------------------------------- *)
module Ax = struct
  module Px = MC.Px

  type t = axiom

  let by_path (p : EcPath.path) (env : env) =
    check_not_suspended
      (MC.lookup_by_path Px.for_axiom.Px.px_premc p env)

  let by_path_opt (p : EcPath.path) (env : env) =
    try_lf (fun () -> by_path p env)

  let lookup name (env : env) =
    let (p, x) = MC.lookup Px.for_axiom name env in
    (EcPath.path_of_mpath p, check_not_suspended x)

  let lookup_opt name env =
    try_lf (fun () -> lookup name env)

  let lookup_path name env =
    fst (lookup name env)

  let add (path : EcPath.path) (env : env) =
    let obj = by_path path env in
    MC.import Px.for_axiom env (EcPath.mpath_of_path path) obj

  let bind name ax env =
    let env = MC.bind_axiom name ax env in
    let (w3, rb) =
      EcWhy3.add_ax env.env_w3
        (EcPath.pqname (EcPath.path_of_mpath env.env_scope) name)
        (NormMp.norm_ax env ax) in
    { env with
      env_w3   = w3;
      env_rb   = rb @ env.env_rb;
      env_item = CTh_axiom (name, ax) :: env.env_item }

  let rebind name ax env =
    MC.bind_axiom name ax env

  let by_path (p : EcPath.path) (env : env) =
    check_not_suspended
      (MC.lookup_by_path Px.for_axiom.Px.px_premc p env)

  let by_path_opt (p : EcPath.path) (env : env) =
    try_lf (fun () -> by_path p env)

  let instanciate p tys env =
    match by_path_opt p env with
    | Some ({ ax_spec = Some f } as ax) ->
        Fsubst.subst_tvar (EcTypes.Tvar.init ax.ax_tparams tys) f
    | _ -> raise (LookupFailure (`Path p))
end


(* -------------------------------------------------------------------- *)
module Theory = struct
  module Px = MC.Px

  type t = ctheory

  (* -------------------------------------------------------------------- *)
  let rec ctheory_of_theory =
      fun th ->
        let items = List.map ctheory_item_of_theory_item th in
          { cth_desc = CTh_struct items; cth_struct = items; }

  and ctheory_item_of_theory_item = function
    | Th_type      (x, ty) -> CTh_type     (x, ty)
    | Th_operator  (x, op) -> CTh_operator (x, op)
    | Th_axiom     (x, ax) -> CTh_axiom    (x, ax)
    | Th_modtype   (x, mt) -> CTh_modtype  (x, mt)
    | Th_module    m       -> CTh_module   m
    | Th_theory    (x, th) -> CTh_theory   (x, ctheory_of_theory th)
    | Th_export    name    -> CTh_export   name

  (* ------------------------------------------------------------------ *)
  let enter name env =
    enter name EcPath.PKother [] env

  (* ------------------------------------------------------------------ *)
  let by_path (p : EcPath.path) (env : env) =
    check_not_suspended
      (MC.lookup_by_path Px.for_theory.Px.px_premc p env)

  let by_path_opt (p : EcPath.path) (env : env) =
    try_lf (fun () -> by_path p env)

  let lookup name (env : env) =
    let (p, x) = MC.lookup Px.for_theory name env in
    (EcPath.path_of_mpath p, check_not_suspended x)

  let lookup_opt name env =
    try_lf (fun () -> lookup name env)

  let lookup_path name env =
    fst (lookup name env)

  (* ------------------------------------------------------------------ *)
  let bind id cth env =
    let env = MC.bind_theory id cth.cth3_theory env in
      { env with
          env_w3   = EcWhy3.rebind env.env_w3 cth.cth3_rebind;
          env_rb   = List.rev_append cth.cth3_rebind env.env_rb;
          env_item = (CTh_theory (id, cth.cth3_theory)) :: env.env_item; }

   (* ------------------------------------------------------------------ *)
  let bindx name th env =
    let rec compile1 path w3env item =
      let xpath = fun x -> EcPath.pqname path x in
        match item with
        | CTh_type     (x, ty) -> EcWhy3.add_ty w3env (xpath x) ty
        | CTh_operator (x, op) -> EcWhy3.add_op w3env (xpath x) op
        | CTh_axiom    (x, ax) -> EcWhy3.add_ax w3env (xpath x) ax
        | CTh_modtype  (_, _)  -> (w3env, [])
        | CTh_module   me      -> EcWhy3.add_mod_exp w3env (xpath me.me_name) me
        | CTh_export   _       -> (w3env, [])
        | CTh_theory (x, th)   -> compile (xpath x) w3env th

    and compile path w3env cth =
      let (w3env, rb) =
        List.map_fold (compile1 path) w3env cth.cth_struct
      in
        (w3env, List.rev (List.flatten rb))
    in

    let cpath = EcPath.path_of_mpath env.env_scope in
    let (w3env, rb) = compile (EcPath.pqname cpath name) env.env_w3 th in

    let env = MC.bind_theory name th env in
      { env with
          env_w3   = w3env;
          env_rb   = rb @ env.env_rb;
          env_item = (CTh_theory (name, th)) :: env.env_item; }

  (* ------------------------------------------------------------------ *)
  let rebind name cth env =
    MC.bind_theory name cth env

  (* ------------------------------------------------------------------ *)
  let import (path : EcPath.path) (env : env) =
    let rec import (env : env) path (cth : ctheory) =
      let xpath x = EcPath.mqname path EcPath.PKother x [] in
      let rec import_cth_item (env : env) = function
        | CTh_type (x, ty) ->
            MC.import Px.for_typedecl env (xpath x) ty

        | CTh_operator (x, op) ->
            MC.import Px.for_operator env (xpath x) op

        | CTh_axiom (x, ax) ->
            MC.import Px.for_axiom env (xpath x) ax

        | CTh_modtype (x, ty) ->
            MC.import Px.for_modtype env (xpath x) ty

        | CTh_module m ->
            MC.import Px.for_module env (EcPath.mqname path EcPath.PKmodule m.me_name []) m

        | CTh_export p ->
            let mp = EcPath.mpath_of_path p in
            import env mp (by_path p env)

        | CTh_theory (x, th) ->
            let env = MC.import Px.for_theory env (xpath x) th in
            { env with env_current =
              MC.amc_bind_mc (EcPath.path_of_mpath (xpath x)) env.env_current }
      in
      List.fold_left import_cth_item env cth.cth_struct

    in
      import env (EcPath.mpath_of_path path) (by_path path env)

  (* ------------------------------------------------------------------ *)
  let export (path : EcPath.path) (env : env) =
    let env = import path env in
      { env with
          env_item = CTh_export path :: env.env_item }

  (* ------------------------------------------------------------------ *)
  let close env =
    let theory =
      let items = List.rev env.env_item in
        { cth_desc   = CTh_struct items;
          cth_struct = items; }
    in
      { cth3_rebind = List.rev env.env_rb;
        cth3_theory = theory; }

  (* ------------------------------------------------------------------ *)
  let require x cth env =
    let rootnm  = EcCoreLib.p_top in
    let mrootnm = EcPath.mpath_of_path rootnm in
    let thpath  = EcPath.pqname rootnm x in
    let mthpath = EcPath.mpath_of_path thpath in

    let env =
      let (_, thmc), submcs =
        MC.mc_of_ctheory_r mrootnm (x, cth.cth3_theory)
      in
        MC.bind_submc env rootnm ((x, thmc), submcs)
    in

    let topmc = Mp.find rootnm env.env_comps in
    let topmc = {
      topmc with
        mc_theories   = Msym.add x (mthpath, cth.cth3_theory) topmc.mc_theories;
        mc_components = Msym.add x thpath topmc.mc_components; }
    in

    let current = {
      env.env_current with
        amc_theories =
          MMsym.add x (mthpath, cth.cth3_theory)
            env.env_current.amc_theories;
        amc_components =
          MMsym.add x thpath env.env_current.amc_components; }
    in

    let comps = env.env_comps in
    let comps = Mp.add rootnm topmc comps in

    { env with
        env_current = current;
        env_comps   = comps;
        env_w3      = EcWhy3.rebind env.env_w3 cth.cth3_rebind; }

  (* ------------------------------------------------------------------ *)
  let add (path : EcPath.path) (env : env) =
    let obj = by_path path env in
      MC.import Px.for_theory env (EcPath.mpath_of_path path) obj
end

(* -------------------------------------------------------------------- *)
let import_w3 env th rd =
  let lth, rbi = EcWhy3.import_w3 env.env_w3
      (EcPath.path_of_mpath env.env_scope) th rd in
  let cth = List.map Theory.ctheory_item_of_theory_item lth in

  let env = {
    env with
      env_w3   = EcWhy3.rebind env.env_w3 [rbi];
      env_rb   = rbi :: env.env_rb;
      env_item = List.rev_append cth env.env_item;
  }
  in

  let add env = function
    | Th_type     (id, ty) -> Ty.rebind id ty env
    | Th_operator (id, op) -> Op.rebind id op env
    | Th_axiom    (id, ax) -> Ax.rebind id ax env
    | Th_theory   (id, th) ->
        Theory.rebind id (Theory.ctheory_of_theory th) env
    | _ -> assert false
  in

  let env = List.fold_left add env lth in
    (env, cth)

(* -------------------------------------------------------------------- *)
let import_w3_dir env dir name rd =
  let th = EcProvers.get_w3_th dir name in
    import_w3 env th rd

(* -------------------------------------------------------------------- *)
let initial =
  let env0 = empty in
  let env = enter EcCoreLib.id_Pervasive EcPath.PKother [] env0 in
  let unit_rn =
    let tunit = Why3.Ty.ts_tuple 0 in
    let nunit = tunit.Why3.Ty.ts_name.Why3.Ident.id_string in
    let tt = Why3.Term.fs_tuple 0 in
    let ntt = tt.Why3.Term.ls_name.Why3.Ident.id_string in
    [ [nunit],EcWhy3.RDts, EcPath.basename EcCoreLib.p_unit;
      [ntt], EcWhy3.RDls, EcPath.basename EcCoreLib.p_tt
    ]  in
  let env, _ = import_w3 env (Why3.Theory.tuple_theory 0) unit_rn in
  let builtin_rn = [
    ["int"]    , EcWhy3.RDts, EcPath.basename EcCoreLib.p_int;
    ["real"]   , EcWhy3.RDts, EcPath.basename EcCoreLib.p_real;
    ["infix ="], EcWhy3.RDls, EcPath.basename EcCoreLib.p_eq
  ] in
  let env, _ = import_w3 env Why3.Theory.builtin_theory builtin_rn in
  let bool_rn = [
    ["bool"] , EcWhy3.RDts, EcPath.basename EcCoreLib.p_bool;
    ["True"] , EcWhy3.RDls, EcPath.basename EcCoreLib.p_true;
    ["False"], EcWhy3.RDls, EcPath.basename EcCoreLib.p_false ] in
  let env, _ = import_w3 env Why3.Theory.bool_theory bool_rn in
  let add_bool sign env path = 
    let ty = EcTypes.toarrow sign EcTypes.tbool in
    Op.bind_logical (EcPath.basename path) 
      (mk_op [] ty None) env in
  let env = add_bool [EcTypes.tbool] env EcCoreLib.p_not in
  let env = List.fold_left (add_bool [EcTypes.tbool;EcTypes.tbool]) env
      [EcCoreLib.p_and;EcCoreLib.p_anda;
       EcCoreLib.p_or;EcCoreLib.p_ora;
       EcCoreLib.p_imp; EcCoreLib.p_iff] in
 let distr_rn = [
    ["distr"], EcWhy3.RDts, EcPath.basename EcCoreLib.p_distr;
  ] in
  let env, _ = import_w3 env EcWhy3.distr_theory distr_rn in
  let cth = Theory.close env in
  let env1 = Theory.bind EcCoreLib.id_Pervasive cth env0 in
  let env1 = Theory.import EcCoreLib.p_Pervasive env1 in
  env1

(* -------------------------------------------------------------------- *)
type ebinding = [
  | `Variable  of EcTypes.pvar_kind * EcTypes.ty
  | `Function  of function_
  | `Module    of module_expr
  | `ModType   of module_sig
]

let bind1 ((x, eb) : symbol * ebinding) (env : env) =
  match eb with
  | `Variable v -> Var   .bind x (fst v) (snd v) env
  | `Function f -> Fun   .bind x f env
  | `Module   m -> Mod   .bind x m env
  | `ModType  i -> ModTy .bind x i env

let bindall (items : (symbol * ebinding) list) (env : env) =
  List.fold_left ((^~) bind1) env items

let norm_l_decl env (hyps,concl) =
  let norm = NormMp.norm_form env in
  let onh (x,lk) =
    match lk with
    | LD_var (ty,o) -> x, LD_var (ty, omap o norm)
    | LD_mem _ -> x, lk
    | LD_modty _ -> x, lk
    | LD_hyp f -> x, LD_hyp (norm f) in
  let concl = norm concl in
  let lhyps = List.map onh hyps.h_local in
  ({ hyps with h_local = lhyps}, concl)

let check_goal env pi ld =
  let ld = (norm_l_decl env ld) in
  let res = EcWhy3.check_goal env.env_w3 pi ld in
  res
