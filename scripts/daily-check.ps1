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

function New-TitleBody {
    param(
        [string]$AnalysisType,
        [string]$Summary,
        [string]$Detail,
        [string[]]$TargetFiles,
        [string]$BranchInfo
    )

    $lines = [System.Collections.ArrayList]@()
    [void]$lines.Add("## 检测概览")
    [void]$lines.Add("")
    [void]$lines.Add("| 项目 | 内容 |")
    [void]$lines.Add("|------|------|")
    [void]$lines.Add("| 类型 | $AnalysisType |")
    [void]$lines.Add("| 分支 | $BranchInfo |")
    [void]$lines.Add("| 检测时间 | $(Get-Date -Format 'yyyy-MM-dd HH:mm') |")
    [void]$lines.Add("")
    [void]$lines.Add("## 摘要")
    [void]$lines.Add("")
    [void]$lines.Add($Summary)
    [void]$lines.Add("")
    [void]$lines.Add("## 详情")
    [void]$lines.Add("")
    [void]$lines.Add($Detail)
    [void]$lines.Add("")
    [void]$lines.Add("## 涉及文件")
    if ($TargetFiles.Count -eq 0) {
        [void]$lines.Add("（无）")
    } else {
        foreach ($f in $TargetFiles) {
            [void]$lines.Add("- `$f`")
        }
    }

    return ($lines -join "`n")
}

function Invoke-TargetScan {
    param(
        [string]$RepoFull,
        [string]$LocalPath
    )

    Write-Log "--- 扫描目标: $RepoFull ---"

    # 1. 更新目标仓库 main
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
        $staleBranches = git branch -r --merged origin/main 2>&1 | Where-Object { $_ -match "^  remotes/origin/feature_" }
        $unmergedBranches = git branch -r --no-merged origin/main 2>&1 | Where-Object { $_ -match "^  remotes/origin/feature_" }

        if ($unmergedBranches) {
            $count = ($unmergedBranches | Measure-Object).Count
            $branches = ($unmergedBranches | ForEach-Object { $_.Trim() }) -join "`n"
            [void]$findings.Add([PSCustomObject]@{
                Type       = "未合入分支"
                Severity   = "info"
                Summary    = "$count 个 feature 分支尚未合入 main"
                Detail     = $branches
                Files      = @()
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
                Files    = $files.Keys | Sort-Object
            })
        }
        Pop-Location
    } catch {
        Write-Log "WARN: TODO 检查失败: $_"
    }

    # --- 检查三：workflow 文件是否存在问题 ---
    try {
        Push-Location $LocalPath
        $wfFiles = Get-ChildItem ".github\workflows\*.yml" -File -ErrorAction SilentlyContinue
        if ($wfFiles) {
            $wfIssues = @()
            foreach ($wf in $wfFiles) {
                $content = Get-Content $wf.FullName -Encoding utf8 -Raw
                if ($content -notmatch "^name:") {
                    $wfIssues += "$($wf.Name): 缺少 name 字段"
                }
                if ($content -notmatch "permissions:") {
                    $wfIssues += "$($wf.Name): 缺少 permissions 声明"
                }
            }
            if ($wfIssues.Count -gt 0) {
                [void]$findings.Add([PSCustomObject]@{
                    Type     = "Workflow 规范"
                    Severity = "warn"
                    Summary  = "$($wfIssues.Count) 个 workflow 存在规范问题"
                    Detail   = $wfIssues -join "`n"
                    Files    = $wfFiles.Name | Sort-Object
                })
            }
        }
        Pop-Location
    } catch {
        Write-Log "WARN: workflow 检查失败: $_"
    }

    # --- 检查四：未跟踪的配置文件 ---
    try {
        Push-Location $LocalPath
        $untracked = git ls-files --others --exclude-standard 2>&1
        $untracked = $untracked | Where-Object { $_ -match "\.(md|yml|yaml|json|js)$" }
        if ($untracked) {
            $count = ($untracked | Measure-Object).Count
            [void]$findings.Add([PSCustomObject]@{
                Type     = "未跟踪文件"
                Severity = "info"
                Summary  = "$count 个新文件未纳入版本管理"
                Detail   = ($untracked -join "`n")
                Files    = @($untracked)
            })
        }
        Pop-Location
    } catch {
        Write-Log "WARN: 未跟踪文件检查失败: $_"
    }

    # --- 检查五：进度分析（基于 timetable ---
    try {
        Push-Location $LocalPath
        $timetablePath = "timetable\75-day-plan.md"
        if (Test-Path $timetablePath) {
            $timetable = Get-Content $timetablePath -Encoding utf8
            $dayMap = @{}
            $currentWeek = $null
            $inTable = $false
            foreach ($line in $timetable) {
                if ($line -match "^## Week (\d+):") {
                    $currentWeek = [int]$Matches[1]; $inTable = $false; continue
                }
                if ($line -match "^\| Day \|") { $inTable = $true; continue }
                if ($inTable -and $line -match "^\| (\d+) \| (.+?) \| (.+?) \| (.+?) \|$") {
                    $dayMap[[int]$Matches[1]] = @{ Week = $currentWeek; Topic = $Matches[2].Trim() }
                }
                if ($inTable -and $line -match "^$") { $inTable = $false }
            }

            $completedDays = @()
            $weekDirs = Get-ChildItem "logs\week-*" -Directory -ErrorAction SilentlyContinue
            foreach ($wd in $weekDirs) {
                $dayFiles = Get-ChildItem "$($wd.FullName)\day-*.md" -File -ErrorAction SilentlyContinue
                foreach ($df in $dayFiles) {
                    if ($df.BaseName -match "^day-(\d+)$") { $completedDays += [int]$Matches[1] }
                }
            }

            $allDays = $dayMap.Keys | Sort-Object
            $completedSet = $completedDays | Sort-Object -Unique
            $progress = [math]::Round($completedSet.Count / $allDays.Count * 100, 1)

            [void]$findings.Add([PSCustomObject]@{
                Type     = "学习进度"
                Severity = "info"
                Summary  = "总进度 $progress% — 已完成 $($completedSet.Count)/$($allDays.Count) 天"
                Detail   = "最后完成: Day $($completedSet | Select-Object -Last 1)"
                Files    = @("logs/", "timetable/75-day-plan.md")
            })
        }
        Pop-Location
    } catch {
        Write-Log "WARN: 进度检查失败: $_"
    }

    # --- 汇总 ---
    if ($findings.Count -eq 0) {
        Write-Log "无发现，跳过 Issue 创建"
        return
    }

    # 检查是否已有今日 open Issue（按日期检测）
    $todayTag = "daily-" + (Get-Date -Format "yyyyMMdd")
    try {
        $existing = gh issue list --repo $RepoFull --label "daily" --state open --json title --jq ".[] | select(.title | startswith(\"[$todayTag]\"))" 2>&1
        if ($existing) {
            Write-Log "今日已有 open Issue，跳过"
            return
        }
    } catch {
        Write-Log "WARN: 检查 Issue 失败: $_"
    }

    # 构建 Issue
    $warnings = $findings | Where-Object { $_.Severity -eq "warn" }
    $infos = $findings | Where-Object { $_.Severity -eq "info" }
    $allFiles = $findings | ForEach-Object { $_.Files } | Where-Object { $_ } | Sort-Object -Unique

    $summaryLines = @()
    $detailSections = @()

    foreach ($f in $findings) {
        $emoji = if ($f.Severity -eq "warn") { "⚠️" } else { "ℹ️" }
        $summaryLines += "- $emoji $($f.Type): $($f.Summary)"
        $detailSections += "### $emoji $($f.Type)"
        $detailSections += ""
        $detailSections += $f.Detail
        $detailSections += ""
    }

    $IssueBody = New-TitleBody `
        -AnalysisType "每日代码分析" `
        -Summary ($summaryLines -join "`n") `
        -Detail ($detailSections -join "`n") `
        -TargetFiles $allFiles `
        -BranchInfo $branchInfo

    $dateStr = Get-Date -Format "yyyyMMdd"
    $title = "[$dateStr] 代码分析 — $($warnings.Count) 个待处理"

    try {
        $result = gh issue create --repo $RepoFull --title $title --label "daily" --body $IssueBody 2>&1
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
    Write-Log "ERROR: targets/ 目录无 .yaml 配置文件"
    exit 1
}

Write-Log "发现 $($targetFiles.Count) 个目标仓库"

foreach ($tf in $targetFiles) {
    $config = @{}
    Get-Content $tf.FullName -Encoding utf8 | ForEach-Object {
        if ($_ -match "^\s*(\w+):\s*(.+)$") {
            $config[$Matches[1]] = $Matches[2].Trim().Trim('"', "'")
        }
    }

    $repoFull = $config["repo"]
    $localPath = $config["local_path"]

    if (-not $repoFull -or -not $localPath) {
        Write-Log "WARN: 配置不完整: $($tf.Name)" ; continue
    }

    if ($TargetName -ne "*" -and $repoFull -notlike "*$TargetName*") {
        Write-Log "跳过 $repoFull" ; continue
    }

    Invoke-TargetScan -RepoFull $repoFull -LocalPath $localPath
}

Write-Log "=== 每日代码分析结束 ==="