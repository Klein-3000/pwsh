# ===================================================================
#  PowerShell 模块化配置文件 (Microsoft.PowerShell_profile.ps1)
#  作者: Klein-3000 
#  版本: 1.0.0
#  目标: 提供可维护、可扩展、高性能的 PowerShell 启动体验
# ===================================================================

# ===============================
#  环境变量设置
# ===============================
$env:EDITOR = "nvim"
$env:POSH_FZF_PREVIEW_CMD = "eza --icons"
$env:OBEXE_HOME = "D:\obsidian\obsidian.exe"
$env:Path += ";C:\Program Files\Git\usr\bin"
# 加载信息提示 (默认不输出提示信息)
# $env:POWERSHELL_CONFIG_DEBUG=1

# ===============================
#  解决中文乱码 & 输出编码问题
# ===============================
[Console]::InputEncoding = [Console]::OutputEncoding = [Text.Encoding]::Utf8
$OutputEncoding = [Text.Encoding]::Utf8

# PowerShell 7+ 真彩色支持（如果使用 pwsh）
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PSStyle.OutputRendering = 'ANSI'
}

# ===============================
#  设置配置目录（仅在未定义时创建为常量）
# ===============================
if (-not (Get-Variable -Name CONFIG_DIR -Scope Script -ErrorAction Ignore)) {
    Set-Variable -Name CONFIG_DIR -Value (Join-Path $PSScriptRoot "config") -Scope Script -Option Constant
}

# ===============================
#  定义核心配置文件路径（有序，避免加载顺序问题）
# ===============================
$config_files = [ordered]@{
    paths      = Join-Path $CONFIG_DIR "paths.ps1"
    utils      = Join-Path $CONFIG_DIR "utils.ps1"
    navigation = Join-Path $CONFIG_DIR "navigation.ps1"
    aliases    = Join-Path $CONFIG_DIR "aliases.ps1"
    keyhandler = Join-Path $CONFIG_DIR "keyhandler.ps1"
    network    = Join-Path $CONFIG_DIR "network.ps1"
    tools      = Join-Path $CONFIG_DIR "tools"  # tools 目录路径
}

# ===============================
#  调试开关：支持 1/true/yes/on（不区分大小写）
# ===============================
$env:POWERSHELL_CONFIG_DEBUG = $env:POWERSHELL_CONFIG_DEBUG ?? 'false'
$script:ConfigDebug = @('1', 'true', 'yes', 'on') -contains $env:POWERSHELL_CONFIG_DEBUG.ToString().ToLower().Trim()

# ===============================
#  通用状态输出函数（用于顺序加载和懒加载）
# ===============================
function Write-ConfigStatus {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ConsoleColor]$Color = 'Gray',

        [switch]$Always   # 始终输出（用于错误/警告）
    )

    if ($Always -or $script:ConfigDebug) {
        Write-Host $Message -ForegroundColor $Color
    }
}

# ===============================
#  定义函数：Import-Config
#  用于安全加载核心模块
# ===============================
function Import-Config {
    param([string]$Name)
    $path = $config_files[$Name]
    if (-not $path) {
        Write-Warning "⚠️ 未知模块: $Name"
        return
    }
    if (Test-Path $path) {
        try {
            Write-ConfigStatus "⏳ 加载配置: $Name ..." -Color Gray
            . $path
            Write-ConfigStatus "✅ 已加载: $Name" -Color Green
        }
        catch {
            Write-Error "❌ 加载失败: $Name`n$_" -ErrorAction Continue
        }
    }
    else {
        Write-Warning "⚠️ 配置文件未找到: $path"
    }
}

# ===============================
#  加载所有核心配置模块（顺序重要！）
# ===============================
Import-Config "paths"
Import-Config "utils"
Import-Config "navigation"
Import-Config "aliases"
Import-Config "keyhandler"
Import-Config "network"

# ===============================
#  request 函数（在任何 Import-Config 之前！）
# ===============================
function request {
    param(
        [Parameter(Mandatory)]
        [string]$ResourceSpec
    )

    # 解析格式：type:name
    if ($ResourceSpec -notmatch "^(\w+):(.+)$") {
        Write-Error "❌ 格式错误：请使用 'type:name' 格式，如 'module:font'"
        return $false
    }

    $type = $matches[1].ToLower()
    $name = $matches[2]

    # 定义资源类型映射
    $ResourceMap = @{
        module = "modules"
        theme  = "themes"
        plugin = "plugins"
        lib    = "libs"
        # 可随时扩展
    }

    if (-not $ResourceMap.ContainsKey($type)) {
        Write-Error "❌ 不支持的资源类型: '$type'。支持的类型: $($ResourceMap.Keys -join ', ')"
        return $false
    }

    $basePath = Join-Path $CONFIG_DIR $ResourceMap[$type]
    $resourcePath = Join-Path $basePath $name

    if (-not (Test-Path $resourcePath)) {
        Write-Error "❌ 资源不存在: $resourcePath"
        return $false
    }

    # 加载该目录下所有 .ps1 文件
    $scripts = Get-ChildItem $resourcePath -Filter "*.ps1" -File
    if ($scripts.Count -eq 0) {
        Write-Warning "⚠️ 该资源目录中没有 .ps1 文件: $resourcePath"
        return $true  # 不算错误，只是空目录
    }

    $loaded = 0
    foreach ($file in $scripts) {
        try {
            . $file.FullName
            Write-Verbose "✅ 加载 [$type] 组件: $name/$($file.BaseName)"
            $loaded++
        }
        catch {
            Write-Error "❌ 加载失败: $name/$($file.Name)`n$_"
        }
    }

    Write-ConfigStatus "✅ 已加载 '$name' ($type)，共 $loaded 个脚本" -Color Green
    return $true
}

# ===============================
#  模式设置
# ===============================
Set-PSReadLineOption -EditMode Emacs

# ===============================
#  注册 config/tools/ 中的工具脚本（懒加载）
# ===============================
$toolsDir = $config_files.tools
$script:tools = [ordered]@{}
$script:loaded_tools = @()  # 记录已加载的工具名

if (Test-Path $toolsDir) {
    Write-ConfigStatus "🔍 扫描工具脚本（懒加载）..." -Color Gray

    # 只获取根目录下的 .ps1 文件
    $toolScripts = Get-ChildItem $toolsDir -File -Filter "*.ps1" | Where-Object {
        $_.DirectoryName -eq $toolsDir
    } | Sort-Object Name

    foreach ($file in $toolScripts) {
        $toolName = $file.BaseName
        $script:tools[$toolName] = $file.FullName  # 记录路径用于调试

        # 创建懒加载函数（使用闭包避免变量捕获问题）
        $loaderScript = "
        function global:$toolName {
            if (`$script:loaded_tools -notcontains '$toolName') {
                Write-ConfigStatus '⏳ 正在加载工具: $toolName ...' -Color Gray
                try {
                    . '$($file.FullName)'
                    `$script:loaded_tools += '$toolName'
                    Write-ConfigStatus '✅ $toolName 已加载' -Color Green

                    # 🔥 关键修复：加载完成后，删除当前懒加载函数
                    Remove-Item 'function:global:$toolName' -ErrorAction SilentlyContinue

                    # 如果脚本定义了同名命令，则直接调用一次
                    if (Get-Command '$toolName' -CommandType Function, Cmdlet, Application -ErrorAction Ignore) {
                        & '$toolName' @args
                    }
                    return
                }
                catch {
                    Write-Error '❌ 加载失败: $toolName`n\$_' -ErrorAction Continue
                    return
                }
            }

            # ✅ 安全兜底：如果已加载但命令未正确定义
            Write-Warning '⚠️ $toolName 已加载，但未找到可用命令。'
        }
        "

        try {
            Invoke-Expression $loaderScript
            Write-ConfigStatus "💤 已注册懒加载命令: $toolName" -Color Yellow
        }
        catch {
            Write-Warning "⚠️ 无法注册懒加载命令: $toolName"
        }
    }

    Write-ConfigStatus "✅ 共注册了 $($toolScripts.Count) 个懒加载工具" -Color Cyan
}
else {
    Write-Warning "⚠️ 工具目录不存在: $toolsDir"
    Write-ConfigStatus "💡 提示: 你可以创建该目录并放入自定义工具脚本。" -Color Yellow
}

# ===============================
#  外观与主题 (Starship)
# ===============================
try {
    $env:STARSHIP_CONFIG = "$PSScriptRoot\StarshipTheme\starship.CoryCharlton"
    Invoke-Expression (&starship init powershell) -ErrorAction Stop
}
catch {
    Write-Warning "⚠️ Starship 初始化失败，确保已安装 starship"
}

# ===============================
#  加载Module
# ===============================
# 导入模块
Import-Module PSFzf

# 设置 Tab 键使用 fzf 补全
Set-PSReadLineKeyHandler -Key Tab -ScriptBlock { Invoke-FzfTabCompletion }

# 更详细的配置：
# ctrl+t ： 只递归当前的目录
$env:FZF_CTRL_T_COMMAND = 'Get-ChildItem -Recurse | ForEach-Object FullName'
Set-PsFzfOption `
  -EnableAliasFuzzyCommand `
  -EnableAliasFuzzyEdit `
  -PSReadlineChordProvider 'Ctrl+t' `
  -PSReadlineChordReverseHistory 'Ctrl+r'

# 修复 Ctrl+T 路径拼接问题
Set-PSReadLineKeyHandler -Key 'Ctrl+t' -ScriptBlock {
    $files = Get-ChildItem -Recurse | ForEach-Object {
        if ($_.PSIsContainer) {
            Join-Path $PWD.Path $_.Name
        } else {
            $_.FullName
        }
    } | Invoke-Fzf -Multi -Select1 -Exit0

    if ($files) {
        $quotedFiles = $files | ForEach-Object { "'$_'" }
        $result = ($quotedFiles -join ' ')
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($result)
    }
}
# terminal-icons
Import-module Terminal-Icons

# ✅ 修复 Alt+C：自动刷新提示符
Set-PSReadLineKeyHandler -Key 'Alt+c' -ScriptBlock {
    $dir = Get-ChildItem -Directory -Recurse | ForEach-Object FullName | Invoke-Fzf -Select1 -Exit0
    if ($dir) {
        cd $dir
        Write-Host "`nChanged location to: $dir" -ForegroundColor Green
    }
}

# ===============================
#  启动完成提示（可静音）
# ===============================
if ($env:POWERSHELL_CONFIG_QUIET -ne 'true') {
    Write-Host "🎉 PowerShell 配置已加载" -ForegroundColor Cyan
}

# ===============================
#  便捷命令
# ===============================
# 创建重新加载配置的函数（不是别名）
function global:reload {
    . $PROFILE
    Write-Host "✅ PowerShell 配置已重新加载" -ForegroundColor Green
}

Set-PSReadLineKeyHandler -Key 'Alt+r' -ScriptBlock {
    $current = (Get-Location).Path
    Start-Process explorer $current
}
