@echo off

set MAIN=MAIN


del *.OBJ
del *.EXE


tasm  /z /m2  %MAIN%.ASM
tlink  /x /l /v /3 /Tde  %MAIN%.OBJ , %MAIN%.EXE

if 0 bcc -ml -IC:\BORLANDC\INCLUDE -LC:BORlANDC\LIB main.c
