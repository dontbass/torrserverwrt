#!/bin/sh

username="torrserver"
dirInstall="/opt/torrserver"
serviceName="torrserver"
scriptname=$(basename "$0")

# Цвета для вывода (POSIX sh совместимо)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

colorize() {
    case $1 in
        red)    printf "${RED}%s${NC}" "$2" ;;
        green)  printf "${GREEN}%s${NC}" "$2" ;;
        yellow) printf "${YELLOW}%s${NC}" "$2" ;;
        cyan)   printf "${CYAN}%s${NC}" "$2" ;;
        *)      printf "%s" "$2" ;;
    esac
}

isRoot() {
    [ "$(id -u)" -eq 0 ]
}

# Определяем архитектуру автоматически
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
    # Читаем порт из init-скрипта
    grep -o '\-\-port [0-9]*' /etc/init.d/$serviceName 2>/dev/null | awk '{print $2}' | head -1
}

checkInstalled() {
    # Проверяем через файл binary, потом через detectArch
    local bin=""
    if [ -f "$dirInstall/binary" ]; then
        bin="$dirInstall/$(cat "$dirInstall/binary")"
    else
        local arch
        arch=$(detectArch)
        [ -n "$arch" ] && bin="$dirInstall/TorrServer-${arch}"
    fi
    if [ -n "$bin" ] && [ -f "$bin" ]; then
        return 0
    fi
    return 1
}

checkDiskSpace() {
    local required=80  # МБ
    local available
    available=$(df "$dirInstall" 2>/dev/null | awk 'NR==2{print int($4/1024)}')
    if [ -z "$available" ]; then
        # dirInstall ещё не создан — проверяем /opt или /
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

helpUsage() {
    printf "Использование: %s [команда]\n\n" "$scriptname"
    printf "  %-28s %s\n" "-i | --install | install" "установка последней версии"
    printf "  %-28s %s\n" "-u | --update  | update"  "обновление до последней версии"
    printf "  %-28s %s\n" "-s | --status  | status"  "статус службы"
    printf "  %-28s %s\n" "-r | --remove  | remove"  "удаление TorrServer"
    printf "  %-28s %s\n" "-h | --help    | help"    "эта справка"
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
        printf " Состояние: $(colorize red НЕ УСТАНОВЛЕН)\n"
        printf "\n"
        return
    fi

    local version arch port ip
    version=$(getInstalledVersion)
    arch=$(getInstalledArch)
    port=$(getServicePort)
    ip=$(getIP)
    [ -z "$port" ] && port="8090"
    [ -z "$ip" ]   && ip="<неизвестен>"

    printf " Версия:    $(colorize cyan "%s")\n" "$version"
    printf " Бинарь:    TorrServer-%s\n" "$arch"

    if isRunning; then
        printf " Служба:    $(colorize green ЗАПУЩЕНА)\n"
        printf " Адрес:     $(colorize green "http://%s:%s")\n" "$ip" "$port"
        # uptime процесса через /proc
        local pid
        pid=$(pidof "TorrServer-${arch}" 2>/dev/null | awk '{print $1}')
        if [ -n "$pid" ] && [ -f "/proc/$pid/stat" ]; then
            local ticks uptime_sec
            ticks=$(awk '{print $22}' /proc/$pid/stat 2>/dev/null)
            uptime_sec=$(awk '{print int($1)}' /proc/uptime 2>/dev/null)
            hz=$(getconf CLK_TCK 2>/dev/null || echo 100)
            if [ -n "$ticks" ] && [ -n "$uptime_sec" ]; then
                local start_sec running_sec
                start_sec=$((ticks / hz))
                running_sec=$((uptime_sec - start_sec))
                if [ $running_sec -gt 0 ]; then
                    local h m s
                    h=$((running_sec / 3600))
                    m=$(((running_sec % 3600) / 60))
                    s=$((running_sec % 60))
                    printf " Uptime:    %dч %dм %dс\n" "$h" "$m" "$s"
                fi
            fi
        fi
    else
        printf " Служба:    $(colorize red ОСТАНОВЛЕНА)\n"
    fi

    # Проверяем наличие обновления
    printf " Проверяем обновления...\n"
    local latest
    latest=$(getLatestRelease)
    if [ -n "$latest" ] && [ "$latest" != "$version" ]; then
        printf " Обновление: $(colorize yellow "доступно %s")\n" "$latest"
    elif [ -n "$latest" ]; then
        printf " Обновление: $(colorize green "не требуется")\n"
    fi

    printf "\n"
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
    # Проверяем что скачали не HTML страницу с ошибкой
    local filesize
    filesize=$(wc -c < "$tmpFile" 2>/dev/null || echo 0)
    if [ "$filesize" -lt 1000000 ]; then
        printf " - Файл слишком мал (%s байт), возможно архитектура недоступна\n" "$filesize"
        rm -f "$tmpFile"
        return 1
    fi
    chmod +x "$tmpFile"
    mv -f "$tmpFile" "$dirInstall/$binName"
    printf "%s" "$version" > "$dirInstall/version"
    printf "%s" "$binName" > "$dirInstall/binary"
    printf " - Загрузка завершена\n"
}

installTorrServer() {
    printf "\n Устанавливаем TorrServer...\n\n"

    # Определяем архитектуру
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

    # Уже установлен?
    if [ -f "$dirInstall/TorrServer-${arch}" ]; then
        printf " TorrServer уже установлен (версия: %s)\n" "$(getInstalledVersion)"
        printf " Обновить до последней версии? (%s/%s) " "$(colorize green Y)es" "$(colorize yellow N)o"
        read -r answer_up </dev/tty
        [ "$answer_up" != "${answer_up#[YyДд]}" ] && UpdateVersion
        return
    fi

    checkDiskSpace

    [ ! -d "$dirInstall" ] && mkdir -p "$dirInstall"

    # Последняя версия
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

    # Порт
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

    # Авторизация
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

    # Init-скрипт для OpenWrt (procd)
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
    /etc/init.d/$serviceName enable
    /etc/init.d/$serviceName start

    # Даём процессу время подняться
    sleep 2

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
}

UpdateVersion() {
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

# === Основной код ===

case $1 in
    -i|--install|install)
        initialCheck
        installTorrServer
        exit
        ;;
    -u|--update|update)
        initialCheck
        UpdateVersion
        exit
        ;;
    -s|--status|status)
        showStatus
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
        printf " Неизвестная команда: %s\n" "$1"
        helpUsage
        exit 1
        ;;
esac

# Интерактивное меню
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
printf "  $(colorize green i) — установить / обновить\n"
printf "  $(colorize cyan  s) — статус\n"
printf "  $(colorize red   d) — удалить\n"
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
        [DdУу]*)
            initialCheck
            uninstall
            break
            ;;
        [NnНн]*)
            break
            ;;
        *)
            printf " Введите i, s, d или n\n"
            ;;
    esac
done

printf " Удачи!\n\n"
