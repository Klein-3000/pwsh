function global:ip {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [string]$Action,

        [Parameter(ValueFromRemainingArguments)]
        $ExtraArgs
    )
    # -------------------------------
    # 内联函数：Shorten-Text
    # -------------------------------
    function Shorten-Text {
        param(
            [string]$Text,
            [int]$MaxLength
        )
        if ($Text.Length -le $MaxLength) {
            return $Text.PadRight($MaxLength)
        }
        else {
            $truncated = $Text.Substring(0, $MaxLength - 3)
            return ($truncated + "...").PadRight($MaxLength)
        }
    }

    $Action = $Action.ToLower()

    # -----------------------------------------------
    # ip link 或 ip l
    # -----------------------------------------------
    if ($Action -eq "link" -or $Action -eq "l") {
        $brief = $false
        if ($ExtraArgs.Count -gt 0) {
            $extra = $ExtraArgs[0].ToLower()
            if ($extra -eq "-b" -or $extra -eq "--brief") {
                $brief = $true
            }
            else {
                Write-Host "Unknown option: $extra" -ForegroundColor Red
                Write-Host "Usage: ip link [-b|--brief]" -ForegroundColor White
                return
            }
        }

        $adapters = Get-NetAdapter | Where-Object { $_.InterfaceIndex -ne $null } | Sort-Object InterfaceIndex
        if (-not $adapters) {
            Write-Host "No network adapters found." -ForegroundColor Yellow
            return
        }

        if ($brief) {
            $header = "{0,-30} {1,-17} {2,-12}" -f "Interface", "MAC Address", "State"
            Write-Host $header -ForegroundColor Cyan
            Write-Host ("-" * 61) -ForegroundColor Gray

            foreach ($adapter in $adapters) {
                $name = Shorten-Text -Text $adapter.InterfaceAlias -MaxLength 30
                $mac = if ($adapter.LinkLayerAddress) { $adapter.LinkLayerAddress } else { "N/A".PadRight(17) }
                $mac = $mac.Substring(0, [Math]::Min(17, $mac.Length)).PadRight(17)
                $state = $adapter.Status
                if ($state -eq "Up") { $color = "Green" }
                elseif ($state -eq "Disconnected") { $color = "Red" }
                else { $color = "Yellow" }
                Write-Host "$name $mac $state" -ForegroundColor $color
            }
        }
        else {
            $header = "{0,-20} {1,-12} {2,-17} {3,-9} {4,-25}" -f "Interface", "State", "MAC Address", "Speed", "Description"
            Write-Host $header -ForegroundColor Cyan
            Write-Host ("-" * 83) -ForegroundColor Gray

            foreach ($adapter in $adapters) {
                $name = Shorten-Text -Text $adapter.InterfaceAlias -MaxLength 20
                $desc = Shorten-Text -Text $adapter.InterfaceDescription -MaxLength 25
                $mac = if ($adapter.LinkLayerAddress) { $adapter.LinkLayerAddress } else { "N/A" }
                $mac = $mac.Substring(0, [Math]::Min(17, $mac.Length)).PadRight(17)
                $state = $adapter.Status.Substring(0, [Math]::Min(12, $adapter.Status.Length)).PadRight(12)
                $speed = if ($adapter.Speed) { [math]::Round($adapter.Speed / 1MB) } else { "N/A" }
                $speedStr = "$speed Mbps".PadRight(9)
                if ($state -like "Up*") { $color = "Green" }
                elseif ($state -like "Disconnected*") { $color = "Red" }
                else { $color = "Yellow" }

                Write-Host "$name $state $mac $speedStr $desc" -ForegroundColor $color
            }
        }
    }

    # -----------------------------------------------
    # ip addr 或 ip a
    # -----------------------------------------------
    elseif ($Action -eq "addr" -or $Action -eq "a") {
        $brief = $false
        if ($ExtraArgs.Count -gt 0) {
            $extra = $ExtraArgs[0].ToLower()
            if ($extra -eq "-b" -or $extra -eq "--brief") {
                $brief = $true
            }
            else {
                Write-Host "Unknown option: $extra" -ForegroundColor Red
                Write-Host "Usage: ip a [-b|--brief]" -ForegroundColor White
                return
            }
        }

        $configs = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -ne "Loopback Pseudo-Interface 1" }
        if (-not $configs) {
            Write-Host "No IPv4 addresses assigned." -ForegroundColor Yellow
            return
        }

        $gateways = @{}
        $routes = Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -eq "0.0.0.0/0" }
        foreach ($route in $routes) {
            $gateways[$route.InterfaceIndex] = $route.NextHop
        }

        if ($brief) {
            $header = "{0,-30} {1,-18} {2,-12}" -f "Interface", "IP/Mask", "State"
            Write-Host $header -ForegroundColor Cyan
            Write-Host ("-" * 62) -ForegroundColor Gray

            foreach ($config in $configs) {
                $adapter = Get-NetAdapter -InterfaceIndex $config.InterfaceIndex -ErrorAction SilentlyContinue
                $state = if ($adapter) { $adapter.Status } else { "Unknown" }
                if ($state -eq "Up") { $color = "Green" }
                elseif ($state -eq "Disconnected") { $color = "Red" }
                else { $color = "Yellow" }
                $ipMask = "$($config.IPAddress)/$($config.PrefixLength)"
                $name = Shorten-Text -Text $config.InterfaceAlias -MaxLength 30
                $ipMask = $ipMask.Substring(0, [Math]::Min(18, $ipMask.Length)).PadRight(18)
                Write-Host "$name $ipMask $state" -ForegroundColor $color
            }
        }
        else {
            $header = "{0,-20} {1,-15} {2,-8} {3,-15} {4,-12} {5,-17}" -f "Interface", "IP Address", "Mask", "Gateway", "State", "MAC Address"
            Write-Host $header -ForegroundColor Cyan
            Write-Host ("-" * 87) -ForegroundColor Gray

            foreach ($config in $configs) {
                $adapter = Get-NetAdapter -InterfaceIndex $config.InterfaceIndex -ErrorAction SilentlyContinue
                $state = if ($adapter) { $adapter.Status } else { "Unknown" }
                $mac = if ($adapter -and $adapter.LinkLayerAddress) { $adapter.LinkLayerAddress } else { "N/A" }
                $gateway = if ($gateways[$config.InterfaceIndex]) { $gateways[$config.InterfaceIndex] } else { "N/A" }
                if ($state -eq "Up") { $color = "Green" }
                elseif ($state -eq "Disconnected") { $color = "Red" }
                else { $color = "Yellow" }

                $name = Shorten-Text -Text $config.InterfaceAlias -MaxLength 20
                $ip = $config.IPAddress.PadRight(15)
                $mask = "/$($config.PrefixLength)".PadRight(8)
                $gw = $gateway.PadRight(15)
                $st = $state.Substring(0, [Math]::Min(12, $state.Length)).PadRight(12)
                $mc = $mac.Substring(0, [Math]::Min(17, $mac.Length)).PadRight(17)

                Write-Host "$name $ip $mask $gw $st $mc" -ForegroundColor $color
            }
        }
    }
    # -----------------------------------------------
    # 帮助
    # -----------------------------------------------
    elseif ($Action -eq "help" -or $Action -eq "h" -or [string]::IsNullOrWhiteSpace($Action)) {
        Write-Host "Usage:" -ForegroundColor Cyan
        Write-Host "  ip addr    or  ip a                - Show IP addresses (detailed)" -ForegroundColor White
        Write-Host "  ip addr -b or  ip a -b             - Show IP addresses (brief)" -ForegroundColor White
        Write-Host "  ip link    or  ip l                - Show network adapters (detailed)" -ForegroundColor White
        Write-Host "  ip link -b or  ip l -b             - Show network adapters (brief)" -ForegroundColor White
        Write-Host "  ip help    or  ip h                - Show this help" -ForegroundColor White
    }
    else {
        Write-Host "Unknown action: $Action" -ForegroundColor Red
        Write-Host "Use 'ip help' for available commands." -ForegroundColor White
    }
}

