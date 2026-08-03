# value_divergence (interp-invoke-arity-exception)

- seed: `853` (native engine, `builtins` policy; the program below is the
  hand-minimized form, written with `writefinding` from a seed-0 rerun)
- interp mode: `rec`
- julia: `1.11.9`
- divergent observation index: 1
- ref exception: `none`  interp exception: `none`

## Detail

```
obs[1]: ref=(:__thrown, :ArgumentError) interp=(:__thrown, :BoundsError)
```

## Shrunk program

```julia
let
    __obs__(try Core.invoke(abs) catch __e; (:__thrown, nameof(typeof(__e))) end)
    __obs__(try Core.invoke(abs, 1, 2) catch __e; (:__thrown, nameof(typeof(__e))) end)
end

```

## Original program

```julia
let
    __obs__(try Core.invoke(abs) catch __e; (:__thrown, nameof(typeof(__e))) end)
    __obs__(try Core.invoke(abs, 1, 2) catch __e; (:__thrown, nameof(typeof(__e))) end)
end

```
