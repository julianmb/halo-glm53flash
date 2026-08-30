#!/usr/bin/env bash
# bounded glm-5.3-flash smoke on amd strix halo (gfx1151)
# mirrors results/smoke-glm-ud-iq1s.log (2026-08-28: decode 9.31 tok/s, coherent)
#
# env overrides:
#   MODEL      path to the shard-00001 gguf (default: models/UD-IQ1_S/...)
#   ENGINE     dir containing llama-completion
#   N_PREDICT  tokens to generate (default 32)
set -euo pipefail

MODEL="${MODEL:-models/UD-IQ1_S/GLM-5.3-Flash-UD-IQ1_S-00001-of-00003.gguf}"
ENGINE="${ENGINE:-$HOME/source/ROCmFPX-glm5next/build-strix-glm5next/bin}"
N_PREDICT="${N_PREDICT:-32}"

exec timeout 900 /usr/bin/time -v "$ENGINE/llama-completion" \
  -m "$MODEL" \
  -dev Vulkan0 -ngl 99 \
  -c 8192 -fa off -ub 512 \
  -p "The capital of France is" -n "$N_PREDICT" \
  --temp 1.0 --top-p 0.95 -no-cnv --simple-io
