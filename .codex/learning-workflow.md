# 学习工作流（Codex + 用户协作模式）

本文件定义 Codex 在此项目中的协作行为标准。

## 核心理念

这是一个**学习性质的项目**。代码提交节奏由**用户的学习节奏**决定，而非自动提交。

完整循环：**学习 → 手动 coding → Codex review → 纠正补全 → 用户同意 → 提 PR → 用户合入**

## 协作角色

| 角色 | 职责 |
|------|------|
| **用户** | 决定学习节奏、动手 coding、review summary、确认同意、合入 PR |
| **Codex** | 讲解知识、审查代码、提纠正建议、执行 git 操作（用户同意后）、创建 PR |

## 标准流程

```
用户: "开始 Day XX"
  └─ Codex: 学习阶段（讲解、贴代码片段，不动文件）
  └─ Codex: 输出总结（文件清单 + 变更目的 + 关键参数 + 风险点）
  └─ 用户: review 总结
  └─ 用户: "动手" / "落盘" / "提交"
  └─ Codex: 落盘阶段（创建分支 + commit）
  └─ Codex: 提 PR
  └─ 用户: review PR → squash merge → close issue
```

## 关键规则

1. **Codex 不自动作出任何代码变更**，每一步都需用户触发或确认。
2. **总结 review 不可跳过**：用户没有明确同意之前，Codex 不得写入任何文件。
3. **禁止向 main 直推**：所有变更必须经过 feature 分支 + PR 流程。
4. **PR 合入方式**：squash merge，保持 main 历史干净。
5. **每日检测自动化**：Codex 可每日提醒当日学习任务（基于 `timetable/75-day-plan.md`），但**不自动执行**。

## 例外许可

以下情况 Codex 可直接操作（无需逐行审批）：
- 创建/修改/删除 `.codex-plugin/` 中的配置和技能文件
- 创建 Issue / PR 模板文件
- 更新 `.gitignore`、`.markdownlint.json` 等非业务配置

## 关联文件

- `.codex-plugin/skills/learning-flow/SKILL.md` — 详细四步流程
- `.codex-plugin/skills/git-commit-conventions/SKILL.md` — 提交规范
- `.codex-plugin/skills/project-standards/SKILL.md` — 项目标准
- `.codex/daily-check-config.md` — 每日检测自动化配置
- `.github/ISSUE_TEMPLATE/daily-learning.md` — 每日 Issue 模板
- `.github/PULL_REQUEST_TEMPLATE.md` — PR 模板
