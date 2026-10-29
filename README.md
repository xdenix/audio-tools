# Аудио-инструменты Windows

Готовые сборки (exe без Python) трёх программ для работы с аудио:

| Программа | Что делает | Размер архива |
|---|---|---|
| **Видеокараоке** (`karaoke`) | Из песни делает MP4: музыка без вокала + слова с подсветкой | ~260 МБ |
| **Минусовка** (`minusmaker`) | Вырезает инструмент из песни нейросетью Demucs | ~200 МБ |
| **RuTube Audio** (`rutube-audio`) | Скачивает аудиодорожку из видео RuTube в MP3 | ~55 МБ |

Установка идёт в `%LOCALAPPDATA%\Programs`, ярлыки — на рабочий стол и в меню «Пуск».
Права администратора не нужны. Модели нейросетей докачиваются при первом использовании
и хранятся в папке программы.

## Установка одной командой (PowerShell)

**Видеокараоке:**
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/xdenix/audio-tools/main/install.ps1))) -App karaoke
```

**Минусовка:**
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/xdenix/audio-tools/main/install.ps1))) -App minusmaker
```

**RuTube Audio:**
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/xdenix/audio-tools/main/install.ps1))) -App rutube-audio
```

**Без параметров** — установщик покажет меню и спросит, что ставить:
```powershell
irm https://raw.githubusercontent.com/xdenix/audio-tools/main/install.ps1 | iex
```

## Параметры

| Параметр | Значение |
|---|---|
| `-App karaoke\|minusmaker\|rutube-audio\|all` | Что устанавливать (по умолчанию — меню) |
| `-Path <папка>` | Куда ставить (по умолчанию `%LOCALAPPDATA%\Programs`) |
| `-Portable` | Только распаковать рядом с установщиком, без ярлыков |
| `-NoShortcut` | Не создавать ярлыки |
| `-Force` | Закрыть запущенную копию программы при переустановке |
| `-Launch` | Запустить программу сразу после установки |

## Обновление

Повторный запуск той же команды ставит свежую версию поверх старой:
модели (`models`) и обновления yt-dlp (`vendor`) при этом сохраняются.

## Исходный код

Исходники лежат в приватных репозиториях: `xdenix/Karaoke`, `xdenix/MinusMaker`, `xdenix/RutubeAudio`.
