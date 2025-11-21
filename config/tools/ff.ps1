function global:ff {
    [CmdletBinding()]
    param(
        # 基础参数
        [Parameter(Position = 0)]
        [string]$name,

        [switch]$list,

        [switch]$help,

        [switch]$listSigils,
        [switch]$listSigilsJsonc,

        [string]$sigil,
        [string]$sigilJsonc,

        [switch]$randSigils,

        # 显示配置
        [int]$width = 30,
        [int]$paddingTop = 1,
        [int]$paddingLeft = 5
    )

    $configRoot = "$env:USERPROFILE\.config\fastfetch"
    $logoDir = "$configRoot\logos"
    $sigilDir = "$logoDir\sigils"
    $sigilConfigDir = "$configRoot\SigilModule"
    $defaultConfig = "$sigilConfigDir\border.jsonc"
    $imageExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.tiff', '.webp', '.webp')

    # 检查 fastfetch 是否可用
    if (-not (Get-Command "fastfetch" -ErrorAction SilentlyContinue)) {
        Write-Error "❌ Fastfetch 未安装或不可用，请先安装 fastfetch。"
        return
    }

    # 显示帮助
    if ($help) {
        Write-Output @"
使用说明: ff [选项]

选项:
  ff                                  - 随机显示 ~/.config/fastfetch/logos/ 中的 logo 图片
  ff -name <文件名>                   - 指定 logos 目录中的图片（如: iuno.png）
  ff -list                            - 列出所有可用的 logo 图片
  ff -sigil <sigil_name>              - 使用 sigils 目录中的徽记，配合默认配置文件
  ff -sigil <name> -sigilJsonc <file> - 指定徽记和配置文件（jsonc 在 SigilModule 中）
  ff -randSigils                      - 随机选择 sigil 图片 和 随机配置文件
  ff -listSigils                      - 列出 sigils/ 目录中的所有徽记图片
  ff -listSigilsJsonc                 - 列出 SigilModule/ 目录中的所有 .jsonc 配置文件
"@
        return
    }

    # -list: 列出 logos 目录中所有支持的图片
    if ($list) {
        Write-Host "`n📄 可用的 logo 图片:" -ForegroundColor Cyan
        if (Test-Path $logoDir) {
            $images = Get-ChildItem -Path $logoDir | Where-Object {
                $imageExtensions -contains $_.Extension.ToLower()
            }
            if ($images) {
                $images | ForEach-Object { Write-Host "  $($_.Name)" }
            } else {
                Write-Warning "在 $logoDir 中未找到支持的图片文件。"
            }
        } else {
            Write-Error "Logo 目录不存在: $logoDir"
        }
        return
    }

    # -list-sigils: 列出 sigils 目录中的所有图片
    if ($listSigils) {
        Write-Host "`n🛡️  可用的 sigil 徽记:" -ForegroundColor Cyan
        if (Test-Path $sigilDir) {
            $sigilImages = Get-ChildItem -Path $sigilDir | Where-Object {
                $imageExtensions -contains $_.Extension.ToLower()
            }
            if ($sigilImages) {
                $sigilImages | ForEach-Object { Write-Host "  $($_.Name)" }
            } else {
                Write-Warning "在 $sigilDir 中未找到支持的图片文件。"
            }
        } else {
            Write-Error "Sigil 图片目录不存在: $sigilDir"
        }
        return
    }

    # -list-sigils-jsonc: 列出 SigilModule 中的 .jsonc 配置文件
    if ($listSigilsJsonc) {
        Write-Host "`n⚙️  可用的 sigil 配置文件:" -ForegroundColor Cyan
        if (Test-Path $sigilConfigDir) {
            $configs = Get-ChildItem -Path $sigilConfigDir -Filter "*.jsonc"
            if ($configs) {
                $configs | ForEach-Object { Write-Host "  $($_.Name)" }
            } else {
                Write-Warning "在 $sigilConfigDir 中未找到 .jsonc 配置文件。"
            }
        } else {
            Write-Error "SigilModule 配置目录不存在: $sigilConfigDir"
        }
        return
    }

    # 验证目录存在
    if (-not (Test-Path $logoDir)) {
        Write-Error "Logo 目录不存在: $logoDir"
        return
    }

    # ========== 处理 -rand-sigils ==========
    if ($randSigils) {
        Write-Verbose "🎲 随机选择 sigil 和配置文件..."

        # 随机选择 sigil 图片
        $sigilImages = Get-ChildItem -Path $sigilDir | Where-Object {
            $imageExtensions -contains $_.Extension.ToLower()
        }
        if (-not $sigilImages) {
            Write-Error "在 $sigilDir 中未找到可用的 sigil 图片。"
            return
        }
        $randomSigil = Get-Random -InputObject $sigilImages
        $imagePath = $randomSigil.FullName

        # 随机选择 jsonc 配置
        $configFiles = Get-ChildItem -Path $sigilConfigDir -Filter "*.jsonc"
        if (-not $configFiles) {
            Write-Error "在 $sigilConfigDir 中未找到 .jsonc 配置文件。"
            return
        }
        $randomConfig = Get-Random -InputObject $configFiles
        $configPath = $randomConfig.FullName

        Write-Host "🎨 使用随机徽记: $($randomSigil.Name)" -ForegroundColor Green
        Write-Host "🔧 使用随机配置: $($randomConfig.Name)" -ForegroundColor Green

        fastfetch --config "$configPath" --iterm "$imagePath" 
        return
    }

    # ========== 处理 -sigil ==========
    if ($sigil) {
        $sigilPath = Join-Path $sigilDir $sigil

        # 如果用户没加扩展名，尝试自动补全
        if (-not [System.IO.Path]::GetExtension($sigil)) {
            foreach ($ext in $imageExtensions) {
                $tryPath = Join-Path $sigilDir "$sigil$ext"
                if (Test-Path $tryPath) {
                    $sigilPath = $tryPath
                    break
                }
            }
        }

        if (-not (Test-Path $sigilPath)) {
            Write-Error "未找到 sigil 图片: $sigil"
            Write-Host "可用 sigil 图片:" -ForegroundColor Yellow
            Get-ChildItem -Path $sigilDir | Where-Object {
                $imageExtensions -contains $_.Extension.ToLower()
            } | ForEach-Object { Write-Host "  $($_.Name)" }
            return
        }

        # 默认配置
        $configToUse = $defaultConfig

        # 如果指定了 -sigil-jsonc，则使用指定的配置文件
        if ($sigilJsonc) {
            $explicitConfigPath = Join-Path $sigilConfigDir $sigilJsonc
            if ($sigilJsonc -notlike "*.jsonc") {
                $explicitConfigPath += ".jsonc"
            }

            if (-not (Test-Path $explicitConfigPath)) {
                Write-Error "未找到配置文件: $explicitConfigPath"
                Write-Host "可用配置文件:" -ForegroundColor Yellow
                Get-ChildItem -Path $sigilConfigDir -Filter "*.jsonc" | ForEach-Object { Write-Host "  $($_.Name)" }
                return
            }
            $configToUse = $explicitConfigPath
        }

        Write-Host "🛡️  使用徽记: $sigil" -ForegroundColor Green
        Write-Host "⚙️  使用配置: $(Split-Path $configToUse -Leaf)" -ForegroundColor Green

        fastfetch --config "$configToUse" --iterm "$sigilPath" 
        return
    }

    # ========== 处理普通 -name 或随机 logo ==========
    $images = Get-ChildItem -Path $logoDir | Where-Object {
        $imageExtensions -contains $_.Extension.ToLower()
    }

    if ($images.Count -eq 0) {
        Write-Error "在 $logoDir 中未找到支持的图片文件。"
        return
    }

    if ($name) {
        $targetImage = $images | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $targetImage) {
            Write-Error "未找到指定的图片: $name"
            Write-Host "可用图片:" -ForegroundColor Yellow
            $images | ForEach-Object { Write-Host "  $($_.Name)" }
            return
        }
        $imagePath = $targetImage.FullName
        Write-Verbose "使用指定图片: $imagePath"
    } else {
        $randomImage = Get-Random -InputObject $images
        $imagePath = $randomImage.FullName
        Write-Verbose "随机使用图片: $imagePath"
    }

    # 默认模式：仅使用图片，加载 config.jsonc（fastfetch 默认行为）
    fastfetch --iterm "$imagePath" --logo-width $width --logo-padding-top $paddingTop --logo-padding-left $paddingLeft
}
