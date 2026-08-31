# PR #27754 tracking — glm5next NextN/MTP graph

Last checked: **2026-08-31**

## Snapshot

| Ref | Value |
|---|---|
| PR state | **OPEN** (unmerged) |
| PR head | `5796547` (updated 2026-08-30T22:34:37Z) |
| unsloth fork `glm5next/upstream` tip | `5796547` |
| our worktree `~/source/ROCmFPX-glm5next` HEAD | `5796547f3` (merged + rebuilt 2026-08-31, build 10748) |

## Delta 1f0a36a35 -> d07e71e (fetched + verified 2026-08-30)

| commit | what |
|---|---|
| `b5517b15d` | tests: add the glm5next fixture |
| `f30bed887` | kv-cache: group the context accessors after type_v |
| `00699716c` | **faster inference** — kv-cache-kpool +159, hybrid/recurrent memory, glm5next.cpp +40 |
| `d07e71ede` | **add MTP support** — glm5next.cpp +146, models.h +8 |

**the nextn stub is gone.** `glm5next.cpp:846` now branches
`if (params.gtype == LLM_GRAPH_TYPE_DECODER_MTP)` instead of asserting
`"glm5next NextN graph not implemented yet"`. the old verdict in
`results/2026-08-28-glm-server-qa.md` was true for `1f0a36a35` but is
superseded as of `d07e71ede` (2026-08-30 06:24 utc).

## State (2026-08-30 evening)

worktree merged to `d07e71ede` (ff-only) and rebuilt clean — `build-strix-glm5next`
now reports `version: 0.3.0-dev (build 10700, commit d07e71ede)`. flag survey of
the new build:

| flag | llama-completion | llama-server | notes |
|---|---|---|---|
| `--spec-type` | absent | **present** | `draft-mtp` is a registered value (also `draft-dflash`, `draft-dspark`, …) |
| `--spec-draft-n-max` / `--spec-draft-p-min` | absent | **present** | the smoke command from the server QA receipt is runnable as-is |
| `--cpu-moe` | present | present | expert FFNs on cpu |
| `--fit` | present | present | |
| `--kv-offload` | present | present | |
| `--no-kv-unified` / `--cache-ram` | absent | absent | from a different/newer build, not this fork |

update 2026-08-31: ff-merged to `5796547f3` — glm5next pooled-keys fix
(`5796547f3` "invalidate pooled keys when a shift splits a pool") + big
ggml/master merge (`a175dcd33`, incl. hip rdna3 mmq tuning). rebuilt clean:
`build 10748, commit 5796547f3`; `draft-mtp` still registered.

synthetic verification (no weights needed): `test-llama-archs` at `5796547f3`
— glm5next fixture **ok on all backends** (vulkan, radv strix halo, meta
skip), 0 fails. suite-wide 41 fails are upstream's, all on one backend
enumeration (refact/qwen2/qwen3tts/pockettts/...), none involve glm5next.

**only the bench is blocked**: `UD-IQ1_S` weights were cleaned from
`/mnt/ssd2/models/glm-5.3-flash/` on 2026-08-30 (re-downloadable from
`unsloth/GLM-5.3-Flash-GGUF`, 93g). pending approval to re-pull.

## Re-check commands

```bash
gh pr view 27754 --repo ggml-org/llama.cpp --json state,mergedAt,updatedAt,headRefOid
git -C ~/source/ROCmFPX ls-remote unsloth glm5next/upstream
git -C ~/source/ROCmFPX-glm5next rev-parse --short HEAD
gh api repos/ggml-org/llama.cpp/issues/27754/comments --jq '.[] | select(.body | test("nextn|MTP";"i")) | .created_at' | tail -3
```

## When weights are back

merge + rebuild are already done (state above). remaining steps:

1. `hf download unsloth/GLM-5.3-Flash-GGUF --include "UD-IQ1_S/*" --local-dir /mnt/ssd2/models/glm-5.3-flash`
2. rerun the MTP smoke from `results/2026-08-28-glm-server-qa.md`
   (`llama-server --spec-type draft-mtp --spec-draft-n-max 4 --spec-draft-p-min 0.6` —
   `draft-mtp` is now a registered value in this build) — compare decode
   tok/s against the 9.31 raw baseline (qwen38 reference: 2.4x)
3. A/B `--cpu-moe` on/off at 8k ctx
4. add the second data row to the gh repo readme
