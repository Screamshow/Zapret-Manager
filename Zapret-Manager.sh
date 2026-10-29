#!/bin/sh
# Zapret Manager fork for Forkop X; original project by StressOzz.
# Console and web UI use the same backend and configuration.
ZAPRET_MANAGER_VERSION="9.90.1"
MIRROR_BASE_URL="${ZAPRET_MANAGER_MIRROR:-https://mirror.51343.ru}"
MIRROR_BASE_URL="${MIRROR_BASE_URL%/}"
GH_RAW="https://raw.githubusercontent.com"
ZM_LUCI_URL="${GH_RAW}/Screamshow/Zapret-Manager/main/ZapretManager_LuCI.sh"
BACKEND="/opt/zapret-manager-luci/backend.sh"

install_panel() {
    local tmp url
    tmp="$(mktemp /tmp/zm-console.XXXXXX)" || return 1
    trap 'rm -f "$tmp"' EXIT HUP INT TERM
    for url in "$MIRROR_BASE_URL/zapret-manager/proxy/raw.githubusercontent.com/Screamshow/Zapret-Manager/main/ZapretManager_LuCI.sh" "$ZM_LUCI_URL"; do
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL --connect-timeout 10 --max-time 120 -o "$tmp" "$url"
        else
            wget -q -T 30 -O "$tmp" "$url"
        fi && [ -s "$tmp" ] && grep -q '^# Version: ' "$tmp" && sh -n "$tmp" && break
        : > "$tmp"
    done
    [ -s "$tmp" ] || { rm -f "$tmp"; trap - EXIT HUP INT TERM; echo 'Не удалось скачать установщик панели'; return 1; }
    sh "$tmp"
    local rc=$?
    rm -f "$tmp"
    trap - EXIT HUP INT TERM
    return "$rc"
}

case "$1" in
    w|--install-web) install_panel; exit $? ;;
esac
if [ ! -x "$BACKEND" ]; then
    echo 'Устанавливаем общий backend и панель Zapret Manager'
    install_panel || exit 1
fi
case "$1" in
    --auto-best) exec "$BACKEND" test_action auto_tick x ;;
    --status) exec "$BACKEND" status ;;
    '') ;;
    *) echo 'Параметры: --status, --auto-best, --install-web'; exit 1 ;;
esac

service_menu() {
    local method="$1" action
    if [ "$method" = term_action ]; then
        printf 'Действие (install/start/restart/remove, Enter — назад): '
    else
        printf 'Действие (install/update/start/stop/restart/remove, Enter — назад): '
    fi
    IFS= read -r action || return
    case "$method:$action" in term_action:update|term_action:stop) echo 'Неизвестное действие'; return ;; esac
    case "$action" in
        install|update|start|stop|restart|remove) "$BACKEND" "$method" "$action" ;;
        '') return ;;
        *) echo 'Неизвестное действие' ;;
    esac
}

while :; do
    printf '\nZapret Manager — Forkop X\n1) Дашборд\n2) Zapret\n3) Zapret2\n4) Hosts\n5) Терминал\nw) Установить/обновить Web UI и LuCI\nEnter) Выход\nВыберите пункт: '
    IFS= read -r choice || exit 0
    case "$choice" in
        1) "$BACKEND" status; "$BACKEND" health ;;
        2) service_menu zapret_action ;;
        3) service_menu zapret2_action ;;
        4) "$BACKEND" hosts_status; echo 'Редактирование Hosts доступно в Web UI и LuCI.' ;;
        5) service_menu term_action ;;
        w|W) install_panel ;;
        '') exit 0 ;;
        *) echo 'Неизвестный пункт' ;;
    esac
done
