# Minimal reproducer for the compiled-mode `rethrow`/`current_exceptions`
# divergence. Run with: julia --project=<repo>/fuzz this-file.jl
#
# Prints one row per (construct, engine). `cmp` is JuliaInterpreter's compiled
# mode (NonRecursiveInterpreter); `rec` is the recursive interpreter; the
# reference is plain `Core.eval`.

using JuliaInterpreter

function check(name, src)
    for (label, interp) in (("rec", JuliaInterpreter.RecursiveInterpreter()),
                            ("cmp", JuliaInterpreter.NonRecursiveInterpreter()))
        m = Module(:T); Core.eval(m, :(using Base))
        out = try
            r = nothing
            for (mod, frag) in JuliaInterpreter.ExprSplitter(m, Base.Meta.parseall(src))
                fr = Base.invokelatest(JuliaInterpreter.Frame, mod, frag)
                fr === nothing && continue
                r = JuliaInterpreter.finish_and_return!(interp, fr, true)
            end
            "value $r"
        catch err
            "throw $(typeof(err)): $(first(sprint(showerror, err), 90))"
        end
        println(rpad("$name/$label", 28), out)
    end
    r = try
        "value $(Core.eval(Module(:R), Base.Meta.parseall(src)))"
    catch err
        "throw $(typeof(err)): $(first(sprint(showerror, err), 90))"
    end
    println(rpad("$name/reference", 28), r)
end

check("rethrow()",          "let; try; error(\"boom\"); catch e; rethrow(); end; end")
check("rethrow(exc)",       "let; try; error(\"boom\"); catch e; rethrow(ArgumentError(\"other\")); end; end")
check("current_exceptions", "let; try; error(\"boom\"); catch e; length(current_exceptions()); end; end")
check("catch_backtrace",    "let; try; error(\"boom\"); catch e; length(catch_backtrace()) > 0; end; end")
