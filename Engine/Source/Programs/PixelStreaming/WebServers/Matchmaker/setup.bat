:: Copyright Epic Games, Inc. All Rights Reserved.
pushd %~dp0

:: MSFT Change: manually installing cors, prior to installing package.json dependencies
:: is a side effect found from using yargs 16.2.0, which is a change from upstream of version 10.1.1.
npm install cors --save
npm install

popd
