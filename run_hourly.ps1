# Hourly wrapper for the threshold campaign. Registered as scheduled task
# "NeuRAM_ThresholdCampaign_Hourly". Advances one iteration (respecting the
# 55-min guard in the runner), commits progress, and removes itself on out/DONE.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$task = "NeuRAM_ThresholdCampaign_Hourly"

# Already finished -> remove the task and stop.
if (Test-Path ".\out\DONE") { schtasks /Delete /TN $task /F 2>$null; exit 0 }

# Advance one iteration (runner enforces the hourly guard).
$s = & dart run bin/campaign_iter.dart 2>&1
$s | Tee-Object ".\out\last_run.txt" | Out-Null

# Guard skip -> nothing to commit.
if ("$s" -match "skip") { exit 0 }

# Commit progress; push if credentials allow, else record the failure.
git add -A 2>$null
git commit -m ("chore(campaign): iter " + (Get-Date -Format "yyyy-MM-dd HH:mm") + " - " + ($s | Select-Object -Last 1)) 2>$null
$push = git push origin feature/threshold-campaign 2>&1
"$push" | Add-Content ".\out\last_run.txt"
if ($LASTEXITCODE -ne 0) {
  Add-Content ".\out\STATUS.md" "`n> NOTE: auto-push failed — manual push of feature/threshold-campaign needed.`n> $push"
  git add out/STATUS.md 2>$null
  git commit --amend --no-edit 2>$null
}

# If the campaign finished this run, remove the task.
if (Test-Path ".\out\DONE") { schtasks /Delete /TN $task /F 2>$null }
