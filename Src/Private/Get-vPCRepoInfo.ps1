<#
Big thanks to Shawn, creating an awsome Reporting Script:
http://blog.smasterson.com/2016/02/16/veeam-v9-my-veeam-report-v9-0-1/
#>

Function Get-vPCRepoInfo {
    [CmdletBinding()]
        param (
            [Parameter(Position=0, ValueFromPipeline=$true)]
            [PSObject[]]$Repository
        )
        Begin {
            $outputAry = @()
            Function New-RepoObject {param($name, $repohost, $path, $free, $total)
            $repoObj = New-Object -TypeName PSObject -Property @{
                Target = $name
                RepoHost = $repohost
                            Storepath = $path
                            StorageFree = [Math]::Round([Decimal]$free/1GB,2)
                            StorageTotal = [Math]::Round([Decimal]$total/1GB,2)
                            FreePercentage = [Math]::Round(($free/$total)*100)
                }
            Return $repoObj | Select-Object Target, RepoHost, Storepath, StorageFree, StorageTotal, FreePercentage
            }
        }
        Process {
            Foreach ($r in $Repository) {
                # Refresh Repository Size Info
                try {
                    if ($PSRemote) {
                        $SyncSpaceCode = {
                            param($RepositoryName);
                            [Veeam.Backup.Core.CBackupRepositoryEx]::SyncSpaceInfoToDb((Get-VBRBackupRepository -Name $RepositoryName), $true)
                        }

                        Invoke-Command -Session $RemoteSession -ScriptBlock $SyncSpaceCode -ArgumentList $r.Name
                    } else {
                        [Veeam.Backup.Core.CBackupRepositoryEx]::SyncSpaceInfoToDb($r, $true)
                    }

                }
                catch {
                    Write-Debug "SyncSpaceInfoToDb Failed"
                    Write-Error $_.ToString()
                    Write-Error $_.ScriptStackTrace
                }
                If ($r.HostId -eq "00000000-0000-0000-0000-000000000000") {
                    $HostName = ""
                }
                Else {
                    $HostName = $(Get-VBRServer | Where-Object {$_.Id -eq $r.HostId}).Name.ToLower()
                }

                if ($PSRemote) {
                # When veeam commands are invoked remotly they are serialized during transfer. The info property become not object but string.
                # To gather the info following construction should be used
                    $r.info = Invoke-Command -Session $RemoteSession -HideComputerName -ScriptBlock {
                        param($RepositoryName);
                        (Get-VBRBackupRepository -Name $RepositoryName).info
                    } -ArgumentList $r.Name
                }

                Write-Debug $r.Info
                $outputObj = New-RepoObject $r.Name $Hostname $r.FriendlyPath $r.GetContainer().CachedFreeSpace.InBytes $r.GetContainer().CachedTotalSpace.InBytes
            }
            $outputAry += $outputObj
        }
        End {
            $outputAry
        }
    }