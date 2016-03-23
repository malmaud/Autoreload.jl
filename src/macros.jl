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

macro aimport(mod)
    modname, deps = parse_deps(mod)
    if isdefined(modname)
        quote
            import $modname
        end
    else
        esc(quote
            arequire(string($(QuoteNode(modname))), depends_on=map(string, $deps))
            import $modname
        end)
    end
end

macro aimport(mod)
    modname, deps = parse_deps(mod)
    if isdefined(modname)
        quote
            using $modname
        end
    else
        esc(quote
            arequire(string($(QuoteNode(modname))), depends_on=map(string, $deps))
            using $modname
        end)
    end
end
