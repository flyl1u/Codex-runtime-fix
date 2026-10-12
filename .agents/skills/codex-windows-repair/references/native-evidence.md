# Other native failures

Match crash time and affected installed executable, not only its display name. Application Error, WER and Crashpad metadata provide different evidence; missing events do not prove absence of a crash.

Keep local dumps private. Analyze exception stream, process/thread role, matching module identity and real unwind information. Arbitrary pointer matches are not a call stack. An offset belongs to an exact build, not a universal signature.

`0xc0000005` is an access violation, not a root cause. Microsoft system DLLs at the fault may be victims of prior corruption. Do not replace DLLs or disable security software from that observation alone.

Route a demonstrated deployment/rendering path to its specific branch. For an apparent app/native failure, choose supported update or a mitigation of a demonstrated trigger within scope, then prepare a precise maintainer summary. State unavailable HRESULT/symbols/reproducer rather than guessing.

If the app cannot remain open, use a permitted independent local environment or prepare the evidence and request specific missing access. Do not upload a dump to an online analyzer or public repo by default.

Source: [Microsoft crash investigation](https://learn.microsoft.com/en-us/troubleshoot/windows-server/performance/troubleshoot-application-service-crashing-behavior).
