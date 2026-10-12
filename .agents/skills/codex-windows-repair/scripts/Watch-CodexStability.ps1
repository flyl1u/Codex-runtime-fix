#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateRange(1,3600)][int]$ObservationSeconds=600,
    [int]$MainProcessId=0,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'Windows is required.'}
$outputFile=[IO.Path]::GetFullPath($OutputPath)
$parent=[IO.Path]::GetDirectoryName($outputFile)
$null=[IO.Directory]::CreateDirectory($parent)
$status=[ordered]@{stage='initializing';timeUtc=[DateTimeOffset]::UtcNow.ToString('o');selectedIntervalSeconds=$ObservationSeconds;observedSeconds=0;mainSurvived=$false;responding=$false;responseSampleCount=0;unresponsiveSampleCount=0;crashDirectoriesObserved=0;newCrashFileCount=0;samplingErrorCount=0;originalWorkloadVerified=$false}
function Save-Observation {
    $status.timeUtc=[DateTimeOffset]::UtcNow.ToString('o')
    [IO.File]::WriteAllText($outputFile,($status | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
}
try{
    $packages=@(Get-AppxPackage -Name OpenAI.Codex)
    $mains=@(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe' OR Name='Codex.exe'" | Where-Object {
        $p=$_
        $p.CommandLine -notmatch '--type=' -and @($packages | Where-Object {$_.InstallLocation -and $p.ExecutablePath -and $p.ExecutablePath.StartsWith($_.InstallLocation.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)}).Count -gt 0
    })
    if($MainProcessId){$mains=@($mains | Where-Object {$_.ProcessId -eq $MainProcessId})}
    if($mains.Count -ne 1){throw 'Select one already running main app process; no launch or restart was attempted.'}
    $target=$mains[0]
    $creationTicks=$target.CreationDate.ToUniversalTime().Ticks
    $roots=[Collections.Generic.List[string]]::new()
    foreach($package in $packages){
        $root=Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Packages') $package.PackageFamilyName) 'LocalCache\Roaming\Codex\web\Codex\Crashpad\reports'
        if(Test-Path -LiteralPath $root -PathType Container){$roots.Add($root)}
    }
    $unpackaged=Join-Path $env:APPDATA 'Codex\web\Codex\Crashpad\reports'
    if(Test-Path -LiteralPath $unpackaged -PathType Container){$roots.Add($unpackaged)}
    $status.crashDirectoriesObserved=$roots.Count
    function Crash-Files {
        foreach($root in $roots){
            Get-ChildItem -LiteralPath $root -File | Where-Object {$_.Extension -eq '.dmp' -or $_.Name -like '*_sidecar.json'} | Select-Object -ExpandProperty FullName
        }
    }
    $baseline=@(Crash-Files)
    $newFiles=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $status.stage='observing';Save-Observation
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while($true){
        $status.observedSeconds=[int][Math]::Floor($timer.Elapsed.TotalSeconds)
        $current=Get-CimInstance Win32_Process -Filter ('ProcessId='+$target.ProcessId)
        if(-not $current -or $current.CreationDate.ToUniversalTime().Ticks -ne $creationTicks){$status.mainSurvived=$false;$status.responding=$false;$status.stage='failed';$status.reason='main-exited-or-replaced';break}
        $status.mainSurvived=$true
        $processHandle=$null
        try{
            $processHandle=Get-Process -Id $target.ProcessId
            $status.responding=$processHandle.Responding
            $status.responseSampleCount++
            if(-not $status.responding){$status.unresponsiveSampleCount++}
            foreach($file in @(Crash-Files | Where-Object {$baseline -notcontains $_})){$null=$newFiles.Add($file)}
            $status.newCrashFileCount=$newFiles.Count
        }catch{$status.samplingErrorCount++}finally{if($processHandle){$processHandle.Dispose()}}
        $status.observedSeconds=[int][Math]::Floor($timer.Elapsed.TotalSeconds)
        if($status.observedSeconds -ge $ObservationSeconds){
            $status.stage=$(if($status.crashDirectoriesObserved -gt 0 -and $status.newCrashFileCount -eq 0 -and $status.samplingErrorCount -eq 0 -and $status.unresponsiveSampleCount -eq 0 -and $status.responding){'checks-passed'}else{'partial'})
            if($status.newCrashFileCount -gt 0){$status.reason='new-crash-metadata-needs-attribution'}
            elseif($status.unresponsiveSampleCount -gt 0){$status.reason='unresponsive-samples'}
            break
        }
        Save-Observation
        Start-Sleep -Seconds ([Math]::Min(5,[Math]::Max(1,$ObservationSeconds-$status.observedSeconds)))
    }
    Save-Observation
    $status | ConvertTo-Json -Depth 5
}catch{
    $status.stage='observer-error';$status.exceptionType=$_.Exception.GetType().Name
    try{Save-Observation}catch{}
    $status | ConvertTo-Json -Depth 5
}
