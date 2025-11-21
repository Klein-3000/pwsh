# ===================================================================
#  paths.ps1 - 路径跳转函数与变量生成器（完整修复版）
#  ✅ 支持用户自定义覆盖默认路径
#  ✅ 生成跳转命令 + 全局变量（如 ${mydosc}）
#  ✅ 新增：支持 -fzf 参数调用 fzf 交互选择子目录
#  ✅ 共用 $env:POSH_FZF_PREVIEW_CMD 预览命令
#  🔧 调试开关：$env:DEBUG_PATHS=1; . $PROFILE
# ===================================================================

# 调试模式：通过环境变量控制
$DEBUG_PATHS = ($env:DEBUG_PATHS -eq "1") -or ($env:DEBUG_PATHS -eq "true")

# 配置文件路径
$CONFIG_DIR = $PSScriptRoot
$defaultFile = Join-Path $CONFIG_DIR "paths.default.json"
$userFile    = Join-Path $CONFIG_DIR "paths.user.json"

# 如果用户配置不存在，自动创建
if (-not (Test-Path $userFile)) {
    Write-Host "🆕 首次运行：创建用户配置文件 $userFile" -ForegroundColor Yellow
    if (Test-Path $defaultFile) {
        Copy-Item $defaultFile $userFile
        Write-Host "✅ 已生成用户配置，请根据需要修改 $userFile" -ForegroundColor Green
    }
    else {
        Write-Error "❌ 错误：未找到默认配置文件 $defaultFile"
        return
    }
}

# 读取默认配置
try {
    $defaultPaths = Get-Content $defaultFile | ConvertFrom-Json -AsHashtable
}
catch {
    Write-Error "❌ 解析 default.json 失败: $_"
    return
}

# 读取用户配置
try {
    $userPaths = Get-Content $userFile | ConvertFrom-Json -AsHashtable
}
catch {
    Write-Error "❌ 解析 user.json 失败: $_"
    return
}

# 合并路径：用户 > 默认，支持新增键
$script:paths = @{}
$allKeys = ($defaultPaths.Keys + $userPaths.Keys) | Sort-Object -Unique

foreach ($key in $allKeys) {
    if ($userPaths.ContainsKey($key)) {
        $script:paths[$key] = $userPaths[$key]
    }
    else {
        $script:paths[$key] = $defaultPaths[$key]
    }

    # 扩展变量：支持 $home, $env:APPDATA 等
    $expanded = $script:paths[$key] `
        -replace '\$home', $HOME `
        -replace '\$env:APPDATA', $env:APPDATA `
        -replace '\$env:LOCALAPPDATA', $env:LOCALAPPDATA `
        -replace '\$env:USERPROFILE', $env:USERPROFILE

    $script:paths[$key] = $expanded
}

# 调试输出
if ($DEBUG_PATHS) {
    Write-Host "`n🔧 开始生成跳转函数与全局变量..." -ForegroundColor Magenta
}

# 清理旧函数（避免重复定义）
if (Get-PSDrive -Name Function -ErrorAction SilentlyContinue) {
    Get-ChildItem Function:\ | Where-Object {
        $_.ModuleName -eq $null -and $script:paths.ContainsKey($_.Name)
    } | Remove-Item -ErrorAction SilentlyContinue
}

# 为每个路径生成跳转函数 + 全局变量
foreach ($key in $script:paths.Keys) {
    $root = $script:paths[$key]
    $rootDisplay = if ([string]::IsNullOrWhiteSpace($root)) { "<空>" } else { $root }

    if ($DEBUG_PATHS) {
        Write-Host "  📌 $key`:`t→ $rootDisplay" -ForegroundColor Gray
    }

    # ✅ 创建全局变量：如 $global:mydosc
    Set-Variable -Name $key -Value $root -Scope Global -Force

    # ✅ 创建跳转函数（支持 -fzf）
    $currentKey = $key
    $currentPaths = $script:paths

    $functionBody = {
        param(
            [Parameter(Position = 0)]
            [string]$SubPath = '',

            [Parameter()]
            [switch]$Fzf
        )

        $root = $currentPaths[$currentKey]
        if (-not $root) {
            Write-Error "❌ 路径 '$currentKey' 未定义或为空"
            return
        }

        if (-not (Test-Path -LiteralPath $root)) {
            Write-Error "❌ 根路径不存在: $root"
            return
        }

        # ========== 非 Fzf 模式：直接跳转 ==========
        if (-not $Fzf) {
            if (-not $SubPath.Trim()) {
                Set-Location $root
                return
            }

            $normalized = $SubPath -replace '[\\/]', [IO.Path]::DirectorySeparatorChar
            $target = Join-Path $root $normalized

            if (Test-Path -LiteralPath $target -PathType Container) {
                Set-Location $target
            }
            else {
                Write-Error "目录不存在或不是文件夹: $target"
            }
            return
        }

        # ========== Fzf 模式：交互式选择子目录 ==========
        $target = $root

        if ($SubPath.Trim()) {
            $normalizedPath = $SubPath -replace '[\\/]', [IO.Path]::DirectorySeparatorChar
            $target = Join-Path $root $normalizedPath
            if (-not (Test-Path -LiteralPath $target -PathType Container)) {
                Write-Error "路径不存在: $target"
                return
            }
        }

        $subDirs = Get-ChildItem -LiteralPath $target -Directory | ForEach-Object { $_.FullName }
        if ($subDirs.Count -eq 0) {
            Write-Warning "目标目录中没有子目录，无法使用 fzf 进行选择。"
            return
        }

        # ✅ 使用环境变量 $env:POSH_FZF_PREVIEW_CMD，未设置则默认为 'ls'
        $previewCmd = $env:POSH_FZF_PREVIEW_CMD ?? 'ls'

        $selected = $subDirs | fzf --height=50% --preview "$previewCmd {}" --preview-window=right,70%

        if (-not $selected) {
            Write-Host "未选择任何目录。" -ForegroundColor Yellow
            return
        }

        # ✅ 清理隐藏字符并验证路径
        $cleanedPath = $selected.Trim() -replace "[\uFEFF\u200B]", ""

        if (Test-Path -LiteralPath $cleanedPath -PathType Container) {
            Set-Location -LiteralPath $cleanedPath
            Write-Host "已进入: $(Resolve-Path .)" -ForegroundColor Green
        } else {
            Write-Error "目标路径无效或不存在: $cleanedPath"
        }
    }.GetNewClosure()  # ✅ 必须紧贴 } 后面，不能换行！

    New-Item -Path "Function:\global:$key" -Value $functionBody -Force | Out-Null
}

# ✅ 增强版 list-path：支持 -Right 排序
function global:list-path {
    <#
    .SYNOPSIS
    列出所有可用的路径跳转命令
    .DESCRIPTION
    默认按别名（key）排序输出。
    使用 -Right 参数时，按路径字符串排序，便于根据路径查找别名。
    .EXAMPLE
    list-path
    # 按别名排序输出
    .EXAMPLE
    list-path -Right
    # 按路径排序（适合记得路径但忘了别名）
    # 相同父目录的路径会聚集，且按长度升序排列
    #>
    [CmdletBinding()]
    param(
        # 按路径排序（右对齐查找模式）
        [switch]$Right
    )

    if (-not $script:paths) {
        Write-Warning "❌ 路径表未定义。"
        return
    }

    if ($script:paths.Count -eq 0) {
        Write-Warning "未定义任何路径跳转命令。"
        return
    }

    $entries = [System.Collections.Generic.List[PSObject]]::new()
    foreach ($key in $script:paths.Keys) {
        $entries.Add([PSCustomObject]@{
            Key  = $key
            Path = $script:paths[$key]
        })
    }

    if ($Right) {
        Write-Host "`n🔍 当前可用路径（按路径排序，便于查找）：" -ForegroundColor Cyan

        $sorted = $entries | Sort-Object {
            $_.Path -replace '\\[^\\]*$', ''  # 父目录
        }, {
            $_.Path.Length                    # 路径长度（升序）
        }, {
            $_.Path                           # 路径本身
        }

        $sorted | Format-Table @{
            Label = 'Alias'
            Expression = { $_.Key.PadRight(10) }
        }, @{
            Label = '→ Path'
            Expression = { $_.Path }
        } -AutoSize
    }
    else {
        Write-Host "`n🎯 当前可用快速跳转命令：" -ForegroundColor Cyan

        $sorted = $entries | Sort-Object Key

        $sorted | Format-Table @{
            Label = 'Alias'
            Expression = { $_.Key.PadRight(12) }
        }, @{
            Label = '→ Path'
            Expression = { $_.Path }
        } -AutoSize
    }
}

# ✅ 查看所有路径变量（如 ${mydosc}）
function global:list-var {
    <#
    .SYNOPSIS
    列出所有由 paths.ps1 创建的全局路径变量
    #>
    if (-not $script:paths) {
        Write-Warning "❌ 路径表未定义。"
        return
    }

    $vars = @()
    foreach ($key in $script:paths.Keys | Sort-Object) {
        $value = Get-Variable -Name $key -ValueOnly -Scope Global -ErrorAction SilentlyContinue
        $vars += [PSCustomObject]@{
            Name  = $key
            Value = $value
        }
    }

    if ($vars.Count -eq 0) {
        Write-Warning "未生成任何全局路径变量。"
        return
    }

    Write-Host "`n🧩 当前可用路径变量（可使用 `${变量名}` 引用）：" -ForegroundColor Cyan
    $vars | Format-Table -AutoSize
}

# 最终提示
# 在 paths.ps1 文件末尾替换为：
if (Get-Command 'Write-ConfigStatus' -ErrorAction Ignore) {
    Write-ConfigStatus "✅ 路径配置已加载（共 $($script:paths.Count) 个命令）" -Color Green
}

# ===================================================================
#  Tab 补全：支持 ${repo}\xxx 的路径自动补全（PowerShell 5.1 兼容版）
# ===================================================================

# 获取所有由 paths.ps1 管理的路径变量名
$RegisteredPathVars = $script:paths.Keys | ForEach-Object { $_, "env:$_" }

# 要监听的参数名列表
$ParameterNames = @('Path', 'LiteralPath', 'Destination', 'FilePath', 'OutputPath', 'ChildPath')

# 对每个参数名单独注册补全器（PowerShell 5.1 不支持数组）
foreach ($paramName in $ParameterNames) {
    Register-ArgumentCompleter -CommandName '*' -ParameterName $paramName -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        # 只处理以 ${ 开头的变量引用
        if ($wordToComplete -notmatch '^\$\{([^}]+)\}(.*)$') { return }

        $varName = $matches[1]
        $pathPart = $matches[2]

        # 判断是否是注册过的路径变量
        if ($varName -notin $script:paths.Keys) {
            return
        }

        # 获取变量值
        $basePath = Get-Variable -Name $varName -ValueOnly -Scope Global -ErrorAction SilentlyContinue
        if (-not $basePath -or -not (Test-Path $basePath)) {
            return
        }

        # 拼接当前输入的子路径
        $searchPath = Join-Path $basePath $pathPart.TrimStart('\','/')

        # 查找匹配的文件和目录
        $items = @()
        if (Test-Path $searchPath) {
            $items += Get-Item $searchPath
        }
        $items += Get-ChildItem $basePath -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like "$($pathPart.TrimStart('\','/'))*" -and $_.Name -ne ''
        }

        # 去重并生成补全结果
        $completions = $items | ForEach-Object {
            $completionText = "`${$varName}" + ($_.FullName.Substring($basePath.Length) -replace '\\', '/') -replace '^/$', ''
            $listItemText = $_.Name
            $toolTip = $_.FullName
            $completionResultType = if ($_.PSIsContainer) { 'Directory' } else { 'File' }

            [System.Management.Automation.CompletionResult]::new(
                $completionText,
                $listItemText,
                $completionResultType,
                $toolTip
            )
        } | Sort-Object -Property ListItemText -Unique

        $completions
    }
}