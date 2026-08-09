#!/bin/sh

username="torrserver"
dirInstall="/opt/torrserver"
serviceName="torrserver"
scriptname=$(basename "$0")

# Цвета для вывода (совместимо с POSIX sh через printf)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

colorize() {
    color=$1
    text=$2
    case $color in
        red)    printf "${RED}%s${NC}" "$text" ;;
        green)  printf "${GREEN}%s${NC}" "$text" ;;
        yellow) printf "${YELLOW}%s${NC}" "$text" ;;
        *)      printf "%s" "$text" ;;
    esac
}

isRoot() {
    [ "$(id -u)" -eq 0 ]
}

# Определяем архитектуру автоматически
detectArch() {
    machine=$(uname -m)
    case "$machine" in
        x86_64)         echo "linux-amd64" ;;
        aarch64|arm64)  echo "linux-arm64" ;;
        armv7*)         echo "linux-arm7" ;;
        armv6*)         echo "linux-arm7" ;;
        armv5*)         echo "linux-arm5" ;;
        mips64*)        echo "linux-mips64" ;;
        mips*)          echo "linux-mips" ;;
        i686|i386)      echo "linux-386" ;;
        riscv64)        echo "linux-riscv64" ;;
        *)
            echo ""
            return 1
            ;;
    esac
}

addUser() {
    [ "$username" = "root" ] && return 0
    if grep -q "^$username:" /etc/passwd 2>/dev/null; then
        printf " - Пользователь %s уже существует!\n" "$username"
        return 0
    fi
    # Пробуем nogroup, если нет — nobody
    local group="nogroup"
    grep -q "^nogroup:" /etc/group 2>/dev/null || group="nobody"
    adduser -D -H -h "$dirInstall" -s /bin/false -G "$group" "$username" 2>/dev/null
    if [ $? -eq 0 ]; then
        chmod 755 "$dirInstall"
        printf " - Пользователь %s добавлен!\n" "$username"
    else
        printf " - Не удалось добавить пользователя %s (продолжаем от root)\n" "$username"
        username="root"
    fi
}

delUser() {
    [ "$username" = "root" ] && return 0
    if grep -q "^$username:" /etc/passwd 2>/dev/null; then
        deluser "$username" 2>/dev/null
        if [ $? -eq 0 ]; then
            printf " - Пользователь %s удален!\n" "$username"
        else
            printf " - Не удалось удалить пользователя %s!\n" "$username"
        fi
    else
        printf " - Пользователь %s не найден!\n" "$username"
    fi
}

getIP() {
    # Пробуем несколько способов получить IP
    local iface
    iface=$(ip route show default 2>/dev/null | awk '/default/{print $5; exit}')
    if [ -n "$iface" ]; then
        ip addr show dev "$iface" 2>/dev/null | awk '/inet /{print $2; exit}' | cut -d/ -f1
    else
        # Fallback: первый не-loopback адрес
        ip addr 2>/dev/null | awk '/inet /{print $2}' | grep -v '^127\.' | cut -d/ -f1 | head -n1
    fi
}

getLatestRelease() {
    curl -sf "https://api.github.com/repos/YouROK/TorrServer/releases/latest" \
        | grep '"tag_name":' \
        | sed -E 's/.*"([^"]+)".*/\1/'
}

getInstalledVersion() {
    local vfile="$dirInstall/version"
    [ -f "$vfile" ] && cat "$vfile" || echo "unknown"
}

checkInstalled() {
    local arch
    arch=$(detectArch)
    if [ -f "$dirInstall/TorrServer-${arch}" ]; then
        printf " - TorrServer найден в директории %s\n" "$dirInstall"
        return 0
    elif [ -f "$dirInstall/TorrServer-linux-arm64" ] || \
         [ -f "$dirInstall/TorrServer-linux-amd64" ] || \
         [ -f "$dirInstall/TorrServer-linux-arm7" ]; then
        printf " - TorrServer найден в директории %s\n" "$dirInstall"
        return 0
    else
        printf " - TorrServer не найден\n"
        return 1
    fi
}

checkInternet() {
    printf " Проверяем соединение с Интернетом...\n"
    # Пробуем curl к GitHub API — это то, что нам реально нужно
    if ! curl -sf --max-time 10 "https://api.github.com" >/dev/null 2>&1; then
        printf " - Нет доступа к Интернету или GitHub. Проверьте соединение.\n"
        exit 1
    fi
    printf " - Соединение с Интернетом в порядке\n"
}

initialCheck() {
    if ! isRoot; then
        printf " Вам нужно запустить скрипт от root. Пример: sh %s\n" "$scriptname"
        exit 1
    fi
    checkInternet
}

helpUsage() {
    printf "%s\n" "$scriptname"
    printf "  -i | --install | install - установка последней версии\n"
    printf "  -u | --update  | update  - обновление до последней версии\n"
    printf "  -r | --remove  | remove  - удаление TorrServer\n"
    printf "  -h | --help    | help    - эта справка\n"
}

cleanup() {
    /etc/init.d/$serviceName stop 2>/dev/null
    /etc/init.d/$serviceName disable 2>/dev/null
    rm -rf /etc/init.d/$serviceName "$dirInstall" 2>/dev/null
    delUser
}

uninstall() {
    if ! checkInstalled; then
        printf " TorrServer не установлен.\n"
        return 1
    fi
    printf "\n"
    printf " Директория c TorrServer - %s\n" "$dirInstall"
    printf "\n"
    printf " Это действие удалит все данные TorrServer включая базу данных торрентов и настройки!\n"
    printf "\n"
    printf " Вы уверены что хотите удалить программу? (%s/%s) " "$(colorize red Y)es" "$(colorize yellow N)o"
    read -r answer_del </dev/tty
    if [ "$answer_del" != "${answer_del#[YyДд]}" ]; then
        cleanup
        printf " - TorrServer удален из системы!\n\n"
    else
        printf "\n"
    fi
}

downloadTorrServer() {
    local version="$1"
    local arch="$2"
    local binName="TorrServer-${arch}"
    local urlBin="https://github.com/YouROK/TorrServer/releases/download/${version}/${binName}"

    printf " Загружаем TorrServer %s для %s...\n" "$version" "$arch"
    if ! curl -L --progress-bar -o "$dirInstall/$binName" "$urlBin"; then
        printf " - Ошибка загрузки! Проверьте соединение или попробуйте позже.\n"
        return 1
    fi
    chmod +x "$dirInstall/$binName"
    # Сохраняем версию и имя бинаря
    printf "%s" "$version" > "$dirInstall/version"
    printf "%s" "$binName" > "$dirInstall/binary"
    printf " - Загрузка завершена\n"
}

installTorrServer() {
    printf " Устанавливаем и настраиваем TorrServer...\n"

    # Определяем архитектуру
    local arch
    arch=$(detectArch)
    if [ -z "$arch" ]; then
        printf " - Неизвестная архитектура: %s\n" "$(uname -m)"
        printf "   Доступные варианты: linux-amd64, linux-arm64, linux-arm7, linux-arm5, linux-mips, linux-mips64, linux-386, linux-riscv64\n"
        printf " Введите архитектуру вручную: "
        read -r arch </dev/tty
    fi

    printf " Определена архитектура: %s\n" "$arch"

    # Проверка существующей установки
    if [ -f "$dirInstall/TorrServer-${arch}" ]; then
        printf " TorrServer уже установлен. Хотите обновить? (%s/%s) " "$(colorize green Y)es" "$(colorize yellow N)o"
        read -r answer_up </dev/tty
        if [ "$answer_up" != "${answer_up#[YyДд]}" ]; then
            UpdateVersion
            return
        fi
    fi

    [ ! -d "$dirInstall" ] && mkdir -p "$dirInstall"

    # Получаем последнюю версию
    printf " Получаем информацию о последней версии...\n"
    local latestVersion
    latestVersion=$(getLatestRelease)
    if [ -z "$latestVersion" ]; then
        printf " - Не удалось получить информацию о версии с GitHub\n"
        exit 1
    fi
    printf " Последняя версия: %s\n" "$latestVersion"

    downloadTorrServer "$latestVersion" "$arch" || exit 1

    addUser

    # Настройка порта
    printf " Хотите изменить порт для TorrServer (по умолчанию 8090)? (%s/%s) " "$(colorize yellow Y)es" "$(colorize green N)o"
    read -r answer_cp </dev/tty
    local servicePort="8090"
    if [ "$answer_cp" != "${answer_cp#[YyДд]}" ]; then
        printf " Введите номер порта: "
        read -r answer_port </dev/tty
        # Валидация порта
        if printf "%s" "$answer_port" | grep -qE '^[0-9]{1,5}$' && [ "$answer_port" -ge 1024 ] && [ "$answer_port" -le 65535 ]; then
            servicePort=$answer_port
        else
            printf " - Некорректный порт, используется 8090\n"
        fi
    fi

    # Настройка авторизации
    local authOptions="--port $servicePort --path $dirInstall"
    local isAuthUser="" isAuthPass=""
    printf " Включить авторизацию на сервере? (%s/%s) " "$(colorize green Y)es" "$(colorize yellow N)o"
    read -r answer_auth </dev/tty
    if [ "$answer_auth" != "${answer_auth#[YyДд]}" ]; then
        printf " Пользователь: "
        read -r isAuthUser </dev/tty
        printf " Пароль: "
        read -r isAuthPass </dev/tty
        printf " Сохраняем учетные данные в %s/accs.db\n" "$dirInstall"
        printf '{\n  "%s": "%s"\n}\n' "$isAuthUser" "$isAuthPass" > "$dirInstall/accs.db"
        chmod 600 "$dirInstall/accs.db"
        authOptions="--port $servicePort --path $dirInstall --httpauth"
    fi

    local binName="TorrServer-${arch}"

    # Создаём init script для OpenWrt (procd)
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

    local serverIP
    serverIP=$(getIP)
    [ -z "$serverIP" ] && serverIP="<IP роутера>"

    printf "\n"
    printf " ✓ TorrServer %s установлен в %s\n" "$latestVersion" "$dirInstall"
    printf "\n"
    printf " Веб-интерфейс: http://%s:%s\n" "$serverIP" "$servicePort"
    printf "\n"
    if [ -n "$isAuthUser" ]; then
        printf " Авторизация: пользователь «%s», пароль «%s»\n" "$isAuthUser" "$isAuthPass"
        printf "\n"
    fi
}

UpdateVersion() {
    if ! checkInstalled; then
        printf " TorrServer не установлен. Сначала выполните установку.\n"
        return 1
    fi

    printf " Получаем информацию о последней версии...\n"
    local latestVersion
    latestVersion=$(getLatestRelease)
    if [ -z "$latestVersion" ]; then
        printf " - Не удалось получить информацию о версии с GitHub\n"
        return 1
    fi

    local currentVersion
    currentVersion=$(getInstalledVersion)
    printf " Установлена: %s | Последняя: %s\n" "$currentVersion" "$latestVersion"

    if [ "$currentVersion" = "$latestVersion" ]; then
        printf " - Уже установлена последняя версия (%s)\n" "$latestVersion"
        return 0
    fi

    # Определяем архитектуру из сохранённого бинаря или автодетектом
    local arch
    if [ -f "$dirInstall/binary" ]; then
        local savedBin
        savedBin=$(cat "$dirInstall/binary")
        arch="${savedBin#TorrServer-}"
    else
        arch=$(detectArch)
    fi

    /etc/init.d/$serviceName stop 2>/dev/null
    downloadTorrServer "$latestVersion" "$arch" || return 1
    /etc/init.d/$serviceName start
    printf " ✓ TorrServer обновлён до %s!\n" "$latestVersion"
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
    -r|--remove|remove)
        initialCheck
        uninstall
        exit
        ;;
    -h|--help|help)
        helpUsage
        exit
        ;;
    *)
        printf "\n"
        printf "=============================================================\n"
        printf " Скрипт установки TorrServer для OpenWrt/FriendlyWrt\n"
        printf "=============================================================\n"
        printf "\n"
        printf " Введите '%s -h' для вызова справки\n" "$scriptname"
        printf "\n"
        ;;
esac

while true; do
    printf " Хотите установить или настроить TorrServer? (%s|%s) Для удаления введите «%s» " \
        "$(colorize green Y)es" "$(colorize yellow N)o" "$(colorize red D)elete"
    read -r ydn </dev/tty
    case $ydn in
        [YyДд]*)
            initialCheck
            installTorrServer
            break
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
            printf " Введите %s, %s или %s\n" "$(colorize green Y)es" "$(colorize yellow N)o" "$(colorize red D)elete"
            ;;
    esac
done

printf " Удачи!\n\n"
