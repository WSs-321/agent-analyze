# 项目标准要求

## 文件组织

```
.
├── .codex-plugin/          # Codex 插件（技能文件）
├── .codex/                 # 项目级 Codex 配置
├── .github/
│   ├── workflows/          # GitHub Actions 工作流
│   ├── ISSUE_TEMPLATE/     # Issue 模板
│   └── PULL_REQUEST_TEMPLATE.md
├── .trae/                  # （历史，待清理）
├── app/                    # 示例应用
├── docs/                   # 概念笔记
├── examples/               # 示例文件
├── logs/                   # 每日学习日志
├── projects/               # 项目验收
├── templates/              # 文档模板
├── timetable/              # 75 天计划
└── tracks/                 # 学习路径
```

## 命名规范

| 类型 | 规范 | 示例 |
|------|------|------|
| Workflow 文件 | `ci-<功能>.yml` | `ci-docker.yml` |
| 分支名 | `feature_<摘要>` | `feature_trivy-pipeline` |
| 日志文件 | `week-XX/day-XX.md` | `week-04/day-25.md` |
| 笔记文件 | `<主题>.md` | `trivy-scan.md` |
| commit message | 中文 ≤10 字 | "Day25 Trivy扫描" |

## 质量标准

- Markdown 文件遵守 `.markdownlint.json`
- Node.js 代码遵守 ESLint 配置
- Workflow 遵循最小权限原则

## 学习记录

每天完成学习后必须填写 `templates/daily-log.md` 模板的日志。
