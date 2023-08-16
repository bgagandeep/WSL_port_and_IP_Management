
# WSL2 Port Forwarding Script

This PowerShell script provides utilities for managing port forwarding rules for WSL2 (Windows Subsystem for Linux version 2).

## Features

1. **Fetch WSL2 IP Address**: Quickly obtain the IP address assigned to your WSL2 instance.
2. **Sync Port Forwarding Rules**: Update existing port forwarding rules to match the current WSL2 IP address, ensuring seamless connectivity.

## Usage

### Prerequisites

- Windows 10 with WSL2 installed and configured.
- PowerShell with administrator privileges.

### Steps

1. **Run the Script**: 
   ```powershell
   .\wsl2_port_forwarding.ps1
   ```
2. Use the provided functions to manage your port forwarding rules.

### Functions

- `Get-WSLIPAddress`: Fetches the IP address of the WSL2 instance.
- `SyncIPAddresses`: Syncs existing port forwarding rules to the current WSL2 IP.

## Contributing

If you find any bugs or would like to add additional features, please create an issue or submit a pull request.
