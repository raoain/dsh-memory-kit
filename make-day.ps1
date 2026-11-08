# make-day.ps1 — Coo 打工日记 出片流水线
# 用法： .\make-day.ps1 -Spec day3.json -Out day3.mp4
#
# Spec 格式（JSON，UTF-8）：
# {
#   "title": "【Day 3】...",
#   "segments": [
#     { "type": "card",  "big": "8 播放", "small": "发布六小时", "accent": "#5AC8FA",
#       "say": "发布六个小时，八个播放。", "gap": 0.4 },
#     { "type": "image", "path": "F:/x/shot.png",
#       "say": "……", "gap": 0.4 },
#     { "type": "video", "path": "F:/x/clip.mp4", "duration": 12,
#       "say": "……", "gap": 1.0 }
#   ]
# }
#
# 说明：
# - 每段的时长 = 配音时长 + gap；video 段取 max(duration, 配音+gap)
# - 字幕画在画面底部（card/image 段）；video 段不压字幕
# - 配音两种引擎：-TtsEngine edge（默认，微软神经语音，自然）或 -TtsEngine sapi（旧的慧慧，机械）
#   缓存到 build\pipeline\tts\<hash>.wav，同一句不重复生成
param(
    [Parameter(Mandatory=$true)][string]$Spec,
    [string]$Out,
    [string]$Font = 'C:\Windows\Fonts\msyh.ttc',
    [ValidateSet('edge','sapi')][string]$TtsEngine = 'edge',
    [string]$TtsVoice = 'zh-CN-XiaoyiNeural',
    [string]$TtsRate = '+0%',
    [string]$EdgeTts = 'F:\Tools\uv\bin\edge-tts.exe'
)
. (Join-Path $PSScriptRoot '_root.ps1')

$ErrorActionPreference = 'Continue'
$FF = 'F:\Tools\bin\ffmpeg.exe'
if (-not (Test-Path $FF)) { throw "找不到 ffmpeg: $FF" }

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Speech

$specPath = (Resolve-Path $Spec).Path
$work = Join-Path (Split-Path $specPath) 'build\pipeline'
New-Item -ItemType Directory -Force -Path $work, "$work\tts", "$work\cards", "$work\segs" | Out-Null
if (-not $Out) { $Out = Join-Path (Split-Path $specPath) 'out.mp4' }

$cfg = Get-Content $specPath -Raw -Encoding UTF8 | ConvertFrom-Json
$segs = @($cfg.segments)

# ---------- TTS ----------
$fmt = New-Object System.Speech.AudioFormat.SpeechAudioFormatInfo(44100,
    [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
    [System.Speech.AudioFormat.AudioChannel]::Mono)
$syn = New-Object System.Speech.Synthesis.SpeechSynthesizer
try { $syn.SelectVoice('Microsoft Huihui Desktop') } catch { }
$syn.Rate = -1

function Get-Tts([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    # 缓存键包含引擎与音色，换音色不会串用旧缓存
    $key = "$TtsEngine|$TtsVoice|$TtsRate|$text"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($key))).Replace('-','').Substring(0,16)
    $f = Join-Path $work "tts\$hash.wav"

    if (-not (Test-Path $f)) {
        $done = $false
        if ($TtsEngine -eq 'edge' -and (Test-Path $EdgeTts)) {
            $mp3 = Join-Path $work "tts\$hash.mp3"
            try {
                & $EdgeTts --voice $TtsVoice --rate $TtsRate --text $text --write-media $mp3 2>$null | Out-Null
                if ((Test-Path $mp3) -and (Get-Item $mp3).Length -gt 1000) {
                    & $FF -y -loglevel error -i $mp3 -ar 44100 -ac 1 -sample_fmt s16 $f 2>$null
                    if (Test-Path $f) { $done = $true }
                }
            } catch { }
            if (-not $done) {
                Write-Host "  edge-tts 失败，回落到 SAPI：$($text.Substring(0,[Math]::Min(20,$text.Length)))…" -ForegroundColor Yellow
            }
            Remove-Item $mp3 -Force -ErrorAction SilentlyContinue
        }
        if (-not $done) {
            $syn.SetOutputToWaveFile($f, $fmt)
            $syn.Speak($text)
            $syn.SetOutputToNull()
        }
    }
    # 单声道 44100Hz 16bit → 88200 字节/秒
    [pscustomobject]@{ Path = $f; Seconds = [math]::Round(((Get-Item $f).Length - 44) / 88200, 3) }
}

# ---------- 卡片 ----------
$punct = ([char[]](0x3002,0xFF0C,0x3001,0xFF1B,0xFF1A,0xFF01,0xFF1F,0x300B,0x3009,0x300D) -join '')

function New-Card([string]$file, [string]$big, [string]$small, [string]$accent) {
    $W = 1920; $H = 1080
    $bmp = New-Object Drawing.Bitmap $W, $H
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $bg = New-Object Drawing.Drawing2D.LinearGradientBrush(
        (New-Object Drawing.Point 0,0), (New-Object Drawing.Point 0,$H),
        [Drawing.Color]::FromArgb(10,16,28), [Drawing.Color]::FromArgb(18,30,46))
    $g.FillRectangle($bg, 0, 0, $W, $H); $bg.Dispose()
    if (-not $accent) { $accent = '#5AC8FA' }
    $ab = New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml($accent))
    $g.FillRectangle($ab, 140, 320, 10, 170); $ab.Dispose()
    $white = New-Object Drawing.SolidBrush ([Drawing.Color]::White)
    $gray  = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(150,160,175))
    $f1 = New-Object Drawing.Font('Microsoft YaHei', 64, [Drawing.FontStyle]::Bold)
    $f2 = New-Object Drawing.Font('Microsoft YaHei', 30, [Drawing.FontStyle]::Regular)
    $g.DrawString($big, $f1, $white, 190, 350)
    if ($small) { $g.DrawString($small, $f2, $gray, 196, 490) }
    $bmp.Save($file, [Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

function Add-Subtitle([string]$src, [string]$dst, [string]$text) {
    $img = [Drawing.Image]::FromFile($src)
    $W = 1920; $H = 1080
    $bmp = New-Object Drawing.Bitmap $W, $H
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $s = [Math]::Max($W / $img.Width, $H / $img.Height)
    $dw = [int]($img.Width * $s); $dh = [int]($img.Height * $s)
    $g.DrawImage($img, (New-Object Drawing.Rectangle ([int](($W-$dw)/2)), ([int](($H-$dh)/2)), $dw, $dh))
    $img.Dispose()
    $rect = New-Object Drawing.Rectangle 0, ($H-280), $W, 280
    $grad = New-Object Drawing.Drawing2D.LinearGradientBrush($rect,
        [Drawing.Color]::FromArgb(0,0,0,0), [Drawing.Color]::FromArgb(215,0,0,0),
        [Drawing.Drawing2D.LinearGradientMode]::Vertical)
    $g.FillRectangle($grad, $rect); $grad.Dispose()
    $drawFont = New-Object Drawing.Font('Microsoft YaHei', 38, [Drawing.FontStyle]::Bold)
    $white = New-Object Drawing.SolidBrush ([Drawing.Color]::White)
    $black = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(210,0,0,0))
    $maxW = 1680; $lines = @(); $cur = ''
    foreach ($ch in $text.ToCharArray()) {
        $test = $cur + $ch
        if (($g.MeasureString($test, $drawFont).Width -gt $maxW) -and $cur.Length -gt 0) {
            $lines += $cur; $cur = [string]$ch
            while ($cur.Length -gt 0 -and $punct.Contains($cur[0]) -and $lines.Count -gt 0) {
                $lines[$lines.Count-1] = $lines[$lines.Count-1] + $cur[0]; $cur = $cur.Substring(1)
            }
        } else { $cur = $test }
    }
    if ($cur.Length -gt 0) { $lines += $cur }
    $lh = 60; $y = $H - 160 - ($lines.Count * $lh) / 2 + $lh / 2
    foreach ($ln in $lines) {
        $sz = $g.MeasureString($ln, $drawFont); $x = ($W - $sz.Width) / 2
        $g.DrawString($ln, $drawFont, $black, ($x+2), ($y-$sz.Height/2+2))
        $g.DrawString($ln, $drawFont, $white, $x, ($y-$sz.Height/2))
        $y += $lh
    }
    $bmp.Save($dst, [Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

# ---------- 逐段准备 ----------
$i = 0
$audioPlan = @()
$videoParts = @()
$timeline = 0.0
$segMeta = @()

foreach ($s in $segs) {
    $i++
    $tts = Get-Tts ($s.say)
    $saySec = if ($tts) { $tts.Seconds } else { 0 }
    $gap = if ($null -ne $s.gap) { [double]$s.gap } else { 0.45 }
    $need = $saySec + $gap
    $file = Join-Path $work ("segs\{0:D2}.png" -f $i)

    switch ($s.type) {
        'card' {
            $card = Join-Path $work ("cards\{0:D2}.png" -f $i)
            New-Card $card $s.big $s.small $s.accent
            if ($s.say -and $s.subtitle -ne $false) { Add-Subtitle $card $file $s.say } else { Copy-Item $card $file -Force }
            $dur = $need
        }
        'image' {
            if ($s.say -and $s.subtitle -ne $false) { Add-Subtitle $s.path $file $s.say } else { Copy-Item $s.path $file -Force }
            $dur = $need
        }
        'video' {
            $dur = [Math]::Max([double]$s.duration, $need)
        }
        default { throw "未知段类型: $($s.type)" }
    }

    $segMeta += [pscustomobject]@{ Index = $i; Type = $s.type; Path = $s.path; File = $file; Duration = [math]::Round($dur,3) }

    # 音频：前导静音 + 配音 + 尾巴静音
    $audioPlan += [pscustomobject]@{ Kind = 'sil'; Seconds = $gap }
    $timeline += $dur
}

# 音频拼接：每段“配音在前，静音在后”，整轨按段顺序拼
$alist = New-Object System.Text.StringBuilder
foreach ($m in $segMeta) {
    $s = $segs[$m.Index - 1]
    if ($s.say) {
        $tts = Get-Tts ($s.say)
        if ($null -eq $tts) { throw "配音生成失败：$($s.say)" }
        [void]$alist.AppendLine("file '" + ($tts.Path.Replace('\','/')) + "'")
        $tail = [Math]::Round($m.Duration - $tts.Seconds, 3)
        if ($tail -gt 0.01) {
            $sil = Join-Path $work ("segs\tail{0:D2}.wav" -f $m.Index)
            & $FF -loglevel error -y -f lavfi -i "anullsrc=r=44100:cl=mono" -t $tail -c:a pcm_s16le $sil 2>&1 | Out-Null
            [void]$alist.AppendLine("file '" + ($sil.Replace('\','/')) + "'")
        }
    } else {
        $sil = Join-Path $work ("segs\sil{0:D2}.wav" -f $m.Index)
        & $FF -loglevel error -y -f lavfi -i "anullsrc=r=44100:cl=mono" -t $m.Duration -c:a pcm_s16le $sil 2>&1 | Out-Null
        [void]$alist.AppendLine("file '" + ($sil.Replace('\','/')) + "'")
    }
}
$alistFile = Join-Path $work 'alist.txt'
[IO.File]::WriteAllText($alistFile, $alist.ToString(), (New-Object System.Text.UTF8Encoding($false)))
$voice = Join-Path $work 'voice.wav'
& $FF -y -f concat -safe 0 -i $alistFile -c copy $voice 2>&1 | Out-Null

# ---------- 视频拼接 ----------
$inputs = @()
$filters = @()
$concatLabels = @()
$idx = 0
foreach ($m in $segMeta) {
    if ($m.Type -eq 'video') {
        $inputs += @('-stream_loop','-1','-t',"$($m.Duration)",'-i',$m.Path)
    } else {
        $inputs += @('-loop','1','-t',"$($m.Duration)",'-i',$m.File)
    }
    $filters += "[$idx`:v]scale=1920:1080,setsar=1,fps=30[v$idx]"
    $concatLabels += "[v$idx]"
    $idx++
}
$inputs += @('-i', $voice)
$audioIdx = $idx
$filter = ($filters -join ';') + ';' + ($concatLabels -join '') + "concat=n=$($segMeta.Count):v=1:a=0[vout]"

& $FF -y @inputs -filter_complex $filter -map '[vout]' -map "$audioIdx`:a" `
    -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p `
    -c:a aac -b:a 192k -shortest $Out 2>&1 | Select-String 'Error|Invalid' | Select-Object -First 3

$syn.Dispose()

if (Test-Path $Out) {
    $len = [math]::Round((Get-Item $Out).Length / 1MB, 2)
    Write-Host ("完成: {0}  ({1} MB, {2} 段)" -f $Out, $len, $segMeta.Count) -ForegroundColor Green
} else {
    throw '出片失败'
}
