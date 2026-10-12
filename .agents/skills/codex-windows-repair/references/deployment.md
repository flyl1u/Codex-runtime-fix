# Runtime deployment and app installation

Select this path when the current runtime operation correlates with a failure, relevant AppX errors, or a matching native deployment stack. A missing framework alone is not evidence of damage. Verify the runtime expected by the current app; never install this case's historical version by default.

The real case had a native deployment null-pointer fault, standard install errors `0x80073CF6` / `0x8007007E`, repairable component storage, then successful installation of the same signed package after DISM repair. The old registry entry remained present; deleting it was not a necessary demonstrated fix. Later user feedback reported recovery, with an app update also occurring.

## Component storage

Use [Restore-WindowsComponentStore.ps1](../scripts/Restore-WindowsComponentStore.ps1) with a fresh collector JSON via `-EvidencePath` only when deployment evidence supports investigating Windows health. The helper checks current build/app consistency, scans health, and restores only `Repairable` storage under existing administrator access. It does not restart automatically.

`-WhatIf` validates snapshot shape, freshness and recent failure evidence, then emits a plan. It does not run the live machine/version/admin preflight or scan Windows health. A successful preview does not prove repair is applicable or possible. In a host without native Appx/Dism cmdlets, use Windows PowerShell 5.1 within the same permitted scope.

The helper accepts recent AppX failure events, not every form of deployment evidence. If a matching native stack selects this branch but the collector has no usable AppX events, do not fabricate a snapshot or disable the guard. Correlate the actual operation's time/package/activity with a narrower permitted Windows event query; the collector's event limit may omit it. If events remain unavailable, record that the helper is inapplicable. An independently justified, authorized component-health scan through supported Windows tools is still a diagnostic option; document its actual evidence and use restoration only for a genuinely repairable state. A host/tool policy rejection continues to block the operation.

```powershell
& .\scripts\Restore-WindowsComponentStore.ps1 -EvidencePath '<private-before.json>' -WhatIf
# Under authorized live repair, execute without -WhatIf.
```

A failed scan, unavailable source or non-repairable state is not a successful repair. Preserve the result and inspect that failure. A healthy scan does not prove app deployment is healthy. Avoid unchanged retries or altering TLS/update protections.

Prefer the app's normal dependency retry when possible. Standard `Add-AppxPackage` may distinguish native app handling from Windows deployment. Before a manual install, verify source, current expected publisher/version/architecture, signature and SHA256. A valid signature alone establishes neither source trust nor compatibility. No installer is distributed by this project.

## Installed app

For abnormal package status or missing files, inspect the current manifest and supported distribution's Repair/update route. Windows Settings Repair preserves app data; Reset removes it and needs a different recovery decision. Do not batch re-register all Windows apps or remove other users' packages.

Do not change build flavor or state namespace merely to suppress a symptom. Verify normal startup, relevant dependency state, original workload and stability after the targeted change. Retain reboot requirements without restarting automatically. DISM repair has no automatic inverse in this project.

Sources: [Microsoft image repair](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/repair-a-windows-image), [Repair-WindowsImage](https://learn.microsoft.com/en-us/powershell/module/dism/repair-windowsimage), [Add-AppxPackage](https://learn.microsoft.com/en-us/powershell/module/appx/add-appxpackage), [signature inspection](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature), [Repair vs Reset](https://learn.microsoft.com/en-us/windows/msix/desktop/managing-your-msix-reset-and-repair).
