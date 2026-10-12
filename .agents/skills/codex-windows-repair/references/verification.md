# Verification and run record

Before changing behavior, record symptom, current app version, effective execution/profile, reproduction, time-to-failure, crash metadata baseline and selected evidence. Note app/Windows updates during the investigation.

Each intervention records trigger, target, backup/recovery method, actual result, before/after checks and uncertainties. Keep private summaries in an ignored local directory so another agent can resume after a host restart. Exclude credentials and dump contents.

Run [Watch-CodexStability.ps1](../scripts/Watch-CodexStability.ps1) for an already running target, with a private `-OutputPath`. Use `-MainProcessId` for multiple instances. Select a duration covering the original failure interval; 600 seconds is a default, not a guarantee.

```powershell
& .\scripts\Watch-CodexStability.ps1 -ObservationSeconds 600 -OutputPath '<private-verification.json>'
```

The observer does not restart the host or execute workloads. For a restart, first prepare permitted independent observation and recovery state, and observe the newly started instance.

Acceptance also needs reproduction of the original workload and improvement of the branch-specific check. Process survival is insufficient for a workload-specific failure. Observer outcomes are:

- `checks-passed`: selected interval elapsed, target survived, all response samples were normal, no new crash metadata or sampling errors. Still requires workload acceptance by Codex.
- `partial`: target survived but coverage was incomplete, unresponsive samples occurred, or new crash metadata needs attribution.
- `failed`: target main process exited or was replaced.
- `observer-error`: observation could not start or continue, including output-write failure; separate this from an application crash.

Response sampling is periodic; it can miss a short hang between samples. `Responding` also does not establish tool/task progress. A hang or integration case needs explicit observations during its trigger and a successful original workload. Match new Crashpad metadata to the instance/time/process role using private evidence before calling it a main-process crash. The helper scans known packaged and unpackaged directories; an unrelated instance or GPU child may produce a new file.

Start observation before the trigger and allow the workload to run during the selected interval. The helper summarizes counts; when attribution or hang timing matters, also retain a private file/time baseline and trigger/response/progress timings. File timestamps alone provide candidates, not proof of process identity. Record missing baselines or timing instead of inventing them.

Check process creation time as well as PID. Read active logs with sharing that permits concurrent writes. A missing optional marker is not automatic activation failure. The historical case's early observer stopped on a log-sharing error; it was not a passed ten-minute test.

Public status uses `observed-improvement`, `not-reproduced`, `failed`, or `blocked`, plus actual workload and observation duration.
