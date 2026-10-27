# config.example.ps1 — 两个脚本的配置区长什么样
# 这不是拿来直接跑的，是给你对照着改的。
# 把下面各项抄进 selfcheck.ps1 和 backup.ps1 开头的「配置区」。

# ============ selfcheck.ps1 的配置区 ============
$SelfCheckConfig = @{
    # 应用名（进程名）。没有就留空字符串。
    AppName     = 'Coopanion'

    # 应用目录，用来读 version（会拼 resources\app\package.json）。没有就留空。
    AppDir      = 'D:\Apps\Coopanion'

    # 应用日志，用来数扩展加载了几个。没有就留空。
    AppLog      = 'D:\Apps\Coopanion\data\logs\core.log'

    # 需要检查版本的外部命令。键是显示名，值是取版本的脚本块。
    ToolCmd     = @{
        'bili-cli' = { & 'C:\Tools\uv\uv.exe' tool list 2>&1 | Select-String 'bili-agent' | Select-Object -First 1 }
    }

    # 需要报告版本的可执行文件（会跑 -version）
    BinPaths    = @('C:\Tools\bin\ffmpeg.exe', 'C:\Tools\bin\ffprobe.exe')

    # 备份目录（每个都查最新一份）
    BackupDirs  = @('C:\Backup\app', 'D:\Backup\app')

    # 要报告剩余空间的盘
    Drives      = @('C:', 'D:')
}

# ============ backup.ps1 的配置区 ============
$BackupConfig = @{
    # 要备份的记忆目录（助手的数据目录）
    Source  = 'D:\Apps\Coopanion\data\home\companion'

    # 第一块盘
    DestA   = 'C:\Backup\app'

    # 第二块盘。留空则只备一份（不推荐）。
    DestB   = 'D:\Backup\app'

    # 文件名前缀
    Prefix  = 'companion'

    # 保留份数
    Keep    = 7
}

# ============ 三个容易踩的坑 ============
#
# 1. 路径带中文或空格：PowerShell 里用单引号包起来，别用双引号（会被当变量展开）。
# 2. .ps1 存成 UTF-8 带 BOM：PowerShell 5.1 会把无 BOM 的 UTF-8 当 ANSI 读，
#    中文注释会让整个脚本解析失败。
# 3. 两块盘要真的不同物理盘：同一个盘的两个目录，盘坏了一起没。
