module Autoreload

export arequire, areload, amodule, aimport

type AFile
  should_reload::Bool
  mtime::Float64
end

const files = (String=>AFile)[]
const module_watch = Symbol[]
const dependencies = (String=>Vector{String})[]


verbose_level = :warn
state = :on


function amodule(module_name)
  if !(module_name in module_watch)
    push!(module_watch, module_name)
  end
end

function standarize(filename)
  if endswith(filename, ".jl")
    filename
  else
    string(filename, ".jl")
  end
end

function find_file(filename; base_file=nothing)

  path =  Base.find_in_node1_path(filename)
  if path == nothing
    base_file = Base.find_in_node1_path(base_file)
    path = joinpath(dirname(base_file), filename)
    if !isfile(path)
      path = nothing
    end
  end
  return path
  # path = Base.find_in_node1_path(filename)
  # if path == nothing
  #   for file in keys(files)
  #     @show file
  #     base = Base.find_in_node1_path(file)
  #     if base == nothing
  #       continue
  #     end
  #     candidate = joinpath(dirname(base), filename)
  #     if isfile(candidate) || isfile(string(candidate, ".jl"))
  #       return candidate
  #     end
  #   end
  # end
  # return path
end

function reload_mtime(filename)
  path = find_file(filename)
  m = mtime(path)
  if m==0.0
    warn("Could not find edit time of $filename")
  end
  m
end

function should_symbol_recurse(var)
  taboo = [Module, String, Dict, Array, Tuple]
  for datatype in taboo
    if isa(var, datatype)
      return false
    end
  end
  return true
end

function collect_symbols(m)
  vars = {}
  _collect_symbols(m, vars)
  return vars
end

function _collect_symbols(m, vars)
  if isa(m, Module)
    name_list = names(m, true)
  else
    name_list = names(m)
  end
  for name in name_list
    var = m.(name)
    if should_symbol_recurse(var)
      _collect_symbols(var, vars)
    end
    if isa(var, Array) || isa(var, Tuple)
      for item in var
        if should_symbol_recurse(item)
          _collect_symbols(item, vars)
        end
        push!(vars, item)
      end
    end
    if isa(var, Dict) #todo handle keys properly
      for (key, value) in var
        for item in (key, value)
          if should_symbol_recurse(item)
            _collect_symbols(item, vars)
          end
          push!(vars, item)
        end
      end
    end
    push!(vars, var)
  end
  vars
end

function remove_file(filename)
  pop!(files, filename)
  pop!(dependencies, filename)
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
    files[filename] = AFile(should_reload, reload_mtime(filename))
    dependencies[filename] = String[]
    for d in depends_on
      d = standarize(d)
      if !haskey(files, d)
        d = find_file(d, base_file = filename)
        if d==nothing
          error("Dependent file not found")
        end
        arequire(d, command = :on_depends)
      end
      push!(dependencies[filename], d)
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

function unsafe_alter_type!(x, T::DataType)
  ptr = convert(Ptr{Uint64}, pointer_from_objref(x))
  ptr_array = pointer_to_array(ptr, 1)
  ptr_array[1] = pointer_from_objref(T)
  x
end

function alter_type(x, T::DataType, var_name="")
  fields = names(T)
  old_fields = names(typeof(x))
  local x_new
  try
    x_new = T()
    for field in fields
      if field in old_fields
        x_new.(field) = x.(field)
      end
    end
  catch
    args = Any[]
    for field in fields
      if field in old_fields
        arg = x.(field)
        push!(args, arg)
      else
        warn("Type alteration of $(var_name) could not be performed automatically")
        return nothing
      end
    end
    x_new =  T(args...)
  end
  return x_new
end

function extract_types(mod::Module)
  types = (DataType=>Symbol)[]
  for var_name in names(mod, true)
    var = mod.(var_name)
    if typeof(var)==DataType
      types[var] = var_name
    end
  end
  types
end

function module_rewrite(m::Module, name::Symbol, value)
  eval(m, :($name=$value))
end

function is_identical_type(t1::DataType, t2::DataType)
  if length(names(t1)) == length(names(t2)) && 
    all(names(t1).==names(t2)) && 
    sizeof(t1)==sizeof(t2) && 
    all(fieldoffsets(t1).==fieldoffsets(t2))
    true
  else
    false
  end
end

function switch_mods(vars,  mod1, mod2)
  types = extract_types(mod1)
  for var in vars
    var_type = typeof(var)
    if haskey(types, var_type)
      type_name = types[var_type]
      mod2_type = mod2.(type_name)
      if is_identical_type(var_type, mod2_type)
        unsafe_alter_type!(var, mod2_type)
      else
        # var_new = alter_type(var, mod2_type, var_name)
        # if var_new!=nothing
        #   module_rewrite(Main, var_name, var_new)
        # end
        warn("Couldn't alter $var")
      end
    end
  end
end


function topological_sort{T}(outgoing::Dict{T, Vector{T}})
  # kahn topological sort
  # todo: use better data structures
  order = T[]
  incoming = (T=>Vector{T})[]
  for (n, children) in outgoing
    for child in children
      if haskey(incoming, child)
        push!(incoming[child], n)
      else
        incoming[child] = [n]
      end
    end
    if !haskey(incoming, n)
      incoming[n] = T[]
    end
  end
  S = T[]
  outgoing_counts = (T=>Int)[]
  for (child, parents) in outgoing
    if isempty(parents)
      push!(S, child)
    end
    outgoing_counts[child] = length(parents)
  end
  while !isempty(S)
    n = pop!(S)
    push!(order, n)
    children = incoming[n]
    for child in children
      outgoing_counts[child] -= 1
      if outgoing_counts[child] == 0
        push!(S, child)
      end
    end
  end
  if length(order) != length(outgoing)
    error("Cyclic dependencies detected")
  end
  return order
end

function deep_reload(file)
  vars = collect_symbols(Main)
  local mod_olds
  try
    mod_olds = Module[Main.(mod_name) for mod_name in module_watch]
  catch err
    if verbose_level == :warn
      warn("Type replacement error:\n $(err)")
    end
    reload(file)
    return
  end
  reload(file)
  mod_news = Module[Main.(mod_name) for mod_name in module_watch]
  for (mod_old, mod_new) in zip(mod_olds, mod_news)
    switch_mods(vars, mod_old, mod_new)
  end
end

function try_reload(file)
  try
    deep_reload(file)
  catch err
    if verbose_level == :warn
      warn("Could not autoreload $(file):\n$(err)")
    end
  end
end

function is_equal_dict(d1::Dict, d2::Dict)
  for key in keys(d1)
    if d1[key]!=d2[key]
      return false
    end
  end
  return true
end

function areload(command= :force)
  global state
  if command == :use_state
    if state == :off
      return
    end
  elseif command == :off
    state = :off
    return
  elseif command == :on
    state = :on
  end
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
      try_reload(file)
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