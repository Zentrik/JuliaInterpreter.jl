# Crash-safe journal: the current candidate is written (and fsync'd) to disk
# *before* it executes, so a segfault or OOM kill still leaves a reproducer.
#
# The fsync is what makes that guarantee hold across a *machine* crash, and it
# costs a disk round-trip on every candidate — a large share of per-case time
# at these program sizes. `sync=false` keeps the write (so a killed *process*
# still leaves the candidate behind, since the data reaches the page cache) but
# drops the barrier. Use the default when hunting worker crashes.

mutable struct Journal
    dir::String
    logio::IO
    sync::Bool
end

function Journal(dir::String; sync::Bool=true)
    mkpath(dir)
    logio = open(joinpath(dir, "log.txt"), "a")
    return Journal(dir, logio, sync)
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
            j.sync && ccall(:fsync, Cint, (Cint,), fd(io))
        end
    end
    println(j.logio, seed)
    j.sync && flush(j.logio)
end

# Called when a case completes without killing the process.
journal_done!(j::Journal) = nothing

Base.close(j::Journal) = close(j.logio)
