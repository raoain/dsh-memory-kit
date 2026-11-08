# show-standby.ps1 — 全屏显示一张图（直播开场用）
# 用法： powershell -File show-standby.ps1 -Path "F:\...\live-standby.png"
param([Parameter(Mandatory=$true)][string]$Path)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
. (Join-Path $PSScriptRoot '_root.ps1')

$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.WindowState = 'Normal'
$form.StartPosition = 'Manual'
$form.Bounds = New-Object System.Drawing.Rectangle $b.X, $b.Y, $b.Width, $b.Height
$form.TopMost = $true
$form.BackColor = [System.Drawing.Color]::Black

$img = [System.Drawing.Image]::FromFile($Path)
$pic = New-Object System.Windows.Forms.PictureBox
$pic.Dock = 'Fill'
$pic.SizeMode = 'Zoom'
$pic.Image = $img
$form.Controls.Add($pic)

# 按 Esc 关闭
$form.KeyPreview = $true
$form.Add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $form.Close() } })

[void]$form.ShowDialog()
$img.Dispose()
