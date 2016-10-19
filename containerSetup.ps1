#region DSC Method
install-package -name xDismFeature,xPendingReboot,xWindowsUpdate,cChoco,cWindowsContainer,xHyper-V,xPSDesiredStateConfiguration -verbose
[DscLocalConfigurationManager()]
Configuration win10DockerLocal{
    Node $env:computername {
        Settings{
            RefreshMode = 'Push'
            RebootNodeIfNeeded = $false
            AllowModuleOverwrite = $true
            ConfigurationMode = 'ApplyOnly'                        
        }
    }
};win10DockerLocal -outputpath $env:temp\win10Docker
set-dsclocalconfigurationmanager -path $env:temp\win10Docker -verbose -force

Configuration win10Docker {
    Param([switch]$runUpdates)
    import-dscresource -name xDismFeature,xPendingReboot,xWindowsUpdateAgent,Environment,xVMSwitch,cWindowsContainer
    import-dscresource -module cChoco -moduleversion 2.2.0.79
    import-dscresource -module PSDesiredStateConfiguration -moduleversion 1.1
    Node $env:COMPUTERNAME{
        #region Features
        xDismFeature Containers {
            Name = 'Containers'
            Ensure = 'Present'
            DependsOn = "[xDismFeature]HyperV"
        }
        xDismFeature HyperV{
            Name = 'Microsoft-Hyper-V'
            Ensure = 'Present'
        }
        xPendingReboot FeatureReboot {
            DependsOn = '[xDismFeature]Containers'
            Name = 'FeatureReboot'
            SkipWindowsUpdate = $true
            SkipPendingFileRename = $true
            SkipPendingComputerRename = $true
            SkipCcmClientSDK = $true
        }
        #endregion

        #region Updates        
        xWindowsUpdateAgent WinUpdate {
            IsSingleInstance = 'Yes'
            Notifications = 'ScheduledInstallation'
            Category = 'Important','Optional','Security'
            Source = 'MicrosoftUpdate'
            DependsOn = '[xPendingReboot]FeatureReboot'
        }
        xPendingReboot RebootIfNecessary {
            Name = "Microsoft Update Reboot"
            DependsOn = '[xWindowsUpdateAgent]WinUpdate'
            SkipPendingComputerRename = $true
            SkipPendingFileRename = $true
            SkipCcmClientSDK = $true
        }        
        #endregion

        #region Docker Install
        script DockerInstallZip {
            DependsOn = '[xPendingReboot]FeatureReboot','[xPendingReboot]RebootIfNecessary'
            testscript = {test-path "$env:temp\docker-1.13.0-dev.zip"}
            setScript = {Invoke-WebRequest "https://master.dockerproject.org/windows/amd64/docker-1.13.0-dev.zip" -OutFile "$env:TEMP\docker-1.13.0-dev.zip" -UseBasicParsing}
            getscript = {@{ZipFile = get-item "$env:temp\docker-1.13.0-dev.zip"}}            
        }

        archive DockerInstall {
            Destination = "$env:programFiles"
            Path = "$env:temp\docker-1.13.0-dev.zip"
            DependsOn = '[script]DockerInstallZip'            
            Ensure = 'Present'            
        }
        Environment dockerToPath {
            name = 'Path'
            Path = $true
            DependsOn = '[archive]DockerInstall'
            value = "$env:programFiles\docker"
            Ensure = 'Present'
        }
        Script dockerService{
            DependsOn = '[environment]dockerToPath'
            Getscript = {@{service = (get-service -name docker -erroraction silentlycontinue)}}
            Testscript = {(get-service -name docker -erroraction silentlycontinue) -ne $null}
            Setscript = {& "$env:ProgramFiles\docker\dockerd" --register-service}
        }
        Service dockerService {
            DependsOn = '[Script]dockerService'
            Name = 'docker'
            State = 'Running'
            StartupType = 'Automatic'
            Ensure = 'Present'
        }
        #endregion

        #region pull Images        
        <#
        script downloadNanoImage {
            DependsOn = '[Service]dockerService'
            getscript = {@{image = & "$env:ProgramFiles\docker\docker" images 'microsoft/nanoserver'}}
            setscript = {& "$env:ProgramFiles\docker\docker" pull 'microsoft/nanoserver'}
            testscript = {(& "$env:ProgramFiles\docker\docker" images --quiet 'microsoft/nanoserver' ) -ne $null}
        }        
        script downloadCoreImage {
            DependsOn = '[Service]dockerService'
            getscript = {@{image = & "$env:ProgramFiles\docker\docker" images 'microsoft/windowsservercore'}}
            setscript = {& "$env:ProgramFiles\docker\docker" pull 'microsoft/windowsservercore'}
            testscript = {(& "$env:ProgramFiles\docker\docker" images -q 'microsoft/windowsservercore' ) -ne $null}
        } 
        #>       
        #endregion 

        #region setup hypervisor
        xVMSwitch vSwitch_External {
            DependsOn = '[xPendingReboot]FeatureReboot'
            Name = 'vSwitch_External'
            Ensure = 'Present'
            Type = 'External'
            NetAdapterName = 'Ethernet'
        }
        #endregion
    }
}; win10Docker -outputpath $env:temp\win10Docker
start-dscconfiguration -path $env:temp\win10Docker -computername $env:computername -verbose -wait -force
#endregion

#invoke-method
<#
Invoke-WebRequest "https://master.dockerproject.org/windows/amd64/docker-1.13.0-dev.zip" -OutFile "$env:TEMP\docker-1.13.0-dev.zip" -UseBasicParsing
Expand-Archive -Path "$env:TEMP\docker-1.13.0-dev.zip" -DestinationPath $env:ProgramFiles
if($env:path -notmatch 'c:\\program files\\docker'){
    $env:path += ";c:\program files\docker"
    [Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\Program Files\Docker", [EnvironmentVariableTarget]::Machine)
}
dockerd --register-service
get-service -name docker | start-service -verbose -passthru | set-service -startuptype Automatic
#>