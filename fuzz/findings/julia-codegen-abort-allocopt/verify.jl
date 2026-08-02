m = Module(:CrashCase)
for st in Meta.parseall(read(ARGS[1], String)).args
    st isa LineNumberNode && continue
    try; Core.eval(m, st); catch e; end
end
println("survived")
