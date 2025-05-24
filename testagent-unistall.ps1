$ErrorActionPreference = "Stop"

# Hardcoded VM list
$vmList = @(
    @{ Subscription = "SubID"; VMName = "VMname"; ResourceGroupName = "RGname" } 
)

# Authenticate using Managed Identity
try {
    Write-Output "Authenticating to Azure with Managed Identity..."
    Connect-AzAccount -Identity | Out-Null
} catch {
    Write-Error "Azure login failed: $_"
    throw $_
}

foreach ($vm in $vmList) {
    $VMName = $vm.VMName
    $ResourceGroupName = $vm.ResourceGroupName
    $SubscriptionId = $vm.Subscription

    Write-Output "n===== Processing VM: $VMName ====="

    try {
        Set-AzContext -SubscriptionId $SubscriptionId

        # Check VM power state
        $vmStatus = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Status
        $powerState = ($vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" }).DisplayStatus
        $wasInitiallyStopped = $powerState -ne "VM running"

        if ($wasInitiallyStopped) {
            Write-Output "VM is not running. Starting VM..."
            Start-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName | Out-Null

            # Poll for VM to be running
            $maxWaitTime = 300  # 5 minutes
            $waitInterval = 15
            $elapsed = 0
            $vmReady = $false

            while (-not $vmReady -and $elapsed -lt $maxWaitTime) {
                Start-Sleep -Seconds $waitInterval
                $vmStatus = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Status
                $powerState = ($vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" }).DisplayStatus
                Write-Output "Waiting for VM to be ready... Current status: $powerState"
                $vmReady = ($powerState -eq "VM running")
                $elapsed += $waitInterval
            }

            if (-not $vmReady) {
                throw "VM did not start within expected time."
            }

            Write-Output "VM is running. Waiting 30 seconds for OS to stabilize..."
            Start-Sleep -Seconds 30
        } else {
            Write-Output "VM is already running."
        }

        # Get OS type and location
        $vmObj = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName
        $osType = $vmObj.StorageProfile.OsDisk.OsType
        $location = $vmObj.Location

        # Remove existing CustomScriptExtension (Windows only)
        $extensions = Get-AzVMExtension -VMName $VMName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        foreach ($ext in $extensions) {
            if ($ext.Publisher -eq "Microsoft.Compute" -and $ext.Type -eq "CustomScriptExtension") {
                Write-Output "Removing existing CustomScriptExtension: $($ext.Name)"
                Remove-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $VMName -Name $ext.Name -Force -ErrorAction SilentlyContinue

                # Wait for removal
                $extRemoved = $false
                $pollTime = 0
                while (-not $extRemoved -and $pollTime -lt 60) {
                    Start-Sleep -Seconds 5
                    $pollTime += 5
                    $existing = Get-AzVMExtension -VMName $VMName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $ext.Name }
                    if (-not $existing) {
                        $extRemoved = $true
                    } else {
                        Write-Output "Waiting for extension '$($ext.Name)' to be fully removed..."
                    }
                }

                if (-not $extRemoved) {
                    Write-Warning "Timeout while waiting for extension '$($ext.Name)' to be removed."
                }
            }
        }

        # Remove TestAgent extensions
        foreach ($ext in $extensions) {
            if ($ext.Publisher -like "*TestAgent*") {
                Write-Output "Removing existing TestAgent extension: $($ext.Name)"
                Remove-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $VMName -Name $ext.Name -Force -ErrorAction SilentlyContinue
            }
        }

        # Build uninstall command and extension config based on OS type
        if ($osType -eq "Windows") {
            $uninstallCommand = 'powershell -Command "Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -like ''*TestAgent*'' } | ForEach-Object { Start-Process msiexec -ArgumentList ''/x'',$_.IdentifyingNumber,''/qn'',''/norestart'' -Wait }"'
            $publisher = "Microsoft.Compute"
            $extensionType = "CustomScriptExtension"
            $typeVersion = "1.10"
        } else {
            $uninstallCommand = 'bash -c "echo ''Stopping TestAgent...''; sudo systemctl stop testagent || sudo service testagent stop || true; echo ''Uninstalling TestAgent...''; if command -v rpm &>/dev/null; then sudo rpm -e testagent; elif command -v dpkg &>/dev/null; then sudo dpkg --purge testagent; else echo ''No supported package manager found.''; fi"'
            $publisher = "Microsoft.Azure.Extensions"
            $extensionType = "CustomScript"
            $typeVersion = "2.1"
        }

        # Install uninstall script extension
        $customScriptName = "UninstallTestAgentScript"
        Write-Output "Installing uninstall script extension on VM: $VMName"
        Set-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $VMName `
            -Location $location -Name $customScriptName -Publisher $publisher `
            -ExtensionType $extensionType -TypeHandlerVersion $typeVersion `
            -Settings @{ "commandToExecute" = $uninstallCommand }

        # Poll for completion
        $timeout = 300
        $interval = 10
        $elapsed = 0
        Write-Output "Waiting for uninstall script to complete..."

        do {
            Start-Sleep -Seconds $interval
            $extStatus = Get-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $VMName -Name $customScriptName -ErrorAction SilentlyContinue
            $provisioningState = $extStatus.ProvisioningState
            Write-Output "Current provisioning state: $provisioningState"
            $elapsed += $interval
        } while (($provisioningState -eq "Creating" -or $provisioningState -eq "Updating") -and $elapsed -lt $timeout)

        if ($provisioningState -ne "Succeeded") {
            Write-Warning "Extension did not complete successfully (State: $provisioningState)"
        } else {
            Write-Output "Extension completed successfully."
        }

        # Clean up uninstall script extension
        Write-Output "Removing uninstall script extension..."
        Remove-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $VMName -Name $customScriptName -Force -ErrorAction SilentlyContinue

        # Restore original power state
        if ($wasInitiallyStopped) {
            Write-Output "Stopping VM to restore original state..."
            Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Force | Out-Null
        }

        Write-Output "✅ Completed cleanup for VM: $VMName"
    }
    catch {
        Write-Warning "⚠️ Skipping VM '$VMName' due to error: $_"
        continue
    }
}
