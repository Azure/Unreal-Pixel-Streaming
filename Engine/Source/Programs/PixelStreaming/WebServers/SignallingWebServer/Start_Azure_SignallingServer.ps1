# Copyright 1998-2018 Epic Games, Inc. All Rights Reserved.

# To avoid customers seeing an IP in the browser, set VMFQDN env variable with the VM DNS
if ($env:VMFQDN) {
    $PublicIp = $env:VMFQDN
}
else {
	# Hit a common url to grab the VM's public URL (non-platform specific)
    $PublicIp = (Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing).Content
}

Write-Output "Public IP: $PublicIp"

# Uses a common STUN server from Google for testing, but recommended to host your own
$peerConnectionOptions = "{ \""iceServers\"": [{\""urls\"": [\""stun:stun.l.google.com:19302\""]}] }"

$ProcessExe = "node.exe"

# defaults to UE 4.27 path where cirrus is 2 directories higher in the path tree
$cirrusPath = "../../cirrus.js"

$exists = Test-Path -Path $cirrusPath
if(!$exists){
    # fall back to pathing used for 4.26 and earlier
    $cirrusPath = "cirrus.js"
}

$Arguments = @($cirrusPath, "--peerConnectionOptions=""$peerConnectionOptions""", "--publicIp=$PublicIp")

# Add arguments passed to script to Arguments for executable
$Arguments += $args

Write-Output "Running: $ProcessExe $Arguments"
Start-Process -FilePath $ProcessExe -ArgumentList $Arguments -Wait -NoNewWindow
