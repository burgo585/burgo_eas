@echo off
set "SRCDIR=c:\Robo Virada de Delta\Automacao_Virada_Delta"
set "TERMDIR=C:\Users\Vini_Burgo\AppData\Roaming\MetaQuotes\Terminal\5A1174AE1007A2760EEEF72EC2A459D5\MQL5\Experts\Automacao_Virada_Delta"
set "METAEDITOR=C:\MetaTrader\metaeditor64.exe"

copy /Y "%SRCDIR%\Robo_Virada_Delta_Pro.mq5" "%TERMDIR%\"
copy /Y "%SRCDIR%\Include\*" "%TERMDIR%\Include\"

"%METAEDITOR%" /compile:"%TERMDIR%\Robo_Virada_Delta_Pro.mq5" /log:"%TERMDIR%\compile.log"

type "%TERMDIR%\compile.log"

copy /Y "%TERMDIR%\Robo_Virada_Delta_Pro.ex5" "%SRCDIR%\"
dir "%SRCDIR%\Robo_Virada_Delta_Pro.ex5"
