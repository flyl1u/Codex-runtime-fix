# Evidence routing

Classify the symptom before choosing a repair. Paths may overlap; keep ranked hypotheses and test one change at a time. Diagnostic coverage is not a success-rate claim.

| Branch | Supporting observations | Not sufficient alone | Next reference/check |
| --- | --- | --- | --- |
| deployment | Correlated runtime operation, AppX failure or native deployment stack | Missing framework or orphan registry entry | [deployment.md](deployment.md): standard deployment and system health |
| app-installation | Abnormal package status, missing installed files, launch failure | Older version number | [deployment.md](deployment.md): supported Repair/current-channel update |
| rendering | Correlated graphics errors and reproducible rendering trigger | One GPU child exit | [rendering-profile.md](rendering-profile.md): supported graphics comparison |
| profile-cache | Cache-specific evidence or controlled isolation changes reproduction | Any Cache directory or generic access violation | [rendering-profile.md](rendering-profile.md): active profile and bounded backup |
| resources | Repeated memory/storage pressure during the failing workload | One low-memory sample | [resources-integrations.md](resources-integrations.md): time series and correlation |
| integrations | One integration consistently precedes failure | Slow tool call or plugin list | [resources-integrations.md](resources-integrations.md): supported single-integration isolation |
| tool-environment | Main app alive with startup/permission/TLS error | “Task stopped” without process evidence | [resources-integrations.md](resources-integrations.md): basic command and actual execution context |
| native-unknown | Matching main-process crash event or dump | ntdll/kernelbase or access violation alone | [native-evidence.md](native-evidence.md): exact exception and module match |

Deployment has a real recovery case in this project. Standard Windows Repair/health operations have Microsoft documentation. The remaining paths are diagnostic guidance awaiting broader real-case validation; expand them using both successful and unsuccessful cases.
