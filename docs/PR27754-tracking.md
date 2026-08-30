# PR #27754 tracking — glm5next NextN/MTP graph

Last checked: **2026-08-30 08:06**

## Snapshot

| Ref | Value |
|---|---|
| PR state | **OPEN** (unmerged), 31 commits, no NextN/MTP discussion in thread |
| PR head | `d07e71e` (updated 2026-08-30T08:06:22Z) |
| unsloth fork `glm5next/upstream` tip | `d07e71e` |
| our worktree `~/source/ROCmFPX-glm5next` HEAD | `1f0a36a35` |

Worktree is **one commit behind** (`1f0a36a35` vs `d07e71e`) — run `git -C ~/source/ROCmFPX-glm5next fetch unsloth && git log --oneline HEAD..unsloth/glm5next/upstream` to see diff. The NextN
draft graph is still the stub (`glm5next.cpp:690` asserts
`"glm5next NextN graph not implemented yet"` — proven by the MTP attempt in
`results/2026-08-28-glm-server-qa.md`).

## What we're watching for

1. A commit to `glm5next.cpp` implementing `LLM_GRAPH_TYPE_DECODER_MTP`
   (removal of the line-690 assert), OR the PR merging into ggml master with
   NextN support.
2. Merging matters separately: once merged, stock llama.cpp builds gain glm5next
   (and ROCmFPX can port it).

## Re-check commands

```bash
gh pr view 27754 --repo ggml-org/llama.cpp --json state,mergedAt,updatedAt,headRefOid
git -C ~/source/ROCmFPX ls-remote unsloth glm5next/upstream
git -C ~/source/ROCmFPX-glm5next rev-parse --short HEAD
gh api repos/ggml-org/llama.cpp/issues/27754/comments --jq '.[] | select(.body | test("nextn|MTP";"i")) | .created_at' | tail -3
```

## If the NextN graph lands

```bash
git -C ~/source/ROCmFPX-glm5next fetch unsloth && \
  git -C ~/source/ROCmFPX-glm5next merge --ff-only unsloth/glm5next/upstream
cmake --build ~/source/ROCmFPX-glm5next/build-strix-glm5next -j16 \
  --target llama-cli llama-server llama-completion
```

Then rerun the MTP smoke from `results/2026-08-28-glm-server-qa.md`
(`--spec-type draft-mtp --spec-draft-n-max 4 --spec-draft-p-min 0.6`) and
compare decode tok/s against the 9.31 raw baseline.
