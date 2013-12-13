module Autoreload

export arequire, areload, amodule, aimport, aoptions_set, aoptions_get

include("constants.jl")
include("strip_constants.jl")
include("smart_types.jl")
include("files.jl")
include("dependencies.jl")

function aoptions_set(;kwargs...)
  global options
  for (key, value) in kwargs
    option_used = false
    for (i, (opt_key, opt_value)) in enumerate(options)
      if key==opt_key
        options[key] = value
        option_used = true
      end
    end
    if !option_used
      error("Option $key not recognized")
    end
  end
  options
end

aoptions_get() = copy(options)

function amodule(module_name)
  if !(module_name in module_watch)
    push!(module_watch, module_name)
  end
end

function remove_file(filename)
  pop!(files, filename)
end

function parse_file(filename)
  path = find_file(filename)
  source = string("begin\n", readall(open(path)), "\n end")
  parsed = parse(source)
  return parsed
end

function arequire(filename=""; command= :on, depends_on=String[])
  if isempty(filename)
    return collect(keys(files))
  end
  filename = standarize(filename)
  if command in [:on, :on_depends]
    if filename in files
      remove_file(filename)
    end
    if command==:on
      should_reload = true
    else
      should_reload = false
    end
    files[filename] = AFile(should_reload, reload_mtime(filename), String[])
    parsed_file = parse_file(filename)
    auto_depends = extract_deps(parsed_file)
    auto_depends = [_.name for _ in auto_depends] #todo respect reload flag
    depends_on = vcat(auto_depends, depends_on) 
    for d in depends_on
      d = standarize(d)
      if !haskey(files, d)
        d = find_file(d, base_file = filename)
        if d==nothing
          error("Dependent file not found")
        end
        arequire(d, command = :on_depends)
      end
      push!(files[filename].deps, d)
    end
    if files[filename].should_reload
      require(find_file(filename))
    end
  elseif command == :off
    if haskey(files, filename)
      remove_file(filename)
    end
  else
    error("Command $command not recognized")
  end
  return
end

function aimport(filename; kwargs...)
  arequire(string(filename); kwargs...)
  amodule(symbol(filename))
  return
end

function module_rewrite(m::Module, name::Symbol, value)
  eval(m, :($name=$value))
end

function switch_mods(vars,  mod1, mod2)
  types = extract_types(mod1)
  for var in vars
    var_type = typeof(var)
    if !isa(var_type,  DataType)
      continue
    end
    for (old_type, type_name) in types
      if is_same_type_base(var_type, old_type)
        mod2_raw_type = mod2.(type_name)
        mod2_type = mod2_raw_type{var_type.parameters...}
        if is_identical_type(var_type, mod2_type)
          unsafe_alter_type!(var, mod2_type)
        else
          warn("Couldn't alter $var")
        end
      end
    end
  end
end

function deep_reload(file; kwargs...)
  file = find_in_path(file; kwargs...)
  vars = collect_symbols(Main)
  main_types = extract_types(Main)

  local mod_olds
  try
    mod_olds = Module[Main.(mod_name) for mod_name in module_watch]
  catch err
    if options[:verbose_level] == :warn
      warn("Type replacement error:\n $(err)")
    end
    reload(file)
    return
  end
  file_path = find_file(file, constants=options[:constants])
  file_parse = parse_file(file_path)
  taboo = collect(values(main_types))
  expr_list = remove_constants(file_parse, taboo)
  for e in expr_list
    eval(Main, e)
  end
  #reload(file)
  mod_news = Module[Main.(mod_name) for mod_name in module_watch]
  if options[:smart_types]
    for (mod_old, mod_new) in zip(mod_olds, mod_news)
      switch_mods(vars, mod_old, mod_new)
    end
  end
end

function try_reload(file; kwargs...)
  deep_reload(file; kwargs...)
  # try
  #   deep_reload(file)
  # catch err
  #   if verbose_level == :warn
  #     warn("Could not autoreload $(file):\n$(err)")
  #   end
  # end
end

function is_equal_dict(d1::Dict, d2::Dict)
  for key in keys(d1)
    if d1[key]!=d2[key]
      return false
    end
  end
  return true
end

function areload(command= :force; kwargs...)
  if command == :use_state
    if options[:state] == :off
      return
    end
  elseif command == :off
    options[:state] = :off
    return
  elseif command == :on
    options[:state] = :on
  end
  dependencies = get_dependency_graph()
  file_order = topological_sort(dependencies)
  should_reload = [filename=>false for filename in file_order]
  for (i, file) in enumerate(file_order)
    file_time = files[file].mtime
    if reload_mtime(file) > file_time
      should_reload[file] = true
      files[file].mtime = reload_mtime(file)
    end
  end
  old_reload = copy(should_reload)
  while true
    for (child, parents) in dependencies
      for parent in parents
        if should_reload[parent]
          should_reload[child] = true
        end
      end
    end
    if is_equal_dict(old_reload, should_reload)
      break
    end
    old_reload = copy(should_reload)
  end

  for file in file_order
    if should_reload[file] && files[file].should_reload
      try_reload(file; constants=options[:constants], kwargs...)
    end
  end
  return
end

function areload_hook()
  areload(:use_state)
end

if isdefined(Main, :IJulia)
  IJulia = Main.IJulia
  try
    IJulia.push_preexecute_hook(areload_hook)
  catch err
    warn("Could not add IJulia hooks:\n$(err)")
  end
end

end

