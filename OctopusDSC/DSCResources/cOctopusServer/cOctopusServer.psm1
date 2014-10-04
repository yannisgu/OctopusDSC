$ErrorActionPreference = "Stop"

function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,
		[parameter(Mandatory = $true)]
		[System.String]
		$AdminUser,

		[parameter(Mandatory = $true)]
		[System.String]
		$AdminPassword
	)

    Write-Verbose "Checking if Octopus Server is installed"
    $installLocation = GetInstallLocation
    $installed = ($installLocation -ne $null) -and (Test-Path $installLocation)
    Write-Verbose "OctopusServer installed: $installed"

    if($installed) {
        $service = GetService $name
        $configured = $service -ne $null
    }


    $ensure = "Absent"
    if($installed -and $configured)  
    {
        $ensure =  "Present"
    }

    Write-Verbose "OctopusServer $Name present $ensure"

	@{
        Name = $Name
        Ensure = $ensure
        Installed = $installed
    }
}

function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[System.Boolean]
		$UpgradeCheck = $true,
		[System.Boolean]
		$ForceSsl  = $false,
		[System.Boolean]
		$UpgradeCheckWithStatistics = $true,
		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure = "Present",
		[parameter(Mandatory = $true)]
		[System.String]
		$Name,
		[System.String[]]
		$WebListPrefixes = "http://localhost",
		[int]
		$StorageListenPort = 10931,
		[int]
		$CommsListenPort = 10943,
		[parameter(Mandatory = $true)]
		[System.String]
		$AdminUser,
		[parameter(Mandatory = $true)]
		[System.String]
		$AdminPassword,
        [string]
        $Licence = ""
	)
    
    $currentResource = (Get-TargetResource -Name $Name -AdminUser $AdminUser -AdminPassword $AdminPassword)
    if ($Ensure -eq "Absent" -and $currentResource["Installed"])
    {
        Write-Verbose "uninstall"
    }
    elseif ($Ensure -eq "Present" -and -not $currentResource["Installed"]) {
        Write-Verbose "install"
        InstalOctopusServer
    }

    if($Ensure -eq "Present" -and $currentResource["Ensure"] -ne "Present") {
        ConfigureOctopusServer -Name $name -UpgradeCheck $UpgradeCheck -UpgradeCheckWithStatistics $UpgradeCheckWithStatistics -ForceSsl $ForceSsl -WebListPrefixes $WebListPrefixes -StorageListenPort $StorageListenPort -CommsListenPort $CommsListenPort -AdminUser $AdminUser -AdminPassword $AdminPassword -Licence $Licence
    }
}

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [System.Boolean]
        $UpgradeCheck = $true,
        [System.Boolean]
        $ForceSsl  = $false,
        [System.Boolean]
        $UpgradeCheckWithStatistics = $true,
        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure = "Present",
        [parameter(Mandatory = $true)]
        [System.String]
        $Name,
        [System.String[]]
        $WebListPrefixes = "http://localhost",
        [int]
        $StorageListenPort = 10931,
        [int]
        $CommsListenPort = 10943,
        [parameter(Mandatory = $true)]
        [System.String]
        $AdminUser,
        [parameter(Mandatory = $true)]
        [System.String]
        $AdminPassword,
        [string]
        $Licence = ""
    )
    
    $currentResource = (Get-TargetResource -Name $Name -AdminUser $AdminUser -AdminPassword $AdminPassword)

    $ensureMatch = $currentResource["Ensure"] -eq $Ensure
    Write-Verbose "Ensure: $($currentResource["Ensure"]) vs. $Ensure = $ensureMatch"
    if (!$ensureMatch) 
    {
        return $false
    }

    return $true
}

function ConfigureOctopusServer {
    param([string]$Name, [boolean]$UpgradeCheck, [bool]$UpgradeCheckWithStatistics, [bool]$ForceSsl, [string[]]$WebListPrefixes, [int]$StorageListenPort, [int]$CommsListenPort, [string]$AdminUser, [string]$AdminPassword, [string]$Licence)

    Write-Verbose "Configure Octopus Server"
    $installDir = GetInstallLocation
    Invoke-AndAssert { & "$installDir\Octopus.Server.exe" create-instance --instance "$Name" --config "C:\Octopus\$Name\OctopusServer.config" --console }
    Invoke-AndAssert { & "$installDir\Octopus.Server.exe" configure --instance "$Name" --home "C:\Octopus\$Name" --storageMode "Embedded" --upgradeCheck $UpgradeCheck --upgradeCheckWithStatistics $UpgradeCheckWithStatistics --webAuthenticationMode "UsernamePassword" --webForceSSL $ForceSsl --webListenPrefixes ([string]::Join( ",", $WebListPrefixes)) --storageListenPort $StorageListenPort --commsListenPort $CommsListenPort --console  }
    Invoke-AndAssert { & "$installDir\Octopus.Server.exe" service --instance "$Name" --stop  --console }
    Invoke-AndAssert { & "$installDir\Octopus.Server.exe" admin --instance "$Name" --username $AdminUser --password $AdminPassword --wait "5000" --console }
    if($Licence) {
        $Licence = [System.Convert]::ToBase64String( [System.Text.Encoding]::UTF8.GetBytes($Licence.Trim()))
        Invoke-AndAssert { & "$installDir\Octopus.Server.exe" license --instance "$Name" --licenseBase64 "$Licence" --wait "5000" --console }
    }
    Invoke-AndAssert { & "$installDir\Octopus.Server.exe" service --instance "$Name" --install --reconfigure --start --console }
}

function InstalOctopusServer {
     Write-Verbose "Beginning Octopus installation" 
  
    $octopusDownloadUrl = "http://octopusdeploy.com/downloads/latest/OctopusServer64"
    if ([IntPtr]::Size -eq 4) 
    {
        $octopusDownloadUrl = "http://octopusdeploy.com/downloads/latest/OctopusServer"
    }
    

    $octopusPath = "$($env:SystemDrive)\Octopus"

    if(-not (Test-Path $octopusPath)) {
        mkdir $octopusPath | Out-Null
    }

    $octopusMsiPath = "$octopusPath\Octopus.msi"
    if ((test-path $octopusMsiPath ) -ne $true) 
    {
        Write-Verbose "Downloading latest Octopus Server MSI from $octopusDownloadUrl to $octopusMsiPath "
        Invoke-WebRequest $octopusDownloadUrl -OutFile $octopusMsiPath
    }
  
    Write-Verbose "Installing MSI..."
    $msiLog = "$($env:SystemDrive)\Octopus\Octopus.msi.log"
    $msiExitCode = (Start-Process -FilePath "msiexec.exe" -ArgumentList "/i $octopusMsiPath /quiet /l*v $msiLog" -Wait -Passthru).ExitCode
    Write-Verbose "Octopus MSI installer returned exit code $msiExitCode"
    if ($msiExitCode -ne 0) 
    {
        throw "Installation of the Octopus MSI failed; MSIEXEC exited with code: $msiExitCode. View the log at $msiLog"
    }
}

function GetService {
    param($name)
    if($name -eq "OctopusServer") {
        $serviceName = "OctopusDeploy"
    }
    else{
        $serviceName = "OctopusDeploy: $name"
    }
    
    Get-Service $serviceName -ErrorAction SilentlyContinue
    
}

function GetInstallLocation {
    (get-itemproperty -path "HKLM:\Software\Octopus\OctopusServer" -ErrorAction SilentlyContinue).InstallLocation
}

function Invoke-AndAssert {
    param ($block) 
  
    & $block | Write-Verbose
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) 
    {
        throw "Command returned exit code $LASTEXITCODE"
    }
}


Export-ModuleMember -Function *-TargetResource



