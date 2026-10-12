# Resources, integrations and tool environment

## Resources

Start from memory and relevant-volume summaries, then compare samples during the failing workload. Add process working set/private bytes where available. A memory reading from a different time cannot prove an out-of-memory failure. If storage errors point to another explicit project/temp volume, inspect that target rather than cleaning unrelated data.

Distinguish reproducible growth from ordinary cached memory. Choose supported workload reduction or specific storage recovery only after identifying the resource and scope; don't terminate other apps or delete files solely to improve a metric. Validate the same workload and pressure before/after. This path awaits real repair cases.

## Integrations

Find a reproducible relationship between one integration and the failure. A tool timeout is different from main-process exit. Use available supported controls to inspect and, when authorized, isolate one implicated integration. A tool requiring an explicit uninstall request still requires that request; generic repair scope is not an uninstall instruction.

Retain previous configuration and undo unsuccessful isolation. Do not bulk uninstall plugins or edit arbitrary integration databases. Plugin presence or the last log line is insufficient causation evidence.

## Tool, permission, authentication and network failures

When the app stays alive and a command reports `setup refresh had errors`, denied access, TLS or auth failure, test a basic permitted local command and inspect the actual tool context. Reconnect a stale tool/session via supported controls. A prior UI permission selection may not match the current execution context after restart.

Investigate connectivity only when request failures support it. Preserve TLS validation and security protections; use supported sign-in/connection recovery instead of deleting credentials. Do not print tokens, auth files or transcripts.

An explicit policy rejection stops that action. Do not switch to another shell, WMI, helper, API or registry import to evade it. Prepare a concrete allowed alternative and describe the actual blocker, retaining earlier authorization without repeating the same question.

Verification is a successful permitted command/connection and resumed task alongside a live app. It does not prove an unrelated native crash was fixed.

Source: [OpenAI stuck-state troubleshooting](https://learn.chatgpt.com/docs/reference/troubleshooting).
