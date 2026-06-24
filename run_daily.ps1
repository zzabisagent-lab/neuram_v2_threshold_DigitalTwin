# Daily wrapper for the threshold campaign. Registered as scheduled task
# "NeuRAM_ThresholdCampaign". Advances one day, commits the progress, and removes
# itself once the campaign saturates (out/DONE).
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$taskName = "NeuRAM_ThresholdCampaign"

# Already finished on a previous run -> remove the task and stop.
if (Test-Path ".\out\DONE") {
  schtasks /Delete /TN $taskName /F 2>$null
  exit 0
}

# 1) advance one day
$summary = & dart run bin/campaign_day.dart 2>&1
$summary | Tee-Object -FilePath ".\out\last_run.txt" | Out-Null
$lastLine = ($summary | Select-Object -Last 1)

# 2) commit progress (out/ artifacts). Push if credentials allow; else local-only.
git add out/ 2>$null
git commit -m ("chore(campaign): day auto-run " + (Get-Date -Format "yyyy-MM-dd") + " - " + $lastLine) 2>$null
$pushed = $false
try {
  git push origin feature/threshold-campaign 2>$null
  if ($LASTEXITCODE -eq 0) { $pushed = $true }
} catch { $pushed = $false }
if (-not $pushed) {
  Add-Content ".\out\STATUS.md" "`n> NOTE: auto-push failed (no git credentials in scheduled context). Local commit only — please push feature/threshold-campaign manually."
  git add out/STATUS.md 2>$null
  git commit --amend --no-edit 2>$null
}

# 3) if the campaign finished this run, remove the task so it stops.
if (Test-Path ".\out\DONE") {
  schtasks /Delete /TN $taskName /F 2>$null
}
