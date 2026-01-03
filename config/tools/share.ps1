function global:share {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [ValidateSet('help', 'version', 'add', 'rm', 'list', 'start', 'stop', 'restart', 'edit', 'amend', 'enable', 'disable')]
        [string]$Command,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$RemainingArgs
    )

    # 内部辅助函数：读取配置
    function Get-ShareConfig {
        $configPath = "$env:USERPROFILE\.share"
        if (Test-Path $configPath) {
            try {
                $content = Get-Content $configPath -Raw
                if ([string]::IsNullOrWhiteSpace($content)) {
                    return @()
                }
                return $content | ConvertFrom-Json
            } catch {
                Write-Error "Failed to parse ~/.share as JSON: $_"
                return @()
            }
        } else {
            return @()
        }
    }

    # 内部辅助函数：写入配置
    function Set-ShareConfig {
        param([object[]]$Config)
        $configPath = "$env:USERPROFILE\.share"
        $Config | ConvertTo-Json -Depth 3 | Set-Content $configPath
    }

    # 内部辅助函数：校验是否为盘符根目录
    function Test-IsDriveRoot {
        param([string]$Path)
        $resolved = Resolve-Path $Path -ErrorAction SilentlyContinue
        if (-not $resolved) { return $false }
        $providerPath = $resolved.ProviderPath
        return $providerPath -match '^[A-Za-z]:\\$'
    }

    # 内部辅助函数：校验共享名是否合法（Windows SMB 共享名规则）
    function Test-ValidShareName {
        param([string]$Name)
        if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
        if ($Name.Length -gt 80) { return $false }
        if ($Name -match '[\\/:*?"<>|]') { return $false }
        if ($Name.EndsWith('.') -or $Name.EndsWith(' ')) { return $false }
        $reserved = @('CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
                      'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')
        if ($reserved -contains $Name.ToUpper()) { return $false }
        return $true
    }
function Get-ShareConfig {
    $path = "$env:USERPROFILE\.share"
    if (-not (Test-Path $path)) {
        return @()
    }
    $content = Get-Content $path -Raw
    $content | ConvertFrom-Json
}
function Set-ShareConfig($config) {
    $path = "$env:USERPROFILE\.share"
    $json = $config | ConvertTo-Json -Depth 10
    $json | Out-File $path -Encoding UTF8 -Force
}
function Test-UserOrGroupExists {
    param([string]$Identity)

    if ([string]::IsNullOrWhiteSpace($Identity)) { return $false }

    # Allow 'everyone' explicitly (not a real account, but valid for SMB)
    if ($Identity -eq 'everyone') { return $true }

    try {
        $ntAccount = [System.Security.Principal.NTAccount]::new($Identity)
        $null = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
        return $true
    } catch {
        return $false
    }
}

    switch ($Command) {
'help' {
    $helpText = @"

share - Manage SMB shares via configuration file ~/.share

Usage:
  share help                    Show this help message
  share version                 Show version
  share list                    List all configured shares and status
  share add -name <name> -path <path> [-permission <user>:<R|F>]
  share add .                   Add current directory as a share (default: everyone:R)
  share rm <name>               Remove a share from config (does NOT delete files)
  share start <name>            Start a share (create SMB share)
  share stop <name>             Stop a share (remove SMB share)
  share restart <name>          Stop and restart a share (apply amended permissions)
  share amend <name> <user>:<R|F> Update permission for a share
  share enable                  Start ALL configured shares
  share disable                 Stop ALL currently active shares managed by this tool
  share edit                    Open ~/.share in default editor
"@

    Write-Host $helpText -ForegroundColor Cyan
}

        'version' {
            Write-Host "0.0.1"
        }

        'add' {
            # 支持两种调用方式：
            #   share add -name X -path Y [-permission U:P]
            #   share add . [-permission U:P]   → 使用当前目录

            $paramsWithValue = @('name', 'path', 'permission')
            $params = @{}
            $index = 0
            $useCurrentDir = $false

            # 特殊处理 "share add ."
            if ($RemainingArgs.Count -eq 1 -and $RemainingArgs[0] -eq '.') {
                $useCurrentDir = $true
            } else {
                # 常规参数解析
                while ($index -lt $RemainingArgs.Count) {
                    $arg = $RemainingArgs[$index]
                    if ($arg -match '^-([a-zA-Z]+)$') {
                        $key = $matches[1]

                        if ($paramsWithValue -contains $key) {
                            $index++
                            if ($index -ge $RemainingArgs.Count -or $RemainingArgs[$index] -match '^-.+') {
                                Write-Error "Missing value for parameter '$arg'"
                                return
                            }
                            $params[$key] = $RemainingArgs[$index]
                            $index++
                        } else {
                            Write-Error "Unknown parameter: $arg"
                            return
                        }
                    } else {
                        Write-Error "Unexpected argument: $arg"
                        return
                    }
                }

                # 必须提供 name 和 path
                if (-not $params.ContainsKey('name') -or -not $params.ContainsKey('path')) {
                    Write-Error "Usage:`n  share add -name <name> -path <path> [-permission <user>:<R|F>]`n  share add . [-permission <user>:<R|F>]"
                    return
                }
            }

            # 获取 name 和 path
            if ($useCurrentDir) {
                $currentItem = Get-Item .
                $shareName = $currentItem.Name
                $sharePath = $currentItem.FullName
            } else {
                $shareName = $params['name']
                $sharePath = $params['path']
            }

            # 获取 permission，默认为 everyone:R
            $permission = if ($params.ContainsKey('permission')) {
                $params['permission']
            } else {
                'everyone:R'
            }

            # 校验 permission 格式: 必须为 "user:R" 或 "user:F"
            # 允许字符：字母、数字、下划线、点、连字符、反斜杠（用于域）
            if ($permission -notmatch '^[\w\\.-]+:[RF]$') {
                Write-Error "Invalid permission format: '$permission'. Expected '<user>:R' or '<user>:F' (e.g., 'alice:R', 'everyone:F')."
                return
            }

            # 校验 share name
            if (-not (Test-ValidShareName $shareName)) {
                Write-Error "Invalid share name '$shareName'. Share names must follow Windows naming rules."
                return
            }

            # 校验路径
            if (-not (Test-Path $sharePath)) {
                Write-Error "Path does not exist: $sharePath"
                return
            }
            if (Test-IsDriveRoot $sharePath) {
                Write-Error "Sharing drive root (e.g., C:\) is not allowed."
                return
            }

            # 检查重名
            $config = @(Get-ShareConfig)
            if ($config | Where-Object { $_.PSObject.Properties.Name -contains 'name' -and $_.name -eq $shareName }) {
                Write-Error "Share name '$shareName' already exists in config."
                return
            }

            # 获取 permission，默认为 everyone:R
            $permission = if ($params.ContainsKey('permission')) {
                $params['permission']
            } else {
                'everyone:R'
            }

            # 校验 permission 格式
            if ($permission -notmatch '^([\w\\.-]+):[RF]$') {
                Write-Error "Invalid permission format: '$permission'. Expected '<user>:R' or '<user:F' (e.g., 'alice:R', 'everyone:F')."
                return
            }
            $principal = $matches[1]

            # 🔍 新增：验证用户/组是否存在
            if (-not (Test-UserOrGroupExists $principal)) {
                Write-Error "User or group '$principal' does not exist. Built-in groups (e.g., 'Users') and 'everyone' are allowed."
                return
            }

            # 创建新条目
            $newEntry = [PSCustomObject]@{
                name       = $shareName
                path       = (Resolve-Path $sharePath).ProviderPath
                permission = $permission
            }

            # 保存
            $config += $newEntry
            Set-ShareConfig $config

            Write-Host "Added share '$shareName' -> $($newEntry.path) [$($newEntry.permission)]" -ForegroundColor Green
        }

        'rm' {
            if ($RemainingArgs.Count -ne 1) {
                Write-Error "Usage: share rm <name>"
                return
            }

            $name = $RemainingArgs[0]

            # 读取配置
            $config = @(Get-ShareConfig)
            if ($config.Count -eq 0) {
                Write-Error "No shares configured."
                return
            }

            # 查找并移除目标项
            $filtered = $config | Where-Object {
                $_.PSObject.Properties.Name -contains 'name' -and $_.name -ne $name
            }

            # 如果没有变化（即没找到）
            if ($filtered.Count -eq $config.Count) {
                Write-Error "Share '$name' not found in config."
                return
            }

            # 保存新配置
            try {
                Set-ShareConfig $filtered
                Write-Host "Removed share '$name'" -ForegroundColor Green
            } catch {
                Write-Error "Failed to save configuration: $_"
                return
            }
        }

        'list' {
            $config = @(Get-ShareConfig)
            if ($config.Count -eq 0) {
                Write-Host "⚠️  暂无已配置的共享。" -ForegroundColor Yellow
                return
            }

            # 获取当前活跃的 SMB 共享名称集合
            $activeShares = @{}
            try {
                $smbShares = Get-SmbShare -ErrorAction Stop
                foreach ($s in $smbShares) {
                    $activeShares[$s.Name] = $true
                }
            } catch {
                # 如果权限不足，静默忽略（不影响配置显示）
            }

            # 构建输出对象
            $output = foreach ($item in $config) {
                # 跳过无效项
                if (-not $item.PSObject.Properties.Name -contains 'name' -or [string]::IsNullOrWhiteSpace($item.name)) {
                    continue
                }

                $status = if ($activeShares.ContainsKey($item.name)) { "已共享" } else { "未共享" }

                # 直接使用 permission 字段（如 "lenovo:F"）
                $permission = if ($item.PSObject.Properties.Name -contains 'permission') {
                    $item.permission
                } else {
                    "Invalid"
                }

                [PSCustomObject]@{
                    Name       = $item.name
                    Path       = $item.path
                    Status     = $status
                    Permission = $permission
                }
            }

            if ($output.Count -eq 0) {
                Write-Host "⚠️  无有效共享配置。" -ForegroundColor Yellow
                return
            }

            # 输出表格
            $output | Format-Table -AutoSize

            # 统计信息
            $total = $output.Count
            $activeCount = ($output | Where-Object { $_.Status -eq "已共享" }).Count

            Write-Host "📊 总计: $total 个共享 | " -NoNewline -ForegroundColor Cyan
            Write-Host "✅ 已共享: $activeCount" -ForegroundColor Green
        }

        'start' {
            if ($RemainingArgs.Count -ne 1) {
                Write-Error "Usage: share start <name>"
                return
            }
            $shareName = $RemainingArgs[0]

            $config = @(Get-ShareConfig)
            $entry = $config | Where-Object {
                $_.PSObject.Properties.Name -contains 'name' -and $_.name -eq $shareName
            } | Select-Object -First 1

            if (-not $entry) {
                Write-Error "Share '$shareName' not found in ~/.share"
                return
            }

            if (-not (Test-Path $entry.path)) {
                Write-Error "Share path does not exist: $($entry.path)"
                return
            }
            if (Test-IsDriveRoot $entry.path) {
                Write-Error "Cannot share drive root: $($entry.path)"
                return
            }

            # 解析 permission: 必须为 "User:R" 或 "User:F"
            if ($entry.permission -notmatch '^(.+?):([RF])$') {
                Write-Error "Invalid permission format in config: '$($entry.permission)'. Expected 'User:R' or 'User:F'"
                return
            }
            $principal = $matches[1].Trim()
            $accessType = $matches[2]

            # 准备参数
            $params = @{
                Name = $shareName
                Path = $entry.path
            }

            if ($accessType -eq 'R') {
                $params.ReadAccess = @($principal)
            } else {
                $params.FullAccess = @($principal)
            }

            # 检查是否已存在
            if (Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue) {
                Write-Error "SMB share '$shareName' already exists. Use 'share stop $shareName' first."
                return
            }

            try {
                New-SmbShare @params -ErrorAction Stop
                Write-Host "Started SMB share '$shareName' at $($entry.path) for account '$principal'" -ForegroundColor Green
            } catch {
                Write-Error "Failed to start share '$shareName': $_"
            }
        }

        'stop' {
            if ($RemainingArgs.Count -ne 1) {
                Write-Error "Usage: share stop <name>"
                return
            }
            $shareName = $RemainingArgs[0]

            try {
                $existing = Get-SmbShare -Name $shareName -ErrorAction Stop
                if (-not $existing) {
                    Write-Error "SMB share '$shareName' is not active."
                    return
                }
                Remove-SmbShare -Name $shareName -Force -ErrorAction Stop
                Write-Host "Stopped SMB share '$shareName'" -ForegroundColor Green
            } catch {
                Write-Error "Failed to stop share '$shareName': $_"
            }
        }

        'restart' {
            if ($RemainingArgs.Count -ne 1) {
                Write-Error "Usage: share restart <name>"
                return
            }

            $shareName = $RemainingArgs[0]

            # 读取配置
            $config = @(Get-ShareConfig)
            $entry = $config | Where-Object {
                $_.PSObject.Properties.Name -contains 'name' -and $_.name -eq $shareName
            } | Select-Object -First 1

            if (-not $entry) {
                Write-Error "Share '$shareName' not found in config (~/.share)."
                return
            }

            # 校验路径
            if (-not (Test-Path $entry.path)) {
                Write-Error "Share path does not exist: $($entry.path)"
                return
            }
            if (Test-IsDriveRoot $entry.path) {
                Write-Error "Cannot share drive root: $($entry.path)"
                return
            }

            # 解析 permission
            if ($entry.permission -notmatch '^(.+?):([RF])$') {
                Write-Error "Invalid permission format in config: '$($entry.permission)'. Expected 'user:R' or 'user:F'."
                return
            }
            $principal = $matches[1].Trim()
            $accessType = $matches[2]

            # 第一步：停止（如果存在）
            if (Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue) {
                try {
                    Remove-SmbShare -Name $shareName -Force -ErrorAction Stop
                    Write-Host "⏹️  Stopped existing share '$shareName'" -ForegroundColor Magenta
                } catch {
                    Write-Error "Failed to stop share '$shareName': $_"
                    return
                }
            }

            # 第二步：启动新共享
            $params = @{
                Name = $shareName
                Path = $entry.path
            }
            if ($accessType -eq 'R') {
                $params.ReadAccess = @($principal)
            } else {
                $params.FullAccess = @($principal)
            }

            try {
                New-SmbShare @params -ErrorAction Stop | Out-Null
                Write-Host "✅ Restarted share '$shareName' with permission '$($entry.permission)'" -ForegroundColor Green
            } catch {
                Write-Error "Failed to restart share '$shareName': $_"
            }
        }

        'edit' {
            $configPath = "$env:USERPROFILE\.share"
            if (-not (Test-Path $configPath)) {
                # 创建空配置
                @() | ConvertTo-Json -Depth 3 | Set-Content $configPath
            }

            # 使用 EDITOR 或 fallback 到 notepad
            if ($env:EDITOR) {
                & $env:EDITOR $configPath
            } else {
                notepad $configPath
            }
        }

        'amend' {
            if ($RemainingArgs.Count -ne 2) {
                Write-Error "Usage: share amend <name> <user>:<R|F>"
                return
            }

            $shareName = $RemainingArgs[0]
            $newPermission = $RemainingArgs[1]

            # 校验 permission 格式
            if ($newPermission -notmatch '^([\w\\.-]+):[RF]$') {
                Write-Error "Invalid permission format: '$newPermission'. Expected '<user>:R' or '<user>:F' (e.g., 'alice:R', 'everyone:F')."
                return
            }
            $principal = $matches[1]

            # 🔍 新增：校验用户或组是否存在
            if (-not (Test-UserOrGroupExists $principal)) {
                Write-Error "User or group '$principal' does not exist on this system. Use 'net user', 'compmgmt.msc', or built-in groups (e.g., 'Users', 'everyone')."
                return
            }

            # 读取配置
            $config = @(Get-ShareConfig)
            if ($config.Count -eq 0) {
                Write-Error "No shares configured in ~/.share"
                return
            }

            # 查找目标项
            $targetIndex = -1
            for ($i = 0; $i -lt $config.Count; $i++) {
                if ($config[$i].PSObject.Properties.Name -contains 'name' -and
                    $config[$i].name -eq $shareName) {
                    $targetIndex = $i
                    break
                }
            }

            if ($targetIndex -eq -1) {
                Write-Error "Share '$shareName' not found in config."
                return
            }

            # 更新 permission
            $oldPermission = $config[$targetIndex].permission
            $config[$targetIndex] = [PSCustomObject]@{
                name       = $config[$targetIndex].name
                path       = $config[$targetIndex].path
                permission = $newPermission
            }

            # 保存
            Set-ShareConfig $config

            Write-Host "✅ Updated share '$shareName': '$oldPermission' → '$newPermission'" -ForegroundColor Green

            # 提示重启
            if (Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue) {
                Write-Host "💡 Note: The share is currently active. Run 'share restart $shareName' to apply changes." -ForegroundColor Cyan
            }
        }  

        'enable' {
            $config = @(Get-ShareConfig)
            if ($config.Count -eq 0) {
                Write-Host "⚠️  No shares configured in ~/.share" -ForegroundColor Yellow
                return
            }

            $success = 0
            $failed = 0

            foreach ($item in $config) {
                if (-not $item.PSObject.Properties.Name -contains 'name' -or [string]::IsNullOrWhiteSpace($item.name)) {
                    continue
                }

                # 跳过路径不存在的
                if (-not (Test-Path $item.path)) {
                    Write-Host "❌ Skipped '$($item.name)': path not found: $($item.path)" -ForegroundColor Red
                    $failed++
                    continue
                }

                # 跳过 drive root
                if (Test-IsDriveRoot $item.path) {
                    Write-Host "❌ Skipped '$($item.name)': sharing drive root is not allowed." -ForegroundColor Red
                    $failed++
                    continue
                }

                # 解析 permission
                if ($item.permission -notmatch '^(.+?):([RF])$') {
                    Write-Host "❌ Skipped '$($item.name)': invalid permission format: '$($item.permission)'" -ForegroundColor Red
                    $failed++
                    continue
                }
                $principal = $matches[1].Trim()
                $accessType = $matches[2]

                # 检查是否已存在
                if (Get-SmbShare -Name $item.name -ErrorAction SilentlyContinue) {
                    Write-Host "⏭️  Skipped '$($item.name)': already active." -ForegroundColor DarkGray
                    $success++  # 视为已启用
                    continue
                }

                # 准备参数
                $params = @{
                    Name = $item.name
                    Path = $item.path
                }
                if ($accessType -eq 'R') {
                    $params.ReadAccess = @($principal)
                } else {
                    $params.FullAccess = @($principal)
                }

                try {
                    New-SmbShare @params -ErrorAction Stop | Out-Null
                    Write-Host "✅ Started '$($item.name)' for '$principal'" -ForegroundColor Green
                    $success++
                } catch {
                    Write-Host "❌ Failed to start '$($item.name)': $_" -ForegroundColor Red
                    $failed++
                }
            }

            Write-Host "`n📊 Enable Summary: $success succeeded, $failed failed." -ForegroundColor Cyan
        }   

        'disable' {
            $config = @(Get-ShareConfig)
            if ($config.Count -eq 0) {
                Write-Host "⚠️  No shares configured. Nothing to disable." -ForegroundColor Yellow
                return
            }

            # 构建配置中的名称集合（用于识别“属于本工具”的共享）
            $managedNames = @{}
            foreach ($item in $config) {
                if ($item.PSObject.Properties.Name -contains 'name') {
                    $managedNames[$item.name] = $true
                }
            }

            # 获取当前所有 SMB 共享
            try {
                $currentShares = Get-SmbShare -ErrorAction Stop
            } catch {
                Write-Error "Failed to query SMB shares (run as administrator?): $_"
                return
            }

            $toStop = @($currentShares | Where-Object { $managedNames.ContainsKey($_.Name) })
            if ($toStop.Count -eq 0) {
                Write-Host "ℹ️  No active shares managed by this tool." -ForegroundColor Cyan
                return
            }

            $success = 0
            $failed = 0

            foreach ($share in $toStop) {
                try {
                    Remove-SmbShare -Name $share.Name -Force -ErrorAction Stop
                    Write-Host "⏹️  Stopped '$($share.Name)'" -ForegroundColor Magenta
                    $success++
                } catch {
                    Write-Host "❌ Failed to stop '$($share.Name)': $_" -ForegroundColor Red
                    $failed++
                }
            }

            Write-Host "`n📊 Disable Summary: $success stopped, $failed failed." -ForegroundColor Cyan
        }

        default {
            Write-Error "Unknown subcommand: $Command"
        }
    }
}