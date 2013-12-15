function should_symbol_recurse(var)
  taboo = [Module, String, Dict, Array, Tuple, DataType, Function]
  for datatype in taboo
    if isa(var, datatype)
      return false
    end
  end
  return true
end

function collect_symbols(m)
  vars = {}
  _collect_symbols(m, vars, 1)
  return vars
end

function _collect_symbols(m, vars, depth)
  # @show depth
  if isa(m, Module)
    name_list = names(m, true)
  else
    name_list = names(m)
  end
  for name in name_list
    var = m.(name)
    if var in vars
      continue
    end
    push!(vars, var)
    if should_symbol_recurse(var)
      @show var
      _collect_symbols(var, vars, depth+1)
    end
    if isa(var, Array) || isa(var, Tuple)
      for item in var
        if should_symbol_recurse(item)
          _collect_symbols(item, vars, depth+1)
        end
        push!(vars, item)
      end
    end
    if isa(var, Dict) #todo handle keys properly
      for (key, value) in var
        for item in (key, value)
          if should_symbol_recurse(item)
            _collect_symbols(item, vars, depth+1)
          end
          push!(vars, item)
        end
      end
    end
  end
  vars
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

function is_identical_type(t1::DataType, t2::DataType)
  if length(names(t1)) == length(names(t2)) && 
    all(names(t1).==names(t2)) && 
    sizeof(t1)==sizeof(t2) && 
    #t1.parameters==t2.parameters && #verify this
    all(fieldoffsets(t1).==fieldoffsets(t2))
    true
  else
    false
  end
end

function is_same_type_base(t1::DataType, t2::DataType)
  if t1.name == t2.name
    true
  else
    false
  end
end