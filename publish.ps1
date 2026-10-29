﻿# Публикация нового релиза программы в этот репозиторий.
#
#   powershell -ExecutionPolicy Bypass -File publish.ps1 -App karaoke -Version 1.1 -Zip "..\Karaoke\dist\Karaoke 1.1.zip"
#   powershell -ExecutionPolicy Bypass -File publish.ps1 -List        # список опубликованных версий
#
# Скрипт: считает sha256, создаёт релиз с тегом <slug>-v<версия>, прикрепляет архив,
# обновляет updates.json и пушит его — установщик сразу увидит новую версию.

param(
    [ValidateSet('karaoke', 'minusmaker', 'rutube-audio', '')]
    [string]$App = '',
    [string]$Version = '',
    [string]$Zip = '',
    [switch]$List
)

$ErrorActionPreference = 'Stop'
$Repo = 'xdenix/audio-tools'

$Meta = @{
    karaoke      = @{ folder = 'Karaoke';      exe = 'Karaoke.exe';      name = 'Видеокараоке' }
    minusmaker   = @{ folder = 'MinusMaker';   exe = 'MinusMaker.exe';   name = 'Минусовка' }
    'rutube-audio' = @{ folder = 'RuTube Audio'; exe = 'RuTube Audio.exe'; name = 'RuTube Audio' }
}

if ($List) {
    gh release list -R $Repo
    return
}

if (-not ($App -and $Version -and $Zip)) {
    throw 'Нужны параметры: -App, -Version, -Zip. Пример в шапке файла.'
}
$Zip = (Resolve-Path $Zip).Path
if (-not (Test-Path $Zip)) { throw "Нет файла: $Zip" }
Set-Location (Join-Path $PSScriptRoot '..')

$meta = $Meta[$App]
$tag = '{0}-v{1}' -f $App, $Version
$assetName = '{0} {1}.zip' -f $meta.folder, $Version
$encoded = [uri]::EscapeDataString($assetName)
$downloadUrl = "https://github.com/$Repo/releases/download/$tag/$encoded"
$sha = (Get-FileHash $Zip -Algorithm SHA256).Hash.ToLower()
$size = (Get-Item $Zip).Length

Write-Host "Релиз: $($meta.name) $Version ($tag), архив $([math]::Round($size/1MB,1)) МБ"

# 1. релиз + архив
$notes = "Release $Version. See README for install instructions."
$releaseUrl = gh release create $tag -R $Repo -t "$($meta.name) $Version" -n $notes $Zip
if ($LASTEXITCODE -ne 0) { throw 'gh release create завершился с ошибкой' }
Write-Host "Релиз создан: $releaseUrl"

# 2. updates.json
$manifestPath = Join-Path $PSScriptRoot '..\updates.json'
$manifest = if (Test-Path $manifestPath) {
    Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    [PSCustomObject]@{ schema = 1 }
}
if (-not $manifest.PSObject.Properties['apps']) {
    $manifest | Add-Member apps ([PSCustomObject]@{})
}
$appProps = $manifest.apps.PSObject.Properties[$App]
$entry = [PSCustomObject]@{
    displayName = $meta.name
    folder      = $meta.folder
    exe         = $meta.exe
    version     = $Version
    tag         = $tag
    asset       = $assetName
    url         = $downloadUrl
    sha256      = $sha
    size        = $size
}
if ($appProps) { $manifest.apps.($App) = $entry }
else { $manifest.apps | Add-Member $App $entry }

$json = $manifest | ConvertTo-Json -Depth 6
$out = Join-Path $env:TEMP 'updates.json'
[IO.File]::WriteAllText($out, $json, [Text.UTF8Encoding]::new($true))
Move-Item $out $manifestPath -Force

# 3. коммит
git add updates.json
git -c core.safecrlf=false commit -m "release: $($meta.name) $Version"
git push
Write-Host "Манифест обновлён и отправлен. Установщик уже видит $Version."
