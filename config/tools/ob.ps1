function global:ob {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [string]$VaultName,

        [Alias('s')]
        [switch]$show,

        [Alias('j')]
        [switch]$json,

        [Alias('o')]
        [string]$open,

        [Alias('on')]
        [int]$openNumber,

        [Alias('r')]
        [switch]$resetOrder,

        [Alias('h')]
        [switch]$help,

        [Alias('p')]
        [string]$pin,

        [Alias('u')]
        [string]$unpin,

        [Alias('n')]
        [int]$number  # ✅ 新增：通过序号打开仓库
    )

    $ConfigFile = "$env:APPDATA\obsidian\obsidian.json"

    # ----------------------------
    # 查找 Obsidian.exe：仅通过环境变量 OBEXE_HOME
    # ----------------------------
    if (-not ($env:OBEXE_HOME)) {
        Write-Error @"
❌ 未设置环境变量 OBEXE_HOME

请设置环境变量指向 Obsidian.exe，例如：

👉 临时设置（当前会话）：
    `$env:OBEXE_HOME = 'C:\Users\<UserName>\AppData\Local\Programs\Obsidian\Obsidian.exe'

📌 永久设置方法（PowerShell）：
    [Environment]::SetEnvironmentVariable('OBEXE_HOME', 'C:\Users\<UserName>\AppData\Local\Programs\Obsidian\Obsidian.exe', 'User')

当前支持的安装方式：
  • Microsoft Store: C:\Users\<UserName>\AppData\Local\Microsoft\WindowsApps\obsidian.exe
  • 官方安装器:     C:\Users\<UserName>\AppData\Local\Programs\Obsidian\Obsidian.exe
  • 便携版:         你解压的任意位置（如 D:\Obsidian\Obsidian.exe）

💡 设置后，重启 PowerShell 或运行：
    `$env:OBEXE_HOME = [Environment]::GetEnvironmentVariable('OBEXE_HOME', 'User')
"@
        return
    }

    if (-not (Test-Path $env:OBEXE_HOME -PathType Leaf)) {
        Write-Error "❌ OBEXE_HOME 指向的路径无效或不是文件：`n    $($env:OBEXE_HOME)"
        return
    }

    $ObsidianExe = $env:OBEXE_HOME

    # ----------------------------
    # Help
    # ----------------------------
    if ($help) {
        Write-Host @"
用法: ob [选项] [<仓库名>]

📌 简洁高效，功能明确

选项:
    ob                    启动 Obsidian
    ob <名>               打开指定仓库
    ob -s                 [show] 显示所有仓库（带序号）
    ob -j                 [json] 输出 obsidian.json 内容
    ob -o <名>            [open] 打开仓库所在目录
    ob -on <序号>         [open-number] 打开第N个仓库的目录
    ob -n <序号>          [number] 打开第N个仓库（按列表顺序）
    ob -p <名>            [pin] 将仓库置顶（加入置顶列表）
    ob -u <名>            [unpin] 取消仓库置顶
    ob -r                 [reset] 重置置顶顺序（清空置顶列表）
    ob -h                 [help] 显示帮助

示例:
    ob -j
    ob -o linux
    ob -on 3
    ob -n 2
    ob -p 工作笔记
    ob -u 临时项目
"@ -ForegroundColor Cyan
        return
    }

    if (-not (Test-Path $ConfigFile)) {
        Write-Error "❌ 配置文件不存在: $ConfigFile"
        return
    }

    try {
        $config = Get-Content $ConfigFile | ConvertFrom-Json -Depth 10
    }
    catch {
        Write-Error "❌ 解析 JSON 失败: $_"
        return
    }

    if (-not $config.PSObject.Properties.Name.Contains("ob_pinned")) {
        $config | Add-Member -MemberType NoteProperty -Name "ob_pinned" -Value @() -Force
    }
    [System.Collections.ArrayList]$pinnedNames = $config.ob_pinned

    # ----------------------------
    # 构建带序号的 vault 列表（置顶优先）
    # ----------------------------
    $vaultList = @()
    $index = 1
    foreach ($pinnedName in $pinnedNames) {
        $item = $config.vaults.PSObject.Properties | Where-Object { (Split-Path $_.Value.path -Leaf) -eq $pinnedName }
        if ($item) {
            $name = Split-Path $item.Value.path -Leaf
            $path = $item.Value.path
            $vaultList += [PSCustomObject]@{ Number = $index; Name = $name; Key = $item.Name; Path = $path; IsPinned = $true }
            $index++
        }
    }
    $allNames = $config.vaults.PSObject.Properties | ForEach-Object { Split-Path $_.Value.path -Leaf } | Sort-Object
    foreach ($name in $allNames) {
        if ($pinnedNames -contains $name) { continue }
        $item = $config.vaults.PSObject.Properties | Where-Object { (Split-Path $_.Value.path -Leaf) -eq $name }
        $path = $item.Value.path
        $vaultList += [PSCustomObject]@{ Number = $index; Name = $name; Key = $item.Name; Path = $path; IsPinned = $false }
        $index++
    }

    # ----------------------------
    # 功能: -json
    # ----------------------------
    if ($json) {
        Write-Host "📄 当前 obsidian.json 内容：" -ForegroundColor Green
        Get-Content $ConfigFile | Write-Host -ForegroundColor Gray
        return
    }

    # ----------------------------
    # 功能: -open (打开目录)
    # ----------------------------
    if ($open) {
        $target = $vaultList | Where-Object { $_.Name -eq $open }
        if (-not $target) {
            Write-Error "❌ 未找到仓库: '$open'"
            ob -s
            return
        }
        $dir = $target.Path
        if (Test-Path $dir) {
            Invoke-Item $dir
            Write-Host "📁 已打开仓库目录: $dir" -ForegroundColor Green
        } else {
            Write-Error "❌ 目录不存在: $dir"
        }
        return
    }

    # ----------------------------
    # 功能: -openNumber (打开第N个仓库的目录)
    # ----------------------------
    if ($openNumber) {
        $target = $vaultList | Where-Object { $_.Number -eq $openNumber }
        if (-not $target) {
            Write-Error "❌ 无效序号: $openNumber"
            ob -s
            return
        }
        $dir = $target.Path
        if (Test-Path $dir) {
            Invoke-Item $dir
            Write-Host "📁 已打开第 $openNumber 个仓库目录: $dir" -ForegroundColor Green
        } else {
            Write-Error "❌ 目录不存在: $dir"
        }
        return
    }

    # ----------------------------
    # ✅ 新增功能: -number (打开第N个仓库)
    # ----------------------------
    if ($number) {
        $target = $vaultList | Where-Object { $_.Number -eq $number }
        if (-not $target) {
            Write-Error "❌ 无效序号: $number"
            ob -s
            return
        }

        $existing = Get-Process -Name Obsidian -ErrorAction SilentlyContinue
        if ($existing) {
            $existing | Stop-Process -Force
            Start-Sleep -Milliseconds 500
        }

        foreach ($item in $config.vaults.PSObject.Properties) {
            if ($item.Value.PSObject.Properties.Name -contains 'open') {
                $item.Value.psobject.Members.Remove('open')
            }
        }
        $config.vaults.($target.Key) | Add-Member -MemberType NoteProperty -Name 'open' -Value $true -Force

        try {
            $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile -Encoding UTF8 -Force
            Write-Host "✅ 已设置默认库: '$($target.Name)'" -ForegroundColor Green
        }
        catch {
            Write-Error "❌ 保存失败: $_"
        }

        Start-Process $ObsidianExe
        Write-Host "🚀 正在启动第 $number 个仓库: '$($target.Name)'..." -ForegroundColor Cyan
        return
    }

    # ----------------------------
    # 功能: -pin
    # ----------------------------
    if ($pin) {
        $target = $vaultList | Where-Object { $_.Name -eq $pin }
        if (-not $target) {
            Write-Error "❌ 未找到仓库: '$pin'"
            ob -s
            return
        }
        if ($pinnedNames -contains $pin) {
            Write-Host "🟡 仓库 '$pin' 已在置顶列表中。" -ForegroundColor Yellow
        } else {
            $pinnedNames.Add($pin)
            try {
                $config.ob_pinned = @($pinnedNames)
                $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile -Encoding UTF8 -Force
                Write-Host "📌 已将 '$pin' 加入置顶列表。" -ForegroundColor Green
            }
            catch { Write-Error "❌ 保存失败: $_" }
        }
        return
    }

    # ----------------------------
    # 功能: -unpin
    # ----------------------------
    if ($unpin) {
        $target = $vaultList | Where-Object { $_.Name -eq $unpin }
        if (-not $target) {
            Write-Error "❌ 未找到仓库: '$unpin'"
            ob -s
            return
        }
        if ($pinnedNames -contains $unpin) {
            $pinnedNames.Remove($unpin)
            try {
                $config.ob_pinned = @($pinnedNames)
                $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile -Encoding UTF8 -Force
                Write-Host "🗑️ 已从置顶列表移除 '$unpin'。" -ForegroundColor Green
            }
            catch { Write-Error "❌ 保存失败: $_" }
        } else {
            Write-Host "🟡 仓库 '$unpin' 不在置顶列表中。" -ForegroundColor Yellow
        }
        return
    }

    # ----------------------------
    # 功能: -resetOrder
    # ----------------------------
    if ($resetOrder) {
        if ($pinnedNames.Count -eq 0) {
            Write-Host "🟢 置顶列表已为空。" -ForegroundColor Green
        } else {
            $oldCount = $pinnedNames.Count
            $pinnedNames.Clear()
            try {
                $config.ob_pinned = @()
                $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile -Encoding UTF8 -Force
                Write-Host "✅ 已清空 $oldCount 个置顶项，恢复默认排列。" -ForegroundColor Green
            }
            catch { Write-Error "❌ 保存失败: $_" }
        }
        return
    }

    # ----------------------------
    # 功能: -show
    # ----------------------------
    if ($show) {
        $table = $vaultList | Select-Object Number, Name, @{
            Name = 'State'; Expression = {
                $s = if ($config.vaults.($_.Key).PSObject.Properties.Name -contains 'open' -and $config.vaults.($_.Key).open) { "✅ (默认)" } else { "❌" }
                if ($_.IsPinned) { "📌 $s" } else { $s }
            }
        }
        $table | Format-Table -AutoSize
        return
    }

    # ----------------------------
    # 默认行为：启动或打开指定仓库
    # ----------------------------
    if (-not $VaultName) {
        & $ObsidianExe
        Write-Host "👉 启动 Obsidian（当前默认库）" -ForegroundColor Green
        return
    }

    $target = $vaultList | Where-Object { $_.Name -eq $VaultName }
    if (-not $target) {
        Write-Error "❌ 未找到仓库: '$VaultName'"
        ob -s
        return
    }

    $existing = Get-Process -Name Obsidian -ErrorAction SilentlyContinue
    if ($existing) {
        $existing | Stop-Process -Force
        Start-Sleep -Milliseconds 500
    }

    foreach ($item in $config.vaults.PSObject.Properties) {
        if ($item.Value.PSObject.Properties.Name -contains 'open') {
            $item.Value.psobject.Members.Remove('open')
        }
    }
    $config.vaults.($target.Key) | Add-Member -MemberType NoteProperty -Name 'open' -Value $true -Force

    try {
        $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile -Encoding UTF8 -Force
        Write-Host "✅ 已设置默认库: '$($target.Name)'" -ForegroundColor Green
    }
    catch {
        Write-Error "❌ 保存失败: $_"
    }

    Start-Process $ObsidianExe
    Write-Host "🚀 正在启动 '$($target.Name)'..." -ForegroundColor Cyan
}