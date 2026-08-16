#!/bin/sh

username="torrserver"
dirInstall="/opt/torrserver"
serviceName="torrserver"
scriptname=$(basename "$0")
NO_COLOR=0
AUTO_MODE=0
LANG_FILE="$dirInstall/lang"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

colorize() {
    if [ "$NO_COLOR" -eq 1 ]; then
        printf "%s" "$2"
    else
        case $1 in
            red)    printf "${RED}%s${NC}" "$2" ;;
            green)  printf "${GREEN}%s${NC}" "$2" ;;
            yellow) printf "${YELLOW}%s${NC}" "$2" ;;
            cyan)   printf "${CYAN}%s${NC}" "$2" ;;
            blue)   printf "${BLUE}%s${NC}" "$2" ;;
            *)      printf "%s" "$2" ;;
        esac
    fi
}

# ============================================================
# ОПРЕДЕЛЕНИЕ ПЛАТФОРМЫ
# ============================================================

OS_TYPE=""
OS_NAME=""

detectOS() {
    if [ -f /etc/openwrt_release ]; then
        OS_TYPE="openwrt"
        OS_NAME="OpenWrt"
        return
    fi
    if [ -f /etc/alpine-release ]; then
        OS_TYPE="alpine"
        OS_NAME="Alpine Linux"
        return
    fi
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="${PRETTY_NAME:-$NAME}"
        case "$ID" in
            ubuntu|debian|raspbian|linuxmint|pop)
                OS_TYPE="debian" ;;
            arch|manjaro|endeavouros|garuda)
                OS_TYPE="arch" ;;
            fedora|rhel|centos|rocky|almalinux)
                OS_TYPE="rhel" ;;
            opensuse*|sles)
                OS_TYPE="suse" ;;
            *)
                # Проверяем по ID_LIKE
                case "$ID_LIKE" in
                    *debian*|*ubuntu*) OS_TYPE="debian" ;;
                    *arch*)            OS_TYPE="arch" ;;
                    *rhel*|*fedora*)   OS_TYPE="rhel" ;;
                    *)                 OS_TYPE="unknown" ;;
                esac
                ;;
        esac
        return
    fi
    OS_TYPE="unknown"
    OS_NAME="Unknown Linux"
}

hasSystemd() {
    command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1
}

# ============================================================
# ЛОКАЛИЗАЦИЯ
# ============================================================

LANG_CODE="ru"

loadLang() {
    if [ -f "$LANG_FILE" ]; then
        LANG_CODE=$(cat "$LANG_FILE")
    fi
}

saveLang() {
    mkdir -p "$dirInstall" 2>/dev/null
    printf "%s" "$LANG_CODE" > "$LANG_FILE"
}

selectLanguage() {
    printf "\n"
    printf "  Select language / Выберите язык:\n"
    printf "\n"
    printf "  1) English\n"
    printf "  2) Русский\n"
    printf "\n"
    printf "  Choice / Выбор [1/2]: "
    read -r lang_choice </dev/tty
    case $lang_choice in
        1) LANG_CODE="en" ;;
        2) LANG_CODE="ru" ;;
        *) LANG_CODE="ru" ;;
    esac
    saveLang
}

# Получить строку по ключу
t() {
    local key="$1"
    shift
    local str=""
    case "${LANG_CODE}:${key}" in
        # --- лого ---
        en:logo_sub)    str="                        for OpenWrt / FriendlyWrt" ;;
        ru:logo_sub)    str="                        для OpenWrt / FriendlyWrt" ;;
        # --- общие ---
        en:yes_no)      str="(%s/%s) " ; printf "$str" "$(colorize green Y)es" "$(colorize yellow N)o" ; return ;;
        ru:yes_no)      str="(%s/%s) " ; printf "$str" "$(colorize green Y)es" "$(colorize yellow N)o" ; return ;;
        en:cancelled)   str=" Cancelled\n" ;;
        ru:cancelled)   str=" Отменено\n" ;;
        en:requires_root) str=" Run as root: sh %s\n" ;;
        ru:requires_root) str=" Запустите от root: sh %s\n" ;;
        en:checking_inet) str=" Checking internet connection...\n" ;;
        ru:checking_inet) str=" Проверяем соединение с Интернетом...\n" ;;
        en:inet_ok)     str=" - Connection OK\n" ;;
        ru:inet_ok)     str=" - Соединение в порядке\n" ;;
        en:inet_fail)   str=" - No access to GitHub. Check your connection.\n" ;;
        ru:inet_fail)   str=" - Нет доступа к GitHub. Проверьте соединение.\n" ;;
        # --- установка ---
        en:install_title)  str="=============================================================\n Installation\n=============================================================\n" ;;
        ru:install_title)  str="=============================================================\n Установка TorrServer\n=============================================================\n" ;;
        en:hw_warn)     str=" $(colorize yellow "ROUTER REQUIREMENTS:")\n  RAM:   256 MB min, 512 MB+ recommended\n  Space: ~70-80 MB free in /opt\n  CPU:   MIPS routers may struggle with streaming.\n         ARM64 works best (NanoPi, RPi 3/4, MT7981)\n" ;;
        ru:hw_warn)     str=" $(colorize yellow "ТРЕБОВАНИЯ К РОУТЕРУ:")\n  RAM:   минимум 256 МБ, рекомендуется 512 МБ и более\n  Место: ~70-80 МБ свободно в /opt\n  CPU:   на MIPS-роутерах стриминг может тормозить.\n         Уверенно работает на ARM64 (NanoPi, RPi 3/4, MT7981)\n" ;;
        en:proceed)     str=" Proceed with installation? " ;;
        ru:proceed)     str=" Продолжить установку? " ;;
        en:aborted)     str=" Installation cancelled\n\n" ;;
        ru:aborted)     str=" Установка отменена\n\n" ;;
        en:arch_detected) str=" Architecture: %s\n" ;;
        ru:arch_detected) str=" Архитектура: %s\n" ;;
        en:arch_unknown)  str=" - Unknown architecture: %s\n   Options: linux-amd64, linux-arm64, linux-arm7, linux-arm5,\n             linux-mips, linux-mipsle, linux-mips64, linux-386, linux-riscv64\n" ;;
        ru:arch_unknown)  str=" - Неизвестная архитектура: %s\n   Варианты: linux-amd64, linux-arm64, linux-arm7, linux-arm5,\n             linux-mips, linux-mipsle, linux-mips64, linux-386, linux-riscv64\n" ;;
        en:arch_enter)  str=" Enter architecture: " ;;
        ru:arch_enter)  str=" Введите архитектуру: " ;;
        en:getting_ver) str=" Fetching latest version...\n" ;;
        ru:getting_ver) str=" Получаем информацию о последней версии...\n" ;;
        en:latest_ver)  str=" Latest version: %s\n" ;;
        ru:latest_ver)  str=" Последняя версия: %s\n" ;;
        en:ver_fail)    str=" - Could not get version from GitHub\n" ;;
        ru:ver_fail)    str=" - Не удалось получить версию с GitHub\n" ;;
        en:port_prompt) str="\n Default port: 8090. Change? " ;;
        ru:port_prompt) str="\n Порт по умолчанию: 8090. Изменить? " ;;
        en:port_enter)  str=" Enter port (1024-65535): " ;;
        ru:port_enter)  str=" Введите порт (1024-65535): " ;;
        en:port_bad)    str=" - Invalid port, using 8090\n" ;;
        ru:port_bad)    str=" - Некорректный порт, используется 8090\n" ;;
        en:auth_prompt) str=" Enable HTTP authorization? " ;;
        ru:auth_prompt) str=" Включить HTTP-авторизацию? " ;;
        en:auth_user)   str=" Username: " ;;
        ru:auth_user)   str=" Пользователь: " ;;
        en:auth_pass)   str=" Password: " ;;
        ru:auth_pass)   str=" Пароль: " ;;
        en:auth_saved)  str=" - Credentials saved\n" ;;
        ru:auth_saved)  str=" - Учётные данные сохранены\n" ;;
        en:autoupd_prompt) str="\n Enable auto-update? (weekly, ~70 MB traffic)\n $(colorize yellow "Not recommended if less than 150 MB free in /opt.")\n Enable? " ;;
        ru:autoupd_prompt) str="\n Включить автообновление? (раз в неделю, ~70 МБ трафика)\n $(colorize yellow "Не рекомендуется если в /opt менее 150 МБ свободно.")\n Включить? " ;;
        en:autoupd_on)  str=" ✓ Auto-update enabled (Sunday 04:00)\n" ;;
        ru:autoupd_on)  str=" ✓ Автообновление включено (воскресенье 04:00)\n" ;;
        en:installed_ok) str=" ✓ TorrServer %s installed and $(colorize green RUNNING)\n" ;;
        ru:installed_ok) str=" ✓ TorrServer %s установлен и $(colorize green ЗАПУЩЕН)\n" ;;
        en:installed_no_start) str=" $(colorize yellow !) TorrServer %s installed but did not start\n   Check: logread | grep torrserver\n" ;;
        ru:installed_no_start) str=" $(colorize yellow !) TorrServer %s установлен, но не запустился\n   Проверьте: logread | grep torrserver\n" ;;
        en:webui)       str=" Web UI: $(colorize cyan "http://%s:%s")\n" ;;
        ru:webui)       str=" Веб-интерфейс: $(colorize cyan "http://%s:%s")\n" ;;
        en:login_pass)  str=" Login: %s  Password: %s\n" ;;
        ru:login_pass)  str=" Логин: %s  Пароль: %s\n" ;;
        # --- обновление ---
        en:update_checking) str=" Fetching latest version info...\n" ;;
        ru:update_checking) str=" Получаем информацию о последней версии...\n" ;;
        en:update_cur_latest) str=" Installed: $(colorize cyan "%s") | Latest: $(colorize green "%s")\n" ;;
        ru:update_cur_latest) str=" Установлена: $(colorize cyan "%s") | Последняя: $(colorize green "%s")\n" ;;
        en:update_ok)   str=" ✓ Already up to date\n" ;;
        ru:update_ok)   str=" ✓ Уже установлена последняя версия\n" ;;
        en:stopping)    str=" Stopping service...\n" ;;
        ru:stopping)    str=" Останавливаем службу...\n" ;;
        en:rollback)    str=" - Rolling back, starting old version\n" ;;
        ru:rollback)    str=" - Откатываемся, запускаем старую версию\n" ;;
        en:updated_ok)  str=" ✓ TorrServer updated to %s and $(colorize green RUNNING)\n" ;;
        ru:updated_ok)  str=" ✓ TorrServer обновлён до %s и $(colorize green ЗАПУЩЕН)\n" ;;
        en:updated_no_start) str=" $(colorize yellow !) Updated to %s but did not start — check: logread | grep torrserver\n" ;;
        ru:updated_no_start) str=" $(colorize yellow !) Обновлён до %s, но не запустился — проверьте: logread | grep torrserver\n" ;;
        # --- загрузка ---
        en:downloading) str=" Downloading TorrServer %s (%s)...\n" ;;
        ru:downloading) str=" Загружаем TorrServer %s (%s)...\n" ;;
        en:dl_fail)     str=" - Download error!\n" ;;
        ru:dl_fail)     str=" - Ошибка загрузки!\n" ;;
        en:dl_small)    str=" - File too small (%s bytes) — architecture may be unavailable\n" ;;
        ru:dl_small)    str=" - Файл слишком мал (%s байт) — возможно архитектура недоступна\n" ;;
        en:dl_done)     str=" - Download complete\n" ;;
        ru:dl_done)     str=" - Загрузка завершена\n" ;;
        # --- статус ---
        en:status_title) str="=============================================================\n TorrServer Status\n=============================================================\n" ;;
        ru:status_title) str="=============================================================\n Статус TorrServer\n=============================================================\n" ;;
        en:not_installed) str=" State:      $(colorize red NOT INSTALLED)\n\n" ;;
        ru:not_installed) str=" Состояние:  $(colorize red НЕ УСТАНОВЛЕН)\n\n" ;;
        en:s_version)   str=" Version:    $(colorize cyan "%s")\n" ;;
        ru:s_version)   str=" Версия:     $(colorize cyan "%s")\n" ;;
        en:s_binary)    str=" Binary:     TorrServer-%s\n" ;;
        ru:s_binary)    str=" Бинарь:     TorrServer-%s\n" ;;
        en:s_running)   str=" Service:    $(colorize green RUNNING)\n" ;;
        ru:s_running)   str=" Служба:     $(colorize green ЗАПУЩЕНА)\n" ;;
        en:s_stopped)   str=" Service:    $(colorize red STOPPED)\n" ;;
        ru:s_stopped)   str=" Служба:     $(colorize red ОСТАНОВЛЕНА)\n" ;;
        en:s_address)   str=" Address:    $(colorize green "http://%s:%s")\n" ;;
        ru:s_address)   str=" Адрес:      $(colorize green "http://%s:%s")\n" ;;
        en:s_address_off) str=" Address:    http://%s:%s\n" ;;
        ru:s_address_off) str=" Адрес:      http://%s:%s\n" ;;
        en:s_uptime)    str=" Uptime:     %dh %dm %ds\n" ;;
        ru:s_uptime)    str=" Uptime:     %dч %dм %dс\n" ;;
        en:s_auth_on)   str=" Auth:       $(colorize yellow ON)\n" ;;
        ru:s_auth_on)   str=" Авториз.:   $(colorize yellow ВКЛ)\n" ;;
        en:s_auth_off)  str=" Auth:       $(colorize cyan OFF)\n" ;;
        ru:s_auth_off)  str=" Авториз.:   $(colorize cyan ВЫКЛ)\n" ;;
        en:s_auth_warn) str=" Auth:       $(colorize yellow ON) $(colorize red "(accs.db missing!")\n" ;;
        ru:s_auth_warn) str=" Авториз.:   $(colorize yellow ВКЛ) $(colorize red "(accs.db не найден!")\n" ;;
        en:s_login)     str=" Login:      %s\n" ;;
        ru:s_login)     str=" Логин:      %s\n" ;;
        en:s_password)  str=" Password:   %s\n" ;;
        ru:s_password)  str=" Пароль:     %s\n" ;;
        en:s_autoupd_on)  str=" Auto-upd:  $(colorize green ON)\n" ;;
        ru:s_autoupd_on)  str=" Автообн.:   $(colorize green ВКЛ)\n" ;;
        en:s_autoupd_off) str=" Auto-upd:  $(colorize cyan OFF)\n" ;;
        ru:s_autoupd_off) str=" Автообн.:   $(colorize cyan ВЫКЛ)\n" ;;
        en:s_update_avail) str=" Update:    $(colorize yellow "available %s")\n" ;;
        ru:s_update_avail) str=" Обновление: $(colorize yellow "доступно %s")\n" ;;
        en:s_update_no) str=" Update:    $(colorize green "not required")\n" ;;
        ru:s_update_no) str=" Обновление: $(colorize green "не требуется")\n" ;;
        en:s_update_fail) str=" Update:    could not check\n" ;;
        ru:s_update_fail) str=" Обновление: не удалось проверить\n" ;;
        en:sep)         str="=============================================================\n" ;;
        ru:sep)         str="=============================================================\n" ;;
        # --- авторизация ---
        en:auth_cur_login) str=" Current login: %s\n" ;;
        ru:auth_cur_login) str=" Текущий логин: %s\n" ;;
        en:auth_menu)   str="\n Options:\n  1 — change login/password\n  2 — disable authorization\n  3 — enable authorization\n  0 — cancel\n" ;;
        ru:auth_menu)   str="\n Варианты:\n  1 — сменить логин/пароль\n  2 — отключить авторизацию\n  3 — включить авторизацию\n  0 — отмена\n" ;;
        en:auth_new_login) str=" New login: " ;;
        ru:auth_new_login) str=" Новый логин: " ;;
        en:auth_new_pass) str=" New password: " ;;
        ru:auth_new_pass) str=" Новый пароль: " ;;
        en:auth_updated) str=" - Credentials updated\n" ;;
        ru:auth_updated) str=" - Учётные данные обновлены\n" ;;
        en:auth_disabled) str=" - Authorization disabled\n" ;;
        ru:auth_disabled) str=" - Авторизация отключена\n" ;;
        en:auth_enabled) str=" - Authorization enabled\n" ;;
        ru:auth_enabled) str=" - Авторизация включена\n" ;;
        en:restarting)  str=" Restarting service...\n" ;;
        ru:restarting)  str=" Перезапускаем службу...\n" ;;
        en:settings_applied) str=" ✓ Settings applied, TorrServer $(colorize green RUNNING)\n" ;;
        ru:settings_applied) str=" ✓ Настройки применены, TorrServer $(colorize green ЗАПУЩЕН)\n" ;;
        en:start_fail)  str=" $(colorize yellow !) TorrServer did not start — check: logread | grep torrserver\n" ;;
        ru:start_fail)  str=" $(colorize yellow !) TorrServer не запустился — проверьте: logread | grep torrserver\n" ;;
        # --- порт ---
        en:port_cur)    str=" Current port: %s\n" ;;
        ru:port_cur)    str=" Текущий порт: %s\n" ;;
        en:port_new)    str=" New port (1024-65535): " ;;
        ru:port_new)    str=" Новый порт (1024-65535): " ;;
        en:port_invalid) str=" - Invalid port\n" ;;
        ru:port_invalid) str=" - Некорректный порт\n" ;;
        en:port_changed) str=" ✓ Port changed. New address: $(colorize cyan "http://%s:%s")\n" ;;
        ru:port_changed) str=" ✓ Порт изменён. Новый адрес: $(colorize cyan "http://%s:%s")\n" ;;
        # --- автообновление ---
        en:autoupd_already) str=" Auto-update already configured (weekly, Sunday 04:00).\n" ;;
        ru:autoupd_already) str=" Автообновление уже настроено (еженедельно по воскресеньям в 04:00).\n" ;;
        en:autoupd_disable) str=" Disable? " ;;
        ru:autoupd_disable) str=" Отключить? " ;;
        en:autoupd_off) str=" ✓ Auto-update disabled\n" ;;
        ru:autoupd_off) str=" ✓ Автообновление отключено\n" ;;
        en:autoupd_info) str="\n Auto-update runs weekly (Sunday, 04:00).\n TorrServer updates rarely — daily checks would be excessive.\n Log: /var/log/torrserver-update.log\n\n $(colorize yellow WARNING) Each update downloads ~70 MB.\n If less than 150 MB free in /opt — update manually: sh %s -u\n\n Enable auto-update? " ;;
        ru:autoupd_info) str="\n Автообновление запускается раз в неделю (воскресенье, 04:00).\n TorrServer обновляется редко, ежедневная проверка избыточна.\n Лог: /var/log/torrserver-update.log\n\n $(colorize yellow ВНИМАНИЕ) При обновлении скачивается ~70 МБ.\n Если в /opt менее 150 МБ — обновляйте вручную: sh %s -u\n\n Включить автообновление? " ;;
        en:autoupd_enabled) str=" ✓ Auto-update enabled (weekly, Sunday 04:00)\n" ;;
        ru:autoupd_enabled) str=" ✓ Автообновление включено (еженедельно, воскресенье 04:00)\n" ;;
        # --- перезапуск ---
        en:restart_svc) str=" Restarting TorrServer...\n" ;;
        ru:restart_svc) str=" Перезапускаем TorrServer...\n" ;;
        en:svc_running) str=" ✓ TorrServer $(colorize green RUNNING)\n" ;;
        ru:svc_running) str=" ✓ TorrServer $(colorize green ЗАПУЩЕН)\n" ;;
        # --- удаление ---
        en:remove_warn) str=" $(colorize red WARNING) All data including torrent database will be deleted!\n" ;;
        ru:remove_warn) str=" $(colorize red ВНИМАНИЕ) Будут удалены все данные включая базу торрентов!\n" ;;
        en:remove_sure) str=" Are you sure? " ;;
        ru:remove_sure) str=" Вы уверены? " ;;
        en:removed_ok)  str=" ✓ TorrServer removed\n\n" ;;
        ru:removed_ok)  str=" ✓ TorrServer удалён\n\n" ;;
        en:not_installed_err) str=" TorrServer is not installed.\n" ;;
        ru:not_installed_err) str=" TorrServer не установлен.\n" ;;
        # --- disk ---
        en:disk_warn)   str=" $(colorize yellow WARN) Only %s MB available, minimum %s MB recommended\n" ;;
        ru:disk_warn)   str=" $(colorize yellow WARN) Доступно только %s МБ, рекомендуется минимум %s МБ\n" ;;
        en:disk_cont)   str=" Continue? " ;;
        ru:disk_cont)   str=" Продолжить? " ;;
        # --- пользователь ---
        en:user_exists) str=" - User %s already exists\n" ;;
        ru:user_exists) str=" - Пользователь %s уже существует\n" ;;
        en:user_added)  str=" - User %s added\n" ;;
        ru:user_added)  str=" - Пользователь %s добавлен\n" ;;
        en:user_root)   str=" - Could not create user %s, running as root\n" ;;
        ru:user_root)   str=" - Не удалось создать пользователя %s, запускаем от root\n" ;;
        en:user_deleted) str=" - User %s deleted\n" ;;
        ru:user_deleted) str=" - Пользователь %s удалён\n" ;;
        # --- меню при установленном ---
        en:already_installed) str="=============================================================\n TorrServer is already installed\n=============================================================\n" ;;
        ru:already_installed) str="=============================================================\n TorrServer уже установлен\n=============================================================\n" ;;
        en:mgmt_menu)   str=" What to do?\n  $(colorize yellow u) — update to latest version\n  $(colorize yellow p) — change port\n  $(colorize yellow a) — configure authorization\n  $(colorize yellow c) — auto-update (cron)\n  $(colorize green  r) — restart service\n  $(colorize red    d) — remove TorrServer\n  $(colorize cyan   l) — change language\n  $(colorize cyan   n) — back\n" ;;
        ru:mgmt_menu)   str=" Что сделать?\n  $(colorize yellow u) — обновить до последней версии\n  $(colorize yellow p) — сменить порт\n  $(colorize yellow a) — настроить авторизацию\n  $(colorize yellow c) — автообновление (cron)\n  $(colorize green  r) — перезапустить службу\n  $(colorize red    d) — удалить TorrServer\n  $(colorize cyan   l) — сменить язык\n  $(colorize cyan   n) — назад\n" ;;
        en:mgmt_hint)   str=" Enter u, p, a, c, r, d, l or n\n" ;;
        ru:mgmt_hint)   str=" Введите u, p, a, c, r, d, l или n\n" ;;
        # --- главное меню ---
        en:main_version) str=" Version: %s\n" ;;
        ru:main_version) str=" Версия:  %s\n" ;;
        en:main_running) str=" Service: $(colorize green RUNNING)\n" ;;
        ru:main_running) str=" Служба:  $(colorize green ЗАПУЩЕНА)\n" ;;
        en:main_stopped) str=" Service: $(colorize red STOPPED)\n" ;;
        ru:main_stopped) str=" Служба:  $(colorize red ОСТАНОВЛЕНА)\n" ;;
        en:main_menu)   str="  $(colorize green  i) — install / update\n  $(colorize cyan   s) — status\n  $(colorize yellow p) — change port\n  $(colorize yellow a) — configure authorization\n  $(colorize cyan   c) — auto-update (cron)\n  $(colorize green  r) — restart service\n  $(colorize red    d) — remove\n  $(colorize cyan   l) — change language\n  $(colorize yellow n) — exit\n" ;;
        ru:main_menu)   str="  $(colorize green  i) — установить / обновить\n  $(colorize cyan   s) — статус\n  $(colorize yellow p) — сменить порт\n  $(colorize yellow a) — настроить авторизацию\n  $(colorize cyan   c) — автообновление (cron)\n  $(colorize green  r) — перезапустить службу\n  $(colorize red    d) — удалить\n  $(colorize cyan   l) — сменить язык\n  $(colorize yellow n) — выйти\n" ;;
        en:main_hint)   str=" Enter i, s, p, a, c, r, d, l or n\n" ;;
        ru:main_hint)   str=" Введите i, s, p, a, c, r, d, l или n\n" ;;
        # --- справка ---
        en:help_usage)  str="Usage: %s [command] [flags]\n\nCommands:\n  %-30s %s\n  %-30s %s\n  %-30s %s\n  %-30s %s\n  %-30s %s\n\nFlags:\n  %-30s %s\n  %-30s %s\n" ;;
        ru:help_usage)  str="Использование: %s [команда] [флаги]\n\nКоманды:\n  %-30s %s\n  %-30s %s\n  %-30s %s\n  %-30s %s\n  %-30s %s\n\nФлаги:\n  %-30s %s\n  %-30s %s\n" ;;
        en:unknown_cmd) str=" Unknown command: %s\n" ;;
        ru:unknown_cmd) str=" Неизвестная команда: %s\n" ;;
        en:good_luck)   str=" Good luck!\n\n" ;;
        ru:good_luck)   str=" Удачи!\n\n" ;;
        # --- платформа ---
        en:os_detected) str=" Platform: %s\n" ;;
        ru:os_detected) str=" Платформа: %s\n" ;;
        en:os_unknown)  str=" $(colorize yellow WARN) Unknown platform, trying generic Linux init\n" ;;
        ru:os_unknown)  str=" $(colorize yellow WARN) Неизвестная платформа, пробуем стандартный Linux init\n" ;;
        en:svc_enabled) str=" - Service enabled and started\n" ;;
        ru:svc_enabled) str=" - Служба включена и запущена\n" ;;
        en:log_hint_systemd) str=" Logs: journalctl -u torrserver -f\n" ;;
        ru:log_hint_systemd) str=" Логи: journalctl -u torrserver -f\n" ;;
        en:log_hint_openwrt) str=" Logs: logread | grep torrserver\n" ;;
        ru:log_hint_openwrt) str=" Логи: logread | grep torrserver\n" ;;
        *) str="[?:${key}]" ;;
    esac
    # shellcheck disable=SC2059
    printf "$str" "$@"
}

# ============================================================
# СИСТЕМНЫЕ ФУНКЦИИ
# ============================================================

isRoot() { [ "$(id -u)" -eq 0 ]; }

detectArch() {
    case "$(uname -m)" in
        x86_64)          echo "linux-amd64" ;;
        aarch64|arm64)   echo "linux-arm64" ;;
        armv7*|armv6*)   echo "linux-arm7" ;;
        armv5*)          echo "linux-arm5" ;;
        mips64*)         echo "linux-mips64" ;;
        mipsel|mipsle)   echo "linux-mipsle" ;;
        mips*)           echo "linux-mips" ;;
        i686|i386)       echo "linux-386" ;;
        riscv64)         echo "linux-riscv64" ;;
        *)               echo ""; return 1 ;;
    esac
}

addUser() {
    [ "$username" = "root" ] && return 0
    if grep -q "^$username:" /etc/passwd 2>/dev/null; then
        t user_exists "$username"; return 0
    fi
    case "$OS_TYPE" in
        openwrt|alpine)
            local group="nogroup"
            grep -q "^nogroup:" /etc/group 2>/dev/null || group="nobody"
            adduser -D -H -h "$dirInstall" -s /bin/false -G "$group" "$username" 2>/dev/null
            ;;
        debian|arch|rhel|suse|*)
            useradd -r -s /bin/false -d "$dirInstall" -M "$username" 2>/dev/null
            ;;
    esac
    if grep -q "^$username:" /etc/passwd 2>/dev/null; then
        chmod 755 "$dirInstall"
        t user_added "$username"
    else
        t user_root "$username"
        username="root"
    fi
}

delUser() {
    [ "$username" = "root" ] && return 0
    grep -q "^$username:" /etc/passwd 2>/dev/null || return 0
    case "$OS_TYPE" in
        openwrt|alpine) deluser "$username" 2>/dev/null ;;
        *)              userdel "$username" 2>/dev/null ;;
    esac
    t user_deleted "$username"
}

getIP() {
    local iface
    iface=$(ip route show default 2>/dev/null | awk '/default/{print $5; exit}')
    if [ -n "$iface" ]; then
        ip addr show dev "$iface" 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1
    else
        ip addr 2>/dev/null | awk '/inet /{print $2}' | grep -v '^127\.' | cut -d/ -f1 | head -n1
    fi
}

getLatestRelease() {
    curl -sf --max-time 15 "https://api.github.com/repos/YouROK/TorrServer/releases/latest" \
        | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

getInstalledVersion() {
    [ -f "$dirInstall/version" ] && cat "$dirInstall/version" || echo "unknown"
}

getInstalledArch() {
    if [ -f "$dirInstall/binary" ]; then
        local b; b=$(cat "$dirInstall/binary"); echo "${b#TorrServer-}"
    else
        detectArch
    fi
}

getServicePort() {
    local f=""
    if [ "$OS_TYPE" = "openwrt" ] || [ "$OS_TYPE" = "alpine" ]; then
        f="/etc/init.d/$serviceName"
    elif hasSystemd; then
        f="/etc/systemd/system/${serviceName}.service"
    fi
    [ -f "$f" ] && grep -o '\-\-port [0-9]*' "$f" 2>/dev/null | awk '{print $2}' | head -1
}

getAuthCredentials() {
    local accsFile="$dirInstall/accs.db"
    [ ! -f "$accsFile" ] && return
    local user pass
    user=$(grep -o '"[^"]*"' "$accsFile" | sed -n '1p' | tr -d '"')
    pass=$(grep -o '"[^"]*"' "$accsFile" | sed -n '2p' | tr -d '"')
    [ -n "$user" ] && [ -n "$pass" ] && printf "%s:%s" "$user" "$pass"
}

isAuthEnabled() {
    local f=""
    if [ "$OS_TYPE" = "openwrt" ] || [ "$OS_TYPE" = "alpine" ]; then
        f="/etc/init.d/$serviceName"
    elif hasSystemd; then
        f="/etc/systemd/system/${serviceName}.service"
    fi
    [ -f "$f" ] && grep -q '\-\-httpauth' "$f" 2>/dev/null
}

checkInstalled() {
    local bin=""
    if [ -f "$dirInstall/binary" ]; then
        bin="$dirInstall/$(cat "$dirInstall/binary")"
    else
        local arch; arch=$(detectArch)
        [ -n "$arch" ] && bin="$dirInstall/TorrServer-${arch}"
    fi
    [ -n "$bin" ] && [ -f "$bin" ]
}

checkDiskSpace() {
    local required=80 available
    available=$(df "$dirInstall" 2>/dev/null | awk 'NR==2{print int($4/1024)}')
    if [ -z "$available" ]; then
        available=$(df /opt 2>/dev/null | awk 'NR==2{print int($4/1024)}')
        [ -z "$available" ] && available=$(df / | awk 'NR==2{print int($4/1024)}')
    fi
    if [ "$available" -lt "$required" ] 2>/dev/null; then
        t disk_warn "$available" "$required"
        printf " "; t disk_cont; t yes_no
        read -r ans </dev/tty
        [ "$ans" != "${ans#[YyДд]}" ] || exit 1
    fi
}

checkInternet() {
    t checking_inet
    if ! curl -sf --max-time 10 "https://api.github.com" >/dev/null 2>&1; then
        t inet_fail; exit 1
    fi
    t inet_ok
}

initialCheck() {
    if ! isRoot; then t requires_root "$scriptname"; exit 1; fi
    checkInternet
}

isRunning() {
    local arch; arch=$(getInstalledArch)
    if [ "$OS_TYPE" = "openwrt" ] || ! hasSystemd; then
        pidof "TorrServer-${arch}" >/dev/null 2>&1
    else
        systemctl is-active --quiet "$serviceName" 2>/dev/null
    fi
}

printLogo() {
    if [ "$NO_COLOR" -eq 0 ]; then printf "${RED}"; fi
    printf "  ████████╗ ██████╗ ██████╗ ██████╗ \n"
    printf "     ██╔══╝██╔═══██╗██╔══██╗██╔══██╗\n"
    printf "     ██║   ██║   ██║██████╔╝██████╔╝\n"
    printf "     ██║   ██║   ██║██╔══██╗██╔══██╗\n"
    printf "     ██║   ╚██████╔╝██║  ██║██║  ██║\n"
    printf "     ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝\n"
    if [ "$NO_COLOR" -eq 0 ]; then printf "${BLUE}"; fi
    printf "  ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗ \n"
    printf "  ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗\n"
    printf "  ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝\n"
    printf "  ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗\n"
    printf "  ███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║\n"
    printf "  ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝\n"
    if [ "$NO_COLOR" -eq 0 ]; then printf "${NC}"; fi
    t logo_sub; printf "\n\n"
}

# ============================================================
# ОСНОВНЫЕ ФУНКЦИИ
# ============================================================

helpUsage() {
    if [ "$LANG_CODE" = "en" ]; then
        printf "Usage: %s [command] [flags]\n\nCommands:\n" "$scriptname"
        printf "  %-30s %s\n" "-i | --install | install"  "install latest version"
        printf "  %-30s %s\n" "-u | --update  | update"   "update to latest version"
        printf "  %-30s %s\n" "-s | --status  | status"   "service status"
        printf "  %-30s %s\n" "-r | --remove  | remove"   "remove TorrServer"
        printf "  %-30s %s\n" "-h | --help    | help"     "this help"
        printf "\nFlags:\n"
        printf "  %-30s %s\n" "--no-color"  "output without colors (for logs/scripts)"
        printf "  %-30s %s\n" "--auto"      "automatic mode (for cron)"
    else
        printf "Использование: %s [команда] [флаги]\n\nКоманды:\n" "$scriptname"
        printf "  %-30s %s\n" "-i | --install | install"  "установка последней версии"
        printf "  %-30s %s\n" "-u | --update  | update"   "обновление до последней версии"
        printf "  %-30s %s\n" "-s | --status  | status"   "статус службы"
        printf "  %-30s %s\n" "-r | --remove  | remove"   "удаление TorrServer"
        printf "  %-30s %s\n" "-h | --help    | help"     "эта справка"
        printf "\nФлаги:\n"
        printf "  %-30s %s\n" "--no-color"  "вывод без цветов (для логов/скриптов)"
        printf "  %-30s %s\n" "--auto"      "автоматический режим (для cron)"
    fi
}

cleanup() {
    svcRemove
    rm -rf "$dirInstall"
    delUser
}

uninstall() {
    if ! checkInstalled; then t not_installed_err; return 1; fi
    printf "\n"
    printf " Directory: %s\n" "$dirInstall"
    t s_version "$(getInstalledVersion)"
    printf "\n"
    t remove_warn
    printf "\n"
    printf " "; t remove_sure; t yes_no
    read -r ans </dev/tty
    if [ "$ans" != "${ans#[YyДд]}" ]; then
        cleanup; t removed_ok
    else
        t cancelled
    fi
}

showStatus() {
    printf "\n"; t status_title
    if ! checkInstalled; then t not_installed; return; fi

    local version arch port ip
    version=$(getInstalledVersion)
    arch=$(getInstalledArch)
    port=$(getServicePort)
    ip=$(getIP)
    [ -z "$port" ] && port="8090"
    [ -z "$ip" ]   && ip="<unknown>"

    t s_version "$version"
    t s_binary "$arch"

    if isRunning; then
        t s_running
        t s_address "$ip" "$port"
        local pid
        pid=$(pidof "TorrServer-${arch}" 2>/dev/null | awk '{print $1}')
        if [ -n "$pid" ] && [ -f "/proc/$pid/stat" ]; then
            local ticks uptime_sec hz start_sec running_sec h m s
            ticks=$(awk '{print $22}' /proc/$pid/stat 2>/dev/null)
            uptime_sec=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
            hz=$(getconf CLK_TCK 2>/dev/null || echo 100)
            if [ -n "$ticks" ] && [ -n "$uptime_sec" ]; then
                start_sec=$((ticks / hz))
                running_sec=$((uptime_sec - start_sec))
                if [ "$running_sec" -gt 0 ] 2>/dev/null; then
                    h=$((running_sec / 3600))
                    m=$(((running_sec % 3600) / 60))
                    s=$((running_sec % 60))
                    t s_uptime "$h" "$m" "$s"
                fi
            fi
        fi
    else
        t s_stopped
        t s_address_off "$ip" "$port"
    fi

    if isAuthEnabled; then
        local creds authUser authPass
        creds=$(getAuthCredentials)
        if [ -n "$creds" ]; then
            authUser="${creds%%:*}"; authPass="${creds#*:}"
            t s_auth_on
            t s_login "$authUser"
            t s_password "$authPass"
        else
            t s_auth_warn
        fi
    else
        t s_auth_off
    fi

    if crontab -l 2>/dev/null | grep -q "torrserver.*update\|update.*torrserver"; then
        t s_autoupd_on
    else
        t s_autoupd_off
    fi

    printf " "; t s_update_avail ""
    local latest
    latest=$(getLatestRelease)
    if [ -n "$latest" ] && [ "$latest" != "$version" ]; then
        t s_update_avail "$latest"
    elif [ -n "$latest" ]; then
        t s_update_no
    else
        t s_update_fail
    fi

    t sep; printf "\n"
}

downloadTorrServer() {
    local version="$1" arch="$2"
    local binName="TorrServer-${arch}"
    local urlBin="https://github.com/YouROK/TorrServer/releases/download/${version}/${binName}"
    local tmpFile="$dirInstall/${binName}.tmp"

    # Проверяем свободное место перед скачиванием
    # При обновлении оба файла существуют одновременно → нужно ~160 МБ
    local required=160
    local existing=0
    [ -f "$dirInstall/$binName" ] && existing=$(du -m "$dirInstall/$binName" 2>/dev/null | awk '{print $1}')
    [ "$existing" -eq 0 ] 2>/dev/null && required=80
    local available
    available=$(df "$dirInstall" 2>/dev/null | awk 'NR==2{print int($4/1024)}')
    [ -z "$available" ] && available=$(df /opt 2>/dev/null | awk 'NR==2{print int($4/1024)}')
    [ -z "$available" ] && available=$(df / | awk 'NR==2{print int($4/1024)}')

    if [ "$available" -lt "$required" ] 2>/dev/null; then
        printf "\n"
        t disk_warn "$available" "$required"
        if [ "$existing" -gt 0 ]; then
            if [ "$LANG_CODE" = "en" ]; then
                printf " $(colorize yellow TIP) Remove old binary first to free ~%s MB? " "$existing"
            else
                printf " $(colorize yellow СОВЕТ) Удалить старый бинарь чтобы освободить ~%s МБ? " "$existing"
            fi
            t yes_no
            read -r ans </dev/tty
            if [ "$ans" != "${ans#[YyДд]}" ]; then
                # Сохраняем версию удаляемого бинаря на случай провала скачивания
                local savedVersion
                savedVersion=$(getInstalledVersion)
                printf "%s" "$savedVersion" > "$dirInstall/version.bak"

                rm -f "$dirInstall/$binName"
                if [ "$LANG_CODE" = "en" ]; then
                    printf " - Old binary removed, proceeding...\n"
                else
                    printf " - Старый бинарь удалён, продолжаем...\n"
                fi
                available=$(df "$dirInstall" 2>/dev/null | awk 'NR==2{print int($4/1024)}')
                if [ "$available" -lt 80 ] 2>/dev/null; then
                    t disk_warn "$available" "80"
                    t dl_fail; return 1
                fi
            else
                t dl_fail; return 1
            fi
        else
            t dl_fail; return 1
        fi
    fi

    t downloading "$version" "$arch"
    if ! curl -L --progress-bar -o "$tmpFile" "$urlBin"; then
        t dl_fail
        rm -f "$tmpFile"
        # Бинарь был удалён для освобождения места — пробуем восстановить
        _recoverBinary "$arch"
        return 1
    fi
    local filesize
    filesize=$(wc -c < "$tmpFile" 2>/dev/null || echo 0)
    if [ "$filesize" -lt 1000000 ]; then
        t dl_small "$filesize"
        rm -f "$tmpFile"
        _recoverBinary "$arch"
        return 1
    fi
    chmod +x "$tmpFile"
    mv -f "$tmpFile" "$dirInstall/$binName"
    printf "%s" "$version" > "$dirInstall/version"
    printf "%s" "$binName" > "$dirInstall/binary"
    rm -f "$dirInstall/version.bak"
    t dl_done
}

# Попытка восстановить бинарь после неудачного скачивания
_recoverBinary() {
    local arch="$1"
    local binName="TorrServer-${arch}"
    local bakVersion=""

    # Проверяем есть ли сохранённая версия (значит бинарь был удалён)
    [ -f "$dirInstall/version.bak" ] || return 0
    bakVersion=$(cat "$dirInstall/version.bak")
    [ -z "$bakVersion" ] && return 0

    if [ "$LANG_CODE" = "en" ]; then
        printf "\n $(colorize red "!") Binary was removed and download failed — system is broken!\n"
        printf "   Attempting to restore version %s...\n" "$bakVersion"
    else
        printf "\n $(colorize red "!") Бинарь был удалён, а скачивание прервалось — система не работает!\n"
        printf "   Пытаемся восстановить версию %s...\n" "$bakVersion"
    fi

    local urlBin="https://github.com/YouROK/TorrServer/releases/download/${bakVersion}/${binName}"
    local tmpFile="$dirInstall/${binName}.tmp"

    if curl -L --progress-bar -o "$tmpFile" "$urlBin" 2>/dev/null; then
        local filesize
        filesize=$(wc -c < "$tmpFile" 2>/dev/null || echo 0)
        if [ "$filesize" -ge 1000000 ]; then
            chmod +x "$tmpFile"
            mv -f "$tmpFile" "$dirInstall/$binName"
            printf "%s" "$bakVersion" > "$dirInstall/version"
            printf "%s" "$binName" > "$dirInstall/binary"
            rm -f "$dirInstall/version.bak"
            svcStart 2>/dev/null
            if [ "$LANG_CODE" = "en" ]; then
                printf " ✓ Restored version %s — service started\n" "$bakVersion"
            else
                printf " ✓ Восстановлена версия %s — служба запущена\n" "$bakVersion"
            fi
            return 0
        fi
    fi

    rm -f "$tmpFile"
    rm -f "$dirInstall/version.bak"
    if [ "$LANG_CODE" = "en" ]; then
        printf " $(colorize red "✗") Recovery failed. To reinstall run:\n"
        printf "   sh %s -i\n\n" "$scriptname"
    else
        printf " $(colorize red "✗") Восстановление не удалось. Для переустановки выполните:\n"
        printf "   sh %s -i\n\n" "$scriptname"
    fi
}

writeInitScript() {
    local binName="$1" authOptions="$2"

    if [ "$OS_TYPE" = "openwrt" ]; then
        # procd init script
        cat > /etc/init.d/$serviceName << EOF
#!/bin/sh /etc/rc.common

START=99
STOP=10

USE_PROCD=1
PROG="$dirInstall/$binName"

start_service() {
    procd_open_instance
    procd_set_param command \$PROG $authOptions
    procd_set_param respawn \${respawn_threshold:-3600} \${respawn_timeout:-5} \${respawn_retry:-5}
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    killall "$binName" 2>/dev/null
    return 0
}

reload_service() {
    stop; sleep 1; start
}
EOF
        chmod +x /etc/init.d/$serviceName

    elif hasSystemd; then
        # systemd service
        cat > /etc/systemd/system/${serviceName}.service << EOF
[Unit]
Description=TorrServer — torrent streaming server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$username
ExecStart=$dirInstall/$binName $authOptions
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload

    elif [ "$OS_TYPE" = "alpine" ]; then
        # OpenRC init script
        cat > /etc/init.d/$serviceName << EOF
#!/sbin/openrc-run

description="TorrServer — torrent streaming server"
command="$dirInstall/$binName"
command_args="$authOptions"
command_user="$username"
pidfile="/run/\${RC_SVCNAME}.pid"
command_background=true
output_log="/var/log/torrserver.log"
error_log="/var/log/torrserver.log"

depend() {
    need net
}
EOF
        chmod +x /etc/init.d/$serviceName
    fi
}

svcEnable() {
    if [ "$OS_TYPE" = "openwrt" ]; then
        /etc/init.d/$serviceName enable
    elif hasSystemd; then
        systemctl enable "$serviceName" 2>/dev/null
    elif [ "$OS_TYPE" = "alpine" ]; then
        rc-update add "$serviceName" default 2>/dev/null
    fi
}

svcDisable() {
    if [ "$OS_TYPE" = "openwrt" ]; then
        /etc/init.d/$serviceName disable 2>/dev/null
    elif hasSystemd; then
        systemctl disable "$serviceName" 2>/dev/null
    elif [ "$OS_TYPE" = "alpine" ]; then
        rc-update del "$serviceName" default 2>/dev/null
    fi
}

svcStart() {
    if [ "$OS_TYPE" = "openwrt" ]; then
        /etc/init.d/$serviceName start
    elif hasSystemd; then
        systemctl start "$serviceName"
    elif [ "$OS_TYPE" = "alpine" ]; then
        rc-service "$serviceName" start
    else
        local arch; arch=$(getInstalledArch)
        local port; port=$(getServicePort); [ -z "$port" ] && port="8090"
        "$dirInstall/TorrServer-${arch}" --port "$port" --path "$dirInstall" &
    fi
}

svcStop() {
    if [ "$OS_TYPE" = "openwrt" ]; then
        /etc/init.d/$serviceName stop 2>/dev/null
    elif hasSystemd; then
        systemctl stop "$serviceName" 2>/dev/null
    elif [ "$OS_TYPE" = "alpine" ]; then
        rc-service "$serviceName" stop 2>/dev/null
    else
        local arch; arch=$(getInstalledArch)
        killall "TorrServer-${arch}" 2>/dev/null
    fi
}

svcRestart() {
    if [ "$OS_TYPE" = "openwrt" ]; then
        /etc/init.d/$serviceName restart 2>/dev/null
    elif hasSystemd; then
        systemctl restart "$serviceName"
    elif [ "$OS_TYPE" = "alpine" ]; then
        rc-service "$serviceName" restart
    else
        svcStop; sleep 1; svcStart
    fi
}

svcRemove() {
    svcStop
    svcDisable
    if [ "$OS_TYPE" = "openwrt" ]; then
        rm -f /etc/init.d/$serviceName
    elif hasSystemd; then
        rm -f /etc/systemd/system/${serviceName}.service
        systemctl daemon-reload 2>/dev/null
    elif [ "$OS_TYPE" = "alpine" ]; then
        rm -f /etc/init.d/$serviceName
    fi
}

logHint() {
    if [ "$OS_TYPE" = "openwrt" ]; then
        t log_hint_openwrt
    else
        t log_hint_systemd
    fi
}

changeAuth() {
    if ! checkInstalled; then t not_installed_err; return 1; fi
    local port; port=$(getServicePort); [ -z "$port" ] && port="8090"
    local creds; creds=$(getAuthCredentials)
    if [ -n "$creds" ]; then t auth_cur_login "${creds%%:*}"; fi
    t auth_menu
    printf " "; t port_enter 2>/dev/null; printf "$(t port_cur 2>/dev/null)" 2>/dev/null
    if [ "$LANG_CODE" = "en" ]; then printf " Choice: "; else printf " Выбор: "; fi
    read -r auth_choice </dev/tty

    local newUser newPass authOptions
    case $auth_choice in
        1)
            t auth_new_login; read -r newUser </dev/tty
            t auth_new_pass; read -r newPass </dev/tty
            printf '{\n  "%s": "%s"\n}\n' "$newUser" "$newPass" > "$dirInstall/accs.db"
            chmod 600 "$dirInstall/accs.db"
            authOptions="--port $port --path $dirInstall --httpauth"
            t auth_updated ;;
        2)
            rm -f "$dirInstall/accs.db"
            authOptions="--port $port --path $dirInstall"
            t auth_disabled ;;
        3)
            t auth_user; read -r newUser </dev/tty
            t auth_pass; read -r newPass </dev/tty
            printf '{\n  "%s": "%s"\n}\n' "$newUser" "$newPass" > "$dirInstall/accs.db"
            chmod 600 "$dirInstall/accs.db"
            authOptions="--port $port --path $dirInstall --httpauth"
            t auth_enabled ;;
        *)
            t cancelled; return 0 ;;
    esac

    local arch binName
    arch=$(getInstalledArch); binName="TorrServer-${arch}"
    writeInitScript "$binName" "$authOptions"
    t restarting
    svcStop; sleep 1
    svcStart; sleep 1
    if isRunning; then t settings_applied; else t start_fail; fi
}

changePort() {
    if ! checkInstalled; then t not_installed_err; return 1; fi
    local currentPort; currentPort=$(getServicePort); [ -z "$currentPort" ] && currentPort="8090"
    t port_cur "$currentPort"
    t port_new; read -r newPort </dev/tty
    if ! printf "%s" "$newPort" | grep -qE '^[0-9]+$' \
        || [ "$newPort" -lt 1024 ] || [ "$newPort" -gt 65535 ]; then
        t port_invalid; return 1
    fi
    local creds authOptions
    creds=$(getAuthCredentials)
    if isAuthEnabled; then
        authOptions="--port $newPort --path $dirInstall --httpauth"
    else
        authOptions="--port $newPort --path $dirInstall"
    fi
    local arch binName
    arch=$(getInstalledArch); binName="TorrServer-${arch}"
    writeInitScript "$binName" "$authOptions"
    t restarting
    svcStop; sleep 1
    svcStart; sleep 1
    if isRunning; then
        local ip; ip=$(getIP); [ -z "$ip" ] && ip="<IP>"
        t port_changed "$ip" "$newPort"
    else
        t start_fail
    fi
}

setupAutoupdate() {
    if ! checkInstalled; then t not_installed_err; return 1; fi
    local cronLine="0 4 * * 0 sh $(readlink -f "$0") --no-color --auto update >> /var/log/torrserver-update.log 2>&1"
    if crontab -l 2>/dev/null | grep -q "torrserver.*update\|update.*torrserver"; then
        t autoupd_already
        t autoupd_disable; t yes_no
        read -r ans </dev/tty
        if [ "$ans" != "${ans#[YyДд]}" ]; then
            local tmp="/tmp/cron_ts.tmp"
            crontab -l 2>/dev/null | grep -v "torrserver.*update\|update.*torrserver" > "$tmp"
            crontab "$tmp"; rm -f "$tmp"
            t autoupd_off
        else
            t cancelled
        fi
        return 0
    fi
    t autoupd_info "$scriptname"
    t yes_no
    read -r ans </dev/tty
    if [ "$ans" != "${ans#[YyДд]}" ]; then
        mkdir -p /etc/crontabs
        local tmp="/tmp/cron_ts.tmp"
        crontab -l 2>/dev/null > "$tmp"
        printf "%s\n" "$cronLine" >> "$tmp"
        crontab "$tmp"; rm -f "$tmp"
        /etc/init.d/cron enable 2>/dev/null
        /etc/init.d/cron start 2>/dev/null
        t autoupd_enabled
    else
        t cancelled
    fi
}

restartService() {
    t restart_svc
    svcRestart
    sleep 2
    if isRunning; then t svc_running; else t start_fail; fi
}

UpdateVersion() {
    if ! checkInstalled; then t not_installed_err; return 1; fi
    t update_checking
    local latestVersion; latestVersion=$(getLatestRelease)
    if [ -z "$latestVersion" ]; then t ver_fail; return 1; fi
    local currentVersion; currentVersion=$(getInstalledVersion)
    t update_cur_latest "$currentVersion" "$latestVersion"
    if [ "$currentVersion" = "$latestVersion" ]; then t update_ok; return 0; fi
    local arch; arch=$(getInstalledArch)
    t stopping
    svcStop; sleep 1
    killall "TorrServer-${arch}" 2>/dev/null; sleep 1
    downloadTorrServer "$latestVersion" "$arch" || {
        t rollback
        svcStart 2>/dev/null
        return 1
    }
    svcStart; sleep 2
    if isRunning; then t updated_ok "$latestVersion"
    else t updated_no_start "$latestVersion"; fi
}

installTorrServer() {
    local arch; arch=$(detectArch)
    if [ -z "$arch" ]; then
        t arch_unknown "$(uname -m)"
        t arch_enter; read -r arch </dev/tty
        [ -z "$arch" ] && exit 1
    fi

    # === Уже установлен ===
    if [ -f "$dirInstall/TorrServer-${arch}" ]; then
        local curVersion latestVersion ip port
        curVersion=$(getInstalledVersion)
        ip=$(getIP); port=$(getServicePort)
        [ -z "$port" ] && port="8090"
        [ -z "$ip" ]   && ip="<IP>"

        printf "\n"; t already_installed
        t s_version "$curVersion"
        t arch_detected "$arch"
        if isRunning; then
            t s_running; t s_address "$ip" "$port"
        else
            t s_stopped
        fi

        printf " "
        local latest; latest=$(getLatestRelease)
        if [ -n "$latest" ] && [ "$latest" != "$curVersion" ]; then
            t s_update_avail "$latest"
        else
            t s_update_no
        fi

        if isAuthEnabled; then
            local creds; creds=$(getAuthCredentials)
            if [ -n "$creds" ]; then
                t s_auth_on
                t s_login "${creds%%:*}"
                t s_password "${creds#*:}"
            else
                t s_auth_warn
            fi
        else
            t s_auth_off
        fi

        if crontab -l 2>/dev/null | grep -q "torrserver.*update\|update.*torrserver"; then
            t s_autoupd_on
        else
            t s_autoupd_off
        fi

        t sep; printf "\n"
        t mgmt_menu

        while true; do
            if [ "$LANG_CODE" = "en" ]; then printf " Choice: "; else printf " Выбор: "; fi
            read -r mgmt </dev/tty
            case $mgmt in
                [UuУу]*) initialCheck; UpdateVersion; break ;;
                [PpПп]*) changePort; break ;;
                [AaАа]*) changeAuth; break ;;
                [CcСс]*) setupAutoupdate; break ;;
                [RrРр]*) restartService; break ;;
                [DdУу]*) initialCheck; uninstall; break ;;
                [LlЯя]*) selectLanguage; break ;;
                [NnНн]*) break ;;
                *) t mgmt_hint ;;
            esac
        done
        return
    fi

    # === Свежая установка ===
    printf "\n"; t install_title; printf "\n"
    t hw_warn
    printf "\n"; t proceed; t yes_no
    read -r ans </dev/tty
    [ "$ans" != "${ans#[YyДд]}" ] || { t aborted; return 0; }
    printf "\n"
    t arch_detected "$arch"

    checkDiskSpace
    [ ! -d "$dirInstall" ] && mkdir -p "$dirInstall"

    t getting_ver
    local latestVersion; latestVersion=$(getLatestRelease)
    if [ -z "$latestVersion" ]; then t ver_fail; exit 1; fi
    t latest_ver "$latestVersion"

    downloadTorrServer "$latestVersion" "$arch" || exit 1
    addUser

    local servicePort="8090"
    t port_prompt; t yes_no
    read -r ans </dev/tty
    if [ "$ans" != "${ans#[YyДд]}" ]; then
        t port_enter; read -r ans_port </dev/tty
        if printf "%s" "$ans_port" | grep -qE '^[0-9]+$' \
            && [ "$ans_port" -ge 1024 ] && [ "$ans_port" -le 65535 ]; then
            servicePort=$ans_port
        else
            t port_bad
        fi
    fi

    local authOptions="--port $servicePort --path $dirInstall"
    local isAuthUser="" isAuthPass=""
    t auth_prompt; t yes_no
    read -r ans </dev/tty
    if [ "$ans" != "${ans#[YyДд]}" ]; then
        t auth_user; read -r isAuthUser </dev/tty
        t auth_pass; read -r isAuthPass </dev/tty
        printf '{\n  "%s": "%s"\n}\n' "$isAuthUser" "$isAuthPass" > "$dirInstall/accs.db"
        chmod 600 "$dirInstall/accs.db"
        authOptions="--port $servicePort --path $dirInstall --httpauth"
        t auth_saved
    fi

    local binName="TorrServer-${arch}"
    writeInitScript "$binName" "$authOptions"
    svcEnable
    svcStart
    sleep 2

    t autoupd_prompt; t yes_no
    read -r ans </dev/tty
    if [ "$ans" != "${ans#[YyДд]}" ]; then
        local cronLine="0 4 * * 0 sh $(readlink -f "$0") --no-color --auto update >> /var/log/torrserver-update.log 2>&1"
        mkdir -p /etc/crontabs
        local tmp="/tmp/cron_ts.tmp"
        crontab -l 2>/dev/null > "$tmp"
        printf "%s\n" "$cronLine" >> "$tmp"
        crontab "$tmp"; rm -f "$tmp"
        /etc/init.d/cron enable 2>/dev/null
        /etc/init.d/cron start 2>/dev/null
        t autoupd_on
    fi

    local serverIP; serverIP=$(getIP); [ -z "$serverIP" ] && serverIP="<IP>"
    printf "\n"; t sep
    t os_detected "$OS_NAME"
    if isRunning; then t installed_ok "$latestVersion"
    else t installed_no_start "$latestVersion"; fi
    t sep
    t webui "$serverIP" "$servicePort"
    [ -n "$isAuthUser" ] && t login_pass "$isAuthUser" "$isAuthPass"
    logHint
    printf "\n"
}

# ============================================================
# ПАРСИНГ ФЛАГОВ И ЗАПУСК
# ============================================================

ARGS=""
for arg in "$@"; do
    case "$arg" in
        --no-color) NO_COLOR=1 ;;
        --auto)     AUTO_MODE=1 ;;
        *)          ARGS="$ARGS $arg" ;;
    esac
done
ARGS="${ARGS# }"

detectOS
loadLang

case $ARGS in
    -i|--install|install) initialCheck; installTorrServer; exit ;;
    -u|--update|update)   initialCheck; UpdateVersion "$AUTO_MODE"; exit ;;
    -s|--status|status)   showStatus; exit ;;
    -r|--remove|remove)   initialCheck; uninstall; exit ;;
    -h|--help|help)       helpUsage; exit ;;
    "")                   ;;
    *) t unknown_cmd "$ARGS"; helpUsage; exit 1 ;;
esac

# Первый запуск — выбор языка если не сохранён
if [ ! -f "$LANG_FILE" ]; then
    selectLanguage
fi

# ============================================================
# ИНТЕРАКТИВНОЕ МЕНЮ
# ============================================================

printf "\n"
printLogo

if checkInstalled 2>/dev/null; then
    t main_version "$(getInstalledVersion)"
    if isRunning; then t main_running; else t main_stopped; fi
fi

printf "\n"
t main_menu
printf "\n"

while true; do
    if [ "$LANG_CODE" = "en" ]; then printf " Choice: "; else printf " Выбор: "; fi
    read -r ydn </dev/tty
    case $ydn in
        [IiИи]*) initialCheck; installTorrServer ;;
        [SsСс]*) showStatus ;;
        [PpПп]*) isRoot || { t requires_root "$scriptname"; continue; }; changePort ;;
        [AaАа]*) isRoot || { t requires_root "$scriptname"; continue; }; changeAuth ;;
        [CcСс]*) isRoot || { t requires_root "$scriptname"; continue; }; setupAutoupdate ;;
        [RrРр]*) isRoot || { t requires_root "$scriptname"; continue; }; restartService ;;
        [DdУу]*) initialCheck; uninstall; break ;;
        [LlЯя]*) selectLanguage ;;
        [NnНн]*) break ;;
        *) t main_hint ;;
    esac
done

t good_luck
