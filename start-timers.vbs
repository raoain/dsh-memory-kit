' start-timers.vbs -- start the repeating organ loops, each one guaranteed single.
'
' Why a vbs: measured on this box (2026-11-08), processes started with Start-Process or
' Invoke-CimMethod do not survive the calling session -- both died within seconds. wscript
' is a separate host, so what it starts does not belong to the calling shell.
'
' Why core/loop.mjs: the single-instance guard used to live in the caller (coo-watchdog.cmd,
' then this vbs). Both could be bypassed: call the vbs directly, pass /force, or hand-roll
' `powershell -Command while(...)`. The user's rule (2026-11-08): this must be stable and
' singular BY ITSELF, not because someone remembers the right entry point.
' Every loop now asks "am I already running?" via a lock file holding its own PID, inside the
' loop, so it holds no matter who starts it or how many times.
'
' Why no nested quotes: the sweep step used to be three `& node ...` calls glued together
' four quote levels deep, and it silently failed to start while the other loops came up.
' Multi-step rounds now live in one script (core/sweep.mjs).
'
' usage: wscript.exe start-timers.vbs
' safe to call any number of times; starting an already-running loop adds nothing.

Set sh = CreateObject("WScript.Shell")
base = "F:\Tools\coo-day1"
n = "node"

' one-shot migration: stop any pre-lock loops still running (they would not check the lock)
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""Get-CimInstance Win32_Process -Filter """"Name='powershell.exe'"""" | Where-Object { $_.CommandLine -like '*coo-day1*while*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }""", 0, False

sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""& " & n & " '" & base & "\core\loop.mjs' --name watchdog --every 300 --cell 4 -- powershell -NoProfile -ExecutionPolicy Bypass -File '" & base & "\watchdog.ps1'""", 0, False
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""& " & n & " '" & base & "\core\loop.mjs' --name reflex --every 3 --cell 7 -- " & n & " '" & base & "\core\reflex.mjs'""", 0, False
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""& " & n & " '" & base & "\core\loop.mjs' --name drift --every 60 --cell 15 -- " & n & " '" & base & "\core\drift.mjs'""", 0, False
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""& " & n & " '" & base & "\core\loop.mjs' --name sweep --every 1800 --cell 18 -- " & n & " '" & base & "\core\sweep.mjs'""", 0, False
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""& " & n & " '" & base & "\core\loop.mjs' --name backup --every 86400 --cell 5 -- powershell -NoProfile -ExecutionPolicy Bypass -File '" & base & "\backup.ps1'""", 0, False
' 2026-11-10: 每个有 every 的器官自己成环（自己的节律就是标准），不再由 sweep 统一带跑
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""& " & n & " '" & base & "\core\loop.mjs' --name self --every 1800 --cell 8 -- " & n & " '" & base & "\core\self.mjs'""", 0, False
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""& " & n & " '" & base & "\core\loop.mjs' --name pulse --every 1800 --cell 9 -- " & n & " '" & base & "\core\pulse.mjs'""", 0, False
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""& " & n & " '" & base & "\core\loop.mjs' --name align --every 86400 --cell 16 -- " & n & " '" & base & "\core\align.mjs'""", 0, False
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""& " & n & " '" & base & "\core\loop.mjs' --name immunity --every 86400 --cell 17 -- " & n & " '" & base & "\core\immunity.mjs'""", 0, False
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""& " & n & " '" & base & "\core\loop.mjs' --name heart --every 60 --cell 18 -- " & n & " '" & base & "\core\consolidate.mjs' --heart""", 0, False
