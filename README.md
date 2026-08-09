# TorrServer для OpenWrt / FriendlyWrt

Скрипт для автоматической установки [TorrServer](https://github.com/YouROK/TorrServer) на роутеры под управлением OpenWrt и FriendlyWrt.

TorrServer — HTTP-сервер для стриминга торрентов без скачивания на диск, с веб-интерфейсом и API.

---

## Возможности скрипта

- Автоматическое определение архитектуры роутера
- Загрузка последней версии TorrServer с GitHub
- Настройка как системной службы через **procd** (OpenWrt native)
- Автозапуск при старте роутера
- Поддержка HTTP-авторизации
- Настройка порта
- Обновление до последней версии без переконфигурации
- Корректное удаление со всеми данными

## Поддерживаемые архитектуры

| Архитектура роутера | Бинарь TorrServer       |
|---------------------|-------------------------|
| aarch64 / arm64     | linux-arm64             |
| armv7               | linux-arm7              |
| armv5               | linux-arm5              |
| x86_64              | linux-amd64             |
| i686 / i386         | linux-386               |
| mips                | linux-mips / linux-mipsle |
| mips64              | linux-mips64            |
| riscv64             | linux-riscv64           |

Если архитектура не определена автоматически, скрипт запросит её вручную.

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

### Параметры запуска

```
install.sh -i | --install | install  — установка последней версии
install.sh -u | --update  | update   — обновление до последней версии
install.sh -r | --remove  | remove   — удаление TorrServer
install.sh -h | --help    | help     — справка
```

Без параметров запускается интерактивное меню.

---

## После установки

TorrServer будет доступен по адресу:

```
http://<IP роутера>:8090
```

Порт можно изменить при установке.

### Управление службой

```sh
# Запуск
/etc/init.d/torrserver start

# Остановка
/etc/init.d/torrserver stop

# Перезапуск
/etc/init.d/torrserver restart

# Статус
/etc/init.d/torrserver status
```

---

## Файлы и директории

| Путь                            | Назначение                      |
|---------------------------------|---------------------------------|
| `/opt/torrserver/`              | Рабочая директория              |
| `/opt/torrserver/TorrServer-*`  | Исполняемый файл                |
| `/opt/torrserver/version`       | Установленная версия            |
| `/opt/torrserver/accs.db`       | Файл авторизации (если включена)|
| `/opt/torrserver/torr/`         | База данных торрентов           |
| `/etc/init.d/torrserver`        | Init-скрипт службы              |

---

## Требования

- OpenWrt 19.07+ или FriendlyWrt
- `curl` (входит в состав большинства прошивок)
- Доступ в интернет с роутера
- Не менее 50 МБ свободного места в `/opt`

---

## Известные ограничения

- Стриминг работает в оперативной памяти — для комфортной работы рекомендуется роутер с 512 МБ RAM и выше
- TorrServer не качает файлы на диск — для постоянного хранения используйте другие инструменты

---

## Источник

На основе оригинального проекта [YouROK/TorrServer](https://github.com/YouROK/TorrServer), адаптирован для OpenWrt.
