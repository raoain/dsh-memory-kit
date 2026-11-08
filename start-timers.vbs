' start-timers.vbs -- launch the three timer loops fully detached.
'
' Why a vbs: measured on this box (2026-11-08), processes started with Start-Process or
' Invoke-CimMethod do not survive the calling session -- both died within seconds. wscript
' is a separate host, so what it starts does not belong to the calling shell.
'
' usage: wscript.exe start-timers.vbs

Set sh = CreateObject("WScript.Shell")
base = "F:\Tools\coo-day1"

sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""while ($true) { & '" & base & "\watchdog.ps1' | Out-Null; Start-Sleep -Seconds 300 }""", 0, False
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""while ($true) { & node '" & base & "\core\reflex.mjs' | Out-Null; Start-Sleep -Seconds 3 }""", 0, False
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""while ($true) { & node '" & base & "\core\drift.mjs' | Out-Null; Start-Sleep -Seconds 60 }""", 0, False
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""while ($true) { & node '" & base & "\core\bus-rotate.mjs' | Out-Null; & node '" & base & "\core\pulse.mjs' | Out-Null; & node '" & base & "\core\self.mjs' | Out-Null; Start-Sleep -Seconds 1800 }""", 0, False
