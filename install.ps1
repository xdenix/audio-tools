# Установщик «Аудио-инструменты» для Windows 10/11 x64.
# Ставит программу в %LOCALAPPDATA%\Programs, создаёт ярлыки,
# при переустановке сохраняет models\ и vendor\ (модели и обновления yt-dlp).
#
# Примеры:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/xdenix/audio-tools/main/install.ps1))) -App karaoke
#   irm https://raw.githubusercontent.com/xdenix/audio-tools/main/install.ps1 | iex        # меню

param(
    [ValidateSet('karaoke', 'minusmaker', 'rutube-audio', 'all', '')]
    [string]$App = '',
    [string]$Path = '',
    [switch]$Portable,
    [switch]$NoShortcut,
    [switch]$Force,
    [switch]$Launch,
    [string]$TempDir = ''
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ManifestUrls = @(
    'https://raw.githubusercontent.com/xdenix/audio-tools/main/updates.json',
    'https://cdn.jsdelivr.net/gh/xdenix/audio-tools@main/updates.json'
)

function Write-Step($text) { Write-Host ''
    Write-Host "== $text" -ForegroundColor Cyan }

function Fail($text) {
    Write-Host ''
    Write-Host "ОШИБКА: $text" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- manifest
function Get-Manifest {
    $last = $null
    foreach ($url in $ManifestUrls) {
        try {
            Write-Host "Загружаю список версий: $url"
            $raw = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
            # запасной вариант: у JSON по стандарту не бывает BOM, но если он есть — срезаем
            if ($raw.Length -gt 0 -and $raw[0] -eq [char]0xFEFF) { $raw = $raw.Substring(1) }
            return ConvertFrom-Json $raw
        } catch { $last = $_ }
    }
    Fail "Не удалось скачать updates.json. Проверь интернет. ($($last.Exception.Message))"
}

# ---------------------------------------------------------------- download
function Invoke-FileDownload($url, $destPath, $label) {
    $request = [Net.WebRequest]::Create($url)
    $request.Method = 'GET'
    $response = $request.GetResponse()
    $total = $response.ContentLength
    $stream = $response.GetResponseStream()
    $file = [IO.File]::Create($destPath)
    $buffer = New-Object byte[] 1MB
    $done = [long]0
    try {
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $file.Write($buffer, 0, $read)
            $done += $read
            if ($total -gt 0) {
                $percent = [int](100 * $done / $total)
                Write-Progress -Activity $label -Status ("{0:N0} из {1:N0} МБ" -f ($done/1MB), ($total/1MB)) -PercentComplete $percent
            }
        }
    } finally {
        $stream.Dispose(); $file.Dispose(); $response.Dispose()
        Write-Progress -Activity $label -Completed
    }
    if ($total -gt 0 -and $done -ne $total) { throw "Скачано $done из $total байт" }
}

function Stop-RunningApp($exeName, $displayName) {
    $processName = [IO.Path]::GetFileNameWithoutExtension($exeName)
    $running = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if (-not $running) { return }
    if (-not $Force) {
        $answer = Read-Host "$displayName сейчас запущена. Закрыть и продолжить? [y/N]"
        if ($answer -notmatch '^[YyДд]') { Fail 'Установка отменена — сначала закрой программу.' }
    }
    $running | ForEach-Object {
        $_.CloseMainWindow() | Out-Null
    }
    $running | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
    $running = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($running) {
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    Write-Host "Закрыто: $displayName"
}

# ---------------------------------------------------------------- install one
function Install-App($slug) {
    $info = $manifest.apps.$slug
    if (-not $info) { Fail "В списке нет программы '$slug'" }

    $name = $info.displayName
    $folder = $info.folder
    $exeName = $info.exe
    $sizeMb = [math]::Round($info.size / 1MB, 0)

    Write-Step "$name $($info.version)"

    # --- куда ставим
    if ($Portable) {
        $base = (Get-Location).Path
    } elseif ($Path) {
        $base = $Path
    } else {
        $base = Join-Path $env:LOCALAPPDATA 'Programs'
    }
    $target = Join-Path $base $folder

    # --- место на диске
    if (-not $Portable) {
        $drive = (Get-PSDrive ($base.Substring(0, 1))).Free
        if ($drive -lt $info.size * 3) {
            Fail ("На диске {0} свободно {1:N1} ГБ, а надо ~{2:N1} ГБ (архив + распакованная папка)." -f
                $base.Substring(0, 2), ($drive/1GB), ($info.size/1GB))
        }
    }

    # --- папки установки и запущенная копия
    if (Test-Path $target) { Stop-RunningApp $exeName $name }

    # --- скачивание
    $download = Join-Path $tempDir ($folder + '.zip')
    if (-not (Test-Path $download)) {
        Write-Host "Качаю архив ($sizeMb МБ)…"
        Invoke-FileDownload $info.url $download "Скачивание: $name"
    } else {
        Write-Host "Архив уже скачан, использую: $download"
    }

    # --- целостность
    if ($info.sha256) {
        $actual = (Get-FileHash $download -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne $info.sha256.ToLower()) {
            Remove-Item $download -Force
            Fail 'Контрольная сумма архива не совпала — файл повреждён. Запусти установку ещё раз.'
        }
        Write-Host 'Контрольная сумма OK'
    }

    # --- распаковка
    $staging = Join-Path $tempDir ($folder + '.unpack')
    if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
    New-Item -ItemType Directory -Force $staging | Out-Null
    Expand-Archive -LiteralPath $download -DestinationPath $staging -Force
    $inner = Get-ChildItem $staging -Directory | Select-Object -First 1
    if (-not $inner -or -not (Test-Path (Join-Path $inner.FullName $exeName))) {
        Remove-Item $staging -Recurse -Force
        Fail 'Архив скачался не полностью или повреждён.'
    }

    # --- подмена папки (сохраняем models/vendor)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $base ($folder + '.old-' + $stamp)
    $isNew = -not (Test-Path $target)
    if (-not $isNew) {
        Move-Item -LiteralPath $target -Destination $backup
    }
    try {
        New-Item -ItemType Directory -Force $base | Out-Null
        Move-Item -LiteralPath $inner.FullName -Destination $target
    } catch {
        if (Test-Path $backup) {
            Remove-Item -Recurse -Force $target -ErrorAction SilentlyContinue
            Move-Item -LiteralPath $backup -Destination $target
        }
        throw
    }
    if (Test-Path $backup) {
        foreach ($keep in 'models', 'vendor') {
            $old = Join-Path $backup $keep
            $new = Join-Path $target $keep
            if (Test-Path $old) {
                if (Test-Path $new) { Remove-Item -Recurse -Force $new }
                Move-Item -LiteralPath $old -Destination $new
            }
        }
        # убрать старые резервные копии от прошлых установок
        Get-ChildItem $base -Directory -Filter ($folder + '.old-*') -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $download -Force -ErrorAction SilentlyContinue

    # --- ярлыки
    if (-not $NoShortcut -and -not $Portable) {
        $shell = New-Object -ComObject WScript.Shell
        $exePath = Join-Path $target $exeName
        $links = @(
            (Join-Path ([Environment]::GetFolderPath('Desktop')) ($name + '.lnk')),
            (Join-Path ([Environment]::GetFolderPath('Programs')) ($name + '.lnk'))
        )
        foreach ($lnk in $links) {
            $shortcut = $shell.CreateShortcut($lnk)
            $shortcut.TargetPath = $exePath
            $shortcut.WorkingDirectory = $target
            $shortcut.Description = $name
            $shortcut.Save()
        }
    }

    Write-Host ''
    Write-Host "Готово: $name $($info.version) установлена" -ForegroundColor Green
    Write-Host "Папка:  $target"
    if (-not $NoShortcut -and -not $Portable) {
        Write-Host 'Ярлыки: на рабочем столе и в меню «Пуск»'
    }
    Write-Host 'Первый запуск: Windows SmartScreen может спросить подтверждение — «Подробнее → Выполнить в любом случае».'

    if ($Launch) { Start-Process (Join-Path $target $exeName) }

    return $target
}

# ---------------------------------------------------------------- main
# временная папка
if (-not $TempDir) {
    $TempDir = Join-Path ([IO.Path]::GetTempPath()) ('audio_tools_install_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
}
New-Item -ItemType Directory -Force $TempDir | Out-Null

$manifest = Get-Manifest

# выбираем программу, если не задана
if (-not $App) {
    Write-Host ''
    Write-Host 'Что установить?' -ForegroundColor Yellow
    $list = @('karaoke', 'minusmaker', 'rutube-audio')
    for ($i = 0; $i -lt $list.Count; $i++) {
        $app = $manifest.apps.($list[$i])
        Write-Host ("  {0}) {1} — {2} {3} ({4:N0} МБ)" -f ($i + 1), $app.displayName, $list[$i], $app.version, ($app.size/1MB))
    }
    Write-Host '  4) Всё сразу'
    $answer = Read-Host 'Номер (или Enter для выхода)'
    if ($answer -match '^\s*4\s*$') { $App = 'all' }
    elseif ($answer -match '^\s*[123]\s*$') { $App = $list[[int]$answer - 1] }
    else { Write-Host 'Установка отменена'; exit 0 }
}

if ($App -eq 'all') {
    foreach ($slug in ('karaoke', 'minusmaker', 'rutube-audio')) { Install-App $slug | Out-Null }
} else {
    Install-App $App | Out-Null
}

Write-Host ''
Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
