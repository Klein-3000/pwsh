function global:tree {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path = ".",

        [int]$L = [int]::MaxValue,

        [int]$CurrentLevel = 0,

        [string]$Prefix = "",

        [bool]$IsLast = $true,

        [switch]$c,           # 显示统计信息 (dir:x; file:y)

        [switch]$h,           # 显示帮助

        [string[]]$i,         # 忽略模式（通配符），如 "f*", "*.log"

        [switch]$NoIgnore     # 不读取 ~/.tree 配置
    )

    if ($h) {
        Write-Host "`ntree v1.2 - 以树状结构显示目录内容（支持 ~/.tree 配置）`n" -ForegroundColor Cyan

        Write-Host "用法:" -ForegroundColor Yellow
        Write-Host "    tree [-Path <string>] [-L <int>] [-c] [-i <pattern>...] [-NoIgnore] [-h]`n"

        Write-Host "参数:" -ForegroundColor Yellow
        Write-Host "    -Path <string>        " -NoNewline -ForegroundColor White
        Write-Host "要显示的路径（默认: 当前目录）"

        Write-Host "    -L <int>              " -NoNewline -ForegroundColor White
        Write-Host "最大显示深度（默认: 无限）"

        Write-Host "    -c                    " -NoNewline -ForegroundColor White
        Write-Host "显示每个目录的统计信息 (dir:x; file:y)"

        Write-Host "    -i <pattern>          " -NoNewline -ForegroundColor White
        Write-Host "忽略匹配名称的项（支持 * 通配符，多个用逗号分隔）"

        Write-Host "    -NoIgnore             " -NoNewline -ForegroundColor White
        Write-Host "忽略 ~/.tree 配置文件（仅使用命令行 -i）"

        Write-Host "    -h, --help            " -NoNewline -ForegroundColor White
        Write-Host "显示此帮助信息并退出`n"

        Write-Host "配置文件:" -ForegroundColor Yellow
        Write-Host "    ~/.tree               每行一个忽略模式（支持 *），以 # 开头为注释`n"

        Write-Host "示例:" -ForegroundColor Yellow
        Write-Host "    tree                                  # 使用 ~/.tree + 默认行为"
        Write-Host "    tree -i 'build*','*.tmp'              # 合并 ~/.tree 和命令行忽略"
        Write-Host "    tree -NoIgnore                        # 完全忽略 ~/.tree"
        Write-Host "    tree -NoIgnore -i 'temp*'             # 仅使用命令行忽略"
        return
    }

    # === 构建最终忽略列表 ===
    $EffectiveIgnore = @()

    # 1. 从 ~/.tree 读取（除非 -NoIgnore）
    if (-not $NoIgnore) {
        $ConfigPath = Join-Path $HOME ".tree"
        if (Test-Path -Path $ConfigPath -PathType Leaf) {
            try {
                $ConfigLines = Get-Content $ConfigPath -ErrorAction Stop |
                    ForEach-Object { $_.Trim() } |
                    Where-Object {
                        $_ -ne "" -and -not $_.StartsWith("#")
                    }
                $EffectiveIgnore += $ConfigLines
            }
            catch {
                # 静默忽略读取错误（权限、编码等）
            }
        }
    }

    # 2. 合并命令行 -i（优先级更高，但实际匹配时顺序无关）
    if ($i) {
        $EffectiveIgnore += $i
    }

    # 去重（可选，非必须，但更干净）
    $EffectiveIgnore = $EffectiveIgnore | Sort-Object -Unique

    # 固定排除项（硬编码，始终生效，即使 -NoIgnore）
    $FixedExcludes = @('.git', '.svn', '.hg', 'node_modules', '__pycache__', 'Thumbs.db', 'desktop.ini')

    # 获取当前项
    $Item = Get-Item $Path -ErrorAction SilentlyContinue
    if (-not $Item) {
        return
    }

    # 非根节点且是固定排除项 → 跳过
    if ($CurrentLevel -gt 0 -and $Item.PSIsContainer -and ($FixedExcludes -contains $Item.Name)) {
        return
    }

    # ========== 显示当前节点 ==========
    if ($CurrentLevel -eq 0) {
        $rootStats = ""
        if ($c) {
            $allChildren = Get-ChildItem $Path -Force -ErrorAction SilentlyContinue
            $filtered = @($allChildren | Where-Object {
                $name = $_.Name
                ($name -notin $FixedExcludes) -and
                (@($EffectiveIgnore | Where-Object { $name -like $_ }).Count -eq 0)
            })
            $dirs  = @($filtered | Where-Object PSIsContainer).Count
            $files = @($filtered | Where-Object { -not $_.PSIsContainer }).Count
            $rootStats = " (dir:$dirs; file:$files)"
        }
        Write-Host $Item.FullName -NoNewline
        if ($rootStats) {
            Write-Host "$rootStats" -ForegroundColor Green
        } else {
            Write-Host ""
        }
    }
    else {
        $connector = if ($IsLast) { '└── ' } else { '├── ' }
        $color = if ($Item.PSIsContainer) { 'DarkCyan' } else { 'White' }

        $stats = ""
        if ($c -and $Item.PSIsContainer) {
            $allChildren = Get-ChildItem $Path -Force -ErrorAction SilentlyContinue
            $filtered = @($allChildren | Where-Object {
                $name = $_.Name
                ($name -notin $FixedExcludes) -and
                (@($EffectiveIgnore | Where-Object { $name -like $_ }).Count -eq 0)
            })
            $dirs  = @($filtered | Where-Object PSIsContainer).Count
            $files = @($filtered | Where-Object { -not $_.PSIsContainer }).Count
            $stats = " (dir:$dirs; file:$files)"
        }

        Write-Host "$Prefix$connector$($Item.Name)" -NoNewline -ForegroundColor $color
        if ($stats) {
            Write-Host "$stats" -ForegroundColor Green
        } else {
            Write-Host ""
        }
    }

    # 停止条件
    if (-not $Item.PSIsContainer -or $CurrentLevel -ge $L) {
        return
    }

    # 获取子项：应用固定排除 + 有效忽略规则
    $Children = @(Get-ChildItem $Path -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $name = $_.Name
            ($name -notin $FixedExcludes) -and
            (@($EffectiveIgnore | Where-Object { $name -like $_ }).Count -eq 0)
        } |
        Sort-Object Name)

    $Total = $Children.Count

    for ($idx = 0; $idx -lt $Total; $idx++) {
        $Child = $Children[$idx]
        $IsLastChild = ($idx -eq ($Total - 1))
        $NewPrefix = if ($IsLast) { "$Prefix    " } else { "$Prefix│   " }

        # 递归调用（传递所有参数，包括 -NoIgnore 和 -i）
        tree -Path $Child.FullName -L $L -CurrentLevel ($CurrentLevel + 1) -Prefix $NewPrefix -IsLast $IsLastChild -c:$c -i $i -NoIgnore:$NoIgnore
    }
}