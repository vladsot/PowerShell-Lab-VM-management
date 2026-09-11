<#
.SYNOPSIS
    Manages Hyper-V Lab Virtual Machines using differencing disks.
.DESCRIPTION
    Provides functions to create Generation 1 and Generation 2 lab VMs from templates 
    and cleanly remove them along with their associated differencing disks.
#>

# Export functions explicitly if desired, though modern PowerShell auto-discovers them
# Export-ModuleMember -Function New-LabVM, Remove-LabVM

Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete

function New-LabVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [string]$Template,   # folder name
        
        [Parameter(Mandatory = $true)]
        [ValidateSet(1, 2)]
        [int]$Gen,
        
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
    $templateVHD = Get-ChildItem -Path $templateFolder -Recurse -Filter *.vhdx | Select-Object -First 1
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

    # Create VM with specified generation
    New-VM -Name $Name -MemoryStartupBytes ($MemoryGB * 1GB) `
        -Generation $Gen -Path $vmPath -SwitchName $Switch

    # Attach disk to correct controller based on generation
    if ($Gen -eq 1) {
        Add-VMHardDiskDrive -VMName $Name `
            -ControllerType IDE -ControllerNumber 0 -ControllerLocation 0 `
            -Path $diffDisk
    } else {
        Add-VMHardDiskDrive -VMName $Name `
            -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0 `
            -Path $diffDisk
    }

    # CPU
    Set-VMProcessor -VMName $Name -Count $CPU

    # Disable Dynamic Memory
    Set-VMMemory -VMName $Name -DynamicMemoryEnabled $false
    
    # Checkpoint type = Production
    Set-VM -Name $Name -CheckpointType Production

    # Configure Boot Order and Firmware based on Generation
    if ($Gen -eq 1) {
        Set-VMBios -VMName $Name -StartupOrder @("IDE", "CD", "Floppy", "LegacyNetworkAdapter")
    } else {
        try {
            Set-VMFirmware -VMName $Name -EnableSecureBoot Off -ErrorAction Stop
        } catch {
            Write-Warning "Could not configure Secure Boot for $Name"
        }

        $firmware = Get-VMFirmware -VMName $Name
        $hddBootEntry = $firmware.BootOrder | Where-Object { $_.Device -is [Microsoft.HyperV.PowerShell.VMHardDiskDrive] }
        if ($hddBootEntry) {
            Set-VMFirmware -VMName $Name -FirstBootDevice $hddBootEntry
        }
    }

    # Start VM
    #Start-VM $Name
}

function Remove-LabVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

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