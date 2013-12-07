module Autoreload

export arequire, areload

const files = (String=>Float64)[]
verbose_level = :warn
state = :on


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

function deep_reload(file)
  reload(file)
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

try:
  import IJulia
  IJulia.push_preexecute_hook(areload_hook)
catch err:
  warn("Could not add IJulia hooks:\n$err")
end




end