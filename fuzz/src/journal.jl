# Crash-safe journal: the current candidate is written (and fsync'd) to disk
# *before* it executes, so a segfault or OOM kill still leaves a reproducer.

mutable struct Journal
    dir::String
    logio::IO
end

function Journal(dir::String)
    mkpath(dir)
    logio = open(joinpath(dir, "log.txt"), "a")
    return Journal(dir, logio)
end

currentpath(j::Journal) = joinpath(j.dir, "current.jl")

function journal_case!(j::Journal, seed::Int, src::String)
    open(currentpath(j), "w") do io
        println(io, "# FuzzJI candidate — seed $seed")
        print(io, src)
        flush(io)
        # Base doesn't expose fsync for IOStreams; a raw fsync(2) is what
        # crash-safety needs (POSIX only, which is fine for a fuzzing rig).
        @static if !Sys.iswindows()
            ccall(:fsync, Cint, (Cint,), fd(io))
        end
    end
    println(j.logio, seed)
    flush(j.logio)
end

# Called when a case completes without killing the process.
journal_done!(j::Journal) = nothing

Base.close(j::Journal) = close(j.logio)
