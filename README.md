# agent-analyze

每日定时分析目标仓库 **main 分支** 代码，提交针对性 Issue 的分析 Agent。

## 职责

- 定时拉取目标仓库 main 分支最新代码
- 多维度扫描分析：
  - 📂 未合入的 feature 分支
  - 🔍 代码中的 TODO / FIXME / HACK 标记
  - ⚙️ Workflow 规范检查（name / permissions 声明）
  - 📄 未跟踪的重要文件
  - 📊 学习进度统计（针对 learning-roadmap 类型）
- 发现问题时自动创建 Issue

**Issue 针对的是 main 分支当前代码的状态，不是学习计划提醒。**

## 配置

编辑 `targets/` 目录下的 `.yaml` 文件，每仓一个：

```yaml
repo: WSs-321/devops-k8s-agent-roadmap
local_path: D:\project\devops-k8s-agent-roadmap
type: learning-roadmap
labels: ["daily"]
```

## Issue 记录

每次创建的 Issue 自动保存到 `records/issues-log.json`：

```json
{
  "issue_number": 42,
  "issue_url": "https://github.com/.../issues/42",
  "repo": "WSs-321/devops-k8s-agent-roadmap",
  "analysis_type": "daily-scan",
  "summary": "发现 3 项: 1 个警告, 2 个提示",
  "target_files": [".github/workflows/ci-docker.yml", "logs/"],
  "created_at": "2026-06-29 23:30:00",
  "solution": "",
  "solved_at": null
}
```

`solution` 和 `solved_at` 初始为空，解决后手动编辑补全。

## 定时任务

Windows Task Scheduler: `DevOps-Learning-DailyCheck` — 每天 **23:30**

## Codex 插件

`.codex-plugin/` 目录包含项目标准的 Codex 技能：
- 学习四步流程（learning-flow）
- Git 提交规范（git-commit-conventions）
- 项目标准要求（project-standards）
