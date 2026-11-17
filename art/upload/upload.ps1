# Capeline art upload (runs on nate's PC only; the key never leaves it).
# Started by upload.bat. Reads the Open Cloud key file (line 1 = the API key, line 2 = nate's Roblox user id), uploads every file in
# manifest.json as a Decal on his account (not for sale, not listed anywhere), and writes ids.json
# (file name -> decal asset id). Safe to run again: files already in ids.json are skipped.
#   powershell -ExecutionPolicy Bypass -File upload.ps1 [-KeyFile <path>]
param([string]$KeyFile = "")

if ($KeyFile -eq "") {
	$KeyFile = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "roblox-keys\capeline-key.txt"
	if (-not (Test-Path $KeyFile)) { $KeyFile = "$env:USERPROFILE\Documents\roblox-keys\capeline-key.txt" }
}
if (-not (Test-Path $KeyFile)) { Write-Host "Key file not found: $KeyFile"; exit 1 }

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$lines = Get-Content -Path $KeyFile
$key = $lines[0].Trim()
$userId = $lines[1].Trim()
$manifest = Get-Content -Raw -Path (Join-Path $here "manifest.json") | ConvertFrom-Json
$idsPath = Join-Path $here "ids.json"
$ids = @{}
if (Test-Path $idsPath) {
	(Get-Content -Raw -Path $idsPath | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $ids[$_.Name] = $_.Value }
}
$tmp = Join-Path $env:TEMP "capeline-upload-request.json"
$failed = @()

function Save-Ids { $ids | ConvertTo-Json | Set-Content -Path $idsPath -Encoding UTF8 }

foreach ($item in $manifest.items) {
	if ($ids.ContainsKey($item.file)) { continue }
	$request = @{
		assetType = $item.type
		displayName = $item.name
		description = "Capeline game art"
		creationContext = @{ creator = @{ userId = $userId } }
	} | ConvertTo-Json -Depth 5 -Compress
	Set-Content -Path $tmp -Value $request -Encoding ASCII
	$file = Join-Path $here ("files\" + $item.file)
	$done = $false
	for ($try = 1; $try -le 5 -and -not $done; $try++) {
		$raw = & curl.exe -s -X POST "https://apis.roblox.com/assets/v1/assets" -H "x-api-key: $key" `
			-F "request=<$tmp;type=application/json" -F "fileContent=@$file;type=image/png"
		$op = $null
		try { $op = $raw | ConvertFrom-Json } catch { }
		if ($null -eq $op -or $null -eq $op.path) {
			Write-Host "retry $($item.file): $raw"
			Start-Sleep -Seconds (5 * $try)
			continue
		}
		$opId = ($op.path -split "/")[-1]
		for ($poll = 0; $poll -lt 30; $poll++) {
			if ($op.done -and $op.response.assetId) { break }
			Start-Sleep -Seconds 2
			try { $op = (& curl.exe -s "https://apis.roblox.com/assets/v1/operations/$opId" -H "x-api-key: $key") | ConvertFrom-Json } catch { }
		}
		if ($op.done -and $op.response.assetId) {
			$ids[$item.file] = [string]$op.response.assetId
			Save-Ids
			Write-Host "ok $($item.file) -> $($op.response.assetId)"
			$done = $true
		}
	}
	if (-not $done) { $failed += $item.file }
	Start-Sleep -Milliseconds 1200
}
Save-Ids
Write-Host "uploaded $($ids.Count) of $($manifest.items.Count); failed: $($failed.Count)"
$failed | ForEach-Object { Write-Host "FAILED $_" }
