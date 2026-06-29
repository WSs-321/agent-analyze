---
name: git-commit-conventions
description: 本项目 Git 提交规范 —— 中文 ≤10 字、无 type 前缀、feature 分支、拒绝对 main 直推。
alwaysApply: true
---

# Git Commit Message 规则

## 内容格式
- 使用中文，简短概括本次变更内容，总字数不超过 10 字。
- 不需要 type 前缀（如 feat/fix），直接描述变更。
- 若一次涉及多处类似改动，合并为一条 message，需覆盖所有改动要点。

## 提交行为（学习项目 ← 人工驱动）

> 本仓库为学习性质项目。**Codex 不得自动提交代码**。

正确流程：
1. 用户学习并手动 coding
2. Codex 提供 review 和纠正建议
3. 用户同意后，Codex 执行 `git add` + `git commit` + `git push`
4. 通过 `gh pr create` 创建 PR
5. 用户最终合入

禁止直接合入 `main` 分支。

## 分支命名

- 若当前在 `main` 分支，先创建功能分支，分支名统一使用 `feature_<变更摘要>`。
- 摘要使用小写英文短词并用 `-` 连接，例如：
  - `feature_trivy-pipeline`
  - `feature_dockerfile-oci-labels`
  - `feature_day22-ghcr-notes`

## 合并提交

- 若上一次 push 之后产生了多次本地 commit 且内容相似，应通过 `git reset --soft` 或 `git commit --amend` 合并为一条。
- 合并后的 message 必须覆盖被合并 commit 的全部要点，仍保持 10 字以内。
- 不修改已经推送到远端的历史 commit。

## 自测 checklist（每次 commit 前对照）

- [ ] message 使用中文，≤10 字
- [ ] 不含 type 前缀（无 feat/fix/docs 等）
- [ ] 包含 day 或任务信息（如 "Day25 Trivy扫描"）
- [ ] 分支名格式 `feature_<摘要>`，非 `main` 分支
- [ ] 当前 commit 不在 `main` 上直推
