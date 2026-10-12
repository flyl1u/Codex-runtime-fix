---
name: codex-windows-repair
description: "Diagnose and repair Windows Codex desktop crashes, launch failures, hangs, or local tool startup errors with evidence-driven interventions and verification. Applies to the Codex desktop environment, not bugs in arbitrary code written by Codex or general Windows cleanup."
---

# Codex Windows Repair

Use actual access to the affected Windows machine. Determine the current app version, execution environment, symptom and authorization; never reuse a historical package version or private profile path as a default.

## Establish what failed

Run [the collector](scripts/Collect-CodexDiagnostics.ps1) for a baseline. Add `-IncludeLogMarkers` when current-process markers help. Correlate the failure time with process evidence, application events and Crashpad metadata. A live main process plus a failed command is a tool failure; a GPU child restart alone does not establish a main-process crash. Missing events, paths or markers are missing evidence, not proof of health or corruption.

Resolve helper paths against this Skill directory. Shell examples in branch references assume it is the working directory; when running elsewhere, invoke the resolved absolute script path.

Persist private before/after summaries, interventions and verification requirements in an ignored local run directory. Each intervention records trigger evidence, exact target, backup/recovery method, actual result and a test that could falsify its usefulness. Keep raw logs, dumps, credentials and databases out of public cases.

## Select an action

Read [fault-map.md](references/fault-map.md), then only the selected branch reference. The case-validated deployment branch is one option. Generic exception codes, old registry entries or a missing runtime package alone do not select it.

Use the least disruptive action that tests the hypothesis. In the user's already authorized repair scope, complete applicable steps without repeating the same permission question. Before a write, confirm existing authorization and actual tool access cover that target. If not, prepare a concrete pending action and explain the actual blocker. This skill grants no additional access.

Back up reversible changes. Preserve `.codex` authentication/chat databases, projects, cookies and persistent browser storage by default. Persistent-data corruption needs a specific recovery plan, not an indiscriminate profile erase.

A repeated unchanged failure calls for new evidence or a different hypothesis. Roll back non-improving reversible experiments before testing another variable. System repair is not automatically reversible: preserve its result and do not claim an inverse operation was performed.

## Restart and verify

Before a host restart, save run state and prepare a permitted independent observer or usable alternate local agent environment. Tell the user about the planned restart. Independent helpers must not bypass execution restrictions. Use the normal application entry and confirm the same effective profile; direct EXE launch may change package identity and invalidate a comparison.

Read [verification.md](references/verification.md). The [observer](scripts/Watch-CodexStability.ps1) records process exits, new crash metadata and incomplete coverage. It does not launch Codex, reproduce a workload or fix anything. A sampler error is not an app crash.

Report what improved, actual checks/duration, original workload reproduced, remaining uncertainties and recovery of reversible changes. Use `observed-improvement`, `not-reproduced`, `failed`, or `blocked` in case summaries rather than claiming a permanent fix. Publication requires reviewed summaries and user authorization.
