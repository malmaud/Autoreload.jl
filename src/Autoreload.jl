module Autoreload

export arequire, areload, amodule, aimport

const files = (String=>Float64)[]
const module_watch = Symbol[]
verbose_level = :warn
state = :on

function amodule(module_name)
  push!(module_watch, module_name)
end

function reload_mtime(filename)
  path = Base.find_in_node1_path(filename)
  m = mtime(path)
  if m==0.0
    warn("Could not find edit time of $filename")
  end
  m
end

function arequire(filename="", command= :on)
  if isempty(filename)
    return collect(keys(files))
  end
  if command == :on
    files[filename] = reload_mtime(filename)
    require(filename)
  elseif command == :off
    if haskey(files, filename)
      pop!(files, filename)    
    end
  else
    error("Command $command not recognized")
  end
  return
end

function aimport(filename)
  arequire(string(filename))
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
  for var_name in names(mod)
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

function switch_mods(vars, var_names, mod1, mod2)
  types = extract_types(mod1)
  for (var, var_name) in zip(vars, var_names)
    var_type = typeof(var)
    if haskey(types, var_type)
      type_name = types[var_type]
      mod2_type = mod2.(type_name)
      if is_identical_type(var_type, mod2_type)
        unsafe_alter_type!(var, mod2_type)
      else
        var_new = alter_type(var, mod2_type, var_name)
        if var_new!=nothing
          module_rewrite(Main, var_name, var_new)
        end
      end
    end
  end
end

function deep_reload(file)
  vars = [Main.(_) for _ in names(Main)]
  local mod_olds
  try
    mod_olds = Module[Main.(mod_name) for mod_name in module_watch]
  catch err
    if verbose_level == :warn
      warn("Type replacement error:\n $(err.msg)")
    end
    reload(file)
    return
  end
  reload(file)
  mod_news = Module[Main.(mod_name) for mod_name in module_watch]
  for (mod_old, mod_new) in zip(mod_olds, mod_news)
    switch_mods(vars, names(Main), mod_old, mod_new)
  end
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

  for (file, file_time) in files
    if reload_mtime(file) > file_time
      try
        deep_reload(file)
      catch err
        if verbose_level == :warn
          warn("Could not autoreload $(file):\n$(err.msg)")
        end
      end
      files[file] = reload_mtime(file)
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
    warn("Could not add IJulia hooks:\n$(err.msg)")
  end
end

end