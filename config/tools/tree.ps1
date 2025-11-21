function global:tree {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [string]$Path = ".",

        [int]$L = [int]::MaxValue,

        [int]$CurrentLevel = 0,

        [string]$Prefix = "",

        [bool]$IsLast = $true,

        [switch]$c,  # 显示统计信息 (dir:x; file:y)

        [switch]$h    # 显示帮助
    )

    if ($h) {
        Write-Host "`ntree v1.0 - 以树状结构显示目录内容`n" -ForegroundColor Cyan

        Write-Host "用法:" -ForegroundColor Yellow
        Write-Host "    tree [-Path <string>] [-L <int>] [-c] [-h]`n"

        Write-Host "参数:" -ForegroundColor Yellow
        Write-Host "    -Path <string)        " -NoNewline -ForegroundColor White
        Write-Host "要显示的路径（默认: 当前目录）"

        Write-Host "    -L <int>              " -NoNewline -ForegroundColor White
        Write-Host "最大显示深度（默认: 无限）"

        Write-Host "    -c                    " -NoNewline -ForegroundColor White
        Write-Host "显示每个目录的统计信息 (dir:x; file:y)"

        Write-Host "    -h, --help            " -NoNewline -ForegroundColor White
        Write-Host "显示此帮助信息并退出`n"

        Write-Host "示例:" -ForegroundColor Yellow
        Write-Host "    tree                  # 显示当前目录树"
        Write-Host "    tree -L 2             # 只显示两层深度"
        Write-Host "    tree -c               # 显示统计信息"
        Write-Host "    tree 'C:\Temp' -L 3   # 指定路径，深度3`n"

        return
    }
    # ✅ 互斥检查
    if ($d -and $f) {
        Write-Warning "参数 -d 和 -f 不能同时使用。请只选择其中一个，或都不使用以显示全部内容。"
        Write-Host "用法示例:" -ForegroundColor Yellow
        Write-Host "    save -d           # 仅显示目录"
        Write-Host "    save -f           # 仅显示文件"
        Write-Host "    save              # 显示所有" -ForegroundColor Gray
        return
    }

    $Item = Get-Item $Path -ErrorAction SilentlyContinue
    if (!$Item) { 
        return  # 路径无效，静默跳过
    }

    $Name = $Item.Name

    # 🔽 固定排除的系统/元数据目录（不包括 .gitignore 等文件）
    $ExcludedDirs = @('.git', '.svn', '.hg', 'node_modules', '__pycache__', 'Thumbs.db', 'desktop.ini')

    # 如果是被排除的目录，且不是根节点，则跳过
    if ($Item.PSIsContainer -and ($ExcludedDirs -contains $Name)) {
        if ($CurrentLevel -gt 0) {
            return  # 不显示，也不展开
        }
        # 根节点是 .git？不可能，但安全起见也跳过
        if ($ExcludedDirs -contains $Name) {
            Write-Warning "无法显示受保护目录: $Path"
            return
        }
    }

    # ========== 显示当前节点 ==========
    if ($CurrentLevel -gt 0) {
        $stats = ""
        if ($c -and $Item.PSIsContainer) {
            # 获取子项，并排除特殊目录
            $children = @(
                Get-ChildItem $Path -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.PSIsContainer -or (-not $_.PSIsContainer -and $_.Name -notin $ExcludedDirs) } |
                Where-Object { $_.Name -notin $ExcludedDirs }
            )
            $dirs = @($children | Where-Object { $_.PSIsContainer }).Count
            $files = @($children | Where-Object { -not $_.PSIsContainer }).Count
            $stats = " (dir:$dirs; file:$files)"
        }

        $connector = if ($IsLast) { '└── ' } else { '├── ' }
        $color = if ($Item.PSIsContainer) { 'DarkCyan' } else { 'White' }

        Write-Host "$Prefix$connector$Name" -NoNewline -ForegroundColor $color
        if ($stats) {
            Write-Host "$stats" -ForegroundColor Green
        } else {
            Write-Host ""
        }
    }
    else {
        # 根节点
        $rootStats = ""
        if ($c) {
            $children = @(
                Get-ChildItem $Path -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notin $ExcludedDirs }
            )
            $dirs = @($children | Where-Object { $_.PSIsContainer }).Count
            $files = @($children | Where-Object { -not $_.PSIsContainer }).Count
            $rootStats = " (dir:$dirs; file:$files)"
        }

        Write-Host $Item.FullName -NoNewline
        if ($rootStats) {
            Write-Host "$rootStats" -ForegroundColor Green
        } else {
            Write-Host ""
        }
    }

    # 如果不是目录或已达到最大深度，停止
    if (!$Item.PSIsContainer -or $CurrentLevel -ge $L) {
        return
    }

    # 获取子项（排除特殊目录）
    $Children = @(
        Get-ChildItem $Path -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notin $ExcludedDirs } |
        Sort-Object Name
    )
    $Total = $Children.Count

    for ($i = 0; $i -lt $Total; $i++) {
        $Child = $Children[$i]
        $IsLastChild = ($i -eq ($Total - 1))

        $NewPrefix = $IsLast ? "$Prefix    " : "$Prefix│   "

        # 递归调用（不再传 -f）
        tree -Path $Child.FullName -L $L -CurrentLevel ($CurrentLevel + 1) -Prefix $NewPrefix -IsLast $IsLastChild -c:$c
    }
}