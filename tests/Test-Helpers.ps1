#Requires -Version 5.1
<#
Runs previews and mocked decisions. Never calls live DISM, restarts Codex,
or changes a profile. Writes only to a new directory beneath OutputDirectory.
#>
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$skillRoot=Join-Path $PSScriptRoot '..\.agents\skills\codex-windows-repair'
$testRoot=Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ('run-'+[Guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($testRoot)
$results=[Collections.Generic.List[object]]::new()
function Assert-Result {
    param([string]$Name,[bool]$Condition)
    $results.Add([pscustomobject]@{name=$Name;passed=$Condition})
    if(-not $Condition){throw ('Test failed: '+$Name)}
}

$repairScript=Join-Path $skillRoot 'scripts\Restore-WindowsComponentStore.ps1'
$observerScript=Join-Path $skillRoot 'scripts\Watch-CodexStability.ps1'
$collectorScript=Join-Path $skillRoot 'scripts\Collect-CodexDiagnostics.ps1'
Get-ChildItem -LiteralPath (Join-Path $skillRoot 'scripts') -Filter '*.ps1' -File | ForEach-Object {
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)
    Assert-Result ('syntax-'+$_.Name) ($errors.Count -eq 0)
}

function New-Evidence {
    [ordered]@{
        schemaVersion='1.1';collectedAtUtc=[DateTimeOffset]::UtcNow.ToString('o')
        windows=@{build='synthetic'};appPackages=@(@{name='OpenAI.Codex';version='0.0.0.0'})
        appxEvents=@(@{timeUtc=[DateTimeOffset]::UtcNow.ToString('o');hexCodes=@('0x80073CF6')})
    }
}
function Run-Preview {
    param($Evidence,[string]$Name)
    $path=Join-Path $testRoot ($Name+'.json')
    [IO.File]::WriteAllText($path,($Evidence | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    & $repairScript -EvidencePath $path -WhatIf | ConvertFrom-Json
}
$preview=Run-Preview (New-Evidence) 'valid-evidence'
Assert-Result 'preview-does-not-repair-or-claim-live-preflight' ($preview.stage -eq 'planned' -and -not $preview.mutationPerformed -and -not $preview.livePreflightPerformed -and -not $preview.automaticallyRestart)
foreach($kind in @('stale-snapshot','future-snapshot','old-event','future-event','no-failure','missing-schema')) {
    $evidence=New-Evidence
    switch($kind){
        'stale-snapshot'{$evidence.collectedAtUtc=[DateTimeOffset]::UtcNow.AddDays(-2).ToString('o')}
        'future-snapshot'{$evidence.collectedAtUtc=[DateTimeOffset]::UtcNow.AddHours(1).ToString('o')}
        'old-event'{$evidence.appxEvents[0].timeUtc=[DateTimeOffset]::UtcNow.AddDays(-2).ToString('o')}
        'future-event'{$evidence.appxEvents[0].timeUtc=[DateTimeOffset]::UtcNow.AddHours(1).ToString('o')}
        'no-failure'{$evidence.appxEvents[0].hexCodes=@('0x00000000')}
        'missing-schema'{$evidence.Remove('schemaVersion')}
    }
    $rejected=$false
    try{$null=Run-Preview $evidence $kind}catch{$rejected=$true}
    Assert-Result ('preview-rejects-'+$kind) $rejected
}

# Execute the actual health decision block with a mocked restore operation.
# This tests decisions; it does not test admin preflight or Windows servicing.
$tokens=$null;$errors=$null
$repairAst=[Management.Automation.Language.Parser]::ParseFile($repairScript,[ref]$tokens,[ref]$errors)
$healthSwitch=@($repairAst.FindAll({param($node) $node -is [Management.Automation.Language.SwitchStatementAst]},$true))
Assert-Result 'health-decision-available' ($healthSwitch.Count -eq 1)
$decision=[scriptblock]::Create($healthSwitch[0].Extent.Text)
function Test-HealthDecision {
    param([string]$Before,[string]$After,[string]$ExpectedStage,[int]$ExpectedRestoreCalls)
    $healthState=$Before;$simulatedAfter=$After
    $calls=[Collections.Generic.List[object]]::new()
    $result=[ordered]@{stage='scanned';healthBefore=$Before;healthAfter=$Before;restorationPerformed=$false;automaticallyRestart=$false;restartRequirement=$null}
    function Repair-WindowsImage {
        [CmdletBinding()]
        param([switch]$Online,[switch]$RestoreHealth,[switch]$NoRestart)
        if(-not ($Online -and $RestoreHealth -and $NoRestart)){throw 'Unexpected servicing request in simulation.'}
        $calls.Add(@{online=$true;restore=$true;noRestart=$true})
        [pscustomobject]@{ImageHealthState=$simulatedAfter;RestartNeeded=$false}
    }
    . $decision
    $valid=$result.stage -eq $ExpectedStage -and $calls.Count -eq $ExpectedRestoreCalls -and -not $result.automaticallyRestart
    if($ExpectedRestoreCalls){$valid=$valid -and $result.restartRequirement -is [bool] -and $result.restartRequirement -eq $false}
    Assert-Result ('health-'+$Before+'-'+$After) $valid
}
Test-HealthDecision 'Healthy' 'Healthy' 'healthy-no-restoration-needed' 0
Test-HealthDecision 'Repairable' 'Healthy' 'restored' 1
Test-HealthDecision 'Repairable' 'NonRepairable' 'restoration-needs-investigation' 1
Test-HealthDecision 'NonRepairable' 'NonRepairable' 'health-needs-investigation' 0

# Run the complete observer against fake process and filesystem APIs.
function Test-Observer {
    param([string]$Mode,[string]$ExpectedStage)
    $observerFixture=[pscustomobject]@{Mode=$Mode;Queries=0;Creation=[DateTime]::UtcNow.AddMinutes(-5);Install=(Join-Path $testRoot 'fake-app')}
    function Get-AppxPackage { param($Name) [pscustomobject]@{InstallLocation=$observerFixture.Install;PackageFamilyName='Synthetic.Codex_Test'} }
    function Get-CimInstance {
        param($ClassName,$Filter)
        if($Filter -like 'Name=*'){
            if($observerFixture.Mode -eq 'selection-error'){return}
        }else{
            $observerFixture.Queries++
            if($observerFixture.Mode -eq 'exit' -and $observerFixture.Queries -gt 1){return}
        }
        $creation=$observerFixture.Creation
        if($observerFixture.Mode -eq 'pid-reuse' -and $observerFixture.Queries -gt 1){$creation=$creation.AddMinutes(1)}
        [pscustomobject]@{ProcessId=4242;CreationDate=$creation;CommandLine='synthetic';ExecutablePath=(Join-Path $observerFixture.Install 'Codex.exe')}
    }
    function Test-Path { param($LiteralPath,$PathType) $observerFixture.Mode -ne 'missing-crash-path' }
    function Get-Process {
        param($Id)
        if($observerFixture.Mode -eq 'sample-error'){throw 'Synthetic sampling failure.'}
        $responding=-not ($observerFixture.Mode -eq 'transient-unresponsive' -and $observerFixture.Queries -eq 1)
        $handle=[pscustomobject]@{Responding=$responding}
        $handle | Add-Member -MemberType ScriptMethod -Name Dispose -Value {}
        $handle
    }
    function Get-ChildItem {
        param($LiteralPath,[switch]$File)
        if($observerFixture.Mode -eq 'new-crash' -and $observerFixture.Queries -gt 0){
            [pscustomobject]@{Name='synthetic.dmp';Extension='.dmp';FullName=(Join-Path $LiteralPath 'synthetic.dmp')}
        }
    }
    $observed=& $observerScript -ObservationSeconds 1 -OutputPath (Join-Path $testRoot ('observer-'+$Mode+'.json')) | ConvertFrom-Json
    $valid=$observed.stage -eq $ExpectedStage -and -not $observed.originalWorkloadVerified
    if($Mode -in @('exit','pid-reuse')){$valid=$valid -and -not $observed.mainSurvived -and $observed.reason -eq 'main-exited-or-replaced' -and $observed.observedSeconds -ge 1}
    if($Mode -eq 'sample-error'){$valid=$valid -and $observed.samplingErrorCount -gt 0}
    if($Mode -eq 'transient-unresponsive'){$valid=$valid -and $observed.responding -and $observed.unresponsiveSampleCount -gt 0 -and $observed.reason -eq 'unresponsive-samples'}
    if($Mode -eq 'new-crash'){$valid=$valid -and $observed.mainSurvived -and $observed.newCrashFileCount -gt 0 -and $observed.reason -eq 'new-crash-metadata-needs-attribution'}
    Assert-Result ('observer-'+$Mode) $valid
}
Test-Observer 'stable' 'checks-passed'
Test-Observer 'exit' 'failed'
Test-Observer 'pid-reuse' 'failed'
Test-Observer 'sample-error' 'partial'
Test-Observer 'missing-crash-path' 'partial'
Test-Observer 'transient-unresponsive' 'partial'
Test-Observer 'new-crash' 'partial'
Test-Observer 'selection-error' 'observer-error'

# Feed varied, synthetic Application-event payloads into the actual parsing block.
$collectorAst=[Management.Automation.Language.Parser]::ParseFile($collectorScript,[ref]$tokens,[ref]$errors)
$eventBlock=@($collectorAst.FindAll({param($node) $node -is [Management.Automation.Language.TryStatementAst] -and $node.Extent.Text.Contains('$report.applicationEvents =')},$true))
Assert-Result 'application-event-parser-available' ($eventBlock.Count -eq 1)
$appPackages=@([pscustomobject]@{InstallLocation='C:\FixtureApps\OpenAI.Codex_Synthetic'})
$cutoff=(Get-Date).AddDays(-1)
$report=[ordered]@{applicationEvents=@()}
$collectionErrors=[Collections.Generic.List[object]]::new()
function Record-CheckError { param([string]$Check,[Exception]$Exception) $collectionErrors.Add([pscustomobject]@{check=$Check;exceptionType=$Exception.GetType().Name}) }
function New-TestEvent {
    param([int]$Id,[string]$Message,[string]$Xml)
    $item=[pscustomobject]@{Id=$Id;TimeCreated=(Get-Date);Message=$Message;RawXml=$Xml}
    $item | Add-Member -MemberType ScriptMethod -Name ToXml -Value {$this.RawXml}
    $item
}
$eventFixtures=@(
    (New-TestEvent 1000 'Unrelated application' '<broken'),
    (New-TestEvent 1000 'OpenAI.Codex synthetic failure' '<Event xmlns="urn:fixture"><EventData><Data Name="AppName">C:\Users\SyntheticPrivate\Codex.exe</Data><Data Name="ModuleName">C:\FixtureApps\windows-updater.node</Data><Data Name="ExceptionCode">c0000005</Data></EventData></Event>'),
    (New-TestEvent 1001 'OpenAI.Codex synthetic report' '<Event><UserData /></Event>'),
    (New-TestEvent 1002 'OpenAI.Codex synthetic malformed report' '<broken')
)
function Get-WinEvent { param($FilterHashtable,$MaxEvents) $eventFixtures }
. ([scriptblock]::Create($eventBlock[0].Extent.Text))
Assert-Result 'event-filter-isolates-failed-payload-and-preserves-other-events' ($report.applicationEvents.Count -eq 3 -and $collectionErrors.Count -eq 1)
$parsed=@($report.applicationEvents | Where-Object {$_.exceptionCode -eq '0XC0000005'})
Assert-Result 'event-fields-allowlisted' ($parsed.Count -eq 1 -and $parsed[0].applicationName -eq 'Codex.exe' -and $parsed[0].moduleName -eq 'windows-updater.node' -and ($report | ConvertTo-Json -Depth 6) -notmatch 'SyntheticPrivate|RawXml|fixture failure')

$summary=[ordered]@{mode='previews-and-mocks';liveSystemRepairPerformed=$false;passed=$results.Count;results=$results.ToArray()}
[IO.File]::WriteAllText((Join-Path $testRoot 'results.json'),($summary | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
$summary | ConvertTo-Json -Depth 6
