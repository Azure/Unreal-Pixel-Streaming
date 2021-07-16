# Copyright (c) Microsoft Corporation.
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
$logoutput = $logsfolder + '\ue4-setupMM-output-' + (get-date).ToString('MMddyyhhmmss') + '.txt'
$folder = "c:\Unreal\"

$folderNoTrail = $folder
if ($folderNoTrail.EndsWith("\")) {
  $l = $folderNoTrail.Length - 1
  $folderNoTrail = $folderNoTrail.Substring(0, $l)
}

$mmServiceFolder = "$folderNoTrail\Engine\Source\Programs\PixelStreaming\WebServers\Matchmaker"
$mmCertFolder = $mmServiceFolder + "\Certificates"
$executionfilepath = "$folderNoTrail\scripts\startMMS.ps1"
$deploymentLocation = $resource_group_name.Split('-')[1]

$base_name = $resource_group_name.Substring(0, $resource_group_name.IndexOf("-"))
$akv = "akv-" + $base_name + "-eastus"

#handle if a Personal Access Token is being passed
#$B64Pat = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$pat"))
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
New-NetFirewallRule -DisplayName 'Matchmaker-IB-90' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 90
New-NetFirewallRule -DisplayName 'Matchmaker-IB-9999' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 9999
New-NetFirewallRule -DisplayName 'Matchmaker-IB-443' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 443

New-NetFirewallRule -DisplayName 'Matchmaker-OB-80' -Direction Outbound -Action Allow -Protocol TCP -LocalPort 80
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

#put a check here if the clone actually occurred, if not break
try {
  Set-Location -Path $mmServiceFolder 
}
catch {
  logmessage $_.Exception.Message
  break
}
finally {
  $error.clear()
}

logmessage "Current folder: $mmServiceFolder"

logmessage $subscription_id
logmessage $resource_group_name
logmessage $vmss_name
logmessage $application_insights_key

$mmConfigJson = (Get-Content  "config.json" -Raw) | ConvertFrom-Json
logmessage "Config json before update : $mmConfigJson"

$mmConfigJson.resourceGroup = $resource_group_name
$mmConfigJson.subscriptionId = $subscription_id
$mmConfigJson.virtualMachineScaleSet = $vmss_name
$mmConfigJson.appInsightsInstrumentationKey = $application_insights_key
$mmConfigJson.region = $deploymentLocation

$mmConfigJson | ConvertTo-Json | set-content "config.json"

# Reading again to confirm the update
$mmConfigJson = (Get-Content  "config.json" -Raw) | ConvertFrom-Json
logmessage "Writing parameters from extension complete." 
logmessage "Updated config : $mmConfigJson"

#create the certificates folder
$mmCertFolder = $mmServiceFolder + "\certificates"

if (-not (Test-Path -LiteralPath $mmCertFolder)) {
  $fso = new-object -ComObject scripting.filesystemobject
  $fso.CreateFolder($mmCertFolder)
}
else {
  logmessage "Path already exists: $mmCertFolder"
}

#set the path to the certificates folder
Set-Location -Path $mmCertFolder 

logmessage "Starting Certificate Process"

logmessage "Az Login"
az login --identity
logmessage "Az Set Subscription"
az account set --subscription $subscription_id
logmessage "AKV: $akv"

[reflection.assembly]::LoadWithPartialName("System.DirectoryServices.AccountManagement")
$whoami = [System.DirectoryServices.AccountManagement.UserPrincipal]::Current
logmessage "Current Context: $whoami"

#check to see if the key exists?
$akvcert = (az keyvault certificate list-versions --vault-name $akv -n "unrealpixelstreaming" --query "[].{Name:name}" -o table).Count

#download the cert to the folder (1 means there is no cert, 3 or more indicates the specific cert was found)
if ($akvcert -gt 1) {
  try {
    logmessage "Starting Downloading of certs"
    ### end process to download certs

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

logmessage "Creating a job schedule "

$trigger = New-JobTrigger -AtStartup -RandomDelay 00:00:10
try {
  $User = "NT AUTHORITY\SYSTEM"
  $PS = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-executionpolicy bypass -noprofile -file $executionfilepath"
  Register-ScheduledTask -Trigger $trigger -User $User -TaskName "StartMMS" -Action $PS -RunLevel Highest -Force 
}
catch {
  logmessage "Exception: " + $_.Exception
}
finally {
  $error.clear()    
}

logmessage "Creating a job schedule complete"
logmessage "Starting the MMS Process "

#invoke the script to start it this time
#Invoke-Expression -Command $executionfilepath
Start-ScheduledTask -TaskName "StartMMS" -AsJob

$EndTime = Get-Date
logmessage "Completed at:$EndTime"