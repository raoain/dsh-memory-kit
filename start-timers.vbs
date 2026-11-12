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
' 2026-11-12: no PowerShell in between. Huorong flagged every `powershell -WindowStyle Hidden
' -Command "& node ..."` as rp_name_execcreate_powershell_hidden (risk_prot_v6). wscript can
' start node hidden by itself (Run with window style 0), so the middle interpreter is gone.
' The one-shot pre-lock migration (a hidden PowerShell Stop-Process sweep) is removed too --
' the locks have been in core/loop.mjs since 2026-11-08, so that migration can never match.
'
' usage: wscript.exe start-timers.vbs
' safe to call any number of times; starting an already-running loop adds nothing.

Set sh = CreateObject("WScript.Shell")
base = "F:\Tools\coo-day1"
n = "node"
q = """"
loopmjs = base & "\core\loop.mjs"

' tick commands that are PowerShell scripts stay as `powershell -File` (they *are* ps1);
' tick commands that are node scripts are started directly.
sh.Run q & n & q & " " & q & loopmjs & q & " --name watchdog --every 300 --cell 4 -- powershell -NoProfile -ExecutionPolicy Bypass -File " & q & base & "\watchdog.ps1" & q, 0, False
sh.Run q & n & q & " " & q & loopmjs & q & " --name reflex --every 3 --cell 7 -- " & n & " " & q & base & "\core\reflex.mjs" & q, 0, False
sh.Run q & n & q & " " & q & loopmjs & q & " --name drift --every 60 --cell 15 -- " & n & " " & q & base & "\core\drift.mjs" & q, 0, False
sh.Run q & n & q & " " & q & loopmjs & q & " --name sweep --every 1800 --cell 18 -- " & n & " " & q & base & "\core\sweep.mjs" & q, 0, False
sh.Run q & n & q & " " & q & loopmjs & q & " --name backup --every 86400 --cell 5 -- powershell -NoProfile -ExecutionPolicy Bypass -File " & q & base & "\backup.ps1" & q, 0, False
' 2026-11-10: every organ with an `every` runs its own loop (its own rhythm is the standard),
' no longer all carried by sweep.
sh.Run q & n & q & " " & q & loopmjs & q & " --name self --every 1800 --cell 8 -- " & n & " " & q & base & "\core\self.mjs" & q, 0, False
sh.Run q & n & q & " " & q & loopmjs & q & " --name pulse --every 1800 --cell 9 -- " & n & " " & q & base & "\core\pulse.mjs" & q, 0, False
sh.Run q & n & q & " " & q & loopmjs & q & " --name align --every 86400 --cell 16 -- " & n & " " & q & base & "\core\align.mjs" & q, 0, False
sh.Run q & n & q & " " & q & loopmjs & q & " --name immunity --every 86400 --cell 17 -- " & n & " " & q & base & "\core\immunity.mjs" & q, 0, False
sh.Run q & n & q & " " & q & loopmjs & q & " --name heart --every 60 --cell 18 -- " & n & " " & q & base & "\core\consolidate.mjs" & q & " --heart", 0, False
