Add-Type -AssemblyName System.Drawing

function global:ConvertTo-Ico {
    param (
        [string]$InputPath,
        [string]$OutputPath,
        [switch]$Help,
        [switch]$Version
    )

    if ($Help) {
        Write-Host @"
USAGE:
    ConvertTo-Ico -InputPath <源图像文件路径> -OutputPath <目标.ico文件路径>
    ConvertTo-Ico -Help
    ConvertTo-Ico -Version
DESCRIPTION:
    将普通图片转换为符合 Windows 要求的 .ico 图标文件。
"@
        return
    }

    # 版本号
    if ($Version) {
        Write-Host "ConvertTO-ico 0.0.2"
        return
    }

    # 参数验证
    if (-not $InputPath -or -not $OutputPath) {
        Write-Error "必须同时指定 -InputPath 和 -OutputPath。"
        Write-Host "用法: ConvertTo-Ico -InputPath <源> -OutputPath <目标>"
        return
    }

    # 将相对路径转为绝对路径（并验证输入文件存在）
    try {
        $resolvedInput = Resolve-Path -Path $InputPath -ErrorAction Stop
        $absoluteInput = $resolvedInput.Path
    } catch {
        throw "输入文件不存在或路径无效: $InputPath"
    }

    # 输出路径：确保父目录存在，并解析为绝对路径
    $outputDir = Split-Path -Parent -Path $OutputPath
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $absoluteOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

    try {
        # 使用绝对路径加载图像
        $originalImage = [System.Drawing.Image]::FromFile($absoluteInput)

        # 自动选择合适尺寸
        $sizes = @(16, 32, 48, 256) | Where-Object {
            $originalImage.Width -ge $_ -and $originalImage.Height -ge $_
        }
        if ($sizes.Count -eq 0) {
            $minSize = [Math]::Min($originalImage.Width, $originalImage.Height)
            $sizes = @($minSize)
        }

        # 构建 ICO 内存结构
        $memoryStream = New-Object System.IO.MemoryStream
        $binaryWriter = New-Object System.IO.BinaryWriter($memoryStream)

        $binaryWriter.Write([UInt16]0)      # Reserved
        $binaryWriter.Write([UInt16]1)      # Type = icon
        $binaryWriter.Write([UInt16]$sizes.Count)

        $imageDataStreams = @()
        $iconDirEntries = @()

        foreach ($size in $sizes) {
            $bmp = New-Object System.Drawing.Bitmap($size, $size)
            $graphics = [System.Drawing.Graphics]::FromImage($bmp)
            $graphics.InterpolationMode = 'HighQualityBicubic'
            $graphics.DrawImage($originalImage, 0, 0, $size, $size)
            $graphics.Dispose()

            $imgStream = New-Object System.IO.MemoryStream
            $bmp.Save($imgStream, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()

            $data = $imgStream.ToArray()
            $imgStream.Dispose()
            $imageDataStreams += $data

            $widthByte = if ($size -eq 256) { 0 } else { $size }
            $iconDirEntries += [PSCustomObject]@{
                Width        = [byte]$widthByte
                Height       = [byte]$widthByte
                ColorCount   = [byte]0
                Reserved     = [byte]0
                Planes       = [UInt16]1
                BitCount     = [UInt16]32
                BytesInRes   = [UInt32]$data.Length
                ImageOffset  = $null
            }
        }

        # 写入图标目录项
        $offset = 6 + ($iconDirEntries.Count * 16)
        foreach ($entry in $iconDirEntries) {
            $entry.ImageOffset = $offset
            $binaryWriter.Write($entry.Width)
            $binaryWriter.Write($entry.Height)
            $binaryWriter.Write($entry.ColorCount)
            $binaryWriter.Write($entry.Reserved)
            $binaryWriter.Write($entry.Planes)
            $binaryWriter.Write($entry.BitCount)
            $binaryWriter.Write($entry.BytesInRes)
            $binaryWriter.Write($entry.ImageOffset)
            $offset += $entry.BytesInRes
        }

        # 写入图像数据
        foreach ($data in $imageDataStreams) {
            $binaryWriter.Write($data)
        }

        # 保存到磁盘
        $finalBytes = $memoryStream.ToArray()
        [System.IO.File]::WriteAllBytes($absoluteOutput, $finalBytes)

        Write-Host "✅ 图标已保存至: $absoluteOutput"
    }
    finally {
        if ($null -ne $originalImage) { $originalImage.Dispose() }
        if ($null -ne $binaryWriter) { $binaryWriter.Dispose() }
        if ($null -ne $memoryStream) { $memoryStream.Dispose() }
    }
}

# ========== 自动执行逻辑（用于 .exe 封装）==========
if ($MyInvocation.InvocationName -ne '.') {
    # 构建参数哈希表
    $params = @{}
    $i = 0
    while ($i -lt $args.Count) {
        $arg = $args[$i]
        if ($arg -match '^-(\w+)$') {
            $paramName = $matches[1]
            if ($i + 1 -lt $args.Count -and $args[$i+1] -notmatch '^-.') {
                $params[$paramName] = $args[$i+1]
                $i += 2
            } else {
                $params[$paramName] = $true
                $i++
            }
        } else {
            Write-Host "❌ 无效参数: $arg" -ForegroundColor Red
            exit 1
        }
    }

    try {
        ConvertTo-Ico @params
    } catch {
        Write-Host "❌ 错误: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# 使用 ps2exe 打包为 exe
# Invoke-ps2exe -InputFile .\ConvertTo-Ico.ps1 -OutputFile ConvertTo-Ico.exe -IconFile .\icon.ico