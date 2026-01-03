$env:bcm_home = "E:\BongoCatMver"

function global:bcm {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [ValidateSet('list', 'up', 'down', 'switch', 'show', 'run', 'help', 'status', 'doctor', 'version')]
        [string]$Command,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$RemainingArgs
    )

    # 检查环境变量
    if (-not $env:bcm_home) {
        Write-Error "Environment variable `$env:bcm_home is not set. Please set it to the root of BongoCatMver (e.g., 'E:\BongoCatMver')."
        return
    }

    $root = Resolve-Path $env:bcm_home -ErrorAction Stop
    $appDir = Join-Path $root "BongoCatMver"
    $sourcesDir = Join-Path $root "Sources"

    if (-not (Test-Path $appDir -PathType Container)) {
        Write-Error "Application directory not found: $appDir"
        return
    }
    if (-not (Test-Path $sourcesDir -PathType Container)) {
        Write-Error "Sources directory not found: $sourcesDir"
        return
    }

    # 辅助函数：从链接反推当前皮肤名
    function Get-SkinFromLinks {
        $configLink = Join-Path $appDir "config.json"
        if (Test-Path $configLink -PathType Leaf) {
            $item = Get-Item $configLink -ErrorAction SilentlyContinue
            if ($item -and $item.LinkType -eq "SymbolicLink") {
                $target = $item.Target
                if ($target -and (Test-Path $target)) {
                    $skinDir = Split-Path (Split-Path $target -Parent) -Leaf
                    if (Test-Path (Join-Path $sourcesDir $skinDir)) {
                        return $skinDir
                    }
                }
            }
        }
        return $null
    }

    # 辅助函数：获取当前激活的皮肤名（优先读记录，其次尝试恢复）
    function Get-CurrentSkin {
        $recordFile = Join-Path $appDir ".bcm-skin"
        if (Test-Path $recordFile) {
            return Get-Content $recordFile -Raw
        } else {
            return Get-SkinFromLinks
        }
    }

    # 辅助函数：清理当前激活状态（供 down 使用）
    function Remove-CurrentSkin {
        $imgTarget = Join-Path $appDir "img"
        $configTarget = Join-Path $appDir "config.json"
        $recordFile = Join-Path $appDir ".bcm-skin"

        # 删除 img（Junction 或目录）
        if (Test-Path $imgTarget) {
            $item = Get-Item $imgTarget
            if ($item.LinkType -eq "Junction" -or $item.LinkType -eq "SymbolicLink") {
                Remove-Item $imgTarget -Force
            } else {
                Remove-Item $imgTarget -Recurse -Force
            }
        }

        # 删除 config.json（SymbolicLink 或文件）
        if (Test-Path $configTarget) {
            $item = Get-Item $configTarget -ErrorAction SilentlyContinue
            if ($item -and $item.LinkType -eq "SymbolicLink") {
                Remove-Item $configTarget -Force
            } else {
                Remove-Item $configTarget -Force
            }
        }

        # 删除记录文件
        if (Test-Path $recordFile) {
            Remove-Item $recordFile -Force
        }
    }

    switch ($Command) {
'help' {
    Write-Host @"
BongoCat Mver Skin Manager (bcm) - v1.0.0

USAGE:
  bcm <command> [args]

COMMANDS:
  list                List all available skins in Sources/
  up <skin>           Activate a skin by creating symlinks
  down                Deactivate current skin (remove links & record)
  switch <skin>       Switch to another skin (down + up)
  show                Show currently active skin name
  run                 Launch BongoCat Mver (requires active skin)
  status              Show detailed activation status and health check
  doctor              Check environment setup and diagnose issues
  help                Show this help message
  version             Show version info

EXAMPLES:
  bcm list
  bcm up yuexia-WeddingDress
  bcm switch yeshunguang
  bcm status
  bcm run
"@ -ForegroundColor Cyan
}

        'version' {
            Write-Host "bcm v1.0.0"
        }

        'list' {
            Get-ChildItem $sourcesDir -Directory | ForEach-Object {
                $skinName = $_.Name
                $hasImg = Test-Path (Join-Path $_.FullName "img") -PathType Container
                $hasConfig = Test-Path (Join-Path $_.FullName "config.json") -PathType Leaf
                $status = if ($hasImg -and $hasConfig) { "✅" } else { "⚠️ (incomplete)" }
                Write-Host "$status $skinName"
            }
        }

        'up' {
            if ($RemainingArgs.Count -ne 1) {
                Write-Error "Usage: bcm up <skin_name>"
                return
            }
            $skinName = $RemainingArgs[0]
            $skinPath = Join-Path $sourcesDir $skinName

            if (-not (Test-Path $skinPath -PathType Container)) {
                Write-Error "Skin '$skinName' not found in $sourcesDir"
                return
            }

            $imgSrc = Join-Path $skinPath "img"
            $configSrc = Join-Path $skinPath "config.json"

            if (-not (Test-Path $imgSrc -PathType Container)) {
                Write-Error "Missing 'img' directory in skin: $skinPath"
                return
            }
            if (-not (Test-Path $configSrc -PathType Leaf)) {
                Write-Error "Missing 'config.json' in skin: $skinPath"
                return
            }

            $imgTarget = Join-Path $appDir "img"
            $configTarget = Join-Path $appDir "config.json"

            # 清理可能的旧状态
            if (Test-Path $imgTarget) { Remove-Item $imgTarget -Recurse -Force }
            if (Test-Path $configTarget) { Remove-Item $configTarget -Force }

            try {
                cmd /c mklink /J "$imgTarget" "$imgSrc" 2>$null | Out-Null
                New-Item -ItemType SymbolicLink -Path $configTarget -Target $configSrc -ErrorAction Stop | Out-Null

                $skinRecordFile = Join-Path $appDir ".bcm-skin"
                Set-Content -Path $skinRecordFile -Value $skinName -NoNewline

                Write-Host "✅ Skin '$skinName' activated!" -ForegroundColor Green
            } catch {
                Write-Error "Failed to create links. Run as Admin or enable Developer Mode.`nError: $_"
                return
            }
        }

        'down' {
            $current = Get-CurrentSkin
            Remove-CurrentSkin
            if ($current) {
                Write-Host "🗑️  Skin '$current' deactivated." -ForegroundColor Yellow
            } else {
                Write-Host "ℹ️  No active skin to deactivate." -ForegroundColor Gray
            }
        }

        'switch' {
            if ($RemainingArgs.Count -ne 1) {
                Write-Error "Usage: bcm switch <skin_name>"
                return
            }
            $newSkin = $RemainingArgs[0]

            # 先停用当前（静默）
            Remove-CurrentSkin

            # 再激活新皮肤（复用 up 逻辑）
            $skinPath = Join-Path $sourcesDir $newSkin
            if (-not (Test-Path $skinPath -PathType Container)) {
                Write-Error "Skin '$newSkin' not found in $sourcesDir"
                return
            }
            $imgSrc = Join-Path $skinPath "img"
            $configSrc = Join-Path $skinPath "config.json"
            if (-not (Test-Path $imgSrc -PathType Container) -or -not (Test-Path $configSrc -PathType Leaf)) {
                Write-Error "Skin '$newSkin' is incomplete."
                return
            }

            $imgTarget = Join-Path $appDir "img"
            $configTarget = Join-Path $appDir "config.json"
            if (Test-Path $imgTarget) { Remove-Item $imgTarget -Recurse -Force }
            if (Test-Path $configTarget) { Remove-Item $configTarget -Force }

            try {
                cmd /c mklink /J "$imgTarget" "$imgSrc" 2>$null | Out-Null
                New-Item -ItemType SymbolicLink -Path $configTarget -Target $configSrc -ErrorAction Stop | Out-Null
                Set-Content -Path (Join-Path $appDir ".bcm-skin") -Value $newSkin -NoNewline
                Write-Host "🔄 Switched to skin: $newSkin" -ForegroundColor Magenta
            } catch {
                Write-Error "Switch failed: $_"
                return
            }
        }

        'show' {
            $current = Get-CurrentSkin
            if ($current) {
                Write-Host "Current skin: $current" -ForegroundColor Cyan
            } else {
                $recovered = Get-SkinFromLinks
                if ($recovered) {
                    Write-Host "Current skin (recovered): $recovered" -ForegroundColor Yellow
                    Set-Content -Path (Join-Path $appDir ".bcm-skin") -Value $recovered -NoNewline
                } else {
                    Write-Host "No active skin." -ForegroundColor Red
                }
            }
        }

    'run' {
        $launchScript = Join-Path $appDir "launch.ps1"
        if (-not (Test-Path $launchScript -PathType Leaf)) {
            Write-Host "❌ Launch script not found: launch.ps1" -ForegroundColor Red
            return
        }

        $imgPath    = Join-Path $appDir "img"
        $configPath = Join-Path $appDir "config.json"

        # 检查皮肤是否已激活（通过文件存在性判断）
        if (-not (Test-Path $imgPath -PathType Container) -or -not (Test-Path $configPath -PathType Leaf)) {
            Write-Host "⚠️  No skin configured. Please run 'bcm up <skin>' first." -ForegroundColor Yellow
            return
        }

        # 可选：显示当前皮肤（如果能获取到）
        $current = Get-CurrentSkin
        if ($current) {
            Write-Host "🚀 Launching with skin: $current" -ForegroundColor Green
        } else {
            Write-Host "🚀 Launching..." -ForegroundColor Green
        }

        & $launchScript
    }
    'status' {
        $recordFile   = Join-Path $appDir ".bcm-skin"
        $imgPath      = Join-Path $appDir "img"
        $configPath   = Join-Path $appDir "config.json"

        # 获取记录中的皮肤名
        $recordedSkin = $null
        if (Test-Path $recordFile) {
            $recordedSkin = Get-Content $recordFile -Raw
        }

        # 检查 img 状态
        $imgExists = Test-Path $imgPath -PathType Container
        $imgIsLink = $false
        if ($imgExists) {
            $imgItem = Get-Item $imgPath -ErrorAction SilentlyContinue
            if ($imgItem -and ($imgItem.LinkType -eq "Junction" -or $imgItem.LinkType -eq "SymbolicLink")) {
                $imgIsLink = $true
            }
        }

        # 检查 config.json 状态
        $configExists = Test-Path $configPath -PathType Leaf
        $configIsLink = $false
        if ($configExists) {
            $configItem = Get-Item $configPath -ErrorAction SilentlyContinue
            if ($configItem -and $configItem.LinkType -eq "SymbolicLink") {
                $configIsLink = $true
            }
        }

        # 尝试从链接反推皮肤名（用于验证）
        $recoveredSkin = Get-SkinFromLinks

        # 判断实际激活的皮肤（优先用记录，其次恢复）
        $activeSkin = $recordedSkin
        if (-not $activeSkin) { $activeSkin = $recoveredSkin }

        # 验证皮肤是否在 Sources 中存在
        $skinValid = $false
        if ($activeSkin) {
            $skinValid = Test-Path (Join-Path $sourcesDir $activeSkin) -PathType Container
        }

        # === 输出状态 ===
        if (-not $imgExists -and -not $configExists) {
            Write-Host "⚠️  No active skin." -ForegroundColor Yellow
            Write-Host "💡 Run 'bcm up <skin>' to activate one." -ForegroundColor DarkGray
            return
        }

        # 显示皮肤名
        if ($activeSkin) {
            Write-Host "Current skin: $activeSkin" -ForegroundColor Cyan
            if (-not $skinValid) {
                Write-Host "❌ Skin not found in Sources/ (orphaned)" -ForegroundColor Red
            }
        } else {
            Write-Host "Current skin: unknown" -ForegroundColor Gray
        }

        # img 状态
        if ($imgExists) {
            if ($imgIsLink) {
                Write-Host "✅ img → valid junction/symlink" -ForegroundColor Green
            } else {
                Write-Host "⚠️  img → exists but is a regular folder (not link)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "❌ img → missing" -ForegroundColor Red
        }

        # config.json 状态
        if ($configExists) {
            if ($configIsLink) {
                Write-Host "✅ config.json → valid symlink" -ForegroundColor Green
            } else {
                Write-Host "⚠️  config.json → exists but is a regular file (not link)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "❌ config.json → missing" -ForegroundColor Red
        }

        # 整体健康判断
        $linksOk = $imgIsLink -and $configIsLink
        $filesOk = $imgExists -and $configExists
        if ($linksOk -and $skinValid) {
            Write-Host "✨ Skin is fully healthy." -ForegroundColor Green
        } elseif ($filesOk) {
            Write-Host "🔧 Skin files exist, but links may be broken. Consider reactivating." -ForegroundColor DarkYellow
            Write-Host "💡 Run 'bcm down' then 'bcm up $activeSkin' to repair." -ForegroundColor DarkGray
        } else {
            Write-Host "💥 Skin is broken. Activation required." -ForegroundColor Red
            Write-Host "💡 Run 'bcm up <skin>' to fix." -ForegroundColor DarkGray
        }
    }
    'doctor' {
        Write-Host "🔍 BongoCat Mver Environment Check" -ForegroundColor Cyan

        # 1. 检查 $env:bcm_home
        if (-not $env:bcm_home) {
            Write-Host "❌ `$env:bcm_home is not set" -ForegroundColor Red
            Write-Host "💡 Set it to your BongoCatMver root (e.g., 'E:\BongoCatMver')" -ForegroundColor DarkGray
            return
        }
        Write-Host "✅ `$env:bcm_home = $env:bcm_home"

        # 2. 检查根目录结构
        $root = Resolve-Path $env:bcm_home -ErrorAction SilentlyContinue
        if (-not $root -or -not (Test-Path $root)) {
            Write-Host "❌ Root path invalid: $env:bcm_home" -ForegroundColor Red
            return
        }

        # 3. 检查 BongoCatMver/ 目录
        $appDir = Join-Path $root "BongoCatMver"
        if (-not (Test-Path $appDir -PathType Container)) {
            Write-Host "❌ Missing application directory: $appDir" -ForegroundColor Red
            return
        }
        Write-Host "✅ Application directory: $appDir"

        # 4. 检查 Sources/ 目录
        $sourcesDir = Join-Path $root "Sources"
        if (-not (Test-Path $sourcesDir -PathType Container)) {
            Write-Host "❌ Missing Sources directory: $sourcesDir" -ForegroundColor Red
            Write-Host "💡 Create it and place skins inside." -ForegroundColor DarkGray
            return
        }
        Write-Host "✅ Sources directory: $sourcesDir"

        # 5. 检查 launch.ps1
        $launchScript = Join-Path $appDir "launch.ps1"
        if (-not (Test-Path $launchScript -PathType Leaf)) {
            Write-Host "⚠️  launch.ps1 not found (required to run BongoCat)" -ForegroundColor Yellow
        } else {
            Write-Host "✅ Launch script: present"
        }

        # 6. 检查至少一个有效皮肤
        $validSkins = Get-ChildItem $sourcesDir -Directory | Where-Object {
            (Test-Path (Join-Path $_.FullName "img") -PathType Container) -and
            (Test-Path (Join-Path $_.FullName "config.json") -PathType Leaf)
        }
        if ($validSkins.Count -eq 0) {
            Write-Host "⚠️  No valid skins found in Sources/" -ForegroundColor Yellow
            Write-Host "💡 A valid skin must contain 'img/' folder and 'config.json'" -ForegroundColor DarkGray
        } else {
            Write-Host "✅ Found $($validSkins.Count) valid skin(s) in Sources/"
        }

        # 7. 检查当前皮肤状态（复用 status 逻辑简化版）
        $current = Get-CurrentSkin
        if ($current) {
            Write-Host "ℹ️  Current skin: $current"
        }

        Write-Host "`n✨ Environment check complete!" -ForegroundColor Green
    }

    }
}