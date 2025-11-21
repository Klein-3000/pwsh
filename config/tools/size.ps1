function global:size {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [string]$Path = ".",

        [ValidateSet('Asc', 'Desc')]
        [string]$Order = 'Asc',

        [switch]$h,
        [switch]$d,
        [switch]$f,
        [switch]$T,
        [int]$Top,
        [string]$Filter,
        [switch]$v  # ✅ 新增 -v 参数：显示版本号
    )

    # ✅ 将 Format-FileSize 提前定义！
    function Format-FileSize($bytes) {
        if ($bytes -ge 1TB) { "{0:F1} TB" -f ($bytes / 1TB) }
        elseif ($bytes -ge 1GB) { "{0:F1} GB" -f ($bytes / 1GB) }
        elseif ($bytes -ge 1MB) { "{0:F1} MB" -f ($bytes / 1MB) }
        elseif ($bytes -ge 1KB) { "{0:F1} KB" -f ($bytes / 1KB) }
        else { "$bytes B" }
    }

    # ✅ 处理 -v：输出版本号
    if ($v) {
        Write-Host "size v0.0.2"
        return
    }

    if ($h) {
        Write-Host "`nsize v0.0.2 - 文件/目录大小可视化工具`n" -ForegroundColor Cyan
        Write-Host "用法:" -ForegroundColor Yellow
        Write-Host "    size [-Path <路径>] [-Order Asc|Desc] [-d|-f] [-T] [-Top <n>] [-Filter <模式>] [-h] [-v]`n"
        Write-Host "参数:" -ForegroundColor Yellow
        Write-Host "    -Path      " -NoNewline; Write-Host "目标路径（默认: 当前目录）"
        Write-Host "    -Order     " -NoNewline; Write-Host "排序方式：Asc（小→大）, Desc（大→小）"
        Write-Host "    -d         " -NoNewline; Write-Host "仅显示子目录"
        Write-Host "    -f         " -NoNewline; Write-Host "仅显示文件"
        Write-Host "    -T         " -NoNewline; Write-Host "仅显示总大小"
        Write-Host "    -Top <n>   " -NoNewline; Write-Host "只显示前 n 个最大项（n > 0）"
        Write-Host "    -Filter    " -NoNewline; Write-Host "按名称过滤（支持 *.log, config*, ?.txt 等通配符）"
        Write-Host "    -h         " -NoNewline; Write-Host "显示帮助"
        Write-Host "    -v         " -NoNewline; Write-Host "显示版本号`n"
        Write-Host "示例:" -ForegroundColor Yellow
        Write-Host "    size -T                          # 显示当前目录总大小"
        Write-Host "    size -Top 5                     # 显示最大的 5 个项目"
        Write-Host "    size -Filter *.log              # 只显示 .log 文件"
        Write-Host "    size -d -Top 3 -Order Desc      # 最大的 3 个目录，降序"
        Write-Host "    size -f -Filter 'temp*'         # 所有以 temp 开头的文件"
        Write-Host "    size -v                         # 显示版本号"
        return
    }

    # 互斥检查：-d 和 -f 不能同时使用
    if ($d -and $f) {
        Write-Warning "参数 -d 和 -f 不能同时使用。请只选择其中一个，或都不使用以显示全部内容。"
        Write-Host "用法示例:" -ForegroundColor Yellow
        Write-Host "    size -d           # 仅显示目录"
        Write-Host "    size -f           # 仅显示文件"
        Write-Host "    size              # 显示所有" -ForegroundColor Gray
        return
    }

    # 获取目标路径下的所有项目（包含隐藏项）
    $items = Get-ChildItem $Path -Force -ErrorAction SilentlyContinue
    if (-not $items) {
        Write-Warning "未找到文件或路径无效: $Path"
        return
    }

    # 计算每个项目的大小
    $itemSizes = @()
    foreach ($item in $items) {
        if ($item.PSIsContainer) {
            # 目录：累加所有文件大小
            $files = Get-ChildItem $item.FullName -File -Recurse -ErrorAction SilentlyContinue
            $size = ($files | Measure-Object -Property Length -Sum).Sum
            if ($null -eq $size) { $size = 0 }
        } else {
            # 文件：直接取 Length
            $size = $item.Length
        }
        $itemSizes += [PSCustomObject]@{
            Name = $item.Name
            Size = $size
            IsDirectory = $item.PSIsContainer
        }
    }

    # 过滤：-d（仅目录）或 -f（仅文件）
    if ($d) {
        $itemSizes = $itemSizes | Where-Object { $_.IsDirectory }
        if (-not $itemSizes) {
            Write-Warning "当前目录下无子目录"
            return
        }
    }
    if ($f) {
        $itemSizes = $itemSizes | Where-Object { -not $_.IsDirectory }
        if (-not $itemSizes) {
            Write-Warning "当前目录下无文件"
            return
        }
    }

    # 过滤：-Filter（按名称匹配）
    if ($Filter) {
        $filtered = $itemSizes | Where-Object { $_.Name -like $Filter }
        if (-not $filtered) {
            Write-Warning "未找到匹配 '$Filter' 的项目"
            return
        }
        $itemSizes = $filtered
    }

    # 排序
    $Sorted = switch ($Order) {
        'Desc' { $itemSizes | Sort-Object Size -Descending }
        Default { $itemSizes | Sort-Object Size }
    }

    # ✅ -T：只显示总大小
    if ($T) {
        $total = ($Sorted | Measure-Object -Property Size -Sum).Sum
        $totalStr = Format-FileSize $total
        $pathDisplay = if ($Path -eq ".") { "当前目录" } else { "'$Path'" }
        Write-Host "`n📁 $pathDisplay 的总大小: " -NoNewline -ForegroundColor Cyan
        Write-Host "$totalStr" -ForegroundColor Green
        return
    }

    # ✅ -Top：只保留前 N 项
    if ($Top -gt 0) {
        $Sorted = $Sorted | Select-Object -First $Top
        if (-not $Sorted) {
            Write-Warning "没有符合条件的项目"
            return
        }
    }

    # 归一化用的最大值
    $MaxSize = ($Sorted | Measure-Object -Property Size -Maximum).Maximum
    if ($MaxSize -eq 0) { $MaxSize = 1 }

    # 获取终端宽度
    try {
        $Width = $Host.UI.RawUI.WindowSize.Width
    } catch { $Width = 80 }

    $BarLength = 20
    if ($Width -lt 60) { $BarLength = 10 }

    $NamePadding = $Width - 15 - $BarLength
    if ($NamePadding -lt 20) { $NamePadding = 20 }

    # 输出每一行
    foreach ($item in $Sorted) {
        $sizeStr = Format-FileSize $item.Size
        $pct = $item.Size / $MaxSize
        $fill = [Math]::Floor($pct * $BarLength)
        $bar = ('█' * $fill) + ('░' * ($BarLength - $fill))

        $name = $item.Name
        if ($name.Length -gt $NamePadding) {
            $cutLen = $NamePadding - 3
            if ($cutLen -le 0) { $name = "" } else {
                $name = "..." + $name.Substring($name.Length - $cutLen)
            }
        }
        $name = $name.PadRight($NamePadding)

        $leftPart = "{0,8}  {1}  " -f $sizeStr, $bar

        Write-Host -NoNewline -ForegroundColor White $leftPart
        if ($item.IsDirectory) {
            Write-Host -ForegroundColor Blue $name   # 目录：蓝色
        } else {
            Write-Host -ForegroundColor White $name  # 文件：白色
        }
    }
}
