#!/usr/bin/env bash
# glm-5.3-flash server qa: reasoning_effort low/max through the jinja chat template
# mirrors results/2026-08-28-glm-server-qa.md (2026-08-28: max gives
# 857-char reasoning_content + 17*23=391 correct)
#
# env overrides:
#   MODEL  path to the shard-00001 gguf
#   ENGINE path to llama-server binary
#   PORT   server port (default 8139)
set -euo pipefail

MODEL="${MODEL:-models/UD-IQ1_S/GLM-5.3-Flash-UD-IQ1_S-00001-of-00003.gguf}"
ENGINE="${ENGINE:-$HOME/source/ROCmFPX-glm5next/build-strix-glm5next/bin/llama-server}"
PORT="${PORT:-8139}"

"$ENGINE" -m "$MODEL" --jinja -dev Vulkan0 -ngl 99 -c 8192 -fa off --port "$PORT" &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT

echo "waiting for health on :$PORT ..."
for _ in $(seq 1 300); do
  curl -sf "http://127.0.0.1:$PORT/health" >/dev/null && break
  sleep 1
done

ask() {
  curl -s "http://127.0.0.1:$PORT/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "{
      \"messages\": [{\"role\": \"user\", \"content\": \"$1\"}],
      \"max_tokens\": $2,
      \"temperature\": 1.0,
      \"top_p\": 0.95,
      \"chat_template_kwargs\": {\"reasoning_effort\": \"$3\"}
    }"
  echo
}

echo "== reasoning_effort=low (expect terse, no thinking) =="
ask "capital of France? one sentence" 200 low
echo
echo "== reasoning_effort=max (expect reasoning_content + 17*23=391) =="
ask "17*23 show work" 400 max
