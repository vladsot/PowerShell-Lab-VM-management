function New-LabVM {
    param(
        [string]$Name,
        [string]$Template,   # folder name
        [int]$MemoryGB = 3,
        [int]$CPU = 2,
        [string]$Switch = "Internal Switch"
    )

    $basePath = "D:\VirtualMachines"
    $vmPath = "$basePath\$Name"
    $diffDisk = "$basePath\Differencing\$Name.vhdx"
    $templateFolder = "$basePath\Templates\$Template"

    # Validate template folder
    if (-not (Test-Path $templateFolder)) {
        throw "Template folder not found: $templateFolder"
    }

    # Find VHDX inside template folder
    $templateVHD = Get-ChildItem -Path $templateFolder -Filter *.vhdx | Select-Object -First 1
    if (-not $templateVHD) {
        throw "No VHDX found in $templateFolder"
    }

    # Ensure folders exist
    New-Item -ItemType Directory -Path $vmPath -Force | Out-Null
    New-Item -ItemType Directory -Path "$basePath\Differencing" -Force | Out-Null

    # Prevent overwrite
    if (Get-VM -Name $Name -ErrorAction SilentlyContinue) {
        throw "VM $Name already exists"
    }

    # Create differencing disk
    New-VHD -Path $diffDisk -ParentPath $templateVHD.FullName -Differencing

    # Create Gen1 VM
    New-VM -Name $Name -MemoryStartupBytes ($MemoryGB * 1GB) `
        -Generation 1 -Path $vmPath -SwitchName $Switch

    # Attach disk to IDE (required for Gen1 boot)
    Add-VMHardDiskDrive -VMName $Name `
        -ControllerType IDE -ControllerNumber 0 -ControllerLocation 0 `
        -Path $diffDisk

    # CPU
    Set-VMProcessor -VMName $Name -Count $CPU

	# Disable dynamic Memory
	Set-VMMemory -VMName $Name -DynamicMemoryEnabled $false
	
    # Checkpoint type = Production
    Set-VM -Name $Name -CheckpointType Production

    # Secure Boot (not applicable to Gen1, but included safely)
    try {
        Set-VMFirmware -VMName $Name -EnableSecureBoot Off -ErrorAction Stop
    } catch {
        # Ignore for Gen1 VMs
    }

    # Start VM
    #Start-VM $Name
}

function Remove-LabVM {
    param([string]$Name)

    $basePath = "D:\VirtualMachines"
    $vmPath = "$basePath\$Name"
    $diffDisk = "$basePath\Differencing\$Name.vhdx"

    $vm = Get-VM -Name $Name -ErrorAction SilentlyContinue

    if ($vm) {
        # Stop only if running
        if ($vm.State -ne "Off") {
            Stop-VM -Name $Name -Force -ErrorAction SilentlyContinue
        }

        # Remove VM
        Remove-VM -Name $Name -Force
    }

    # Cleanup files (always attempt)
    if (Test-Path $vmPath) {
        Remove-Item $vmPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path $diffDisk) {
        Remove-Item $diffDisk -Force -ErrorAction SilentlyContinue
    }
}
