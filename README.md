# TorrServer для OpenWrt / FriendlyWrt

Скрипт для автоматической установки [TorrServer](https://github.com/YouROK/TorrServer) на роутеры под управлением OpenWrt и FriendlyWrt.

TorrServer — HTTP-сервер для стриминга торрентов без скачивания на диск, с веб-интерфейсом и API.

---

## Возможности скрипта

- Автоматическое определение архитектуры роутера
- Загрузка **последней версии** TorrServer с GitHub
- Настройка как системной службы через **procd** (OpenWrt native) с автозапуском
- Настройка порта и HTTP-авторизации при установке
- Обновление до последней версии без переконфигурации
- Атомарная замена бинаря при обновлении (без `text file busy`)
- Откат на старую версию при неудачном обновлении
- Проверка свободного места перед загрузкой
- Проверка доступности процесса после старта
- Статус службы: версия, uptime, адрес, логин/пароль, наличие обновлений
- Корректное удаление со всеми данными

---

## Установка

```sh
curl -sSL https://raw.githubusercontent.com/dontbass/torrserverwrt/main/install.sh | sh
```

Или скачать и запустить вручную:

```sh
curl -O https://raw.githubusercontent.com/dontbass/torrserverwrt/main/install.sh
chmod +x install.sh
sh install.sh -i
```

---

## Команды

```
install.sh -i | --install | install  — установка последней версии
install.sh -u | --update  | update   — обновление до последней версии
install.sh -s | --status  | status   — статус службы
install.sh -r | --remove  | remove   — удаление TorrServer
install.sh -h | --help    | help     — справка
```

Без параметров — интерактивное меню с отображением текущего состояния.

### Пример вывода статуса

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
 Обновление: не требуется
=============================================================
```

---

## Поддерживаемые архитектуры

| Роутер / SoC                          | `uname -m`  | Бинарь             |
|---------------------------------------|-------------|--------------------|
| NanoPi R5S, Hiveton H5000M (A53)      | aarch64     | linux-arm64        |
| Cudy TR3000, GL.iNet (MT7981B)        | aarch64     | linux-arm64        |
| Raspberry Pi 3/4 (64-bit)            | aarch64     | linux-arm64        |
| Raspberry Pi 2/3 (32-bit)            | armv7l      | linux-arm7         |
| GL.iNet GL-AR750 (MIPS 24Kc)         | mips        | linux-mips         |
| Beeline SmartBox TURBO+ (MT7621)     | mipsel      | linux-mipsle       |
| x86/x86_64 (PC роутер)               | x86_64      | linux-amd64        |
| Прочие                                | —           | ручной ввод        |

Если архитектура не определяется автоматически — скрипт предложит ввести её вручную.

---

## После установки

TorrServer доступен по адресу:

```
http://<IP роутера>:8090
```

### Управление службой

```sh
/etc/init.d/torrserver start
/etc/init.d/torrserver stop
/etc/init.d/torrserver restart
/etc/init.d/torrserver status
```

### Просмотр логов

```sh
logread | grep torrserver
```

---

## Файлы и директории

| Путь                              | Назначение                          |
|-----------------------------------|-------------------------------------|
| `/opt/torrserver/`                | Рабочая директория                  |
| `/opt/torrserver/TorrServer-*`    | Исполняемый файл                    |
| `/opt/torrserver/version`         | Установленная версия                |
| `/opt/torrserver/binary`          | Имя бинаря (для обновления)         |
| `/opt/torrserver/accs.db`         | Логин/пароль авторизации (если вкл) |
| `/opt/torrserver/torr/`           | База данных торрентов               |
| `/etc/init.d/torrserver`          | Init-скрипт службы                  |

---

## Требования

- OpenWrt 19.07+ или FriendlyWrt
- `curl` (входит в большинство прошивок)
- Доступ роутера в интернет
- Минимум 80 МБ свободного места в `/opt`
- 256+ МБ RAM (512 МБ рекомендуется)

---

## Источник

На основе оригинального проекта [YouROK/TorrServer](https://github.com/YouROK/TorrServer), адаптирован для OpenWrt.
