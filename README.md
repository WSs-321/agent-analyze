# agent-analyze

学习路线智能分析 Agent。每日定时检测目标仓库的学习进度，自动提交 Issue。

## 职责

- 定时拉取目标仓库最新代码
- 解析学习计划（timetable）对比实际完成进度
- 检测到未完成的 Day 时自动创建 Issue
- **只创建 Issue，不修改任何代码**

## 目标仓库配置

编辑 `targets/` 目录下的 `.yaml` 文件，每个文件定义一个要监控的仓库：

```yaml
repo: WSs-321/devops-k8s-agent-roadmap
local_path: D:\project\devops-k8s-agent-roadmap
timetable: timetable\75-day-plan.md
logs_dir: logs
labels: ["learning", "daily"]
```

## 定时任务

Windows Task Scheduler 每天 23:30 执行 `scripts/daily-check.ps1`。

## Codex 插件

`.codex-plugin/` 目录包含 Codex 插件配置，涵盖：
- 学习四步流程（learning-flow）
- Git 提交规范（git-commit-conventions）
- 项目标准要求（project-standards）

## Issue 记录

每次创建的 Issue 都会自动保存到 `records/issues-log.json`，记录字段：

| 字段 | 说明 |
|------|------|
| issue_number | GitHub Issue 编号 |
| issue_url | Issue 链接 |
| repo | 目标仓库 |
| day / week / topic | 对应 timetable 中的 Day、周次、主题 |
| task | 当日学习任务 |
| target_files | 本次 Issue 涉及的关联文件 |
| created_at | 创建时间 |
| solution | 解决方案（手动填写，有则写） |
| solved_at | 解决时间（手动填写） |

记录的 `solution` 和 `solved_at` 字段初始为空，可以在 Issue 解决后手动编辑 `records/issues-log.json` 补全。
