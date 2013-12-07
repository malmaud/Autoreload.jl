module Autoreload

export arequire, areload, amodule, ainclude

const files = (String=>Float64)[]
const module_watch = Symbol[]
verbose_level = :warn
state = :on

function amodule(module_name)
  push!(module_watch, module_name)
end

function arequire(filename="", command= :on)
  if isempty(filename)
    return collect(keys(files))
  end
  if filename[end-2:end] != ".jl"
    filename = string(filename, ".jl")
  end
  if command == :on
    files[filename] = mtime(filename)
    require(filename)
  elseif command == :off
    if haskey(files, filename)
      pop!(files, filename)    
    end
  else
    error("Command $command not recognized")
  end
end

function ainclude(filename)
  arequire(string(filename))
  amodule(symbol(filename))
end

function alter_type(x, T::DataType)
  ptr = convert(Ptr{Uint64}, pointer_from_objref(x))
  ptr_array = pointer_to_array(ptr, 1)
  ptr_array[1] = pointer_from_objref(T)
  x
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

function switch_mods(vars, mod1, mod2)
  types = extract_types(mod1)
  for var in vars
    var_type = typeof(var)
    if haskey(types, var_type)
      type_name = types[var_type]
      mod2_type = mod2.(type_name)
      alter_type(var, mod2_type)
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
      warn("Type replacement error:\n $err")
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
    if mtime(file) > file_time
      try
        deep_reload(file)
      catch err
        if verbose_level == :warn
          warn("Could not autoreload $(file):\n$err")
        end
      end
      files[file] = mtime(file)
    end
  end
end

function areload_hook()
  areload(:use_state)
end

import IJulia
try
  IJulia.push_preexecute_hook(areload_hook)
catch err
  warn("Could not add IJulia hooks:\n$err")
end




end