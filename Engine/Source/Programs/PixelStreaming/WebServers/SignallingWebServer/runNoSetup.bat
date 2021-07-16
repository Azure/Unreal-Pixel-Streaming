:: Copyright Epic Games, Inc. All Rights Reserved.
@echo off

pushd %~dp0

title Cirrus

::Run node server
::If running with frontend web server and accessing outside of localhost pass in --publicIp=<ip_of_machine>
node cirrus %*

popd
pause
