Set-PSReadLineKeyHandler -Key 'Alt+r' -ScriptBlock {
    $current = (Get-Location).Path
    Start-Process explorer $current
}
# ===================================================================
#  🔧 keyhandler.ps1 - 静默版 Alt+E（推荐）
#  ✅ 成功：替换为 notepad
#  ❌ 失败：无提示，无光标移动，不打断输入
# ===================================================================

Set-PSReadLineKeyHandler -Key 'Alt+e' -ScriptBlock {
    param($key, $arg)

    # 🔍 1. 获取上一条命令
    $history = Get-History -Count 1 -ErrorAction SilentlyContinue
    if (-not $history) { return }

    $commandLine = $history.CommandLine.Trim()
    $tokens = $commandLine -split '\s+', 2
    if ($tokens.Length -lt 2) { return }

    $cmd = $tokens[0].ToLower()
    $arg = $tokens[1].Trim()

    # 🔍 2. 支持的 cat 命令
    $CatCommands = @('cat', 'type', 'gc', 'get-content')
    if ($cmd -notin $CatCommands) { return }

    # 🔍 3. 解析文件路径（支持 $profile, $aliases 等变量）
    $filePath = $null

    if ($arg -like '$*') {
        $varName = $arg.TrimStart('$')
        switch ($varName) {
            'profile'   { $filePath = $PROFILE }
            'aliases'   { $filePath = Get-Variable -Name aliases -ValueOnly -ErrorAction SilentlyContinue }
            'navigation'{ $filePath = Get-Variable -Name navigation -ValueOnly -ErrorAction SilentlyContinue }
            'paths'     { $filePath = Get-Variable -Name paths -ValueOnly -ErrorAction SilentlyContinue }
            'utils'     { $filePath = Get-Variable -Name utils -ValueOnly -ErrorAction SilentlyContinue }
            'keyhandler'{ $filePath = Get-Variable -Name keyhandler -ValueOnly -ErrorAction SilentlyContinue }
            default {
                $var = Get-Variable -Name $varName -ValueOnly -ErrorAction SilentlyContinue
                if ($var -and (Test-Path $var -PathType Leaf)) {
                    $filePath = $var
                }
            }
        }
    }
    else {
        $filePath = $arg
    }

    # 🔍 4. 验证文件存在
    if (-not $filePath -or -not (Test-Path $filePath -PathType Leaf)) {
        return
    }

    # ✅ 5. 构造 notepad 命令
    $resolvedPath = Resolve-Path $filePath
    $quotedPath = if ($resolvedPath -match '\s') { "`"$resolvedPath`"" } else { $resolvedPath }
    $newCommand = "notepad $quotedPath"

    # 替换当前行
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert($newCommand)
    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($newCommand.Length)
}