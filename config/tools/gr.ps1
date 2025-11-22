function global:gr {
    [CmdletBinding(DefaultParameterSetName = 'Command')]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Command')]
        [string]$Command,

        [Parameter(ParameterSetName = 'Version')]
        [Alias('v')]
        [switch]$Version,

        [Parameter(ValueFromRemainingArguments = $true, ParameterSetName = 'Command')]
        [string[]]$RemainingArgs
    )

    # ========== Handle -version ==========
    if ($PSCmdlet.ParameterSetName -eq 'Version') {
        Write-Output "gr version 0.0.2"
        return
    }

    # ========== Missing command ==========
    if ([string]::IsNullOrWhiteSpace($Command)) {
        Write-Error "缺少子命令。使用 'gr help' 查看帮助。"
        return
    }

    $configPath = "$HOME/.gr"
    if (-not (Test-Path $configPath)) {
        @{} | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding Utf8
    }

    function Get-RepoMap {
        $content = Get-Content $configPath -Raw
        if ([string]::IsNullOrWhiteSpace($content)) { return @{} }
        return $content | ConvertFrom-Json -AsHashtable
    }

    function Save-RepoMap([hashtable]$Map) {
        $Map | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding Utf8
    }

    switch ($Command) {
        'help' {
            Write-Host @"
USAGE:
    gr add -name <name> -path <path/to/repo>
    gr rm  <name>
    gr rename <old_name> <new_name>
    gr cd  <name>
    gr list
    gr status [name]
    gr log [name]
    gr run <name> <git_cmd> [age...]
    gr open <name> 
    gr info <name> 
    gr -v | --version
    gr help
DESCRIPTION:
    管理多个 Git 仓库的快捷访问。
"@ -ForegroundColor Cyan
        }

        'list' {
            # === 参数解析：检查是否包含 -ShowPath ===
            $showPath = $false
            if ($RemainingArgs.Count -eq 1 -and $RemainingArgs[0] -eq '-ShowPath') {
                $showPath = $true
            } elseif ($RemainingArgs.Count -gt 0) {
                Write-Error "用法: gr list [-ShowPath]"
                return
            }

            $configFile = "$HOME\.gr"
            if (-not (Test-Path -Path $configFile)) {
                Write-Host "暂无管理的仓库。" -ForegroundColor Gray
                return
            }

            $jsonContent = Get-Content -Path $configFile -Raw
            if ([string]::IsNullOrWhiteSpace($jsonContent)) {
                Write-Host "配置文件为空。" -ForegroundColor Yellow
                return
            }

            try {
                $repoConfig = $jsonContent | ConvertFrom-Json
            } catch {
                Write-Error "无法解析 .gr 配置文件：$($_.Exception.Message)"
                return
            }

            $registeredRepos = @{}
            if ($null -ne $repoConfig) {
                foreach ($prop in $repoConfig.psobject.Properties) {
                    $registeredRepos[$prop.Name] = $prop.Value
                }
            }

            if ($registeredRepos.Count -eq 0) {
                Write-Host "暂无管理的仓库。" -ForegroundColor Gray
                return
            }

            # ========== 模式 1: 显示路径映射 ==========
            if ($showPath) {
                foreach ($repoName in ($registeredRepos.Keys | Sort-Object)) {
                    $displayPath = $registeredRepos[$repoName] -replace [regex]::Escape($HOME), '~'
                    Write-Host "$repoName --> $displayPath"
                }
                return
            }

            # ========== 模式 2: 增强状态列表 ==========
            $repoStatusList = foreach ($repoName in ($registeredRepos.Keys | Sort-Object)) {
                $fullPath = $registeredRepos[$repoName]

                if (-not (Test-Path -Path $fullPath)) {
                    [PSCustomObject]@{
                        Name       = $repoName
                        Branch     = "[无效路径]"
                        StatusIcon = "✗"
                        LatestLog  = ""
                        StatusType = 'error'
                    }
                    continue
                }

                $branchResult = & git -C $fullPath rev-parse --abbrev-ref HEAD 2>$null
                if ($LASTEXITCODE -ne 0) {
                    [PSCustomObject]@{
                        Name       = $repoName
                        Branch     = "[非Git目录]"
                        StatusIcon = "✗"
                        LatestLog  = ""
                        StatusType = 'error'
                    }
                    continue
                }

                $statusOutput = & git -C $fullPath status --porcelain 2>$null
                $statusType = 'clean'
                $statusIcon = "✔"

                if ($LASTEXITCODE -ne 0) {
                    $statusType = 'error'
                    $statusIcon = "✗"
                } else {
                    if ($statusOutput.Count -eq 0) {
                        $statusType = 'clean'
                        $statusIcon = "✔"
                    } elseif ($statusOutput -match '^[\? ]') {
                        $statusType = 'untracked'
                        $statusIcon = "?"
                    } else {
                        $statusType = 'modified'
                        $statusIcon = "●"
                    }
                }

                $logLine = & git -C $fullPath log -1 --oneline --no-color 2>$null
                if ($LASTEXITCODE -ne 0 -or -not $logLine) {
                    $logLine = "<无提交>"
                }

                [PSCustomObject]@{
                    Name       = $repoName
                    Branch     = $branchResult.Trim()
                    StatusIcon = $statusIcon
                    LatestLog  = $logLine.Trim()
                    StatusType = $statusType
                }
            }

            $maxNameLen   = [Math]::Max(($repoStatusList.Name | Measure-Object -Property Length -Maximum).Maximum, 4)
            $maxBranchLen = [Math]::Max(($repoStatusList.Branch | Measure-Object -Property Length -Maximum).Maximum, 6)
            $maxLogLen    = 50

            foreach ($item in $repoStatusList) {
                $truncatedLog = if ($item.LatestLog.Length -gt $maxLogLen) {
                    $item.LatestLog.Substring(0, $maxLogLen - 3) + "..."
                } else {
                    $item.LatestLog
                }

                $namePart   = "{0,-$maxNameLen}" -f $item.Name
                $branchPart = "{0,-$maxBranchLen}" -f $item.Branch
                $logPart    = "{0,-$maxLogLen}" -f $truncatedLog

                $color = switch ($item.StatusType) {
                    'clean'      { 'Green' }
                    'modified'   { 'Yellow' }
                    'untracked'  { 'Magenta' }
                    default      { 'Red' }
                }

                Write-Host $namePart     -ForegroundColor White       -NoNewline
                Write-Host "  "          -NoNewline
                Write-Host $branchPart   -ForegroundColor Cyan        -NoNewline
                Write-Host " "           -NoNewline
                Write-Host $item.StatusIcon -ForegroundColor $color   -NoNewline
                Write-Host "  "          -NoNewline
                Write-Host $logPart      -ForegroundColor DarkGray
            }
        }

        'log' {
            $repos = Get-RepoMap
            if ($repos.Count -eq 0) {
                Write-Host "暂无管理的仓库。" -ForegroundColor Gray
                return
            }

            if ($RemainingArgs.Count -gt 1) {
                Write-Error "用法: gr log [name]"
                return
            }

            $targets = if ($RemainingArgs.Count -eq 1) {
                $name = $RemainingArgs[0]
                if (-not $repos.ContainsKey($name)) {
                    Write-Error "仓库 '$name' 未注册"
                    return
                }
                @(@{ Name = $name; Path = $repos[$name] })
            } else {
                foreach ($key in ($repos.Keys | Sort-Object)) {
                    @{ Name = $key; Path = $repos[$key] }
                }
            }

            foreach ($repo in $targets) {
                Write-Host ("=" * 60) -ForegroundColor Cyan
                Write-Host ">>> $($repo.Name) --> $($repo.Path)" -ForegroundColor Green
                Write-Host ("=" * 60) -ForegroundColor Cyan

                $result = & git -C $repo.Path log --oneline --graph -n 5 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "❌ Git 错误: $($result | Out-String)" -ForegroundColor Red
                } else {
                    $result
                }
                Write-Host ""
            }
        }

        'status' {
            $repos = Get-RepoMap
            if ($repos.Count -eq 0) {
                Write-Host "暂无管理的仓库。" -ForegroundColor Gray
                return
            }

            if ($RemainingArgs.Count -gt 1) {
                Write-Error "用法: gr status [name]"
                return
            }

            $targets = if ($RemainingArgs.Count -eq 1) {
                $name = $RemainingArgs[0]
                if (-not $repos.ContainsKey($name)) {
                    Write-Error "仓库 '$name' 未注册"
                    return
                }
                @(@{ Name = $name; Path = $repos[$name] })
            } else {
                foreach ($key in ($repos.Keys | Sort-Object)) {
                    @{ Name = $key; Path = $repos[$key] }
                }
            }

            foreach ($repo in $targets) {
                Write-Host ("=" * 50) -ForegroundColor Yellow
                Write-Host ">>> $($repo.Name)" -ForegroundColor Magenta
                Write-Host ("=" * 50) -ForegroundColor Yellow

                $result = & git -C $repo.Path status --short 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "❌ Git 错误: $($result | Out-String)" -ForegroundColor Red
                } else {
                    if ([string]::IsNullOrWhiteSpace(($result | Out-String).Trim())) {
                        Write-Host "  (干净)" -ForegroundColor Green
                    } else {
                        $result
                    }
                }
                Write-Host ""
            }
        }

        'run' {
            if ($RemainingArgs.Count -lt 1) {
                Write-Error "用法: gr run <仓库名> <git命令> [参数...]"
                return
            }

            $repoName = $RemainingArgs[0]
            $gitArgs  = $RemainingArgs[1..($RemainingArgs.Count - 1)]

            # 加载配置（复用你的逻辑）
            $configFile = "$HOME\.gr"
            if (-not (Test-Path $configFile)) {
                Write-Error "错误：尚未配置任何仓库。请先使用 'gr add'。"
                return
            }

            $jsonContent = Get-Content $configFile -Raw
            if ([string]::IsNullOrWhiteSpace($jsonContent)) {
                Write-Error "错误：配置文件为空。"
                return
            }

            try {
                $repoConfig = $jsonContent | ConvertFrom-Json
            } catch {
                Write-Error "错误：无法解析 .gr 配置文件：$($_.Exception.Message)"
                return
            }

            $repos = @{}
            foreach ($prop in $repoConfig.psobject.Properties) {
                $repos[$prop.Name] = $prop.Value
            }

            if (-not $repos.ContainsKey($repoName)) {
                Write-Error "错误：仓库 '$repoName' 未被管理。可用仓库：$($repos.Keys -join ', ')"
                return
            }

            $repoPath = $repos[$repoName]
            if (-not (Test-Path $repoPath)) {
                Write-Error "错误：仓库路径不存在：$repoPath"
                return
            }

            # === 新增：打印头部 ===
            $headerLine = "=" * 60
            Write-Host $headerLine -ForegroundColor Gray
            Write-Host ">>> $repoName --> $repoPath" -ForegroundColor Cyan
            Write-Host $headerLine -ForegroundColor Gray

            # 执行 git 命令
            & git -C $repoPath @gitArgs

            # 保留退出码
            $global:LASTEXITCODE = $LASTEXITCODE
        }

        'add' {
            # === 新增：支持 gr add . ===
            if ($RemainingArgs.Count -eq 1 -and $RemainingArgs[0] -eq '.') {
                $currentDir = (Get-Location).Path

                # 检查是否为 Git 仓库
                if (-not (Test-Path (Join-Path $currentDir ".git"))) {
                    Write-Error "错误：当前目录不是 Git 仓库（缺少 .git 目录）"
                    return
                }

                # 自动取目录名
                $name = Split-Path $currentDir -Leaf
                if ([string]::IsNullOrWhiteSpace($name)) {
                    Write-Error "错误：无法从路径获取目录名"
                    return
                }
                $fullPath = $currentDir

                # 加载现有配置
                $repos = Get-RepoMap

                # 检查名称冲突
                if ($repos.ContainsKey($name)) {
                    Write-Host "名称 '$name' 已存在：" -ForegroundColor Yellow -NoNewline
                    Write-Host "$name --> $($repos[$name])" -ForegroundColor Cyan
                    return
                }

                # 保存
                $repos[$name] = $fullPath
                Save-RepoMap $repos
                Write-Host "[SUCCESS] 已添加: $name --> $fullPath" -ForegroundColor Green
                return
            }

            # === 原有逻辑：gr add -name xxx -path yyy ===
            if ($RemainingArgs.Count -ne 4) {
                Write-Error "用法: gr add -name <name> -path <path>"
                Write-Error "   或: gr add . （在 Git 仓库目录中执行）"
                return
            }

            $name = $null
            $path = $null
            for ($i = 0; $i -lt $RemainingArgs.Count; $i += 2) {
                $key = $RemainingArgs[$i]
                $value = $RemainingArgs[$i + 1]
                if ($key -eq '-name') { $name = $value }
                elseif ($key -eq '-path') { $path = $value }
                else { Write-Error "未知参数: '$key'"; return }
            }

            if (-not $name -or -not $path) {
                Write-Error "必须提供 -name 和 -path"
                return
            }

            try {
                $fullPath = Resolve-Path -Path $path -ErrorAction Stop | ForEach-Object Path
            } catch {
                Write-Error "路径无效: $path"
                return
            }

            if (-not (Test-Path (Join-Path $fullPath '.git'))) {
                Write-Error "不是 Git 仓库: $fullPath"
                return
            }

            $repos = Get-RepoMap
            if ($repos.ContainsKey($name)) {
                Write-Host "名称 '$name' 已存在：" -ForegroundColor Yellow -NoNewline
                Write-Host "$name --> $($repos[$name])" -ForegroundColor Cyan
                return
            }

            $repos[$name] = $fullPath
            Save-RepoMap $repos
            Write-Host "[SUCCESS] 已添加: $name --> $fullPath" -ForegroundColor Green
        }

        'rm' {
            if ($RemainingArgs.Count -ne 1) {
                Write-Error "用法: gr rm <name>"
                return
            }
            $name = $RemainingArgs[0]
            $repos = Get-RepoMap
            if (-not $repos.ContainsKey($name)) {
                Write-Error "未找到仓库: '$name'"
                return
            }
            $oldPath = $repos[$name]
            $repos.Remove($name)
            Save-RepoMap $repos
            Write-Host "[SUCCESS] 已移除管理记录: $name --> $oldPath" -ForegroundColor Green
            Write-Host "(注意：磁盘上的仓库文件未被删除)" -ForegroundColor Gray
        }

        'rename' {
            if ($RemainingArgs.Count -ne 2) {
                Write-Error "用法: gr rename <旧名称> <新名称>"
                return
            }

            $oldName = $RemainingArgs[0]
            $newName = $RemainingArgs[1]

            # 校验名称合法性（不能包含特殊字符）
            if ($newName -match '[\\/:*?"<>| ]') {
                Write-Error "仓库名称不能包含 \ / : * ? "" < > | 或空格"
                return
            }

            $configFile = "$HOME\.gr"
            if (-not (Test-Path $configFile)) {
                Write-Error "尚未添加任何仓库，请先使用 'gr add'"
                return
            }

            $jsonContent = Get-Content $configFile -Raw
            if ([string]::IsNullOrWhiteSpace($jsonContent)) {
                Write-Error "配置文件为空"
                return
            }

            try {
                $repoConfig = $jsonContent | ConvertFrom-Json
            } catch {
                Write-Error "配置文件格式错误：$($_.Exception.Message)"
                return
            }

            # 转为哈希表
            $repos = @{}
            foreach ($prop in $repoConfig.psobject.Properties) {
                $repos[$prop.Name] = $prop.Value
            }

            # 检查旧名称是否存在
            if (-not $repos.ContainsKey($oldName)) {
                Write-Error "错误：仓库 '$oldName' 未被管理"
                return
            }

            # 检查新名称是否已存在
            if ($repos.ContainsKey($newName)) {
                Write-Error "错误：仓库 '$newName' 已存在"
                return
            }

            # 执行重命名：移除旧键，添加新键
            $path = $repos[$oldName]
            $repos.Remove($oldName)
            $repos[$newName] = $path

            # 写回 .gr 文件（按字母排序，美观）
            $sortedRepos = [ordered]@{}
            foreach ($key in ($repos.Keys | Sort-Object)) {
                $sortedRepos[$key] = $repos[$key]
            }

            try {
                $sortedRepos | ConvertTo-Json -Depth 99 | Set-Content $configFile -Encoding UTF8
                Write-Host "✓ 仓库名称已从 '$oldName' 改为 '$newName'" -ForegroundColor Green
            } catch {
                Write-Error "写入配置文件失败：$($_.Exception.Message)"
            }
        }

        'cd' {
            if ($RemainingArgs.Count -ne 1) {
                Write-Error "用法: gr cd <name>"
                return
            }
            $name = $RemainingArgs[0]
            $repos = Get-RepoMap
            if (-not $repos.ContainsKey($name)) {
                Write-Error "未找到仓库: $name"
                return
            }
            Set-Location -Path $repos[$name]
        }

        'open' {
            if ($RemainingArgs.Count -ne 1) {
                Write-Error "用法: gr open <仓库名>"
                return
            }

            $repoName = $RemainingArgs[0]
            $repos = Get-RepoMap

            if (-not $repos.ContainsKey($repoName)) {
                $allNames = @($repos.Keys | Sort-Object)
                if ($allNames.Count -le 6) {
                    $displayNames = $allNames -join ', '
                } else {
                    $displayNames = ($allNames[0..4] -join ', ') + ', ...'
                }
                Write-Error @"
错误：仓库 '$repoName' 未被管理。
可用仓库（前5个）：$displayNames
👉 使用 'gr list' 查看简要列表，或 'gr list -showpath' 查看路径详情。
"@
                return
            }

            $repoPath = $repos[$repoName]
            if (-not (Test-Path $repoPath)) {
                Write-Error "错误：仓库路径不存在：$repoPath"
                return
            }

            Write-Host "正在打开: $repoPath" -ForegroundColor Green
            Invoke-Item $repoPath
        }

        'info' {
            if ($RemainingArgs.Count -ne 1) {
                Write-Error "用法: gr info <仓库名>"
                return
            }

            $repoName = $RemainingArgs[0]
            $repos = Get-RepoMap

            if (-not $repos.ContainsKey($repoName)) {
                $allNames = @($repos.Keys | Sort-Object)
                if ($allNames.Count -le 6) {
                    $displayNames = $allNames -join ', '
                } else {
                    $displayNames = ($allNames[0..4] -join ', ') + ', ...'
                }
                Write-Error @"
错误：仓库 '$repoName' 未被管理。
可用仓库（前5个）：$displayNames
👉 使用 'gr list' 查看简要列表，或 'gr list -showpath' 查看路径详情。
"@
                return
            }

            $repoPath = $repos[$repoName]
            if (-not (Test-Path $repoPath)) {
                Write-Error "错误：仓库路径不存在：$repoPath"
                return
            }

            # === 显示详细信息 ===
            $headerLine = "=" * 60
            Write-Host $headerLine -ForegroundColor Gray
            Write-Host ">>> $repoName" -ForegroundColor Cyan
            Write-Host $headerLine -ForegroundColor Gray

            Write-Host "路径        : $repoPath"

            if (-not (Test-Path (Join-Path $repoPath ".git"))) {
                Write-Host "状态        : ❌ 不是 Git 仓库" -ForegroundColor Red
                return
            }

            # 当前分支
            $branch = & git -C $repoPath rev-parse --abbrev-ref HEAD 2>$null
            if ($LASTEXITCODE -ne 0) { $branch = "<unknown>" }

            # 远程跟踪分支
            $tracking = & git -C $repoPath for-each-ref --format='%(upstream:short)' refs/heads/$branch 2>$null
            if ($tracking) {
                $branchDisplay = "$branch (跟踪 $tracking)"
            } else {
                $branchDisplay = "$branch (无远程跟踪)"
            }
            Write-Host "分支        : $branchDisplay"

            # 远程 URL
            $remoteUrl = & git -C $repoPath remote get-url origin 2>$null
            if (-not $remoteUrl) { $remoteUrl = "<未设置 origin>" }
            Write-Host "远程 URL    : $remoteUrl"

            # 工作区状态
            $statusPorcelain = & git -C $repoPath status --porcelain 2>$null
            if ($null -eq $statusPorcelain -or $statusPorcelain.Count -eq 0) {
                $statusText = "干净"
                $statusColor = "Green"
            } else {
                $modified = @($statusPorcelain | Where-Object { $_.StartsWith('M') }).Count
                $untracked = @($statusPorcelain | Where-Object { $_.StartsWith('?') }).Count
                $deleted = @($statusPorcelain | Where-Object { $_.StartsWith('D') }).Count

                $parts = @()
                if ($modified -gt 0) { $parts += "${modified}个修改" }
                if ($untracked -gt 0) { $parts += "${untracked}个未跟踪" }
                if ($deleted -gt 0) { $parts += "${deleted}个删除" }
                $statusText = "有变更 (" + ($parts -join ", ") + ")"
                $statusColor = "Yellow"
            }
            Write-Host "状态        : $statusText" -ForegroundColor $statusColor

            # 最新提交
            $logLine = & git -C $repoPath log -1 --pretty=format:"%h|%ad|%an <%ae>|%s" --date=iso 2>$null
            if ($logLine) {
                $parts = $logLine -split '\|', 4
                $commitHash = $parts[0]
                $commitDate = $parts[1].Substring(0, 19) -replace 'T', ' '
                $author     = $parts[2]
                $subject    = $parts[3]

                Write-Host "最新提交    : $commitHash ($commitDate)"
                Write-Host "作者        : $author"
                Write-Host "提交消息    : $subject"
            } else {
                Write-Host "最新提交    : <无提交记录>"
            }
        }

        default {
            Write-Error "未知子命令: '$Command'。使用 'gr help' 查看帮助。"
        }
    }
}