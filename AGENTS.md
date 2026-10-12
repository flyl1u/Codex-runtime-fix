# Agent entrypoint

When the user asks to diagnose or repair Windows Codex desktop behavior, read `.agents/skills/codex-windows-repair/SKILL.md` and follow the matching evidence path. The user supplies symptoms and scope; loading this repository does not authorize changes by itself.

For project development or review, use fixtures, `-WhatIf`, and read-only checks. Do not perform live system repair, restart the host, alter app profiles, or install packages as a development side effect.

Store private runs under `.runs/<case-id>/` or another explicitly chosen local location. Public cases contain reviewed summaries only. Distinguish facts, hypotheses, diagnostic coverage, and verified outcomes.

Within existing repair authorization, complete evidence-supported actions without repetitive confirmation. Check actual tool permissions. A policy rejection is a stop for that action, not a reason to switch tools to bypass it.
