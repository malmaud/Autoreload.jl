function remove_constants(e_block::Expr, taboo::Vector)
  e_eval = {}
  for e in e_block.args
    if isa(e, Expr) && e.head==:type
      if e.args[2] in taboo
        warn("Removing redefinition of $(e.args[2])")
        continue
      end
    end
    push!(e_eval, e)
  end
  new_e = Expr(e_block.head, e_eval, e_block.typ)
  return e_eval
end

