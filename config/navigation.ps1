# ===================================================================
#  快速返回上级目录
# ===================================================================
# ===================================================================
#  私有辅助函数：通用上级目录跳转逻辑
# ===================================================================
function script:Invoke-ParentNavigate {
    param(
        [Parameter(Mandatory)]
        [int]$LevelsUp,

        [Parameter(Position = 0)]
        [string]$Path,

        [Parameter()]
        [switch]$Fzf
    )

    # 检查 fzf 是否存在（仅在使用时检查）
    if ($Fzf -and !(Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Error "fzf命令找不到，无法使用-fzf参数的功能。请检查fzf命令是否安装，或检查环境变量是否配置正确"
        return
    }

    # 计算目标基础路径：向上跳 $LevelsUp 级
    $current = Get-Item $PWD
    for ($i = 0; $i -lt $LevelsUp; $i++) {
        if ($null -eq $current.Parent) {
            Write-Error "无法再向上跳转：已达文件系统根目录"
            return
        }
        $current = $current.Parent
    }
    $baseDir = $current.FullName

    if ($Fzf) {
        $target = $baseDir

        # 如果提供了 Path，则跳转到 baseDir 下的子目录
        if (-not [string]::IsNullOrWhiteSpace($Path)) {
            $normalizedPath = $Path.Replace('\', [IO.Path]::DirectorySeparatorChar)
            $target = Join-Path $baseDir $normalizedPath
            if (-not (Test-Path -LiteralPath $target -PathType Container)) {
                Write-Host "路径不存在: $target" -ForegroundColor Yellow
                return
            }
        }

        # 获取目标目录下的子目录
        $subDirs = Get-ChildItem -LiteralPath $target -Directory | ForEach-Object { $_.FullName }
        if ($subDirs.Count -eq 0) {
            Write-Warning "目标目录中没有子目录，无法使用 fzf 进行选择。"
            return
        }

        $previewCmd = $env:POSH_FZF_PREVIEW_CMD ?? 'ls'

        $selected = $subDirs | fzf --height=50% --preview "$previewCmd {}" --preview-window=right,70%
        if ($selected) {
            # ✅ 清理隐藏字符（如 UTF-8 BOM \uFEFF、零宽空格 \u200B）
            $cleanedPath = $selected.Trim() -replace "[\uFEFF\u200B]", ""

            # ✅ 验证清理后的路径是否有效
            if (Test-Path -LiteralPath $cleanedPath -PathType Container) {
                Set-Location -LiteralPath $cleanedPath
                Write-Host "已进入: $(Resolve-Path .)" -ForegroundColor Green
            } else {
                Write-Host "目标路径无效或不存在: $cleanedPath" -ForegroundColor Red
            }
        } else {
            Write-Host "未选择任何目录。" -ForegroundColor Yellow
        }
    }
    else {
        # 非 fzf 模式
        if ([string]::IsNullOrWhiteSpace($Path)) {
            Set-Location ('..\' * $LevelsUp).TrimEnd('\')
        }
        else {
            $normalizedPath = $Path.Replace('\', [IO.Path]::DirectorySeparatorChar)
            $target = Join-Path $baseDir $normalizedPath
            if (Test-Path -LiteralPath $target -PathType Container) {
                Set-Location $target
            }
            else {
                Write-Host "路径不存在: $target" -ForegroundColor Red
            }
        }
    }
}
# ===================================================================
#  快速返回上级目录（支持 -fzf 和 <path>）
# ===================================================================
function global:..    { Invoke-ParentNavigate -LevelsUp 1 @args }
function global:...   { Invoke-ParentNavigate -LevelsUp 2 @args }
function global:....  { Invoke-ParentNavigate -LevelsUp 3 @args }

# ===================================================================
#  智能打开：open 命令
# ===================================================================
function global:open {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    # === 1. 检测是否为 URL ===
    $urlPattern = '^(https?://|www\.)|(\w+\.\w+)'
    $sanitizedTarget = $Target.Trim()

    if ($sanitizedTarget -match $urlPattern) {
        $url = $sanitizedTarget
        if ($url -like "www.*")      { $url = "https://" + $url }
        elseif ($url -notlike "http*"){ $url = "https://" + $url }

        try {
            $uri = [uri]$url
            if ($uri.Scheme -in @('http', 'https')) {
                $choice = Read-Host @"
🌐 即将打开网页：
    $url

是否在默认浏览器中打开？[Y/n]
"@
                if ($choice -notmatch '^[Yy]$|^$') {
                    Write-Host "操作已取消。" -ForegroundColor Yellow
                    return
                }
                Start-Process $url
                return
            }
        }
        catch { }
    }

    # === 2. 打开当前目录 ===
    if ($Target -eq '.') {
        explorer $PWD
        return
    }

    # === 3. 解析路径：优先从 $script:paths 查找 ===
    $path = $script:paths.ContainsKey($Target) ? $script:paths[$Target] : $Target

    # === 4. 网络路径安全警告 ===
    if ($path -like "\\*") {
        $choice = Read-Host @"
⚠️  即将打开一个网络位置：
    $path

网络共享可能包含恶意文件或窃取凭据。
仅在你信任该设备和网络时继续。

是否继续打开？[y/N]
"@
        if ($choice -notmatch '^[Yy]$') {
            Write-Host "操作已取消。" -ForegroundColor Yellow
            return
        }
        explorer $path
        return
    }

    # === 5. 检查本地路径存在性 ===
    if (-not (Test-Path $path)) {
        Write-Error "路径或文件不存在: $path"
        return
    }

    # === 6. 判断类型并打开 ===
    $item = Get-Item $path
    if ($item.PSIsContainer) {
        explorer $item.FullName
    }
    else {
        $ext = $item.Extension.ToLower()
        $executables = @('.exe', '.msi', '.bat', '.cmd', '.ps1', '.vbs', '.scr', '.pif', '.lnk')

        if ($executables -contains $ext) {
            $choice = Read-Host @"
⚠️  检测到可执行文件: $($item.Name)

此类文件可能包含病毒或恶意程序。
仅在你完全信任来源时运行。

是否继续打开？[Y/n]
"@
            if ($choice -notmatch '^[Yy]$|^$') {
                Write-Host "操作已取消。" -ForegroundColor Yellow
                return
            }
        }
        Invoke-Item $item.FullName
    }
}
