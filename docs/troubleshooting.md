# Agent workflow entry

主要执行者是拥有本机工具访问的 Codex。用户在项目目录中说明症状并授权诊断或修复，Codex 按 [AGENTS.md](../AGENTS.md) 加载 [Skill](../.agents/skills/codex-windows-repair/SKILL.md)。

先区分退出、无响应、子进程重启和工具失败，再按 [故障目录](../.agents/skills/codex-windows-repair/references/fault-map.md) 选择有证据的路径。触发条件成立才执行适用步骤；真实案例是其中一条参考。

记录目标、备份/恢复方法，使用已有授权完成处理，权限不足时说明具体阻碍。之后按 [验收方法](../.agents/skills/codex-windows-repair/references/verification.md) 重做原任务并记录实际结果。

没有本机访问的 Agent 可以分析脱敏材料，不能声称已修复这台电脑。
