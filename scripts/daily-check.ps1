param(
    [string]$AgentPath = "D:\project\agent-analyze",
    [string]$TargetName = "*"
)

$ErrorActionPreference = "Stop"
$LogFile = Join-Path $AgentPath ".codex\daily-check.log"

function Write-Log {
    param([string]$Message)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$time $Message" | Out-File -FilePath $LogFile -Encoding utf8 -Append
}

function Save-AnalysisRecord {
    param(
        [string]$RepoFull,
        [int]$IssueNumber,
        [string]$IssueUrl,
        [string]$AnalysisType,
        [string]$Summary,
        [string[]]$TargetFiles
    )

    $recordsFile = Join-Path $AgentPath "records\issues-log.json"
    $record = [PSCustomObject]@{
        issue_number  = $IssueNumber
        issue_url     = $IssueUrl
        repo          = $RepoFull
        analysis_type = $AnalysisType
        summary       = $Summary
        target_files  = $TargetFiles
        created_at    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        solution      = ""
        solved_at     = $null
    }

    $records = @()
    if (Test-Path $recordsFile) {
        try {
            $records = Get-Content $recordsFile -Encoding utf8 | ConvertFrom-Json
            if ($records -isnot [array]) { $records = @($records) }
        } catch {
            Write-Log "WARN: 读取记录文件失败，重建: $_"
            $records = @()
        }
    }

    $records += $record
    $records | ConvertTo-Json -Depth 3 | Out-File -FilePath $recordsFile -Encoding utf8
    Write-Log "记录已保存: Issue #$IssueNumber -> $recordsFile"
}

function Invoke-TargetScan {
    param(
        [string]$RepoFull,
        [string]$LocalPath,
        [string[]]$IssueLabels
    )

    Write-Log "--- 扫描目标: $RepoFull ---"

    try {
        Push-Location $LocalPath
        Write-Log "拉取 $RepoFull main 分支..."
        git checkout main 2>&1 | Out-Null
        git pull --ff-only 2>&1 | Out-Null
        $branchInfo = "main @ $(git log -1 --format='%h %ai' 2>&1)"
        Write-Log "main 已更新: $branchInfo"
    } catch {
        Write-Log "WARN: git pull 失败: $_"
        Pop-Location
        return
    }
    Pop-Location

    $findings = [System.Collections.ArrayList]@()

    # --- 检查一：未合入的 feature 分支 ---
    try {
        Push-Location $LocalPath
        $unmergedBranches = git branch -r --no-merged origin/main 2>&1 | Where-Object { $_ -match "^  remotes/origin/feature_" }
        if ($unmergedBranches) {
            $count = ($unmergedBranches | Measure-Object).Count
            $branches = ($unmergedBranches | ForEach-Object { $_.Trim() }) -join "`n"
            [void]$findings.Add([PSCustomObject]@{
                Type     = "未合入分支"
                Severity = "info"
                Summary  = "$count 个 feature 分支尚未合入 main"
                Detail   = $branches
                Fix      = "逐分支 review 后 squash merge 到 main，删除已合入分支"
                Files    = @()
            })
        }
        Pop-Location
    } catch {
        Write-Log "WARN: 分支检查失败: $_"
    }

    # --- 检查二：TODO / FIXME / HACK 标记 ---
    try {
        Push-Location $LocalPath
        $todoLines = Select-String -Path "app\src\*.js", "app\test\*.js", "app\scripts\*.js" `
            -Pattern "(TODO|FIXME|HACK|XXX)" -CaseSensitive -SimpleMatch -ErrorAction SilentlyContinue
        if ($todoLines) {
            $count = ($todoLines | Measure-Object).Count
            $detailLines = @()
            $files = @{}
            foreach ($match in $todoLines) {
                $relPath = $match.Path -replace [regex]::Escape($LocalPath + "\"), ""
                $files[$relPath] = $true
                $detailLines += "$relPath($($match.LineNumber)): $($match.Line.Trim())"
            }
            [void]$findings.Add([PSCustomObject]@{
                Type     = "待办标记"
                Severity = "warn"
                Summary  = "代码中残留 $count 处 TODO/FIXME 标记"
                Detail   = ($detailLines | Select-Object -First 20) -join "`n"
                Fix      = "逐处 review，已完成则删除标记，未完成则提 feature 分支实现"
                Files    = $files.Keys | Sort-Object
            })
        }
        Pop-Location
    } catch {
        Write-Log "WARN: TODO 检查失败: $_"
    }

    # --- 检查三：workflow 规范 ---
    try {
        Push-Location $LocalPath
        $wfFiles = Get-ChildItem ".github\workflows\*.yml" -File -ErrorAction SilentlyContinue
        if ($wfFiles) {
            $wfIssues = @()
            $wfFilesAll = @()
            foreach ($wf in $wfFiles) {
                $wfFilesAll += $wf.Name
                $content = Get-Content $wf.FullName -Encoding utf8 -Raw
                if ($content -notmatch "^name:") {
                    $wfIssues += "- $($wf.Name): 缺少 \`name\` 字段"
                }
                if ($content -notmatch "permissions:") {
                    $wfIssues += "- $($wf.Name): 缺少 \`permissions\` 声明"
                }
            }
            if ($wfIssues.Count -gt 0) {
                [void]$findings.Add([PSCustomObject]@{
                    Type     = "Workflow 规范"
                    Severity = "warn"
                    Summary  = "$($wfIssues.Count) 个 workflow 存在规范问题"
                    Detail   = $wfIssues -join "`n"
                    Fix      = "补全 name 和 permissions 字段，参考 ci-docker.yml 的规范写法"
                    Files    = $wfFilesAll | Sort-Object
                })
            }
        }
        Pop-Location
    } catch {
        Write-Log "WARN: workflow 检查失败: $_"
    }

    # --- 检查四：未跟踪的重要文件 ---
    try {
        Push-Location $LocalPath
        $untracked = git ls-files --others --exclude-standard 2>&1 | Where-Object { $_ -match "\.(md|yml|yaml|json|js)$" }
        if ($untracked) {
            $count = ($untracked | Measure-Object).Count
            [void]$findings.Add([PSCustomObject]@{
                Type     = "未跟踪文件"
                Severity = "info"
                Summary  = "$count 个新文件未纳入版本管理"
                Detail   = ($untracked -join "`n")
                Fix      = "review 后纳入版本管理: \`git add <文件> && git commit\`"
                Files    = @($untracked)
            })
        }
        Pop-Location
    } catch {
        Write-Log "WARN: 未跟踪文件检查失败: $_"
    }

    # --- 检查五：进度分析 ---
    try {
        Push-Location $LocalPath
        if (Test-Path "timetable\75-day-plan.md") {
            $timetable = Get-Content "timetable\75-day-plan.md" -Encoding utf8
            $dayMap = @{}; $currentWeek = $null; $inTable = $false
            foreach ($line in $timetable) {
                if ($line -match "^## Week (\d+):") { $currentWeek = [int]$Matches[1]; $inTable = $false; continue }
                if ($line -match "^\| Day \|") { $inTable = $true; continue }
                if ($inTable -and $line -match "^\| (\d+) \| (.+?) \| (.+?) \| (.+?) \|$") {
                    $dayMap[[int]$Matches[1]] = @{ Week = $currentWeek; Topic = $Matches[2].Trim() }
                }
                if ($inTable -and $line -match "^$") { $inTable = $false }
            }
            $completedDays = @()
            Get-ChildItem "logs\week-*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                Get-ChildItem "$($_.FullName)\day-*.md" -File -ErrorAction SilentlyContinue | ForEach-Object {
                    if ($_.BaseName -match "^day-(\d+)$") { $completedDays += [int]$Matches[1] }
                }
            }
            $allDays = $dayMap.Keys | Sort-Object
            $completedSet = $completedDays | Sort-Object -Unique
            $pct = [math]::Round($completedSet.Count / $allDays.Count * 100, 1)
            [void]$findings.Add([PSCustomObject]@{
                Type     = "学习进度"
                Severity = "info"
                Summary  = "总进度 $pct% — 已完成 $($completedSet.Count)/$($allDays.Count) 天"
                Detail   = "最后完成: Day $($completedSet | Select-Object -Last 1)"
                Fix      = "继续按 timetable 推进学习，每天完成一个 Day"
                Files    = @("logs/", "timetable/75-day-plan.md")
            })
        }
        Pop-Location
    } catch {
        Write-Log "WARN: 进度检查失败: $_"
    }

    # --- 汇总 ---
    if ($findings.Count -eq 0) {
        Write-Log "无发现，跳过"
        return
    }

    # 检查今日是否已有 Issue
    $todayTag = "daily-" + (Get-Date -Format "yyyyMMdd")
    try {
        $existing = gh issue list --repo $RepoFull --label "AI" --state open --json title --jq ".[] | select(.title | startswith(\"[$todayTag]\"))" 2>&1
        if ($existing) {
            Write-Log "今日已有 AI Issue，跳过"
            return
        }
    } catch {
        Write-Log "WARN: 检查 Issue 失败: $_"
    }

    # --- 构建 Issue body（含模拟 PR 合入） ---
    $warnings = $findings | Where-Object { $_.Severity -eq "warn" }
    $infos   = $findings | Where-Object { $_.Severity -eq "info" }
    $allFiles = $findings | ForEach-Object { $_.Files } | Where-Object { $_ } | Sort-Object -Unique

    $lines = [System.Collections.ArrayList]@()

    # 检测概览
    [void]$lines.Add("## 🕐 检测概览")
    [void]$lines.Add("")
    [void]$lines.Add("| 项目 | 内容 |")
    [void]$lines.Add("|------|------|")
    [void]$lines.Add("| 来源 | 🤖 agent-analyze |")
    [void]$lines.Add("| 目标 | $RepoFull |")
    [void]$lines.Add("| 分支 | $branchInfo |")
    [void]$lines.Add("| 检测 | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') |")
    [void]$lines.Add("")

    # 发现汇总
    [void]$lines.Add("## 📋 发现问题")
    [void]$lines.Add("")
    foreach ($f in $findings) {
        $emoji = if ($f.Severity -eq "warn") { "⚠️" } else { "ℹ️" }
        [void]$lines.Add("- $emoji **[$($f.Type)]** $($f.Summary)")
    }
    [void]$lines.Add("")

    # 逐项详情
    [void]$lines.Add("## 🔍 详情")
    [void]$lines.Add("")
    foreach ($f in $findings) {
        $emoji = if ($f.Severity -eq "warn") { "⚠️" } else { "ℹ️" }
        [void]$lines.Add("### $emoji $($f.Type)")
        [void]$lines.Add("")
        [void]$lines.Add($f.Detail)
        [void]$lines.Add("")
    }

    # 模拟 PR 合入
    [void]$lines.Add("---")
    [void]$lines.Add("")
    [void]$lines.Add("## 🔀 模拟 PR 合入")
    [void]$lines.Add("")
    [void]$lines.Add("以下是针对本次发现的建议修复方案，模拟标准 PR 流程：")
    [void]$lines.Add("")

    $hasWarn = $warnings.Count -gt 0
    $hasInfo = $infos.Count -gt 0

    if ($hasWarn) {
        [void]$lines.Add("### 建议分支")
        [void]$lines.Add("")
        $branchName = "feature_fix-" + (Get-Date -Format "MMdd") + "-daily"
        [void]$lines.Add("````")
        [void]$lines.Add("git checkout -b $branchName")
        [void]$lines.Add("````")
        [void]$lines.Add("")

        [void]$lines.Add("### 建议变更")
        [void]$lines.Add("")
        [void]$lines.Add("| 文件 | 建议操作 | 说明 |")
        [void]$lines.Add("|------|----------|------|")
        foreach ($f in $warnings) {
            foreach ($file in $f.Files) {
                [void]$lines.Add("| \`$file\` | 修复 | $($f.Fix) |")
            }
        }
        [void]$lines.Add("")

        [void]$lines.Add("### 合入方式")
        [void]$lines.Add("")
        [void]$lines.Add("````")
        [void]$lines.Add("gh pr create --base main --head $branchName")
        [void]$lines.Add("# review 后 squash merge")
        [void]$lines.Add("````")
        [void]$lines.Add("")
    }

    # 涉及文件
    if ($allFiles.Count -gt 0) {
        [void]$lines.Add("### 涉及文件")
        [void]$lines.Add("")
        foreach ($f in $allFiles) {
            [void]$lines.Add("- \`$f\`")
        }
        [void]$lines.Add("")
    }

    # 页脚
    if (-not $hasWarn) {
        [void]$lines.Add("本次检测未发现需要修复的问题，均为提示性信息。")
        [void]$lines.Add("")
    }
    [void]$lines.Add("---")
    [void]$lines.Add("> 🤖 由 agent-analyze 自动提交 · 非人工操作")
    [void]$lines.Add("> 标签: \`AI\` \`daily\`")

    $issueBody = $lines -join "`n"

    $dateStr = Get-Date -Format "yyyyMMdd"
    $warnCount = $warnings.Count
    $title = "[$dateStr] 代码分析 — $warnCount 个待处理"

    # 创建 Issue（使用所有标签）
    try {
        $labelArgs = ""
        foreach ($lb in $IssueLabels) {
            $labelArgs += " --label `"$lb`""
        }

        $result = gh issue create --repo $RepoFull --title $title $labelArgs --body $issueBody 2>&1
        Write-Log "Issue: $result"

        $issueUrl = $result.Trim()
        $issueNumber = 0
        if ($issueUrl -match "issues/(\d+)$") {
            $issueNumber = [int]$Matches[1]
        }

        Save-AnalysisRecord `
            -RepoFull $RepoFull `
            -IssueNumber $issueNumber `
            -IssueUrl $issueUrl `
            -AnalysisType "daily-scan" `
            -Summary "发现 $($findings.Count) 项: $($warnings.Count) 个警告, $($infos.Count) 个提示" `
            -TargetFiles $allFiles
    } catch {
        Write-Log "ERROR: 创建 Issue 失败: $_"
    }
}

# === 主流程 ===
Write-Log "=== 每日代码分析开始 ==="

$targetsDir = Join-Path $AgentPath "targets"
$targetFiles = Get-ChildItem "$targetsDir\*.yaml" -File -ErrorAction SilentlyContinue
if ($targetFiles.Count -eq 0) {
    Write-Log "ERROR: targets/ 无配置" ; exit 1
}
Write-Log "发现 $($targetFiles.Count) 个目标"

foreach ($tf in $targetFiles) {
    $config = @{}
    Get-Content $tf.FullName -Encoding utf8 | ForEach-Object {
        if ($_ -match "^\s*(\w+):\s*(.+)$") { $config[$Matches[1]] = $Matches[2].Trim().Trim('"', "'") }
    }
    $repoFull = $config["repo"]; $localPath = $config["local_path"]; $labelsRaw = $config["labels"]
    if (-not $repoFull -or -not $localPath) { Write-Log "WARN: 配置不完整"; continue }
    if ($TargetName -ne "*" -and $repoFull -notlike "*$TargetName*") { Write-Log "跳过 $repoFull"; continue }
    $labels = @("daily")
    if ($labelsRaw) { $labels = $labelsRaw -replace '\[|\]|"' , '' -split ',' | ForEach-Object { $_.Trim() } }
    Invoke-TargetScan -RepoFull $repoFull -LocalPath $localPath -IssueLabels $labels
}

Write-Log "=== 每日代码分析结束 ==="