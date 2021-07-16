# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.

[CmdletBinding()]
Param (
    [Parameter(Position=0, Mandatory=$false, HelpMessage = "Current instance number for a Signlaing Server folder, default 1")]
    [int] $instanceNum = 1,
    [Parameter(Position=1, Mandatory=$false, HelpMessage = "The streaming port start for multiple instances, default 8888")]
    [int] $streamingPort = 8888,
    [Parameter(Position=2, Mandatory=$false, HelpMessage = "The resolution width of the 3D app, default 1920")]
    [int] $resolutionWidth = 1920,
    [Parameter(Position=3, Mandatory=$false, HelpMessage = "The resolution height of the 3D app, default 1080")]
    [int] $resolutionHeight = 1080,
    [Parameter(Position=4, Mandatory=$false, HelpMessage = "The name of the 3D app, default PixelStreamingDemo")]
    [string] $pixel_stream_application_name = "PixelStreamingDemo"
)

#####################################################################################################
#base variables
#####################################################################################################
$PixelStreamerFolder = "C:\Unreal\"
$PixelStreamerExecFile = $PixelStreamerFolder + $pixel_stream_application_name + ".exe"
$vmServiceFolder = "C:\Unreal\Engine\Source\Programs\PixelStreaming\WebServers\SignallingWebServer"
if($instanceNum -gt 1) {
   $vmServiceFolder = $vmServiceFolder + $instanceNum
}

$logsbasefolder = "C:\gaming"
$logsfolder = "c:\gaming\logs"
$logoutput = $logsfolder + '\ue4-startVMSS-output' + (get-date).ToString('MMddyyhhmmss') + '.txt'
$stdout = $logsfolder + '\ue4-signalservice-stdout' + (get-date).ToString('MMddyyhhmmss') + '.txt'
$stderr = $logsfolder + '\ue4-signalservice-stderr' + (get-date).ToString('MMddyyhhmmss') + '.txt'

#pixelstreamer arguments
$port = $streamingPort + ($instanceNum-1)
$audioMixerArg = "-AudioMixer"
$streamingIPArg = "-PixelStreamingIP=localhost"
$streamingPortArg = "-PixelStreamingPort=" + $port
$renderOffScreenArg = "-RenderOffScreen"
$resolutionWidthArg = "-ResX=" + $resolutionWidth
$resolutionHeightArg = "-ResY=" + $resolutionHeight

#Used for https and certs usage for a custom domain versus .cloudapp.azure.com (this replaces that part)
$customDomainName = ".unrealpixelstreaming.com/"
#####################################################################################################

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope LocalMachine -Force

try {
   New-EventLog -Source PixelStreamer -LogName Application -MessageResourceFile $PixelStreamerExecFile -CategoryResourceFile $PixelStreamerExecFile
}
catch {
   #do nothing, this is ok.
}
finally {
   $error.clear()    
}
 
#create a log folder if it does not exist
if (-not (Test-Path -LiteralPath $logsfolder)) {
   Write-Output "creating directory :" + $logsfolder
   $fso = new-object -ComObject scripting.filesystemobject
   if (-not (Test-Path -LiteralPath $logsbasefolder)) {
      $fso.CreateFolder($logsbasefolder)
      Write-Output "created gaming folder"
   }
   $fso.CreateFolder($logsfolder)
   Write-EventLog -LogName "Application" -Source "PixelStreamer" -EventID 3100 -EntryType Information -Message "Created logs folder"
}
else {
   Write-Output "Path already exists :" + $logsfolder
   Write-EventLog -LogName "Application" -Source "PixelStreamer" -EventID 3101 -EntryType Information -Message "log folder alredy exists"
}

Set-Alias -Name git -Value "$Env:ProgramFiles\Git\bin\git.exe" -Scope Global
Set-Alias -Name node -Value "$Env:ProgramFiles\nodejs\node.exe" -Scope Global
Set-Alias -Name npm -Value "$Env:ProgramFiles\nodejs\node_modules\npm" -Scope Global

$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False


Set-Content -Path $logoutput -Value "startingVMSS"

if (-not (Test-Path -LiteralPath $PixelStreamerFolder)) {
   $logMessage = "PixelStreamer folder :" + $PixelStreamerFolder + " doesn't exist" 
   Write-EventLog -LogName "Application" -Source "PixelStreamer" -EventID 3102 -EntryType Error -Message $logMessage
   Add-Content -Path $logoutput -Value $logMessage
}

Set-Location -Path $PixelStreamerFolder 
$logMessage = "current folder :" + $PixelStreamerFolder 
Add-Content -Path $logoutput -Value $logMessage

if (-not (Test-Path -LiteralPath $PixelStreamerExecFile)) {
   $logMessage = "PixelStreamer Exec file :" + $PixelStreamerExecFile + " doesn't exist" 
   Add-Content -Path $logoutput -Value $logMessage
}

try {
& $PixelStreamerExecFile $audioMixerArg $streamingIPArg $streamingPortArg $renderOffScreenArg -WinX=0 -WinY=0 $resolutionWidthArg $resolutionHeightArg -Windowed -ForceRes
$logMessage = "started :" + $PixelStreamerExecFile 
}
catch {
   $logMessage = "Exception in starting Pixel Streamer : " + $_.Exception.Message
   Write-Output $logmessage
 }
 finally {
   $error.clear()
 }

Add-Content -Path $logoutput -Value $logMessage

if (-not (Test-Path -LiteralPath $vmServiceFolder)) {
   $logMessage = "SignalService folder :" + $vmServiceFolder + " doesn't exist" 
   Write-EventLog -LogName "Application" -Source "PixelStreamer" -EventID 3104 -EntryType Error -Message $logMessage
   Add-Content -Path $logoutput -Value $logMessage
}

Set-Location -Path $vmServiceFolder 
$logMessage = "current folder :" + $vmServiceFolder
Add-Content -Path $logoutput -Value $logMessage

$vmssConfigJson = (Get-Content  "config.json" -Raw) | ConvertFrom-Json
Write-Output $vmssConfigJson
$logMessage = "Config.json :" + $vmssConfigJson
Add-Content -Path $logoutput -Value $logMessage

try {
   $resourceGroup = $vmssConfigJson.resourceGroup
   $vmssName = $vmssConfigJson.virtualMachineScaleSet
   $akv = "akv-" + $vmssName.substring(0, 5) + "-eastus"
    
   $thispublicip = (Invoke-WebRequest -uri "http://ifconfig.me/ip" -UseBasicParsing).Content
   $logMessage = "Public IP Address for lookup of FQDN: " + $thispublicip;
   Add-Content -Path $logoutput -Value $logMessage

   az login --identity
   $json = az vmss list-instance-public-ips -g $resourceGroup -n $vmssName | ConvertFrom-Json
   $vmss = $json | where { $_.ipAddress -eq $thispublicip }

   # TODO: add the check if the cert exists
   #if true change the url
   #else
   $fqdn = $vmss.dnsSettings.fqdn

   $akvcert = (az keyvault certificate list-versions --vault-name $akv -n "unrealpixelstreaming" --query "[].{Name:name}" -o table).Count

   #download the cert to the folder (1 means there is no cert, 3 or more indicates the specific cert was found)
   if ($akvcert -gt 1) 
   {
      logMessage = "The fqdn :"+$fqdn
      Add-Content -Path $logoutput -Value $logMessage

      $fqdn = $fqdn.replace(".cloudapp.azure.com/","")  
      $fqdn = $fqdn.replace(".","-")  + $customDomainName
      logMessage = "The new fqdn :"+$fqdn
      Add-Content -Path $logoutput -Value $logMessage
   }
   
   $env:VMFQDN = $fqdn;
   $logMessage = "Success in getting FQDN: " + $fqdn;

   Add-Content -Path $logoutput -Value $logMessage
}
catch {
   Write-Host "Error getting FQDN: " + $_
   $logMessage = "Error getting FQDN for VM: " + $_
   Add-Content -Path $logoutput -Value $logMessage
}

start-process "cmd.exe" "/c .\runAzure.bat"  -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorVariable ProcessError

if ($ProcessError) {
   $logMessage = "Error in starting Signal Service"
   Write-EventLog -LogName "Application" -Source "PixelStreamer" -EventID 3105 -EntryType Error -Message $logMessage
}
else {
   $logMessage = "Started vmss sucessfully runAzure.bat" 
   Write-EventLog -LogName "Application" -Source "PixelStreamer" -EventID 3106 -EntryType Information -Message $logMessage
}

Add-Content -Path $logoutput -Value $logMessage
