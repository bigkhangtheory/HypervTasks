configuration VmHostServer
{
    <#
    .SYNOPSIS
        The DSC Configuration includes composite resources for the deployment and configuration of a Hyper-V virtualization host.
    
    .PARAMETER VirtualHardDiskPath
        Specifies the default folder to store virtual hard disks on the Hyper-V host.
    
    .PARAMETER VirtualMachinePath
        Specifies the default folder to store virtual machine configuration files on the Hyper-V host.

    .PARAMETER EnableEnhancedSessionMode
        Indicates whether users can use enhanced mode when they connect to virtual machines on this server by using Virtual Machine Connection.
    
    .PARAMETER VirtualMachineMigrationEnabled
        Indicates whether Live Migration should be enabled or disabled on the Hyper-V host.

    .PARAMETER NumaSpanningEnabled
        Specifies whether virtual machines on the Hyper-V host can use resources from more than one NUMA node.

    .PARAMETER UseAnyNetworkForMigration
        Specifies how networks are selected for incoming live migration traffic.
        
        If set to $True, any available network on the host can be used for this traffic.
        
        If set to $False, incoming live migration traffic is transmitted only on the networks specified in the MigrationNetworks property of the host.

    .PARAMETER VirtualMachineMigrationAuthenticationType
        Specifies the type of authentication to be used for live migrations. The acceptable values for this parameter are 'Kerberos' and 'CredSSP'.

    .PARAMETER VirtualMachineMigrationPerformanceOption
        Specifies the performance option to use for live migration. The acceptable values for this parameter are 'TCPIP', 'Compression' and 'SMB'.

    .PARAMETER MaximumVirtualMachineMigrations
        Specifies the maximum number of live migrations that can be performed at the same time on the Hyper-V host.
    
    .PARAMETER MaximumStorageMigrations
        Specifies the maximum number of storage migrations that can be performed at the same time on the Hyper-V host.

    .NOTES
        Requirements:
            - The Hyper-V role has to be installed on the node
            - The Hyper-V PowerShell module has to be installed on the node
    #>
    param (
        [Parameter()]
        [System.String]
        $VirtualHardDiskPath = "$env:PUBLIC\Documents\Hyper-V\Virtual Hard Disks",

        [Parameter()]
        [System.String]
        $VirtualMachinePath = "$env:ProgramData\Microsoft\Windows\Hyper-V",
        
        [Parameter()]
        [System.Boolean]
        $EnableEnhancedSessionMode = $true,

        [Parameter()]
        [System.Boolean]
        $NumaSpanningEnabled = $true,

        [Parameter()]
        [System.Boolean]
        $VirtualMachineMigrationEnabled = $true,

        [Parameter()]
        [System.Boolean]
        $UseAnyNetworkForMigration = $true,

        [Parameter()]
        [ValidateSet('Kerberos', 'CredSSP')]
        [System.String]
        $VirtualMachineMigrationAuthenticationType = 'Kerberos',

        [Parameter()]
        [ValidateSet('TCPIP', 'Compression', 'SMB')]
        [System.String]
        $VirtualMachineMigrationPerformanceOption = 'Compression',

        [Parameter()]
        [UInt32]
        $MaximumStorageMigrations = 2,

        [Parameter()]
        [UInt32]
        $MaximumVirtualMachineMigrations = 2,

        [Parameter()]
        [System.Collections.Hashtable[]]
        $VirtualSwitches,

        [Parameter()]
        [System.Collections.Hashtable[]]
        $VirtualNetworkAdapters

        <# TODO
        [Parameter()]
        [System.Collections.Hashtable[]]
        $VirtualMachines
        #>
    )

    # Import dependencies
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName 'xHyper-V'
    <#
        .NOTES
            The 'xHyper-V' module contains DSC resources for the deployment and configuration of Hyper-V hosts, virtual machines and the following related resources:
            - xVHD (manages VHDs in a Hyper-V Host)
            - xVhdFile (manages files or directories in a VHD. It can be used to copy files/folders to a VHD, remove files/folders from a VHD, and change attributes of a file in a VHD)
            - xVMHardDiskDrive (manages VHD(X) files attached to a Hyper-V virtual machine)
            - xVMHost (manages Hyper-V host settings)
            - xVMHyperV (manages VMs in a Hyper-V Host)
            - xVMNetworkAdapter (manages VMNetAdapters attached to a Hyper-V virtual machine or the Management OS)
            - xVMSwitch (manages virtual switches in a Hyper-V Host)
    #>

    # Requirements
    #   - The Hyper-V role must be installed
    #   - The Hyper-V PowerShell module must be installed
    WindowsFeature hyperVFeature
    {
        Name   = 'Hyper-V'
        Ensure = 'Present'
    }
    WindowsFeature hyperVPowerShellFeature
    {
        Name   = 'Hyper-V-PowerShell'
        Ensure = 'Present'
    }
    $dependsOnHyperVFeatures = '[WindowsFeature]hyperVFeature', '[WindowsFeature]hyperVPowerShellFeature'


    <#  
    ========================================================================
        HYPER-V HOST SETTINGS
    ========================================================================
    #>
    xVMHost hyperVHostSettings
    {
        <#
            .SYNOPSIS
                This DSC Resource configures the Hyper-V settings for a Hyper-V host server.
        #>
        IsSingleInstance                          = 'Yes'
        EnableEnhancedSessionMode                 = $EnableEnhancedSessionMode
        MaximumStorageMigrations                  = $MaximumStorageMigrations
        MaximumVirtualMachineMigrations           = $MaximumVirtualMachineMigrations
        NumaSpanningEnabled                       = $NumaSpanningEnabled
        UseAnyNetworkForMigration                 = $UseAnyNetworkForMigration
        VirtualHardDiskPath                       = $VirtualHardDiskPath
        VirtualMachineMigrationAuthenticationType = $VirtualMachineMigrationAuthenticationType
        VirtualMachineMigrationPerformanceOption  = $VirtualMachineMigrationPerformanceOption
        VirtualMachinePath                        = $VirtualMachinePath
        VirtualMachineMigrationEnabled            = $VirtualMachineMigrationEnabled
        DependsOn                                 = $dependsOnHyperVFeatures
    }
    $dependsOnVmHostSettings = '[xVMHost]hyperVHostSettings'


    <#
    ===========================================================================
        HYPER-V VIRTUAL SWITCH
    ===========================================================================
    #>
    # configure Hyper-V Virtual switches
    if ($null -ne $VirtualSwitches)
    {
        # dependency place holder
        $dependsOnVirtualSwitches = New-Object -TypeName System.Collections.ArrayList
        # instantiate DSC Resources for Hyper-V virtual switches
        foreach ($mySwitch in $VirtualSwitches)
        {
            # remove Case Sensitivity of ordered Dictionary or Hashtables
            $mySwitch = @{} + $mySwitch
            
            # compose configuration name for Hyper-V virtual switch, stripping non-letter characters
            $myExecutionName = "vSwitch_$($mySwitch.Name -replace '[().:\s]', '')"
            
            # this resource depends on Hyper-V roles installed
            $mySwitch.DependsOn = $dependsOnHyperVFeatures
            
            # ensure Present if not specified
            if (-not $mySwitch.ContainsKey('Ensure'))
            {
                $mySwitch.Ensure = 'Present'
            }
            
            # create DSC resource for Hyper-V virtual switch
            $Splatting = @{
                ResourceName  = 'xVMSwitch'
                ExecutionName = $myExecutionName
                Properties    = $mySwitch
                NoInvoke      = $true
            }
            (Get-DscSplattedResource @Splatting).Invoke($mySwitch)
            
            # add DSC Configuration name as dependency for next Configuration
            $dependsOnVirtualSwitches.Add("[$($Splatting.ResourceName)]$myExecutionName")
        } #foreach
    } #if
    elseif ($null -ne $VirtualNetworkAdapters)
    {
        throw 'ERROR: Cannot create virtual network adapters for the management OS if virtual switches do not exist.'
    } # HYPER-V VIRTUAL SWITCH


    <#
    ===========================================================================
        HYPER-V MANAGEMENT NETWORK ADAPTER
    ===========================================================================
    #>
    # configure Hyper-V management OS virtual network adapter
    if ($null -ne $VirtualNetworkAdapters)
    {
        # instantiate DSC Resources for Hyper-V management OS virtual network adapter
        foreach ($myAdapter in $VirtualNetworkAdapters)
        {
            if (-not ($VirtualSwitches.Name -contains $myAdapter.SwitchName))
            {
                # at this point, the management OS virtual network adapter does not specify an existing virtual switch
                throw 'ERROR: Cannot create virtual network adapters for the management OS if the virtual switch does not exist.'
            }
            
            # remove Case Sensitivity of ordered Dictionary or Hashtables
            $myAdapter = @{} + $myAdapter
            
            # compose configuration name for management OS virtual network adapter, stripping non-letter characters
            $myExecutionName = "vEthernet_$($myAdapter.Name -replace '[().:\s]', '')"

            # this resource depends on the Hyper-V virtual switch resource
            $myAdapter.DependsOn = $dependsOnVirtualSwitches
            
            # ensure Present if not specified
            if (-not $myAdapter.ContainsKey('Ensure'))
            {
                $myAdapter.Ensure = 'Present'
            }
            
            # this virutal network adapter is identified by it's name
            $myAdapter.Id = $myAdapter.Name 
            
            # this virtual network adapter is attached to the management OS
            $myAdapter.VMName = 'ManagementOS'

            # If specified, set static IP on management virtual network adapter
            if ($myAdapter.NetworkSetting)
            {
                $myAdapter.NetworkSetting = xNetworkSettings {
                    IpAddress      = $myAdapter.NetworkSetting.IpAddress
                    Subnet         = $myAdapter.NetworkSetting.Subnet
                    DefaultGateway = $myAdapter.NetworkSetting.DefaultGateway
                    DnsServer      = $myAdapter.NetworkSetting.DnsServer
                }
            }
            # create DSC resource for Hyper-V virtual switch
            $Splatting = @{
                ResourceName  = 'xVMNetworkAdapter'
                ExecutionName = $myExecutionName
                Properties    = $myAdapter
                NoInvoke      = $true
            }
            (Get-DscSplattedResource @Splatting).Invoke($myAdapter)
            
        }
    } # HYPER-V MANAGEMENT NETWORK ADAPTER

    <# TODO
    ===========================================================================
        HYPER-V VIRTUAL MACHINES
    ===========================================================================
    #>
    #if ($null -ne $VirtualMachines)
    #{
    #    # instantiate DSC Resources for Hyper-V virtual machines
    #    foreach ($myVirtualMachine in $VirtualMachines)
    #    {
    #        # remove case sensitivity for ordered Dictionary or Hashtables
    #        $myVirtualMachine = @{ } + $myVirtualMachine

    #        # first, create virtual hard disk file
    #        xVhd "vhdx_$($myVirtualMachine.Name)"
    #        {
    #            Name = $myVirtualMachine.Name
    #            Path = $myVirtualMachine.Path
    #            Generation = 'Vhdx'
    #            Type = 'Dynamic'
    #        }
    #    }
    #}
}