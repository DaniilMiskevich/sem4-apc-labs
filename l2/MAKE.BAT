@echo off


set MAIN=main


bcc -ml -IC:\BORLANDC\INCLUDE -LC:BORlANDC\LIB %MAIN%.c

