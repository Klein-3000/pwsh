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
            $repos = Get-RepoMap
            if ($repos.Count -eq 0) {
                Write-Host "暂无管理的仓库。" -ForegroundColor Gray
                return
            }
            $sortedNames = $repos.Keys | Sort-Object
            foreach ($name in $sortedNames) {
                Write-Host "$name --> $($repos[$name])"
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