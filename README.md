# GLM-5.3-Flash on AMD Strix Halo — optimized llama.cpp setup + receipts

a tuned, verified setup for running **GLM-5.3-Flash** (zai-org, 320b total / 18b active, hybrid KDA + DSA attention, mHC, 1m ctx) on an **amd ryzen ai max+ 395 (strix halo, gfx1151, 128gb unified memory)** with llama.cpp — plus the measured numbers and every flag that mattered getting there.

- gguf: [`unsloth/GLM-5.3-Flash-GGUF`](https://huggingface.co/unsloth/GLM-5.3-Flash-GGUF) (arch `glm5next`)
- engine: [`unslothai/llama.cpp` branch `glm5next/upstream`](https://github.com/unslothai/llama.cpp/tree/glm5next/upstream) (= [ggml-org PR #27754](https://github.com/ggml-org/llama.cpp/pull/27754), **not merged into mainline llama.cpp yet**)
- all numbers below are measured on real hardware, raw logs in [`results/`](results/)

## headline results (2026-08-28, ud-iq1_s 93gb)

| metric | value | conditions |
|---|---|---|
| decode | **9.31 tok/s** | raw, no speculative decoding, radv vulkan, -ngl 99 |
| prefill | 19.72 tok/s | 5-token prompt (short — treat as order-of-magnitude) |
| model load | 25.49 s | 93 gb mmap from nvme |
| peak rss | ~402 mb | weights are mmap'd, not counted |
| coherence | pass | "the capital of france is paris, a city with a rich history..." |

writeup: [`results/2026-08-28-first-glm-smoke.md`](results/2026-08-28-first-glm-smoke.md) · raw log: [`results/smoke-glm-ud-iq1s.log`](results/smoke-glm-ud-iq1s.log)

### server mode + thinking modes — pass

openai-compatible server with `--jinja`; `reasoning_effort` (low / high / max) works through the chat template:

| test | request | result |
|---|---|---|
| `reasoning_effort=low` | "capital of france? one sentence" | `"the capital of france is paris."` — terse, no thinking |
| `reasoning_effort=max` | "17*23 show work" | 857 chars of `reasoning_content` (two methods, self-verified) + clean final answer: **17×23 = 391** |

writeup: [`results/2026-08-28-glm-server-qa.md`](results/2026-08-28-glm-server-qa.md)

### mtp / speculative decoding — not implemented upstream

the gguf ships the nextn/mtp head (`blk.45.nextn.*`, loads fine) but the draft graph is an explicit stub: requesting it hits `glm5next.cpp:690 GGML_ASSERT(... "glm5next NextN graph not implemented yet")`. three attempts, all end at that assert ([`results/smoke-glm-mtp.log`](results/smoke-glm-mtp.log)). so **9.31 tok/s is the no-speculation baseline**; implementing `LLM_GRAPH_TYPE_DECODER_MTP` is the single biggest tok/s lever (the same trick gave 2.4x on qwen3.8-flash-next on this class of hardware). watch state: [`docs/PR27754-tracking.md`](docs/PR27754-tracking.md).

## hardware this was measured on

| part | value |
|---|---|
| apu | amd ryzen ai max+ 395 (strix halo), radeon 8060s, `gfx1151` |
| memory | 128 gb unified (124 gi usable) |
| cpu threads used | 16 of 32 |
| kernel | 7.0.0-30-generic, inbox amdgpu 7.0.0-30, no dkms |
| vulkan | mesa radv, api 1.4.354, driver 26.1.7 |
| rocm | 7.2.3 present (hip used at build time; decode ran on radv vulkan) |

## recreate it

### 1. weights (93 gb)

```bash
pip install -U "huggingface_hub[cli]"
hf download unsloth/GLM-5.3-Flash-GGUF \
  --include "UD-IQ1_S/*" \
  --local-dir models
# expect 3 shards: 9.4mb + 49.6gb + 43.5gb = 93.09gb total
```

### 2. engine

the `UD-IQ1_S` quant uses only stock llama.cpp quant types — no custom kernels, no patching:

```bash
git clone https://github.com/unslothai/llama.cpp glm5next-engine
cd glm5next-engine
git checkout 1f0a36a35   # commit the receipts here were measured at
# (or track the branch tip: git checkout glm5next/upstream)

cmake -S . -B build-strix-glm5next \
  -DGGML_HIP=ON -DGGML_VULKAN=ON \
  -DAMDGPU_TARGETS=gfx1151 \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build build-strix-glm5next -j16 --target llama-completion llama-server
```

build gotchas:
- **`-DCMAKE_POSITION_INDEPENDENT_CODE=ON` is required** — static hip objects fail the pie link step otherwise.
- receipts used the hip+vulkan build; decode ran on radv vulkan. a vulkan-only build should also work but is untested here.
- this fork ships `llama-completion`; prefer it over `llama-cli` (different arg gating — e.g. `-no-cnv` is rejected there).

### 3. smoke test

or just run [`scripts/smoke.sh`](scripts/smoke.sh) (env-overridable `MODEL` / `ENGINE` / `N_PREDICT`):

```bash
timeout 900 /usr/bin/time -v <engine>/bin/llama-completion \
  -m models/UD-IQ1_S/GLM-5.3-Flash-UD-IQ1_S-00001-of-00003.gguf \
  -dev Vulkan0 -ngl 99 \
  -c 8192 -fa off -ub 512 \
  -p "The capital of France is" -n 32 \
  --temp 1.0 --top-p 0.95 -no-cnv --simple-io
```

expect: coherent paris answer at ~9.3 tok/s decode. the exact expected log is [`results/smoke-glm-ud-iq1s.log`](results/smoke-glm-ud-iq1s.log).

### 4. server + thinking modes

or just run [`scripts/server-qa.sh`](scripts/server-qa.sh):

```bash
<engine>/bin/llama-server \
  -m models/UD-IQ1_S/GLM-5.3-Flash-UD-IQ1_S-00001-of-00003.gguf \
  --jinja -dev Vulkan0 -ngl 99 -c 8192 -fa off --port 8139 &

curl http://127.0.0.1:8139/v1/chat/completions -H "Content-Type: application/json" -d '{
  "messages": [{"role":"user","content":"17*23 show work"}],
  "max_tokens": 400, "temperature": 1.0, "top_p": 0.95,
  "chat_template_kwargs": {"reasoning_effort": "max"}
}'
```

## flags you must not skip (hard-won)

| flag | why |
|---|---|
| `-c 8192` (or any explicit bound) | the gguf defaults to 1,048,576 ctx — allocating that on 128gb uma **hard-hung the box** once. always bound it. |
| `-fa off` | flash attention breaks mla correctness on this arch (per upstream pr). garbage output with `-fa on`. |
| `-ub 512` | the ub used in the measured run; larger values untested for glm. |
| `timeout` + `/usr/bin/time -v` | cheap insurance on a box that can hard-hang. |
| `--temp 1.0 --top-p 0.95` | z.ai's recommended sampling for this model. |

## quant ladder (unsloth dynamic, from their published kld bench)

| quant | size | top-1 acc retained | fits 128gb uma? |
|---|---|---|---|
| UD-IQ1_S | 93.1 gb | 70.9% | yes — **these receipts** |
| UD-IQ1_M | 97.6 gb | 73.1% | yes |
| UD-IQ2_XXS | 101.8 gb | 76.3% | yes, tight with kv |
| UD-Q2_K_XL | 108.7 gb | 78.3% | yes, tight |
| UD-IQ3_XXS | 120.4 gb | 81.6% | borderline (unsloth's own 128gb demo quant) |
| UD-Q4_K_XL | 199.7 gb | 92.2% | no |

only UD-IQ1_S has been run on strix halo so far.

## repo layout

```
.
├── README.md            <- this file
├── scripts/
│   ├── smoke.sh         <- one-command reproduction of the measured smoke
│   └── server-qa.sh     <- one-command server + reasoning_effort test
├── results/             <- receipts: writeups + raw logs, one per measurement
└── docs/
    └── PR27754-tracking.md   <- upstream merge / mtp watch state
```

## status / roadmap

- [x] ud-iq1_s raw smoke, coherent, 9.31 tok/s (radv vulkan)
- [x] server mode + `reasoning_effort` low/max
- [ ] mtp/nextn speculative decoding — blocked on upstream stub (`glm5next.cpp:690`)
- [ ] ud-iq1_m / ud-iq2_xxs numbers on halo
- [ ] hip decode path numbers (current receipts are radv vulkan)

## credits

- zai-org — [GLM-5.3-Flash](https://huggingface.co/zai-org/GLM-5.3-Flash) (mit)
- unsloth — [dynamic gguf quants](https://huggingface.co/unsloth/GLM-5.3-Flash-GGUF) + the `glm5next` llama.cpp branch
- measured on a single strix halo box; n=1, short prompts — treat the tok/s as a baseline to beat, not a spec.
