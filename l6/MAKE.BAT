@echo off


del /Q BUILD
mkdir BUILD


tasm  /z /m2  MAIN.ASM , BUILD
tlink  /x /l /v /3 /Tde  build\MAIN.OBJ , BUILD\MAIN.EXE

if 0 bcc -ml -IC:\BORLANDC\INCLUDE -LC:BORlANDC\LIB main.c
