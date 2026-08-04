# interp_only_throw (corpusvalue-interp_only_throw-938d349c)

- seed: `1785779695500600226`
- walk seed: `2813607554556078055`
- interp mode: `corpusvalue`
- julia: `1.12.6`
- divergent observation index: 0
- ref exception: `none`  interp exception: `ArgumentError`

## Detail

```
interp threw ArgumentError: ArgumentError: invalid type for argument x in method definition for + at none:77
```

## Shrunk program

```julia
import Base: IndexLinear
#= none:14 =# Core.@doc "    DateTime(dt::Date) -> DateTime\n\nConvert a `Date` to a `DateTime`. The hour, minute, second, and millisecond parts of\nthe new `DateTime` are assumed to be zero.\n" DateTime(dt::TimeType) = begin
            #= none:20 =#
            convert(DateTime, dt)
        end
x::DateTime + y::Quarter = begin
        #= none:77 =#
        x + Month(y)
    end
struct TSlow{T, N} <: AbstractArray{T, N}
    #= none:35 =#
    data::Dict{NTuple{N, Int}, T}
    #= none:36 =#
    dims::NTuple{N, Int}
end
```

## Original program

```julia
import Base: IndexLinear
#= none:14 =# Core.@doc "    DateTime(dt::Date) -> DateTime\n\nConvert a `Date` to a `DateTime`. The hour, minute, second, and millisecond parts of\nthe new `DateTime` are assumed to be zero.\n" DateTime(dt::TimeType) = begin
            #= none:20 =#
            convert(DateTime, dt)
        end
x::DateTime + y::Quarter = begin
        #= none:77 =#
        x + Month(y)
    end
struct TSlow{T, N} <: AbstractArray{T, N}
    #= none:35 =#
    data::Dict{NTuple{N, Int}, T}
    #= none:36 =#
    dims::NTuple{N, Int}
end
```
