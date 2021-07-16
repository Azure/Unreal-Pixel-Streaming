:: Copyright Epic Games, Inc. All Rights Reserved.
@echo off

pushd %~dp0

call setup.bat

title Cirrus

::Run node server

Powershell.exe -executionpolicy unrestricted -File Start_Azure_WithTURN_SignallingServer.ps1

popd
pause
