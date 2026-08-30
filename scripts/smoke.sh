#!/usr/bin/env bash
# glm-5.3-flash quant picker + downloader + smoke for amd strix halo (gfx1151, 128gb uma)
#
# usage:
#   ./smoke.sh                       # list quants and what fits 128gb
#   ./smoke.sh UD-IQ1_S              # download (if missing) + run the measured smoke
#   ./smoke.sh UD-IQ3_XXS --force    # allow borderline / non-fitting quants
#
# env overrides: MODEL_DIR ENGINE CTX N_PREDICT DEV NGL PROMPT
# receipts for the default run: ../results/smoke-glm-ud-iq1s.log
set -euo pipefail

REPO="unsloth/GLM-5.3-Flash-GGUF"
MODEL_DIR="${MODEL_DIR:-models}"
CTX="${CTX:-8192}"
N_PREDICT="${N_PREDICT:-32}"
DEV="${DEV:-Vulkan0}"
NGL="${NGL:-99}"
PROMPT="${PROMPT:-The capital of France is}"

# name | size_gb | shards | fit on 128gb uma (yes | borderline | no)
# fit assumes -c 8192 (small kv) + os overhead on a 128gb halo (124gi usable);
# raise ctx and the bigger quants stop fitting — use --cpu-moe / --kv-offload then
QUANTS=(
  "UD-IQ1_S|93.1|3|yes"
  "UD-IQ1_M|97.6|3|yes"
  "UD-IQ2_XXS|101.8|4|yes"
  "UD-Q2_K_XL|108.7|4|yes"
  "UD-IQ3_XXS|120.4|4|borderline"
  "UD-IQ4_XS|156.8|5|no"
  "UD-Q4_K_XL|199.7|6|no"
  "UD-Q5_K_XL|240.3|6|no"
  "UD-Q6_K_XL|291.8|7|no"
)

die() { echo "error: $*" >&2; exit 1; }

list_quants() {
  echo "quants in $REPO and whether they fit a 128gb strix halo at -c $CTX:"
  printf "%-12s %8s %7s %s\n" QUANT "SIZE_GB" SHARDS "FITS_128GB"
  for row in "${QUANTS[@]}"; do
    IFS='|' read -r q s sh fit <<< "$row"
    printf "%-12s %8s %7s %s\n" "$q" "$s" "$sh" "$fit"
  done
  echo
  echo "usage: $0 <QUANT> [--force]   (default receipt quant: UD-IQ1_S)"
}

find_quant() {
  for row in "${QUANTS[@]}"; do
    IFS='|' read -r q s sh fit <<< "$row"
    [ "$q" = "$1" ] && { echo "$row"; return 0; }
  done
  return 1
}

download_quant() {
  local q="$1" size_gb="$2" dir="$MODEL_DIR/$q"
  if ls "$dir"/GLM-5.3-Flash-"$q"-00001-of-*.gguf >/dev/null 2>&1; then
    echo "$q already present in $dir - skipping download"
    return 0
  fi
  mkdir -p "$dir"
  # disk free check (KB) before pulling tens of gb
  if command -v df >/dev/null 2>&1; then
    local avail_kb need_kb
    avail_kb=$(df -Pk "$dir" | awk 'NR==2{print $4}')
    need_kb=$(awk -v g="$size_gb" 'BEGIN{printf "%d", g*1024*1024}')
    [ "$avail_kb" -gt "$need_kb" ] || die "only ${avail_kb}kb free, need ~${need_kb}kb for $q - free up space or pick a smaller quant"
  fi
  local dl
  if command -v hf >/dev/null 2>&1; then
    dl=(hf download "$REPO" --include "$q/*" --local-dir "$MODEL_DIR")
  elif command -v huggingface-cli >/dev/null 2>&1; then
    dl=(huggingface-cli download "$REPO" --include "$q/*" --local-dir "$MODEL_DIR")
  else
    die "need 'hf' or 'huggingface-cli' (pip install -U 'huggingface_hub[cli]')"
  fi
  echo "downloading $q (~${size_gb}gb) from $REPO ..."
  "${dl[@]}"
}

find_engine() {
  local c
  if [ -n "${ENGINE:-}" ]; then
    echo "${ENGINE%/}/llama-completion"; return 0
  fi
  for c in \
    "$HOME/source/ROCmFPX-glm5next/build-strix-glm5next/bin/llama-completion" \
    "./engine/bin/llama-completion" \
    "$(command -v llama-completion 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}

main() {
  local quant="" force=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) force=1; shift ;;
      --list|-l) list_quants; exit 0 ;;
      -h|--help) list_quants; exit 0 ;;
      -*) die "unknown option: $1" ;;
      *) quant="$1"; shift ;;
    esac
  done

  if [ -z "$quant" ]; then list_quants; exit 0; fi

  local row size_gb shards fit
  row=$(find_quant "$quant") || { list_quants; die "unknown quant: $quant"; }
  IFS='|' read -r quant size_gb shards fit <<< "$row"

  if [ "$fit" = "no" ] && [ "$force" -ne 1 ]; then
    die "$quant is ${size_gb}gb - does not fit a 128gb halo (max ~122gb with -c $CTX). use --force to try anyway (expect swapping/hang)"
  fi
  if [ "$fit" = "borderline" ] && [ "$force" -ne 1 ]; then
    echo "warning: $quant is ${size_gb}gb - borderline on 128gb uma at -c $CTX."
    echo "         if it swaps or hangs: rerun with CTX=4096, or wrap the engine to add --cpu-moe / --kv-offload"
  fi

  download_quant "$quant" "$size_gb"

  local model_file
  model_file=$(ls "$MODEL_DIR/$quant"/GLM-5.3-Flash-"$quant"-00001-of-*.gguf 2>/dev/null | head -n 1)
  [ -n "$model_file" ] || die "shard not found after download in $MODEL_DIR/$quant"

  local engine_bin
  engine_bin=$(find_engine) || die "engine not found - set ENGINE=/path/to/bin (llama-completion from unslothai/llama.cpp branch glm5next/upstream, see ../README.md)"

  echo "engine : $engine_bin"
  echo "model  : $model_file"
  echo "flags  : -dev $DEV -ngl $NGL -c $CTX -fa off -ub 512"
  [ "$fit" != "no" ] || echo "WARNING: running a quant that does not fit - expect heavy swap or hang"

  local run=("$engine_bin" -m "$model_file" -dev "$DEV" -ngl "$NGL"
             -c "$CTX" -fa off -ub 512
             -p "$PROMPT" -n "$N_PREDICT"
             --temp 1.0 --top-p 0.95 -no-cnv --simple-io)

  # bounded: hard timeout when available (the 1m default ctx hangs this box)
  if command -v timeout >/dev/null 2>&1; then
    exec timeout 1800 "${run[@]}"
  else
    exec "${run[@]}"
  fi
}

main "$@"
