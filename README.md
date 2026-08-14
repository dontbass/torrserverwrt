<div align="center">

<img src="logo.svg" alt="TorrServer for OpenWrt" width="100%"/>

**Установщик [TorrServer](https://github.com/YouROK/TorrServer) для OpenWrt и FriendlyWrt**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-POSIX%20sh-89e051.svg)](#)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-19.07%2B-00b5e2.svg)](https://openwrt.org)
[![TorrServer](https://img.shields.io/badge/TorrServer-latest-e03030.svg)](https://github.com/YouROK/TorrServer/releases/latest)
[![GitHub stars](https://img.shields.io/github/stars/dontbass/torrserverwrt?style=flat&color=yellow)](https://github.com/dontbass/torrserverwrt/stargazers)

</div>

---

## Что это

TorrServer — HTTP-сервер для стриминга торрентов **без скачивания на диск**. Идеально подходит для домашнего медиацентра: запускаете фильм в Lampa или любом другом плеере, роутер раздаёт поток прямо из торрента.

Этот скрипт автоматизирует установку, настройку и обслуживание TorrServer на роутерах под управлением **OpenWrt** и **FriendlyWrt**.

```
  Lampa / плеер  ──▶  TorrServer (роутер)  ──▶  торрент-трекер
```

---

## Быстрый старт

```sh
curl -sSL https://raw.githubusercontent.com/dontbass/torrserverwrt/main/install.sh | sh
```

Или вручную:

```sh
curl -O https://raw.githubusercontent.com/dontbass/torrserverwrt/main/install.sh
sh install.sh -i
```

После установки веб-интерфейс доступен по адресу `http://<IP роутера>:8090`

---

## Возможности

| | |
|---|---|
| 🔍 | Автоопределение архитектуры роутера |
| ⬇️ | Загрузка последней версии TorrServer с GitHub |
| ⚙️ | Настройка службы через **procd** с автозапуском |
| 🔒 | HTTP-авторизация и смена пароля без переустановки |
| 🔌 | Смена порта без переустановки |
| 🔄 | Атомарное обновление бинаря (без `text file busy`) |
| ↩️ | Откат на старую версию при неудачном обновлении |
| ⏰ | Автообновление через cron (еженедельно) |
| 📊 | Статус: версия, uptime, адрес, логин/пароль |
| 💾 | Проверка свободного места перед загрузкой |
| 🗑️ | Корректное удаление со всеми данными |

---

## Интерактивное меню

```
 Версия:  MatriX.142.2
 Служба:  ЗАПУЩЕНА

  i — установить / обновить
  s — статус
  p — сменить порт
  a — настроить авторизацию
  c — автообновление (cron)
  r — перезапустить службу
  d — удалить
  n — выйти
```

---

## Команды

```sh
sh install.sh -i    # установка
sh install.sh -u    # обновление
sh install.sh -s    # статус
sh install.sh -r    # удаление
sh install.sh -h    # справка
```

Флаги: `--no-color` — без цветов (для логов), `--auto` — для cron.

---

## Статус службы

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

---

## Совместимость

> **На MIPS-роутерах** стриминг может работать нестабильно из-за слабого CPU.
> Рекомендуются устройства на **ARM64**.

| Устройство | SoC | `uname -m` | Бинарь |
|---|---|---|---|
| NanoPi R2S/R4S/R5S | RK3328/RK3399 | `aarch64` | `linux-arm64` |
| Hiveton H5000M | MT7988 (A53) | `aarch64` | `linux-arm64` |
| Cudy TR3000, GL.iNet MT3000 | MT7981B | `aarch64` | `linux-arm64` |
| Raspberry Pi 3/4 (64-bit) | BCM2837/2711 | `aarch64` | `linux-arm64` |
| Raspberry Pi 2/3 (32-bit) | BCM2836/2837 | `armv7l` | `linux-arm7` |
| Beeline SmartBox TURBO+ | MT7621 | `mipsel` | `linux-mipsle` |
| GL.iNet GL-AR750 | QCA9563 | `mips` | `linux-mips` |
| PC-роутер | x86_64 | `x86_64` | `linux-amd64` |
| Прочие | — | — | ручной ввод |

**Минимальные требования:** 256 МБ RAM · 80 МБ в `/opt` · curl · OpenWrt 19.07+

---

## Подключение Lampa

TorrServer нативно поддерживается в [Lampa](https://lampa.stream):

```
Lampa → Настройки → TorrServer → Адрес: http://<IP роутера>:8090
```

Нажмите «Проверить» — статус должен стать зелёным «Подключено».

---

## Автообновление

TorrServer выходит редко. Автообновление проверяет наличие новой версии **раз в неделю** (воскресенье, 04:00) и скачивает (~70 МБ) только если она есть.

```sh
# Включить / отключить — через меню (пункт c)
# Лог обновлений:
cat /var/log/torrserver-update.log
```

> Не рекомендуется при менее 150 МБ свободного места в `/opt`.

---

## Файлы

| Путь | Назначение |
|---|---|
| `/opt/torrserver/TorrServer-*` | Исполняемый файл |
| `/opt/torrserver/version` | Текущая версия |
| `/opt/torrserver/accs.db` | Логин/пароль (если авторизация включена) |
| `/opt/torrserver/torr/` | База торрентов |
| `/etc/init.d/torrserver` | Init-скрипт службы |
| `/var/log/torrserver-update.log` | Лог автообновлений |

---

<div align="center">

Основан на [YouROK/TorrServer](https://github.com/YouROK/TorrServer) · адаптирован для OpenWrt

</div>
