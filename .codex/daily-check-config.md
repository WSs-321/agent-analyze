# 每日定时检测配置

## 目标

每日自动检测本仓库，根据 `timetable/75-day-plan.md` 的学习计划，提一个针对性的 Issue，帮助用户了解当天的学习任务和进展。

## 触发时机

每日北京时间 08:00（或用户设定的其他时间）。

## 检测逻辑

1. 读取 `timetable/75-day-plan.md` 确定当天属于哪个 Day
2. 检查 `logs/week-XX/day-XX.md` 是否存在，判断该天是否已完成
3. 检查当前 Progress：已完成 vs 计划进度
4. 若当天未完成且未创建 Issue，则用 `daily-learning` 模板创建 Issue

## 自动化规则（Codex Automation）

```yaml
# 创建 Codex 定时任务
# 触发时间：每天 08:00 北京时间
# 动作：
#   1. 读取 timetable/75-day-plan.md 确定当日主题
#   2. 检查 logs/ 目录确认进度
#   3. 使用 .github/ISSUE_TEMPLATE/daily-learning.md 创建 Issue
#   4. 在对话中向用户汇报当日任务
```

## 手动触发

用户也可以在任何时候主动要求检查进度：
- "检查今天的学习任务"
- "今天该学什么"
- "进度到哪了"

## 不自动执行的保证

本自动化**仅创建 Issue 和汇报信息**，不会：
- ❌ 自动创建分支
- ❌ 自动写入代码/笔记
- ❌ 自动提 PR
- ❌ 自动合入

一切代码变更都走"学习 → 手动 coding → review → 同意 → PR"流程。
