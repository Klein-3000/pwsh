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
        Write-Output "gr version 0.0.1"
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
    gr list
    gr log [name]
    gr status [name]
    gr cd <name>
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

                $result = & git -C $repo.Path log --oneline --graph --all 2>&1
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

        'add' {
            if ($RemainingArgs.Count -ne 4) {
                Write-Error "用法: gr add -name <name> -path <path>"
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

        default {
            Write-Error "未知子命令: '$Command'。使用 'gr help' 查看帮助。"
        }
    }
}