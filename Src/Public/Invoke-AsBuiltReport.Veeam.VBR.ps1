function Invoke-AsBuiltReport.Veeam.VBR {
    <#
    .SYNOPSIS
        PowerShell script to document the configuration of Veeam VBR in Word/HTML/Text formats
    .DESCRIPTION
        Documents the configuration of Veeam VBR in Word/HTML/Text formats using PScribo.
    .NOTES
        Version:        0.1.0
        Author:         Tim Carman
        Twitter:
        Github:
        Credits:        Iain Brighton (@iainbrighton) - PScribo module

    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Veeam.VBR
    #>

	# Do not remove or add to these parameters
    param (
        [String[]] $Target = "localhost",
        [PSCredential] $Credential
    )

    # Import Report Configuration
    $Report = $ReportConfig.Report
    $InfoLevel = $ReportConfig.InfoLevel
    $Options = $ReportConfig.Options

    # Used to set values to TitleCase where required
    $TextInfo = (Get-Culture).TextInfo

	# Update/rename the $System variable and build out your code within the ForEach loop. The ForEach loop enables AsBuiltReport to generate an as built configuration against multiple defined targets.

    #region foreach loop
    foreach ($System in $Target) {
        #region: Start Load VEEAM Snapin / Module
        # Loading Module or PSSnapin
        # Make sure PSModulePath includes Veeam Console
        $MyModulePath = "C:\Program Files\Veeam\Backup and Replication\Console\"
        $env:PSModulePath = $env:PSModulePath + "$([System.IO.Path]::PathSeparator)$MyModulePath"
        if ($Modules = Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
            try {
                $Modules | Import-Module -WarningAction SilentlyContinue
                }
                catch {
                    throw "Failed to load Veeam Modules"
                    }
            }
            else {
                "No Veeam Modules found, Fallback to SnapIn."
                try {
                    Add-PSSnapin -PassThru VeeamPSSnapIn -ErrorAction Stop | Out-Null
                    }
                    catch {
                        throw "Failed to load VeeamPSSnapIn and no Modules found"
                        }
            }
            #endregion

            #region: Query Version
            if ($Module = Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
                try {
                    switch ($Module.Version.ToString()) {
                        {$_ -eq "1.0"} {  [int]$VbrVersion = "11"  }
                        Default {[int]$VbrVersion = "11"}
                    }
                    }
                    catch {
                        throw "Failed to get Version from Module"
                        }
                }
                else {
                    "No Veeam Modules found, Fallback to SnapIn."
                    try {
                        [int]$VbrVersion = (Get-PSSnapin VeeamPSSnapin).PSVersion.ToString()
                        }
                        catch {
                            throw "Failed to get Version from Module or SnapIn"
                            }
                }
            #endregions

            #region: Start BRHost Connection
            $OpenConnection = (Get-VBRServerSession).Server
            if($OpenConnection -eq $System) {
            } elseif ($null -eq $OpenConnection) {
                try {
                    Connect-VBRServer -Server $System
                }
                catch {
                    Throw "Failed to connect to Veeam BR Host '$System' with user '$env:USERNAME'"
                }
            } else {
                Disconnect-VBRServer
                try {
                    Connect-VBRServer -Server $System
                }
                catch {
                    Throw "Failed to connect to Veeam BR Host '$System' with user '$env:USERNAME'"
                }
            }

            $NewConnection = (Get-VBRServerSession).Server
            if ($null -eq $NewConnection) {
                Throw "Failed to connect to Veeam BR Host '$System' with user '$env:USERNAME'"
            }
            #endregion
	}
	#endregion foreach loop
}
