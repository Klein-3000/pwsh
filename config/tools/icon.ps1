function global:icon {
    [CmdletBinding(DefaultParameterSetName = 'Set')]
    param(
        [Parameter(ParameterSetName = '__help', Mandatory)][switch]$Help,
        [Parameter(ParameterSetName = 'List', Mandatory)][switch]$List,
        [Parameter(ParameterSetName = 'Doctor', Mandatory)][string]$Doctor,
        [Parameter(ParameterSetName = 'Set', Mandatory)][ValidatePattern('^[A-Z]$')][string]$Drive,
        [Parameter(ParameterSetName = 'Set', Mandatory)][string]$Icon,
        [Parameter(ParameterSetName = 'Refresh', Mandatory)][ValidateSet('ie','explorer')][string]$Refresh = 'ie',
        [Parameter(ParameterSetName = 'Default')][switch]$Default,
        [Parameter(ParameterSetName = 'Default')][ValidatePattern('^[A-Z]$')][string]$ForDrive,
        [Parameter(ParameterSetName = 'Version')][switch]$Version
    )

    # ========== 嵌套函数：必须放在 param() 之后 ==========
    function Test-ValidIcoFile {
        param([string]$Path)
        if (-not (Test-Path $Path -PathType Leaf)) { return $false }
        try {
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                $bytes = Get-Content -Path $Path -AsByteStream -ReadCount 0 -TotalCount 6
            } else {
                $bytes = Get-Content -Path $Path -Encoding Byte -ReadCount 0 -TotalCount 6
            }
            if ($bytes.Count -lt 6) { return $false }
            if ($bytes[0] -eq 0 -and $bytes[1] -eq 0 -and
                $bytes[2] -eq 1 -and $bytes[3] -eq 0) {
                $iconCount = [System.BitConverter]::ToUInt16($bytes[4..5], 0)
                return $iconCount -ge 1
            }
        } catch {}
        return $false
    }

    # ========== 主逻辑开始 ==========
    if ($PSCmdlet.ParameterSetName -eq '__help' -or $Help) {
        Write-Host @"
USAGE:
    icon -Drive <盘符> -Icon <图标路径>
    icon -List
    icon -Doctor <图标路径>
    icon -Refresh [ie|explorer]
    icon -Default [-ForDrive <盘符>]
    icon -Version
    icon -Help
DESCRIPTION:
    管理 Windows 固定驱动器图标。
"@ -ForegroundColor Cyan
        return
    }

    # 新增：-Version 参数支持
    if ($PSCmdlet.ParameterSetName -eq 'Version') {
        Write-Host "icon v0.0.2"
        return
    }

    $BasePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons"

    if ($PSCmdlet.ParameterSetName -eq 'Doctor') {
        if (Test-ValidIcoFile $Doctor) {
            Write-Host "✅ '$Doctor' 是有效的 Windows .ico 文件。" -ForegroundColor Green
        } else {
            Write-Host "❌ '$Doctor' 不是有效的 .ico 文件。" -ForegroundColor Red
        }
        return
    }

    if ($PSCmdlet.ParameterSetName -eq 'List') {
        # 获取所有本地磁盘盘符（大写）
        $allDrives = (Get-PSDrive -PSProvider FileSystem).Name.ToUpper() | Sort-Object -Unique

        # 获取已自定义图标的盘符（从注册表读取，转为大写）
        $customDriveMap = @{}
        if (Test-Path $BasePath) {
            $subKeys = Get-ChildItem -Path $BasePath -ErrorAction SilentlyContinue
            foreach ($key in $subKeys) {
                if ($key.PSIsContainer) {
                    $driveLetter = $key.PSChildName.ToUpper()
                    # 尝试读取图标路径
                    $iconPath = $null
                    $defaultIconPath = Join-Path $key.PSPath "DefaultIcon"
                    if (Test-Path $defaultIconPath) {
                        $prop = Get-ItemProperty -Path $defaultIconPath -Name "(default)" -ErrorAction SilentlyContinue
                        if ($prop -and $prop.'(default)') {
                            $iconPath = $prop.'(default)'
                        }
                    }
                    $customDriveMap[$driveLetter] = $iconPath
                }
            }
        }

        Write-Host "📌 当前磁盘图标状态：" -ForegroundColor Cyan
        foreach ($d in $allDrives) {
            if ($customDriveMap.ContainsKey($d)) {
                $iconVal = $customDriveMap[$d]
                if ($iconVal) {
                    Write-Host "  $d : $iconVal" -ForegroundColor Yellow
                } else {
                    Write-Host "  $d : ⚠️ 已设置但图标路径为空" -ForegroundColor DarkYellow
                }
            } else {
                Write-Host "  $d : (默认系统图标)" -ForegroundColor Gray
            }
        }

        # 额外：显示注册表中存在但非当前文件系统盘符的项（如 Z: 映射网络盘等）
        $extraDrives = $customDriveMap.Keys | Where-Object { $allDrives -notcontains $_ }
        if ($extraDrives) {
            Write-Host "`n📎 其他自定义图标（非本地磁盘）：" -ForegroundColor Magenta
            foreach ($ed in $extraDrives | Sort-Object) {
                $val = $customDriveMap[$ed]
                $displayText = if ($val -and $val.Trim()) { $val } else { '⚠️ 路径为空' }
                Write-Host "  $ed : $displayText" -ForegroundColor Magenta
            }
        }

        return
    }

    # 权限检查
    if (@('Set','Default') -contains $PSCmdlet.ParameterSetName) {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($id)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Error "❌ 需要以管理员身份运行。"
            return
        }
    }

    if ($PSCmdlet.ParameterSetName -eq 'Set') {
        if (-not (Test-ValidIcoFile $Icon)) {
            Write-Error "图标文件 '$Icon' 不符合 Windows .ico 格式要求。"
            return
        }
        $regPath = Join-Path $BasePath "$Drive\DefaultIcon"
        New-Item $regPath -Force | Out-Null
        Set-ItemProperty $regPath '(default)' $Icon
        Write-Host "✅ 已设置 $Drive 盘图标。" -ForegroundColor Green
        & "$env:SystemRoot\System32\ie4uinit.exe" -show | Out-Null
        Write-Host "🔄 图标缓存已刷新。" -ForegroundColor Yellow
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Refresh') {
        if ($Refresh -eq 'ie') {
            & "$env:SystemRoot\System32\ie4uinit.exe" -show | Out-Null
            Write-Host "🔄 使用 ie4uinit.exe 刷新。" -ForegroundColor Yellow
        } else {
            Stop-Process -Name explorer -Force
            Write-Host "🔄 资源管理器已重启。" -ForegroundColor Yellow
        }
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Default') {
        $target = if ($ForDrive) { Join-Path $BasePath $ForDrive } else { $BasePath }
        if (Test-Path $target) {
            Remove-Item $target -Recurse -Force
            $msg = if ($ForDrive) { "已恢复 $ForDrive 盘默认图标。" } else { "已清除所有自定义图标。" }
            Write-Host "✅ $msg" -ForegroundColor Green
        } else {
            Write-Host "ℹ️  无自定义图标需要恢复。" -ForegroundColor Gray
        }
        & "$env:SystemRoot\System32\ie4uinit.exe" -show | Out-Null
        Write-Host "🔄 图标缓存已刷新。" -ForegroundColor Yellow
    }
}

# ========== 自动执行逻辑（用于 .exe 封装）==========
if ($MyInvocation.InvocationName -ne '.') {
    # 解析命令行参数为哈希表（支持开关和带值参数）
    $params = @{}
    $i = 0
    while ($i -lt $args.Count) {
        $arg = $args[$i]
        if ($arg -match '^-(\w+)$') {
            $paramName = $matches[1]
            # 检查是否为有效参数（可选：增强健壮性）
            if ($i + 1 -lt $args.Count -and $args[$i+1] -notmatch '^-.') {
                $params[$paramName] = $args[$i+1]
                $i += 2
            } else {
                $params[$paramName] = $true
                $i++
            }
        } else {
            Write-Host "❌ 无效参数: $arg" -ForegroundColor Red
            exit 1
        }
    }

    try {
        icon @params
    } catch {
        Write-Host "❌ 错误: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# 使用 ps2exe 打包为 exe
# Invoke-ps2exe -InputFile .\icon.ps1 -OutputFile icon.exe -IconFile .\icon.ico