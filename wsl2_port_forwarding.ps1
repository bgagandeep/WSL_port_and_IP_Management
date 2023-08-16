# ---- Helper Functions ----

# Fetches the WSL2 IP Address
function Get-WSLIPAddress {
    return (wsl hostname -I | Out-String).Trim().Split()[0]
}

# Sync existing port forwarding rules to the current WSL2 IP
function SyncIPAddresses {
    param (
        [Parameter(Mandatory=$true)]
        [string]$wslAddress,
        [Parameter(Mandatory=$true)]
        [string]$listenAddress,
        [Parameter(Mandatory=$true)]
        [string]$fireWallDisplayName
    )

    $existingRules = netsh interface portproxy show all | Where-Object { $_ -like "*$fireWallDisplayName*" }
    $changed = $false

    foreach ($rule in $existingRules) {
        $ruleSplit = $rule -split ":", 4
        if ($ruleSplit.Length -eq 4) {
            $currentIP = $ruleSplit[2].Trim()
            if ($currentIP -ne $wslAddress) {
                $localPort = $ruleSplit[1].Trim()
                # Delete the outdated rule
                netsh interface portproxy delete v4tov4 listenport=$localPort listenaddress=$listenAddress
                # Add the rule with the updated IP
                netsh interface portproxy add v4tov4 listenport=$localPort listenaddress=$listenAddress connectport=$localPort connectaddress=$wslAddress
                Write-Host "Updated port $localPort to new WSL IP address" -ForegroundColor Yellow
                $changed = $true
            }
        }
    }

    if (-not $changed) {
        Write-Host "All ports are already synced with the current WSL IP address" -ForegroundColor Green
    }
}

# Forwards or removes a specific port
function ForwardPort {
    param (
        [Parameter(Mandatory=$true)]
        [string]$mode,
        [Parameter(Mandatory=$true)]
        [int]$port,
        [Parameter(Mandatory=$true)]
        [string]$listenAddress,
        [Parameter(Mandatory=$true)]
        [string]$wslAddress
    )

    if ($mode -eq 'add') {
        netsh interface portproxy add v4tov4 listenport=$port listenaddress=$listenAddress connectport=$port connectaddress=$wslAddress
    } elseif ($mode -eq 'delete') {
        netsh interface portproxy delete v4tov4 listenport=$port listenaddress=$listenAddress
    }
}

# Manages firewall rules for a specific port
function HandleFirewall {
    param (
        [Parameter(Mandatory=$true)]
        [string]$mode,
        [Parameter(Mandatory=$true)]
        [int]$port,
        [Parameter(Mandatory=$true)]
        [string]$fireWallDisplayName
    )

    if ($mode -eq 'add') {
        New-NetFireWallRule -DisplayName "$fireWallDisplayName $port Outbound" -Direction Outbound -LocalPort $port -Action Allow -Protocol TCP
        New-NetFireWallRule -DisplayName "$fireWallDisplayName $port Inbound" -Direction Inbound -LocalPort $port -Action Allow -Protocol TCP
    } elseif ($mode -eq 'delete') {
        Remove-NetFireWallRule -DisplayName "$fireWallDisplayName $port Outbound"
        Remove-NetFireWallRule -DisplayName "$fireWallDisplayName $port Inbound"
    }
}

# Fetches currently forwarded ports
function GetForwardedPorts {
    return netsh interface portproxy show v4tov4 | Where-Object { $_ -match "^\s*\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\s+(\d+)" } | ForEach-Object { $matches[1] }
}

# Handles a range of ports
function HandlePortRange {
    param (
        [Parameter(Mandatory=$true)]
        [string]$mode,
        [Parameter(Mandatory=$true)]
        [int]$startPort,
        [Parameter(Mandatory=$true)]
        [int]$endPort,
        [Parameter(Mandatory=$true)]
        [string]$listenAddress,
        [Parameter(Mandatory=$true)]
        [string]$wslAddress,
        [Parameter(Mandatory=$true)]
        [string]$fireWallDisplayName
    )

    $totalPorts = $endPort - $startPort + 1
    $count = 0

    foreach ($port in $startPort..$endPort) {
        $count++
        $percentComplete = ($count / $totalPorts) * 100
        Write-Progress -PercentComplete $percentComplete -Status "Processing port $port of $totalPorts" -Activity "$mode Ports" -Id 1

        ForwardPort -mode $mode -port $port -listenAddress $listenAddress -wslAddress $wslAddress
        HandleFirewall -mode $mode -port $port -fireWallDisplayName $fireWallDisplayName
    }

    Write-Progress -PercentComplete 100 -Status "Done" -Activity "$mode Ports Completed" -Completed -Id 1
}

function ProcessAddOrDelete {
    param (
        [Parameter(Mandatory=$true)]
        [string]$mode,
        [Parameter(Mandatory=$true)]
        [string]$listenAddress,
        [Parameter(Mandatory=$true)]
        [string]$wslAddress,
        [Parameter(Mandatory=$true)]
        [string]$fireWallDisplayName
    )

    $portInput = Read-Host "Enter a port number, range (e.g., 8000-9000) or 'all'"

    if ($portInput -eq 'all' -and $mode -eq 'delete') {
        $forwardedPorts = GetForwardedPorts
        foreach ($port in $forwardedPorts) {
            ForwardPort -mode 'delete' -port $port -listenAddress $listenAddress -wslAddress $wslAddress
            HandleFirewall -mode 'delete' -port $port -fireWallDisplayName $fireWallDisplayName
        }
    } elseif ($portInput -match "^(\d+)-(\d+)$") {
        $startPort = [int]$matches[1]
        $endPort = [int]$matches[2]
        if ($startPort -le $endPort -and $startPort -gt 0 -and $endPort -le 65535) {
            HandlePortRange -mode $mode -startPort $startPort -endPort $endPort -listenAddress $listenAddress -wslAddress $wslAddress -fireWallDisplayName $fireWallDisplayName
        } else {
            Write-Host "Invalid port range. Please ensure start port is less than or equal to end port and both are between 1 and 65535." -ForegroundColor Red
        }
    } elseif ($portInput -match "^\d+$" -and [int]$portInput -gt 0 -and [int]$portInput -le 65535) {
        ForwardPort -mode $mode -port $portInput -listenAddress $listenAddress -wslAddress $wslAddress
        HandleFirewall -mode $mode -port $portInput -fireWallDisplayName $fireWallDisplayName
    } else {
        Write-Host "Invalid input. Please enter a valid port number, range, or 'all'." -ForegroundColor Red
    }
}

# ---- Main Execution ----

$wslAddress = Get-WSLIPAddress

if (-not $wslAddress) {
    Write-Host "Error: Could not find WSL IP address." -ForegroundColor Red
    exit
}

$listenAddress = '0.0.0.0'
$fireWallDisplayName = 'WSL Port Forwarding'

$mode = Read-Host "Choose a mode: 'add' to forward ports, 'delete' to remove forwarding, 'list' to see forwarded ports, or 'sync' to synchronize IP addresses"

# Based on the mode, perform appropriate action
switch ($mode) {
    'add' {
        ProcessAddOrDelete -mode 'add' -listenAddress $listenAddress -wslAddress $wslAddress -fireWallDisplayName $fireWallDisplayName
    }

    'delete' {
        ProcessAddOrDelete -mode 'delete' -listenAddress $listenAddress -wslAddress $wslAddress -fireWallDisplayName $fireWallDisplayName
    }

    'list' {
        Invoke-Expression "netsh interface portproxy show all"
    }

    'sync' {
        SyncIPAddresses -wslAddress $wslAddress -listenAddress $listenAddress -fireWallDisplayName $fireWallDisplayName
    }

    default {
        Write-Host "Invalid mode selected. Exiting..." -ForegroundColor Red
        exit
    }
}
