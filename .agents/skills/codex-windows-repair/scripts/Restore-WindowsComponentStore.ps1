#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
param([Parameter(Mandatory=$true)][string]$EvidencePath)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
$evidence=Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json
foreach ($required in @('schemaVersion','collectedAtUtc','windows','appPackages','appxEvents')) {
    if (-not $evidence.PSObject.Properties[$required]) { throw 'A complete collector snapshot is required.' }
}
if ([string]$evidence.schemaVersion -notin @('1.0','1.1')) { throw 'Unsupported collector schema.' }
$collected=[DateTimeOffset]::Parse($evidence.collectedAtUtc)
$age=[DateTimeOffset]::UtcNow-$collected
if ($age.TotalHours -gt 24 -or $age.TotalMinutes -lt -5) { throw 'Refresh the diagnostic snapshot before selecting live repair.' }
$deploymentFailures=@($evidence.appxEvents | Where-Object {
    $eventTime=[DateTimeOffset]::MinValue
    $_.PSObject.Properties['timeUtc'] -and $_.PSObject.Properties['hexCodes'] -and
    [DateTimeOffset]::TryParse([string]$_.timeUtc,[ref]$eventTime) -and
    ([DateTimeOffset]::UtcNow-$eventTime).TotalHours -le 24 -and
    ([DateTimeOffset]::UtcNow-$eventTime).TotalMinutes -ge -5 -and
    ($eventTime-$collected).TotalMinutes -le 5 -and
    @($_.hexCodes | Where-Object { $_ -match '^0X[89A-Fa-f][0-9A-Fa-f]{7}$' }).Count -gt 0
})
if (-not $deploymentFailures.Count) { throw 'No matching deployment-failure evidence; select another diagnostic path.' }
$plan=[ordered]@{stage='planned';operation='scan-and-restore-only-if-repairable';deploymentFailureCount=$deploymentFailures.Count;livePreflightPerformed=$false;automaticallyRestart=$false;mutationPerformed=$false}
if ($WhatIfPreference) { $plan | ConvertTo-Json; return }

$osInfo=Get-CimInstance Win32_OperatingSystem
$currentApp=@(Get-AppxPackage -Name OpenAI.Codex)
if (-not $evidence.PSObject.Properties['windows'] -or [string]$evidence.windows.build -ne [string]$osInfo.BuildNumber) { throw 'Snapshot does not match the current Windows build.' }
$matchingApp=@($currentApp | Where-Object {
    $current=$_
    @($evidence.appPackages | Where-Object {$_.name -eq $current.Name -and [string]$_.version -eq [string]$current.Version}).Count -gt 0
})
if (-not $matchingApp.Count) { throw 'Snapshot does not match the current app version.' }
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Existing administrator access is required; no elevation was attempted.' }
$plan.livePreflightPerformed=$true
if (-not $PSCmdlet.ShouldProcess('Windows component store','Scan and restore only if repairable, without restarting')) { $plan | ConvertTo-Json; return }

$health=Repair-WindowsImage -Online -ScanHealth -NoRestart
$healthState=[string]$health.ImageHealthState
$result=[ordered]@{stage='scanned';healthBefore=$healthState;healthAfter=$healthState;restorationPerformed=$false;automaticallyRestart=$false;restartRequirement=$null}
if ($health.PSObject.Properties['RestartNeeded']) { $result.restartRequirement=$health.RestartNeeded }
switch ($healthState) {
    'Healthy' { $result.stage='healthy-no-restoration-needed' }
    'Repairable' {
        $restored=Repair-WindowsImage -Online -RestoreHealth -NoRestart
        $result.restorationPerformed=$true
        $result.healthAfter=[string]$restored.ImageHealthState
        $result.stage=$(if ($result.healthAfter -eq 'Healthy') {'restored'} else {'restoration-needs-investigation'})
        if ($restored.PSObject.Properties['RestartNeeded']) { $result.restartRequirement=$restored.RestartNeeded }
    }
    default { $result.stage='health-needs-investigation' }
}
$result | ConvertTo-Json
