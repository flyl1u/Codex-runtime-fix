# Verification for contributors

Run helper regression checks on Windows with PowerShell 5.1 or a compatible host:

```powershell
& .\tests\Test-Helpers.ps1 -OutputDirectory .\.runs\helper-tests
```

The suite writes synthetic snapshots and observer results to a new directory beneath the specified output directory. It tests preview evidence guards, health-state decisions with a mocked DISM operation, the complete observer against mocked APIs, and application-event parsing with varied payloads. It never performs live system repair, launches/restarts Codex, or changes a profile. Mocked success is not a successful repair on a real Windows device.

`fixtures/agent-cases.json` supplies independent synthetic troubleshooting tasks for a Codex behavior evaluation. Give another Codex instance the Skill and these inputs, restrict it to the fixtures, and review whether its actions follow the evidence. Relevant checks include distinguishing child/tool failures from main-process exit, avoiding repairs based only on an orphan entry or a single memory sample, preserving data, and providing workload acceptance.

Separately validate the Skill structure, parse all PowerShell sources, and run the collector in read-only mode. A short live observer check validates the helper's operation only; report its actual duration. Broad real-device repair coverage must come from reviewed cases, including unsuccessful interventions.
