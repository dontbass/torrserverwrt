#!/bin/sh

username="torrserver"
dirInstall="/opt/torrserver"
serviceName="torrserver"
scriptname=$(basename "$0")
NO_COLOR=0

# Цвета для вывода (POSIX sh совместимо)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
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
            *)      printf "%s" "$2" ;;
        esac
    fi
}

isRoot() {
    [ "$(id -u)" -eq 0 ]
}

detectArch() {
    machine=$(uname -m)
    case "$machine" in
        x86_64)             echo "linux-amd64" ;;
        aarch64|arm64)      echo "linux-arm64" ;;
        armv7*|armv6*)      echo "linux-arm7" ;;
        armv5*)             echo "linux-arm5" ;;
        mips64*)            echo "linux-mips64" ;;
        mipsel|mipsle)      echo "linux-mipsle" ;;
        mips*)              echo "linux-mips" ;;
        i686|i386)          echo "linux-386" ;;
        riscv64)            echo "linux-riscv64" ;;
        *)                  echo ""; return 1 ;;
    esac
}

addUser() {
    [ "$username" = "root" ] && return 0
    if grep -q "^$username:" /etc/passwd 2>/dev/null; then
        printf " - Пользователь %s уже существует\n" "$username"
        return 0
    fi
    local group="nogroup"
    grep -q "^nogroup:" /etc/group 2>/dev/null || group="nobody"
    adduser -D -H -h "$dirInstall" -s /bin/false -G "$group" "$username" 2>/dev/null
    if [ $? -eq 0 ]; then
        chmod 755 "$dirInstall"
        printf " - Пользователь %s добавлен\n" "$username"
    else
        printf " - Не удалось создать пользователя %s, запускаем от root\n" "$username"
        username="root"
    fi
}

delUser() {
    [ "$username" = "root" ] && return 0
    if grep -q "^$username:" /etc/passwd 2>/dev/null; then
        deluser "$username" 2>/dev/null && \
            printf " - Пользователь %s удалён\n" "$username" || \
            printf " - Не удалось удалить пользователя %s\n" "$username"
    fi
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
        | grep '"tag_name":' \
        | sed -E 's/.*"([^"]+)".*/\1/'
}

getInstalledVersion() {
    [ -f "$dirInstall/version" ] && cat "$dirInstall/version" || echo "unknown"
}

getInstalledArch() {
    if [ -f "$dirInstall/binary" ]; then
        local b
        b=$(cat "$dirInstall/binary")
        echo "${b#TorrServer-}"
    else
        detectArch
    fi
}

getServicePort() {
    grep -o '\-\-port [0-9]*' /etc/init.d/$serviceName 2>/dev/null | awk '{print $2}' | head -1
}

getAuthCredentials() {
    local accsFile="$dirInstall/accs.db"
    [ ! -f "$accsFile" ] && return
    local user pass
    user=$(grep -o '"[^"]*":' "$accsFile" | head -1 | tr -d '": ')
    pass=$(grep -o ': *"[^"]*"' "$accsFile" | head -1 | sed 's/: *"//;s/"//')
    [ -n "$user" ] && [ -n "$pass" ] && printf "%s:%s" "$user" "$pass"
}

checkInstalled() {
    local bin=""
    if [ -f "$dirInstall/binary" ]; then
        bin="$dirInstall/$(cat "$dirInstall/binary")"
    else
        local arch
        arch=$(detectArch)
        [ -n "$arch" ] && bin="$dirInstall/TorrServer-${arch}"
    fi
    [ -n "$bin" ] && [ -f "$bin" ]
}

checkDiskSpace() {
    local required=80
    local available
    available=$(df "$dirInstall" 2>/dev/null | awk 'NR==2{print int($4/1024)}')
    if [ -z "$available" ]; then
        available=$(df /opt 2>/dev/null | awk 'NR==2{print int($4/1024)}')
        [ -z "$available" ] && available=$(df / | awk 'NR==2{print int($4/1024)}')
    fi
    if [ "$available" -lt "$required" ] 2>/dev/null; then
        printf " $(colorize yellow WARN) Доступно только %s МБ, рекомендуется минимум %s МБ\n" "$available" "$required"
        printf " Продолжить? (%s/%s) " "$(colorize yellow Y)es" "$(colorize green N)o"
        read -r answer_disk </dev/tty
        [ "$answer_disk" != "${answer_disk#[YyДд]}" ] || exit 1
    fi
}

checkInternet() {
    printf " Проверяем соединение с Интернетом...\n"
    if ! curl -sf --max-time 10 "https://api.github.com" >/dev/null 2>&1; then
        printf " - Нет доступа к GitHub. Проверьте соединение.\n"
        exit 1
    fi
    printf " - Соединение в порядке\n"
}

initialCheck() {
    if ! isRoot; then
        printf " Запустите скрипт от root: sh %s\n" "$scriptname"
        exit 1
    fi
    checkInternet
}

isRunning() {
    local arch
    arch=$(getInstalledArch)
    pidof "TorrServer-${arch}" >/dev/null 2>&1
}

restartService() {
    printf " Перезапускаем TorrServer...\n"
    /etc/init.d/$serviceName restart 2>/dev/null
    sleep 2
    if isRunning; then
        printf " ✓ TorrServer $(colorize green ЗАПУЩЕН)\n"
    else
        printf " $(colorize yellow !) TorrServer не запустился — проверьте: logread | grep torrserver\n"
    fi
}

helpUsage() {
    printf "Использование: %s [команда] [флаги]\n\n" "$scriptname"
    printf "Команды:\n"
    printf "  %-30s %s\n" "-i | --install | install"   "установка последней версии"
    printf "  %-30s %s\n" "-u | --update  | update"    "обновление до последней версии"
    printf "  %-30s %s\n" "-s | --status  | status"    "статус службы"
    printf "  %-30s %s\n" "--stremio    | stremio"     "инструкция по интеграции со Stremio"
    printf "  %-30s %s\n" "-r | --remove  | remove"    "удаление TorrServer"
    printf "  %-30s %s\n" "-h | --help    | help"      "эта справка"
    printf "\nФлаги:\n"
    printf "  %-30s %s\n" "--no-color"                 "вывод без цветов (для логов/скриптов)"
    printf "  %-30s %s\n" "--auto"                     "автоматический режим (для cron)"
}

# URL-кодирование строки (заменяем спецсимволы для вставки в URL)
urlencode() {
    printf "%s" "$1" | sed \
        -e 's/%/%25/g' \
        -e 's/ /%20/g' \
        -e 's/!/%21/g' \
        -e 's/"/%22/g' \
        -e 's/#/%23/g' \
        -e 's/\$/%24/g' \
        -e 's/&/%26/g' \
        -e "s/'/%27/g" \
        -e 's/(/%28/g' \
        -e 's/)/%29/g' \
        -e 's/\*/%2A/g' \
        -e 's/+/%2B/g' \
        -e 's/,/%2C/g' \
        -e 's/:/%3A/g' \
        -e 's/;/%3B/g' \
        -e 's/=/%3D/g' \
        -e 's/?/%3F/g' \
        -e 's/@/%40/g'
}

stremioSetup() {
    printf "\n"
    printf "=============================================================\n"
    printf " Интеграция TorrServer + Stremio\n"
    printf "=============================================================\n"

    if ! checkInstalled; then
        printf " $(colorize yellow !) TorrServer не установлен.\n"
        printf "   Сначала выполните установку: sh %s -i\n\n" "$scriptname"
        return 1
    fi

    if ! isRunning; then
        printf " $(colorize yellow !) TorrServer установлен, но не запущен.\n"
        printf "   Запустите: /etc/init.d/torrserver start\n\n"
    fi

    local ip port tsUrl
    ip=$(getIP)
    port=$(getServicePort)
    [ -z "$ip" ]   && ip="<IP-роутера>"
    [ -z "$port" ] && port="8090"
    tsUrl="http://${ip}:${port}"

    # --- Способ 1: прямая ссылка Torrentio с русскими трекерами ---
    # Конфиг: русские трекеры, приоритет русского языка, без кэма и скринеров
    local torrentioConfig="providers=rutor,rutracker,1337x,thepiratebay,torrentgalaxy|language=russian|qualityfilter=cam,scr,unknown"
    local torrentioManifest="https://torrentio.strem.fun/${torrentioConfig}/manifest.json"
    local torrentioStremio="stremio://torrentio.strem.fun/${torrentioConfig}/manifest.json"

    # --- Способ 2: Moisa — проксирование через ваш TorrServer ---
    # Moisa принимает TorrServer URL как параметр конфигурации
    local tsUrlEncoded
    tsUrlEncoded=$(urlencode "$tsUrl")
    local moisaConfig="torrserverUrl=${tsUrlEncoded}|qualityfilter=cam,scr,unknown"
    local moisaManifest="https://moisa.fun/${moisaConfig}/manifest.json"
    local moisaStremio="stremio://moisa.fun/${moisaConfig}/manifest.json"
    local moisaConfigure="https://moisa.fun/configure"

    printf "\n"
    printf " Ваш TorrServer: $(colorize cyan "%s")\n" "$tsUrl"
    printf "\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    printf " СПОСОБ 1 — Torrentio (проще, без TorrServer как бэкенда)\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    printf "\n"
    printf " Torrentio — популярный Stremio-аддон, агрегирует торренты\n"
    printf " из множества трекеров. В этом варианте Stremio использует\n"
    printf " собственный движок для воспроизведения (не TorrServer).\n"
    printf " Но можно использовать оба способа одновременно.\n"
    printf "\n"
    printf " Ссылка для установки в Stremio:\n"
    printf " $(colorize cyan "%s")\n" "$torrentioManifest"
    printf "\n"
    printf " Как добавить:\n"
    printf "  1. Откройте Stremio → Аддоны → значок поиска\n"
    printf "  2. Вставьте ссылку выше и нажмите Enter\n"
    printf "  3. Нажмите «Установить»\n"
    printf "\n"
    printf " Настройка под себя: $(colorize cyan "https://torrentio.strem.fun/configure")\n"
    printf "\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    printf " СПОСОБ 2 — Moisa (Torrentio → ваш TorrServer → Stremio)\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    printf "\n"
    printf " Moisa проксирует потоки из Torrentio через ваш TorrServer.\n"
    printf " Воспроизведение идёт через роутер — более стабильный буфер,\n"
    printf " лучше для 4K, нет зависимости от встроенного движка Stremio.\n"
    printf "\n"
    printf " $(colorize yellow "ВАЖНО:") IP роутера должен быть доступен с устройства\n"
    printf " на котором запущен Stremio (телевизор, телефон, PC).\n"
    printf " Если Stremio на том же роутере — используйте 127.0.0.1.\n"
    printf "\n"
    printf " Шаг 1 — Настройте Moisa:\n"
    printf " Откройте в браузере: $(colorize cyan "%s")\n" "$moisaConfigure"
    printf " Введите TorrServer URL: $(colorize green "%s")\n" "$tsUrl"
    printf " Нажмите «Generate addon URL»\n"
    printf "\n"
    printf " Или используйте готовую ссылку (если IP %s верный):\n" "$ip"
    printf " $(colorize cyan "%s")\n" "$moisaManifest"
    printf "\n"
    printf " Шаг 2 — Установите аддон в Stremio:\n"
    printf "  1. Stremio → Аддоны → значок поиска\n"
    printf "  2. Вставьте ссылку выше и нажмите Enter\n"
    printf "  3. Нажмите «Установить»\n"
    printf "\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    printf " КАК ЭТО РАБОТАЕТ\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    printf "\n"
    printf " Способ 1 (Torrentio напрямую):\n"
    printf "  Stremio → Torrentio API → магнет-ссылка → встроенный движок\n"
    printf "\n"
    printf " Способ 2 (через TorrServer):\n"
    printf "  Stremio → Moisa → Torrentio API → TorrServer (роутер) → Stremio\n"
    printf "\n"
    printf " Рекомендация: попробуйте Способ 1 сначала — он проще.\n"
    printf " Если буферизация нестабильна или нужна поддержка 4K —\n"
    printf " переходите на Способ 2 через Moisa.\n"
    printf "\n"
    printf "=============================================================\n"
    printf "\n"

    # Сохраняем ссылки в файл для удобства
    local linksFile="$dirInstall/stremio-links.txt"
    cat > "$linksFile" << EOF
TorrServer URL: $tsUrl

=== Способ 1: Torrentio (прямой) ===
Manifest: $torrentioManifest
Настройка: https://torrentio.strem.fun/configure

=== Способ 2: Moisa (через TorrServer) ===
Manifest: $moisaManifest
Настройка: $moisaConfigure
TorrServer URL для Moisa: $tsUrl
EOF
    printf " Ссылки сохранены в: $(colorize cyan "%s")\n\n" "$linksFile"
}

cleanup() {
    /etc/init.d/$serviceName stop 2>/dev/null
    /etc/init.d/$serviceName disable 2>/dev/null
    rm -f /etc/init.d/$serviceName
    rm -rf "$dirInstall"
    delUser
}

uninstall() {
    if ! checkInstalled; then
        printf " TorrServer не установлен.\n"
        return 1
    fi
    printf "\n"
    printf " Директория: %s\n" "$dirInstall"
    printf " Версия:     %s\n" "$(getInstalledVersion)"
    printf "\n"
    printf " $(colorize red ВНИМАНИЕ) Будут удалены все данные включая базу торрентов!\n"
    printf "\n"
    printf " Вы уверены? (%s/%s) " "$(colorize red Y)es" "$(colorize yellow N)o"
    read -r answer_del </dev/tty
    if [ "$answer_del" != "${answer_del#[YyДд]}" ]; then
        cleanup
        printf " ✓ TorrServer удалён\n\n"
    else
        printf " Отменено\n\n"
    fi
}

showStatus() {
    printf "\n"
    printf "=============================================================\n"
    printf " Статус TorrServer\n"
    printf "=============================================================\n"

    if ! checkInstalled; then
        printf " Состояние:  $(colorize red НЕ УСТАНОВЛЕН)\n\n"
        return
    fi

    local version arch port ip
    version=$(getInstalledVersion)
    arch=$(getInstalledArch)
    port=$(getServicePort)
    ip=$(getIP)
    [ -z "$port" ] && port="8090"
    [ -z "$ip" ]   && ip="<неизвестен>"

    printf " Версия:     $(colorize cyan "%s")\n" "$version"
    printf " Бинарь:     TorrServer-%s\n" "$arch"

    if isRunning; then
        printf " Служба:     $(colorize green ЗАПУЩЕНА)\n"
        printf " Адрес:      $(colorize green "http://%s:%s")\n" "$ip" "$port"
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
                    printf " Uptime:     %dч %dм %dс\n" "$h" "$m" "$s"
                fi
            fi
        fi
    else
        printf " Служба:     $(colorize red ОСТАНОВЛЕНА)\n"
        printf " Адрес:      http://%s:%s\n" "$ip" "$port"
    fi

    # Авторизация
    local creds authUser authPass
    creds=$(getAuthCredentials)
    if [ -n "$creds" ]; then
        authUser="${creds%%:*}"
        authPass="${creds#*:}"
        printf " Авториз.:   $(colorize yellow ВКЛ)\n"
        printf " Логин:      %s\n" "$authUser"
        printf " Пароль:     %s\n" "$authPass"
    else
        printf " Авториз.:   $(colorize cyan ВЫКЛ)\n"
    fi

    # Автообновление
    if crontab -l 2>/dev/null | grep -q "torrserver.*update\|update.*torrserver"; then
        printf " Автообн.:   $(colorize green ВКЛ)\n"
    else
        printf " Автообн.:   $(colorize cyan ВЫКЛ)\n"
    fi

    # Проверка обновлений
    printf " Обновление: "
    local latest
    latest=$(getLatestRelease)
    if [ -n "$latest" ] && [ "$latest" != "$version" ]; then
        printf "$(colorize yellow "доступно %s")\n" "$latest"
    elif [ -n "$latest" ]; then
        printf "$(colorize green "не требуется")\n"
    else
        printf "не удалось проверить\n"
    fi

    printf "=============================================================\n\n"
}

downloadTorrServer() {
    local version="$1"
    local arch="$2"
    local binName="TorrServer-${arch}"
    local urlBin="https://github.com/YouROK/TorrServer/releases/download/${version}/${binName}"
    local tmpFile="$dirInstall/${binName}.tmp"

    printf " Загружаем TorrServer %s (%s)...\n" "$version" "$arch"
    if ! curl -L --progress-bar -o "$tmpFile" "$urlBin"; then
        printf " - Ошибка загрузки!\n"
        rm -f "$tmpFile"
        return 1
    fi
    local filesize
    filesize=$(wc -c < "$tmpFile" 2>/dev/null || echo 0)
    if [ "$filesize" -lt 1000000 ]; then
        printf " - Файл слишком мал (%s байт) — возможно архитектура недоступна в этом релизе\n" "$filesize"
        rm -f "$tmpFile"
        return 1
    fi
    chmod +x "$tmpFile"
    mv -f "$tmpFile" "$dirInstall/$binName"
    printf "%s" "$version" > "$dirInstall/version"
    printf "%s" "$binName" > "$dirInstall/binary"
    printf " - Загрузка завершена\n"
}

writeInitScript() {
    local binName="$1"
    local authOptions="$2"
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
    stop
    sleep 1
    start
}
EOF
    chmod +x /etc/init.d/$serviceName
}

changeAuth() {
    if ! checkInstalled; then
        printf " TorrServer не установлен.\n"
        return 1
    fi

    local port
    port=$(getServicePort)
    [ -z "$port" ] && port="8090"

    local creds authUser authPass
    creds=$(getAuthCredentials)
    if [ -n "$creds" ]; then
        authUser="${creds%%:*}"
        printf " Текущий логин: %s\n" "$authUser"
    fi

    printf "\n Варианты:\n"
    printf "  1 — сменить логин/пароль\n"
    printf "  2 — отключить авторизацию\n"
    printf "  3 — включить авторизацию\n"
    printf "  0 — отмена\n"
    printf " Выбор: "
    read -r auth_choice </dev/tty

    local newUser newPass authOptions
    case $auth_choice in
        1)
            printf " Новый логин: "
            read -r newUser </dev/tty
            printf " Новый пароль: "
            read -r newPass </dev/tty
            printf '{\n  "%s": "%s"\n}\n' "$newUser" "$newPass" > "$dirInstall/accs.db"
            chmod 600 "$dirInstall/accs.db"
            authOptions="--port $port --path $dirInstall --httpauth"
            printf " - Учётные данные обновлены\n"
            ;;
        2)
            rm -f "$dirInstall/accs.db"
            authOptions="--port $port --path $dirInstall"
            printf " - Авторизация отключена\n"
            ;;
        3)
            printf " Логин: "
            read -r newUser </dev/tty
            printf " Пароль: "
            read -r newPass </dev/tty
            printf '{\n  "%s": "%s"\n}\n' "$newUser" "$newPass" > "$dirInstall/accs.db"
            chmod 600 "$dirInstall/accs.db"
            authOptions="--port $port --path $dirInstall --httpauth"
            printf " - Авторизация включена\n"
            ;;
        *)
            printf " Отменено\n"
            return 0
            ;;
    esac

    local arch binName
    arch=$(getInstalledArch)
    binName="TorrServer-${arch}"
    writeInitScript "$binName" "$authOptions"

    printf " Перезапускаем службу...\n"
    /etc/init.d/$serviceName stop 2>/dev/null
    sleep 1
    /etc/init.d/$serviceName start
    sleep 1
    if isRunning; then
        printf " ✓ Настройки применены, TorrServer $(colorize green ЗАПУЩЕН)\n"
    else
        printf " $(colorize yellow !) TorrServer не запустился — проверьте: logread | grep torrserver\n"
    fi
}

changePort() {
    if ! checkInstalled; then
        printf " TorrServer не установлен.\n"
        return 1
    fi

    local currentPort
    currentPort=$(getServicePort)
    [ -z "$currentPort" ] && currentPort="8090"
    printf " Текущий порт: %s\n" "$currentPort"
    printf " Новый порт (1024-65535): "
    read -r newPort </dev/tty

    if ! printf "%s" "$newPort" | grep -qE '^[0-9]+$' \
        || [ "$newPort" -lt 1024 ] || [ "$newPort" -gt 65535 ]; then
        printf " - Некорректный порт\n"
        return 1
    fi

    local creds authOptions
    creds=$(getAuthCredentials)
    if [ -n "$creds" ]; then
        authOptions="--port $newPort --path $dirInstall --httpauth"
    else
        authOptions="--port $newPort --path $dirInstall"
    fi

    local arch binName
    arch=$(getInstalledArch)
    binName="TorrServer-${arch}"
    writeInitScript "$binName" "$authOptions"

    printf " Перезапускаем службу...\n"
    /etc/init.d/$serviceName stop 2>/dev/null
    sleep 1
    /etc/init.d/$serviceName start
    sleep 1
    if isRunning; then
        local ip
        ip=$(getIP)
        [ -z "$ip" ] && ip="<IP роутера>"
        printf " ✓ Порт изменён. Новый адрес: $(colorize cyan "http://%s:%s")\n" "$ip" "$newPort"
    else
        printf " $(colorize yellow !) TorrServer не запустился — проверьте: logread | grep torrserver\n"
    fi
}

setupAutoupdate() {
    if ! checkInstalled; then
        printf " TorrServer не установлен.\n"
        return 1
    fi

    # TorrServer обновляется редко (раз в несколько недель), еженедельной проверки достаточно
    local cronLine="0 4 * * 0 sh $(readlink -f "$0") --no-color --auto update >> /var/log/torrserver-update.log 2>&1"

    # Проверяем текущее состояние
    if crontab -l 2>/dev/null | grep -q "torrserver.*update\|update.*torrserver"; then
        printf " Автообновление уже настроено (еженедельно по воскресеньям в 04:00).\n"
        printf " Отключить? (%s/%s) " "$(colorize red Y)es" "$(colorize yellow N)o"
        read -r answer </dev/tty
        if [ "$answer" != "${answer#[YyДд]}" ]; then
            local tmpCron="/tmp/cron_torrserver.tmp"
            crontab -l 2>/dev/null | grep -v "torrserver.*update\|update.*torrserver" > "$tmpCron"
            crontab "$tmpCron"
            rm -f "$tmpCron"
            printf " ✓ Автообновление отключено\n"
        else
            printf " Отменено\n"
        fi
        return 0
    fi

    printf "\n"
    printf " Автообновление запускается раз в неделю (воскресенье, 04:00).\n"
    printf " TorrServer обновляется редко, ежедневная проверка избыточна.\n"
    printf " Лог: /var/log/torrserver-update.log\n"
    printf "\n"
    printf " $(colorize yellow ВНИМАНИЕ) При обновлении скачивается ~70 МБ.\n"
    printf " Если на роутере мало места в /opt — не включайте автообновление,\n"
    printf " обновляйте вручную командой: sh %s -u\n" "$scriptname"
    printf "\n"
    printf " Включить автообновление? (%s/%s) " "$(colorize green Y)es" "$(colorize yellow N)o"
    read -r answer </dev/tty
    if [ "$answer" != "${answer#[YyДд]}" ]; then
        mkdir -p /etc/crontabs
        local tmpCron="/tmp/cron_torrserver.tmp"
        crontab -l 2>/dev/null > "$tmpCron"
        printf "%s\n" "$cronLine" >> "$tmpCron"
        crontab "$tmpCron"
        rm -f "$tmpCron"
        /etc/init.d/cron enable 2>/dev/null
        /etc/init.d/cron start 2>/dev/null
        printf " ✓ Автообновление включено (еженедельно, воскресенье 04:00)\n"
    else
        printf " Отменено\n"
    fi
}

installTorrServer() {
    printf "\n"
    printf "=============================================================\n"
    printf " Установка TorrServer\n"
    printf "=============================================================\n"
    printf "\n"
    printf " $(colorize yellow "ТРЕБОВАНИЯ К РОУТЕРУ:")\n"
    printf "  RAM:   минимум 256 МБ, рекомендуется 512 МБ и более\n"
    printf "  Место: ~70-80 МБ свободно в /opt\n"
    printf "  CPU:   на MIPS-роутерах (TP-Link, Xiaomi mini и т.п.)\n"
    printf "         стриминг может тормозить или не работать вовсе.\n"
    printf "         Уверенно работает на ARM64 (NanoPi, RPi 3/4, MT7981)\n"
    printf "\n"
    printf " Продолжить установку? (%s/%s) " "$(colorize green Y)es" "$(colorize yellow N)o"
    read -r answer_warn </dev/tty
    [ "$answer_warn" != "${answer_warn#[YyДд]}" ] || { printf " Установка отменена\n\n"; return 0; }
    printf "\n"

    local arch
    arch=$(detectArch)
    if [ -z "$arch" ]; then
        printf " - Неизвестная архитектура: %s\n" "$(uname -m)"
        printf "   Варианты: linux-amd64, linux-arm64, linux-arm7, linux-arm5,\n"
        printf "             linux-mips, linux-mipsle, linux-mips64, linux-386, linux-riscv64\n"
        printf " Введите архитектуру: "
        read -r arch </dev/tty
        [ -z "$arch" ] && exit 1
    fi
    printf " Архитектура: %s\n" "$arch"

    if [ -f "$dirInstall/TorrServer-${arch}" ]; then
        printf " TorrServer уже установлен (версия: %s)\n" "$(getInstalledVersion)"
        printf " Обновить до последней версии? (%s/%s) " "$(colorize green Y)es" "$(colorize yellow N)o"
        read -r answer_up </dev/tty
        [ "$answer_up" != "${answer_up#[YyДд]}" ] && UpdateVersion
        return
    fi

    checkDiskSpace

    [ ! -d "$dirInstall" ] && mkdir -p "$dirInstall"

    printf " Получаем информацию о последней версии...\n"
    local latestVersion
    latestVersion=$(getLatestRelease)
    if [ -z "$latestVersion" ]; then
        printf " - Не удалось получить версию с GitHub\n"
        exit 1
    fi
    printf " Последняя версия: %s\n" "$latestVersion"

    downloadTorrServer "$latestVersion" "$arch" || exit 1

    addUser

    local servicePort="8090"
    printf "\n Порт по умолчанию: 8090. Изменить? (%s/%s) " "$(colorize yellow Y)es" "$(colorize green N)o"
    read -r answer_cp </dev/tty
    if [ "$answer_cp" != "${answer_cp#[YyДд]}" ]; then
        printf " Введите порт (1024-65535): "
        read -r answer_port </dev/tty
        if printf "%s" "$answer_port" | grep -qE '^[0-9]+$' \
            && [ "$answer_port" -ge 1024 ] && [ "$answer_port" -le 65535 ]; then
            servicePort=$answer_port
        else
            printf " - Некорректный порт, используется 8090\n"
        fi
    fi

    local authOptions="--port $servicePort --path $dirInstall"
    local isAuthUser="" isAuthPass=""
    printf " Включить HTTP-авторизацию? (%s/%s) " "$(colorize green Y)es" "$(colorize yellow N)o"
    read -r answer_auth </dev/tty
    if [ "$answer_auth" != "${answer_auth#[YyДд]}" ]; then
        printf " Пользователь: "
        read -r isAuthUser </dev/tty
        printf " Пароль: "
        read -r isAuthPass </dev/tty
        printf '{\n  "%s": "%s"\n}\n' "$isAuthUser" "$isAuthPass" > "$dirInstall/accs.db"
        chmod 600 "$dirInstall/accs.db"
        authOptions="--port $servicePort --path $dirInstall --httpauth"
        printf " - Учётные данные сохранены\n"
    fi

    local binName="TorrServer-${arch}"
    writeInitScript "$binName" "$authOptions"
    /etc/init.d/$serviceName enable
    /etc/init.d/$serviceName start

    sleep 2

    # Предложить автообновление
    printf "\n"
    printf " Включить автообновление? (раз в неделю, ~70 МБ трафика)\n"
    printf " $(colorize yellow "Не рекомендуется если в /opt менее 150 МБ свободно.")\n"
    printf " Включить? (%s/%s) " "$(colorize green Y)es" "$(colorize yellow N)o"
    read -r answer_cron </dev/tty
    if [ "$answer_cron" != "${answer_cron#[YyДд]}" ]; then
        local cronLine="0 4 * * 0 sh $(readlink -f "$0") --no-color --auto update >> /var/log/torrserver-update.log 2>&1"
        mkdir -p /etc/crontabs
        local tmpCron="/tmp/cron_torrserver.tmp"
        crontab -l 2>/dev/null > "$tmpCron"
        printf "%s\n" "$cronLine" >> "$tmpCron"
        crontab "$tmpCron"
        rm -f "$tmpCron"
        /etc/init.d/cron enable 2>/dev/null
        /etc/init.d/cron start 2>/dev/null
        printf " ✓ Автообновление включено (воскресенье 04:00)\n"
    fi

    local serverIP
    serverIP=$(getIP)
    [ -z "$serverIP" ] && serverIP="<IP роутера>"

    printf "\n"
    printf "=============================================================\n"
    if isRunning; then
        printf " ✓ TorrServer %s установлен и $(colorize green ЗАПУЩЕН)\n" "$latestVersion"
    else
        printf " $(colorize yellow !) TorrServer %s установлен, но не запустился\n" "$latestVersion"
        printf "   Проверьте: logread | grep torrserver\n"
    fi
    printf "=============================================================\n"
    printf " Веб-интерфейс: $(colorize cyan "http://%s:%s")\n" "$serverIP" "$servicePort"
    if [ -n "$isAuthUser" ]; then
        printf " Логин: %s  Пароль: %s\n" "$isAuthUser" "$isAuthPass"
    fi
    printf "\n"

    printf " Показать инструкцию по подключению к Stremio? (%s/%s) " \
        "$(colorize green Y)es" "$(colorize yellow N)o"
    read -r answer_stremio </dev/tty
    [ "$answer_stremio" != "${answer_stremio#[YyДд]}" ] && stremioSetup
}

UpdateVersion() {
    # --auto флаг: тихий режим для cron (без лишнего вывода если версия актуальна)
    local auto_mode="$1"

    if ! checkInstalled; then
        printf " TorrServer не установлен.\n"
        return 1
    fi

    printf " Получаем информацию о последней версии...\n"
    local latestVersion
    latestVersion=$(getLatestRelease)
    if [ -z "$latestVersion" ]; then
        printf " - Не удалось получить версию с GitHub\n"
        return 1
    fi

    local currentVersion
    currentVersion=$(getInstalledVersion)
    printf " Установлена: $(colorize cyan "%s") | Последняя: $(colorize green "%s")\n" \
        "$currentVersion" "$latestVersion"

    if [ "$currentVersion" = "$latestVersion" ]; then
        printf " ✓ Уже установлена последняя версия\n"
        return 0
    fi

    local arch
    arch=$(getInstalledArch)

    printf " Останавливаем службу...\n"
    /etc/init.d/$serviceName stop 2>/dev/null
    sleep 1
    killall "TorrServer-${arch}" 2>/dev/null
    sleep 1

    downloadTorrServer "$latestVersion" "$arch" || {
        printf " - Откатываемся, запускаем старую версию\n"
        /etc/init.d/$serviceName start 2>/dev/null
        return 1
    }

    /etc/init.d/$serviceName start
    sleep 2

    if isRunning; then
        printf " ✓ TorrServer обновлён до %s и $(colorize green ЗАПУЩЕН)\n" "$latestVersion"
    else
        printf " $(colorize yellow !) Обновлён до %s, но не запустился — проверьте: logread | grep torrserver\n" "$latestVersion"
    fi
}

# === Парсим флаги ===
AUTO_MODE=0
ARGS=""
for arg in "$@"; do
    case "$arg" in
        --no-color) NO_COLOR=1 ;;
        --auto)     AUTO_MODE=1 ;;
        *)          ARGS="$ARGS $arg" ;;
    esac
done
# Убираем ведущий пробел
ARGS="${ARGS# }"

# === Основной код ===
case $ARGS in
    -i|--install|install)
        initialCheck
        installTorrServer
        exit
        ;;
    -u|--update|update)
        initialCheck
        UpdateVersion "$AUTO_MODE"
        exit
        ;;
    -s|--status|status)
        showStatus
        exit
        ;;
    --stremio|stremio)
        stremioSetup
        exit
        ;;
    -r|--remove|remove)
        initialCheck
        uninstall
        exit
        ;;
    -h|--help|help)
        helpUsage
        exit
        ;;
    "")
        ;;
    *)
        printf " Неизвестная команда: %s\n" "$ARGS"
        helpUsage
        exit 1
        ;;
esac

# === Интерактивное меню ===
printf "\n"
printf "=============================================================\n"
printf " TorrServer — установщик для OpenWrt / FriendlyWrt\n"
printf "=============================================================\n"

if checkInstalled 2>/dev/null; then
    printf " Версия:  %s\n" "$(getInstalledVersion)"
    if isRunning; then
        printf " Служба:  $(colorize green ЗАПУЩЕНА)\n"
    else
        printf " Служба:  $(colorize red ОСТАНОВЛЕНА)\n"
    fi
fi

printf "\n"
printf "  $(colorize green  i) — установить / обновить\n"
printf "  $(colorize cyan   s) — статус\n"
printf "  $(colorize cyan   t) — интеграция со Stremio\n"
printf "  $(colorize yellow p) — сменить порт\n"
printf "  $(colorize yellow a) — настроить авторизацию\n"
printf "  $(colorize cyan   c) — автообновление (cron)\n"
printf "  $(colorize green  r) — перезапустить службу\n"
printf "  $(colorize red    d) — удалить\n"
printf "  $(colorize yellow n) — выйти\n"
printf "\n"

while true; do
    printf " Выбор: "
    read -r ydn </dev/tty
    case $ydn in
        [IiИи]*)
            initialCheck
            installTorrServer
            break
            ;;
        [SsСс]*)
            showStatus
            ;;
        [TtТт]*)
            stremioSetup
            ;;
        [PpПп]*)
            isRoot || { printf " Требуется root\n"; continue; }
            changePort
            ;;
        [AaАа]*)
            isRoot || { printf " Требуется root\n"; continue; }
            changeAuth
            ;;
        [CcСc]*)
            isRoot || { printf " Требуется root\n"; continue; }
            setupAutoupdate
            ;;
        [RrРр]*)
            isRoot || { printf " Требуется root\n"; continue; }
            restartService
            ;;
        [DdУу]*)
            initialCheck
            uninstall
            break
            ;;
        [NnНн]*)
            break
            ;;
        *)
            printf " Введите i, s, t, p, a, c, r, d или n\n"
            ;;
    esac
done

printf " Удачи!\n\n"
