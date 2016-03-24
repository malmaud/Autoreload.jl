using MacroTools

function parse_deps(ex)
    m = @match ex begin
        (x_ <: y_) => (:deps, x, y)
        x_ => (:no_deps, x)
    end
    if m[1] == :deps
        deps = @match m[3] begin
            [x__] => (x)
            x_ => ([x])
        end
    else
        deps = []
    end
    (m[2], deps)
end


function auto_do(mod, action)
    modname, deps = parse_deps(mod)
    if isdefined(modname)
        quote
            $(Expr(action, modname))
        end
    else
        esc(quote
            arequire(string($(QuoteNode(modname))), depends_on=map(string, $deps))
            $(Expr(action, modname))
        end)
    end
end

macro aimport(mod)
    auto_do(mod, :import)
end

macro ausing(mod)
    auto_do(mod, :using)
end
