# glm-5.3-flash quant picker + downloader + smoke for windows (strix halo 128gb or any cuda/vulkan box)
#
# usage (powershell):
#   .\smoke.ps1                       # list quants and what fits 128gb
#   .\smoke.ps1 UD-IQ1_S              # download (if missing) + run the smoke
#   .\smoke.ps1 UD-IQ3_XXS -Force     # allow borderline / non-fitting quants
#
# requires: huggingface cli (pip install -U "huggingface_hub[cli]") and a
# llama.cpp build with glm5next support (unslothai/llama.cpp branch
# glm5next/upstream = ggml PR #27754). prefers llama-completion.exe, falls
# back to llama-cli.exe (drops the completion-only flags if so).
#
# notes for the measured receipt: linux + radv vulkan; on windows the vulkan
# backend differs (amd adrenalin driver), expect somewhat different tok/s.
param(
  [Parameter(Position = 0)][string]$Quant = "",
  [int]$Ctx = 8192,
  [int]$NPredict = 32,
  [string]$Dev = "Vulkan0",
  [int]$Ngl = 99,
  [string]$ModelDir = "models",
  [string]$Engine = "",
  [string]$Repo = "unsloth/GLM-5.3-Flash-GGUF",
  [string]$Prompt = "The capital of France is",
  [switch]$Force,
  [switch]$List
)

$ErrorActionPreference = "Stop"

# name | size_gb | shards | fit on 128gb uma (yes | borderline | no)
$Quants = @(
  ,@("UD-IQ1_S",   "93.1", "3", "yes")
  ,@("UD-IQ1_M",   "97.6", "3", "yes")
  ,@("UD-IQ2_XXS", "101.8", "4", "yes")
  ,@("UD-Q2_K_XL", "108.7", "4", "yes")
  ,@("UD-IQ3_XXS", "120.4", "4", "borderline")
  ,@("UD-IQ4_XS",  "156.8", "5", "no")
  ,@("UD-Q4_K_XL", "199.7", "6", "no")
  ,@("UD-Q5_K_XL", "240.3", "6", "no")
  ,@("UD-Q6_K_XL", "291.8", "7", "no")
)

function Show-Quants {
  Write-Host "quants in $Repo and whether they fit a 128gb strix halo at -c $Ctx :"
  "{0,-12} {1,8} {2,7} {3}" -f "QUANT", "SIZE_GB", "SHARDS", "FITS_128GB"
  foreach ($row in $Quants) {
    "{0,-12} {1,8} {2,7} {3}" -f $row[0], $row[1], $row[2], $row[3]
  }
  Write-Host ""
  Write-Host "usage: .\smoke.ps1 <QUANT> [-Force]   (default receipt quant: UD-IQ1_S)"
}

function Find-Quant([string]$Name) {
  foreach ($row in $Quants) { if ($row[0] -eq $Name) { return $row } }
  return $null
}

function Download-Quant([string]$Q, [string]$SizeGb) {
  $dir = Join-Path $ModelDir $Q
  if (Get-ChildItem -Path $dir -Filter "GLM-5.3-Flash-$Q-00001-of-*.gguf" -ErrorAction SilentlyContinue) {
    Write-Host "$Q already present in $dir - skipping download"
    return
  }
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  # disk free check before pulling tens of gb
  $drive = Get-PSDrive -Name ($dir.Substring(0, 1))
  $needGb = [double]$SizeGb
  if ($drive.Free / 1GB -lt $needGb) {
    throw ("only {0:n1} gb free, need ~{1} gb for $Q - free up space or pick a smaller quant" -f ($drive.Free / 1GB), $needGb)
  }
  $cli = $null
  if (Get-Command hf -ErrorAction SilentlyContinue) { $cli = "hf" }
  elseif (Get-Command huggingface-cli -ErrorAction SilentlyContinue) { $cli = "huggingface-cli" }
  else { throw "need 'hf' or 'huggingface-cli' (pip install -U 'huggingface_hub[cli]')" }
  Write-Host "downloading $Q (~$SizeGb gb) from $Repo ..."
  & $cli download $Repo --include "$Q/*" --local-dir $ModelDir
  if ($LASTEXITCODE -ne 0) { throw "download failed" }
}

function Find-Engine {
  if ($Engine -ne "") { return (Join-Path $Engine.TrimEnd('\') "llama-completion.exe") }
  $candidates = @(
    (Join-Path $ModelDir "..\engine\bin\llama-completion.exe"),
    ".\engine\bin\llama-completion.exe"
  )
  foreach ($c in $candidates) {
    if (Test-Path $c) { return $c }
  }
  $cmd = Get-Command llama-completion.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

if ($List -or $Quant -eq "") { Show-Quants; exit 0 }

$row = Find-Quant $Quant
if (-not $row) { Show-Quants; throw "unknown quant: $Quant" }
$SizeGb = $row[1]; $Fit = $row[3]

if ($Fit -eq "no" -and -not $Force) {
  throw "$Quant is $SizeGb gb - does not fit a 128gb halo (max ~122 gb with -c $Ctx). use -Force to try anyway (expect swapping/hang)"
}
if ($Fit -eq "borderline" -and -not $Force) {
  Write-Warning "$Quant is $SizeGb gb - borderline on 128gb uma at -c $Ctx. if it swaps or hangs: rerun with -Ctx 4096, or wrap the engine to add --cpu-moe / --kv-offload"
}

Download-Quant $Quant $SizeGb

$shard = Get-ChildItem -Path (Join-Path $ModelDir $Quant) -Filter "GLM-5.3-Flash-$Quant-00001-of-*.gguf" |
  Select-Object -First 1
if (-not $shard) { throw "shard not found after download in $(Join-Path $ModelDir $Quant)" }

$engineBin = Find-Engine
if (-not $engineBin) {
  throw "engine not found - set -Engine <dir> (llama-completion.exe or llama-cli.exe from unslothai/llama.cpp branch glm5next/upstream)"
}
# fall back to llama-cli.exe (windows release builds ship it; the fork's
# llama-completion.exe is preferred because -no-cnv / --simple-io live there)
$cliFlags = @("-no-cnv", "--simple-io")
if (-not (Test-Path $engineBin)) {
  $cliExe = Get-Command llama-cli.exe -ErrorAction SilentlyContinue
  if ($cliExe) { $engineBin = $cliExe.Source; $cliFlags = @() }
  else { throw "neither llama-completion.exe nor llama-cli.exe found" }
}

Write-Host "engine : $engineBin"
Write-Host "model  : $($shard.FullName)"
Write-Host "flags  : -dev $Dev -ngl $Ngl -c $Ctx -fa off -ub 512"
if ($Fit -eq "no") { Write-Warning "running a quant that does not fit - expect heavy swap or hang" }

# bounded: hard timeout so a runaway run can't wedge the box unattended
$args_ = @("-m", $shard.FullName, "-dev", $Dev, "-ngl", $Ngl,
           "-c", $Ctx, "-fa", "off", "-ub", "512",
           "-p", $Prompt, "-n", $NPredict,
           "--temp", "1.0", "--top-p", "0.95") + $cliFlags
$proc = Start-Process -FilePath $engineBin -ArgumentList $args_ -NoNewWindow -PassThru
if (-not $proc.WaitForExit(1800 * 1000)) {
  Write-Warning "timeout after 30 min - killing"
  $proc.Kill()
  exit 124
}
exit $proc.ExitCode
