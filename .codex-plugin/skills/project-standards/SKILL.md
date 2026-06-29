---
name: project-standards
description: 项目标准要求 —— 文件组织规范、命名规范、质量标准、PR 合入规范。
alwaysApply: true
---

# 项目标准要求

## 仓库结构

```
.
├── .codex-plugin/          # Codex 插件配置（技能文件）
├── .github/
│   ├── workflows/          # GitHub Actions 工作流
│   ├── ISSUE_TEMPLATE/     # Issue 模板
│   └── PULL_REQUEST_TEMPLATE.md
├── .trae/                  # （历史）Trae 规则，迁移完成后可删除
├── .vscode/
├── app/                    # 示例应用代码（Node.js）
│   ├── src/
│   ├── test/
│   ├── scripts/
│   ├── Dockerfile
│   └── package.json
├── docs/                   # 概念笔记（每个新主题一篇 .md）
├── examples/               # 示例文件（github-actions/）
├── logs/                   # 每日学习日志
│   ├── week-01/
│   ├── week-03/
│   └── week-04/
├── projects/               # 项目验收标准
├── templates/              # 文档模板
├── timetable/              # 75 天学习计划
├── tracks/                 # 学习路径跟踪文档
├── README.md
└── ROADMAP.md
```

## 文件规范

- **Markdown 文件**：遵守 `.markdownlint.json` 配置（MD013/MD033/MD041 关闭）。
- **Workflow 文件**：`.github/workflows/*.yml`，使用 kebab-case 命名。
- **日志文件**：`logs/week-XX/day-XX.md`，使用 `templates/daily-log.md` 模板。
- **笔记文件**：`docs/<主题>.md`，使用 kebab-case 命名。
- **代码风格**：Node.js 项目遵守 ESLint 配置。

## 学习记录规范

- 每天先读 `timetable/75-day-plan.md` 确认当日主题。
- 学习日志包含：今日目标、实际完成、遇到的问题、解决方案、明日计划。
- 日志模板参见 `templates/daily-log.md`。

## 工作流规范

- `.github/workflows/` 中每个 workflow 职责单一。
- 命名：`ci-<功能>.yml`、`cd-<环境>.yml`、`security-<工具>.yml`。
- 最小权限原则：每个 workflow 声明 `permissions`，不依赖默认权限。
- 关键操作（push image、deploy）加 `if` 条件避免 PR 触发。

## 代码提交规范

参见 `git-commit-conventions` skill。

## PR 合入规范

参见 `.github/PULL_REQUEST_TEMPLATE.md`。

核心原则：
1. feature 分支 → 创建 PR → review → 用户批准 → squash merge
2. 禁止向 `main` 直推
3. PR 标题格式：`[Day XX] <变更摘要>`
4. 合入方式：squash merge，保持 main 历史干净
