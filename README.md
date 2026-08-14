<div align="center">

<img src="logo.svg" alt="TorrServer for OpenWrt" width="100%"/>

**Installer for [TorrServer](https://github.com/YouROK/TorrServer) on OpenWrt and FriendlyWrt**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-POSIX%20sh-89e051.svg)](#)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-19.07%2B-00b5e2.svg)](https://openwrt.org)
[![TorrServer](https://img.shields.io/badge/TorrServer-latest-e03030.svg)](https://github.com/YouROK/TorrServer/releases/latest)
[![Release](https://img.shields.io/github/v/release/dontbass/torrserverwrt?color=e03030&label=release)](https://github.com/dontbass/torrserverwrt/releases/latest)
[![GitHub stars](https://img.shields.io/github/stars/dontbass/torrserverwrt?style=flat&color=yellow)](https://github.com/dontbass/torrserverwrt/stargazers)

[English](#english) · [Русский](#русский)

</div>

---

## English

### What is this

TorrServer is an HTTP server for **streaming torrents without downloading to disk**. Perfect for a home media center: start a movie in Lampa or any other player, and the router streams it directly from the torrent.

This script automates installation, configuration, and maintenance of TorrServer on routers running **OpenWrt** and **FriendlyWrt**.

```
  Lampa / player  ──▶  TorrServer (router)  ──▶  torrent tracker
```

### Quick start

```sh
curl -sSL https://raw.githubusercontent.com/dontbass/torrserverwrt/main/install.sh | sh
```

Or manually:

```sh
curl -O https://raw.githubusercontent.com/dontbass/torrserverwrt/main/install.sh
sh install.sh -i
```

After installation the web UI is available at `http://<router IP>:8090`

### Features

| | |
|---|---|
| 🌐 | English / Russian interface — language saved between sessions |
| 🔍 | Auto-detection of router architecture |
| ⬇️ | Downloads the latest TorrServer version from GitHub |
| ⚙️ | Configures as a system service via **procd** with autostart |
| 🔒 | HTTP authorization — set, change or disable without reinstall |
| 🔌 | Change port without reinstall |
| 🔄 | Atomic binary update (no `text file busy`) |
| ↩️ | Rollback to old version on failed update |
| ⏰ | Auto-update via cron (weekly) |
| 📊 | Status: version, uptime, address, login/password |
| 💾 | Free space check before download |
| 🗑️ | Clean removal with all data |

### Commands

```sh
sh install.sh -i    # install
sh install.sh -u    # update
sh install.sh -s    # status
sh install.sh -r    # remove
sh install.sh -h    # help
```

Flags: `--no-color` — no colors (for logs), `--auto` — for cron.

### Status output

```
=============================================================
 TorrServer Status
=============================================================
 Version:    MatriX.142.2
 Binary:     TorrServer-linux-arm64
 Service:    RUNNING
 Address:    http://192.168.1.1:8090
 Uptime:     2h 15m 42s
 Auth:       ON
 Login:      admin
 Password:   mypassword
 Auto-upd:   ON
 Update:     not required
=============================================================
```

### Lampa integration

TorrServer is natively supported in [Lampa](https://lampa.stream):

```
Lampa → Settings → TorrServer → Address: http://<router IP>:8090
```

Press «Check» — the status should turn green «Connected».

### Compatibility

> **On MIPS routers** streaming may be unstable due to weak CPU.
> **ARM64** devices are recommended.

| Device | SoC | `uname -m` | Binary |
|---|---|---|---|
| NanoPi R2S/R4S/R5S | RK3328/RK3399 | `aarch64` | `linux-arm64` |
| Hiveton H5000M | MT7988 (A53) | `aarch64` | `linux-arm64` |
| Cudy TR3000, GL.iNet MT3000 | MT7981B | `aarch64` | `linux-arm64` |
| Raspberry Pi 3/4 (64-bit) | BCM2837/2711 | `aarch64` | `linux-arm64` |
| Raspberry Pi 2/3 (32-bit) | BCM2836/2837 | `armv7l` | `linux-arm7` |
| Beeline SmartBox TURBO+ | MT7621 | `mipsel` | `linux-mipsle` |
| GL.iNet GL-AR750 | QCA9563 | `mips` | `linux-mips` |
| x86/x86_64 PC router | — | `x86_64` | `linux-amd64` |
| Others | — | — | manual input |

**Minimum requirements:** 256 MB RAM · 80 MB in `/opt` · curl · OpenWrt 19.07+

### Auto-update

TorrServer releases rarely. Auto-update checks for a new version **once a week** (Sunday, 04:00) and downloads (~70 MB) only if available.

> Not recommended if less than 150 MB free in `/opt`.

```sh
cat /var/log/torrserver-update.log   # update log
```

### Files

| Path | Purpose |
|---|---|
| `/opt/torrserver/TorrServer-*` | Executable |
| `/opt/torrserver/version` | Installed version |
| `/opt/torrserver/lang` | Selected language |
| `/opt/torrserver/accs.db` | Login/password (if auth enabled) |
| `/opt/torrserver/torr/` | Torrent database |
| `/etc/init.d/torrserver` | Service init script |
| `/var/log/torrserver-update.log` | Auto-update log |

---

## Русский

### Что это

TorrServer — HTTP-сервер для **стриминга торрентов без скачивания на диск**. Идеально для домашнего медиацентра: запускаете фильм в Lampa или любом другом плеере, роутер раздаёт поток прямо из торрента.

Этот скрипт автоматизирует установку, настройку и обслуживание TorrServer на роутерах под управлением **OpenWrt** и **FriendlyWrt**.

```
  Lampa / плеер  ──▶  TorrServer (роутер)  ──▶  торрент-трекер
```

### Быстрый старт

```sh
curl -sSL https://raw.githubusercontent.com/dontbass/torrserverwrt/main/install.sh | sh
```

Или вручную:

```sh
curl -O https://raw.githubusercontent.com/dontbass/torrserverwrt/main/install.sh
sh install.sh -i
```

После установки веб-интерфейс доступен по адресу `http://<IP роутера>:8090`

### Возможности

| | |
|---|---|
| 🌐 | Интерфейс на русском и английском — язык сохраняется между сессиями |
| 🔍 | Автоопределение архитектуры роутера |
| ⬇️ | Загрузка последней версии TorrServer с GitHub |
| ⚙️ | Настройка службы через **procd** с автозапуском |
| 🔒 | HTTP-авторизация — включить, сменить пароль или отключить без переустановки |
| 🔌 | Смена порта без переустановки |
| 🔄 | Атомарное обновление бинаря (без `text file busy`) |
| ↩️ | Откат на старую версию при неудачном обновлении |
| ⏰ | Автообновление через cron (еженедельно) |
| 📊 | Статус: версия, uptime, адрес, логин/пароль |
| 💾 | Проверка свободного места перед загрузкой |
| 🗑️ | Корректное удаление со всеми данными |

### Команды

```sh
sh install.sh -i    # установка
sh install.sh -u    # обновление
sh install.sh -s    # статус
sh install.sh -r    # удаление
sh install.sh -h    # справка
```

Флаги: `--no-color` — без цветов (для логов), `--auto` — для cron.

### Вывод статуса

```
=============================================================
 Статус TorrServer
=============================================================
 Версия:     MatriX.142.2
 Бинарь:     TorrServer-linux-arm64
 Служба:     ЗАПУЩЕНА
 Адрес:      http://192.168.1.1:8090
 Uptime:     2ч 15м 42с
 Авториз.:   ВКЛ
 Логин:      admin
 Пароль:     mypassword
 Автообн.:   ВКЛ
 Обновление: не требуется
=============================================================
```

### Подключение Lampa

TorrServer нативно поддерживается в [Lampa](https://lampa.stream):

```
Lampa → Настройки → TorrServer → Адрес: http://<IP роутера>:8090
```

Нажмите «Проверить» — статус должен стать зелёным «Подключено».

### Совместимость

> **На MIPS-роутерах** стриминг может работать нестабильно из-за слабого CPU.
> Рекомендуются устройства на **ARM64**.

| Устройство | SoC | `uname -m` | Бинарь |
|---|---|---|---|
| NanoPi R2S/R4S/R5S | RK3328/RK3399 | `aarch64` | `linux-arm64` |
| Hiveton H5000M | MT7988 (A53) | `aarch64` | `linux-arm64` |
| Cudy TR3000, GL.iNet MT3000 | MT7981B | `aarch64` | `linux-arm64` |
| Raspberry Pi 3/4 (64-bit) | BCM2837/2711 | `aarch64` | `linux-arm64` |
| Raspberry Pi 2/3 (32-bit) | BCM2836/2837 | `armv7l` | `linux-arm7` |
| Beeline SmartBox TURBO+ | MT7621 | `mipsel` | `linux-mipsle` |\
| GL.iNet GL-AR750 | QCA9563 | `mips` | `linux-mips` |
| PC-роутер x86/x86_64 | — | `x86_64` | `linux-amd64` |
| Прочие | — | — | ручной ввод |

**Минимальные требования:** 256 МБ RAM · 80 МБ в `/opt` · curl · OpenWrt 19.07+

### Автообновление

TorrServer выходит редко. Автообновление проверяет наличие новой версии **раз в неделю** (воскресенье, 04:00) и скачивает (~70 МБ) только если она есть.

> Не рекомендуется при менее 150 МБ свободного места в `/opt`.

```sh
cat /var/log/torrserver-update.log   # лог обновлений
```

### Файлы

| Путь | Назначение |
|---|---|
| `/opt/torrserver/TorrServer-*` | Исполняемый файл |
| `/opt/torrserver/version` | Текущая версия |
| `/opt/torrserver/lang` | Выбранный язык |
| `/opt/torrserver/accs.db` | Логин/пароль (если авторизация включена) |
| `/opt/torrserver/torr/` | База торрентов |
| `/etc/init.d/torrserver` | Init-скрипт службы |
| `/var/log/torrserver-update.log` | Лог автообновлений |

---

<div align="center">

Based on [YouROK/TorrServer](https://github.com/YouROK/TorrServer) · adapted for OpenWrt

</div>
