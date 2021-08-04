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

            #region: Collect and filter Repos
            [Array]$AllRepos = Get-VBRBackupRepository | Where-Object {$_.Type -notmatch "SanSnapshotOnly"}    # Get all Repositories Except SAN
            [Array]$CloudRepos = $AllRepos | Where-Object {$_.Type -match "Cloud"}    # Get all Cloud Repositories
            [Array]$repoList = $AllRepos | Where-Object {$_.Type -notmatch "Cloud"}    # Get all Repositories Except SAN and Cloud
            <#
            Thanks to Bernd Leinfelder for the Scalouts Part!
            https://github.com/berndleinfelder
            #>
            [Array]$scaleouts = Get-VBRBackupRepository -scaleout
            if ($scaleouts) {
                foreach ($scaleout in $scaleouts) {
                    $extents = Get-VBRRepositoryExtent -Repository $scaleout
                    foreach ($ex in $extents) {
                        $repoList = $repoList + $ex.repository
                    }
                }
            }
            #endregion

            #region: Repository
            if ($VbrVersion -ge 11) {
                $RepoData = $repoList | Get-vPCRepoInfo
            }
            else {
                $RepoData = $repoList | Get-vPCRepoInfoPre11
            }
            $RepoReport = @()
            ForEach ($RawRepo in $RepoData){
                If ($RawRepo.FreePercentage -lt $repoCritical) {$Status = "Critical"}
                ElseIf ($RawRepo.FreePercentage -lt $repoWarn) {$Status = "Warning"}
                ElseIf ($RawRepo.FreePercentage -eq "Unknown") {$Status = "Unknown"}
                Else {$Status = "OK"}
                $Object = "" | Select-Object "Repository Name", "Free (GB)", "Total (GB)", "Free (%)", "Status"
                $Object."Repository Name" = $RawRepo.Target
                $Object."Free (GB)" = $RawRepo.StorageFree
                $Object."Total (GB)" = $RawRepo.StorageTotal
                $Object."Free (%)" = $RawRepo.FreePercentage
                $Object."Status" = $Status

                $RepoReport += $Object
                }

            <#
            Thanks to Chris Arceneaux for his Cloud Repo Snippet
            https://forums.veeam.com/powershell-f26/veeam-cloud-repository-disk-space-report-t63332.html
            #>
            if ($CloudRepos) {
                Write-Debug "Cloud Repo Section Entered..."
                $CloudProviders = Get-VBRCloudProvider

                foreach ($CloudProvider in $CloudProviders){
                    if ($CloudProvider.Resources){
                        foreach ($CloudProviderRessource in $CloudProvider.Resources){
                            $CloudRepo = $CloudRepos | Where-Object {($_.CloudProvider.HostName -eq $CloudProvider.DNSName) -and ($_.Name -eq $CloudProviderRessource.RepositoryName)}
                            $totalSpaceGb = [Math]::Round([Decimal]$CloudProviderRessource.RepositoryAllocatedSpace/1KB,2)
                            #$totalUsedGb = [Math]::Round([Decimal]([Veeam.Backup.Core.CBackupRepository]::GetRepositoryBackupsSize($CloudRepo.Id.Guid))/1GB,2)
                            if ($VbrVersion -ge 10) {
                                $totalUsedGb = [Math]::Round([Decimal]([Veeam.Backup.Core.CBackupRepository]::GetRepositoryBackupsSize($CloudRepo.Id.Guid))/1GB,2)
                            }
                            else {
                                $totalUsedGb = [Math]::Round([Decimal]([Veeam.Backup.Core.CBackupRepository]::GetRepositoryStoragesSize($CloudRepo.Id.Guid))/1GB,2)
                            }
                            $totalFreeGb = [Math]::Round($totalSpaceGb - $totalUsedGb,2)
                            $freePercentage = [Math]::Round(($totalFreeGb/$totalSpaceGb)*100)
                            If ($freePercentage -lt $repoCritical) {$Status = "Critical"}
                            ElseIf ($freePercentage -lt $repoWarn) {$Status = "Warning"}
                            ElseIf ($freePercentage -eq "Unknown") {$Status = "Unknown"}
                            Else {$Status = "OK"}
                            $Object = "" | Select-Object "Repository Name", "Free (GB)", "Total (GB)", "Free (%)", "Status"
                            $Object."Repository Name" = $CloudProviderRessource.RepositoryName
                            $Object."Free (GB)" = $totalFreeGb
                            $Object."Total (GB)" = $totalSpaceGb
                            $Object."Free (%)" = $freePercentage
                            $Object."Status" = $Status

                            $RepoReport += $Object
                        }
                    }
                }

                #region Report

                Section -Style Heading2 'Veeam Backup & Replication Server' {
                    Paragraph "The following sections detail the configuration of VBR Server '$System'"
                    BlankLine
                    # Gather basic  Server Information
                    $VBRServerInfo = [PSCustomObject]@{
                        'vCenter Server' = $System
                        'Version' = $VbrVersion
                    }
                    $TableParams = @{
                        Name = "VBR Server Summary - $System"
                        ColumnWidths = 20, 20, 20, 20, 20
                    }
                    if ($Report.ShowTableCaptions) {
                        $TableParams['Caption'] = "- $($TableParams.Name)"
                    }
                    $VBRServerInfo | Table @TableParams
                }

                Section -Style Heading3 'Repositories' {
                    $TableParams = @{
                        Name = "Repositories - $System"
                        ColumnWidths = 25, 25, 25, 25
                    }
                    if ($Report.ShowTableCaptions) {
                        $TableParams['Caption'] = "- $($TableParams.Name)"
                    }
                    $RepoReport | Table @TableParams
                }
                #endreion

            }
            #endregion
	}
	#endregion foreach loop
}
