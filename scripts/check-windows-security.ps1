# Records evidence; never changes antivirus policy or uploads samples.
param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$file = (Resolve-Path -LiteralPath $Executable).Path
$signature = Get-AuthenticodeSignature -LiteralPath $file
$report = [ordered]@{
    sha256 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    signatureStatus = $signature.Status.ToString()
    defenderStatus = 'not_run'
    defenderEngine = $null
    defenderDefinitions = $null
    v3Status = 'not_tested'
    scope = 'CI-host Defender only when available; not a V3 or SmartScreen verdict.'
}
$scanStarted = $false
$mp = Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($mp) {
    try {
        $state = Get-MpComputerStatus
        $report.defenderEngine = $state.AMEngineVersion
        $report.defenderDefinitions = $state.AntivirusSignatureVersion
        if ($state.AMServiceEnabled -and $state.AntivirusEnabled) {
            $platform = Join-Path $env:ProgramData 'Microsoft\Windows Defender\Platform'
            $scanner = Get-ChildItem -LiteralPath $platform -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                ForEach-Object { Join-Path $_.FullName 'MpCmdRun.exe' } |
                Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if (-not $scanner) { $scanner = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe' }
            if (Test-Path -LiteralPath $scanner) {
                # Do not remediate/quarantine samples or suppress detections; fail the build instead.
                $scanStarted = $true
                & $scanner -Scan -ScanType 3 -File $file -DisableRemediation
                $code = $LASTEXITCODE
                $report.defenderStatus = if ($code -eq 0) { 'scan_completed_no_threat_reported' } else { 'scan_failed_or_detected' }
                $report.defenderExitCode = $code
            } else { $report.defenderStatus = 'scanner_unavailable' }
        } else { $report.defenderStatus = 'service_unavailable' }
    } catch {
        $report.defenderStatus = if ($scanStarted) { 'scan_error' } else { 'service_query_unavailable' }
        Write-Warning 'Defender status/scan could not be completed; no clean verdict is claimed.'
    }
} else { $report.defenderStatus = 'cmdlet_unavailable' }
if ($report.signatureStatus -notin @('Valid', 'NotSigned')) {
    throw 'Invalid/untrusted signature status. Refusing to package.'
}
$destination = Join-Path $OutputDirectory 'antivirus-report.json'
$report | ConvertTo-Json | Set-Content -LiteralPath $destination -Encoding utf8
Write-Host "Authenticode: $($report.signatureStatus); Defender: $($report.defenderStatus); V3: not tested"
if ($report.defenderStatus -eq 'scan_failed_or_detected' -or $report.defenderStatus -eq 'scan_error') {
    throw 'Antivirus scan did not establish a clean result. Review before packaging.'
}
