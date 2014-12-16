Import-Module rsCommon

Configuration ClientLCM
{
   param ($Node, $pullServerUri, $ObjectGuid, $CertificateID)
   
   Node $Node
   {
      LocalConfigurationManager
      {
         AllowModuleOverwrite = 'True'
         ConfigurationID = $ObjectGuid
         CertificateID = $CertificateID
         ConfigurationModeFrequencyMins = 30
         ConfigurationMode = 'ApplyAndAutoCorrect'
         RebootNodeIfNeeded = 'True'
         RefreshMode = 'Pull'
         RefreshFrequencyMins = 15
         DownloadManagerName = 'WebDownloadManager'
         DownloadManagerCustomData = (@{ServerUrl = $pullServerUri; AllowUnsecureConnection = "false"})
      }
   }
}

Configuration PullServerLCM
{
   
   Node $env:COMPUTERNAME
   {
      LocalConfigurationManager
      {
         AllowModuleOverwrite = 'True'
         ConfigurationModeFrequencyMins = 30
         ConfigurationMode = 'ApplyAndAutoCorrect'
         RebootNodeIfNeeded = 'True'
         RefreshMode = 'PUSH'
         RefreshFrequencyMins = 15
      }
   }
}

. (Get-rsSecrets)
. "$("C:\DevOps", $d.mR, 'PullServerInfo.ps1' -join '\' )"
New-rsEventLogSource -logSource LCM

if(Test-rsCloud) {
   $ObjectGuid = (Get-rsXenInfo -value name) -replace "instance-", ""
}
else {
   $ObjectGuid = ((Get-rsDedicatedInfo -Value $env:COMPUTERNAME) | ? { $_.name -eq $env:COMPUTERNAME } ).id
}

if((Get-rsRole -Value $env:COMPUTERNAME) -eq "pull") {
   $pullServerName = $env:COMPUTERNAME
   chdir "C:\Windows\Temp"
   PullServerLCM
   Set-DscLocalConfigurationManager -Path "C:\Windows\Temp\PullServerLCM" -Verbose
   Get-ScheduledTask -TaskName "Consistency" | Start-ScheduledTask
   $result = Get-DscLocalConfigurationManager | ConvertTo-Json -Depth 4
   Write-EventLog -LogName DevOps -Source LCM -EntryType Information -EventId 1000 -Message "Applying Desired State Local Configuration $result"
}
else {
   $Node = $env:COMPUTERNAME
   $cN = "CN=" + $Node + "_enc"
   Set-Location -Path ("C:\DevOps", $d.mR -join "\")
   Start -Wait "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "fetch origin $($d.branch_rsConfigs)"
   Start -Wait "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "merge remotes/origin/$($d.branch_rsConfigs)"
   
   if (!(Test-Path -Path $("C:\DevOps", $d.mR, "Certificates", "Credentials" -join '\')))
   {
      New-Item -Path $("C:\DevOps", $d.mR, "Certificates", "Credentials" -join '\') -ItemType directory
   }
   powershell.exe "C:\DevOps\rsProvisioning\makecert.exe" -r -pe -n $cN -sky exchange -ss my $("C:\DevOps", $d.mR, "Certificates\Credentials","$ObjectGuid.cer"  -join '\'), -sr localmachine, -len 2048
   Start -Wait "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "add $("C:\DevOps", $d.mR, "Certificates\Credentials","$ObjectGuid.cer"  -join '\')"
   Start -Wait "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "commit -a -m `"pushing $ObjectGuid.crt`""
   Start-Sleep ([System.Math]::Round((Get-Random -min 0 -Maximum 1.0),2)*100)   
   Start -Wait "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "fetch origin $($d.branch_rsConfigs)"
   Start -Wait "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "merge remotes/origin/$($d.branch_rsConfigs)"
   Start -Wait "C:\Program Files (x86)\Git\bin\git.exe" -ArgumentList "push origin $($d.branch_rsConfigs)"
   chdir "C:\Windows\Temp"
   $pullServerName = $pullServerInfo.pullServerName
   $pullServerUri = "https://" + $pullServerName + ":8080/PSDSCPullServer.svc"
   $certThumbPrint = (Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.PrivateKey.KeySize -eq 2048 -and $_.Subject -eq $cN}).Thumbprint
   ClientLCM -Node $Node -pullServerUri $pullServerUri -ObjectGuid $ObjectGuid -CertificateID $certThumbPrint -OutputPath "C:\Windows\Temp"
   Set-DscLocalConfigurationManager -Path "C:\Windows\Temp" -Verbose
   Get-ScheduledTask -TaskName "Consistency" | Start-ScheduledTask
   $result = Get-DscLocalConfigurationManager | ConvertTo-Json -Depth 4
   Write-EventLog -LogName DevOps -Source LCM -EntryType Information -EventId 1000 -Message "Applying Desired State Local Configuration $result"
}

