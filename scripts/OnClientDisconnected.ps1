# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.

# This is optionally used by the Signaling Server to reset the UE4 exe when a user disconnects
[CmdletBinding()]
Param (
    [Parameter(Position=0, Mandatory=$true, HelpMessage = "3D Application name")]
    [string] $unrealAppName,
    [Parameter(Position=1, Mandatory=$true, HelpMessage = "The streaming port of the 3D App name we're trying to restart")]
    [int] $streamingPort
)

try {
    #Two UE4 processes are spun up so we close both of them here, and only restart the one that is the original parent .exe
    $processes = Get-Process ($unrealAppName + "*")
    write-host "Start - Unreal processes: " $processes.Count
    $finalPath = ""
    $finalArgs = ""
    if($processes.Count -gt 0)
    {
        foreach($process in $processes)
        {
            $path = $process.Path
            $procID = $process.Id
            $cmdline = (Get-WMIObject Win32_Process -Filter "Handle=$procID").CommandLine

            if($cmdline.Contains("-PixelStreamingPort="+$streamingPort))
            {
                if($cmdline -Match (" " + $unrealAppName + " "))
                {
                    $processToKill = $process
                }

                #Only grab the original parent pixel streaming unreal app, not the child one, so we can restart it
                if($cmdline -notmatch (" " + $unrealAppName + " "))
                {
                    $finalPath = $path
                    $finalArgs = $cmdline.substring($cmdline.IndexOf("-AudioMixer"))
                }
            }
        }
        
        if($processToKill -ne $null)
        {
            write-host "Shutting down UE4 app: $processToKill.Path"
    
            try 
            {
                $processToKill | Stop-Process -Force
            }
            catch 
            {
                Write-Host "ERROR:::An error occurred when stopping process: "
                Write-Host $_

                try 
                {
                    Start-Sleep -s 1
                    
                    $processToKill.Kill()
                    $processToKill.WaitForExit(3000)
                }
                catch 
                {
                    Write-Host "ERROR:::An error occurred when killing process: "
                    Write-Host $_
                }
            }
            finally
            {
                Write-Host "Process killed"
            }

            Start-Sleep -s 1
        }        
    }
    else
    {
        Write-Host $unrealAppName " not running when trying to restart"
    }

    try 
    {
        Start-Sleep -s 5

        $startProcess = $false
        $newProcesses = Get-Process ($unrealAppName + "*")
        Write-Host "After kill - Unreal processes: " $newProcesses.Count
        if($newProcesses.Count -le 0)
        {
            $startProcess = $true
        }
        else
        {
            $startProcess = $true
            foreach($process in $newProcesses)
            {
                $procID = $process.Id
                $cmdline = (Get-WMIObject Win32_Process -Filter "Handle=$procID").CommandLine

                if($cmdline.Contains("-PixelStreamingPort="+$streamingPort))
                {
                    $startProcess = $false
                    break
                }
            }
        }

        if($startProcess -eq $true)
        {
            write-host "Starting Process - " $finalPath $finalArgs
            #Start the final application if not already restarted
            Start-Process -FilePath $finalPath -ArgumentList $finalArgs
        }

        Start-Sleep -s 5
        $newProcesses = Get-Process ($unrealAppName + "*")
        Write-Host "After restart - Unreal processes: " $newProcesses.Count

    }
    catch 
    {
        Write-Host "ERROR:::An error occurred when starting the process: " $finalPath $finalArgs
        Write-Host $_
    }
}
catch 
{
  Write-Host "ERROR:::An error occurred:"
  Write-Host $_
  Write-Host $_.ScriptStackTrace
}