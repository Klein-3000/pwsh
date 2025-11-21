function global:cat-git {
    Get-Content 'C:\Users\Lenovo\.gitconfig'
}

function global:ln {
    [CmdletBinding()]
    param(
        # ✅ 关键：去掉 Position，只能用 -s 调用
        [switch]$s,

        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Target,

        [Parameter(Position = 1, Mandatory = $true)]
        [string]$Link
    )

    $ItemType = if ($s) { "SymbolicLink" } else { "HardLink" }

    try {
        if (Test-Path $Link) {
            $existingItem = Get-Item $Link -ErrorAction SilentlyContinue
            if ($existingItem.LinkType -eq "SymbolicLink") {
                Write-Warning "链接 '$Link' 已存在。"
                return
            }
            else {
                Write-Error "目标路径 '$Link' 已存在且不是链接，无法覆盖。"
                return
            }
        }

        if (-not (Test-Path $Target)) {
            Write-Error "目标 '$Target' 不存在，无法创建链接。"
            return
        }

        New-Item -ItemType $ItemType -Path $Link -Target $Target -ErrorAction Stop | Out-Null
        $linkTypeStr = if ($s) { "符号链接" } else { "硬链接" }
        Write-Host "$linkTypeStr 已创建: '$Link' -> '$Target'" -ForegroundColor Green
    }
    catch [System.UnauthorizedAccessException] {
        Write-Error "权限不足。请以管理员身份运行 PowerShell，或启用 '开发者模式'。"
    }
    catch {
        Write-Error "创建链接失败: $($_.Exception.Message)"
    }
}

function global:myrun {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Name,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )

    $configFile = Join-Path $PSScriptRoot "program.json"
    if (-not (Test-Path $configFile)) {
        Write-Warning "❌ 程序配置文件不存在: $configFile"
        return
    }

    try {
        $programs = Get-Content $configFile -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "❌ 无法解析 program.json: $($_.Exception.Message)"
        return
    }

    if (-not $programs.PSObject.Properties.Name.Contains($Name)) {
        Write-Warning "❌ 未找到程序别名: '$Name'"
        return
    }

    $programPath = $programs.$Name
    if (-not (Test-Path $programPath)) {
        Write-Warning "❌ 程序路径不存在: $programPath"
        return
    }

    # ✅ 直接使用 Start-Process（别名 start），无需判断扩展名
    Start-Process $programPath -ArgumentList $Args -WorkingDirectory (Split-Path $programPath) -Verb "Open"
}

# ========== 增强版 rreplace 函数 ==========
function global:rreplace {
    [CmdletBinding(DefaultParameterSetName="Repeat")]
    param(
        [Parameter(ParameterSetName="ReplaceText")]
        [Alias('s')]
        [switch]$Replace,

        [Parameter(Position=0, ParameterSetName="ReplaceText")]
        [string]$Old,

        [Parameter(Position=1, ParameterSetName="ReplaceText")]
        [string]$New,

        [Parameter(Mandatory, Position=0, ParameterSetName="ReplaceLast")]
        [Alias('l')]
        [string]$Last,

        [Parameter(Mandatory, Position=0, ParameterSetName="ReplaceCommand")]
        [Alias('f')]
        [string]$Command
    )

    $history = Get-History | Where-Object { $_.CommandLine -notmatch '^\s*r(\s.*)?$' }
    if (-not $history) {
        Write-Warning "没有找到可执行的历史命令。"
        return
    }

    $lastCmd = $history[-1].CommandLine
    $parts = $lastCmd -split ' ', 2
    $cmd = $parts[0]
    $argsStr = if ($parts.Count -eq 2) { $parts[1] } else { '' }

    switch ($PSCmdlet.ParameterSetName) {
        "Repeat" {
            Write-Host "执行: $lastCmd" -ForegroundColor Green
            Invoke-Expression $lastCmd
            return
        }

        "ReplaceText" {
            if ([string]::IsNullOrWhiteSpace($Old)) {
                Write-Warning "请提供要替换的文本。"
                return
            }
            $newCmd = $lastCmd -replace [regex]::Escape($Old), $New
        }

        "ReplaceLast" {
            if ([string]::IsNullOrWhiteSpace($argsStr)) {
                $newCmd = "$cmd $Last"
            } else {
                $argList = $argsStr -split ' '
                $argList[-1] = $Last
                $newCmd = "$cmd " + ($argList -join ' ')
            }
        }

        "ReplaceCommand" {
            if ([string]::IsNullOrWhiteSpace($argsStr)) {
                $newCmd = $Command
            } else {
                $newCmd = "$Command $argsStr"
            }
        }
    }

    Write-Host "原命令: $lastCmd" -ForegroundColor Gray
    Write-Host "新命令: $newCmd" -ForegroundColor Green
    Invoke-Expression $newCmd
}

# 覆盖原生 r 别名
Remove-Item Alias:\r -ErrorAction SilentlyContinue
Set-Alias -Name r -Value rreplace -Scope Global -Force
