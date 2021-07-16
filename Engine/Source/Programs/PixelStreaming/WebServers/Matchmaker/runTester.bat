@echo off

pushd %~dp0

call setup.bat

title Tester

::Run node server
node tester %*

popd
pause