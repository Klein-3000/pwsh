# iconctl.ps1

Add-Type -AssemblyName System.Drawing

function global:iconctl {
    param(
        [Parameter(Position = 0)]
        [string]$Command,

        [Parameter(Position = 1, ValueFromRemainingArguments)]
        [string[]]$Args
    )

    # ========== 内部工具函数 ==========

    function Get-IconHome {
        if ($env:ICON_HOME) {
            return $env:ICON_HOME
        }
        return Join-Path $env:LOCALAPPDATA "Icons"
    }

    function Ensure-IconHome {
        $iconHomePath = Get-IconHome
        if (-not (Test-Path $iconHomePath)) {
            New-Item -ItemType Directory -Path $iconHomePath -Force | Out-Null
        }
        return $iconHomePath
    }

    function Test-ValidIconName {
        param([string]$Name)
        return $Name -match '^[a-zA-Z0-9_-]+$'
    }

    # ========== 子命令：preview ==========
    function Invoke-Preview {
        param([string]$IconName)

        if (-not $IconName) {
            Write-Host "❌ 用法: iconctl preview <图标名>" -ForegroundColor Red
            return
        }

        if (-not (Test-ValidIconName $IconName)) {
            Write-Host "❌ 图标名 '$IconName' 包含非法字符。仅允许英文字母、数字、下划线(_)、连字符(-)。" -ForegroundColor Red
            return
        }

        $iconHomePath = Ensure-IconHome
        $iconFullPath = Join-Path $iconHomePath "$IconName.ico"

        if (-not (Test-Path $iconFullPath)) {
            Write-Host "❌ 图标文件 '$iconFullPath' 不存在。" -ForegroundColor Red
            return
        }

        $previewCmd = if ($env:ICON_PREVIEWCMD) { $env:ICON_PREVIEWCMD } else { "ii" }

        try {
            switch ($previewCmd) {
                "ii" {
                    Invoke-Item "$iconFullPath"
                }
                default {
                    if (Get-Command $previewCmd -ErrorAction SilentlyContinue) {
                        & $previewCmd $iconFullPath
                    } else {
                        Write-Host "⚠️ 预览命令 '$previewCmd' 未找到，回退到 ii..." -ForegroundColor Yellow
                        Invoke-Item "$iconFullPath"
                    }
                }
            }
        } catch {
            Write-Host "❌ 预览失败: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }

    # ========== 子命令：convert ==========
    function Invoke-Convert {
        param([string]$ImagePath)

        if (-not $ImagePath) {
            Write-Host "❌ 用法: iconctl convert <图片路径>" -ForegroundColor Red
            return
        }

        try {
            $resolvedInput = Resolve-Path -Path $ImagePath -ErrorAction Stop
        } catch {
            Write-Host "❌ 输入文件不存在: $ImagePath" -ForegroundColor Red
            return
        }

        $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($resolvedInput.Path)
        if (-not (Test-ValidIconName $fileNameWithoutExt)) {
            Write-Host "❌ 图标名 '$fileNameWithoutExt' 包含非法字符。仅允许英文字母、数字、下划线(_)、连字符(-)。" -ForegroundColor Red
            return
        }

        $iconHomePath = Ensure-IconHome
        $outputPath = Join-Path $iconHomePath "$fileNameWithoutExt.ico"

        try {
            $originalImage = [System.Drawing.Image]::FromFile($resolvedInput.Path)

            $sizes = @(16, 32, 48, 256) | Where-Object {
                $originalImage.Width -ge $_ -and $originalImage.Height -ge $_
            }
            if ($sizes.Count -eq 0) {
                $minSize = [Math]::Min($originalImage.Width, $originalImage.Height)
                $sizes = @($minSize)
            }

            $memoryStream = New-Object System.IO.MemoryStream
            $binaryWriter = New-Object System.IO.BinaryWriter($memoryStream)

            $binaryWriter.Write([UInt16]0)
            $binaryWriter.Write([UInt16]1)
            $binaryWriter.Write([UInt16]$sizes.Count)

            $imageDataStreams = @()
            $iconDirEntries = @()

            foreach ($size in $sizes) {
                $bmp = New-Object System.Drawing.Bitmap($size, $size)
                $graphics = [System.Drawing.Graphics]::FromImage($bmp)
                $graphics.InterpolationMode = 'HighQualityBicubic'
                $graphics.DrawImage($originalImage, 0, 0, $size, $size)
                $graphics.Dispose()

                $imgStream = New-Object System.IO.MemoryStream
                $bmp.Save($imgStream, [System.Drawing.Imaging.ImageFormat]::Png)
                $bmp.Dispose()

                $data = $imgStream.ToArray()
                $imgStream.Dispose()
                $imageDataStreams += $data

                $widthByte = if ($size -eq 256) { 0 } else { $size }
                $iconDirEntries += [PSCustomObject]@{
                    Width        = [byte]$widthByte
                    Height       = [byte]$widthByte
                    ColorCount   = [byte]0
                    Reserved     = [byte]0
                    Planes       = [UInt16]1
                    BitCount     = [UInt16]32
                    BytesInRes   = [UInt32]$data.Length
                    ImageOffset  = $null
                }
            }

            $offset = 6 + ($iconDirEntries.Count * 16)
            foreach ($entry in $iconDirEntries) {
                $entry.ImageOffset = $offset
                $binaryWriter.Write($entry.Width)
                $binaryWriter.Write($entry.Height)
                $binaryWriter.Write($entry.ColorCount)
                $binaryWriter.Write($entry.Reserved)
                $binaryWriter.Write($entry.Planes)
                $binaryWriter.Write($entry.BitCount)
                $binaryWriter.Write($entry.BytesInRes)
                $binaryWriter.Write($entry.ImageOffset)
                $offset += $entry.BytesInRes
            }

            foreach ($data in $imageDataStreams) {
                $binaryWriter.Write($data)
            }

            $finalBytes = $memoryStream.ToArray()
            [System.IO.File]::WriteAllBytes($outputPath, $finalBytes)

            Write-Host "✅ 图标已保存至: $outputPath" -ForegroundColor Green
        }
        finally {
            if ($null -ne $originalImage) { $originalImage.Dispose() }
            if ($null -ne $binaryWriter) { $binaryWriter.Dispose() }
            if ($null -ne $memoryStream) { $memoryStream.Dispose() }
        }
    }

    # ========== 子命令：list ==========
    function Invoke-List {
        $iconHomePath = Get-IconHome
        if (-not (Test-Path $iconHomePath)) {
            Write-Host "📁 ICON_HOME 为空: $iconHomePath" -ForegroundColor Gray
            return
        }

        $icons = Get-ChildItem -Path $iconHomePath -Filter "*.ico" -File |
                 ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } |
                 Sort-Object

        if ($icons) {
            Write-Host "📦 ICON_HOME 中的图标:" -ForegroundColor Cyan
            $icons | ForEach-Object { Write-Host "  $_" }
        } else {
            Write-Host "📭 ICON_HOME 中无 .ico 文件。" -ForegroundColor Gray
        }
    }

    # ========== 子命令：show ==========
    function Invoke-Show {
        $BasePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons"

        $allDrives = (Get-PSDrive -PSProvider FileSystem).Name.ToUpper() | Sort-Object -Unique
        $customDriveMap = @{}

        if (Test-Path $BasePath) {
            $subKeys = Get-ChildItem -Path $BasePath -ErrorAction SilentlyContinue
            foreach ($key in $subKeys) {
                if ($key.PSIsContainer) {
                    $driveLetter = $key.PSChildName.ToUpper()
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

        $extraDrives = $customDriveMap.Keys | Where-Object { $allDrives -notcontains $_ }
        if ($extraDrives) {
            Write-Host "`n📎 其他自定义图标（非本地磁盘）：" -ForegroundColor Magenta
            foreach ($ed in $extraDrives | Sort-Object) {
                $val = $customDriveMap[$ed]
                $displayText = if ($val -and $val.Trim()) { $val } else { '⚠️ 路径为空' }
                Write-Host "  $ed : $displayText" -ForegroundColor Magenta
            }
        }
    }

    # ========== 子命令：restore ==========
    function Invoke-Restore {
        param([string]$Target)

        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($id)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Host "❌ 需要以管理员身份运行。" -ForegroundColor Red
            return
        }

        $BasePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons"

        if ($Target -eq "all") {
            if (Test-Path $BasePath) {
                Remove-Item $BasePath -Recurse -Force
                Write-Host "✅ 已清除所有自定义图标。" -ForegroundColor Green
            } else {
                Write-Host "ℹ️ 无自定义图标需要恢复。" -ForegroundColor Gray
            }
        } elseif ($Target -match '^[A-Z]$') {
            $targetPath = Join-Path $BasePath $Target
            if (Test-Path $targetPath) {
                Remove-Item $targetPath -Recurse -Force
                Write-Host "✅ 已恢复 $Target 盘默认图标。" -ForegroundColor Green
            } else {
                Write-Host "ℹ️ $Target 盘未设置自定义图标。" -ForegroundColor Gray
            }
        } else {
            Write-Host "❌ 无效参数。用法: iconctl restore <盘符|all>" -ForegroundColor Red
            Write-Host "   示例: iconctl restore D" -ForegroundColor Gray
            Write-Host "         iconctl restore all" -ForegroundColor Gray
            return
        }

        & "$env:SystemRoot\System32\ie4uinit.exe" -show | Out-Null
        Write-Host "🔄 图标缓存已刷新。" -ForegroundColor Yellow
    }

    # ========== 子命令：set ==========
    function Invoke-Set {
        param([string]$Drive, [string]$IconName)

        if (-not $Drive -or -not $IconName) {
            Write-Host "❌ 用法: iconctl set <盘符> <图标名>" -ForegroundColor Red
            return
        }

        if ($Drive -notmatch '^[A-Z]$') {
            Write-Host "❌ 盘符必须为大写字母 A-Z。" -ForegroundColor Red
            return
        }

        if (-not (Test-ValidIconName $IconName)) {
            Write-Host "❌ 图标名 '$IconName' 包含非法字符。仅允许英文字母、数字、下划线(_)、连字符(-)。" -ForegroundColor Red
            return
        }

        $iconHomePath = Ensure-IconHome
        $iconFullPath = Join-Path $iconHomePath "$IconName.ico"

        if (-not (Test-Path $iconFullPath)) {
            Write-Host "❌ 图标文件 '$iconFullPath' 不存在。" -ForegroundColor Red
            return
        }

        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($id)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Host "❌ 需要以管理员身份运行。" -ForegroundColor Red
            return
        }

        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\DriveIcons\$Drive\DefaultIcon"
        try {
            New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
            Set-ItemProperty -Path $regPath -Name "(default)" -Value $iconFullPath -ErrorAction Stop
            Write-Host "✅ 已设置 $Drive 盘图标。" -ForegroundColor Green
        } catch {
            Write-Host "❌ 设置图标失败: $($_.Exception.Message)" -ForegroundColor Red
            return
        }

        & "$env:SystemRoot\System32\ie4uinit.exe" -show | Out-Null
        Write-Host "🔄 图标缓存已刷新。" -ForegroundColor Yellow
    }

    # ========== 子命令：open ==========
    function Invoke-OpenIconHome {
        # 确定图标目录路径
        if ($env:ICON_HOME) {
            $iconDir = $env:ICON_HOME
        } else {
            $iconDir = Join-Path $env:LOCALAPPDATA "Icons"
        }

        # 检查目录是否存在
        if (-not (Test-Path -Path $iconDir -PathType Container)) {
            Write-Host "❌ 图标目录不存在: $iconDir" -ForegroundColor Red
            if ($env:ICON_HOME) {
                Write-Host "   您设置了 ICON_HOME 环境变量，但该路径无效。" -ForegroundColor Gray
            } else {
                Write-Host "   默认路径未初始化。可先运行 'iconctl set ...' 自动创建。" -ForegroundColor Gray
            }
            return
        }

        try {
            Invoke-Item $iconDir
            Write-Host "📁 已打开图标目录: $iconDir" -ForegroundColor Green
        } catch {
            Write-Host "❌ 无法打开目录: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # ========== 子命令：usb set ==========
    function Invoke-UsbSet {
        param(
            [Parameter(Mandatory)]
            [string]$Drive,
            [Parameter(Mandatory)]
            [string]$IconName,
            [switch]$Force
        )

        if ($Drive -notmatch '^[A-Z]$') {
            Write-Host "❌ 盘符必须为单个大写字母（如 E）。" -ForegroundColor Red
            return
        }

        if (-not (Test-ValidIconName $IconName)) {
            Write-Host "❌ 图标名 '$IconName' 包含非法字符。仅允许英文字母、数字、下划线(_)、连字符(-)。" -ForegroundColor Red
            return
        }

        try {
            $driveInfo = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$($Drive):'" -ErrorAction Stop
            if ($null -eq $driveInfo -or $driveInfo.DriveType -ne 2) {
                Write-Host "❌ 盘符 $Drive 不是可移动磁盘（U盘/移动硬盘）。" -ForegroundColor Red
                Write-Host "   请确认设备已正确连接。" -ForegroundColor Gray
                return
            }
        } catch {
            Write-Host "❌ 无法查询盘符 $Drive 的信息。" -ForegroundColor Red
            return
        }

        $usbRoot = "$Drive`:"
        if (-not (Test-Path $usbRoot)) {
            Write-Host "❌ 盘符 $Drive 不存在或无法访问。" -ForegroundColor Red
            return
        }

        $iconHomePath = Ensure-IconHome
        $sourceIconPath = Join-Path $iconHomePath "$IconName.ico"
        $targetIconPath = Join-Path $usbRoot "$IconName.ico"
        $autorunPath = Join-Path $usbRoot "autorun.inf"

        if (-not (Test-Path $sourceIconPath)) {
            Write-Host "❌ 源图标文件不存在: $sourceIconPath" -ForegroundColor Red
            return
        }

        if ((Test-Path $autorunPath) -and (-not $Force)) {
            Write-Host "⚠️ U 盘根目录已存在 autorun.inf 文件。" -ForegroundColor Yellow
            Write-Host "   为避免意外覆盖，未进行任何操作。" -ForegroundColor Gray
            Write-Host "   如需强制覆盖，请添加 -Force 参数。" -ForegroundColor Gray
            return
        }

        try {
            # === 核心优化：先删后建，彻底规避属性问题 ===
            if (Test-Path $targetIconPath) {
                Remove-Item -Path $targetIconPath -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $autorunPath) {
                Remove-Item -Path $autorunPath -Force -ErrorAction SilentlyContinue
            }

            Copy-Item -Path $sourceIconPath -Destination $targetIconPath -Force

            $content = "[autorun]`r`nicon=$IconName.ico"
            [System.IO.File]::WriteAllLines($autorunPath, $content, [System.Text.Encoding]::Default)

            Write-Host "✅ U 盘图标设置成功！" -ForegroundColor Green
            Write-Host "   图标文件: $targetIconPath" -ForegroundColor Gray
            Write-Host "   配置文件: $autorunPath" -ForegroundColor Gray
            Write-Host "`n💡 请安全弹出 U 盘并重新插入，以使新图标生效。" -ForegroundColor Cyan

        } catch {
            Write-Host "❌ 设置 U 盘图标失败: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }

    # ========== 子命令：usb clear ==========
    function Invoke-UsbClear {
        param(
            [Parameter(Mandatory)]
            [string]$Drive
        )

        if ($Drive -notmatch '^[A-Z]$') {
            Write-Host "❌ 盘符必须为单个大写字母（如 E）。" -ForegroundColor Red
            return
        }

        $usbRoot = "$Drive`:"

        if (-not (Test-Path $usbRoot)) {
            Write-Host "❌ 盘符 $Drive 不存在或无法访问。" -ForegroundColor Red
            return
        }

        # 检查是否为可移动磁盘（DriveType = 2）
        try {
            $driveInfo = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$($Drive):'" -ErrorAction Stop
            if ($null -eq $driveInfo -or $driveInfo.DriveType -ne 2) {
                Write-Host "❌ 盘符 $Drive 不是可移动磁盘（U盘/移动硬盘）。" -ForegroundColor Red
                Write-Host "   usbclear 仅用于 U 盘或移动硬盘。" -ForegroundColor Gray
                return
            }
        } catch {
            Write-Host "❌ 无法查询盘符 $Drive 的信息。" -ForegroundColor Red
            return
        }

        $autorunPath = Join-Path $usbRoot "autorun.inf"

        if (-not (Test-Path $autorunPath)) {
            Write-Host "ℹ️ U 盘根目录未发现 autorun.inf，无需清理。" -ForegroundColor Cyan
            return
        }

        try {
            # 读取 autorun.inf 内容并提取 icon 路径
            $content = Get-Content -Path $autorunPath -Raw -ErrorAction SilentlyContinue
            $iconFileToDelete = $null

            if ($content -and ($content -match '(?im)^\s*icon\s*=\s*([^\r\n;]+)\s*$')) {
                $iconFileToDelete = $matches[1].Trim()
                # 确保路径不包含目录遍历（安全过滤）
                if ($iconFileToDelete -match '[\\/]' -or $iconFileToDelete -notlike '*.ico') {
                    Write-Host "⚠️ 警告: autorun.inf 中的 icon 路径包含非法字符或非 .ico 文件，跳过删除图标。" -ForegroundColor Yellow
                    $iconFileToDelete = $null
                }
            }

            # 删除图标文件（如果合法且存在）
            if ($iconFileToDelete) {
                $iconPath = Join-Path $usbRoot $iconFileToDelete
                if (Test-Path $iconPath) {
                    Remove-Item -Path $iconPath -Force -ErrorAction SilentlyContinue
                    Write-Host "🗑️ 已删除图标文件: $iconPath" -ForegroundColor Gray
                }
            }

            # 删除 autorun.inf
            Remove-Item -Path $autorunPath -Force -ErrorAction SilentlyContinue
            Write-Host "✅ 已清除 U 盘自定义图标设置。" -ForegroundColor Green
            Write-Host "`n💡 请安全弹出 U 盘并重新插入，以恢复默认图标。" -ForegroundColor Cyan

        } catch {
            Write-Host "❌ 清理 U 盘图标失败: $($_.Exception.Message)" -ForegroundColor Red
            return
        }
    }

    # ========== 子命令：usb show ==========
    function Invoke-UsbShow {
        # 获取所有可移动磁盘（DriveType = 2）
        try {
            $drives = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=2" -ErrorAction Stop
            if (-not $drives) {
                Write-Host "ℹ️ 未检测到任何 U 盘或移动硬盘。" -ForegroundColor Cyan
                return
            }
        } catch {
            Write-Host "❌ 无法查询可移动磁盘信息。" -ForegroundColor Red
            return
        }

        Write-Host "📌 U 盘图标状态：" -ForegroundColor Magenta

        foreach ($d in $drives) {
            $letter = $d.DeviceID.TrimEnd(':')
            $label = if ($d.VolumeName) { "$($d.VolumeName) ($letter)" } else { $letter }
            $autorunPath = "$letter`:\autorun.inf"

            if (Test-Path $autorunPath) {
                $content = Get-Content -Path $autorunPath -Raw -ErrorAction SilentlyContinue
                if ($content -match '(?im)^\s*icon\s*=\s*([^\r\n;]+)\s*$') {
                    $iconRef = $matches[1].Trim()
                    Write-Host "  $label : $iconRef"
                } else {
                    Write-Host "  $label : (autorun.inf 存在，但未设置 icon)"
                }
            } else {
                Write-Host "  $label : (默认系统图标)"
            }
        }
    }
    
    # ========== 子命令：refresh ==========
    function Invoke-Refresh {
        & "$env:SystemRoot\System32\ie4uinit.exe" -show | Out-Null
        Write-Host "🔄 图标缓存已刷新（使用 ie4uinit.exe）。" -ForegroundColor Yellow
    }

    # ========== 子命令：version ==========
    function Invoke-Version {
        Write-Host "iconctl v0.0.1"
    }

    # ========== 主分发逻辑 ==========
    if (-not $Command) {
        Write-Host "USAGE: iconctl <command> [args]" -ForegroundColor Cyan
        Write-Host "通过 help 查看可用的子命令" -ForegroundColor Gray
        return
    }

    switch ($Command) {
        "convert" {
            Invoke-Convert -ImagePath ($Args[0])
        }
        "list" {
            Invoke-List
        }
        "show" {
            Invoke-Show
        }
        "restore" {
            Invoke-Restore -Target ($Args[0])
        }
        "set" {
            if ($Args.Count -lt 2) {
                Write-Host "❌ 用法: iconctl set <盘符> <图标名>" -ForegroundColor Red
                return
            }
            Invoke-Set -Drive $Args[0] -IconName $Args[1]
        }
        "preview" {
            if ($Args.Count -ne 1) {
                Write-Host "❌ 用法: iconctl preview <图标名>" -ForegroundColor Red
                return
            }
            Invoke-Preview -IconName $Args[0]
        }
        "refresh" {
            Invoke-Refresh
        }
        "version" {
            Invoke-Version
        }
        "open" {
            if ($Args.Count -ne 0) {
                Write-Host "❌ 用法: iconctl open" -ForegroundColor Red
                # Write-Host "   功能: 打开图标存储目录（$env:ICON_HOME 或默认路径）" -ForegroundColor Gray
                if ($env:ICON_HOME) {
                    Write-Host "   功能: 打开图标存储目录（$env:ICON_HOME)"
                }
                else {
                    Write-Host "   功能: 打开图标存储目录 ($env:LOCALAPPDATA\Icons)"
                }
                return
            }
            Invoke-OpenIconHome
        }
        "usb" {
            if ($Args.Count -lt 1) {
                Write-Host "❌ 用法: iconctl usb <set|clear|show>" -ForegroundColor Red
                Write-Host "   示例:" -ForegroundColor Gray
                Write-Host "     iconctl usb set G myicon" -ForegroundColor Gray
                Write-Host "     iconctl usb set G myicon -Force" -ForegroundColor Gray
                Write-Host "     iconctl usb clear G" -ForegroundColor Gray
                Write-Host "     iconctl usb show" -ForegroundColor Gray
                return
            }

            $subAction = $Args[0].ToLower()
            # ✅ 安全获取剩余参数
            $remainingArgs = if ($Args.Count -gt 1) { $Args[1..($Args.Count - 1)] } else { @() }

            switch ($subAction) {
                "set" {
                    if ($remainingArgs.Count -lt 2) {
                        Write-Host "❌ 用法: iconctl usb set <盘符> <图标名> [-Force]" -ForegroundColor Red
                        return
                    }
                    $drive = $remainingArgs[0]
                    $iconName = $remainingArgs[1]
                    $hasForce = $remainingArgs[2..($remainingArgs.Count - 1)] -contains '-Force' -or 
                                $remainingArgs[2..($remainingArgs.Count - 1)] -contains '-force'
                    Invoke-UsbSet -Drive $drive -IconName $iconName -Force:$hasForce
                }
                "clear" {
                    if ($remainingArgs.Count -ne 1) {
                        Write-Host "❌ 用法: iconctl usb clear <盘符>" -ForegroundColor Red
                        return
                    }
                    Invoke-UsbClear -Drive $remainingArgs[0]
                }
                "show" {
                    if ($remainingArgs.Count -gt 0) {
                        Write-Host "❌ usb show 不接受参数。" -ForegroundColor Red
                        Write-Host "   用法: iconctl usb show" -ForegroundColor Gray
                        return
                    }
                    Invoke-UsbShow
                }
                default {
                    Write-Host "❌ 未知 usb 子命令: $subAction" -ForegroundColor Red
                    Write-Host "   支持: set, clear, show" -ForegroundColor Gray
                }
            }
        }
        "help" {
            Write-Host "iconctl - Windows 图标管理工具" -ForegroundColor Cyan
            Write-Host "用法: iconctl <command> [args]" -ForegroundColor White
            Write-Host ""
            Write-Host "本地磁盘图标（C/D 等）:" -ForegroundColor Yellow
            Write-Host "  set <盘符> <图标名>    设置指定盘符的自定义图标（需管理员）"
            Write-Host "  show                  显示所有盘符的图标状态"
            Write-Host "  restore <盘符|all>    恢复指定盘符或全部为默认图标（需管理员）"
            Write-Host ""
            Write-Host "U 盘/移动硬盘图标（通过 autorun.inf）:" -ForegroundColor Yellow
            Write-Host "  usb set <盘符> <图标名> [-Force]  为 U 盘设置图标（自动复制 .ico 并生成 autorun.inf）"
            Write-Host "  usb clear <盘符>      清除 U 盘的图标设置（删除 autorun.inf 和图标文件）"
            Write-Host "  usb show              列出所有已连接 U 盘的图标状态"
            Write-Host ""
            Write-Host "图标文件管理（位于 ICON_HOME 目录）:" -ForegroundColor Yellow
            Write-Host "  convert <图片路径>    将图片转换为 .ico 并保存到图标库"
            Write-Host "  list                  列出 ICON_HOME 中所有可用图标"
            Write-Host "  preview <图标名>      预览指定图标"
            Write-Host "  open                  打开 ICON_HOME 目录（便于手动管理图标文件）"
            Write-Host ""
            Write-Host "其他:" -ForegroundColor Yellow
            Write-Host "  refresh               手动刷新系统图标缓存"
            Write-Host "  version               显示版本信息"
            Write-Host "  help                  显示此帮助信息"
            Write-Host ""
            Write-Host "💡 提示:"
            Write-Host "  - 图标名仅支持字母、数字、下划线(_)、连字符(-)"
            Write-Host "  - ICON_HOME 默认为: $env:LOCALAPPDATA\Icons"
            Write-Host "  - 可通过环境变量 ICON_HOME 自定义图标存储目录"
        }
        default {
            Write-Host "❌ 未知命令: $Command" -ForegroundColor Red
            Write-Host "通过 help 查看可用的子命令" -ForegroundColor Gray
            return
        }
    }
}

# 如果是直接执行脚本（而非被 dot-sourced），则调用函数
if ($MyInvocation.InvocationName -ne '.') {
    iconctl @args
}