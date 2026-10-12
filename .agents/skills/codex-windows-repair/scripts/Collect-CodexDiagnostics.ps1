#Requires -Version 5.1
<#
.SYNOPSIS
Emits an allowlisted local diagnostic summary without changing app or system state.
.PARAMETER IncludeLogMarkers
Reads current app-process logs locally and returns only predefined marker names.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 168)][int]$LookbackHours = 24,
    [switch]$IncludeLogMarkers
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This collector requires Windows.' }
$cutoff = (Get-Date).AddHours(-$LookbackHours)
$collectionErrors = [Collections.Generic.List[object]]::new()

function Record-CheckError {
    param([string]$Check, [Exception]$Exception)
    $collectionErrors.Add([pscustomobject]@{check = $Check; exceptionType = $Exception.GetType().Name})
}

function Read-SharedText {
    param([string]$Path)
    $stream = $null
    $reader = $null
    try {
        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
        $reader = [IO.StreamReader]::new($stream)
        $reader.ReadToEnd()
    } finally {
        if ($reader) { $reader.Dispose() } elseif ($stream) { $stream.Dispose() }
    }
}

$report = [ordered]@{
    schemaVersion = '1.1'
    collectedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    lookbackHours = $LookbackHours
    windows = $null
    resources = [ordered]@{totalPhysicalMemoryMB = $null; freePhysicalMemoryMB = $null; volumes = @()}
    appPackages = @()
    primaryRuntimePackages = @()
    processes = [ordered]@{matchedCount = 0; main = @()}
    crashFileMetadata = @()
    appxEventScanLimit = 200
    appxEvents = @()
    applicationEvents = @()
    deploymentExtensions = @()
    runtimeLogMarkers = [ordered]@{requested = [bool]$IncludeLogMarkers; scannedFiles = 0; matchedMarkers = @()}
    collectionErrors = @()
}

try {
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $report.windows = [ordered]@{version = $osInfo.Version; build = $osInfo.BuildNumber; architecture = $osInfo.OSArchitecture}
    $report.resources.totalPhysicalMemoryMB = [math]::Round($osInfo.TotalVisibleMemorySize / 1024, 1)
    $report.resources.freePhysicalMemoryMB = [math]::Round($osInfo.FreePhysicalMemory / 1024, 1)
} catch { Record-CheckError 'windows-version' $_.Exception }

try {
    $volumeRoles = @{}
    foreach ($location in @(@{role='system';path=$env:WINDIR}, @{role='profile';path=$env:LOCALAPPDATA})) {
        $root = [IO.Path]::GetPathRoot($location.path)
        if ($root -match '^[A-Za-z]:\\$') {
            $drive = $root.TrimEnd('\')
            if (-not $volumeRoles.ContainsKey($drive)) { $volumeRoles[$drive] = [Collections.Generic.List[string]]::new() }
            $volumeRoles[$drive].Add($location.role)
        }
    }
    $report.resources.volumes = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Where-Object {$volumeRoles.ContainsKey($_.DeviceID)} | ForEach-Object {
        [pscustomobject]@{roles=@($volumeRoles[$_.DeviceID].ToArray()); totalGB=[math]::Round($_.Size/1GB,1); freeGB=[math]::Round($_.FreeSpace/1GB,1)}
    })
} catch { Record-CheckError 'resource-volumes' $_.Exception }

$appPackages = @()
try {
    $appPackages = @(Get-AppxPackage -Name OpenAI.Codex)
    $report.appPackages = @($appPackages | ForEach-Object {
        [pscustomobject]@{name = $_.Name; version = [string]$_.Version; status = [string]$_.Status}
    })
    $report.primaryRuntimePackages = @(Get-AppxPackage -Name 'OpenAI.CodexPrimaryRuntime*' | ForEach-Object {
        [pscustomobject]@{name = $_.Name; version = [string]$_.Version; status = [string]$_.Status}
    })
} catch { Record-CheckError 'app-packages' $_.Exception }

$mainIds = @()
try {
    $candidateProcesses = @(Get-CimInstance Win32_Process -Filter "Name='ChatGPT.exe' OR Name='Codex.exe'")
    $appProcesses = @($candidateProcesses | Where-Object {
        $candidate = $_
        @($appPackages | Where-Object {
            $_.InstallLocation -and $candidate.ExecutablePath -and $candidate.ExecutablePath.StartsWith($_.InstallLocation.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
        }).Count -gt 0
    })
    $report.processes.matchedCount = $appProcesses.Count
    $mainProcesses = @($appProcesses | Where-Object { $_.CommandLine -notmatch '--type=' })
    $mainIds = @($mainProcesses | Select-Object -ExpandProperty ProcessId)
    $report.processes.main = @($mainProcesses | ForEach-Object {
        $processHandle = Get-Process -Id $_.ProcessId
        try {
        [pscustomobject]@{
            executableName = $_.Name
            uptimeSeconds = [int]((Get-Date) - $_.CreationDate).TotalSeconds
            responding = $processHandle.Responding
            workingSetMB = [math]::Round($processHandle.WorkingSet64/1MB,1)
            privateBytesMB = [math]::Round($processHandle.PrivateMemorySize64/1MB,1)
            handleCount = $processHandle.HandleCount
        }
        } finally { $processHandle.Dispose() }
    })
} catch { Record-CheckError 'app-processes' $_.Exception }

$profiles = [Collections.Generic.List[object]]::new()
foreach ($package in $appPackages) {
    $cache = Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Packages') $package.PackageFamilyName) 'LocalCache'
    $profiles.Add([pscustomobject]@{scope = 'packaged'; crashPath = (Join-Path $cache 'Roaming\Codex\web\Codex\Crashpad\reports'); logPath = (Join-Path $cache 'Local\Codex\Logs')})
}
$profiles.Add([pscustomobject]@{scope = 'unpackaged'; crashPath = (Join-Path $env:APPDATA 'Codex\web\Codex\Crashpad\reports'); logPath = (Join-Path $env:LOCALAPPDATA 'Codex\Logs')})

foreach ($profile in $profiles) {
    try {
        $directoryExists = Test-Path -LiteralPath $profile.crashPath -PathType Container
        $recent = @()
        if ($directoryExists) {
            $recent = @(Get-ChildItem -LiteralPath $profile.crashPath -File | Where-Object { $_.LastWriteTime -ge $cutoff })
        }
        $dumpFiles = @($recent | Where-Object { $_.Extension -eq '.dmp' })
        $sidecars = @($recent | Where-Object { $_.Name -like '*_sidecar.json' })
        $latest = $recent | Where-Object { $_.Extension -eq '.dmp' -or $_.Name -like '*_sidecar.json' } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        $report.crashFileMetadata += [pscustomobject]@{
            scope = $profile.scope
            directoryExists = $directoryExists
            recentDumpCount = $dumpFiles.Count
            recentSidecarCount = $sidecars.Count
            latestWriteUtc = $(if ($latest) { $latest.LastWriteTimeUtc.ToString('o') } else { $null })
        }
    } catch { Record-CheckError ('crash-metadata-' + $profile.scope) $_.Exception }
}

try {
    $events = @(Get-WinEvent -FilterHashtable @{LogName = 'Microsoft-Windows-AppXDeploymentServer/Operational'; StartTime = $cutoff} -MaxEvents 200)
    $report.appxEvents = @($events | Where-Object { $_.Message -match 'OpenAI\.Codex' } | ForEach-Object {
        [pscustomobject]@{
            timeUtc = $_.TimeCreated.ToUniversalTime().ToString('o')
            eventId = $_.Id
            level = $_.Level
            hexCodes = @([regex]::Matches($_.Message, '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value.ToUpperInvariant() } | Sort-Object -Unique)
        }
    })
} catch {
    if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { Record-CheckError 'appx-events' $_.Exception }
}

try {
    $appEvents = @(Get-WinEvent -FilterHashtable @{LogName='Application';Id=1000,1001,1002;StartTime=$cutoff} -MaxEvents 100)
    $report.applicationEvents = @($appEvents | ForEach-Object {
        $event = $_
        $message = [string]$event.Message
        $belongsToCodex = $message -match 'OpenAI\.Codex'
        foreach($package in $appPackages) {
            if($package.InstallLocation -and $message.IndexOf($package.InstallLocation,[StringComparison]::OrdinalIgnoreCase) -ge 0) { $belongsToCodex=$true }
        }
        if(-not $belongsToCodex) { return }
        $fields = @{}
        try {
            $xml = [xml]$event.ToXml()
            foreach($datum in $xml.SelectNodes('/*[local-name()="Event"]/*[local-name()="EventData"]/*[local-name()="Data"]')) {
                $key = $datum.GetAttribute('Name')
                if($key) { $fields[$key] = $datum.InnerText }
            }
        } catch { Record-CheckError 'application-event-fields' $_.Exception }
        $appName = $(if($fields.ContainsKey('AppName')){[IO.Path]::GetFileName($fields['AppName'])}else{$null})
        $moduleName = $(if($fields.ContainsKey('ModuleName')){[IO.Path]::GetFileName($fields['ModuleName'])}else{$null})
        if($appName -and $appName -notmatch '^[A-Za-z0-9_.-]{1,120}$'){$appName=$null}
        if($moduleName -and $moduleName -notmatch '^[A-Za-z0-9_.-]{1,120}$'){$moduleName=$null}
        $exceptionCode = $null
        if($fields.ContainsKey('ExceptionCode') -and $fields['ExceptionCode'] -match '^(?:0x)?([0-9A-Fa-f]{8})$'){$exceptionCode='0X'+$Matches[1].ToUpperInvariant()}
        [pscustomobject]@{timeUtc=$event.TimeCreated.ToUniversalTime().ToString('o');eventId=$event.Id;applicationName=$appName;moduleName=$moduleName;exceptionCode=$exceptionCode}
    })
} catch {
    if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { Record-CheckError 'application-events' $_.Exception }
}

$registryBase = $null
$extensionRoot = $null
try {
    $registryBase = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    $extensionRoot = $registryBase.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\UndockedDeploymentExtensionModules', $false)
    if ($extensionRoot) {
        foreach ($name in @($extensionRoot.GetSubKeyNames() | Where-Object { $_ -like 'Microsoft.WindowsAppRuntime.*' })) {
            $entry = $null
            try {
                $entry = $extensionRoot.OpenSubKey($name, $false)
                foreach ($valueName in $entry.GetValueNames()) {
                    $dllPath = $entry.GetValue($valueName)
                    if ($dllPath -is [string] -and $dllPath.EndsWith('.dll', [StringComparison]::OrdinalIgnoreCase)) {
                        $dllState = 'unknown'
                        try {
                            $null = Get-Item -LiteralPath $dllPath -Force
                            $dllState = 'exists'
                        } catch [Management.Automation.ItemNotFoundException] { $dllState = 'missing' }
                        catch { Record-CheckError 'deployment-extension-file' $_.Exception }
                        $report.deploymentExtensions += [pscustomobject]@{registrationName = $name; dllState = $dllState}
                    }
                }
            } catch { Record-CheckError 'deployment-extension-entry' $_.Exception }
            finally { if ($entry) { $entry.Dispose() } }
        }
    }
} catch { Record-CheckError 'deployment-extensions' $_.Exception }
finally {
    if ($extensionRoot) { $extensionRoot.Dispose() }
    if ($registryBase) { $registryBase.Dispose() }
}

if ($IncludeLogMarkers) {
    $knownMarkers = @('windows_primary_runtime_framework_activated', 'windows_primary_runtime_framework_ready', 'windows_primary_runtime_framework_activation_failed', 'runtimeSource=framework', 'activatedRuntimeSource=primary-framework', 'GPU process crashed', 'GPU process exited unexpectedly', 'out of memory', 'ERR_CERT_AUTHORITY_INVALID', 'TLS handshake failed', 'setup refresh had errors', 'blocked by policy', 'SQLITE_CORRUPT', 'disk full')
    $foundMarkers = [Collections.Generic.HashSet[string]]::new()
    foreach ($profile in $profiles) {
        try {
            if (-not (Test-Path -LiteralPath $profile.logPath -PathType Container)) { continue }
            $logs = @(Get-ChildItem -LiteralPath $profile.logPath -Recurse -File -Filter '*.log' | Where-Object {
                $logFile = $_
                $logFile.LastWriteTime -ge $cutoff -and $logFile.Length -le 10MB -and @($mainIds | Where-Object { $logFile.Name -match ('-' + [regex]::Escape([string]$_) + '-') }).Count -gt 0
            } | Sort-Object LastWriteTime -Descending | Select-Object -First 8)
            foreach ($logFile in $logs) {
                try {
                    $content = Read-SharedText $logFile.FullName
                    $report.runtimeLogMarkers.scannedFiles++
                    foreach ($marker in $knownMarkers) {
                        if ($content.IndexOf($marker, [StringComparison]::Ordinal) -ge 0) { $null = $foundMarkers.Add($marker) }
                    }
                    $content = $null
                } catch { Record-CheckError 'runtime-log-read' $_.Exception }
            }
        } catch { Record-CheckError ('runtime-log-scan-' + $profile.scope) $_.Exception }
    }
    $report.runtimeLogMarkers.matchedMarkers = @($foundMarkers | Sort-Object)
}

$report.collectionErrors = @($collectionErrors.ToArray())
$report | ConvertTo-Json -Depth 8
