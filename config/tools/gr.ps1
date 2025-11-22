function global:gr {
    param(
        [Parameter(Position = 0)]
        [string]$Command,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$RemainingArgs
    )

    # ========== 特殊处理：顶层 -v / --version ==========
    if ($Command -and ($Command -eq '-v' -or $Command -eq '--version' -or $Command -eq '-version')) {
        Write-Host "gr v0.0.1"
        return
    }

    # ========== 缺少子命令 ==========
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
    gr rm -name <name>
    gr list
    gr list -verbose   (or -v)
    gr cd <name>
    gr -v | --version
    gr help
DESCRIPTION:
    管理多个 Git 仓库的快捷访问。
"@ -ForegroundColor Cyan
        }

        'list' {
            # ✅ 不管有没有参数，一律输出完整路径格式
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

        'add' {
            if ($RemainingArgs.Count -ne 4) {
                Write-Error "用法: gr add -name <name> -path <path>"
                return
            }

            # 手动配对参数（允许顺序任意）
            $name = $null
            $path = $null

            for ($i = 0; $i -lt $RemainingArgs.Count; $i += 2) {
                $key = $RemainingArgs[$i]
                $value = $RemainingArgs[$i + 1]
                if ($key -eq '-name') {
                    $name = $value
                } elseif ($key -eq '-path') {
                    $path = $value
                } else {
                    Write-Error "未知参数: '$key'"
                    return
                }
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
            if ($RemainingArgs.Count -ne 2 -or $RemainingArgs[0] -ne '-name') {
                Write-Error "用法: gr rm -name <name>"
                return
            }
            $name = $RemainingArgs[1]
            $repos = Get-RepoMap
            if (-not $repos.ContainsKey($name)) {
                Write-Error "未找到仓库: $name"
                return
            }
            $oldPath = $repos[$name]
            $repos.Remove($name)
            Save-RepoMap $repos
            Write-Host "[SUCCESS] 已移除: $name --> $oldPath" -ForegroundColor Green
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