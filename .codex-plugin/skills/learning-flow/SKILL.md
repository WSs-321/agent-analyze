---
name: learning-flow
description: 75-day DevOps/K8s/Agent 学习四步流程 —— 学习 → 总结（等待确认）→ 落盘 → 提 PR。严禁跳过总结审查，严禁自动提交代码。
alwaysApply: true
---

# 学习流程规则

凡涉及 `timetable/75-day-plan.md` 中的每日学习内容，Codex 必须严格按"学习→总结→落盘→提 PR"四步流程执行，缺一步都不得进入下一步。

## 第一步：学习

> 用户说"学习"或"讲解"或"开始 Day X"时触发

- **仅做讲解、贴示例、写代码片段，不创建、不修改任何文件**。
- 内容以 Markdown 代码块、ASCII 图、表格呈现，便于在对话里消化。
- 不创建 feature 分支，不运行 `git add` / `git commit` / `git push`。
- 不写 `logs/week-*/day-*.md`，不写 `docs/*.md`，不加 `.github/workflows/*.yml`。

## 第二步：总结

> 学完一个主题后触发

- 把当天要落的文件清单、关键要点、YAML / Markdown 草案以"总结"形式输出在对话里，**等你 review**。
- 总结里必须显式列出：
  1. 文件路径
  2. 变更目的
  3. 关键参数 / 字段说明
  4. 风险点
- **未收到用户明确同意（点头 / "动手" / "落盘" / "提交"等）之前，不进入第三步**。
- ✅ 禁止：直接 commit / push / 创建分支。
- ✅ 禁止：先把代码写成再说，再问用户。

## 第三步：落盘

> 收到用户同意后触发

- 按总结里确认的文件路径创建或修改代码。
- 本地先 `git checkout main && git pull --ff-only` 拉齐。
- 从 `main` 新建 `feature_<变更摘要>` 分支（摘要用英文小写、`-` 连接，参考 git-commit-conventions）。
- `git add -A` + `git commit -m "<message>"`，message 中文、≤10 字、含 day / 任务信息。
- 不在本步 push。

## 第四步：提 PR

- `git push -u origin <feature-branch>`。
- 调用 `gh pr create --base main --head <branch>` 创建 PR，并回显 PR URL。
- 若 `gh` 不可用，给出 GitHub Compare 链接让用户手动创建。
- 推完后向用户回显：commit hash、message、分支名、PR URL。
- 失败后立即停止并报告原因，不重试破坏性操作。

## 强制约束

- 全程**禁止跳过"总结 review"**；用户没有点头就不准动文件、不准建分支。
- 全程**禁止直接 commit / push 到 `main`**。
- 任何"先写出来给你看"的代码片段，**只在对话里贴**，不要顺手写到磁盘。
- 误判当日主题时（如把 Week 4 当成 K8s 而非 GHCR），必须以 `timetable/75-day-plan.md` 为准，不要凭直觉。
- 不在第一 / 第二步运行 `git checkout -b` 之类会改变仓库状态的高风险命令。

## 自测 checklist（每条 daily 提交前对照）

- [ ] 总结里列出的文件路径用户已确认
- [ ] 文件内容符合 markdownlint 配置且与已有 `docs/docker-*.md` 风格一致
- [ ] commit message ≤10 字、含 day 信息
- [ ] 分支名 `feature_<摘要>`，从最新 `main` 拉出
- [ ] `gh pr create` 已成功并拿到 PR URL 回显

## 与 Trae 规则的差异

此规则从 `.trae/rules/learning-flow.md` 迁移而来。核心差异：
- 要求 Codex 在使用前先出示计划（本 SKILL.md），让用户确认后再执行。
- 强调手动 coding → Codex review → 纠正补全 → 用户同意 → 提 PR 的完整闭环。
- 明确禁止 Codex 自动提交代码（包括 `.trae/rules/git-commit-message.md` 中的自动提交流程）。
