# 上游故障摘要草稿

标题建议：Windows Primary Runtime deployment failure leads to a native null-pointer crash

Affected observed version: Codex `26.1002.52244` / build `13536`; Windows app package `26.1002.7124.0`, x64. This report describes a historical local observation; the current user later reported recovery and also received an app update.

A local browser-process minidump showed `0xc0000005`, a read from address zero, at `windows-updater.node+0x1a789`, on a libuv worker thread. PE unwind analysis of the matching signed module yielded the relevant chain `+0x1a789 → +0x24e41 → +0x2a7ee`. Interface and call-site analysis associated this path with `IPackageManager9.AddPackageByUriAsync` for a Primary Runtime framework installation. The captured operation pointer was null; the exact preceding HRESULT was not established.

Independent installation of the same signed runtime package failed with `0x80073CF6`, inner error `0x8007007E`. After DISM successfully repaired the component store, standard installation of that same package succeeded and its status became `Ok`.

Suggested engineering investigation: verify HRESULT and operation-pointer handling around deployment initiation and asynchronous status access, and return a recoverable installation error when Windows deployment fails. This is a request to investigate a failure path, not a claim that an independently reviewed source-level patch is available.

The full dump and application binaries are intentionally not distributed. There is no public minimal reproducer yet. Relevant interface definition: [Microsoft Windows SDK declaration](https://github.com/microsoft/win32metadata/blob/main/generation/WinSDK/RecompiledIdlHeaders/winrt/windows.management.deployment.h).

This summary is published in this community repository. It has not been submitted to OpenAI or Microsoft.
