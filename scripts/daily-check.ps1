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

function Save-IssueRecord {
    param(
        [string]$RepoFull,
        [int]$IssueNumber,
        [string]$IssueUrl,
        [int]$Day,
        [int]$Week,
        [string]$Topic,
        [string]$Task,
        [string[]]$TargetFiles
    )

    $recordsFile = Join-Path $AgentPath "records\issues-log.json"
    $record = [PSCustomObject]@{
        issue_number = $IssueNumber
        issue_url    = $IssueUrl
        repo         = $RepoFull
        day          = $Day
        week         = $Week
        topic        = $Topic
        task         = $Task
        target_files = $TargetFiles
        created_at   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        solution     = ""
        solved_at    = $null
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

function Invoke-TargetCheck {
    param(
        [string]$RepoFull,
        [string]$LocalPath,
        [string]$TimetableRel,
        [string]$LogsDirRel,
        [string[]]$IssueLabels
    )

    Write-Log "--- 检查目标: $RepoFull ---"

    # 1. 更新目标仓库代码
    try {
        Push-Location $LocalPath
        Write-Log "拉取 $RepoFull main 分支..."
        git checkout main 2>&1 | Out-Null
        git pull --ff-only 2>&1 | Out-Null
        Write-Log "main 已更新"
    } catch {
        Write-Log "WARN: git pull 失败: $_"
        Pop-Location
        return
    }
    Pop-Location

    # 2. 解析 timetable
    $timetablePath = Join-Path $LocalPath $TimetableRel
    if (-not (Test-Path $timetablePath)) {
        Write-Log "ERROR: timetable 不存在: $timetablePath"
        return
    }

    $timetable = Get-Content $timetablePath -Encoding utf8
    $dayMap = @{}
    $currentWeek = $null
    $inTable = $false

    foreach ($line in $timetable) {
        if ($line -match "^## Week (\d+):") {
            $currentWeek = [int]$Matches[1]
            $inTable = $false
            continue
        }
        if ($line -match "^\| Day \|") {
            $inTable = $true
            continue
        }
        if ($inTable -and $line -match "^\| (\d+) \| (.+?) \| (.+?) \| (.+?) \|$") {
            $dayNum = [int]$Matches[1]
            $dayMap[$dayNum] = @{
                Week   = $currentWeek
                Topic  = $Matches[2].Trim()
                Task   = $Matches[3].Trim()
                Output = $Matches[4].Trim()
            }
        }
        if ($inTable -and $line -match "^$") {
            $inTable = $false
        }
    }

    if ($dayMap.Count -eq 0) {
        Write-Log "ERROR: 未能解析 timetable"
        return
    }

    # 3. 统计已完成 Day
    $completedDays = [System.Collections.ArrayList]@()
    $logsDir = Join-Path $LocalPath $LogsDirRel
    if (Test-Path $logsDir) {
        $weekDirs = Get-ChildItem "$logsDir\week-*" -Directory -ErrorAction SilentlyContinue
        foreach ($wd in $weekDirs) {
            $dayFiles = Get-ChildItem "$($wd.FullName)\day-*.md" -File -ErrorAction SilentlyContinue
            foreach ($df in $dayFiles) {
                if ($df.BaseName -match "^day-(\d+)$") {
                    [void]$completedDays.Add([int]$Matches[1])
                }
            }
        }
    }

    Write-Log "已完成: $($completedDays.Count) / $($dayMap.Count) 天"

    # 4. 找下一个未完成的 Day
    $allDays = $dayMap.Keys | Sort-Object
    $nextDay = $null
    foreach ($d in $allDays) {
        if ($d -notin $completedDays) {
            $nextDay = $d
            break
        }
    }

    if (-not $nextDay) {
        Write-Log "全部 Day 已完成，跳过"
        return
    }

    $info = $dayMap[$nextDay]
    $weekStr = $info.Week.ToString("00")
    $dayStr  = $nextDay.ToString("00")
    Write-Log "下一个: Day $dayStr (Week $weekStr) - $($info.Topic)"

    # 5. 检查是否已有 open Issue
    try {
        $existing = gh issue list `
            --repo $RepoFull `
            --label $IssueLabels[0] `
            --state open `
            --json title `
            --jq ".[] | select(.title | startswith(\"[Day $dayStr]\"))" 2>&1
        if ($existing) {
            Write-Log "Day $dayStr 已有 open Issue，跳过"
            return
        }
    } catch {
        Write-Log "WARN: 检查 Issue 失败: $_"
    }

    # 6. 构造 Issue body
    $prevDay = $allDays | Where-Object { $_ -lt $nextDay } | Select-Object -Last 1
    $prevTopic = if ($prevDay) { $dayMap[$prevDay].Topic } else { "（无）" }

    $bodyLines = [System.Collections.ArrayList]@()
    [void]$bodyLines.Add("## 📋 当日信息")
    [void]$bodyLines.Add("")
    [void]$bodyLines.Add("| 项目 | 内容 |")
    [void]$bodyLines.Add("|------|------|")
    [void]$bodyLines.Add("| 计划来源 | `timetable/75-day-plan.md` |")
    [void]$bodyLines.Add("| 当前阶段 | Week $weekStr |")
    [void]$bodyLines.Add("| 当日主题 | $($info.Topic) |")
    [void]$bodyLines.Add("| 预计耗时 | 3 小时 |")
    [void]$bodyLines.Add("")
    [void]$bodyLines.Add("## 🎯 今日目标")
    [void]$bodyLines.Add("")
    [void]$bodyLines.Add("- [ ] $($info.Task)")
    [void]$bodyLines.Add("")
    [void]$bodyLines.Add("## 📝 学习要点")
    [void]$bodyLines.Add("<!-- 开始学习后在此记录关键概念 -->")
    [void]$bodyLines.Add("")
    [void]$bodyLines.Add("## ⚠️ 待确认问题")
    [void]$bodyLines.Add("<!-- 学习过程中遇到的问题 -->")
    [void]$bodyLines.Add("")
    [void]$bodyLines.Add("## ✅ 完成检查清单")
    [void]$bodyLines.Add("- [ ] 学习日志: `$LogsDirRel/week-$weekStr/day-$dayStr.md`")
    [void]$bodyLines.Add("- [ ] 概念笔记: `docs/<主题>.md`（如需）")
    [void]$bodyLines.Add("- [ ] 代码变更已通过 feature 分支提 PR")
    [void]$bodyLines.Add("- [ ] 本 Issue 已关联对应 PR")
    [void]$bodyLines.Add("")
    [void]$bodyLines.Add("---")
    [void]$bodyLines.Add("> 🕐 检测: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    [void]$bodyLines.Add("> 上一步: Day $prevDay — $prevTopic")

    $issueBody = $bodyLines -join "`n"

    # 7. 创建 Issue
    try {
        $title = "[Day $dayStr] $($info.Topic) — Week $weekStr"
        $result = gh issue create `
            --repo $RepoFull `
            --title $title `
            --label $IssueLabels[0] `
            --body $issueBody 2>&1
        Write-Log "Issue: $result"

        # 从 gh 返回中提取 issue number
        # 返回格式: https://github.com/WSs-321/devops-k8s-agent-roadmap/issues/42
        $issueUrl = $result.Trim()
        $issueNumber = 0
        if ($issueUrl -match "issues/(\d+)$") {
            $issueNumber = [int]$Matches[1]
        }

        # 8. 保存 Issue 记录到本仓
        $targetFilesList = @(
            "timetable/$TimetableRel",
            "$LogsDirRel/week-$weekStr/day-$dayStr.md"
        )
        if ($info.Output -and $info.Output -ne "-") {
            $targetFilesList += "docs/$($info.Topic -replace '\s+','-').md"
        }

        Save-IssueRecord `
            -RepoFull $RepoFull `
            -IssueNumber $issueNumber `
            -IssueUrl $issueUrl `
            -Day $nextDay `
            -Week $info.Week `
            -Topic $info.Topic `
            -Task $info.Task `
            -TargetFiles $targetFilesList
    } catch {
        Write-Log "ERROR: 创建 Issue 失败: $_"
    }
}

# === 主流程 ===
Write-Log "=== 每日检测开始 ==="

$targetsDir = Join-Path $AgentPath "targets"
$targetFiles = Get-ChildItem "$targetsDir\*.yaml" -File -ErrorAction SilentlyContinue

if ($targetFiles.Count -eq 0) {
    Write-Log "ERROR: targets/ 目录无 .yaml 配置文件"
    exit 1
}

Write-Log "发现 $($targetFiles.Count) 个目标仓库配置"

foreach ($tf in $targetFiles) {
    $config = @{}
    Get-Content $tf.FullName -Encoding utf8 | ForEach-Object {
        if ($_ -match "^\s*(\w+):\s*(.+)$") {
            $config[$Matches[1]] = $Matches[2].Trim().Trim('"', "'")
        }
    }

    $repoFull = $config["repo"]
    $localPath = $config["local_path"]
    $timetableRel = $config["timetable"]
    $logsDirRel = $config["logs_dir"]
    $labelsRaw = $config["labels"]

    $labels = @("daily")
    if ($labelsRaw) {
        $labels = $labelsRaw -replace '\[|\]|"' , '' -split ',' | ForEach-Object { $_.Trim() }
    }

    if (-not $repoFull -or -not $localPath) {
        Write-Log "WARN: 配置不完整，跳过: $($tf.Name)"
        continue
    }

    if ($TargetName -ne "*" -and $repoFull -notlike "*$TargetName*") {
        Write-Log "跳过 $repoFull（TargetName 过滤）"
        continue
    }

    Invoke-TargetCheck `
        -RepoFull $repoFull `
        -LocalPath $localPath `
        -TimetableRel $timetableRel `
        -LogsDirRel $logsDirRel `
        -IssueLabels $labels
}

Write-Log "=== 每日检测结束 ==="