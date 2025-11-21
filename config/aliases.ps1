Set-Alias scb Set-Clipboard

# wezterm command alias
# 推荐：创建一个函数作为 imgcat 别名
function global:imgcat {
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$Path
    )
    wezterm imgcat $Path
}
