#Requires -Version 5.1
[CmdletBinding()]
param([ValidateRange(1,168)][int]$LookbackHours=24,[switch]$IncludeLogMarkers)
& (Join-Path $PSScriptRoot '..\.agents\skills\codex-windows-repair\scripts\Collect-CodexDiagnostics.ps1') -LookbackHours $LookbackHours -IncludeLogMarkers:$IncludeLogMarkers
