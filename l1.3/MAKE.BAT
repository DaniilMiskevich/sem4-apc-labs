@echo off

set com=com
set exe=exe


set MAIN=main
set BUILD=build
set BUILD_TYPE=%exe%


del /Q %BUILD%
mkdir %BUILD%


tasm  /z  %MAIN%.asm , %BUILD%

if %BUILD_TYPE%==%com% set BUILD_FLAG=/Tdc
if %BUILD_TYPE%==%exe% set BUILD_FLAG=/Tde
tlink  /x /l /v  %BUILD_FLAG%  %BUILD%\%MAIN%.obj , %BUILD%\%MAIN%.%BUILD_TYPE%

