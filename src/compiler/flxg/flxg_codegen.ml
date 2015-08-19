open Flx_bbdcl
open Flx_btype
open Flx_exceptions
open Flx_mtypes2
open Flx_options
open Flx_print
open Flx_util
open Flx_version
open Flxg_state

module CS = Flx_code_spec


let instantiate state bsym_table root_proc =
  if state.syms.Flx_mtypes2.compiler_options.Flx_options.print_flag then
  print_endline "//INSTANTIATING\n";

  let label_map = Flx_label.create_label_map bsym_table state.syms.counter in
  let label_usage = Flx_label.create_label_usage bsym_table label_map in
  let label_info = label_map, label_usage in

  (* Make sure we can find the _init_ instance *)
  let top_class =
    try Flx_name.cpp_instance_name state.syms bsym_table root_proc []
    with Not_found ->
      failwith ("can't name instance of root _init_ procedure index " ^
        string_of_bid root_proc)
  in

  (* FUDGE the init procedure to make interfacing a bit simpler *)
  let topclass_props =
    let bsym = Flx_bsym_table.find bsym_table root_proc in
    match Flx_bsym.bbdcl bsym with
    | BBDCL_fun (props,vs,p,BTYP_void,exes) -> props
    | _ -> syserr (Flx_bsym.sr bsym) "Expected root to be procedure"
  in
  if state.syms.Flx_mtypes2.compiler_options.Flx_options.print_flag then
  print_endline  ("//root module's init procedure has name " ^  top_class);

  label_map, label_usage, label_info, top_class, topclass_props


let codegen_bsyms
  state
  bsym_table
  label_map
  label_usage
  label_info
  top_class
  topclass_props
=
  let shapes = ref Flx_set.StringSet.empty in 
  let shape_map = Hashtbl.create 97 in
  let psh s = Flxg_file.output_string state.header_file s in
  let psb s = Flxg_file.output_string state.body_file s in
  let psp s = Flxg_file.output_string state.package_file s in
  let psr s = Flxg_file.output_string state.rtti_file s in
  let psi s = Flxg_file.output_string state.felix_interface_file s in

  let plh s = psh s; psh "\n" in
  let plb s = psb s; psb "\n" in
  let plr s = psr s; psr "\n" in
  let plp s = psp s; psp "\n" in
  let pli s = psi s; psi "\n" in

  if state.syms.Flx_mtypes2.compiler_options.Flx_options.print_flag then
  print_endline "//GENERATING Package Requirements";

  let instantiate_instance f insts kind (bid, ts) =
    let bsym =
      try Flx_bsym_table.find bsym_table bid with Not_found ->
        failwith ("can't find index " ^ string_of_bid bid)
    in
    match Flx_bsym.bbdcl bsym with
    | BBDCL_external_code (_,s,kind',_) when kind' = kind ->
        begin match s with
        | CS.Identity
        | CS.Str ""
        | CS.Str_template "" -> ()
        | CS.Virtual ->
            clierr (Flx_bsym.sr bsym) "Instantiate virtual insertion!"
        | _ ->
            let s =
              match s with
              | CS.Identity | CS.Virtual ->
                  assert false (* covered above *)
              | CS.Str s ->
                  Flx_cexpr.ce_expr "atom" s
              | CS.Str_template s ->
                  (* do we need tsubst vs ts t? *)
                  let tn t = Flx_name.cpp_typename state.syms bsym_table t in
                  let ts = List.map tn ts in
                  Flx_csubst.csubst shapes
                    (Flx_bsym.sr bsym)
                    (Flx_bsym.sr bsym)
                    s
                    (fun () -> Flx_cexpr.ce_atom "Error")
                    []
                    []
                    "Error"
                    "Error"
                    ts
                    "atom"
                    "Error"
                    ["Error"]
                    ["Error"]
                    ["Error"]
                    (Flx_bsym.id bsym)
            in
            let s = Flx_cexpr.sc "expr" s in
            if not (Hashtbl.mem insts s) then begin
              Hashtbl.add insts s ();
              f s
            end
        end
      | _ -> ()
  in

  let instantiate_instances f kind =
    let tn t = Flx_name.cpp_typename state.syms bsym_table t in
    let dfnlist = ref [] in
    Hashtbl.iter
      (fun (i,ts) _ -> dfnlist := (i,ts) :: !dfnlist)
      state.syms.instances;

    let insts = Hashtbl.create 97 in

    List.iter
      (instantiate_instance f insts kind)
      (List.sort compare !dfnlist)
  in

  (* These must be in order: build a list and sort it *)
  instantiate_instances plp `Package;

  if state.syms.Flx_mtypes2.compiler_options.Flx_options.print_flag then
  print_endline "//GENERATING C++: user headers";

  plh ("#ifndef _FLX_GUARD_" ^ Flx_name.cid_of_flxid state.module_name);
  plh ("#define _FLX_GUARD_" ^ Flx_name.cid_of_flxid state.module_name);
  plh ("//Input file: " ^ state.input_filename);
  plh ("//Generated by Felix Version " ^ !version_data.version_string);
  plh ("//Timestamp: " ^ state.compile_start_gm_string);
  plh ("//Timestamp: " ^ state.compile_start_local_string);
  plh "";

  (* THE PRESENCE OF THESE LINES IS A BUG .. defeats the FLX_NO_INCLUDES switch
   * but we need this temporarily, at least until we fix flx.flx compilation
   * in the build system to generate dependencies in the flx.includes file
   *
   * Also we need to fix the compiler and all libraries to use explicit
   * qualification everywhere which will make the code a bit of a mess..
   *)
  plh "//FELIX RUNTIME";
  plh "#include \"flx_rtl.hpp\"";
  (* plh "using namespace ::flx::rtl;";  *)
  plh "#include \"flx_gc.hpp\"";
  (* plh "using namespace ::flx::gc::generic;"; *)

  plh "#ifndef FLX_NO_INCLUDES";
  plh ("#include \"" ^ state.module_name ^ ".includes\"");
  plh "#endif";
  plh "";

  plh "\n//-----------------------------------------";
  plh "//USER HEADERS";

  (* These must be in order: build a list and sort it *)
  instantiate_instances plh `Header;

  plh "\n//-----------------------------------------";
  List.iter plh [
    "//FELIX SYSTEM";
    "namespace flxusr { namespace " ^
    Flx_name.cid_of_flxid state.module_name ^ " {";
    "struct thread_frame_t;"
  ];

  if state.syms.Flx_mtypes2.compiler_options.Flx_options.print_flag then
  print_endline "//GENERATING C++: collect types";
  let types = ref [] in
  Hashtbl.iter (fun t index -> types := (index, t) :: !types) state.syms.registry;

  let types = List.sort (fun a1 a2 -> compare (fst a1) (fst a2)) !types in
  (*
  List.iter
  (fun (_,t) -> print_endline (string_of_btypecode sym_table t))
  types
  ;
  *)

  if state.syms.Flx_mtypes2.compiler_options.Flx_options.print_flag then
  print_endline "//GENERATING C++: type class names";
  plh "\n//-----------------------------------------";
  plh "//NAME THE TYPES";
  plh  (Flx_tgen.gen_type_names state.syms bsym_table types);
  if state.syms.Flx_mtypes2.compiler_options.Flx_options.print_flag then
  print_endline "//DONE: NAME THE TYPES";

  if state.syms.Flx_mtypes2.compiler_options.Flx_options.print_flag then
  print_endline "//GENERATING C++: type class definitions";
  plh "\n//-----------------------------------------";
  plh  "//DEFINE THE TYPES";
  plh  (Flx_tgen.gen_types state.syms bsym_table types);
  if state.syms.Flx_mtypes2.compiler_options.Flx_options.print_flag then
  print_endline "//DONE C++: type class definitions";

  if state.syms.Flx_mtypes2.compiler_options.Flx_options.print_flag then
  print_endline "//GENERATING C++: function and procedure classes";
  plh "\n//-----------------------------------------";
  plh  "//DEFINE FUNCTION CLASS NAMES";
  plh  (Flx_gen.gen_function_names state.syms bsym_table);
  if state.syms.Flx_mtypes2.compiler_options.Flx_options.print_flag then
  print_endline "//DONE GENERATING C++: function and procedure class names";

  plh "\n//-----------------------------------------";
  plh  "//DEFINE FUNCTION CLASSES";
  plh  (Flx_gen.gen_functions state.syms bsym_table shapes shape_map);
  if state.syms.Flx_mtypes2.compiler_options.Flx_options.print_flag then
  print_endline "//DONE DEFINE FUNCTION CLASSES";

  let topvars_with_type = Flx_findvars.find_thread_vars_with_type bsym_table in
  let topvars = List.map fst topvars_with_type in
  List.iter plh
  [
  "struct thread_frame_t {";
  "  int argc;";
  "  char **argv;";
  "  FILE *flx_stdin;";
  "  FILE *flx_stdout;";
  "  FILE *flx_stderr;";
  "  ::flx::gc::generic::gc_profile_t *gcp;";
  "  ::flx::gc::generic::gc_shape_t * const shape_list_head;";
  "  thread_frame_t(";
  "  );";
  ]
  ;
  plh (Flx_gen_helper.format_vars state.syms bsym_table topvars []);
  plh "};";
  plh "";
  plh "FLX_DCL_THREAD_FRAME";
  plh "";
  plh ("}} // namespace flxusr::" ^ Flx_name.cid_of_flxid state.module_name);

  (* BODY *)
  if state.syms.Flx_mtypes2.compiler_options.Flx_options.print_flag then
  print_endline "//GENERATING C++: GC ptr maps & offsets";

  plb ("//Input file: " ^ state.input_filename);
  plb ("//Generated by Felix Version " ^ !version_data.version_string);
  plb ("//Timestamp: " ^ state.compile_start_gm_string);
  plb ("//Timestamp: " ^ state.compile_start_local_string);

  plb ("#define FLX_EXTERN_" ^ Flx_name.cid_of_flxid state.module_name ^ " FLX_EXPORT");
  plb ("#include \"" ^ state.module_name ^ ".hpp\"");
  plb "#include <stdio.h>"; (* for diagnostics *)

  plb "#define comma ,";
  plb "\n//-----------------------------------------";
  plb "//EMIT USER BODY CODE";
  plb (
    "using namespace ::flxusr::" ^
    Flx_name.cid_of_flxid state.module_name ^ ";");


  (* These must be in order: build a list and sort it *)
  instantiate_instances plb `Body;

  (*
  print_endline "BEFORE RTTI GENERATION";
  Flx_set.StringSet.iter 
    (fun s-> print_endline ("SHAPE REQUIRED " ^ s))
  (!shapes);
  *)



  plb "\n//-----------------------------------------";
  plb (
    "namespace flxusr { namespace " ^
    Flx_name.cid_of_flxid state.module_name ^ " {");

  (* include RTTI file. Must be before the thread frame constructor because
   * the head of the rtti shape list may be thread_frame_t_ptr_map
   * which is stored in the thread frame so the library function can get
   * the shape object list *)

  (* if Flxg_file.was_used state.rtti_file then begin *)
    plb "\n//-----------------------------------------";
    plb "//DEFINE OFFSET tables for GC";
    plb ("#include \"" ^ state.module_name ^ ".rtti\"");
  (* end; *)


  plb "FLX_DEF_THREAD_FRAME";
  plb "//Thread Frame Constructor";

  let sr = Flx_srcref.make_dummy "Thread Frame" in
  let topfuns = List.filter
    (fun (_,t) -> Flx_gen_helper.is_gc_pointer state.syms bsym_table sr t)
    topvars_with_type
  in
  let topfuns = List.map fst topfuns in
  let topinits =
    [
      "  gcp(0)";
      "  shape_list_head("^Flx_name.cid_of_flxid state.module_name ^"_head_shape)";
    ]
    @
    List.map
    (fun index ->
      "  " ^
      Flx_name.cpp_instance_name state.syms bsym_table index [] ^
      "(0)"
    )
    topfuns
  in
  let topinits = String.concat ",\n" topinits in
  List.iter plb
  [
  "thread_frame_t::thread_frame_t(";
  ") :";
  topinits;
  "{}"
  ];

  begin
    let header_emitted = ref false in
    Hashtbl.iter
    (fun (fno,_) inst ->
      try
        let labels = Hashtbl.find label_map fno in
        Hashtbl.iter
        (fun lab lno ->
          match Flx_label.get_label_kind_from_index label_usage lno with
          | `Far ->
            if not !header_emitted then begin
              plb "\n//-----------------------------------------";
              plb "#if FLX_CGOTO";
              plb "//DEFINE LABELS for GNUC ASSEMBLER LABEL HACK";
              header_emitted := true;
            end
            ;
            plb ("FLX_DECLARE_LABEL(" ^ string_of_bid lno ^ "," ^
              string_of_bid inst ^ "," ^ lab ^ ")")
          | `Near -> ()
          | `Unused -> ()
        )
        labels
      with Not_found -> ()
    )
    state.syms.instances
    ;
    if !header_emitted then plb "#endif";
  end
  ;

  if state.syms.Flx_mtypes2.compiler_options.Flx_options.print_flag then
  print_endline "//GENERATING C++: method bodies";

  plb "\n//-----------------------------------------";
  plb "//DEFINE FUNCTION CLASS METHODS";
  plb ("#include \"" ^ state.module_name ^ ".ctors_cpp\"");
  Flx_gen.gen_execute_methods
    (Flxg_file.filename state.body_file)
    state.syms
    bsym_table
    shapes shape_map
    label_info
    state.syms.counter
    (Flxg_file.open_out state.body_file)
    (Flxg_file.open_out state.ctors_file);


  if state.syms.Flx_mtypes2.compiler_options.Flx_options.print_flag then
  print_endline "//GENERATING C++: interface";
  plb "\n//-----------------------------------------";
  plb ("}} // namespace flxusr::" ^ Flx_name.cid_of_flxid state.module_name);

  let mname = Flx_name.cid_of_flxid state.module_name in

  plb "//CREATE STANDARD EXTERNAL INTERFACE";
  plb (
    "FLX_FRAME_WRAPPERS(::flxusr::" ^ mname ^","^mname ^ ")");

  begin if List.mem `Pure topclass_props then
    if List.mem `Requires_ptf topclass_props then
    plb (
      "FLX_C_START_WRAPPER_PTF(::flxusr::" ^ 
      mname ^ ","^mname^"," ^ top_class ^ ")")
    else
    plb (
      "FLX_C_START_WRAPPER_NOPTF(::flxusr::" ^ 
      mname ^ ","^mname^"," ^ top_class ^ ")")
  else if List.mem `Stackable topclass_props then
    plb (
      "FLX_STACK_START_WRAPPER(::flxusr::" ^
      mname ^ ","^mname^"," ^ top_class ^ ")")
  else
    plb (
      "FLX_START_WRAPPER(::flxusr::" ^
      mname ^ ","^mname^"," ^ top_class ^ ")")
  end;

  plb "\n//-----------------------------------------";

  if List.length state.syms.bifaces > 0 then begin
    plh "//DECLARE USER EXPORTS";
    plh (Flx_gen_biface.gen_biface_headers
      state.syms
      bsym_table
      state.syms.bifaces state.module_name);

    plb "//DEFINE EXPORTS";
    plb (Flx_gen_biface.gen_biface_bodies
      state.syms
      bsym_table
      shapes shape_map
      label_map
      state.syms.bifaces);

    plb (Flx_gen_python.gen_python_module
      state.module_name
      state.syms
      bsym_table
      state.syms.bifaces);

    pli (Flx_gen_biface.gen_biface_felix
      state.syms
      bsym_table
      state.syms.bifaces 
      state.module_name);

  end;

  let gen_uint_array name values =
    "static unsigned int const " ^ name ^ "[" ^ string_of_int (List.length values) ^ "] = {" ^ (
        catmap "," (fun x -> (string_of_int x) ^ "u") values
    ) ^ "};" in

  (* rather late: generate variant remapping tables *)
  if Hashtbl.length state.syms.variant_map > 0 then begin
    plr "// VARIANT REMAP ARRAYS";
    Hashtbl.iter
    (fun (srct,dstt) vidx ->
      match srct,dstt with
      | BTYP_variant srcls, BTYP_variant dstls ->
        begin
          let rcmp (s,_) (s',_) = compare s s' in
          let srcls = List.sort rcmp srcls in
          let dstls = List.sort rcmp dstls in
          let n = List.length srcls in
          let remap =
            List.map
            (fun (s,_) ->
              match Flx_list.list_assoc_index dstls s with
              | Some i -> i
              | None -> assert false
            )
            srcls
          in
          plr (
            "static int vmap_" ^ string_of_bid vidx ^ "[" ^ string_of_int n ^
            "]={" ^ catmap "," (fun i -> si i) remap ^ "};")
        end
      | _ -> failwith "Remap non variant types??"
    )
    state.syms.variant_map
  end
  ;
  plh "//header complete";
  plh "#endif";
  plb "//body complete";
  Flxg_file.close_out state.header_file;
  Flxg_file.close_out state.body_file;
  Flxg_file.close_out state.ctors_file;
  Flxg_file.close_out state.felix_interface_file;

  if Hashtbl.length state.syms.array_sum_offset_table > 0 then
  begin
    plr "\n// Array indexing helpers for sum indexes\n";
    Hashtbl.iter (fun _ (name,values) ->
      plr  (gen_uint_array name values)
    )
    state.syms.array_sum_offset_table;
  end;

  if Hashtbl.length state.syms.power_table > 0 then
  begin
    plr "\n// integer powers of constants \n";
    Hashtbl.iter (fun size values ->
      plr  (gen_uint_array ("flx_ipow_"^si size) values)
    )
    state.syms.power_table;
  end;

  (*
  print_endline "END OF CODE GENERATION";
  Flx_set.StringSet.iter 
    (fun s-> print_endline ("SHAPE REQUIRED " ^ s))
  (!shapes);
  Hashtbl.iter
   (fun s t ->  print_endline ("SHAPE GENERATED " ^ s))
  shape_map;
  print_endline "START OF RTTI GENERATION";
  *)

  let extras = ref [] in 
  Flx_set.StringSet.iter 
    (fun s-> 
       (*
       print_endline ("Extra Shape " ^ s);
       *)
       try 
         let t = Hashtbl.find shape_map s in
         extras := t :: !extras;
       with Not_found -> assert false
    )
  (!shapes);
  let extras = !extras in

  let _, tables = Flx_ogen.gen_offset_tables
    state.syms
    bsym_table
    extras
    state.module_name
    "&::flx::rtl::_address_ptr_map"
  in
   plr tables
  ;

  Flxg_file.close_out state.rtti_file;
  plp "flx";
  plp "flx_gc";  (* RF: flx apps now need flx_gc. is this the way to do it? *)
  Flxg_file.close_out state.package_file


let codegen state bsym_table root_proc =
  let label_map, label_usage, label_info, top_class, topclass_props =
    Flx_profile.call
      "Flxg_codegen.instantiate"
      (instantiate state bsym_table)
      root_proc
  in

  (* Exit early if we're done. *)
  if state.syms.compiler_options.compile_only then () else

  (* Finally, lets do some code generation! *)
  Flx_profile.call
    "Flxg_codegen.codegen_bsyms"
    (codegen_bsyms state bsym_table label_map label_usage label_info top_class)
    topclass_props

