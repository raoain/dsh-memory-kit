' start-timers.vbs -- launch the timer loops fully detached, guarded.
'
' Why a vbs: measured on this box (2026-11-08), processes started with Start-Process or
' Invoke-CimMethod do not survive the calling session -- both died within seconds. wscript
' is a separate host, so what it starts does not belong to the calling shell.
'
' 2026-11-08 second fix: the duplicate-driver guard used to live only in coo-watchdog.cmd,
' so calling this vbs directly (which is what a person or a script does when restoring a
' stopped heartbeat) bypassed the guard and started a second set -- 7 processes instead of
' 4, three times in one afternoon.
' The guard now lives HERE, at the place that actually starts processes. The question it asks
' is answered by the bus, not by a marker file and not by matching its own command line:
'   heartbeat age < 90 s  -> a set is already running, start nothing.
'
' usage: wscript.exe start-timers.vbs      (safe to call any number of times)
'        wscript.exe start-timers.vbs /force   (start anyway, e.g. after killing a hung set)

Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = "F:\Tools\coo-day1"

force = False
For Each a In WScript.Arguments
    If LCase(a) = "/force" Then force = True
Next

' --- guard: ask the bus how long ago the last heartbeat landed -----------------------
Dim age
age = 9999
On Error Resume Next
Set exec = sh.Exec("node """ & base & "\core\timers-alive.mjs""")
out = exec.StdOut.ReadAll()
On Error GoTo 0
If Len(Trim(out)) > 0 Then
    If IsNumeric(Trim(out)) Then age = CLng(Trim(out))
End If

If (Not force) And (age < 90) Then
    ' a set is already beating; starting another would only halve the interval
    WScript.Quit 0
End If

sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""while ($true) { & '" & base & "\watchdog.ps1' | Out-Null; Start-Sleep -Seconds 300 }""", 0, False
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""while ($true) { & node '" & base & "\core\reflex.mjs' | Out-Null; Start-Sleep -Seconds 3 }""", 0, False
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""while ($true) { & node '" & base & "\core\drift.mjs' | Out-Null; Start-Sleep -Seconds 60 }""", 0, False
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""while ($true) { & node '" & base & "\core\bus-rotate.mjs' | Out-Null; & node '" & base & "\core\pulse.mjs' | Out-Null; & node '" & base & "\core\self.mjs' | Out-Null; Start-Sleep -Seconds 1800 }""", 0, False
