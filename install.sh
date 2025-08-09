#!/bin/sh

username="torrserver"
dirInstall="/opt/torrserver"
serviceName="torrserver"
scriptname=$(basename "$0")
architecture="arm64" # Для FriendlyWrt явно указываем архитектуру

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Функции
colorize() {
    color=$1
    text=$2
    case $color in
        red) echo -e "${RED}${text}${NC}" ;;
        green) echo -e "${GREEN}${text}${NC}" ;;
        yellow) echo -e "${YELLOW}${text}${NC}" ;;
        *) echo -e "${text}" ;;
    esac
}

isRoot() {
    [ $(id -u) -eq 0 ] && return 0 || return 1
}

addUser() {
    if isRoot; then
        [ "$username" = "root" ] && return 0
        if grep -q "^$username:" /etc/passwd; then
            echo " - Пользователь $username уже существует!"
            return 0
        else
            adduser -D -H -h "$dirInstall" -s /bin/false -G nogroup "$username"
            if [ $? -eq 0 ]; then
                chmod 755 "$dirInstall"
                echo " - Пользователь $username добавлен!"
            else
                echo " - Не удалось добавить пользователя $username!"
                return 1
            fi
        fi
    fi
}

delUser() {
    if isRoot; then
        [ "$username" = "root" ] && return 0
        if grep -q "^$username:" /etc/passwd; then
            deluser "$username" 2>/dev/null
            [ $? -eq 0 ] && echo " - Пользователь $username удален!" || echo " - Не удалось удалить пользователя $username!"
        else
            echo " - Пользователь $username не найден!"
            return 1
        fi
    fi
}

checkRunning() {
    pidof TorrServer-linux-arm64 | head -n 1
}

getIP() {
    ip addr show dev $(ip route | grep default | awk '{print $5}') | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n 1
}

uninstall() {
    checkInstalled
    echo ""
    echo " Директория c TorrServer - ${dirInstall}"
    echo ""
    echo " Это действие удалит все данные TorrServer включая базу данных торрентов и настройки!"
    echo ""
    read -p " Вы уверены что хотите удалить программу? ($(colorize red Y)es/$(colorize yellow N)o) " answer_del </dev/tty
    if [ "$answer_del" != "${answer_del#[YyДд]}" ]; then
        cleanup
        echo " - TorrServer удален из системы!"
        echo ""
    else
        echo ""
    fi
}

cleanup() {
    /etc/init.d/$serviceName stop 2>/dev/null
    /etc/init.d/$serviceName disable 2>/dev/null
    rm -rf /etc/init.d/$serviceName $dirInstall 2>/dev/null
    delUser
}

helpUsage() {
    echo "$scriptname"
    echo "  -i | --install | install - установка последней версии"
    echo "  -u | --update  | update  - установка последнего обновления, если имеется"
    echo "  -r | --remove  | remove  - удаление TorrServer"
    echo "  -h | --help    | help    - эта справка"
}

checkInternet() {
    echo " Проверяем соединение с Интернетом..."
    if ! ping -c 2 google.com >/dev/null 2>&1; then
        echo " - Нет Интернета. Проверьте ваше соединение."
        exit 1
    fi
    echo " - соединение с Интернетом успешно"
}

initialCheck() {
    if ! isRoot; then
        echo " Вам нужно запустить скрипт от root. Пример: sh $scriptname"
        exit 1
    fi
    checkInternet
}

getLatestRelease() {
    curl -s https://api.github.com/repos/YouROK/TorrServer/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

installTorrServer() {
    echo " Устанавливаем и настраиваем TorrServer..."
    
    if [ -f "$dirInstall/TorrServer-linux-arm64" ]; then
        read -p " TorrServer уже установлен. Хотите обновить? ($(colorize green Y)es/$(colorize yellow N)o) " answer_up </dev/tty
        if [ "$answer_up" != "${answer_up#[YyДд]}" ]; then
            UpdateVersion
            return
        fi
    fi

    binName="TorrServer-linux-arm64"
    [ ! -d "$dirInstall" ] && mkdir -p "$dirInstall"
    
    urlBin="https://github.com/YouROK/TorrServer/releases/download/MatriX.136/TorrServer-linux-arm64"
    
    echo " Загружаем TorrServer..."
    curl -L -o "$dirInstall/$binName" "$urlBin"
    chmod +x "$dirInstall/$binName"
    
    addUser
    
    read -p " Хотите изменить порт для TorrServer (по умолчанию 8090)? ($(colorize yellow Y)es/$(colorize green N)o) " answer_cp </dev/tty
    if [ "$answer_cp" != "${answer_cp#[YyДд]}" ]; then
        read -p " Введите номер порта: " answer_port </dev/tty
        servicePort=$answer_port
    else
        servicePort="8090"
    fi
    
    read -p " Включить авторизацию на сервере? ($(colorize green Y)es/$(colorize yellow N)o) " answer_auth </dev/tty
    if [ "$answer_auth" != "${answer_auth#[YyДд]}" ]; then
        read -p " Пользователь: " answer_user </dev/tty
        isAuthUser=$answer_user
        read -p " Пароль: " answer_pass </dev/tty
        isAuthPass=$answer_pass
        echo " Сохраняем $isAuthUser:$isAuthPass в ${dirInstall}/accs.db"
        echo -e "{\n  \"$isAuthUser\": \"$isAuthPass\"\n}" > "$dirInstall/accs.db"
        authOptions="--port $servicePort --path $dirInstall --httpauth"
    else
        authOptions="--port $servicePort --path $dirInstall"
    fi
    
    # Создаем init script для OpenWrt
    cat << EOF > /etc/init.d/$serviceName
#!/bin/sh /etc/rc.common

START=99
STOP=10

USE_PROCD=1
PROG="$dirInstall/TorrServer-linux-arm64"

start_service() {
    procd_open_instance
    procd_set_param command \$PROG $authOptions
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    killall TorrServer-linux-arm64
}

reload_service() {
    stop
    start
}
EOF

    chmod +x /etc/init.d/$serviceName
    /etc/init.d/$serviceName enable
    /etc/init.d/$serviceName start
    
    serverIP=$(getIP)
    
    echo ""
    echo " TorrServer установлен в директории ${dirInstall}"
    echo ""
    echo " Теперь вы можете открыть браузер по адресу http://${serverIP}:${servicePort}"
    echo ""
    if [ -n "$isAuthUser" ]; then
        echo " Для авторизации используйте пользователя «$isAuthUser» с паролем «$isAuthPass»"
        echo ""
    fi
}

checkInstalled() {
    if [ -f "$dirInstall/TorrServer-linux-arm64" ]; then
        echo " - TorrServer найден в директории $dirInstall"
        return 0
    else
        echo " - TorrServer не найден"
        return 1
    fi
}

UpdateVersion() {
    /etc/init.d/$serviceName stop
    curl -L -o "$dirInstall/TorrServer-linux-arm64" "https://github.com/YouROK/TorrServer/releases/download/MatriX.136/TorrServer-linux-arm64"
    chmod +x "$dirInstall/TorrServer-linux-arm64"
    /etc/init.d/$serviceName start
    echo " - TorrServer обновлен!"
}

# Основной код
case $1 in
    -i|--install|install)
        initialCheck
        installTorrServer
        exit
        ;;
    -u|--update|update)
        initialCheck
        if checkInstalled; then
            UpdateVersion
        fi
        exit
        ;;
    -r|--remove|remove)
        uninstall
        exit
        ;;
    -h|--help|help)
        helpUsage
        exit
        ;;
    *)
        echo ""
        echo "============================================================="
        echo " Скрипт установки TorrServer для OpenWrt/FriendlyWrt"
        echo "============================================================="
        echo ""
        echo " Введите $scriptname -h для вызова справки"
        ;;
esac

while true; do
    echo ""
    read -p " Хотите установить или настроить TorrServer? ($(colorize green Y)es|$(colorize yellow N)o) Для удаления введите «$(colorize red D)elete» " ydn </dev/tty
    case $ydn in
        [YyДд]*)
            initialCheck
            installTorrServer
            break
            ;;
        [DdУу]*)
            uninstall
            break
            ;;
        [NnНн]*)
            break
            ;;
        *) echo " Введите $(colorize green Y)es, $(colorize yellow N)o или $(colorize red D)elete"
            ;;
    esac
done

echo " Удачи!"
echo ""
