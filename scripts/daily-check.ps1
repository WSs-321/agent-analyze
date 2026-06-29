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

function Invoke-RecordPR {
    param(
        [string]$RepoFull,
        [int]$IssueNumber,
        [string]$IssueUrl,
        [string]$AnalysisType,
        [string]$Summary,
        [string[]]$TargetFiles
    )

    $recordsFile = Join-Path $AgentPath "records\issues-log.json"

    # 构建记录对象
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

    # 读取已有记录
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
    $recordsJson = ($records | ConvertTo-Json -Depth 3)

    # 写文件
    $recordsJson | Out-File -FilePath $recordsFile -Encoding utf8
    Write-Log "记录已写入: $recordsFile"

    # === PR 自动合入流程 ===
    $dateTag = Get-Date -Format "yyyyMMdd-HHmmss"
    $branchName = "record/issue-$IssueNumber-$dateTag"

    try {
        Push-Location $AgentPath

        # 拉取最新 master
        git checkout master 2>&1 | Out-Null
        git pull --ff-only origin master 2>&1 | Out-Null

        # 创建分支、提交
        git checkout -b $branchName 2>&1 | Out-Null
        git add $recordsFile 2>&1 | Out-Null
        git commit -m "记录 Issue #$IssueNumber — $RepoFull" 2>&1 | Out-Null
        Write-Log "分支已提交: $branchName"

        # 推送
        git push -u origin $branchName 2>&1 | Out-Null
        Write-Log "分支已推送"

        # 创建 PR
        $prBody = @"
## 记录 Issue

| 项目 | 内容 |
|------|------|
| Issue | [#$IssueNumber]($IssueUrl) |
| 仓库 | $RepoFull |
| 类型 | $AnalysisType |
| 摘要 | $Summary |

### 涉及文件
$(if ($TargetFiles.Count -gt 0) { ($TargetFiles | ForEach-Object { "- \`$_\`" }) -join "`n" } else { "（无）" })

---

> 🤖 由 agent-analyze 自动提交
"@
        $prUrl = gh pr create --base master --head $branchName --title "记录 Issue #$IssueNumber — $RepoFull" --body $prBody 2>&1
        Write-Log "PR 已创建: $prUrl"

        # Squash merge 并删除分支
        gh pr merge --squash --delete-branch $prUrl 2>&1 | Out-Null
        Write-Log "PR 已 squash merge: $prUrl"

        # 切回 master 拉取最新
        git checkout master 2>&1 | Out-Null
        git pull --ff-only origin master 2>&1 | Out-Null

    } catch {
        Write-Log "ERROR: PR 流程失败: $_"
        # 恢复现场
        try { git checkout master 2>&1 | Out-Null } catch {}
    }
    Pop-Location
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
        git checkout main 2>&1 | Out-Null
        git pull --ff-only 2>&1 | Out-Null
        $branchInfo = "main @ $(git log -1 --format='%h %ai' 2>&1)"
        Write-Log "main 已更新: $branchInfo"
    } catch {
        Write-Log "WARN: git pull 失败: $_"; Pop-Location; return
    }
    Pop-Location

    $findings = [System.Collections.ArrayList]@()

    # 检查一：未合入分支
    try {
        Push-Location $LocalPath
        $unmerged = git branch -r --no-merged origin/main 2>&1 | Where-Object { $_ -match "^  remotes/origin/feature_" }
        if ($unmerged) {
            $count = ($unmerged | Measure-Object).Count
            $list = ($unmerged | ForEach-Object { $_.Trim() }) -join "`n"
            [void]$findings.Add([PSCustomObject]@{
                Type="未合入分支"; Severity="info"; Summary="$count 个 feature 分支尚未合入 main"
                Detail=$list; Fix="逐分支 review 后 squash merge"
                Files=@()
            })
        }
        Pop-Location
    } catch {}

    # 检查二：TODO/FIXME
    try {
        Push-Location $LocalPath
        $todo = Select-String -Path "app\src\*.js","app\test\*.js","app\scripts\*.js" -Pattern "(TODO|FIXME|HACK|XXX)" -CaseSensitive -SimpleMatch -ErrorAction SilentlyContinue
        if ($todo) {
            $count = ($todo | Measure-Object).Count
            $details = @(); $files=@{}
            foreach ($m in $todo) {
                $rp = $m.Path -replace [regex]::Escape($LocalPath+"\"),""
                $files[$rp]=$true; $details += "$rp($($m.LineNumber)): $($m.Line.Trim())"
            }
            [void]$findings.Add([PSCustomObject]@{
                Type="待办标记"; Severity="warn"; Summary="代码中残留 $count 处 TODO/FIXME 标记"
                Detail=($details|Select-Object -First 20)-join "`n"
                Fix="逐处 review，已完成则删除标记"
                Files=$files.Keys|Sort-Object
            })
        }
        Pop-Location
    } catch {}

    # 检查三：Workflow 规范
    try {
        Push-Location $LocalPath
        $wf = Get-ChildItem ".github\workflows\*.yml" -File -ErrorAction SilentlyContinue
        if ($wf) {
            $issues=@(); $allWf=@()
            foreach ($w in $wf) { $allWf+=$w.Name; $c=Get-Content $w.FullName -Raw
                if ($c -notmatch "^name:") { $issues += "- $($w.Name): 缺少 \`name\`" }
                if ($c -notmatch "permissions:") { $issues += "- $($w.Name): 缺少 \`permissions\`" }
            }
            if ($issues.Count -gt 0) {
                [void]$findings.Add([PSCustomObject]@{
                    Type="Workflow 规范"; Severity="warn"
                    Summary="$($issues.Count) 个 workflow 存在规范问题"
                    Detail=$issues-join "`n"
                    Fix="补全 name 和 permissions"
                    Files=$allWf|Sort-Object
                })
            }
        }
        Pop-Location
    } catch {}

    # 检查四：未跟踪文件
    try {
        Push-Location $LocalPath
        $untracked = git ls-files --others --exclude-standard 2>&1 | Where-Object { $_ -match "\.(md|yml|yaml|json|js)$" }
        if ($untracked) {
            $count = ($untracked | Measure-Object).Count
            [void]$findings.Add([PSCustomObject]@{
                Type="未跟踪文件"; Severity="info"; Summary="$count 个新文件未纳入版本管理"
                Detail=($untracked-join "`n"); Fix="review 后 git add + commit"
                Files=@($untracked)
            })
        }
        Pop-Location
    } catch {}

    # 检查五：进度
    try {
        Push-Location $LocalPath
        if (Test-Path "timetable\75-day-plan.md") {
            $tt = Get-Content "timetable\75-day-plan.md" -Encoding utf8
            $dm=@{};$cw=$null;$it=$false
            foreach ($l in $tt) {
                if ($l-match"^## Week (\d+):"){$cw=[int]$Matches[1];$it=$false;continue}
                if ($l-match"^\| Day \|"){$it=$true;continue}
                if ($it-and$l-match"^\| (\d+) \| (.+?) \| (.+?) \| (.+?) \|\$"){$dm[[int]$Matches[1]]=@{Week=$cw;Topic=$Matches[2].Trim()}}
                if ($it-and$l-match"^\$"){$it=$false}
            }
            $cd=@()
            Get-ChildItem "logs\week-*" -Directory -ErrorAction SilentlyContinue|%{
                Get-ChildItem "$($_.FullName)\day-*.md" -File -ErrorAction SilentlyContinue|%{
                    if($_.BaseName-match"^day-(\d+)$"){$cd+=[int]$Matches[1]}
                }
            }
            $ad=$dm.Keys|Sort-Object;$cs=$cd|Sort-Object -Unique
            $pct=[math]::Round($cs.Count/$ad.Count*100,1)
            [void]$findings.Add([PSCustomObject]@{
                Type="学习进度"; Severity="info"
                Summary="总进度 $pct% — $($cs.Count)/$($ad.Count) 天"
                Detail="最后完成: Day $($cs|Select-Object -Last 1)"
                Fix="按 timetable 推进"; Files=@("logs/","timetable/75-day-plan.md")
            })
        }
        Pop-Location
    } catch {}

    if ($findings.Count -eq 0) { Write-Log "无发现"; return }

    # 查重
    $todayTag = "daily-"+(Get-Date -Format "yyyyMMdd")
    try {
        $existing = gh issue list --repo $RepoFull --label "AI" --state open --json title --jq ".[]|select(.title|startswith(\"[$todayTag]\"))" 2>&1
        if ($existing) { Write-Log "今日已有 AI Issue，跳过"; return }
    } catch {}

    # 构建 Issue
    $warnings = $findings|Where-Object{$_.Severity -eq "warn"}
    $infos = $findings|Where-Object{$_.Severity -eq "info"}
    $allFiles = $findings|ForEach-Object{$_.Files}|Where-Object{$_}|Sort-Object -Unique

    $lines = [System.Collections.ArrayList]@()
    [void]$lines.Add("## 🕐 检测概览"); [void]$lines.Add("")
    [void]$lines.Add("| 项目 | 内容 |"); [void]$lines.Add("|------|------|")
    [void]$lines.Add("| 来源 | 🤖 agent-analyze |")
    [void]$lines.Add("| 目标 | $RepoFull |"); [void]$lines.Add("| 分支 | $branchInfo |")
    [void]$lines.Add("| 检测 | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') |"); [void]$lines.Add("")
    [void]$lines.Add("## 📋 发现问题"); [void]$lines.Add("")
    foreach ($f in $findings) {
        $emoji = if($f.Severity -eq "warn"){"⚠️"}else{"ℹ️"}
        [void]$lines.Add("- $emoji **[$($f.Type)]** $($f.Summary)")
    }
    [void]$lines.Add(""); [void]$lines.Add("## 🔍 详情"); [void]$lines.Add("")
    foreach ($f in $findings) {
        $emoji = if($f.Severity -eq "warn"){"⚠️"}else{"ℹ️"}
        [void]$lines.Add("### $emoji $($f.Type)"); [void]$lines.Add(""); [void]$lines.Add($f.Detail); [void]$lines.Add("")
    }
    [void]$lines.Add("---"); [void]$lines.Add("")
    [void]$lines.Add("## 🔀 模拟 PR 合入"); [void]$lines.Add("")

    if ($warnings.Count -gt 0) {
        $bn = "feature_fix-"+(Get-Date -Format "MMdd")+"-daily"
        [void]$lines.Add("### 建议分支"); [void]$lines.Add("")
        [void]$lines.Add("````"); [void]$lines.Add("git checkout -b $bn"); [void]$lines.Add("````"); [void]$lines.Add("")
        [void]$lines.Add("### 建议变更"); [void]$lines.Add("")
        [void]$lines.Add("| 文件 | 建议操作 | 说明 |"); [void]$lines.Add("|------|----------|------|")
        foreach ($f in $warnings) { foreach ($file in $f.Files) {
            [void]$lines.Add("| \`$file\` | 修复 | $($f.Fix) |")
        }}
        [void]$lines.Add(""); [void]$lines.Add("### 合入方式"); [void]$lines.Add("")
        [void]$lines.Add("````"); [void]$lines.Add("gh pr create --base main --head $bn")
        [void]$lines.Add("# review 后 squash merge"); [void]$lines.Add("````"); [void]$lines.Add("")
    }
    if ($allFiles.Count -gt 0) {
        [void]$lines.Add("### 涉及文件"); [void]$lines.Add("")
        foreach ($f in $allFiles) { [void]$lines.Add("- \`$f\`") }; [void]$lines.Add("")
    }
    if (-not $warnings) { [void]$lines.Add("本次检测未发现需修复的问题，均为提示性信息。"); [void]$lines.Add("") }
    [void]$lines.Add("---"); [void]$lines.Add("> 🤖 由 agent-analyze 自动提交 · 非人工操作")
    [void]$lines.Add("> 标签: \`AI\` \`daily\`")
    $issueBody = $lines -join "`n"

    $dateStr = Get-Date -Format "yyyyMMdd"
    $title = "[$dateStr] 代码分析 — $($warnings.Count) 个待处理"

    # 创建 Issue
    try {
        $labelArgs = ""
        foreach ($lb in $IssueLabels) { $labelArgs += " --label `"$lb`"" }
        $result = gh issue create --repo $RepoFull --title $title $labelArgs --body $issueBody 2>&1
        Write-Log "Issue: $result"

        $issueUrl = $result.Trim()
        $issueNumber = 0
        if ($issueUrl -match "issues/(\d+)$") { $issueNumber = [int]$Matches[1] }

        # 保存记录 → 自动 PR 合入 agent-analyze
        Invoke-RecordPR `
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
if ($targetFiles.Count -eq 0) { Write-Log "ERROR: 无配置"; exit 1 }
Write-Log "发现 $($targetFiles.Count) 个目标"

foreach ($tf in $targetFiles) {
    $config = @{}
    Get-Content $tf.FullName -Encoding utf8 | ForEach-Object {
        if ($_ -match "^\s*(\w+):\s*(.+)$") { $config[$Matches[1]] = $Matches[2].Trim().Trim('"',"'" ) }
    }
    $r = $config["repo"]; $lp = $config["local_path"]; $lr = $config["labels"]
    if (-not $r -or -not $lp) { Write-Log "WARN: 配置不完整"; continue }
    if ($TargetName -ne "*" -and $r -notlike "*$TargetName*") { Write-Log "跳过 $r"; continue }
    $labels = @("daily")
    if ($lr) { $labels = $lr -replace '\[|\]|"','' -split ',' | ForEach-Object { $_.Trim() } }
    Invoke-TargetScan -RepoFull $r -LocalPath $lp -IssueLabels $labels
}
Write-Log "=== 每日代码分析结束 ==="