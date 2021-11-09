#Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.
Param (
  [Parameter(Mandatory = $True, HelpMessage = "subscription id from terraform")]
  [String]$subscription_id = "",
  [Parameter(Mandatory = $True, HelpMessage = "resource group name")]
  [String]$resource_group_name = "",
  [Parameter(Mandatory = $True, HelpMessage = "vmss name")]
  [String]$vmss_name = "",  
  [Parameter(Mandatory = $True, HelpMessage = "application insights key")]
  [String]$application_insights_key = "",
  [Parameter(Mandatory = $True, HelpMessage = "matchmaker load balancer fqdn")]
  [String]$mm_lb_fqdn = "",
  [Parameter(Mandatory = $false, HelpMessage = "Desired instances of 3D apps running per VM, default 1")]
  [int] $instancesPerNode = 1,
  [Parameter(Mandatory = $false, HelpMessage = "The streaming port start for multiple instances, default 8888")]
  [int] $streamingPort = 8888,
  [Parameter(Mandatory = $false, HelpMessage = "The resolution width of the 3D app, default 1920")]
  [int] $resolutionWidth = 1920,
  [Parameter(Mandatory = $false, HelpMessage = "The resolution height of the 3D app, default 1080")]
  [int] $resolutionHeight = 1080,
  [Parameter(Mandatory = $false, HelpMessage = "The name of the 3D app, default PixelStreamingDemo")]
  [string] $pixel_stream_application_name = "PixelStreamingDemo",
  [Parameter(Mandatory = $false, HelpMessage = "The frames per second of the 3D app, default -1 which reverts to default behavior of UE")]
  [int] $fps = -1,
  [Parameter(Mandatory = $True, HelpMessage = "git path")]
  [String]$gitpath = "",
  [Parameter(Mandatory = $False, HelpMessage = "github access token")]
  [String]$pat = ""
)

$StartTime = Get-Date

#####################################################################################################
#base variables
#####################################################################################################
$logsfolder = "c:\gaming\logs"
$logoutput = $logsfolder + '\ue4-setupVMSS-output-' + (get-date).ToString('MMddyyhhmmss') + '.txt'
$folder = "c:\Unreal\"

$folderNoTrail = $folder
if ($folderNoTrail.EndsWith("\")) {
  $l = $folderNoTrail.Length - 1
  $folderNoTrail = $folderNoTrail.Substring(0, $l)
}

$vmServiceFolder = "$folderNoTrail\Engine\Source\Programs\PixelStreaming\WebServers\SignallingWebServer"
$vmWebServicesFolder = "$folderNoTrail\Engine\Source\Programs\PixelStreaming\WebServers\"
$engineIniFilepath = "$folderNoTrail\" + $pixel_stream_application_name + "\Saved\Config\WindowsNoEditor\Engine.ini"
$executionfilepath = "$folderNoTrail\scripts\startVMSS.ps1"
$taskName = "StartVMSS"
$defaultHttpPort = 80
$defaultHttpsPort = 443
$deploymentLocation = $resource_group_name.Split('-')[1]

$base_name = $resource_group_name.Substring(0, $resource_group_name.IndexOf("-"))
$akv = "akv-" + $base_name + "-eastus"

$defaultHttpPort = 80
$defaultHttpsPort = 443

if ($pat.Length -gt 0) {
  #handle if a PAT was passed and use that in the url
  $newprefix = "https://$pat@"
  $gitpath = $gitpath -replace "https://", $newprefix  
}
#####################################################################################################
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
Set-ExecutionPolicy Bypass -Scope Process -Force

New-Item -Path $logsfolder -ItemType directory -Force
function logmessage() {
  $logmessage = $args[0]    
  $MessageTime = Get-Date -Format "[MM/dd/yyyy HH:mm:ss]"

  $output = "$MessageTime - $logmessage"
  Add-Content -Path $logoutput -Value $output
}

logmessage "Starting BE Setup at:$StartTime"
logmessage "Disabling Windows Firewalls started"
New-NetFirewallRule -DisplayName 'Matchmaker-IB-80' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80
New-NetFirewallRule -DisplayName 'Matchmaker-IB-9999' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 9999
New-NetFirewallRule -DisplayName 'Matchmaker-IB-8888' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8888
New-NetFirewallRule -DisplayName 'Matchmaker-IB-8889' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8889
New-NetFirewallRule -DisplayName 'Matchmaker-IB-8890' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8890
New-NetFirewallRule -DisplayName 'Matchmaker-IB-8891' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8891
New-NetFirewallRule -DisplayName 'Matchmaker-IB-19302' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 19302
New-NetFirewallRule -DisplayName 'Matchmaker-IB-19303' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 19303
New-NetFirewallRule -DisplayName 'Matchmaker-IB-443' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 443

New-NetFirewallRule -DisplayName 'Matchmaker-OB-80' -Direction Outbound -Action Allow -Protocol TCP -LocalPort 80
New-NetFirewallRule -DisplayName 'Matchmaker-OB-9999' -Direction Outbound -Action Allow -Protocol TCP -LocalPort 9999
New-NetFirewallRule -DisplayName 'Matchmaker-OB-19302' -Direction Outbound -Action Allow -Protocol TCP -LocalPort 19302
New-NetFirewallRule -DisplayName 'Matchmaker-OB-19303' -Direction Outbound -Action Allow -Protocol TCP -LocalPort 19303
New-NetFirewallRule -DisplayName 'Matchmaker-OB-443' -Direction Outbound -Action Allow -Protocol TCP -LocalPort 443

logmessage "Disabling Windows Firewalls complete"

#git and git-lfs is on the image already
[reflection.assembly]::LoadWithPartialName("System.DirectoryServices.AccountManagement")
$whoami = [System.DirectoryServices.AccountManagement.UserPrincipal]::Current
logmessage "Current Context: $whoami"

logmessage "Creating: $folder"
New-Item -Path $folder -ItemType directory

logmessage "Cloning code process from Git Start"
if ( (Get-ChildItem $folderNoTrail | Measure-Object).Count -eq 0) {
  try {
    logmessage "Set Path to: $folder"
    Set-Location -Path $folder 

    logmessage "Git LFS Install"
    git lfs install
    Start-Sleep 10

    logmessage "Git Clone Start"
    git clone --depth 1 $gitpath $folderNoTrail --q
    logmessage "Git Clone Complete"

    logmessage "Git cloning process Complete"
  }
  catch {
    logmessage $_.Exception.Message
    break
  }
  finally {
    $error.clear()
  }
} 
else { 
  logmessage "Unreal Folder was not Empty. ABORTING."
  break
}

logmessage "Start DirectX Installation"
choco upgrade directx -s c:\\choco-packages\\directx -y --no-progress
logmessage "Completed DirectX Installation"

logmessage "Starting a Choco Upgrade All"
choco upgrade all -y --no-progress
logmessage "Completed the Choco Upgrade All"

#Add FPS to Engine.ini if FPS is set to > -1
if ($fps -gt -1) {
  logmessage "Start - Adding FPS config to Engine.ini"
  
  try {
    if (-not (Test-Path -LiteralPath $engineIniFilepath)) {
      logmessage "Cannot find Engine.ini folder - creating it and adding Engine.ini"
      New-Item -Path $engineIniFilepath -ItemType directory
      New-Item -Path ($engineIniFilepath+"\Engine.ini") -ItemType File
    }
    else {
      logmessage "Adding FPS config to Engine.ini"

      Add-Content -Path $engineIniFilepath -Value ""
      Add-Content -Path $engineIniFilepath -Value "[/Script/Engine.Engine]"
      Add-Content -Path $engineIniFilepath -Value "bUseFixedFrameRate=True"
      Add-Content -Path $engineIniFilepath -Value ("FixedFrameRate=" + $fps + ".000000")
    }
    logmessage "Finish - Adding FPS config complete"
  }
  catch {
    logmessage $_.Exception.Message
  }
  finally {
    $error.clear()
  }
}

logmessage "Starting Loop"
#############################################
#Loops through all the instances of the SS we want, and duplciate the directory and setup the config/startup process
for ($instanceNum = 1; $instanceNum -le $instancesPerNode; $instanceNum++) {
  try {
    $SSFolder = $vmServiceFolder
       
    #if we are at more than one instance in the loop we need to duplicate the SS dir
    if ($instanceNum -gt 1) {
      $taskName = "StartVMSS" + $instanceNum
      $SSFolder = $vmWebServicesFolder + "SignallingWebServer" + $instanceNum

      #duplicate vmServiceFolder directory
      $newSSFolder = $vmWebServicesFolder + "SignallingWebServer" + $instanceNum
      $sourceFolder = $vmServiceFolder + "*"
      Copy-Item -Path $sourceFolder -Destination $newSSFolder -Recurse
    }

    try {
      Set-Location -Path $SSFolder 
    }
    catch {
      logmessage $_.Exception.Message
      break
    }
    finally {
      $error.clear()
    }

    logmessage "Writing paramters from extension: $SSFolder"

    $vmssConfigJson = (Get-Content  "config.json" -Raw) | ConvertFrom-Json
    logmessage "current config : $vmssConfigJson"

    $vmssConfigJson.resourceGroup = $resource_group_name
    $vmssConfigJson.subscriptionId = $subscription_id
    $vmssConfigJson.virtualMachineScaleSet = $vmss_name
    $vmssConfigJson.appInsightsInstrumentationKey = $application_insights_key
    $vmssConfigJson.MatchmakerAddress = $mm_lb_fqdn
    $vmssConfigJson.PublicIp = $thispublicip
    $vmssConfigJson.HttpPort = ($defaultHttpPort + ($instanceNum - 1))
    $vmssConfigJson.HttpsPort = ($defaultHttpsPort + ($instanceNum - 1))
    $vmssConfigJson.StreamerPort = ($streamingPort + ($instanceNum - 1))
    $vmssConfigJson.unrealAppName = $pixel_stream_application_name
    $vmssConfigJson.region = $deploymentLocation

    $vmssConfigJson | ConvertTo-Json | set-content "config.json"
    $vmssConfigJson = (Get-Content  "config.json" -Raw) | ConvertFrom-Json
    logmessage $vmssConfigJson

    logmessage "Writing parameters from extension complete. Updated config : $vmssConfigJson"
  }
  catch {
    logmessage "Exception: " + $_.Exception
  }
  finally {
    $error.clear()    
  }

  logmessage "Creating a job schedule "

  $trigger = New-JobTrigger -AtStartup -RandomDelay 00:00:10
  try {
    $User = "NT AUTHORITY\SYSTEM"
    $PS = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-executionpolicy bypass -noprofile -file $executionfilepath $instanceNum $streamingPort $resolutionWidth $resolutionHeight ""$pixel_stream_application_name"""
    Register-ScheduledTask -Trigger $trigger -User $User -TaskName $taskName -Action $PS -RunLevel Highest -AsJob -Force
  }
  catch {
    logmessage "Exception: " + $_.Exception
  }
  finally {
    $error.clear()    
  }

  logmessage "Creating a job schedule complete"

  logmessage "Az Login"
  az login --identity
  logmessage "Az Set Subscription"
  az account set --subscription $subscription_id

  [reflection.assembly]::LoadWithPartialName("System.DirectoryServices.AccountManagement")
  $whoami = [System.DirectoryServices.AccountManagement.UserPrincipal]::Current
  logmessage "Current Context: $whoami"
  
  ### adding process to download certs
  logmessage "Starting download of certs"
  
  #create the certificates folder
  $vmCertFolder = $SSFolder + "\certificates"

  if (-not (Test-Path -LiteralPath $vmCertFolder)) {
    $fso = new-object -ComObject scripting.filesystemobject
    $fso.CreateFolder($vmCertFolder)
  }
  else {
    logmessage "Path already exists: $vmCertFolder"
  }

  #set the path to the certificates folder
  Set-Location -Path $vmCertFolder 

  try {
    #check to see if the key exists?
    $akvcert = (az keyvault certificate list-versions --vault-name $akv -n "unrealpixelstreaming" --query "[].{Name:name}" -o table).Count

    #download the cert to the folder (1 means there is no cert, 3 or more indicates the specific cert was found)
    if ($akvcert -gt 1) {
      try {
        az keyvault certificate download --vault-name $akv -n "unrealpixelstreaming" -f client-cert.pem
        logmessage "Certificates Download Succeeded"
      }
      catch {
        logmessage "Certificates Download Failed"
      }
    }
    else {
      logmessage "Certificate does not exist"
    }

    logmessage "Completed download of certs"
    ### end process to download certs
  }
  catch {
    logmessage "Exception: " + $_.Exception
  }
  finally {
    $error.clear()    
  }
  logmessage "Starting the VMSS Process "

  #invoke the script to start it this time
  Set-ExecutionPolicy Bypass -Scope CurrentUser -Force

  #Add param for which version of SS folder we are at
  #Invoke-Expression "$executionfilepath $instanceNum $streamingPort $resolutionWidth $resolutionHeight $pixel_stream_application_name"
  Start-ScheduledTask -TaskName $taskName -AsJob
}

$EndTime = Get-Date
logmessage "Completed at:$EndTime"