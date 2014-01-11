type AFile
    should_reload::Bool
    mtime::Float64
    deps::Vector{String}
end

type Dep
    should_reload::Bool
    name::String
end
suppress_warnings = false
const files = (String=>AFile)[]
const options = (Symbol=>Any)[:constants=>false, :strip_types=>true, :smart_types=>true, :verbose_level=>:warn, :state=>:on]
# verbose_level = :warn
# state = :on