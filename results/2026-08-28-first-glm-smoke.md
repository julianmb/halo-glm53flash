# 2026-08-28 — GLM-5.3-Flash first successful run on Strix Halo

Engine: `~/source/ROCmFPX-glm5next` worktree @ `unslothai/llama.cpp:glm5next/upstream`
(`1f0a36a35`), build `build-strix-glm5next` (HIP+Vulkan, gfx1151, static,
CMAKE_POSITION_INDEPENDENT_CODE=ON — required, PIE link fails otherwise).

Model: `weights/UD-IQ1_S/` (93GB, 3 shards, unmodified unsloth dynamic 1-bit —
no ROCmFPX quant needed to run).

Command:
```
llama-completion -m weights/UD-IQ1_S/GLM-5.3-Flash-UD-IQ1_S-00001-of-00003.gguf \
  -dev Vulkan0 -ngl 99 -c 8192 -fa off -ub 512 \
  -p "The capital of France is" -n 32 --temp 1.0 --top-p 0.95 -no-cnv --simple-io
```

Result: **COHERENT** —
"The capital of France is Paris, a city with a rich history and culture, home to
famous landmarks like the Eiffel Tower and the Louvre Museum. It is also the country"

- load 25.5s (93GB mmap)
- prompt eval 19.7 tok/s
- **decode 9.31 tok/s** (raw, no speculative)
- peak RSS 402 GiB?? — no: 412044 kB = 402 MB... no, 412044*1024 = 421MB —
  actually 412044 kB ≈ 402 GiB is wrong; 412044 kB = 402 MB. (mmap'd weights not counted in RSS)
- unused-tensor warnings: blk.45.nextn.{enorm,hnorm,shared_head_norm} (MTP head,
  ignored by this build — future MTP/speculative work)
- `-fa off` required (PR #27754 MLA correctness), `-c 8192` bounded (1M default)

Conclusion: GLM-5.3-Flash UD-IQ1_S RUNS on Strix Halo Vulkan at ~9.3 tok/s raw.
Next: server mode + reasoning_effort kwarg; then ROCmFP4 quant feasibility
(needs arch port into ROCmFPX tree — see port plan in HANDOVER.md).
