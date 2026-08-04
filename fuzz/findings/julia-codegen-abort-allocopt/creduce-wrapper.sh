#!/usr/bin/env bash
# C-Reduce interestingness wrapper.
#
# C-Reduce runs its test in a fresh temp dir containing only a copy of the file
# under reduction, under its original basename, and passes no arguments. So the
# wrapper has to (a) hard-code that basename and (b) reference everything else
# by absolute path.
#
# Usage:
#     apt-get install -y creduce            # 2.11.0 works
#     mkdir -p /tmp/crrun && cp minimized.jl /tmp/crrun/cr.jl
#     cd /tmp/crrun && creduce --not-c --n 4 /abs/path/to/creduce-wrapper.sh cr.jl
#
# `--not-c` selects the language-agnostic pass schedule (pass_balanced,
# pass_lines, pass_clex, pass_ints, pass_blank), which is what chews through
# nested Julia expressions. `--n` (not `-n`) sets the core count.
#
# Note the flag is `--n`; `-n` is rejected by creduce 2.11.

export PATH="$HOME/.juliaup/bin:$PATH"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$HERE/interesting.sh" cr.jl
