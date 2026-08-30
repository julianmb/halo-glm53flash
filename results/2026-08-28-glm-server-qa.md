# 2026-08-28 — GLM-5.3-Flash server QA + MTP verdict

Engine: `~/source/ROCmFPX-glm5next` worktree (`unslothai/llama.cpp:glm5next/upstream`
@ `1f0a36a35`), `build-strix-glm5next`, model `weights/UD-IQ1_S` (93GB).

## Server mode + reasoning_effort — PASS

`llama-server --jinja -dev Vulkan0 -ngl 99 -c 8192 -fa off --port 8139`, health OK.

| Test | Request | Result |
|---|---|---|
| reasoning_effort=low | "capital of France? one sentence", 200 tok cap | `"The capital of France is Paris."` — tight, no thinking |
| reasoning_effort=max | "17*23 show work", 400 tok cap | 857 chars `reasoning_content` (two methods, self-verified) + clean `content`: **17×23 = 391** ✓ |

`chat_template_kwargs.reasoning_effort` works through the jinja template.
Receipt: server log + this file. Server killed after QA (cleanup done).

## MTP (draft-mtp speculative) — NOT IMPLEMENTED upstream

Three attempts, all dead ends, ending in a definitive assert:
1. `llama-completion --spec-type draft-mtp` → `error: invalid argument: --spec-type`
   (flag registered only for SPECULATIVE/SERVER/CLI example types)
2. `llama-cli -no-cnv --spec-type ...` → `error: invalid argument: -no-cnv`
   (also example-gated in this build)
3. `llama-server --spec-type draft-mtp --spec-draft-n-max 4 --spec-draft-p-min 0.6`
   → server never binds; log ends in:
   `glm5next.cpp:690: GGML_ASSERT(params.gtype != LLM_GRAPH_TYPE_DECODER_MTP &&
   "glm5next NextN graph not implemented yet") failed`

**Verdict:** the `blk.45.nextn.*` MTP head tensors are loaded but the NextN
draft graph is an explicit stub upstream. Reviving MTP = implementing the
`LLM_GRAPH_TYPE_DECODER_MTP` case in glm5next.cpp (eh_proj/enorm/hnorm wiring
+ draft KV) — real port work, the single biggest tok/s lever (cf. qwen38 MTP 2.4×).
Track upstream PR #27754 for an implementation landing.
