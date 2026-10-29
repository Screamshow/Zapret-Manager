#!/bin/sh
read -r _ _ ZM_NEW_VER <<'ZM_VERSION_EOF'
# Version: 4.71.1
# Forkop-Manager-Contract: five-section-v1
ZM_VERSION_EOF
set -e

GREEN="\033[1;32m"; CYAN="\033[1;36m"; YELLOW="\033[1;33m"; MAGENTA="\033[1;35m"; BLUE="\033[0;34m"; NC="\033[0m"; DGRAY="\033[38;5;244m"

_zmi_say() { echo -e "${CYAN}==>${NC} $*"; }
_zmi_ok() { echo -e "   ${GREEN}✓${NC} $*"; }
_zmi_step() { echo -e "   → $*"; }
_zmi_warn() { echo -e "   ${YELLOW}!${NC} $*"; }
if command -v apk >/dev/null 2>&1; then PM="apk"; INSTALL="apk add"
else PM="opkg"; INSTALL="opkg install"; fi
_zmi_has() {
	if [ "$PM" = apk ]; then apk info -e "$1" >/dev/null 2>&1
	else opkg list-installed 2>/dev/null | grep -q "^$1 "; fi
}
_zmi_pkg() {
	# Forkop stages file rollback; package changes are a separate transaction.
	if [ "${ZM_FORKOP_TRANSACTION:-0}" = 1 ]; then _zmi_has "$1"; return $?; fi
	if _zmi_has "$1"; then _zmi_ok "Пакет $1 уже установлен"; return 0; fi
	_zmi_step "Устанавливаем пакет $1"
	$INSTALL "$1" >/dev/null 2>&1 || true
	if ! _zmi_has "$1"; then
		_zmi_step "Не получилось — обновляем список пакетов и пробуем ещё раз"
		$PM update >/dev/null 2>&1 || true
		$INSTALL "$1" >/dev/null 2>&1 || true
	fi
	if _zmi_has "$1"; then _zmi_ok "Пакет $1 установлен"; return 0; fi
	_zmi_warn "Пакет $1 не установился — проверьте интернет на роутере. $2"
	return 1
}
clear 2>/dev/null || true
echo -e "${MAGENTA}Zapret Manager для LuCI и Web $ZM_NEW_VER — установка${NC}\n"
_zmi_say "Проверяем, что панель сейчас ничем не занята"

for _zm_pid in /tmp/zapret-manager-luci/*.pid; do
	[ -f "$_zm_pid" ] || continue
	_zm_job="$(basename "$_zm_pid" .pid)"
	case "$_zm_job" in versions|*_download) continue ;; esac
	if kill -0 "$(cat "$_zm_pid" 2>/dev/null)" 2>/dev/null && ! grep -q '^__DONE__' "/tmp/zapret-manager-luci/$_zm_job.log" 2>/dev/null; then
		echo -e "${YELLOW}Сейчас в панели идёт операция ($_zm_job) — дождитесь её окончания и запустите установку снова${NC}"
		exit 1
	fi
done

_zm_n=0
while [ -f /tmp/zm_uninstall_panel.sh ] && ps w 2>/dev/null | grep -q '[z]m_uninstall_panel\.sh'; do
	[ "$_zm_n" = 0 ] && _zmi_step "Панель сейчас удаляется — ждём окончания"
	if [ "$_zm_n" -ge 60 ]; then
		echo -e "${YELLOW}Удаление панели не закончилось за минуту — запустите установку чуть позже${NC}"
		exit 1
	fi
	sleep 1; _zm_n=$((_zm_n + 1))
done
_zmi_ok "Можно ставить"
_zmi_say "Убираем файлы прежней версии панели"
if [ "${ZM_FORKOP_TRANSACTION:-0}" != 1 ] && [ -s /tmp/zapret-manager-luci/resolv.conf.zm-bak ]; then
	if [ -e /tmp/resolv.conf ]; then cat /tmp/zapret-manager-luci/resolv.conf.zm-bak > /tmp/resolv.conf 2>/dev/null || true
	else cat /tmp/zapret-manager-luci/resolv.conf.zm-bak > /etc/resolv.conf 2>/dev/null || true; fi
fi
rm -rf \
	/tmp/zapret-manager-luci* \
	/tmp/zm_uninstall_panel.sh \
	/tmp/luci-indexcache* \
	/tmp/luci-modulecache/* 2>/dev/null

_zmi_ok "Готово"
_zmi_say "Записываем файлы панели"
mkdir -p /opt/zapret-manager-luci
chmod 0755 /opt/zapret-manager-luci
_zm_old_ver="$(sed -n 's/^ZM_VERSION="\([0-9][0-9.]*\)"$/\1/p' /opt/zapret-manager-luci/backend.sh 2>/dev/null | head -n 1)"
cat > '/opt/zapret-manager-luci/backend.sh.zm-new' << 'ZM_INSTALLER_EOF'
#!/bin/sh
umask 022

CONF="/etc/config/zapret"
ZM_VERSION="@ZM_VERSION@"
ZM_FLAVOR="forkop-five-section-v1"
ZM_SCRIPT_URL="https://raw.githubusercontent.com/Screamshow/Zapret-Manager/refs/heads/main/ZapretManager_LuCI.sh"
GH_RAW="https://raw.githubusercontent.com"
GH_MAIN="https://github.com"

EXCLUDE_URL="${GH_RAW}/Screamshow/Zapret-Manager/refs/heads/main/zapret-hosts-user-exclude.txt"
FLOWSEAL_ZIP="${GH_MAIN}/Flowseal/zapret-discord-youtube/archive/refs/heads/main.zip"
FLOWSEAL_FAKE_RAW="${GH_MAIN}/Flowseal/zapret-discord-youtube/raw/refs/heads/main/bin"
STR_URL="${GH_RAW}/Screamshow/Zapret-Manager/refs/heads/main/files/StrYoutube"
ZAPRET_VER="72.20260307"
JOBS_DIR="/tmp/zapret-manager-luci"
ZM_STATE_DIR="/opt/zapret-manager-luci/state"
CRON_FILE="/etc/crontabs/root"
ZM_GHP_FILE="$ZM_STATE_DIR/ghproxy"
ZM_GHP_FAIL="$JOBS_DIR/ghproxy.fail"
ZM_GHP_LOG="$JOBS_DIR/ghproxy.log"
ZM_GHP_LIST="gh-proxy.org ghfast.top gh.llkk.cc ghproxy.net"
_zm_ghp_load() {
	[ -n "$ZM_GHP_MODE" ] && return 0
	ZM_GHP_MODE=off
	grep -qE '^mode=(auto|always)$' "$ZM_GHP_FILE" 2>/dev/null && ZM_GHP_MODE=auto
	return 0
}
_zm_gh_host() {
	case "$1" in
		https://raw.githubusercontent.com/*|https://github.com/*|https://codeload.github.com/*|https://objects.githubusercontent.com/*|https://release-assets.githubusercontent.com/*|https://gist.githubusercontent.com/*|https://gist.github.com/*) return 0 ;;
	esac
	return 1
}
ZM_MIR_BASE="${ZAPRET_MANAGER_MIRROR:-https://mirror.51343.ru}"; ZM_MIR_BASE="${ZM_MIR_BASE%/}"
ZM_MIR_PROXY="$ZM_MIR_BASE/zapret-manager/proxy"
# Hosts the mirror forwards. codeload.github.com is left out on purpose: the
# mirror answers "upstream host is not allowed" for it, so those fetches stay
# on the direct and gh-proxy path below.
_zm_mir_host() {
	case "$1" in
		https://raw.githubusercontent.com/*|https://github.com/*|https://api.github.com/*|https://cdn.jsdelivr.net/*|https://packages.routerich.ru/*) return 0 ;;
	esac
	return 1
}
_zm_mir_url() { printf '%s/%s' "$ZM_MIR_PROXY" "${1#https://}"; }
# Same test as _zm_dl_sane, repeated here because that one is defined further
# down the file than this code runs.
_zm_mir_sane() { [ -s "$1" ] && ! head -c 1024 "$1" | grep -qiE '<(!doctype|html|head|body)'; }
_zm_mir_exec() {
	local t="$1" a x=0
	shift
	for a; do
		[ "$x" = 0 ] && { set --; x=1; }
		if _zm_mir_host "$a"; then set -- "$@" "$(_zm_mir_url "$a")"; else set -- "$@" "$a"; fi
	done
	command "$t" "$@"
}
_zm_ghp_say() {
	[ -n "$ZM_JOB_LOG" ] && printf '%s\n' "$1" >> "$ZM_JOB_LOG" 2>/dev/null
	mkdir -p "$JOBS_DIR" 2>/dev/null
	{ tail -n 39 "$ZM_GHP_LOG" 2>/dev/null; printf '%s|%s\n' "$(date +%s)" "$(printf '%s' "$1" | sed 's/^[[:space:]]*//')"; } > "$ZM_GHP_LOG.$$" 2>/dev/null && mv -f "$ZM_GHP_LOG.$$" "$ZM_GHP_LOG" 2>/dev/null
	return 0
}
_zm_ghp_why() {
	case "$1:$2" in
		curl:5|curl:6) echo "не нашёлся адрес (DNS)" ;;
		curl:7) echo "не удалось подключиться" ;;
		curl:28) echo "не ответил вовремя" ;;
		curl:35|wget:5) echo "ошибка защищённого соединения" ;;
		curl:52|curl:56|curl:18) echo "соединение оборвалось" ;;
		wget:4) echo "ошибка сети" ;;
		*) return 1 ;;
	esac
}
_zm_ghp_out() {
	local t="$1" a nx=""
	shift
	for a; do
		if [ -n "$nx" ]; then [ "$a" = - ] || printf '%s' "$a"; return 0; fi
		case "$t:$a" in
			curl:-o|curl:--output|wget:-O|wget:-qO|wget:--output-document) nx=1 ;;
			curl:-o?*) [ "${a#-o}" = - ] || printf '%s' "${a#-o}"; return 0 ;;
			wget:-qO?*) [ "${a#-qO}" = - ] || printf '%s' "${a#-qO}"; return 0 ;;
			wget:-O?*) [ "${a#-O}" = - ] || printf '%s' "${a#-O}"; return 0 ;;
		esac
	done
	return 0
}
_zm_ghp_exec() {
	local t="$1" pre="$2" a x=0
	shift 2
	for a; do
		[ "$x" = 0 ] && { set --; x=1; }
		if _zm_gh_host "$a"; then set -- "$@" "$pre$a"; else set -- "$@" "$a"; fi
	done
	command "$t" "$@"
}
_zm_ghp_run() {
	local t="$1" a gh="" mir="" rc why out nm m
	shift
	for a; do _zm_gh_host "$a" && { gh="$a"; break; }; done
	[ -n "$gh" ] || { command "$t" "$@"; return; }
	_zm_ghp_load
	for a; do _zm_mir_host "$a" && { mir="$a"; break; }; done
	if [ -n "$mir" ] && [ -z "$ZM_MIR_OFF" ]; then
		out="$(_zm_ghp_out "$t" "$@")"
		_zm_mir_exec "$t" "$@"; rc=$?
		if [ "$rc" = 0 ] && { [ -z "$out" ] || [ "$out" = /dev/null ] || _zm_mir_sane "$out"; }; then return 0; fi
		[ -n "$out" ] && [ "$out" != /dev/null ] && rm -f "$out" 2>/dev/null
		nm="${mir%%\?*}"; nm="${nm##*/}"; [ -n "$nm" ] || nm="$mir"
		_zm_ghp_say "   · $nm не получен с зеркала $ZM_MIR_BASE — пробуем напрямую"
	fi
	command "$t" "$@"; rc=$?
	if [ "$rc" = 0 ]; then [ "$ZM_GHP_MODE" = off ] && rm -f "$ZM_GHP_FAIL" 2>/dev/null; return 0; fi
	why="$(_zm_ghp_why "$t" "$rc")" || return $rc
	if [ "$ZM_GHP_MODE" != auto ] || [ -n "$ZM_GHP_NOMIR" ]; then
		[ "$ZM_GHP_MODE" = off ] && { mkdir -p "$JOBS_DIR" 2>/dev/null; date +%s > "$ZM_GHP_FAIL" 2>/dev/null; }
		return $rc
	fi
	nm="${gh%%\?*}"; nm="${nm##*/}"; [ -n "$nm" ] || nm="$gh"
	out="$(_zm_ghp_out "$t" "$@")"
	if [ -z "$out" ] && [ "$t:$rc" != curl:6 ] && [ "$t:$rc" != curl:7 ]; then
		_zm_ghp_say "   · GitHub: $nm — $why. Через зеркало не повторяем: часть ответа уже получена"
		return $rc
	fi
	_zm_ghp_say "   · GitHub: $nm не скачался напрямую — $why. Пробуем через зеркала"
	for m in $ZM_GHP_LIST; do
		[ -n "$out" ] && [ "$out" != /dev/null ] && rm -f "$out" 2>/dev/null
		_zm_ghp_exec "$t" "https://$m/" "$@"; rc=$?
		if [ "$rc" = 0 ]; then
			if [ -n "$out" ] && [ "$out" != /dev/null ] && ! _zm_dl_sane "$out"; then
				_zm_ghp_say "   · $m: вместо файла пришла страница ошибки"
				rc=1; continue
			fi
			_zm_ghp_say "   ✓ $nm скачан через зеркало $m. Следующие загрузки — снова напрямую"
			return 0
		fi
		why="$(_zm_ghp_why "$t" "$rc")" || why="ошибка $rc"
		_zm_ghp_say "   · $m: не скачалось — $why"
	done
	_zm_ghp_say "   !! $nm не скачался ни напрямую, ни через зеркала ($(echo $ZM_GHP_LIST | sed 's/ /, /g'))"
	[ "$rc" = 0 ] && rc=1
	return $rc
}
_zm_has() { local d IFS=:; for d in ${PATH:-/usr/sbin:/usr/bin:/sbin:/bin}; do [ -n "$d" ] && [ -x "$d/$1" ] && [ ! -d "$d/$1" ] && return 0; done; return 1; }
curl() { _zm_ghp_run curl "$@"; }
wget() { _zm_ghp_run wget "$@"; }
_zm_fetch_ok() {
	[ -s "$1" ] || return 1
	[ -n "$ZM_FETCH_ANY" ] || ! head -c 1024 "$1" | grep -qiE '<(!doctype|html|head|body)' || return 1
	ZM_FETCH_SIZE="$(wc -c < "$1" 2>/dev/null | tr -d ' ')"
	return 0
}
_zm_fetch() {
	local u="$1" o="$2" tm="${3:-120}" rg="$4" ef code rc e i
	ZM_FETCH_ERR=""; ZM_FETCH_SIZE=0
	ef="$o.zmerr"
	rm -f "$o"
	if _zm_has curl; then
		code="$(curl -fsSL --connect-timeout 10 --max-time "$tm" ${rg:+-r "$rg"} -A "Mozilla/5.0" -o "$o" -w '%{http_code}' "$u" 2>"$ef")"; rc=$?
		code="$(printf '%s' "$code" | tail -c 3)"
		e="$(tail -n 1 "$ef" 2>/dev/null | sed 's/^curl: ([0-9]*) //')"; rm -f "$ef"
		if [ "$rc" = 0 ] && _zm_fetch_ok "$o"; then return 0; fi
		rm -f "$o"
		if [ "$rc" = 22 ]; then
			case "$code" in
				404|410) ZM_FETCH_ERR="файла нет на сервере (HTTP $code)"; return 1 ;;
				403) ZM_FETCH_ERR="сервер отказал в доступе (HTTP 403)" ;;
				429) ZM_FETCH_ERR="сервер просит подождать — слишком много запросов (HTTP 429)" ;;
				5??) ZM_FETCH_ERR="сервер временно не работает (HTTP $code)" ;;
				*) ZM_FETCH_ERR="сервер ответил ошибкой HTTP ${code:-?}" ;;
			esac
		elif [ "$rc" = 0 ]; then ZM_FETCH_ERR="вместо файла пришла веб-страница"
		else ZM_FETCH_ERR="$(_zm_ghp_why curl "$rc" || echo "${e:-curl: ошибка $rc}")"; fi
	fi
	if [ -z "$rg" ] && _zm_has wget; then
		e="$(ZM_GHP_NOMIR=1; wget -T 20 -U "Mozilla/5.0" -O "$o" "$u" 2>&1)"; rc=$?
		if [ "$rc" = 0 ] && _zm_fetch_ok "$o"; then ZM_FETCH_ERR=""; return 0; fi
		rm -f "$o"
		if [ "$rc" = 0 ]; then e="вместо файла пришла веб-страница"
		else e="$(_zm_ghp_why wget "$rc" || printf '%s\n' "$e" | grep -v '^Downloading\|^Connecting\|^Writing\|^Download completed\|^$' | tail -n 1)"; fi
		ZM_FETCH_ERR="${ZM_FETCH_ERR:+$ZM_FETCH_ERR; }wget: ${e:-не скачалось}"
	fi
	[ -n "$ZM_FETCH_ERR" ] || ZM_FETCH_ERR="на роутере нет ни curl, ни wget"

	return 1
}
_zm_size_txt() { local b="${1:-0}"; if [ "$b" -lt 1024 ]; then echo "$b Б"; elif [ "$b" -lt 1048576 ]; then echo "$(( (b + 512) / 1024 )) КБ"; else awk -v b="$b" 'BEGIN { printf "%.1f МБ\n", b / 1048576 }'; fi; }
_zm_get() {
	local nm="${3:-${1##*/}}"
	if _zm_fetch "$1" "$2" "${4:-120}"; then echo "   ✓ $nm — $(_zm_size_txt "$ZM_FETCH_SIZE")"; return 0; fi
	echo "   !! $nm — не скачался: $ZM_FETCH_ERR"
	return 1
}
gh_mirrors() { _zm_ghp_load; [ "$ZM_GHP_MODE" = auto ] && echo $ZM_GHP_LIST; return 0; }

HOSTS_FILE="/etc/hosts"
EXPERT_MODE_FILE="/opt/zapret-manager-luci/expert_mode"
PORTS_UDP="88,1024-2407,2409-4499,4502-19293,19345-49999,50101-65535"
PORTS_TCP="2099,2802,2302,2502,3478-3480,3724,6000-8000,8085,8090,8100,8903,8904,25565,27015-27030,27036-27037,35500-35600,50001,60442"
{ [ -d "$JOBS_DIR" ] && [ -d "$ZM_STATE_DIR" ]; } || mkdir -p "$JOBS_DIR" "$ZM_STATE_DIR" 2>/dev/null

if command -v opkg >/dev/null 2>&1; then
	PKG="opkg"; PKG_ADD="opkg install"; PKG_DEL="opkg remove"; PKG_UPD="opkg update"
	RAZ="ipk"
else
	PKG="apk"; PKG_ADD="apk add --allow-untrusted"; PKG_DEL="apk del"; PKG_UPD="apk update"
	RAZ="apk"
fi

esc() {
	case "$1" in *[!A-Za-z0-9\ ._:/@+=,%-]*) ;; *) printf '%s' "$1"; return 0 ;; esac
	printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g' | tr '\n' ' '
}

esc_ml() {
	printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' | sed 's/\r$//; s/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g' | sed ':a;N;$!ba;s/\n/\\n/g'
}

_job_running() {
	local pid="$JOBS_DIR/$1.pid"
	[ -f "$pid" ] && kill -0 "$(cat "$pid" 2>/dev/null)" 2>/dev/null || return 1
	! grep -q '^__DONE__' "$JOBS_DIR/$1.log" 2>/dev/null
}

job_status() {
	local name="$1"
	local pid="$JOBS_DIR/$name.pid"
	local log="$JOBS_DIR/$name.log"
	local running="false" done="false" rc=""
	_job_running "$name" && running="true"
	if [ -f "$log" ] && grep -q '^__DONE__' "$log"; then
		done="true"
		rc=$(grep '^__DONE__' "$log" | tail -1 | awk '{print $2}')
	fi
	printf '{"running":%s,"done":%s,"rc":"%s"}\n' "$running" "$done" "$rc"
}

log_tail() {
	local name="$1"
	local log="$JOBS_DIR/$name.log"
	[ -f "$log" ] || { echo '{"lines":""}'; return; }
	printf '{"lines":"%s"}\n' "$(esc_ml "$(tail -n 300 "$log" | grep -v '^__DONE__')")"
}

_confz() {
	if [ "$PKG" = "apk" ]; then echo "/etc/apk/repositories.d/distfeeds.list"
	else echo "/etc/opkg/distfeeds.conf"; fi
}

ZM_MIRROR_STATE="$ZM_STATE_DIR/mirror.state"
_mirror_host() {
	grep -v '^[[:space:]]*#' "$(_confz)" 2>/dev/null | grep -oE 'https?://[^ ]+/(releases|snapshots)/' | head -n1 | sed -E 's#^https?://##; s#/(releases|snapshots)/$##'
}

_mirror_name() {
	local f url
	f="$(_confz)"
	[ -f "$f" ] || { echo "файл не найден"; return; }
	url="$(_mirror_host)"
	[ -n "$url" ] || url=$(head -n1 "$f")
	case "$url" in
		*mirror-03.infra.openwrt.org*) echo "Infra OpenWrt" ;;
		*c3sl.ufpr.br*) echo "Brazil" ;;
		*ustc.edu.cn*) echo "China" ;;
		*tetaneutral.net*) echo "France" ;;
		*garr.it*) echo "Italy" ;;
		*marwan.ma*) echo "Morocco" ;;
		*pixeldeck.net*) echo "USA" ;;
		*rwth-aachen.de*) echo "Germany" ;;
		*downloads.openwrt.org*) echo "default / OpenWrt" ;;
		'') echo "неизвестное" ;;
		*) echo "$url" ;;
	esac
}

_mirror_info() {
	local h how="" ts=""
	h="$(_mirror_host)"
	if [ -s "$ZM_MIRROR_STATE" ] && [ "$(cut -f1 "$ZM_MIRROR_STATE")" = "$h" ]; then
		how="$(cut -f3 "$ZM_MIRROR_STATE")"; ts="$(cut -f2 "$ZM_MIRROR_STATE")"
	fi
	[ "$h" = downloads.openwrt.org ] && how=""
	printf '"mirror":"%s","mirror_host":"%s","mirror_how":"%s","mirror_at":%s' "$(esc "$(_mirror_name)")" "$(esc "$h")" "$(esc "$how")" "${ts:-0}"
}

_cpu_stat() { awk '/^cpu / { t = 0; for (i = 2; i <= NF; i++) t += $i; print t, $5 + $6; exit }' /proc/stat 2>/dev/null; }

_cpu_load() {
	local f="$JOBS_DIR/cpu.stat" now prev="" t1 i1 t2 i2 p
	now="$(_cpu_stat)"
	[ -n "$now" ] || return 0
	if [ -s "$f" ] && [ -z "$(find "$f" -mmin +1 2>/dev/null)" ]; then
		read -r prev 2>/dev/null < "$f"
	fi
	if [ -z "$prev" ]; then
		prev="$now"
		sleep 1
		now="$(_cpu_stat)"
	fi
	set -- $prev $now
	t1=$1; i1=$2; t2=$3; i2=$4
	if [ $((t2 - t1)) -lt 50 ] 2>/dev/null && [ -s "$f.pct" ]; then
		p=""; read -r p 2>/dev/null < "$f.pct"
		[ -n "$p" ] && { echo "$p"; return 0; }
	fi
	[ "$t2" -gt "$t1" ] 2>/dev/null || { echo 0; return 0; }
	echo "$now" > "$f"
	p=$(( (100 * ((t2 - t1) - (i2 - i1)) + (t2 - t1) / 2) / (t2 - t1) ))
	echo "$p" > "$f.pct"
	echo "$p"
}

_cpu_temp() {
	local z t typ best="" v
	for z in /sys/class/thermal/thermal_zone*; do
		[ -r "$z/temp" ] || continue
		t=""; read -r t 2>/dev/null < "$z/temp"
		case "$t" in ''|*[!0-9-]*) continue ;; esac
		typ=""; read -r typ 2>/dev/null < "$z/type"
		case "$typ" in *cpu*|*CPU*|*soc*|*SOC*) best="$t"; break ;; esac
		{ [ -z "$best" ] || [ "$t" -gt "$best" ]; } && best="$t"
	done
	if [ -z "$best" ]; then
		for z in /sys/class/hwmon/hwmon*/temp1_input; do
			[ -r "$z" ] || continue
			t=""; read -r t 2>/dev/null < "$z"
			case "$t" in ''|*[!0-9-]*) continue ;; esac
			best="$t"; break
		done
	fi
	[ -n "$best" ] || return 0
	if [ "$best" -gt 1000 ] 2>/dev/null; then v=$(( (best + 50) / 100 )); echo "$((v / 10)).$((v % 10))"
	else echo "$best"; fi
}

_inet_ping() {
	local h out ms
	for h in ya.ru vk.ru; do
		out=$(ping -4 -c 1 -W 2 "$h" 2>/dev/null)
		ms=$(echo "$out" | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | head -n1)
		[ -n "$ms" ] && { echo "$(date +%s) ok ${ms%%.*}"; return 0; }
	done
	for h in ya.ru vk.ru; do
		ms=$(curl -s -o /dev/null --connect-timeout 4 --max-time 6 -w '%{time_namelookup} %{time_connect}' "http://$h/" 2>/dev/null) || continue
		echo "$(date +%s) ok $(echo "$ms" | awk '{ v = ($2 - $1) * 1000; if (v < 1) v = 1; printf "%d", v }')"
		return 0
	done
	for h in 77.88.8.8 1.1.1.1; do
		ping -4 -c 1 -W 2 "$h" >/dev/null 2>&1 && { echo "$(date +%s) nodns"; return 0; }
	done
	for h in 1.1.1.1 8.8.8.8; do
		curl -s -o /dev/null --connect-timeout 4 --max-time 6 "http://$h/" >/dev/null 2>&1 && { echo "$(date +%s) nodns"; return 0; }
	done
	echo "$(date +%s) fail"
}
_inet_state() {
	local f="$ZM_STATE_DIR/inet" t r ms age
	read -r t r ms 2>/dev/null < "$f"
	age=$(( $(date +%s) - ${t:-0} ))
	if [ "$age" -ge 10 ] || [ "$age" -lt 0 ]; then
		mkdir -p "$ZM_STATE_DIR"
		if mkdir "$f.lock" 2>/dev/null; then
			( _inet_ping > "$f.new" 2>/dev/null && mv -f "$f.new" "$f"; rmdir "$f.lock" ) >/dev/null 2>&1 &
		elif [ -n "$(find "$f.lock" -mmin +1 2>/dev/null)" ]; then
			rmdir "$f.lock" 2>/dev/null
		fi
	fi
	[ -n "$r" ] && [ "$age" -lt 120 ] && echo "$r $ms"
}

ZM_SI_STATIC="$JOBS_DIR/si.static"
_si_static() {
	local f="$ZM_SI_STATIC" line="" model arch owrt target
	if [ -s "$f" ] && [ ! "$(_confz)" -nt "$f" ] && [ ! "$ZM_MIRROR_STATE" -nt "$f" ] && [ -z "$(find "$f" -mmin +10 2>/dev/null)" ]; then
		IFS= read -r line 2>/dev/null < "$f"
		[ -n "$line" ] && { printf '%s\n' "$line"; return 0; }
	fi
	model=$(cat /tmp/sysinfo/model 2>/dev/null)
	arch=$(grep DISTRIB_ARCH /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)
	owrt=$(grep '^DISTRIB_RELEASE=' /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)
	target=$(grep '^DISTRIB_TARGET=' /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)
	line="$(printf '%s,"model":"%s","arch":"%s","openwrt":"%s","target":"%s","hostname":"%s","kernel":"%s"' "$(_mirror_info)" \
		"$(esc "$model")" "$(esc "$arch")" "$(esc "$owrt")" "$(esc "$target")" "$(esc "$(cat /proc/sys/kernel/hostname 2>/dev/null)")" "$(esc "$(uname -r 2>/dev/null)")")"
	printf '%s\n' "$line" > "$f.$$" 2>/dev/null && mv -f "$f.$$" "$f" 2>/dev/null || rm -f "$f.$$"
	printf '%s\n' "$line"
}

system_info() {
	local df_j inet inet_ms
	df_j=$(df -h /tmp / 2>/dev/null | awk 'function c(x) { gsub(/["\\]/, "", x); return x }
		NR == 2 { a = $3; b = $4 } NR == 3 { u = $3; v = $4 }
		END { printf "\"tmp_used\":\"%s\",\"tmp_free\":\"%s\",\"root_used\":\"%s\",\"root_free\":\"%s\"", c(a), c(b), c(u), c(v) }')
	[ -n "$df_j" ] || df_j='"tmp_used":"","tmp_free":"","root_used":"","root_free":""'
	set -- $(_inet_state)
	inet="$1"; inet_ms="$2"
	printf '{%s,%s,"cpu_temp":"%s","cpu_load":"%s","inet":"%s","inet_ms":"%s"}\n' "$(_si_static)" "$df_j" "$(_cpu_temp)" "$(_cpu_load)" "$inet" "$inet_ms"
}

case "$1" in
	system_info) system_info; exit ;;
	job_status)  job_status "$2"; exit ;;
	log_tail)    log_tail "$2"; exit ;;
esac

INSTALL="_zm_pkg_add";  UPDATE="_zm_pkg_update"

ZM_NL='
'
_zm_re() { case "$1" in *"$ZM_NL"*) return 1 ;; esac; printf '%s\n' "$1" | grep -qE -- "$2"; }

ZM_TMO=""
_zm_tmo_ok() {
	[ -n "$ZM_TMO" ] || { if timeout 1 true >/dev/null 2>&1; then ZM_TMO=1; else ZM_TMO=0; fi; }
	[ "$ZM_TMO" = 1 ]
}
_zm_tmo() {
	local s="$1" p w rc
	shift
	case "$(type "$1" 2>/dev/null)" in *function*) ;; *) if _zm_tmo_ok; then timeout "$s" "$@"; return; fi ;; esac
	case "$s" in ''|*[!0-9]*) s=60 ;; esac
	{ "$@" <&3 3<&- & } 3<&0
	p=$!
	( i=0
	  while [ "$i" -lt "$s" ] && kill -0 "$p" 2>/dev/null; do sleep 1; i=$((i + 1)); done
	  if kill -0 "$p" 2>/dev/null; then kill "$p" 2>/dev/null; sleep 1; kill -9 "$p" 2>/dev/null; fi ) >/dev/null 2>&1 </dev/null &
	w=$!
	wait "$p" 2>/dev/null; rc=$?
	wait "$w" 2>/dev/null
	case "$rc" in 137|143) rc=124 ;; esac
	return $rc
}

ZM_JESC_AWK='function jesc(s,    o, i, c, n) {
	o = ""; n = length(s)
	for (i = 1; i <= n; i++) {
		c = substr(s, i, 1)
		if (c == "\\") o = o "\\\\"
		else if (c == "\"") o = o "\\\""
		else if (c == "\t") o = o "\\t"
		else if (c != "\r") o = o c
	}
	return o
}
'

_zm_zone_sec() {
	local z
	for z in $(uci -q -X show firewall | sed -n "s/^firewall\.\([^.=]*\)=zone\$/\1/p"); do
		[ "$(uci -q get "firewall.$z.name")" = "$1" ] && { echo "$z"; return 0; }
	done
	return 1
}
_zm_zone_of_net() {
	local z
	for z in $(uci -q -X show firewall | sed -n "s/^firewall\.\([^.=]*\)=zone\$/\1/p"); do
		case " $(uci -q get "firewall.$z.network") " in *" $1 "*) uci -q get "firewall.$z.name"; return 0 ;; esac
	done
	return 1
}
_zm_lan_zone() {
	local c="$JOBS_DIR/lanzone" v=""
	if [ -s "$c" ] && { [ ! -e /etc/config/firewall ] || [ "$c" -nt /etc/config/firewall ]; }; then read -r v < "$c"; [ -n "$v" ] && { echo "$v"; return 0; }; fi
	v="$(_zm_lan_zone_find)"
	[ -n "$v" ] && { printf '%s\n' "$v" > "$c.$$" 2>/dev/null && mv -f "$c.$$" "$c" 2>/dev/null; }
	echo "${v:-lan}"
}
_zm_lan_zone_find() {
	local f w
	_zm_zone_of_net lan && return 0
	_zm_zone_sec lan >/dev/null && { echo lan; return 0; }
	w="$(_zm_wan_zone)"
	for f in $(uci -q -X show firewall | sed -n "s/^firewall\.\([^.=]*\)=forwarding\$/\1/p"); do
		[ "$(uci -q get "firewall.$f.dest")" = "$w" ] && { uci -q get "firewall.$f.src"; return 0; }
	done
	echo lan
}
_zm_wan_zone() { _zm_zone_of_net wan || echo wan; }
_zm_lan_nets() {
	local s n=""
	s="$(_zm_zone_sec "$(_zm_lan_zone)")" && n="$(uci -q get "firewall.$s.network")"
	echo "${n:-lan}"
}
_zm_lan_devs() {
	local s n d out=""
	for n in $(_zm_lan_nets); do
		d="$(ifstatus "$n" 2>/dev/null | jsonfilter -e '@.l3_device' 2>/dev/null)"
		[ -n "$d" ] || d="$(ifstatus "$n" 2>/dev/null | jsonfilter -e '@.device' 2>/dev/null)"
		[ -n "$d" ] || d="$(uci -q get "network.$n.device")"
		[ -n "$d" ] && [ -d "/sys/class/net/$d" ] || continue
		case " $out " in *" $d "*) ;; *) out="$out $d" ;; esac
	done
	if s="$(_zm_zone_sec "$(_zm_lan_zone)")"; then
		for d in $(uci -q get "firewall.$s.device"); do
			[ -d "/sys/class/net/$d" ] || continue
			case " $out " in *" $d "*) ;; *) out="$out $d" ;; esac
		done
	fi
	[ -n "$out" ] || out="br-lan"
	echo $out
}
_zm_lan_ip() {
	local n ip d
	ip="$(ifstatus lan 2>/dev/null | jsonfilter -e "@['ipv4-address'][0].address" 2>/dev/null)"
	[ -n "$ip" ] && { echo "$ip"; return 0; }
	for n in $(_zm_lan_nets); do
		[ "$n" = lan ] && continue
		ip="$(ifstatus "$n" 2>/dev/null | jsonfilter -e "@['ipv4-address'][0].address" 2>/dev/null)"
		[ -n "$ip" ] && { echo "$ip"; return 0; }
	done
	ip="$(uci -q get network.lan.ipaddr 2>/dev/null | awk '{ print $1 }' | cut -d/ -f1)"
	[ -n "$ip" ] && { echo "$ip"; return 0; }
	for d in $(_zm_lan_devs); do
		ip="$(ip -4 -o addr show dev "$d" 2>/dev/null | awk '{ print $4; exit }' | cut -d/ -f1)"
		[ -n "$ip" ] && { echo "$ip"; return 0; }
	done
	return 1
}

_pkg_is_installed() {
	if [ "$PKG" = "apk" ]; then apk info -e "$1" >/dev/null 2>&1
	elif [ -f /usr/lib/opkg/status ]; then awk -v p="$1" '$1 == "Package:" { x = ($2 == p) } x && $1 == "Status:" && / (installed|unpacked)$/ { f = 1; exit } END { exit !f }' /usr/lib/opkg/status
	else opkg list-installed 2>/dev/null | grep -q "^$1 "; fi
}
_apk_ver() {
	local v=""
	[ -f /lib/apk/db/installed ] && v="$(awk -v p="$1" '/^P:/ { x = (substr($0, 3) == p) } x && /^V:/ { print substr($0, 3); exit }' /lib/apk/db/installed)"
	[ -n "$v" ] || v="$(apk info -v 2>/dev/null | sed -n "s/^$1-\([0-9][^ ]*\)\$/\1/p" | head -n1)"
	[ -n "$v" ] && printf '%s\n' "$v"
}
_kv_last() {
	local l v=""
	[ -f "$1" ] || return 0
	while IFS= read -r l || [ -n "$l" ]; do case "$l" in "$2="*) v="${l#"$2="}" ;; esac; done < "$1"
	printf '%s' "$v"
}
_opkg_ver() {
	if [ -f /usr/lib/opkg/status ]; then
		awk -v p="$1" 'function out() { if (x && ok && v != "" && !d) { print v; d = 1 } }
			$1 == "Package:" { out(); if (d) exit; x = ($2 == p); v = ""; ok = 0; next }
			x && $1 == "Version:" { v = $2 } x && $1 == "Status:" && / (installed|unpacked)$/ { ok = 1 } END { out() }' /usr/lib/opkg/status
	else opkg list-installed 2>/dev/null | awk -v p="$1" '$1 == p { print $3; exit }'; fi
}

_ensure_deps() {
	local need=""
	_zm_has curl || need="$need curl"
	command -v unzip >/dev/null 2>&1 || need="$need unzip"
	[ -z "$need" ] && return 0
	echo "==> Не хватает программ:$need — устанавливаем"
	$UPDATE
	$INSTALL $need
}

_zm_kids() {
	local f a b c d r
	for f in /proc/[0-9]*/stat; do
		{ read -r a b c d r < "$f"; } 2>/dev/null || continue
		[ "$d" = "$1" ] && echo "$a"
	done
}

_zm_kill_tree() {
	local c
	[ -n "$1" ] || return 0
	kill -STOP "$1" 2>/dev/null
	for c in $(_zm_kids "$1"); do _zm_kill_tree "$c"; done
	kill -9 "$1" 2>/dev/null
}

_zm_pkg_unlock() {
	pidof opkg >/dev/null 2>&1 || rm -f /var/lock/opkg.lock 2>/dev/null
	return 0
}

_zm_dots() {
	local p="$1" tmo="${2:-900}" i=0 o="${ZM_JOB_LOG:-/dev/null}" shown=0
	[ -n "$ZM_IN_WAIT" ] && o=/dev/null
	while kill -0 "$p" 2>/dev/null; do
		sleep 1
		i=$((i + 1))
		if [ "$i" -ge "$tmo" ]; then
			_zm_kill_tree "$p"
			[ "$shown" = 1 ] && echo >> "$o"
			shown=0
			echo "!! Шаг не завершился за $tmo с — прерываем его, чтобы ничего не зависло" >> "${ZM_JOB_LOG:-/dev/null}"
			[ -n "${ZM_TMO_FLAG:-}" ] && : > "$ZM_TMO_FLAG"
			_zm_pkg_unlock
			break
		fi
		if [ "$i" -ge 20 ]; then
			[ "$shown" = 0 ] && { printf 'Подождите ' >> "$o"; shown=1; }
			[ $((i % 5)) = 0 ] && printf '.' >> "$o"
		fi
	done
	[ "$shown" = 1 ] && echo >> "$o"
	return 0
}

_zm_run() {
	local tmo="$1" p rc t="/tmp/zm-run.$$.$RANDOM"
	shift
	( ZM_IN_WAIT=1; export ZM_IN_WAIT; "$@" ) > "$t" 2>&1 &
	p=$!
	_zm_dots "$p" "$tmo"
	wait "$p" 2>/dev/null
	rc=$?
	cat "$t" 2>/dev/null
	rm -f "$t"
	return $rc
}

_zm_pkg_fmt() {
	awk '
		{ sub(/\r$/, "") }
		/^Downloading / { next }
		/^Updated list of available packages in / { n = $0; sub(/.*\//, "", n); print "     · обновлён список: " n; next }
		/^Installing [^ ]+ \(/ { v = $3; gsub(/[()]/, "", v); print "     · ставим " $2 " " v; next }
		/^Upgrading [^ ]+ / { print "     · обновляем " $2; next }
		/^Configuring / { n = $2; sub(/\.$/, "", n); print "     · настраиваем " n; next }
		/^Removing package / { print "     · удаляем " $3; next }
		/^Package .* is up to date/ { print "     · " $2 " уже стоит последней версии"; next }
		/^\([0-9]+\/[0-9]+\) Installing / { v = $4; gsub(/[()]/, "", v); print "     · ставим " $3 " " v; next }
		/^\([0-9]+\/[0-9]+\) Upgrading / { print "     · обновляем " $3; next }
		/^\([0-9]+\/[0-9]+\) (Purging|Deleting) / { print "     · удаляем " $3; next }
		/^OK: [0-9]+ distinct packages available/ { print "     · доступно пакетов: " $2; next }
		/^fetch / { next }
		/ubus call service delete .*Not found/ { next }
		/(write error|[Ww]rite error): [Bb]roken pipe|^[^ ]*: [Bb]roken pipe$/ { next }
		/linuxfw: clear ip6?tables: exec: "ip6?tables": executable file not found/ { next }
		/router: enumerating tailscale0 addresses for cleanup failed/ { next }
		/[Ee]rror|ERROR|Collected errors|^ \* |[Uu]nknown package|not found|No such|unable|cannot|failed|Failed|unsatisfiable|breaks:/ { l = $0; sub(/^[ *]+/, "", l); if (l != "" && !seen[l]++) print "     ! " l; next }
	'
}

_zm_pkg_names() {
	local a out=""
	for a; do
		case "$a" in -*) continue ;; esac
		a="${a##*/}"
		out="$out${out:+, }$a"
	done
	echo "$out"
}

_zm_pkg_update() {
	local try=1 rc t0 bad h
	h="$(_mirror_host)"
	while :; do
		t0="$(date +%s)"
		echo "   → Скачиваем свежий список пакетов из репозитория"
		_zm_run 150 $PKG_UPD > "/tmp/zm-pkg.$$" 2>&1
		rc=$?
		_zm_pkg_fmt < "/tmp/zm-pkg.$$"
		bad=""; [ -n "$h" ] && _mirror_upd_bad "/tmp/zm-pkg.$$" "$h" && bad=1
		rm -f "/tmp/zm-pkg.$$"
		if [ "$rc" = 0 ] && [ -z "$bad" ]; then
			echo "   ✓ Список пакетов обновлён за $(( $(date +%s) - t0 )) с"
			return 0
		fi
		_zm_pkg_unlock
		[ "$try" -ge 2 ] && break
		_zm_dns_ok "$(h="${h:-downloads.openwrt.org}"; echo "${h%%/*}")" || _zm_net_heal
		echo "   ↻ $([ "$rc" = 0 ] && echo "Обновился не полностью" || echo "Не получилось") — пробуем ещё раз"
		try=$((try + 1))
		sleep 3
	done
	if { [ -n "$bad" ] || [ "$rc" != 0 ]; } && [ -n "$h" ]; then
		if [ -n "$bad" ] || ! _mirror_probe "$h" "$(_mirror_feed1)" >/dev/null; then
			_mirror_auto && return 0
		fi
	fi
	if [ "$rc" = 0 ]; then
		echo "   ! Список пакетов обновился не полностью — часть репозиториев не ответила"
		return 0
	fi
	echo "   ✗ Список пакетов не обновился — проверьте интернет и доступ к ${h:-downloads.openwrt.org}"
	return 1
}

_zm_pkg_add() {
	local rc names p miss=""
	names="$(_zm_pkg_names "$@")"
	echo "   → Устанавливаем: $names"
	_zm_run 300 $PKG_ADD "$@" > "/tmp/zm-pkg.$$" 2>&1
	rc=$?
	_zm_pkg_fmt < "/tmp/zm-pkg.$$"
	rm -f "/tmp/zm-pkg.$$"
	_zm_pkg_unlock
	if [ "$rc" = 0 ]; then echo "   ✓ Установлено: $names"
	else
		for p; do case "$p" in -*|*/*|*.ipk|*.apk) continue ;; esac; _pkg_is_installed "$p" || miss="$miss${miss:+, }$p"; done
		echo "   ✗ Не установилось: ${miss:-$names}"
	fi
	return $rc
}

_zm_ca_have() { ls /etc/ssl/certs/*.crt >/dev/null 2>&1; }

_zm_ca_keep() {
	_zm_ca_have && return 0
	echo "   → Возвращаем корневые сертификаты (ca-bundle) — без них не работает HTTPS"
	_zm_run 180 $PKG_ADD ca-bundle >/dev/null 2>&1 || { _zm_run 150 $PKG_UPD >/dev/null 2>&1; _zm_run 180 $PKG_ADD ca-bundle >/dev/null 2>&1; }
	if _zm_ca_have; then echo "   ✓ Сертификаты на месте"
	else echo "   ! Не удалось поставить ca-bundle — установите его вручную, иначе HTTPS-загрузки не заработают"; fi
	return 0
}

job_start() {
	local name="$1"; shift
	local log="$JOBS_DIR/$name.log"
	local pid="$JOBS_DIR/$name.pid"
	if _job_running "$name"; then
		printf '{"started":true,"job":"%s","already_running":true}\n' "$name"
		return 0
	fi
	: > "$log"
	( ZM_JOB_LOG="$log"; export ZM_JOB_LOG; "$@" >>"$log" 2>&1; rc=$?; _zm_net_restore >>"$log" 2>&1; [ -n "$(tail -c 1 "$log" 2>/dev/null)" ] && echo >>"$log"; echo "__DONE__ $rc" >>"$log" ) &
	echo $! > "$pid"
	printf '{"started":true,"job":"%s"}\n' "$name"
}

_zm_cron_drop() {
	local pat="$1" what="$2"
	grep -qiE "$pat" "$CRON_FILE" 2>/dev/null || return 0
	echo "   → Убираем задания $what из расписания (cron)"
	grep -viE "$pat" "$CRON_FILE" > "$CRON_FILE.zm" 2>/dev/null
	if [ $? -le 1 ] && [ -f "$CRON_FILE.zm" ]; then cat "$CRON_FILE.zm" > "$CRON_FILE"; fi
	rm -f "$CRON_FILE.zm"
	/etc/init.d/cron restart >/dev/null 2>&1
	echo "   ✓ Расписание очищено"
}

_zm_svc_off() {
	[ -x "/etc/init.d/$1" ] || return 0
	echo "   → Останавливаем службу $1 и убираем её из автозапуска"
	_zm_run 60 "/etc/init.d/$1" stop >/dev/null 2>&1
	"/etc/init.d/$1" disable >/dev/null 2>&1
	return 0
}

ZM_RESOLV_BAK="$JOBS_DIR/resolv.conf.zm-bak"

_zm_dns_ok() { nslookup "$1" >/dev/null 2>&1; }

ZM_REBOOT_HINT="$JOBS_DIR/reboot.hint"

_zm_reboot_hint_get() {
	local ts now
	[ -s "$ZM_REBOOT_HINT" ] || return 0
	ts="$(sed -n 2p "$ZM_REBOOT_HINT" 2>/dev/null)"
	now="$(date +%s)"
	case "$ts" in
		''|*[!0-9]*) rm -f "$ZM_REBOOT_HINT"; return 0 ;;
		*) [ $((now - ts)) -gt 120 ] && { rm -f "$ZM_REBOOT_HINT"; return 0; } ;;
	esac
	head -n1 "$ZM_REBOOT_HINT"
}

_zm_rb_note() {
	[ -n "$ZM_RB_NOTE" ] && echo "$ZM_RB_NOTE"
	ZM_RB_NOTE=""
	return 0
}

reboot_hint_clear() {
	rm -f "$ZM_REBOOT_HINT"
	printf '{"ok":true}\n'
}

system_reboot() {
	local j
	j="$(_zm_busy_job)" && { printf '{"error":"%s"}\n' "$(esc "Сейчас идёт операция: $j — дождитесь её окончания")"; return 1; }
	rm -f "$ZM_REBOOT_HINT"
	( sleep 2; sync; reboot ) >/dev/null 2>&1 </dev/null &
	printf '{"ok":true}\n'
}

_zm_net_own() {
	[ -n "$ZM_JOB_LOG" ] || return 0
	grep -qxF "$ZM_JOB_LOG" "$ZM_RESOLV_BAK.owners" 2>/dev/null || echo "$ZM_JOB_LOG" >> "$ZM_RESOLV_BAK.owners"
}

_zm_net_others() {
	local o
	[ -f "$ZM_RESOLV_BAK.owners" ] || return 1
	while read -r o; do
		[ -n "$o" ] && [ "$o" != "$ZM_JOB_LOG" ] || continue
		_job_running "$(basename "$o" .log)" && return 0
	done < "$ZM_RESOLV_BAK.owners"
	return 1
}

_zm_net_orphan() {
	[ -f "$ZM_RESOLV_BAK" ] || return 1
	if [ -s "$ZM_RESOLV_BAK.owners" ]; then
		_zm_net_others && return 1
		return 0
	fi
	[ -z "$(_zm_busy_job)" ]
}

_zm_net_heal() {
	if [ -f "$ZM_RESOLV_BAK" ]; then _zm_net_own; return 0; fi
	local src=/tmp/resolv.conf
	[ -s "$src" ] || src=/etc/resolv.conf
	[ -s "$src" ] || return 1
	cat "$src" > "$ZM_RESOLV_BAK.new" 2>/dev/null && [ -s "$ZM_RESOLV_BAK.new" ] || { rm -f "$ZM_RESOLV_BAK.new"; return 1; }
	mv -f "$ZM_RESOLV_BAK.new" "$ZM_RESOLV_BAK"
	rm -f "$ZM_RESOLV_BAK.owners"
	_zm_net_own
	printf 'nameserver 1.1.1.1\nnameserver 9.9.9.9\n' > /tmp/resolv.conf 2>/dev/null || printf 'nameserver 1.1.1.1\nnameserver 9.9.9.9\n' > /etc/resolv.conf
	echo "   → DNS роутера не отвечает — на время операции берём 1.1.1.1 и 9.9.9.9"
}

_zm_net_restore() {
	[ -f "$ZM_RESOLV_BAK" ] || return 0
	if [ "$1" != force ] && [ -n "$ZM_JOB_LOG" ]; then
		local lk="$ZM_RESOLV_BAK.lock" i=0
		while ! mkdir "$lk" 2>/dev/null; do
			i=$((i + 1)); [ "$i" -ge 10 ] && { rmdir "$lk" 2>/dev/null; continue; }
			sleep 1
		done
		if [ -s "$ZM_RESOLV_BAK.owners" ] && ! grep -qxF "$ZM_JOB_LOG" "$ZM_RESOLV_BAK.owners"; then rmdir "$lk"; return 0; fi
		grep -vxF "$ZM_JOB_LOG" "$ZM_RESOLV_BAK.owners" > "$ZM_RESOLV_BAK.o2.$$" 2>/dev/null
		mv -f "$ZM_RESOLV_BAK.o2.$$" "$ZM_RESOLV_BAK.owners"
		if _zm_net_others; then rmdir "$lk"; return 0; fi
		rmdir "$lk"
	fi
	mv -f "$ZM_RESOLV_BAK" "$ZM_RESOLV_BAK.r" 2>/dev/null || return 0
	if [ -s "$ZM_RESOLV_BAK.r" ]; then
		if [ -e /tmp/resolv.conf ]; then cat "$ZM_RESOLV_BAK.r" > /tmp/resolv.conf; else cat "$ZM_RESOLV_BAK.r" > /etc/resolv.conf; fi
	fi
	rm -f "$ZM_RESOLV_BAK.r" "$ZM_RESOLV_BAK.owners"
	echo "   ✓ Обычный DNS роутера возвращён"
}

zm_watch() {
rpcd_watch
    _test_recover >/dev/null 2>&1
    _zm_net_orphan && _zm_net_restore force >/dev/null 2>&1
    _ft_zapret_sync
    _zo_doh_follow
    return 0
}

_zm_job_skip() { case "$1" in versions|*_download) return 0 ;; esac; return 1; }

_zm_cancel_one() {
	local j="$1" pid log="$JOBS_DIR/$1.log"
	pid="$(cat "$JOBS_DIR/$j.pid" 2>/dev/null)"
	[ -n "$pid" ] && _zm_kill_tree "$pid"
	grep -q '^__DONE__' "$log" 2>/dev/null && return 0
	[ -n "$(tail -c 1 "$log" 2>/dev/null)" ] && echo >> "$log"
	echo "!! Операция остановлена вручную — все её процессы завершены" >> "$log"
	echo "__DONE__ 130" >> "$log"
	case "$j" in
        strategy_test) rm -f "$ZA_RUN" ;;
        install_zapret) _nochange_restore zapret >> "$log" 2>&1 ;;
        install_zapret2) _nochange_restore zapret2 >> "$log" 2>&1 ;;
    esac
}

jobs_cancel() {
	local f j list="" sep=""
	for f in "$JOBS_DIR"/*.pid; do
		[ -f "$f" ] || continue
		j="$(basename "$f" .pid)"
		_zm_job_skip "$j" && continue
		[ -n "$1" ] && [ "$1" != "$j" ] && continue
		_job_running "$j" || continue
		_zm_cancel_one "$j"
		list="$list$sep\"$j\""; sep=","
	done
	local busy=""
	for f in "$JOBS_DIR"/*.pid; do
		[ -f "$f" ] || continue
		_job_running "$(basename "$f" .pid)" && { busy=1; break; }
	done
	if [ -z "$busy" ]; then
		for f in /tmp/zm-run.* /tmp/zm-wait.* /tmp/zm-quiet.* /tmp/zm-pkg.*; do
			[ -e "$f" ] || continue
			_zm_tmp_live "$f" && continue
			rm -f "$f" 2>/dev/null
		done
	fi
	_zm_net_orphan && _zm_net_restore force >/dev/null 2>&1
	_zm_pkg_unlock
	printf '{"ok":true,"stopped":[%s]}\n' "$list"
}

_zm_rpcd_kick() {
	local i=0
	/etc/init.d/rpcd reload >/dev/null 2>&1
	while [ "$i" -lt 8 ]; do
		sleep 1; i=$((i + 1))
		if [ -n "$1" ]; then eval "$1" >/dev/null 2>&1 && return 0
		else ubus -t 3 list zapret-manager >/dev/null 2>&1 && return 0; fi
	done
	/etc/init.d/rpcd restart >/dev/null 2>&1
	return 1
}

rpcd_watch() {
	local rc mark="/tmp/zm-rpcd-slow"
	if ! pidof rpcd >/dev/null 2>&1; then
		logger -t zapret-manager "rpcd не запущен — запускаем, чтобы вернуть вход в LuCI"
		/etc/init.d/rpcd restart >/dev/null 2>&1
		return 0
	fi
	if ! ubus -t 5 list session >/dev/null 2>&1; then
		if [ -n "$(find "$mark" -mmin -5 2>/dev/null)" ]; then
			logger -t zapret-manager "rpcd не отвечает второй раз подряд — перезапускаем"
			rm -f "$mark"
			_zm_rpcd_kick 'ubus -t 3 list session'
		else touch "$mark"; fi
		return 0
	fi
	ubus -t 15 call session access '{"ubus_rpc_session":"00000000000000000000000000000000","scope":"ubus","object":"session","function":"access"}' >/dev/null 2>&1
	rc=$?
	if [ "$rc" = 7 ]; then
		if [ -n "$(find "$mark" -mmin -5 2>/dev/null)" ]; then
			logger -t zapret-manager "rpcd завис второй раз подряд — перезапускаем, чтобы вернуть вход в LuCI"
			rm -f "$mark"
			_zm_rpcd_kick 'ubus -t 5 call session access "{\"ubus_rpc_session\":\"00000000000000000000000000000000\",\"scope\":\"ubus\",\"object\":\"session\",\"function\":\"access\"}"'
		else touch "$mark"; fi
		return 0
	fi
	rm -f "$mark"
	_rpcd_plugin_watch
	return 0
}

_rpcd_plugin_watch() {
	local pl=/usr/libexec/rpcd/zapret-manager sig st stamp=/tmp/zm-rpcd-plugin.stamp
	[ -x "$pl" ] || return 0
	_rpcd_plugin_state "$pl" && { rm -f "$stamp"; return 0; }
	sleep 5
	_rpcd_plugin_state "$pl"
	st=$?
	[ "$st" = 0 ] && { rm -f "$stamp"; return 0; }
	sig="$(date -r "$pl" +%s 2>/dev/null)"
	if [ "$st" = 1 ]; then
		case "$(cat "$stamp" 2>/dev/null)" in
			"$sig.x3") return 0 ;;
			"$sig.x2") echo "$sig.x3" > "$stamp" ;;
			"$sig.x1") echo "$sig.x2" > "$stamp" ;;
			*) echo "$sig.x1" > "$stamp" ;;
		esac
		logger -t zapret-manager "rpcd не видит панель (Object not found) — перезапускаем rpcd"
	else
		[ "$(cat "$stamp" 2>/dev/null)" = "$sig.m" ] && return 0
		echo "$sig.m" > "$stamp"
		logger -t zapret-manager "rpcd держит старый список методов панели — перечитываем плагины rpcd"
	fi
	_zm_rpcd_kick '_rpcd_plugin_state /usr/libexec/rpcd/zapret-manager'
	return 0
}

_rpcd_plugin_state() {
	local want have
	ubus -t 5 list zapret-manager >/dev/null 2>&1 || return 1
	want="$(grep -c 'json_add_object' "$1" 2>/dev/null)"
	have="$(ubus -v list zapret-manager 2>/dev/null | grep -c '^[[:space:]]*"')"
	[ "${want:-0}" -gt 0 ] 2>/dev/null || return 0
	[ "${have:-0}" -gt 0 ] 2>/dev/null || return 0
	[ "$have" = "$want" ] && return 0
	return 2
}

ui_theme_set() {
	case "$1" in micro|light|dark|ink|bento|minimal|retro|depth|graphite|oled|matrix|auto) ;; *) echo '{"error":"неизвестная тема"}'; return 1 ;; esac
	mkdir -p "$ZM_STATE_DIR" /www/zm
	printf '%s\n' "$1" > "$ZM_STATE_DIR/ui.theme"
	printf '%s\n' "$1" > /www/zm/theme.txt
	chmod 0644 /www/zm/theme.txt 2>/dev/null
	printf '{"ok":true}\n'
}

UI_NAV_FILE="$ZM_STATE_DIR/ui.nav.hidden"
ui_nav_get() { [ -s "$UI_NAV_FILE" ] || return 0; tr '\n' ' ' < "$UI_NAV_FILE" | sed 's/  */ /g; s/^ //; s/ $//'; }
ui_nav_set() {
	local id out="" n=0
	for id in $(printf '%s' "$1" | tr ',' ' '); do
		printf '%s' "$id" | grep -qE '^[a-z0-9_]{1,32}$' || { echo '{"error":"неверный раздел"}'; return 1; }
		[ "$id" = dashboard ] && continue
		case " $out " in *" $id "*) continue ;; esac
		out="$out $id"; n=$((n + 1))
		[ "$n" -le 64 ] || { echo '{"error":"слишком много разделов"}'; return 1; }
	done
	mkdir -p "$ZM_STATE_DIR"
	if [ -n "$out" ]; then printf '%s\n' $out > "$UI_NAV_FILE"; else rm -f "$UI_NAV_FILE"; fi
	printf '{"ok":true,"hidden":"%s"}\n' "$(ui_nav_get)"
}

ui_flags_get() {
	local f="$ZM_STATE_DIR/ui.flags" out="" sep="" k
	if [ -s "$f" ]; then
		for k in $(grep -E '^[a-z0-9_]{1,48}$' "$f" | sort -u); do out="$out$sep\"$k\":1"; sep=","; done
	fi
	printf '{"flags":{%s}}\n' "$out"
}

ui_flag_set() {
	local f="$ZM_STATE_DIR/ui.flags"
	printf '%s' "$1" | grep -qE '^[a-z0-9_]{1,48}$' || { echo '{"error":"неверное имя"}'; return 1; }
	mkdir -p "$ZM_STATE_DIR"
	grep -qx "$1" "$f" 2>/dev/null || echo "$1" >> "$f"
	printf '{"ok":true}\n'
}

zapret_restart() {
	[ -n "$ZM_NO_RESTART" ] && return 0
	[ -s "$ZC_FILE" ] && _zc_drop
	_yv_ipid_sync
	_zo_doh_sync
	if [ -n "$(_fake_missing)" ]; then
		if [ -n "$ZM_JOB_LOG" ]; then _fake_ensure; else _zm_run 25 _fake_ensure >/dev/null 2>&1; fi
	fi
	chmod -R a+rX /opt/zapret/ipset /opt/zapret/files 2>/dev/null
	[ -x /opt/zapret/sync_config.sh ] && /opt/zapret/sync_config.sh >/dev/null 2>&1
	/etc/init.d/zapret restart >/dev/null 2>&1
}

_strat_label() {
	local s
	s=$(_nfq_names | sed 's/^#[[:space:]]*//; s/[[:space:]]*$//; /^udp443$/d; /^DoH$/d; /^[Nn][Oo][Cc][Hh][Aa][Nn][Gg][Ee]$/d' | tr '\n' ' ' | sed 's/ $//')
	_yv_ipid_on && s="$(printf '%s' "$s" | sed -E 's/(^| )(Yv[0-9]+)( |$)/\1\2z\3/')"
	_udp443_on && s="${s:+$s }QUIC"
	_zo_doh_on && s="${s:+$s }DoH"
	{ _zc_has || [ -s "$ZC_FILE" ]; } && s="${s:+$s }Custom"
	[ -z "$s" ] && _nfq_opt_body | grep -q -- '^[[:space:]]*--' && s="своя"
	_zo_wss_on && s="${s:+$s }wssize"
	printf '%s' "$s"
}

status() {
	local zr="not_installed" zr_running="false" zr_ver=""
	_test_recover
	if [ -f /etc/init.d/zapret ]; then
		zr="installed"
		zr_ver="$ZAPRET_VER"
		pgrep -f "/opt/zapre[t]/" >/dev/null 2>&1 && zr_running="true"
	fi

	local zr2="not_installed" zr2_running="false" zr2_luci=""
	if [ -f /etc/init.d/zapret2 ]; then
		zr2="installed"
		/etc/init.d/zapret2 status >/dev/null 2>&1 && zr2_running="true"
		zr2_luci="$(_z2_luci_path)"
	fi

	local strat="" fs_marker="" testing=false test_now="" ZM_NFQ_BODY="" zdd="" zdo=false ZM_YS="" ZM_UDP="" ZM_DOH="" ZM_RKN="" ZM_FITS=""
	if [ "$zr" = installed ]; then
		zdd="$(_zo_doh_hosts)"
		[ -n "$zdd" ] && zdo=true
		zdd="${zdd:-$ZO_DOH_DEF}"
	fi
	if [ -f "$CONF" ]; then
		ZM_NFQ_BODY="$(_nfq_opt_body)"
		ZM_YS="$(_yv_ipid_scan)"
		if _udp443_on; then ZM_UDP=1; else ZM_UDP=0; fi
		if _zo_doh_on; then ZM_DOH=1; else ZM_DOH=0; fi
		if _zo_rkn_on; then ZM_RKN=1; else ZM_RKN=0; fi
		if _zo_rkn_fits; then ZM_FITS=1; else ZM_FITS=0; fi
		strat=$(_strat_label)
		fs_marker=$(sed -n '/^# ZMFS:/{s/^# ZMFS://p;q}' "$CONF")
		if [ -s "$TEST_BACKUP" ] && _test_running; then
			testing=true; test_now="$strat"
			strat=$(CONF="$TEST_BACKUP"; ZM_NFQ_BODY=""; ZM_YS=""; ZM_UDP=""; ZM_DOH=""; ZM_RKN=""; ZM_FITS=""; _strat_label)
			fs_marker=$(sed -n '/^# ZMFS:/{s/^# ZMFS://p;q}' "$TEST_BACKUP")
			[ "$test_now" = "$strat" ] && test_now=""
		fi
	fi

	printf '{"pkg":"%s","zapret":"%s","zapret_running":%s,"zapret_version":"%s","zapret2":"%s","zapret2_running":%s,"strategy":"%s","flowseal":"%s","yv_off":%s,"quic_yt":%s,"expert":%s,"rkn":%s,"rkn_on":%s,"rkn_fits":%s,"rkn_count":%s,"wssize":%s,"ulist":%s,"ulist_on":%s,"ulist_count":%s,"testing":%s,"test_now":"%s","ipid":%s,"ipid_want":"%s","yt_tcp":%s,"z2_luci":"%s","zdoh":%s,"zdoh_on":%s,"zdoh_doms":"%s","zdoh_own":%s}\n' \
		"$PKG" "$zr" "$zr_running" "$(esc "$zr_ver")" "$zr2" "$zr2_running" "$(esc "$strat")" "$(esc "$fs_marker")" \
		"$([ -f /opt/zapret-manager-luci/yv_off ] && echo true || echo false)" \
		"$([ -f "$CONF" ] && _udp443_on && echo true || echo false)" \
		"$([ -f "$EXPERT_MODE_FILE" ] && echo true || echo false)" \
		"$([ -f "$ZO_RKN_FLAG" ] && echo true || echo false)" \
		"$([ -f "$CONF" ] && _zo_rkn_on && echo true || echo false)" \
		"$([ -f "$CONF" ] && { _zo_rkn_fits || _zo_rkn_on; } && echo true || echo false)" \
		"$(awk 'NF { n++ } END { print n + 0 }' "$ZO_RKN_FILE" 2>/dev/null | grep . || echo 0)" \
		"$([ -f "$CONF" ] && _zo_wss_on && echo true || echo false)" \
		"$([ -f "$ZO_USER_FLAG" ] && echo true || echo false)" \
		"$([ -f "$CONF" ] && _zo_user_on && echo true || echo false)" \
		"$(_zo_user_count)" "$testing" "$(esc "$test_now")" \
		"$([ -f "$CONF" ] && _yv_ipid_on && echo true || echo false)" "$(_yv_ipid_want)" \
		"$([ -f "$CONF" ] && [ "${ZM_YS%% *}" -gt 0 ] 2>/dev/null && echo true || echo false)" "$(esc "$zr2_luci")" \
		"$([ -f "$ZO_DOH_FLAG" ] && echo true || echo false)" "$([ -f "$CONF" ] && _zo_doh_on && echo true || echo false)" \
		"$(esc "$zdd")" "$zdo"
}
_z2_luci_path() {
	grep -ho '"admin/[A-Za-z0-9_/-]*zapret2[A-Za-z0-9_/-]*"' /usr/share/luci/menu.d/*.json 2>/dev/null | tr -d '"' | grep -v 'zapret-manager' |
		awk '{ print length($0) "\t" $0 }' | sort -n | head -n 1 | cut -f 2
}

_do_install_zapret_core() {
	_ensure_deps
	if [ -f /etc/init.d/zapret2 ] && [ ! -f "$EXPERT_MODE_FILE" ]; then
		echo "ОШИБКА: установлен Zapret2, он несовместим с Zapret — сначала удалите Zapret2"
		return 1
	fi
	local ver="$ZAPRET_VER" arch url tmp
	echo "==> Ставим Zapret $ver"
	arch="$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)"
	url="${GH_MAIN}/remittor/zapret-openwrt/releases/download/v${ver}/zapret_v${ver}_${arch}.zip"
	tmp="$JOBS_DIR/install_tmp"; rm -rf "$tmp"; mkdir -p "$tmp"; cd "$tmp" || return 1

	echo "==> Обновляем список пакетов"
	$UPDATE

	if [ -f /etc/init.d/zapret ]; then
		echo "==> Останавливаем текущий Zapret"
		/etc/init.d/zapret stop >/dev/null 2>&1
		for p in $(pgrep -f "/opt/zapre[t]/" 2>/dev/null); do kill -9 "$p" 2>/dev/null; done
	fi

	echo "==> Скачиваем $url"
	local attempt=1 max_attempts=5
	while [ "$attempt" -le "$max_attempts" ]; do
		rm -f zapret.zip
		if ! _zm_fetch "$url" zapret.zip 300; then
			echo "!! Попытка $attempt из $max_attempts: архив не скачался — $ZM_FETCH_ERR"
			case "$ZM_FETCH_ERR" in *"(HTTP 404)"*|*"(HTTP 410)"*) attempt=$max_attempts ;; esac
		fi
		command -v unzip >/dev/null 2>&1 || { echo "==> Устанавливаем unzip"; $INSTALL unzip >&2; }
		if [ -s zapret.zip ] && unzip -tq zapret.zip >/dev/null 2>&1; then
			echo "   ✓ Архив скачан и проверен: $(_zm_size_txt "$(wc -c < zapret.zip | tr -d ' ')")"
			break
		fi
		if [ -s zapret.zip ]; then
			if command -v unzip >/dev/null 2>&1; then echo "!! Попытка $attempt из $max_attempts: архив скачался не целиком ($(wc -c < zapret.zip) байт)"
			else echo "!! Попытка $attempt из $max_attempts: архив скачан, но unzip не установился — проверьте список пакетов"; fi
		fi
		attempt=$((attempt + 1))
	done
	if [ "$attempt" -gt "$max_attempts" ]; then
		echo "ОШИБКА: не удалось скачать целый архив за $max_attempts попыток — проверьте соединение с GitHub"
		return 1
	fi
	unzip -o zapret.zip >/dev/null 2>&1

	echo "==> Устанавливаем пакеты"
	if [ "$PKG" = "apk" ]; then
		for p in apk/zapret*; do
			[ -f "$p" ] || continue
			echo "$p" | grep -q luci && continue
			echo "  - $(basename "$p")"; $INSTALL "$p" >&2 || { echo "ОШИБКА: $p"; return 1; }
		done
		for p in apk/luci*; do
			[ -f "$p" ] || continue
			echo "  - $(basename "$p")"; $INSTALL "$p" >&2
		done
	else
		for p in zapret_*.ipk; do
			[ -f "$p" ] || continue
			echo "  - $(basename "$p")"; $INSTALL "$p" >&2 || { echo "ОШИБКА: $p"; return 1; }
		done
		for p in luci-app-zapret_*.ipk; do
			[ -f "$p" ] || continue
			echo "  - $(basename "$p")"; $INSTALL "$p" >&2
		done
	fi

	_nochange_restore zapret
	echo "==> Добавляем домены в исключения"
	_nochange_fetch /opt/zapret/ipset/zapret-hosts-user-exclude.txt "$EXCLUDE_URL" || echo "!! Список исключений не скачался — оставлен прежний"

	do_add_fake_flow

	echo "==> Включаем автозапуск и custom.d-скрипты"
	/etc/init.d/zapret enable >/dev/null 2>&1
	sed -i "/DISABLE_CUSTOM/s/'1'/'0'/" "$CONF" 2>/dev/null

	cd /; rm -rf "$tmp"
	echo "==> Готово, Zapret установлен ($ver)"
}

do_install_zapret() {
	local rc
	_nochange_save zapret /opt/zapret/ipset "$CONF"
	_do_install_zapret_core; rc=$?
	_nochange_restore zapret
	_ft_zapret_sync
	return $rc
}

do_install_zapret2() {
	local rc
	_nochange_save zapret2 /opt/zapret2/ipset /etc/config/zapret2
	_do_install_zapret2_core; rc=$?
	_nochange_restore zapret2
	_ft_zapret_sync
	return $rc
}

do_install_zapret_full() {
	do_install_zapret || return 1
	[ -f /etc/init.d/zapret ] || return 1

	if _nochange_strategy; then echo "==> Стратегия помечена #nochange — оставляем её как есть"
	else
		_zc_lift
		echo "==> Применяем базовую стратегию v7"
		strategy_set_v v7 >/dev/null
	fi

	if ! _nochange_strategy; then
		echo "==> Настраиваем игровую стратегию Gv1"
		game_set 1 >/dev/null
	fi
	_zc_drop

	echo "==> Готово, Zapret установлен и настроен"
}

do_remove_zapret() {
	local rc=0
	echo "==> Останавливаем Zapret"
	_zm_svc_off zapret
	for p in $(pgrep -f "/opt/zapre[t]/" 2>/dev/null); do kill -9 "$p" 2>/dev/null; done
	nft delete table inet zapret >/dev/null 2>&1
	echo "   ✓ Процессы nfqws остановлены, правила файрвола сняты"
	echo "==> Удаляем пакеты Zapret"
	_zm_pkg_wipe luci-i18n-zapret-ru luci-app-zapret zapret || rc=1
	echo "==> Удаляем файлы, стратегии и списки"
	_zm_wipe /opt/zapret "$CONF" "$CONF-opkg" "$CONF.apk-new" /etc/init.d/zapret /etc/rc.d/*[0-9]zapret /etc/firewall.zapret /etc/hotplug.d/*/*zapret \
		/tmp/zapret /tmp/zapret.* "$YV_OFF_FLAG" "$DV_OFF_FLAG" "$JOBS_DIR/flowseal_strategies.txt" "$JOBS_DIR/youtube_strategies.txt" "$ZO_RKN_FLAG" "$ZO_USER_FLAG" "$ZO_IPID_FLAG" "$ZO_DOH_FLAG" &&
		echo "   ✓ Файлы удалены, остатков нет" || rc=1
	crontab -l 2>/dev/null | awk '{ l = tolower($0) } l ~ /zapret/ && l !~ /zapret-manager|zapret2/ { next } { print }' | crontab - 2>/dev/null
	sed -i "\\|$ZA_TAG|d; \\|$ZX_AUTO_TAG=|d" "$CRON_FILE" 2>/dev/null
	_ft_zapret_gone
	echo "   ✓ Задания Zapret убраны из расписания"
	_zm_rm_listed zapret || rc=1
	/etc/init.d/firewall reload >/dev/null 2>&1
	_zm_rm_done "$rc" "Zapret"
}
zapret_action() {
	local action="$1"
	case "$action" in
		install)
			if [ ! -f /etc/init.d/zapret ] && [ -f /etc/init.d/zapret2 ] && [ ! -f "$EXPERT_MODE_FILE" ]; then
				echo '{"error":"Стоит Zapret2 — он несовместим с Zapret. Чтобы поставить Zapret, удалите Zapret2."}'; return 1
			fi
			job_start install_zapret do_install_zapret_full ;;
		update)         job_start install_zapret do_install_zapret ;;
		remove)         job_start remove_zapret  do_remove_zapret ;;
		start)          /etc/init.d/zapret start >/dev/null 2>&1; zapret_restart; status ;;
		restart)
			[ -x /etc/init.d/zapret ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
			zapret_restart
			for p in 1 2 3 4 5; do pgrep -f "/opt/zapre[t]/" >/dev/null 2>&1 && break; sleep 1; done
			status ;;
		stop)
			/etc/init.d/zapret stop >/dev/null 2>&1
			for p in $(pgrep -f "/opt/zapre[t]/" 2>/dev/null); do kill -9 "$p" 2>/dev/null; done
			status ;;
		*) echo '{"error":"неизвестное действие"}' ;;
	esac
}

_z2_arch() { awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release 2>/dev/null; }
_do_install_zapret2_core() {
	local arch
	arch="$(_z2_arch)"
	if [ "$arch" != "aarch64_cortex-a53" ]; then
		echo "ОШИБКА: Zapret2 поддерживает только архитектуру aarch64_cortex-a53 (у вас: $arch)"
		return 1
	fi
	if [ -f /etc/init.d/zapret ] && [ ! -f "$EXPERT_MODE_FILE" ]; then
		echo "ОШИБКА: установлен основной Zapret, он несовместим с Zapret2 — сначала удалите Zapret"
		return 1
	fi
	_ensure_deps

	local base_url raz
	if [ "$PKG" = "apk" ]; then
		base_url="https://packages.routerich.ru/25.12/mediatek/filogic/routerich/"; raz="apk"
	else
		base_url="https://packages.routerich.ru/24.10/mediatek/filogic/routerich/"; raz="ipk"
	fi

	local tmp="$JOBS_DIR/install_z2_tmp"; rm -rf "$tmp"; mkdir -p "$tmp"; cd "$tmp" || return 1

	echo "==> Ищем актуальный пакет Zapret2 в $base_url"
	ZM_FETCH_ANY=1
	_zm_fetch "$base_url" index.html 15 || { ZM_FETCH_ANY=""; echo "ОШИБКА: не удалось получить список пакетов — $ZM_FETCH_ERR"; return 1; }
	ZM_FETCH_ANY=""

	local main_file luci_file
	if [ "$PKG" = "apk" ]; then
		main_file=$(grep -oE 'zapret2-[0-9][^"]*\.apk' index.html | head -n1)
		luci_file=$(grep -oE 'luci-app-zapret2-[0-9][^"]*\.apk' index.html | head -n1)
	else
		main_file=$(grep -oE 'zapret2_[0-9][^"]*_aarch64_cortex-a53\.ipk' index.html | head -n1)
		luci_file=$(grep -oE 'luci-app-zapret2_[0-9][^"]*_all\.ipk' index.html | head -n1)
	fi
	[ -z "$main_file" ] && { echo "ОШИБКА: пакет zapret2 не найден в репозитории"; return 1; }

	echo "==> Скачиваем $main_file"
	_zm_get "${base_url}${main_file}" "$main_file" "" 60 || { echo "ОШИБКА скачивания $main_file"; return 1; }
	if [ -n "$luci_file" ]; then
		echo "==> Скачиваем $luci_file"
		_zm_get "${base_url}${luci_file}" "$luci_file" "" 60
	fi

	echo "==> Обновляем список пакетов"
	$UPDATE

	echo "==> Устанавливаем"
	$INSTALL ./*."$raz" || { echo "ОШИБКА установки"; return 1; }
	_nochange_restore zapret2

	echo "==> Добавляем домены в исключения"
	mkdir -p /opt/zapret2/ipset
	_nochange_fetch /opt/zapret2/ipset/zapret_hosts_user_exclude.txt "$EXCLUDE_URL"

	echo "==> Настраиваем стратегии"
	mkdir -p /opt/zapret2/init.d/openwrt/custom.d
	_nochange_fetch /opt/zapret2/init.d/openwrt/custom.d/50-discord_media.sh \
		"${GH_RAW}/Screamshow/Zapret-Manager/refs/heads/main/files/Zapret2/50-discord_media.sh" \
		|| echo "!! Не удалось загрузить 50-discord_media.sh"
	if _nochange_in /etc/config/zapret2; then echo "   · Стратегия Zapret2 помечена #nochange — оставляем как есть"
	else
		_nochange_fetch /etc/config/zapret2 "${GH_RAW}/Screamshow/Zapret-Manager/refs/heads/main/files/Zapret2/zapret2" || echo "!! Не удалось загрузить zapret2"
	fi
	_nochange_fetch /opt/zapret2/ipset/zapret_hosts_discord.txt "${GH_RAW}/Screamshow/Zapret-Manager/refs/heads/main/files/Zapret2/zapret_hosts_discord.txt" \
		|| echo "!! Не удалось загрузить zapret_hosts_discord.txt"

	echo "==> Запускаем Zapret2"
	/etc/init.d/zapret2 enable >/dev/null 2>&1
	/etc/init.d/zapret2 restart >/dev/null 2>&1

	cd /; rm -rf "$tmp"
	echo "==> Готово, Zapret2 установлен"
}

do_remove_zapret2() {
	local rc=0
	echo "==> Останавливаем Zapret2"
	_zm_svc_off zapret2
	for p in $(pgrep -f "/opt/zapret[2]/" 2>/dev/null); do kill -9 "$p" 2>/dev/null; done
	nft delete table inet zapret2 >/dev/null 2>&1
	echo "   ✓ Процессы остановлены, правила файрвола сняты"
	echo "==> Удаляем пакеты Zapret2"
	_zm_pkg_wipe luci-i18n-zapret2-ru luci-app-zapret2 zapret2 || rc=1
	echo "==> Удаляем файлы и настройки"
	_zm_wipe /etc/config/zapret2 /etc/config/zapret2-opkg /etc/config/zapret2.apk-new /opt/zapret2 /etc/init.d/zapret2 /etc/rc.d/*zapret2 /etc/hotplug.d/*/*zapret2 /tmp/zapret2* &&
		echo "   ✓ Файлы удалены, остатков нет" || rc=1
	_zm_cron_drop 'zapret2' 'Zapret2'
	_zm_rm_listed zapret2 || rc=1
	/etc/init.d/firewall reload >/dev/null 2>&1
	_ft_zapret_gone
	_zm_rm_done "$rc" "Zapret2"
}
zapret2_action() {
	local action="$1"
	case "$action" in
		install|update)
			if [ ! -f /etc/init.d/zapret2 ] && [ -f /etc/init.d/zapret ] && [ ! -f "$EXPERT_MODE_FILE" ]; then
				echo '{"error":"Стоит Zapret — он несовместим с Zapret2. Чтобы поставить Zapret2, удалите Zapret."}'; return 1
			fi
			if [ "$action" = install ] && [ "$(_z2_arch)" != "aarch64_cortex-a53" ]; then
				printf '{"error":"%s"}\n' "$(esc "Zapret2 работает только на роутерах с архитектурой aarch64_cortex-a53, у этого роутера — $(_z2_arch)")"; return 1
			fi
			job_start install_zapret2 do_install_zapret2 ;;
		remove)         job_start remove_zapret2  do_remove_zapret2 ;;
		start)          /etc/init.d/zapret2 start >/dev/null 2>&1; status ;;
		stop)           /etc/init.d/zapret2 stop >/dev/null 2>&1; status ;;
		restart)
			[ -x /etc/init.d/zapret2 ] || { echo '{"error":"Zapret2 не установлен"}'; return 1; }
			/etc/init.d/zapret2 restart >/dev/null 2>&1
			for p in 1 2 3 4 5; do /etc/init.d/zapret2 status >/dev/null 2>&1 && break; sleep 1; done
			status ;;
		*) echo '{"error":"неизвестное действие"}' ;;
	esac
}

NOCHANGE_RX='#[[:space:]]*nochange'
NOCHANGE_MSG="включено «Не изменять стратегию» (#nochange) — панель её не меняет. Выключите этот переключатель в «Редактировать текущую стратегию», чтобы разрешить изменения"

_nochange_in() { [ -f "$1" ] && grep -qiE "$NOCHANGE_RX" "$1"; }
_nochange_strategy() { _nfq_opt_body | grep -qiE "$NOCHANGE_RX"; }
_nochange_guard() {
	_nochange_strategy || return 0
	printf '{"error":"%s","nochange":true}\n' "$(esc "$NOCHANGE_MSG")"
	return 1
}

_zm_dl_sane() { [ -s "$1" ] && ! head -c 1024 "$1" | grep -qiE '<(!doctype|html|head|body)'; }

_nochange_fetch() {
	local f="$1" url="$2" tmp="$1.zm-new"
	if _nochange_in "$f"; then
		[ -n "$ZM_JOB_LOG" ] && echo "   · $(basename "$f"): помечен #nochange — не обновляем" >&2
		return 0
	fi
	mkdir -p "$(dirname "$f")"
	if _zm_fetch "$url" "$tmp" 60 && _zm_dl_sane "$tmp"; then mv -f "$tmp" "$f"
	else rm -f "$tmp"; return 1; fi
}

_nochange_save() {
	local key="$1" keep="$ZM_STATE_DIR/nochange.$1" p f
	shift
	[ -d "$keep" ] && _nochange_restore "$key" >/dev/null 2>&1
	for p in "$@"; do
		if [ -d "$p" ]; then set -- "$p"/*; else set -- "$p"; fi
		for f in "$@"; do
			[ -f "$f" ] && _nochange_in "$f" || continue
			mkdir -p "$keep"
			cp -p "$f" "$keep/$(echo "$f" | sed 's#/#%#g')" || continue
			echo "   · $(basename "$f"): помечен #nochange — сохраним как есть"
		done
	done
	return 0
}

_nochange_restore() {
	local keep="$ZM_STATE_DIR/nochange.$1" f dst
	[ -d "$keep" ] || return 0
	for f in "$keep"/*; do
		[ -f "$f" ] || continue
		dst="$(basename "$f" | sed 's#%#/#g')"
		mkdir -p "$(dirname "$dst")"
		cp -p "$f" "$dst" && echo "   ✓ $(basename "$dst") оставлен как был (#nochange)"
	done
	rm -rf "$keep"
}

_add_gp_domains() {
	_nochange_in /opt/zapret/ipset/zapret-hosts-google.txt && return 0
	local f="/opt/zapret/ipset/zapret-hosts-google.txt" tmp
	mkdir -p "$(dirname "$f")"
	tmp="$f.tmp"
	{
		[ -f "$f" ] && cat "$f"
		printf '%s\n' "gvt1.com" "googleplay.com" "play.google.com" "beacons.gvt2.com" \
			"play.googleapis.com" "play-fe.googleapis.com" "lh3.googleusercontent.com" \
			"android.clients.google.com" "connectivitycheck.gstatic.com" \
			"play-lh.googleusercontent.com" "play-games.googleusercontent.com" \
			"prod-lt-playstoregatewayadapter-pa.googleapis.com" "youtubei.youtube.com" \
			"cloudfunctions.net"
	} | sort -u > "$tmp"
	mv "$tmp" "$f"
}

_refresh_exclude_file() {
	_nochange_fetch /opt/zapret/ipset/zapret-hosts-user-exclude.txt "$EXCLUDE_URL"
}

YV_OFF_FLAG="/opt/zapret-manager-luci/yv_off"
DV_OFF_FLAG="/opt/zapret-manager-luci/dv_off"
DISCORD_RX='^--filter-l7=discord,stun$|^--filter-udp=19294-19344,50000-50100$|^--filter-tcp=2053,2083,2087,2096,8443$|^--hostlist-domains=discord[.]media$|^#[ \t]*Dv[0-9]+$'

YV_RX='^#[ \t]*Yv[0-9]+$|^--hostlist=/opt/zapret/ipset/zapret-hosts-google[.]txt$'
NFQ_MARK_RX='^[ \t]*#[ \t]*((Yv|Dv|Gv)[0-9]|udp443[ \t]*$|DoH[ \t]*$)'
UDP443_MARK_RX='^[ \t]*#[ \t]*udp443[ \t]*$'

_nfq_drop_profiles() {
	local rc zl=""
	if [ ! -s "$ZC_FILE" ] && _zc_has; then _zc_lift; zl=1; fi
	_nfq_drop_profiles_raw "$@"; rc=$?
	[ -n "$zl" ] && _zc_drop
	return $rc
}
_nfq_drop_profiles_raw() {
	local rx="$1" force="$2" keep="$3" old="$JOBS_DIR/nfq_drop_old" new="$JOBS_DIR/nfq_drop_new" rc
	mkdir -p "$JOBS_DIR"
	awk "/^[[:space:]]*option NFQWS_OPT '\$/ { f = 1 } f" "$CONF" > "$old"
	[ -s "$old" ] || { rm -f "$old"; return 1; }
	grep -q "^[[:space:]]*'[[:space:]]*\$" "$old" || { rm -f "$old"; return 1; }
	awk -v RX="$rx" -v KP="$keep" -v MK="$NFQ_MARK_RX" -v UQ="$UDP443_MARK_RX" -v q="'" '
		function emit(l) { o[++no] = l }
		function flush(   i, drop, real, udp) {
			if (n == 0 && np == 0) return
			drop = 0; real = 0; udp = 0
			for (i = 1; i <= np; i++) if (pc[i] ~ RX) drop = 1
			for (i = 1; i <= n; i++) {
				if (b[i] ~ RX) drop = 1
				if (b[i] !~ /^[ \t]*#/) real++
				if (b[i] == "--filter-udp=443") udp = 1
			}
			if (drop && KP != "") {
				for (i = 1; i <= np; i++) if (pc[i] ~ KP) drop = 0
				for (i = 1; i <= n; i++) if (b[i] ~ KP) drop = 0
			}
			if (drop) removed = 1
			else if (real > 0) {
				for (i = 1; i <= np; i++) if (udp || pc[i] !~ UQ) emit(pc[i])
				if (printed) emit("--new")
				for (i = 1; i <= n; i++) if (udp || b[i] !~ UQ) emit(b[i])
				printed = 1
			}
			n = 0; np = 0
		}
		function hold_in(   i) { for (i = 1; i <= nh; i++) b[++n] = h[i]; nh = 0 }
		NR == 1 { head = $0; next }
		done { tail[++nt] = $0; next }
		$0 ~ ("^[ \t]*" q "[ \t]*$") {
			hold_in(); flush()
			print head
			for (i = 1; i <= nn; i++) print nm[i]
			for (i = 1; i <= no; i++) print o[i]
			print
			done = 1; next
		}
		/^[ \t]*$/ { next }
		$0 == "--new" { flush(); for (k = 1; k <= nh; k++) pc[++np] = h[k]; nh = 0; next }
		/^[ \t]*#/ {
			if ($0 ~ MK) h[++nh] = $0
			else if (!(($0) in seen)) { seen[$0] = 1; nm[++nn] = $0 }
			next
		}
		{ hold_in(); b[++n] = $0 }
		END {
			if (!done) exit 1
			for (i = 1; i <= nt; i++) print tail[i]
			exit (removed ? 0 : 3)
		}' "$old" > "$new"
	rc=$?
	if [ "$rc" = 0 ] || { [ "$rc" = 3 ] && [ -n "$force" ]; }; then
		sed -i "/^[[:space:]]*option NFQWS_OPT '/,\$d" "$CONF"
		cat "$new" >> "$CONF"
	fi
	rm -f "$old" "$new"
	return $rc
}

_nfq_normalize() { _nfq_drop_profiles '^#ZM_NEVER_MATCHES$' force; return 0; }

_nfq_opt_body() {
	if [ -n "$ZM_NFQ_BODY" ]; then printf '%s\n' "$ZM_NFQ_BODY"; return 0; fi
	sed -n "/^[[:space:]]*option NFQWS_OPT '\$/,/^[[:space:]]*'\$/p" "$CONF" 2>/dev/null
}

ZC_FILE="$ZM_STATE_DIR/zapret.custom.lift"
ZC_BAK="$ZM_STATE_DIR/zapret.custom.conf"
ZC_AFTER="$ZM_STATE_DIR/zapret.custom.after"
ZC_START_RX='^[ \t]*#[ \t]*customstart[ \t]*$'
ZC_END_RX='^[ \t]*#[ \t]*customend[ \t]*$'
_zc_has() { _nfq_opt_body | awk -v S="$ZC_START_RX" -v E="$ZC_END_RX" 'tolower($0) ~ S { s = 1 } s && tolower($0) ~ E { f = 1 } END { exit !f }'; }
_zc_norm() {
	awk -v q="'" '
		function flush(   i) { while (nb > 0 && b[nb] == "--new") nb--; for (i = 1; i <= nb; i++) print b[i]; nb = 0 }
		!inb && /^[ \t]*option NFQWS_OPT \047[ \t]*$/ { print; inb = 1; nb = 0; next }
		inb && $0 ~ ("^[ \t]*" q "[ \t]*$") { flush(); print; inb = 0; next }
		inb { if ($0 == "--new" && (nb == 0 || b[nb] == "--new")) next; b[++nb] = $0; next }
		{ print }
		END { if (inb) flush() }' "$CONF" > "$CONF.zc" && [ -s "$CONF.zc" ] && cat "$CONF.zc" > "$CONF"
	rm -f "$CONF.zc"
}
_zc_lift() {
	[ -f "$CONF" ] || return 0
	[ -s "$ZC_FILE" ] && _zc_drop
	_zc_has || return 0
	mkdir -p "$ZM_STATE_DIR"
	cp -f "$CONF" "$ZC_BAK"
	awk -v F="$ZC_FILE" -v q="'" -v S="$ZC_START_RX" -v E="$ZC_END_RX" '
		!inb && /^[ \t]*option NFQWS_OPT \047[ \t]*$/ { inb = 1; print; next }
		inb && $0 ~ ("^[ \t]*" q "[ \t]*$") { inb = 0; print; next }
		inb && !c && tolower($0) ~ S { c = 1 }
		c { print > F; if (tolower($0) ~ E) c = 0; next }
		{ print }' "$CONF" > "$CONF.zc" || { rm -f "$CONF.zc" "$ZC_FILE" "$ZC_BAK"; return 0; }
	if [ ! -s "$ZC_FILE" ] || [ ! -s "$CONF.zc" ]; then rm -f "$CONF.zc" "$ZC_FILE" "$ZC_BAK"; return 0; fi
	cat "$CONF.zc" > "$CONF"; rm -f "$CONF.zc"
	awk -v S="$ZC_START_RX" -v E="$ZC_END_RX" '{ a[NR] = $0 } END { for (i = 1; i <= NR; i++) { if (a[i] == "--new" && (i == 1 || i == NR || tolower(a[i - 1]) ~ S || tolower(a[i + 1]) ~ E)) continue; print a[i] } }' 		"$ZC_FILE" > "$ZC_FILE.n" && [ -s "$ZC_FILE.n" ] && mv -f "$ZC_FILE.n" "$ZC_FILE"
	rm -f "$ZC_FILE.n"
	_zc_norm
	cp -f "$CONF" "$ZC_AFTER"
	ZC_LIFTED=1
}
_zc_drop() {
	[ -s "$ZC_FILE" ] || { rm -f "$ZC_FILE" "$ZC_BAK" "$ZC_AFTER"; ZC_LIFTED=""; return 0; }
	[ -f "$CONF" ] && grep -q "^[[:space:]]*option NFQWS_OPT '[[:space:]]*\$" "$CONF" || return 0
	if _zc_has; then rm -f "$ZC_FILE" "$ZC_BAK" "$ZC_AFTER"; ZC_LIFTED=""; return 0; fi
	if [ -s "$ZC_BAK" ] && [ -f "$ZC_AFTER" ] && cmp -s "$CONF" "$ZC_AFTER"; then
		cat "$ZC_BAK" > "$CONF"
	else
		awk -v F="$ZC_FILE" '
			!d && /^[ \t]*option NFQWS_OPT \047[ \t]*$/ { print; while ((getline l < F) > 0) print l; print "--new"; d = 1; next }
			{ print }' "$CONF" > "$CONF.zc" && [ -s "$CONF.zc" ] && cat "$CONF.zc" > "$CONF"
		rm -f "$CONF.zc"
		_zc_norm
	fi
	rm -f "$ZC_FILE" "$ZC_BAK" "$ZC_AFTER"
	ZC_LIFTED=""
}
_nfq_names() {
	_nfq_opt_body | awk -v S="$ZC_START_RX" -v E="$ZC_END_RX" 'tolower($0) ~ S { c = 1; next } c { if (tolower($0) ~ E) c = 0; next } /^#/ { print }'
}
_udp443_on() { case "$ZM_UDP" in 1) return 0 ;; 0) return 1 ;; esac; _nfq_opt_body | grep -qx -- '--filter-udp=443'; }
_udp443_add() {
	_udp443_on && return 0
	sed -i '/^[[:space:]]*#[[:space:]]*udp443[[:space:]]*$/d' "$CONF"
	sed -i "/^[[:space:]]*option NFQWS_OPT '/a\\#udp443\\n--filter-udp=443\\n--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt\\n--dpi-desync=fake\\n--dpi-desync-repeats=11\\n--dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin\\n--new" "$CONF"
	_add_ports_if_missing NFQWS_PORTS_UDP 443
}

youtube_quic_set() {
	local mode="$1"
	[ -f "$CONF" ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	case "$mode" in
		on)
			_udp443_on && { printf '{"ok":true,"quic":true}\n'; return 0; }
			_add_gp_domains
			_udp443_add
			_nfq_normalize ;;
		off)
			_udp443_on || { sed -i '/^[[:space:]]*#[[:space:]]*udp443[[:space:]]*$/d' "$CONF"; printf '{"ok":true,"quic":false}\n'; return 0; }
			_nfq_drop_profiles '^--filter-udp=443$'
			case $? in 0|3) ;; *) echo '{"error":"блок стратегий Zapret (NFQWS_OPT) записан не так, как его пишет панель, — блок QUIC не тронут"}'; return 1 ;; esac
			sed -i '/^[[:space:]]*#[[:space:]]*udp443[[:space:]]*$/d' "$CONF" ;;
		*) echo '{"error":"неизвестное действие"}'; return 1 ;;
	esac
	zapret_restart
	printf '{"ok":true,"quic":%s}\n' "$(_udp443_on && echo true || echo false)"
}

_add_yv_default() {
	[ -f "$YV_OFF_FLAG" ] && return 0
	if ! grep -q "^#Yv" "$CONF" && ! grep -q "^#general" "$CONF"; then
		sed -i "/^[[:space:]]*option NFQWS_OPT '/a\\#Yv08\\n--filter-tcp=443\\n--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt\\n--dpi-desync=hostfakesplit\\n--dpi-desync-hostfakesplit-mod=host=google.com\\n--dpi-desync-fooling=ts\\n--new" "$CONF"
	fi
}

_discord_str_add() {
	[ -f "$DV_OFF_FLAG" ] && return 0
	if ! grep -q "option NFQWS_PORTS_UDP.*19294-19344,50000-50100" "$CONF"; then
		sed -i "/^[[:space:]]*option NFQWS_PORTS_UDP '/s/'\$/,19294-19344,50000-50100'/" "$CONF"
	fi
	if ! grep -q "option NFQWS_PORTS_TCP.*2053,2083,2087,2096,8443" "$CONF"; then
		sed -i "/^[[:space:]]*option NFQWS_PORTS_TCP '/s/'\$/,2053,2083,2087,2096,8443'/" "$CONF"
	fi
	if ! grep -q -- "--filter-udp=19294-19344,50000-50100" "$CONF"; then
		local last_line1
		last_line1=$(grep -n "^'\$" "$CONF" | tail -n1 | cut -d: -f1)
		[ -n "$last_line1" ] && sed -i "${last_line1},\$d" "$CONF"
		printf "%s\n" "--new" "--filter-udp=19294-19344,50000-50100" "--filter-l7=discord,stun" \
			"--dpi-desync=fake" "--dpi-desync-fake-discord=/opt/zapret/files/fake/stun.bin" \
			"--dpi-desync-fake-stun=/opt/zapret/files/fake/stun.bin" "--dpi-desync-repeats=6" \
			"#Dv1" "--new" "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" \
			"--dpi-desync=multisplit" "--dpi-desync-split-seqovl=652" "--dpi-desync-split-pos=2" \
			"--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin" \
			"'" >> "$CONF"
	fi
}

_ts_warning() { grep -q "=ts" "$CONF" 2>/dev/null && echo true || echo false; }

ZM_TS_RX='fooling=([a-z0-9]+,)*ts(,|$)'
_ts_has() { grep -qE -- "$ZM_TS_RX"; }
_ts_parts() {
	awk -v pu="--filter-udp=$PORTS_UDP" -v pt="--filter-tcp=$PORTS_TCP" -v rx="$ZM_TS_RX" '
		function flush(   lab) {
			if (has) {
				seen[g ? "YouTube" : dc ? "Discord" : gm ? "игры" : "основная"] = 1
			}
			has = 0; g = 0; dc = 0; gm = 0
		}
		{ sub(/^[ \t]+/, ""); sub(/[ \t\r]+$/, "") }
		$0 == "--new" { flush(); next }
		/^#/ || $0 == "" || $0 == "'"'"'" { next }
		$0 ~ rx { has = 1 }
		/zapret-hosts-google|^--filter-udp=443$/ { g = 1 }
		/discord|19294-19344|2053,2083/ { dc = 1 }
		$0 == pu || $0 == pt || /^--filter-(udp|tcp)=80,88,444-65535$/ { gm = 1 }
		END { flush(); n = split("основная YouTube Discord игры", O, " "); for (i = 1; i <= n; i++) if (O[i] in seen) print O[i] }'
}
_ts_yv_text() { [ -s "$(_yv_file)" ] && awk -v n="#$1" '$0 == n { f = 1; next } /^#Yv[0-9]/ { f = 0 } f' "$(_yv_file)"; }
ts_check() {
	local kind="${1%%:*}" id="${1#*:}" out="" yv dv gv l
	_ts_add() { out="$out${out:+,}\"$(esc "$1")\""; }
	case "$kind" in
		v)
			_zm_re "$id" '^v([1-9]|10)$' || { echo '{"error":"некорректная версия"}'; return 1; }
			strategy_"$id" | _ts_has && _ts_add "основная · $id"
			if [ ! -f "$YV_OFF_FLAG" ] && [ -f "$CONF" ]; then
				yv="$(grep -oE '^#[[:space:]]*Yv[0-9]+$' "$CONF" | head -n1 | sed 's/^#[[:space:]]*//')"
				if [ -n "$yv" ] && [ "$yv" != Yv08 ] && [ -n "$(_ts_yv_text "$yv")" ]; then
					_ts_yv_text "$yv" | _ts_has && _ts_add "YouTube · $yv"
				else
					printf '%s\n' '--dpi-desync-fooling=ts' | _ts_has && _ts_add "YouTube · Yv08"
				fi
			fi
			if [ ! -f "$DV_OFF_FLAG" ] && [ -f "$CONF" ]; then
				dv="$(grep -oE '^#[[:space:]]*Dv[0-9]+$' "$CONF" | head -n1 | sed 's/^#[[:space:]]*Dv//')"
				_zm_re "${dv:-1}" '^(1[0-7]|[1-9])$' && Dv"${dv:-1}" | _ts_has && _ts_add "Discord · Dv${dv:-1}"
			fi
			gv="$(grep -oE '^#Gv[1-4](Xtreme)?$' "$CONF" 2>/dev/null | head -n1 | sed 's/^#Gv//; s/Xtreme$//')"
			if [ -n "$gv" ]; then
				{ if [ "$gv" = 1 ]; then strategy_Gv1; else strategy_Gv "$gv"; fi; strategy_TCP_common; } | _ts_has && _ts_add "игры · Gv$gv"
			fi ;;
		flowseal)
			[ -s "$(_flowseal_file)" ] || { echo '{"ts":false,"parts":[]}'; return 0; }
			awk -v n="#$id" '$0 == n { f = 1; next } /^#/ && f { exit } f' "$(_flowseal_file)" | _ts_parts > "$JOBS_DIR/ts.parts"
			while IFS= read -r l; do _ts_add "$l"; done < "$JOBS_DIR/ts.parts" ;;
		youtube)
			_ts_yv_text "$id" | _ts_has && _ts_add "YouTube · $id" ;;
		dv)
			_zm_re "$id" '^(1[0-7]|[1-9])$' && Dv"$id" | _ts_has && _ts_add "Discord · Dv$id" ;;
		gv)
			_zm_re "$id" '^[1-4]$' && { if [ "$id" = 1 ]; then strategy_Gv1; else strategy_Gv "$id"; fi; strategy_TCP_common; } | _ts_has && _ts_add "игры · Gv$id" ;;
		text)
			printf '%s\n' "$id" | _ts_parts > "$JOBS_DIR/ts.parts"
			while IFS= read -r l; do _ts_add "$l"; done < "$JOBS_DIR/ts.parts" ;;
		current)
			[ -f "$CONF" ] || { echo '{"ts":false,"parts":[]}'; return 0; }
			_nfq_opt_body | _ts_parts > "$JOBS_DIR/ts.parts"
			while IFS= read -r l; do _ts_add "$l"; done < "$JOBS_DIR/ts.parts" ;;
		*) echo '{"error":"неизвестный вид стратегии"}'; return 1 ;;
	esac
	rm -f "$JOBS_DIR/ts.parts"
	printf '{"ts":%s,"parts":[%s]}\n' "$([ -n "$out" ] && echo true || echo false)" "$out"
}

strategy_list_v() {
	printf '{"items":[%s]}\n' "$(
		i=1
		while [ "$i" -le 10 ]; do
			printf '{"id":"v%s","label":"Стратегия v%s"}' "$i" "$i"
			[ "$i" -lt 10 ] && printf ','
			i=$((i + 1))
		done
	)"
}

strategy_set_v() {
	local version="$1" yv yvk dv gv xt q w
	_zm_re "$version" '^v([1-9]|10)$' || { echo '{"error":"некорректная версия"}'; return 1; }
	[ -f "$CONF" ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	_udp443_on && q=1
	_zo_wss_on && w=1
	yv=$(grep -oE '^#[[:space:]]*Yv[0-9]+$' "$CONF" | head -n1 | sed 's/^#[[:space:]]*//')
	yvk=""
	if [ -n "$yv" ] && [ "$yv" != Yv08 ] && [ ! -f "$YV_OFF_FLAG" ]; then
		yvk="$JOBS_DIR/yv_keep.$$"
		_nfq_opt_body | awk -v y="$yv" -v q="'" '{ l = $0; gsub(/[ \t\r]/, "", l) } l == "#" y { f = 1; print l; next } f && (l == "--new" || l == q || l ~ /^#(Yv|Dv|Gv|v)[0-9]/) { exit } f && l != "" { sub(/^[ \t]+/, ""); sub(/[ \t\r]+$/, ""); print }' > "$yvk"
		[ "$(grep -c -- '^--' "$yvk" 2>/dev/null)" -gt 0 ] || { rm -f "$yvk"; yvk=""; }
	fi
	dv=$(grep -oE '^#[[:space:]]*Dv[0-9]+$' "$CONF" | head -n1 | sed 's/^#[[:space:]]*Dv//')
	gv=$(grep -oE '^#Gv[1-4](Xtreme)?$' "$CONF" | head -n1 | sed 's/^#Gv//; s/Xtreme$//')
	grep -q "^#Gv[0-9]\+Xtreme\$" "$CONF" && xt=1
	_game_xtreme_undo_opts
	_remove_ports_if_present NFQWS_PORTS_UDP "$PORTS_UDP"
	_remove_ports_if_present NFQWS_PORTS_TCP "$PORTS_TCP"
	sed -i '/^# ZMFS:/d' "$CONF"
	sed -i "/^[[:space:]]*option NFQWS_OPT '/,\$d" "$CONF"
	{ echo "	option NFQWS_OPT '"; strategy_"$version"; echo "'"; } >> "$CONF"
	_add_gp_domains
	_refresh_exclude_file
	_add_yv_default
	_discord_str_add
	ZM_NO_RESTART=1
	if [ -n "$yv" ] && [ "$yv" != Yv08 ] && [ ! -f "$YV_OFF_FLAG" ] && [ ! -s "$(_yv_file)" ]; then
		do_yv_download >/dev/null 2>&1
	fi
	if [ -n "$yv" ] && [ "$yv" != Yv08 ] && [ ! -f "$YV_OFF_FLAG" ] && [ -s "$(_yv_file)" ] && grep -qxF "#$yv" "$(_yv_file)"; then
		strategy_set_youtube "$yv" >/dev/null
	elif [ -n "$yvk" ]; then
		ZM_YV_FILE="$yvk"; strategy_set_youtube "$yv" >/dev/null; ZM_YV_FILE=""
	fi
	[ -n "$yvk" ] && rm -f "$yvk"
	[ -n "$dv" ] && [ "$dv" != 1 ] && [ ! -f "$DV_OFF_FLAG" ] && discord_set_dv "$dv" >/dev/null
	if [ -n "$gv" ]; then
		game_set "$gv" >/dev/null
		[ -n "$xt" ] && game_toggle_xtreme >/dev/null
	fi
	[ -n "$q" ] && _udp443_add
	_zo_reapply "$w"
	ZM_NO_RESTART=""
	_nfq_normalize
	zapret_restart
	printf '{"ok":true,"strategy":"%s","ts_warning":%s}\n' "$version" "$(_ts_warning)"
}

_flowseal_file() { echo "$JOBS_DIR/flowseal_strategies.txt"; }

FLOWSEAL_FAKES="stun2.bin quic_initial_4pda_to.bin quic_initial_5ka_ru.bin quic_initial_lemana_pro.bin \
quic_initial_rutube_ru.bin quic_initial_steam_chat_com.bin quic_initial_steamcommunity_com.bin \
quic_initial_steamstatic_com.bin quic_initial_tencent_com.bin tls_clienthello_4pda_to.bin \
tls_clienthello_5ka_ru.bin tls_clienthello_awswaf_com.bin tls_clienthello_max_ru.bin \
tls_clienthello_sochi_park.bin tls_clienthello_steam_chat_com.bin tls_clienthello_steamstatic_com.bin \
tls_clienthello_teamspeak_com.bin tls_clienthello_www_sferum_ru.bin tls_clienthello_www_google_com_2.bin"

do_add_fake_flow() {
	[ -d /opt/zapret ] || return 0
	[ -f "$CONF" ] || return 0
	local d=/opt/zapret/files/fake f extra="" list="" n=0
	mkdir -p "$d"
	[ -s "$(_flowseal_file)" ] && extra=$(grep -oE "$d/[A-Za-z0-9_.-]+\.bin" "$(_flowseal_file)" | sed "s|^$d/||" | sort -u)
	for f in $FLOWSEAL_FAKES $extra; do
		case "$f" in ACTIVE_*) continue ;; esac
		case " $list " in *" $f "*) continue ;; esac
		[ -s "$d/$f" ] && continue
		list="$list $f"; n=$((n + 1))
	done
	if [ "$n" = 0 ]; then echo "==> fake-файлы на месте"; return 0; fi
	echo "==> Скачиваем недостающие fake-файлы: $n"
	_fake_get_many $list
	if [ "$ZM_FAKE_BAD" = 0 ]; then echo "   ✓ Все fake-файлы скачаны: $ZM_FAKE_OK"
	else echo "!! Скачано fake-файлов: $ZM_FAKE_OK из $n. Стратегии с недостающими файлами работать не будут — панель докачает их при смене стратегии"; fi
}

ZAPRET_FAKE_RAW="${GH_MAIN}/bol-van/zapret/raw/refs/heads/master/files/fake"
ZM_FAKE_RAW="${GH_MAIN}/Screamshow/Zapret-Manager/raw/refs/heads/main/files"
FAKE_FAIL="$JOBS_DIR/fake_fail"
_fake_missing() {
	local f d=/opt/zapret/files/fake
	grep -oE "$d/[A-Za-z0-9_.-]+\.bin" "${1:-$CONF}" 2>/dev/null | sort -u | while read -r f; do
		case "${f##*/}" in ACTIVE_*) continue ;; esac
		[ -s "$f" ] || echo "${f##*/}"
	done
}
ZM_FAKE_OWN="tls_clienthello_www_google_com_2.bin"
_fake_fetch() {
	local d=/opt/zapret/files/fake u srcs err=""
	mkdir -p "$d"
	ZM_FAKE_SRC=""
	srcs="$FLOWSEAL_FAKE_RAW $ZAPRET_FAKE_RAW $ZM_FAKE_RAW"
	case " $ZM_FAKE_OWN " in *" $1 "*) srcs="$ZM_FAKE_RAW $FLOWSEAL_FAKE_RAW" ;; esac
	for u in $srcs; do
		rm -f "$d/$1.zmdl"
		if _zm_fetch "$u/$1" "$d/$1.zmdl" 30; then
			mv -f "$d/$1.zmdl" "$d/$1"; chmod a+r "$d/$1" 2>/dev/null
			case "$u" in "$FLOWSEAL_FAKE_RAW") ZM_FAKE_SRC=Flowseal ;; "$ZAPRET_FAKE_RAW") ZM_FAKE_SRC=zapret ;; *) ZM_FAKE_SRC="Zapret Manager" ;; esac
			return 0
		fi
		case "$u" in "$FLOWSEAL_FAKE_RAW") u=Flowseal ;; "$ZAPRET_FAKE_RAW") u=zapret ;; *) u="Zapret Manager" ;; esac
		err="${err:+$err; }$u — $ZM_FETCH_ERR"
	done
	rm -f "$d/$1.zmdl"
	ZM_FETCH_ERR="$err"
	return 1
}
_fake_get_many() {
	local d=/opt/zapret/files/fake r="$JOBS_DIR/fakes.$$" f n=0 tot=$# batch="" pids="" st src sz why
	ZM_FAKE_OK=0; ZM_FAKE_BAD=0; ZM_FAKE_FAILED=""
	mkdir -p "$d" "$r"
	for f; do
		( if _fake_fetch "$f"; then printf 'ok|%s|%s\n' "$ZM_FAKE_SRC" "$(wc -c < "$d/$f" | tr -d ' ')"; else printf 'bad|%s\n' "$ZM_FETCH_ERR"; fi ) > "$r/$f" 2>/dev/null &
		pids="$pids $!"; batch="$batch $f"; n=$((n + 1))
		[ $((n % 4)) = 0 ] || [ "$n" = "$tot" ] || continue
		wait $pids 2>/dev/null
		for f in $batch; do
			IFS='|' read -r st src sz < "$r/$f" 2>/dev/null
			if [ "$st" = ok ]; then
				ZM_FAKE_OK=$((ZM_FAKE_OK + 1))
				echo "   ✓ $f — $(_zm_size_txt "$sz")$([ "$src" != Flowseal ] && echo " · из $src")"
			else
				why="$(sed -n 's/^bad|//p' "$r/$f" 2>/dev/null)"
				ZM_FAKE_BAD=$((ZM_FAKE_BAD + 1)); ZM_FAKE_FAILED="$ZM_FAKE_FAILED $f"
				echo "   !! $f — не скачался: ${why:-нет ответа}"
			fi
		done
		pids=""; batch=""
	done
	rm -rf "$r"
	return 0
}
_fake_ensure() {
	local f t now miss
	[ -d /opt/zapret ] || return 0
	miss="$(_fake_missing "$1")"
	[ -n "$miss" ] || return 0
	now="$(date +%s)"
	mkdir -p "$JOBS_DIR"
	local want=""
	for f in $miss; do
		t="$(awk -v f="$f" '$1 == f { t = $2 } END { print t }' "$FAKE_FAIL" 2>/dev/null)"
		if [ -n "$t" ] && [ $((now - t)) -lt 600 ]; then echo "!! Нет fake-файла $f (недавно не скачался) — стратегия с ним может не работать"; continue; fi
		want="$want $f"
	done
	[ -n "$want" ] || return 0
	echo "==> Докачиваем fake-файлы для стратегии: $(echo $want | wc -w)"
	_fake_get_many $want
	for f in $want; do
		case " $ZM_FAKE_FAILED " in
			*" $f "*) echo "$f $now" >> "$FAKE_FAIL" ;;
			*) [ -f "$FAKE_FAIL" ] && awk -v f="$f" '$1 != f' "$FAKE_FAIL" > "$FAKE_FAIL.t" && mv -f "$FAKE_FAIL.t" "$FAKE_FAIL" ;;
		esac
	done
	[ "$ZM_FAKE_BAD" = 0 ] || echo "!! Стратегия с недостающими fake-файлами может не работать"
	return 0
}

do_flowseal_download() {
	_ensure_deps
	local out zip tmp attempt=1 max_attempts=5 dst
	dst="$(_flowseal_file)"; out="$dst.new"; zip="$JOBS_DIR/flowseal.zip"; tmp="$JOBS_DIR/flowseal_src"
	echo "==> Скачиваем список стратегий Flowseal"
	rm -rf "$tmp" "$zip"; : > "$out"
	command -v unzip >/dev/null 2>&1 || $INSTALL unzip >&2

	while [ "$attempt" -le "$max_attempts" ]; do
		rm -f "$zip"
		if ! _zm_fetch "$FLOWSEAL_ZIP" "$zip" 180; then
			echo "!! Попытка $attempt из $max_attempts: архив Flowseal не скачался — $ZM_FETCH_ERR"
			case "$ZM_FETCH_ERR" in *"(HTTP 404)"*|*"(HTTP 410)"*) attempt=$max_attempts ;; esac
		fi
		if [ -s "$zip" ] && unzip -tq "$zip" >/dev/null 2>&1; then
			echo "   ✓ Архив скачан и проверен: $(_zm_size_txt "$(wc -c < "$zip" | tr -d ' ')")"
			break
		fi
		attempt=$((attempt + 1))
	done
	if [ "$attempt" -gt "$max_attempts" ]; then
		echo "ОШИБКА: не удалось скачать целый архив за $max_attempts попыток — проверьте соединение с GitHub"
		rm -f "$out" "$zip"
		[ -s "$dst" ] && echo "   · Остался прежний список Flowseal — его стратегии можно выбирать"
		return 1
	fi

	mkdir -p "$tmp"; unzip -oq "$zip" -d "$tmp" || { echo "ОШИБКА распаковки"; rm -rf "$out" "$zip" "$tmp"; return 1; }
	local base="$tmp/zapret-discord-youtube-main"

	echo "==> Разбираем .bat-стратегии"
	find "$base" -type f -name 'general*.bat' ! -name 'general (ALT5).bat' | while read -r F; do
		MATCH=$(grep -E '^--filter-udp=19294-19344,50000-50100|^--filter-tcp=%GameFilterTCP%|^--filter-udp=%GameFilterUDP%|^--filter-tcp=2053,2083,2087,2096,8443|^--filter-tcp=443 --hostlist="%LISTS%list-google.txt"|^--filter-tcp=80,443 --hostlist="%LISTS%list-general.txt"' "$F")
		[ -z "$MATCH" ] && continue
		NAME=$(basename "$F" .bat)
		{ echo "#$NAME"; echo "$MATCH" | sed 's/--/\n--/g' | sed '/^$/d' | sed 's/[[:space:]]*$//'; echo; } >> "$out"
	done

	echo "==> Приводим пути и плейсхолдеры к реальным (как в оригинальном download_strategies)"
	sed -i '/--hostlist="%LISTS%list-general.txt"/d' "$out"
	sed -i '/--ipset="%LISTS%ipset-all.txt"/d' "$out"
	sed -i '/--hostlist="%LISTS%list-general-user.txt"/d' "$out"
	sed -i '/--ipset-exclude="%LISTS%ipset-exclude.txt"/d' "$out"
	sed -i '/--ipset-exclude="%LISTS%ipset-exclude-user.txt"/d' "$out"
	sed -i '/--hostlist-exclude="%LISTS%list-exclude-user.txt"/d' "$out"
	sed -i 's|"%LISTS%list-exclude.txt"|/opt/zapret/ipset/zapret-hosts-user-exclude.txt|g' "$out"
	sed -i 's|"%LISTS%list-google.txt"|/opt/zapret/ipset/zapret-hosts-google.txt|g' "$out"
	sed -i 's/--new[[:space:]]\^/--new/g' "$out"

	sed -i 's|"%BIN%ACTIVE_DISCORD_UDP.bin"|/opt/zapret/files/fake/quic_initial_steamcommunity_com.bin|g' "$out"
	sed -i 's|"%BIN%ACTIVE_GAME_UDP.bin"|/opt/zapret/files/fake/quic_initial_4pda_to.bin|g' "$out"
	sed -i 's|"%BIN%\([A-Za-z0-9_.-]*\.bin\)"|/opt/zapret/files/fake/\1|g; s|%BIN%\([A-Za-z0-9_.-]*\.bin\)|/opt/zapret/files/fake/\1|g' "$out"
	sed -i 's|\^!|/opt/zapret/files/fake/tls_clienthello_www_google_com.bin|g' "$out"

	sed -i "s|%GameFilterTCP%|$PORTS_TCP|g" "$out"
	sed -i "s|%GameFilterUDP%|$PORTS_UDP|g" "$out"

	sed -i 's/[[:space:]]\+$//' "$out"
	sed -i '/^[[:space:]]*$/d' "$out"
	sed -i '/^--new$/ { N; /^--new\n$/d; }' "$out"

	local left
	left=$(grep -oE '%[A-Za-z_]+%' "$out" | sort -u | tr '\n' ' ')
	[ -n "$left" ] && echo "!! В стратегиях остались неизвестные плейсхолдеры: $left"

	if [ -d /opt/zapret ]; then
		echo "==> Добавляем fake-файлы из архива Flowseal"
		mkdir -p /opt/zapret/files/fake
		local fb fn
		for fb in "$base"/bin/*.bin; do
			[ -s "$fb" ] || continue
			fn=$(basename "$fb")
			case "$fn" in ACTIVE_*) continue ;; esac
			if [ ! -s "/opt/zapret/files/fake/$fn" ]; then cp -f "$fb" "/opt/zapret/files/fake/$fn"
			else case " $FLOWSEAL_FAKES " in *" $fn "*) cmp -s "$fb" "/opt/zapret/files/fake/$fn" 2>/dev/null || cp -f "$fb" "/opt/zapret/files/fake/$fn" ;; esac; fi
		done
	fi

	rm -rf "$tmp" "$zip"

	do_add_fake_flow

	local miss
	miss=$(grep -oE '/opt/zapret/files/fake/[A-Za-z0-9_.-]+\.bin' "$out" | sort -u | while read -r fb; do [ -s "$fb" ] || printf '%s ' "${fb##*/}"; done)
	[ -n "$miss" ] && [ -d /opt/zapret ] && echo "!! Нет fake-файлов: $miss— стратегии с ними работать не будут"

	if ! grep -q '^#' "$out"; then
		rm -f "$out"
		echo "ОШИБКА: в архиве Flowseal не нашлось ни одной стратегии"
		return 1
	fi
	mv -f "$out" "$dst"
	echo "==> Готово, стратегий: $(grep -c '^#' "$dst")"
}

strategy_list_flowseal() {
	local f; f="$(_flowseal_file)"
	if [ "$1" = cached ] && [ ! -s "$f" ]; then
		printf '{"items":[],"none":true,"running":%s}\n' "$(_job_running flowseal_download && echo true || echo false)"
		return 0
	fi
	if [ ! -s "$f" ] || [ "$1" = refresh ]; then
		job_start flowseal_download do_flowseal_download
		return
	fi
	printf '{"running":%s,"items":[%s]}\n' "$(_job_running flowseal_download && echo true || echo false)" "$(
		grep '^#' "$f" | sed 's/^#//' | awk "$ZM_JESC_AWK"'{
			v = jesc($0)
			printf "%s{\"id\":\"%s\",\"label\":\"%s\"}", (NR>1?",":""), v, v
		}'
	)"
}

strategy_set_flowseal() {
	local name="$1" f block q w
	f="$(_flowseal_file)"
	[ -s "$f" ] || { echo '{"error":"список не загружен — сначала обновите"}'; return 1; }
	[ -f "$CONF" ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	case "$name" in *"$ZM_NL"*|*\\*) echo '{"error":"стратегия не найдена"}'; return 1 ;; esac
	block=$(awk -v n="#$name" '$0==n{flag=1; print; next} /^#/ && flag{exit} flag{print}' "$f")
	[ -z "$block" ] && { echo '{"error":"стратегия не найдена"}'; return 1; }
	_udp443_on && q=1
	_zo_wss_on && w=1
	rm -f "$YV_OFF_FLAG" "$DV_OFF_FLAG"
	_game_xtreme_undo_opts
	_remove_ports_if_present NFQWS_PORTS_UDP "$PORTS_UDP"
	_remove_ports_if_present NFQWS_PORTS_TCP "$PORTS_TCP"
	sed -i '/^# ZMFS:/d' "$CONF"
	{ printf '# ZMFS:%s\n' "$name"; cat "$CONF"; } > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
	sed -i "/option NFQWS_OPT '/,\$d" "$CONF"
	{ echo "	option NFQWS_OPT '"; echo "$block"; echo "'"; } >> "$CONF"
	if ! grep -q "option NFQWS_PORTS_UDP.*19294-19344,50000-50100" "$CONF"; then
		sed -i "/^[[:space:]]*option NFQWS_PORTS_UDP '/s/'\$/,19294-19344,50000-50100'/" "$CONF"
	fi
	if ! grep -q "option NFQWS_PORTS_TCP.*2053,2083,2087,2096,8443" "$CONF"; then
		sed -i "/^[[:space:]]*option NFQWS_PORTS_TCP '/s/'\$/,2053,2083,2087,2096,8443'/" "$CONF"
	fi
	_add_gp_domains
	_refresh_exclude_file
	sed -i '/--new/{N;/--filter-tcp=2802/{s/--new/#Gv0\n--new/;};}' "$CONF"
	if printf '%s\n' "$block" | grep -qxF -e "--filter-udp=$PORTS_UDP" -e "--filter-tcp=$PORTS_TCP"; then
		_add_ports_if_missing NFQWS_PORTS_UDP "$PORTS_UDP"
		_add_ports_if_missing NFQWS_PORTS_TCP "$PORTS_TCP"
	fi
	[ -n "$q" ] && _udp443_add
	_zo_reapply "$w"
	zapret_restart
	printf '{"ok":true,"strategy":"%s","ts_warning":%s}\n' "$(esc "$name")" "$(_ts_warning)"
}

_yv_file() { echo "${ZM_YV_FILE:-$JOBS_DIR/youtube_strategies.txt}"; }

do_yv_download() {
	_ensure_deps
	local out; out="$(_yv_file)"
	echo "==> Скачиваем список стратегий для YouTube"
	_zm_fetch "$STR_URL" "$out" 20 || { echo "ОШИБКА скачивания: $ZM_FETCH_ERR"; return 1; }
	local n
	for n in $YV_BUILTIN; do
		grep -qx "#Yv$n" "$out" && continue
		[ -n "$(tail -c 1 "$out")" ] && echo >> "$out"
		_yv_builtin "$n" >> "$out"
	done
	[ -d /opt/zapret ] && [ -n "$(_fake_missing "$out")" ] && _fake_ensure "$out"
	echo "==> Готово, стратегий: $(grep -c '^#Yv' "$out")"
}

YV_BUILTIN="28 29 30 31"
_yv_builtin() {
	local G="--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt" F="/opt/zapret/files/fake"
	case "$1" in
		29) printf '%s\n' "#Yv29" "--filter-tcp=443" "$G" "--dpi-desync=hostfakesplit" "--dpi-desync-fooling=ts" \
			"--dpi-desync-hostfakesplit-mod=host=www.google.com" "--dpi-desync-hostfakesplit-midhost=midsld+1"; return ;;
		30) printf '%s\n' "#Yv30" "--filter-tcp=443" "$G" "--dpi-desync=hostfakesplit" "--dpi-desync-fooling=ts" \
			"--dpi-desync-hostfakesplit-mod=host=www.google.com" "--dpi-desync-hostfakesplit-midhost=sld+1"; return ;;
		31) printf '%s\n' "#Yv31" "--filter-tcp=443" "$G" "--dpi-desync=fake,multisplit" "--dpi-desync-split-seqovl=717" \
			"--dpi-desync-split-pos=sld,sld+3,endhost-1" "--dpi-desync-fooling=ts" "--dpi-desync-repeats=8" \
			"--dpi-desync-split-seqovl-pattern=$F/tls_clienthello_www_google_com_2.bin" "--dpi-desync-fake-tls=$F/tls_clienthello_www_google_com_2.bin"; return ;;
		28) ;;
		*) return 1 ;;
	esac
	printf '%s\n' "#Yv28" "--filter-tcp=443" "--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt" \
		"--dpi-desync=fake,multidisorder" "--dpi-desync-split-seqovl=midsld-4" \
		"--dpi-desync-split-pos=2,midsld+3,sniext+2,endhost-2,midsld-3,host+1,-10" "--dpi-desync-fooling=ts" \
		"--dpi-desync-repeats=23" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_sferum_ru.bin" \
		"--dpi-desync-fake-tls=/opt/zapret/files/fake/stun2.bin" "--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_sferum_ru.bin" \
		"--dpi-desync-fake-tls=/opt/zapret/files/fake/stun.bin" "--dpi-desync-fake-http=/opt/zapret/files/fake/tls_clienthello_max_ru.bin"
}

strategy_list_youtube() {
	local f; f="$(_yv_file)"
	if [ ! -s "$f" ] || [ "$1" = refresh ]; then
		job_start youtube_download do_yv_download
		return
	fi
	printf '{"items":[%s]}\n' "$(
		grep -oE '^#Yv[0-9]+' "$f" | sed 's/^#//' | awk '{
			printf "%s{\"id\":\"%s\"}", (NR>1?",":""), $0
		}'
	)"
}

_yv_block_remove() { _nfq_drop_profiles "$YV_RX" "" '^--filter-udp=443$'; }

strategy_set_youtube() {
	local name="$1" f selected
	if [ "$name" = off ]; then
		[ -f "$CONF" ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
		_yv_block_remove
		case $? in
			0) mkdir -p "$(dirname "$YV_OFF_FLAG")"; touch "$YV_OFF_FLAG"; zapret_restart; printf '{"ok":true,"strategy":"off","removed":true}\n' ;;
			3) mkdir -p "$(dirname "$YV_OFF_FLAG")"; touch "$YV_OFF_FLAG"; printf '{"ok":true,"strategy":"off","removed":false}\n' ;;
			*) echo '{"error":"блок стратегий Zapret (NFQWS_OPT) записан не так, как его пишет панель, — YouTube-часть не тронута"}'; return 1 ;;
		esac
		return 0
	fi
	f="$(_yv_file)"
	[ -s "$f" ] || { echo '{"error":"список не загружен — сначала обновите"}'; return 1; }
	[ -f "$CONF" ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	selected="#$name"
	case "$name" in *"$ZM_NL"*) echo '{"error":"стратегия не найдена"}'; return 1 ;; esac
	grep -qxF "$selected" "$f" || { echo '{"error":"стратегия не найдена"}'; return 1; }
	rm -f "$YV_OFF_FLAG"

	local saved="$JOBS_DIR/yv_saved" newtmp="$JOBS_DIR/yv_new" finaltmp="$JOBS_DIR/yv_final" oldtmp="$JOBS_DIR/yv_old"
	local awk_strip="$JOBS_DIR/yv_strip.awk" awk_insert="$JOBS_DIR/yv_insert.awk" awk_dedup="$JOBS_DIR/yv_dedup.awk"
	local flag=0
	: > "$saved"
	while IFS= read -r line; do
		[ "$line" = "$selected" ] && flag=1 && continue
		case "$line" in \#Yv[0-9]*) flag=0 ;; esac
		[ "$flag" -eq 1 ] && printf '%s\n' "$line" >> "$saved"
	done < "$f"

	local awk_cut="$JOBS_DIR/yv_cut.awk"
	cat > "$awk_cut" << 'AWK_CUT_EOF'
/^[ \t]*option NFQWS_OPT '$/ { flag = 1 }
flag { print }
AWK_CUT_EOF
	awk -f "$awk_cut" "$CONF" > "$oldtmp"
	rm -f "$awk_cut"
	sed -i "/^[[:space:]]*option NFQWS_OPT '/,\$d" "$CONF"
	sed -i "/^[[:space:]]*#Yv[0-9]\+/d" "$oldtmp"

	cat > "$awk_strip" << 'AWK_STRIP_EOF'
{
	if (skip) {
		if ($0 == "--new" || $0 ~ /^[ \t]*'$/) { skip = 0; next }
		if ($0 ~ /^[ \t]*$/) next
		next
	}
	if ($0 == "--filter-tcp=443") {
		getline n
		if (n == "--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt") { skip = 1; next }
		else { print $0; print n; next }
	}
	if ($0 == "--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt") has_google = 1
	if ($0 ~ /^[ \t]*#Yv/) next
	print
}
AWK_STRIP_EOF
	awk -f "$awk_strip" "$oldtmp" > "$newtmp"

	cat > "$awk_insert" << 'AWK_INSERT_EOF'
BEGIN { inserted = 0; has_google = 0 }
$0 == "--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt" { has_google = 1 }
$0 == "--new" && !inserted {
	while ((getline l < savedfile) > 0) if (l !~ /^[ \t]*$/) print l
	print "--new"
	inserted = 1
	next
}
$0 ~ /^[ \t]*option NFQWS_OPT '$/ && !has_google && !inserted {
	print
	print sel
	while ((getline l < savedfile) > 0) if (l !~ /^[ \t]*$/) print l
	print "--new"
	inserted = 1
	next
}
{ print }
AWK_INSERT_EOF
	awk -v sel="$selected" -v savedfile="$saved" -f "$awk_insert" "$newtmp" > "$finaltmp"

	cat "$finaltmp" >> "$CONF"

	cat > "$awk_dedup" << 'AWK_DEDUP_EOF'
{
	if ($0 == "--new") { if (prev != "--new") print }
	else print
	prev = $0
}
AWK_DEDUP_EOF
	awk -f "$awk_dedup" "$CONF" > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
	grep -qE "^[ \t]*'[ \t]*\$" "$CONF" || echo "'" >> "$CONF"
	_nfq_normalize

	_add_gp_domains
	zapret_restart
	rm -f "$saved" "$newtmp" "$finaltmp" "$oldtmp" "$awk_strip" "$awk_insert" "$awk_dedup"

	printf '{"ok":true,"strategy":"%s","ts_warning":%s}\n' "$(esc "$name")" "$(_ts_warning)"
}

Dv1()  { printf '%s\n' "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" "--dpi-desync=multisplit" "--dpi-desync-split-seqovl=652" "--dpi-desync-split-pos=2" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin"; }
Dv2()  { printf '%s\n' "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" "--dpi-desync=fake,multisplit" "--dpi-desync-split-seqovl=681" "--dpi-desync-split-pos=1" "--dpi-desync-fooling=ts" "--dpi-desync-repeats=8" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin" "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com"; }
Dv3()  { printf '%s\n' "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" "--dpi-desync=fake" "--dpi-desync-repeats=6" "--dpi-desync-fooling=ts" "--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin" "--dpi-desync-fake-tls-mod=none"; }
Dv4()  { printf '%s\n' "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" "--dpi-desync=multisplit" "--dpi-desync-split-seqovl=652" "--dpi-desync-split-pos=2" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin"; }
Dv5()  { printf '%s\n' "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" "--dpi-desync=fake,multisplit" "--dpi-desync-repeats=6" "--dpi-desync-fooling=badseq" "--dpi-desync-badseq-increment=1000" "--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin"; }
Dv6()  { printf '%s\n' "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" "--dpi-desync=multisplit" "--dpi-desync-split-seqovl=681" "--dpi-desync-split-pos=1" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin"; }
Dv7()  { printf '%s\n' "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" "--dpi-desync=multisplit" "--dpi-desync-split-pos=2,sniext+1" "--dpi-desync-split-seqovl=679" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin"; }
Dv8()  { printf '%s\n' "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" "--dpi-desync=fake" "--dpi-desync-fake-tls-mod=none" "--dpi-desync-repeats=6" "--dpi-desync-fooling=badseq" "--dpi-desync-badseq-increment=2"; }
Dv9()  { printf '%s\n' "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" "--dpi-desync=fake,fakedsplit" "--dpi-desync-split-pos=1" "--dpi-desync-fooling=badseq" "--dpi-desync-badseq-increment=2" "--dpi-desync-repeats=8" "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com"; }
Dv10() { printf '%s\n' "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" "--dpi-desync=fake,multisplit" "--dpi-desync-split-seqovl=681" "--dpi-desync-split-pos=1" "--dpi-desync-fooling=badseq" "--dpi-desync-badseq-increment=10000000" "--dpi-desync-repeats=8" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin" "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com"; }
Dv11() { printf '%s\n' "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" "--dpi-desync=fake,multisplit" "--dpi-desync-split-seqovl=681" "--dpi-desync-split-pos=1" "--dpi-desync-fooling=ts" "--dpi-desync-repeats=8" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin" "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com"; }
Dv12() { printf '%s\n' "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" "--dpi-desync=fake" "--dpi-desync-repeats=6" "--dpi-desync-fooling=badseq" "--dpi-desync-badseq-increment=2" "--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin"; }
Dv13() { printf '%s\n' "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" "--dpi-desync=fake" "--dpi-desync-repeats=6" "--dpi-desync-fooling=ts" "--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin"; }
Dv14() { printf '%s\n' "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" "--dpi-desync=fake,fakedsplit" "--dpi-desync-repeats=6" "--dpi-desync-fooling=ts" "--dpi-desync-fakedsplit-pattern=0x00" "--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin"; }
Dv15() { printf '%s\n' "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" "--dpi-desync=fake,multidisorder" "--dpi-desync-split-pos=1,midsld" "--dpi-desync-repeats=11" "--dpi-desync-fooling=badseq" "--dpi-desync-fake-tls=0x00000000" "--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin" "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com"; }
Dv16() { printf '%s\n' "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" "--dpi-desync=fake,hostfakesplit" "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com" "--dpi-desync-hostfakesplit-mod=host=www.google.com,altorder=1" "--dpi-desync-fooling=ts"; }
Dv17() { printf '%s\n' "--filter-tcp=2053,2083,2087,2096,8443" "--hostlist-domains=discord.media" "--dpi-desync=hostfakesplit" "--dpi-desync-repeats=4" "--dpi-desync-fooling=ts" "--dpi-desync-hostfakesplit-mod=host=www.google.com"; }

_discord_active() {
	[ -f "$CONF" ] || return 1
	grep -qx -- '--filter-l7=discord,stun' "$CONF" || grep -qE '^[[:space:]]*--filter-tcp=2053,2083,2087,2096,8443$' "$CONF"
}

discord_status() {
	local dv="" fake="" active=false
	if [ -f "$CONF" ]; then
		dv=$(grep -oE '^#[[:space:]]*Dv[0-9]+' "$CONF" | head -n1 | sed 's/^#[[:space:]]*//')
		fake=$(grep -m1 -- '--dpi-desync-fake-discord=' "$CONF" | sed 's|.*fake/||')
		_discord_active && active=true
	fi
	printf '{"script":"%s","finland":%s,"current":"%s","current_fake":"%s","active":%s,"available":["Dv1","Dv2","Dv3","Dv4","Dv5","Dv6","Dv7","Dv8","Dv9","Dv10","Dv11","Dv12","Dv13","Dv14","Dv15","Dv16","Dv17"]}\n' "$(_zo_script)" "$(_hosts_block_status finland)" "$(esc "$dv")" "$(esc "$fake")" "$active"
}

discord_off() {
	[ -f "$CONF" ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	_nfq_drop_profiles "$DISCORD_RX"
	case $? in
		0)
			sed -i -e "/^[[:space:]]*option NFQWS_PORTS_UDP '/s/,19294-19344,50000-50100//" \
				-e "/^[[:space:]]*option NFQWS_PORTS_TCP '/s/,2053,2083,2087,2096,8443//" "$CONF"
			mkdir -p "$(dirname "$DV_OFF_FLAG")"; touch "$DV_OFF_FLAG"
			zapret_restart
			printf '{"ok":true,"dv":"off","removed":true}\n' ;;
		3)
			mkdir -p "$(dirname "$DV_OFF_FLAG")"; touch "$DV_OFF_FLAG"
			printf '{"ok":true,"dv":"off","removed":false}\n' ;;
		*) echo '{"error":"блок стратегий Zapret (NFQWS_OPT) записан не так, как его пишет панель, — Discord-часть не тронута"}'; return 1 ;;
	esac
}

discord_set_dv() {
	local num="$1" strat
	[ "$num" = off ] && { discord_off; return; }
	_zm_re "$num" '^(1[0-7]|[1-9])$' || { echo '{"error":"некорректный номер Dv"}'; return 1; }
	[ -f "$CONF" ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	strat="$(Dv"$num")"
	if ! grep -qx -- '--filter-l7=discord,stun' "$CONF" || ! grep -q -E '^[[:space:]]*--filter-tcp=2053,2083,2087,2096,8443' "$CONF"; then
		_nfq_drop_profiles "$DISCORD_RX"
		case $? in 0|3) ;; *) echo '{"error":"блок стратегий Zapret (NFQWS_OPT) записан не так, как его пишет панель, — Discord-часть не добавлена"}'; return 1 ;; esac
		rm -f "$DV_OFF_FLAG"
		_discord_str_add
		grep -q -E '^[[:space:]]*--filter-tcp=2053,2083,2087,2096,8443' "$CONF" || {
			echo '{"error":"не удалось добавить блок Discord — сначала выберите основную стратегию"}'; return 1; }
	fi
	rm -f "$DV_OFF_FLAG"
	local start end line
	start=$(grep -n -E '^[[:space:]]*--filter-tcp=2053,2083,2087,2096,8443' "$CONF" | head -n1 | cut -d: -f1)
	end=$(tail -n +"$start" "$CONF" | grep -n -m1 -E '^--new$|^#|^'"'"'$' | cut -d: -f1)
	end=$((start + end - 1))
	sed -i "${start},$((end - 1))d" "$CONF"
	line=$start
	echo "$strat" | while IFS= read -r l; do sed -i "${line}i$l" "$CONF"; line=$((line + 1)); done
	if grep -q -E '^#[[:space:]]*Dv' "$CONF"; then
		sed -i "s/^#[[:space:]]*Dv[0-9]\+/#Dv$num/" "$CONF"
	else
		sed -i "${start}i#Dv$num" "$CONF"
	fi
	zapret_restart
	printf '{"ok":true,"dv":"Dv%s"}\n' "$num"
}

discord_set_fake() {
	local file="$1"
	case "$file" in
		stun.bin|stun2.bin|quic_initial_4pda_to.bin|quic_initial_tencent_com.bin|tls_clienthello_sochi_park.bin|quic_initial_www_google_com.bin|quic_initial_steamcommunity_com.bin|quic_initial_5ka_ru.bin|quic_initial_rutube_ru.bin) ;;
		*) echo '{"error":"неизвестный fake-файл"}'; return 1 ;;
	esac
	[ -f "$CONF" ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	grep -q -- "--filter-l7=discord,stun" "$CONF" || { echo '{"error":"стратегия Discord выключена — сначала выберите Dv"}'; return 1; }
	awk -v new="$file" '{
		if ($0 == "--filter-l7=discord,stun") { print; getline; print;
			if ($0 == "--dpi-desync=fake") { getline a; getline b;
				if (a ~ /^--dpi-desync-fake-discord=/) {
					print "--dpi-desync-fake-discord=/opt/zapret/files/fake/" new
					print "--dpi-desync-fake-stun=/opt/zapret/files/fake/" new
				} else { print a; print b }
			}
			next
		}
		print
	}' "$CONF" > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
	zapret_restart
	printf '{"ok":true,"fake":"%s"}\n' "$(esc "$file")"
}

_hosts_block() {
	case "$1" in
		nalog) printf '%s\n' \
			"#Nalog" \
			"213.24.64.175 lkfl2.nalog.ru" \
			"213.24.64.181 lknpd.nalog.ru" ;;
		ntc) printf '%s\n' \
			"#ntc.party" \
			"130.255.77.28 ntc.party" ;;
		instagram) printf '%s\n' \
			"#Instagram&Facebook" \
			"57.144.222.34 instagram.com www.instagram.com" \
			"157.240.9.174 instagram.com www.instagram.com" \
			"157.240.245.174 instagram.com www.instagram.com b.i.instagram.com z-p42-chat-e2ee-ig.facebook.com help.instagram.com" \
			"157.240.205.174 instagram.com www.instagram.com" \
			"57.144.244.192 static.cdninstagram.com graph.instagram.com i.instagram.com api.instagram.com edge-chat.instagram.com" \
			"31.13.66.63 scontent.cdninstagram.com scontent-hel3-1.cdninstagram.com" \
			"57.144.244.1 facebook.com www.facebook.com fb.com fbsbx.com" \
			"57.144.244.128 static.xx.fbcdn.net scontent.xx.fbcdn.net" \
			"31.13.67.20 scontent-hel3-1.xx.fbcdn.net" ;;
		librusec) printf '%s\n' \
			"#lib.rus.ec" \
			"185.39.18.98 lib.rus.ec www.lib.rus.ec" ;;
		ai_openai) printf '%s\n' \
			"#OpenAI" \
			"45.155.204.190 chatgpt.com ab.chatgpt.com auth.openai.com auth0.openai.com platform.openai.com cdn.oaistatic.com" \
			"45.155.204.190 tcr9i.chat.openai.com webrtc.chatgpt.com android.chat.openai.com api.openai.com operator.chatgpt.com" \
			"45.155.204.190 sora.chatgpt.com sora.com videos.openai.com ios.chat.openai.com cdn.auth0.com files.oaiusercontent.com" ;;
		ai_claude) printf '%s\n' \
			"#Claude" \
			"45.155.204.190 claude.ai console.anthropic.com api.anthropic.com" ;;
		ai_gemini) printf '%s\n' \
			"#Gemini" \
			"45.155.204.190 gemini.google.com" ;;
		ai_aistudio) printf '%s\n' \
			"#AIStudio" \
			"45.155.204.190 aistudio.google.com generativelanguage.googleapis.com aitestkitchen.withgoogle.com aisandbox-pa.googleapis.com" \
			"45.155.204.190 webchannel-alkalimakersuite-pa.clients6.google.com alkalimakersuite-pa.clients6.google.com assistant-s3-pa.googleapis.com" \
			"45.155.204.190 proactivebackend-pa.googleapis.com robinfrontend-pa.googleapis.com o.pki.goog labs.google labs.google.com notebooklm.google" \
			"45.155.204.190 notebooklm.google.com jules.google.com stitch.withgoogle.com" ;;
		ai_grok) printf '%s\n' \
			"#Grok" \
			"45.155.204.190 grok.com accounts.x.ai assets.grok.com" ;;
		ai_copilot) printf '%s\n' \
			"#Microsoft" \
			"45.155.204.190 copilot.microsoft.com sydney.bing.com edgeservices.bing.com rewards.bing.com" \
			"45.155.204.190 xsts.auth.xboxlive.com xgpuwebf2p.gssv-play-prod.xboxlive.com xgpuweb.gssv-play-prod.xboxlive.com" \
			"45.155.204.190 xboxdesignlab.xbox.com" ;;
		ai_deepl) printf '%s\n' \
			"#DeepL" \
			"45.155.204.190 deepl.com www.deepl.com www2.deepl.com login-wall.deepl.com w.deepl.com dict.deepl.com ita-free.www.deepl.com" \
			"45.155.204.190 write-free.www.deepl.com experimentation.deepl.com experimentation-grpc.deepl.com ita-free.app.deepl.com" \
			"45.155.204.190 ott.deepl.com api-free.deepl.com backend.deepl.com clearance.deepl.com errortracking.deepl.com" \
			"45.155.204.190 oneshot-free.www.deepl.com checkout.www.deepl.com gtm.deepl.com auth.deepl.com shield.deepl.com" ;;
		ai_elevenlabs) printf '%s\n' \
			"#ElevenLabs" \
			"45.155.204.190 elevenlabs.io api.us.elevenlabs.io elevenreader.io api.elevenlabs.io help.elevenlabs.io" ;;
		ai_windsurf) printf '%s\n' \
			"#Windsurf" \
			"45.155.204.190 windsurf.com codeium.com server.codeium.com web-backend.codeium.com marketplace.windsurf.com" \
			"45.155.204.190 unleash.codeium.com inference.codeium.com windsurf-stable.codeium.com" \
			"144.31.14.104 windsurf-telemetry.codeium.com" ;;
		ai_trae) printf '%s\n' \
			"#Trae.ai" \
			"45.155.204.190 trae-api-sg.mchost.guru api.trae.ai api-sg-central.trae.ai api16-normal-alisg.mchost.guru" ;;
		ai_manus) printf '%s\n' \
			"#Manus" \
			"45.155.204.190 manus.im api.manus.im" ;;
		ai_notion) printf '%s\n' \
			"#Notion" \
			"45.155.204.190 www.notion.so calendar.notion.so" ;;
		twitch) printf '%s\n' \
			"#Twitch" \
			"45.155.204.190 usher.ttvnw.net gql.twitch.tv" ;;
		telegram) printf '%s\n' \
			"#TelegramWeb" \
			"149.154.167.220 core.telegram.org api.telegram.org flora.web.telegram.org kws1-1.web.telegram.org kws1.web.telegram.org kws2-1.web.telegram.org kws2.web.telegram.org kws4-1.web.telegram.org" \
			"149.154.167.220 kws4.web.telegram.org kws5-1.web.telegram.org kws5.web.telegram.org pluto-1.web.telegram.org pluto.web.telegram.org td.telegram.org telegram.dog" \
			"149.154.167.220 telegram.me telegram.org telegram.space telesco.pe venus.web.telegram.org web.telegram.org zws1-1.web.telegram.org zws1.web.telegram.org" \
			"149.154.167.220 tg.dev t.me zws2-1.web.telegram.org zws2.web.telegram.org zws4-1.web.telegram.org zws5-1.web.telegram.org zws5.web.telegram.org" ;;
		spotify) printf '%s\n' \
			"#Spotify" \
			"45.155.204.190 api.spotify.com login5.spotify.com encore.scdn.co gew1-spclient.spotify.com spclient.wg.spotify.com" \
			"45.155.204.190 api-partner.spotify.com aet.spotify.com www.spotify.com accounts.spotify.com open.spotify.com" \
			"45.155.204.190 accounts.scdn.co gew1-dealer.spotify.com open-exp.spotifycdn.com www-growth.scdn.co" ;;
		rutor) printf '%s\n' \
			"#rutor" \
			"172.66.159.63 rutor.info d.rutor.info" ;;
		scell) printf '%s\n' \
			"#Supercell" \
			"103.27.157.38 accounts.supercell.com cdn.id.supercell.com clashofclans.inbox.supercell.com game-assets.brawlstarsgame.com" \
			"103.27.157.38 game-assets.clashofclans.com game-assets.clashroyaleapp.com security.id.supercell.com store.supercell.com" \
			"31.25.239.132 accounts.supercell.com cdn.id.supercell.com clashofclans.inbox.supercell.com game-assets.brawlstarsgame.com" \
			"31.25.239.132 game-assets.clashofclans.com game-assets.clashroyaleapp.com game.boombeachgame.com game.mocogame.com security.id.supercell.com store.supercell.com" \
			"185.246.223.127 game.brawlstarsgame.com" \
			"62.133.62.97 game.clashroyaleapp.com" \
			"193.23.209.189 gamea.clashofclans.com" \
			"108.61.167.26 game.squadbustersgame.com" ;;
		githubraw) printf '%s\n' \
			"#githubusercontent.com" \
			"146.75.22.132 objects.githubusercontent.com release-assets.githubusercontent.com raw.githubusercontent.com private-user-images.githubusercontent.com gist.githubusercontent.com" \
			"146.75.22.132 camo.githubusercontent.com avatars.githubusercontent.com avatars0.githubusercontent.com avatars1.githubusercontent.com avatars2.githubusercontent.com avatars3.githubusercontent.com avatars4.githubusercontent.com avatars5.githubusercontent.com" ;;
		github) printf '%s\n' \
			"#github.com" \
			"140.82.114.3 github.com" \
			"185.199.110.154 github.githubassets.com" \
			"185.199.110.133 camo.githubassets.com" ;;
		spotifyext) printf '%s\n' \
			"#SpotifyEXT" \
			"45.155.204.190 spotify.com www.spotify.com accounts.spotify.com login.spotify.com login5.spotify.com login.app.spotify.com auth.spotify.com account.spotify.com api.spotify.com api-partner.spotify.com spclient.wg.spotify.com gew1-spclient.spotify.com" \
			"45.155.204.190 guc3-spclient.spotify.com gae2-spclient.spotify.com gue1-spclient.spotify.com gnl-spclient.spotify.com spclient.spotify.com ap-gew1.spotify.com ap-gue1.spotify.com ap-gae2.spotify.com ap-gew4.spotify.com ap-sto3.spotify.com" \
			"45.155.204.190 ap-guc3.spotify.com ap.spotify.com apresolve.spotify.com aet.spotify.com gew1-dealer.g2.spotify.com guc3-dealer.g2.spotify.com gue1-dealer.g2.spotify.com dealer.spotify.com dealer-wg.spotify.com edge-web.dual-gslb.spotify.com" \
			"45.155.204.190 client.spotify.com web-partner.spotify.com connect.spotify.com gce.spotify.com clienttoken.spotify.com exp.wg.spotify.com pixel.spotify.com pixel-static.spotify.com image-upload.spotify.com content.spotify.com analytics.spotify.com" \
			"45.155.204.190 crashdump.spotify.com log.spotify.com logger.spotify.com metrics.spotify.com desktop.spotify.com audio-fa-tls13.spotifycdn.com heads-fa-tls13.spotifycdn.com heads4-fa-tls13.spotifycdn.com image-cdn-fa.spotifycdn.com" \
			"45.155.204.190 concerts.spotifycdn.com mrkt.spotifycdn.com pickasso.spotifycdn.com podz-content.spotifycdn.com seed-mix-image.spotifycdn.com thisis-images.spotifycdn.com wap.spotifycdn.com web-sdk-assets.spotifycdn.com spotifycdn.com spotifycdn.net" \
			"35.186.224.24 open.spotify.com" \
			"162.159.141.124 audio4-fa-tls13.spotifycdn.com audio-cf.spotifycdn.com open-exp.spotifycdn.com" \
			"23.36.163.34 audio-ak-spotify-com.akamaized.net" \
			"2.16.168.44 audio4-ak-spotify-com.akamaized.net" \
			"199.232.210.248 scdn.co i.scdn.co line-up.scdn.co mosaic.scdn.co daily-mix.scdn.co lineup-images.scdn.co encore.scdn.co image-cdn-fa.scdn.co accounts.scdn.co www.scdn.co www-growth.scdn.co av.scdn.co seafoam.scdn.co" \
			"23.48.23.145 heads-ak-spotify-com.akamaized.net" \
			"45.155.204.190 xpui.app.spotify.com" ;;
		roblox) printf '%s\n' \
			"#tr.rbxcdn.com" \
			"108.156.22.8 tr.rbxcdn.com" \
			"108.157.32.114 tr.rbxcdn.com" \
			"18.65.147.108 tr.rbxcdn.com" \
			"18.65.147.112 tr.rbxcdn.com" \
			"13.224.181.18 tr.rbxcdn.com" \
			"13.224.181.74 tr.rbxcdn.com" \
			"54.230.253.22 tr.rbxcdn.com" \
			"54.230.253.81 tr.rbxcdn.com" \
			"54.230.253.48 tr.rbxcdn.com" \
			"54.230.253.59 tr.rbxcdn.com" \
			"143.204.214.34 tr.rbxcdn.com" \
			"143.204.214.67 tr.rbxcdn.com" \
			"143.204.214.92 tr.rbxcdn.com" \
			"99.84.181.25 tr.rbxcdn.com" \
			"99.84.181.63 tr.rbxcdn.com" \
			"65.8.158.45 tr.rbxcdn.com" \
			"65.8.158.112 tr.rbxcdn.com" ;;
		rutracker) printf '%s\n' \
			"#Rutracker" \
			"172.67.182.196 rutracker.org" ;;
		tapeop) printf '%s\n' \
			"#tapeop.dev" \
			"216.24.57.251 www.tapeop.dev tapeop.dev" \
			"216.24.57.3 www.tapeop.dev tapeop.dev" ;;
		finland) echo "#Discord Finland"; awk 'BEGIN { for (i = 10000; i <= 10199; i++) print "104.25.158.178 finland" i ".discord.media" }' ;;
		*) return 1 ;;
	esac
}

_hosts_block_status() {
	local block="$1" content
	content="$(_hosts_block "$block")" || return 1
	[ -f "$HOSTS_FILE" ] || { echo false; return; }
	printf '%s\n' "$content" | awk -v hf="$HOSTS_FILE" 'function n(s) { gsub(/\r/, "", s); gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
		BEGIN { while ((getline l < hf) > 0) have[n(l)] = 1; close(hf) }
		{ k = n($0); if (k == "" || (k in seen)) next; seen[k] = 1; total++; if (k in have) found++ }
		END { print (total > 0 && found == total) ? "true" : "false" }'
}
_hosts_drop_lines() {
	local tmp="$HOSTS_FILE.zmtmp" list="$HOSTS_FILE.zmdrop"
	cat > "$list"
	awk -v list="$list" 'function n(s) { gsub(/\r/, "", s); gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
		BEGIN { while ((getline l < list) > 0) { k = n(l); if (k != "") drop[k] = 1 } close(list) }
		!(n($0) in drop)' "$HOSTS_FILE" > "$tmp" && cat "$tmp" > "$HOSTS_FILE"
	rm -f "$tmp" "$list"
}

_hosts_add_lines() {
	local list="$HOSTS_FILE.zmadd" add="$HOSTS_FILE.zmnew"
	cat > "$list"
	[ -f "$HOSTS_FILE" ] || : > "$HOSTS_FILE"
	awk -v hf="$HOSTS_FILE" 'function n(s) { gsub(/\r/, "", s); gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
		BEGIN { while ((getline l < hf) > 0) have[n(l)] = 1; close(hf) }
		{ k = n($0); if (k == "" || (k in have)) next; have[k] = 1; print }' "$list" > "$add"
	if [ -s "$add" ]; then
		[ -s "$HOSTS_FILE" ] && [ -n "$(tail -c 1 "$HOSTS_FILE" 2>/dev/null)" ] && echo >> "$HOSTS_FILE"
		cat "$add" >> "$HOSTS_FILE"
	fi
	rm -f "$list" "$add"
}

HOSTS_BLOCKS="nalog ntc instagram librusec ai_openai ai_claude ai_gemini ai_aistudio ai_grok ai_copilot ai_deepl ai_elevenlabs ai_windsurf ai_trae ai_manus ai_notion twitch telegram spotify spotifyext rutor rutracker scell roblox githubraw github tapeop finland"
hosts_status() {
	local blocks="$HOSTS_BLOCKS" b
	local geohide=""
	if grep -q '^### dns.malw.link: hosts file' "$HOSTS_FILE" 2>/dev/null; then geohide="malw"
	elif grep -q '^### geohide.ru: hosts file' "$HOSTS_FILE" 2>/dev/null; then
		if grep -q '^# Регион серверов: US$' "$HOSTS_FILE" 2>/dev/null; then geohide="us"
		elif grep -q '^# Регион серверов: EU$' "$HOSTS_FILE" 2>/dev/null; then geohide="eu"
		elif grep -q '^# Регион серверов: RU$' "$HOSTS_FILE" 2>/dev/null; then geohide="ru"
		else geohide="unknown"; fi
	fi
	printf '{"geohide":"%s","items":[' "$(esc "$geohide")"
	for b in $blocks; do echo "@@ZMB $b"; _hosts_block "$b"; done | awk -v hf="$HOSTS_FILE" 'function n(s) { gsub(/\r/, "", s); gsub(/[ \t]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
		function flush() { if (id == "") return; printf "%s{\"id\":\"%s\",\"enabled\":%s}", (cnt++ ? "," : ""), id, (total > 0 && found == total) ? "true" : "false" }
		BEGIN { while ((getline l < hf) > 0) have[n(l)] = 1; close(hf) }
		/^@@ZMB / { flush(); id = substr($0, 7); total = 0; found = 0; split("", seen); next }
		{ k = n($0); if (k == "" || (k in seen)) next; seen[k] = 1; total++; if (k in have) found++ }
		END { flush() }'
	printf '],"extra":%s}\n' "$(_hosts_extra)"
}

hosts_toggle() {
	local block="$1" content line enabled
	content="$(_hosts_block "$block")" || { echo '{"error":"неизвестный блок"}'; return 1; }
	enabled="$(_hosts_block_status "$block")"
	if [ "$enabled" = "true" ]; then
		printf '%s\n' "$content" | _hosts_drop_lines
	else
		printf '%s\n' "$content" | _hosts_add_lines
	fi
	/etc/init.d/dnsmasq restart >/dev/null 2>&1
	printf '{"ok":true,"block":"%s","enabled":%s}\n' "$(esc "$block")" "$([ "$enabled" = "true" ] && echo false || echo true)"
}

hosts_replace_geohide() {
	local region="$1" url tmp
	case "$region" in
		ru) url="${GH_RAW}/Internet-Helper/GeoHideDNS/refs/heads/main/hosts/hosts" ;;
		eu) url="${GH_RAW}/Internet-Helper/GeoHideDNS/refs/heads/main/hosts/eu/hosts" ;;
		us) url="${GH_RAW}/Internet-Helper/GeoHideDNS/refs/heads/main/hosts/us/hosts" ;;
		malw) url="${GH_RAW}/ImMALWARE/dns.malw.link/refs/heads/master/hosts" ;;
		*) echo '{"error":"неизвестный регион"}'; return 1 ;;
	esac
	tmp="$JOBS_DIR/geohide_hosts.tmp"
	_zm_fetch "$url" "$tmp" 60
	if [ ! -s "$tmp" ]; then
		rm -f "$tmp"
		printf '{"error":"%s"}\n' "$([ "$region" = malw ] && echo "не удалось скачать hosts dns.malw.link" || echo "не удалось скачать GeoHide hosts")"
		return 1
	fi
	if [ "$(grep -cE '^[[:space:]]*[0-9a-fA-F.:]+[[:space:]]+[A-Za-z0-9]' "$tmp")" -lt 20 ]; then
		rm -f "$tmp"
		echo '{"error":"скачался не файл hosts — попробуйте ещё раз позже"}'
		return 1
	fi
	if ! mv "$tmp" "$HOSTS_FILE" 2>/dev/null; then
		rm -f "$tmp"
		echo '{"error":"не удалось записать /etc/hosts — проверьте свободное место на роутере"}'
		return 1
	fi
	/etc/init.d/dnsmasq restart >/dev/null 2>&1
	printf '{"ok":true,"region":"%s"}\n' "$region"
}

hosts_reset() {
	printf '%s\n' "127.0.0.1	localhost" "" "::1	localhost ip6-localhost ip6-loopback" "ff02::1 ip6-allnodes" "ff02::2 ip6-allrouters" > "$HOSTS_FILE"
	/etc/init.d/dnsmasq restart >/dev/null 2>&1
	printf '{"ok":true}\n'
}

HOSTS_EDIT_MAX=262144

hosts_file_get() {
	local sz n
	[ -f "$HOSTS_FILE" ] || { echo '{"error":"файл hosts не найден"}'; return 1; }
	sz="$(wc -c < "$HOSTS_FILE" | tr -d ' ')"
	if [ "${sz:-0}" -gt "$HOSTS_EDIT_MAX" ]; then
		n="$(wc -l < "$HOSTS_FILE" | tr -d ' ')"
		printf '{"too_big":true,"size":%s,"lines":%s}\n' "$sz" "${n:-0}"
		return 0
	fi
	printf '{"content":"%s"}\n' "$(esc_ml "$(cat "$HOSTS_FILE")")"
}

hosts_file_set() {
	local content="$1"
	[ -n "$content" ] || { echo '{"error":"пустой файл — сохранение отменено"}'; return 1; }
	[ "$(printf '%s' "$content" | wc -c)" -gt "$HOSTS_EDIT_MAX" ] && { echo '{"error":"файл слишком большой для редактора"}'; return 1; }
	cp "$HOSTS_FILE" "$HOSTS_FILE.zm-bak" 2>/dev/null
	printf '%s' "$content" > "$HOSTS_FILE"
	[ -n "$(tail -c 1 "$HOSTS_FILE" 2>/dev/null)" ] && echo >> "$HOSTS_FILE"
	/etc/init.d/dnsmasq restart >/dev/null 2>&1
	printf '{"ok":true}\n'
}

ZM_UP_FILE="$JOBS_DIR/upload.part"
ZM_UP_MAX=4194304
upload_part() {
	local part="$1" sz
	mkdir -p "$JOBS_DIR"
	case "$part" in
		first) : > "$ZM_UP_FILE" ;;
		next) [ -f "$ZM_UP_FILE" ] || { echo '{"error":"загрузка прервалась — сохраните ещё раз"}'; return 1; } ;;
		*) echo '{"error":"неверная часть файла"}'; return 1 ;;
	esac
	printf '%s' "$2" >> "$ZM_UP_FILE"
	sz="$(wc -c < "$ZM_UP_FILE" | tr -d ' ')"
	[ "${sz:-0}" -gt "$ZM_UP_MAX" ] && { rm -f "$ZM_UP_FILE"; echo '{"error":"текст слишком большой"}'; return 1; }
	printf '{"ok":true,"size":%s}\n' "${sz:-0}"
}

_ports_get() { sed -n "s/^[[:space:]]*option $1 '\([^']*\)'.*/\1/p" "$CONF" | head -n1; }
_ports_put() { sed -i "s|^\([[:space:]]*option $1 '\)[^']*'|\1$2'|" "$CONF"; }
_remove_ports_if_present() {
	local option="$1" ports="$2" cur out="" p
	grep -q "^[[:space:]]*option $option '" "$CONF" || return 0
	cur="$(_ports_get "$option")"
	for p in $(echo "$cur" | tr ',' ' '); do
		case ",$ports," in *",$p,"*) continue ;; esac
		out="$out${out:+,}$p"
	done
	[ "$out" = "$cur" ] || _ports_put "$option" "$out"
}

_add_ports_if_missing() {
	local option="$1" ports="$2" cur p
	grep -q "^[[:space:]]*option $option '" "$CONF" || return 0
	cur="$(_ports_get "$option")"
	for p in $(echo "$ports" | tr ',' ' '); do
		case ",$cur," in *",$p,"*) ;; *) cur="$cur${cur:+,}$p" ;; esac
	done
	_ports_put "$option" "$cur"
}

strategy_TCP_common() {
	printf '%s\n' "--new" "--filter-tcp=$PORTS_TCP" "--dpi-desync-any-protocol=1" "--dpi-desync-cutoff=n5" \
		"--dpi-desync=multisplit" "--dpi-desync-split-seqovl=582" "--dpi-desync-split-pos=1" \
		"--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/stun.bin"
}

strategy_Gv1() {
	printf '%s\n' "#Gv1" "--new" "--filter-udp=$PORTS_UDP" "--dpi-desync=fake" "--dpi-desync-cutoff=d2" \
		"--dpi-desync-any-protocol=1" "--dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/stun.bin"
}

strategy_Gv() {
	local n="$1"
	printf '%s\n' "#Gv$n" "--new" "--filter-udp=$PORTS_UDP" "--dpi-desync=fake" "--dpi-desync-repeats=10" \
		"--dpi-desync-any-protocol=1" "--dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/stun.bin" "--dpi-desync-cutoff=n$n"
}

_game_rx() {
	printf '%s' "^#Gv[0-9]+(Xtreme)?\$|^--filter-(udp|tcp)=($PORTS_UDP|$PORTS_TCP|80,88,444-65535)\$"
}

_game_active() {
	[ -f "$CONF" ] || return 1
	sed -n "/^[[:space:]]*option NFQWS_OPT '\$/,\$p" "$CONF" | grep -qE "$(_game_rx)"
}

_game_xtreme_undo_opts() {
	local xfile="/opt/zapret/tmp/GvXtreme" old_tcp_opt old_udp_opt
	grep -q "^#Gv[0-9]\+Xtreme\$" "$CONF" || { rm -f "$xfile"; return 0; }
	if [ -f "$xfile" ]; then
		old_tcp_opt=$(sed -n '4p' "$xfile")
		old_udp_opt=$(sed -n '5p' "$xfile")
		[ -n "$old_tcp_opt" ] && sed -i "s|^[[:space:]]*option NFQWS_PORTS_TCP .*|$old_tcp_opt|" "$CONF"
		[ -n "$old_udp_opt" ] && sed -i "s|^[[:space:]]*option NFQWS_PORTS_UDP .*|$old_udp_opt|" "$CONF"
	fi
	rm -f "$xfile"
}

game_status() {
	local current="" xtreme="false" fake="" active="false"
	if [ -f "$CONF" ]; then
		current=$(grep -oE '^#Gv[1-4](Xtreme)?$' "$CONF" | head -n1 | sed 's/^#//; s/Xtreme$//')
		grep -q "^#Gv[0-9]\+Xtreme\$" "$CONF" && xtreme="true"
		fake=$(grep -m1 -- '--dpi-desync-fake-unknown-udp=' "$CONF" | sed 's|.*fake/||')
		_game_active && active="true"
	fi
	printf '{"current":"%s","xtreme":%s,"fake":"%s","active":%s}\n' "$(esc "$current")" "$xtreme" "$(esc "$fake")" "$active"
}

game_set() {
	local choice="$1" current="" rc
	_zm_re "$choice" '^([1-4]|off)$' || { echo '{"error":"некорректный номер Gv"}'; return 1; }
	[ -f "$CONF" ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	current=$(grep -oE '^#Gv[1-4](Xtreme)?$' "$CONF" | head -n1 | sed 's/^#//; s/Xtreme$//')

	if [ "$choice" = off ]; then
		_game_active || { printf '{"ok":true,"game":"none","removed":false}\n'; return 0; }
		cp "$CONF" "$CONF.gvbak"
		_game_xtreme_undo_opts
		_nfq_drop_profiles "$(_game_rx)"
		rc=$?
		case $rc in
			0|3)
				rm -f "$CONF.gvbak"
				_remove_ports_if_present NFQWS_PORTS_UDP "$PORTS_UDP"
				_remove_ports_if_present NFQWS_PORTS_TCP "$PORTS_TCP"
				zapret_restart
				printf '{"ok":true,"game":"none","removed":true}\n' ;;
			*)
				mv -f "$CONF.gvbak" "$CONF"
				echo '{"error":"блок стратегий Zapret (NFQWS_OPT) записан не так, как его пишет панель, — игровая часть не тронута"}'; return 1 ;;
		esac
		return 0
	fi

	[ "$current" = "Gv$choice" ] && { printf '{"ok":true,"game":"Gv%s"}\n' "$choice"; return 0; }

	cp "$CONF" "$CONF.gvbak"
	_game_xtreme_undo_opts
	_nfq_drop_profiles "$(_game_rx)"
	case $? in
		0|3) rm -f "$CONF.gvbak" ;;
		*) mv -f "$CONF.gvbak" "$CONF"
			echo '{"error":"блок стратегий Zapret (NFQWS_OPT) записан не так, как его пишет панель, — игровая часть не тронута"}'; return 1 ;;
	esac

	local last_quote strat
	last_quote=$(grep -n "^[[:space:]]*'[[:space:]]*\$" "$CONF" | tail -n1 | cut -d: -f1)
	[ -n "$last_quote" ] && sed -i "${last_quote},\$d" "$CONF"
	if [ "$choice" = "1" ]; then strat="$(strategy_Gv1; strategy_TCP_common)"; else strat="$(strategy_Gv "$choice"; strategy_TCP_common)"; fi
	echo "$strat" | sed '/^$/d' >> "$CONF"
	echo "'" >> "$CONF"
	_add_ports_if_missing NFQWS_PORTS_UDP "$PORTS_UDP"
	_add_ports_if_missing NFQWS_PORTS_TCP "$PORTS_TCP"
	zapret_restart
	printf '{"ok":true,"game":"Gv%s"}\n' "$choice"
}

game_set_fake() {
	local file="$1"
	case "$file" in
		stun.bin|stun2.bin|quic_initial_4pda_to.bin|quic_initial_tencent_com.bin|tls_clienthello_sochi_park.bin|quic_initial_www_google_com.bin|quic_initial_steamcommunity_com.bin|quic_initial_5ka_ru.bin|quic_initial_rutube_ru.bin) ;;
		*) echo '{"error":"неизвестный fake-файл"}'; return 1 ;;
	esac
	[ -f "$CONF" ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	grep -q -- '--dpi-desync-fake-unknown-udp=' "$CONF" || { echo '{"error":"игровая стратегия не установлена"}'; return 1; }
	awk -v new="$file" 'BEGIN{done=0} !done && /--dpi-desync-fake-unknown-udp=/{sub(/\/opt\/zapret\/files\/fake\/[^ ]+/, "/opt/zapret/files/fake/" new); done=1} {print}' "$CONF" > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
	zapret_restart
	printf '{"ok":true,"fake":"%s"}\n' "$(esc "$file")"
}

game_toggle_xtreme() {
	[ -f "$CONF" ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	local xfile="/opt/zapret/tmp/GvXtreme"
	local xports="80,88,444-65535"
	local xnfqws="80,88,443-65535"
	mkdir -p "$(dirname "$xfile")"

	if grep -q "^#Gv[0-9]\+Xtreme\$" "$CONF"; then
		[ -f "$xfile" ] || { echo '{"error":"файл восстановления отсутствует"}'; return 1; }
		local old_gv old_udp old_tcp old_tcp_opt old_udp_opt
		old_gv=$(sed -n '1p' "$xfile")
		old_udp=$(sed -n '2p' "$xfile")
		old_tcp=$(sed -n '3p' "$xfile")
		old_tcp_opt=$(sed -n '4p' "$xfile")
		old_udp_opt=$(sed -n '5p' "$xfile")
		awk -v gv="$old_gv" -v udp="$old_udp" -v tcp="$old_tcp" '
			/^#Gv[0-9]+Xtreme$/ { print gv; restore = 1; next }
			restore && /^--filter-udp=/ { print udp; next }
			restore && /^--filter-tcp=/ { print tcp; restore = 0; next }
			{ print }
		' "$CONF" > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
		[ -n "$old_tcp_opt" ] && sed -i "s|^[[:space:]]*option NFQWS_PORTS_TCP .*|$old_tcp_opt|" "$CONF"
		[ -n "$old_udp_opt" ] && sed -i "s|^[[:space:]]*option NFQWS_PORTS_UDP .*|$old_udp_opt|" "$CONF"
		rm -f "$xfile"
		zapret_restart
		printf '{"ok":true,"xtreme":false}\n'
		return
	fi

	grep -q "^#Gv[0-9]\+\$" "$CONF" || { echo '{"error":"игровая стратегия не установлена"}'; return 1; }
	awk '
		/^#Gv[0-9]+$/ { gv = $0; found = 1; next }
		found && /^--filter-udp=/ { udp = $0 }
		found && /^--filter-tcp=/ { tcp = $0 }
		/^[ \t]*option NFQWS_PORTS_TCP / { tcp_option = $0 }
		/^[ \t]*option NFQWS_PORTS_UDP / { udp_option = $0 }
		END { print gv; print udp; print tcp; print tcp_option; print udp_option }
	' "$CONF" > "$xfile"
	sed -i -e "s|^[[:space:]]*option NFQWS_PORTS_TCP .*|	option NFQWS_PORTS_TCP '$xnfqws'|" \
		-e "s|^[[:space:]]*option NFQWS_PORTS_UDP .*|	option NFQWS_PORTS_UDP '$xnfqws'|" "$CONF"
	sed -i "s/^#\(Gv[0-9]\+\)\$/#\1Xtreme/" "$CONF"
	awk -v ports="$xports" '
		/^#Gv[0-9]+Xtreme$/ { gv = 1; print; next }
		gv && /^--filter-udp=/ { print "--filter-udp=" ports; next }
		gv && /^--filter-tcp=/ { print "--filter-tcp=" ports; gv = 0; next }
		{ print }
	' "$CONF" > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
	zapret_restart
	printf '{"ok":true,"xtreme":true}\n'
}

_quic_blocked() {
	uci show firewall 2>/dev/null | grep -q "name='Block_UDP_80'" \
		&& uci show firewall 2>/dev/null | grep -q "name='Block_UDP_443'" \
		&& echo true || echo false
}

ZM_V6_OPT_RX="^[[:space:]]*option[[:space:]]+DISABLE_IPV6[[:space:]]+['\"]?"
_ipv6_enabled_in_zapret() {
	[ -f "$CONF" ] && grep -Eq "${ZM_V6_OPT_RX}0['\"]?[[:space:]]*\$" "$CONF" && echo true || echo false
}
_zapret_v6_set() {
	if grep -Eq "${ZM_V6_OPT_RX}[^[:space:]]*[[:space:]]*\$" "$CONF"; then
		sed -i -E "s/${ZM_V6_OPT_RX}[^[:space:]]*[[:space:]]*\$/\toption DISABLE_IPV6 '$1'/" "$CONF"
	else
		sed -i "/^[[:space:]]*config[[:space:]]\{1,\}main[[:space:]]\{1,\}'\{0,1\}config'\{0,1\}[[:space:]]*\$/a\\	option DISABLE_IPV6 '$1'" "$CONF"
	fi
}

FW4_TPL="/usr/share/firewall4/templates/ruleset.uc"
_fw4_offload_set() {
	local st="$1" zf="$2" t="$FW4_TPL.zm.$$"
	[ -f "$FW4_TPL" ] || return 2
	awk -v st="$st" -v zf="$zf" '
		BEGIN { re = "^[ \t]*meta l4proto [{] tcp, udp [}] (ct mark and 0x0ff00000 == 0x0 )?(ct original packets ge 30 )?flow offload @ft;$" }
		!done && $0 ~ re {
			ind = $0; sub(/meta l4proto.*$/, "", ind)
			hs = index($0, "ct mark and 0x0ff00000 == 0x0 ") > 0; hz = index($0, "ct original packets ge 30 ") > 0
			if (st == "1") hs = 1; else if (st == "0") hs = 0
			if (zf == "1") hz = 1; else if (zf == "0") hz = 0
			n = ind "meta l4proto { tcp, udp } " (hs ? "ct mark and 0x0ff00000 == 0x0 " : "") (hz ? "ct original packets ge 30 " : "") "flow offload @ft;"
			if (n != $0) ch = 1
			print n; done = 1; next
		}
		{ print }
		END { exit done ? (ch ? 0 : 1) : 2 }' "$FW4_TPL" > "$t"
	case $? in
		0) cat "$t" > "$FW4_TPL"; rm -f "$t"; return 0 ;;
		1) rm -f "$t"; return 1 ;;
		*) rm -f "$t"; return 2 ;;
	esac
}

_fw4_offload_on() { [ "$(uci -q get firewall.@defaults[0].flow_offloading)" = 1 ]; }
_fw4_offload_mode() {
	if [ "$(uci -q get firewall.@defaults[0].flow_offloading_hw)" = 1 ] && [ "$(uci -q get firewall.@defaults[0].flow_offloading)" = 1 ]; then echo hw
	elif [ "$(uci -q get firewall.@defaults[0].flow_offloading)" = 1 ]; then echo sw
	else echo off; fi
}

FT_ZAPRET_OFF="$ZM_STATE_DIR/ft.zapret.off"
_ft_zapret_sync() {
	[ -f "$FW4_TPL" ] && [ ! -f "$FT_ZAPRET_OFF" ] && _fw4_offload_on || return 0
	[ -x /etc/init.d/zapret ] || [ -x /etc/init.d/zapret2 ] || return 0
	[ "$(_flow_offloading_fix_applied)" = true ] && return 0
	_fw4_offload_set keep 1 || return 0
	logger -t zapret-manager "Flow Offloading: включён — поправка для Zapret применена сама"
	/etc/init.d/firewall reload >/dev/null 2>&1
	return 0
}
_ft_zapret_gone() {
	[ -x /etc/init.d/zapret ] || [ -x /etc/init.d/zapret2 ] && return 0
	rm -f "$FT_ZAPRET_OFF"
	[ "$(_flow_offloading_fix_applied)" = true ] || return 0
	_fw4_offload_set keep 0 || return 0
	echo "   ✓ Поправка Flow Offloading для Zapret убрана — Zapret на роутере больше нет"
	_fw4_offload_on && /etc/init.d/firewall reload >/dev/null 2>&1
	return 0
}

_flow_offloading_fix_applied() {
	grep -q 'ct original packets ge 30 flow offload @ft;' /usr/share/firewall4/templates/ruleset.uc 2>/dev/null \
		&& echo true || echo false
}

_expert_mode() { [ -f "$EXPERT_MODE_FILE" ] && echo true || echo false; }

system_status() {
printf '{"quic_blocked":%s,"ipv6_enabled":%s,"flow_offloading_fix":%s,"flow_mode":"%s","fw4_tpl":%s,"zapret_fix_off":%s,"zapret_installed":%s,"watch_off":%s,"expert_mode":%s,"pkg":"%s",%s}\n' \
        "$(_quic_blocked)" "$(_ipv6_enabled_in_zapret)" "$(_flow_offloading_fix_applied)" "$(_fw4_offload_mode)" "$([ -f "$FW4_TPL" ] && echo true || echo false)" \
        "$([ -f "$FT_ZAPRET_OFF" ] && echo true || echo false)" "$([ -x /etc/init.d/zapret ] || [ -x /etc/init.d/zapret2 ] && echo true || echo false)" "$([ -f "$WATCH_OFF" ] && echo true || echo false)" "$(_expert_mode)" "$PKG" "$(_zt_json)"
}

ZM_V6_ADDRS="2001:4860:4860::8888 2606:4700:4700::1111 2a02:6b8::feed:0ff"
ZM_V6_STATE="$JOBS_DIR/v6.state"
_zm_v6_ms() {
	local a t
	for a in "$@"; do
		t="$(ping -6 -c1 -W2 "$a" 2>/dev/null | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | head -n1)"
		[ -n "$t" ] && { echo "$t"; return 0; }
	done
	return 1
}
_zm_v6_dns() {
	nslookup google.com 127.0.0.1 2>/dev/null | awk '/^Name:/ { f = 1 } f && /^Address/ && /:[0-9A-Fa-f]*:/ { ok = 1 } END { exit !ok }'
}
_zm_v6_reach() {
	local a t
	for a in google.com $ZM_V6_ADDRS; do
		t="$(_zm_v6_ms "$a")" && { echo "$t $a"; return 0; }
	done
	return 1
}
_zm_v6_state_of() {
	[ -n "$1" ] || { echo dead; return; }
	if [ "${1#* }" = google.com ] || _zm_v6_dns; then echo live; else echo nodns; fi
}
_zm_v6_save() { mkdir -p "$JOBS_DIR"; echo "$1" > "$ZM_V6_STATE"; }
_zm_v6_probe() {
	_zm_v6_state_of "$(_zm_v6_reach)"
}
_zm_v6_cached() {
	local f="$ZM_V6_STATE"
	if [ ! -s "$f" ] || [ -n "$(find "$f" -mmin +10 2>/dev/null)" ]; then
		if mkdir "$f.lock" 2>/dev/null; then
			( _zm_v6_probe > "$f.new" 2>/dev/null; [ -s "$f.new" ] && mv -f "$f.new" "$f"; rmdir "$f.lock" ) >/dev/null 2>&1 </dev/null &
		elif [ -n "$(find "$f.lock" -mmin +2 2>/dev/null)" ]; then
			rmdir "$f.lock" 2>/dev/null
		fi
	fi
	cat "$f" 2>/dev/null
}

system_check_connectivity() {
	local t4 t6 r dns=true st
	t4=$(ping -4 -c1 -W2 google.com 2>/dev/null | grep 'time=' | sed -E 's/.*time=([0-9.]+).*/\1/')
	r="$(_zm_v6_reach)"; t6="${r%% *}"
	st="$(_zm_v6_state_of "$r")"
	[ "$st" = nodns ] && dns=false
	_zm_v6_save "$st"
	printf '{"ipv4_ok":%s,"ipv4_ms":"%s","ipv6_ok":%s,"ipv6_ms":"%s","ipv6_dns":%s}\n' \
		"$([ -n "$t4" ] && echo true || echo false)" "$(esc "$t4")" \
		"$([ -n "$t6" ] && echo true || echo false)" "$(esc "$t6")" "$dns"
}

_zm_want() { case "$1" in on) echo true ;; off) echo false ;; *) echo "" ;; esac; }
system_toggle_quic() {
	local w
	w="$(_zm_want "$1")"
	if [ -n "$w" ] && [ "$(_quic_blocked)" = "$w" ]; then printf '{"ok":true,"quic_blocked":%s}\n' "$w"; return 0; fi
	_sys_quic_flip
}
_sys_quic_flip() {
	if [ "$(_quic_blocked)" = "true" ]; then
		local rule idx
		for rule in Block_UDP_80 Block_UDP_443; do
			while true; do
				idx=$(uci show firewall | grep "name='$rule'" | cut -d. -f2 | cut -d= -f1 | head -n1)
				[ -z "$idx" ] && break
				uci -q delete "firewall.$idx" >/dev/null 2>&1 || break
			done
		done
		uci commit firewall >/dev/null 2>&1
		/etc/init.d/firewall restart >/dev/null 2>&1
		printf '{"ok":true,"quic_blocked":false}\n'
		return
	fi
	local lz wz
	lz="$(_zm_lan_zone)"; wz="$(_zm_wan_zone)"
	uci add firewall rule >/dev/null 2>&1
	uci set firewall.@rule[-1].name='Block_UDP_80' >/dev/null 2>&1
	uci add_list firewall.@rule[-1].proto='udp' >/dev/null 2>&1
	uci set "firewall.@rule[-1].src=$lz" >/dev/null 2>&1
	uci set "firewall.@rule[-1].dest=$wz" >/dev/null 2>&1
	uci set firewall.@rule[-1].dest_port='80' >/dev/null 2>&1
	uci set firewall.@rule[-1].target='REJECT' >/dev/null 2>&1
	uci add firewall rule >/dev/null 2>&1
	uci set firewall.@rule[-1].name='Block_UDP_443' >/dev/null 2>&1
	uci add_list firewall.@rule[-1].proto='udp' >/dev/null 2>&1
	uci set "firewall.@rule[-1].src=$lz" >/dev/null 2>&1
	uci set "firewall.@rule[-1].dest=$wz" >/dev/null 2>&1
	uci set firewall.@rule[-1].dest_port='443' >/dev/null 2>&1
	uci set firewall.@rule[-1].target='REJECT' >/dev/null 2>&1
	uci commit firewall >/dev/null 2>&1
	/etc/init.d/firewall restart >/dev/null 2>&1
	printf '{"ok":true,"quic_blocked":true}\n'
}

system_toggle_ipv6() {
	local w
	[ -f "$CONF" ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	w="$(_zm_want "$1")"
	if [ -n "$w" ] && [ "$(_ipv6_enabled_in_zapret)" = "$w" ]; then printf '{"ok":true,"ipv6_enabled":%s}\n' "$w"; return 0; fi
	_sys_ipv6_flip
}
_sys_ipv6_flip() {
	local r
	if [ "$(_ipv6_enabled_in_zapret)" = true ]; then
		_zapret_v6_set 1
		[ "$(_ipv6_enabled_in_zapret)" = false ] || { echo '{"error":"не удалось изменить настройку DISABLE_IPV6 в конфиге Zapret — ничего не изменено"}'; return 1; }
		zapret_restart
		printf '{"ok":true,"ipv6_enabled":false}\n'
		return
	fi
	if ! r="$(_zm_v6_reach)"; then
		_zm_v6_save dead
		echo '{"error":"IPv6 на роутере сейчас не работает: не ответили ни google.com, ни DNS Google, Cloudflare и Яндекса по IPv6. Включать его в Zapret не нужно"}'
		return 1
	fi
	_zm_v6_save "$(_zm_v6_state_of "$r")"
	_zapret_v6_set 0
	[ "$(_ipv6_enabled_in_zapret)" = true ] || { echo '{"error":"не удалось изменить настройку DISABLE_IPV6 в конфиге Zapret — ничего не изменено"}'; return 1; }
	zapret_restart
	printf '{"ok":true,"ipv6_enabled":true}\n'
}

system_toggle_flow_offloading_fix() {
	local template="/usr/share/firewall4/templates/ruleset.uc" w
	[ -f "$template" ] || { echo '{"error":"шаблон firewall4 не найден"}'; return 1; }
	w="$(_zm_want "$1")"
	if [ -n "$w" ] && [ "$(_flow_offloading_fix_applied)" = "$w" ]; then
		[ "$w" = true ] && rm -f "$FT_ZAPRET_OFF"
		printf '{"ok":true,"flow_offloading_fix":%s}\n' "$w"; return 0
	fi
	if grep -q 'ct original packets ge 30 flow offload @ft;' "$template"; then
		if _fw4_offload_on; then mkdir -p "$ZM_STATE_DIR"; : > "$FT_ZAPRET_OFF"; fi
		_fw4_offload_set keep 0
		fw4 restart >/dev/null 2>&1
		printf '{"ok":true,"flow_offloading_fix":false}\n'
		return
	fi
	rm -f "$FT_ZAPRET_OFF"
	_fw4_offload_set keep 1
	if ! grep -q 'ct original packets ge 30 flow offload @ft;' "$template"; then
		echo '{"error":"в шаблоне firewall4 нет ожидаемой строки flow offload — исправление не применилось, ничего не изменено"}'
		return 1
	fi
	fw4 restart >/dev/null 2>&1
	printf '{"ok":true,"flow_offloading_fix":true}\n'
}

_zm_tmp_live() {
	local p="${1##*/}"
	p="${p#*.}"; p="${p%%.*}"
	case "$p" in ''|*[!0-9]*) return 1 ;; esac
	[ "$p" != "$$" ] && [ -d "/proc/$p" ]
}

gh_proxy() {
	local mo f=0 sep=""
	case "$1" in
		get|'') ;;
		set)
			mo="${2%%|*}"
			case "$mo" in off|auto) ;; *) echo '{"error":"неизвестный режим"}'; return 1 ;; esac
			mkdir -p "$ZM_STATE_DIR"
			if [ "$mo" = auto ]; then echo 'mode=auto' > "$ZM_GHP_FILE"; else rm -f "$ZM_GHP_FILE"; fi
			rm -f "$ZM_GHP_FAIL"
			ZM_GHP_MODE="" ;;
		*) echo '{"error":"неизвестное действие"}'; return 1 ;;
	esac
	_zm_ghp_load
	[ -s "$ZM_GHP_FAIL" ] && read -r f < "$ZM_GHP_FAIL"
	case "$f" in ''|*[!0-9]*) f=0 ;; esac
	printf '{"ok":true,"mode":"%s","list":"%s","fail_at":%s,"now":%s,"log":[' "$ZM_GHP_MODE" "$ZM_GHP_LIST" "$f" "$(date +%s)"
	[ -s "$ZM_GHP_LOG" ] && tail -n 15 "$ZM_GHP_LOG" | while IFS='|' read -r t m; do
		case "$t" in ''|*[!0-9]*) continue ;; esac
		printf '%s{"t":%s,"m":"%s"}' "$sep" "$t" "$(esc "$m")"; sep=","
	done
	printf ']}\n'
}
_zm_ghp_warn() {
	local f=0
	_zm_ghp_load
	[ "$ZM_GHP_MODE" = off ] && [ -s "$ZM_GHP_FAIL" ] || return 1
	read -r f < "$ZM_GHP_FAIL"
	case "$f" in ''|*[!0-9]*) return 1 ;; esac
	[ $(( $(date +%s) - f )) -lt 1800 ]
}

_pg_trace() {
case "$1" in
		zapret) echo "pkg:luci-i18n-zapret-ru pkg:luci-app-zapret pkg:zapret /opt/zapret /etc/config/zapret /etc/config/zapret-opkg /etc/init.d/zapret /etc/rc.d/*[0-9]zapret /etc/firewall.zapret /etc/hotplug.d/*/*zapret /etc/config/zapret.apk-new /tmp/zapret $(_zm_luci_files zapret) nft:zapret cron:zm-autobest cron:zm-excl-auto $ZO_RKN_FLAG $ZO_USER_FLAG $ZO_IPID_FLAG $ZO_DOH_FLAG $ZA_MODE_FILE $ZA_LAST $ZA_YT_FILE $ZA_LAST_YT $ZA_TS $ZA_TIME_FILE $ZA_LOG $TEST_KEEP $TEST_BACKUP $ZC_FILE $ZC_BAK $ZC_AFTER $YV_OFF_FLAG $DV_OFF_FLAG $TEST_DIR $TEST_CUSTOM_FILE" ;;
		zapret2) echo "pkg:luci-i18n-zapret2-ru pkg:luci-app-zapret2 pkg:zapret2 /opt/zapret2 /etc/config/zapret2 /etc/config/zapret2-opkg /etc/init.d/zapret2 /etc/rc.d/*zapret2 /etc/hotplug.d/*/*zapret2 /etc/config/zapret2.apk-new /tmp/zapret2* $(_zm_luci_files zapret2) nft:zapret2 cronrx:zapret2" ;;
		terminal) echo "pkg:luci-i18n-ttyd-ru pkg:luci-app-ttyd pkg:ttyd /usr/bin/ttyd /etc/config/ttyd /etc/config/ttyd-opkg /etc/config/ttyd.apk-new /etc/init.d/ttyd /etc/rc.d/*ttyd $(_zm_luci_files ttyd)" ;;
esac
}

ZM_MIRRORS="downloads.openwrt.org mirror-03.infra.openwrt.org openwrt.tetaneutral.net ftp.halifax.rwth-aachen.de/openwrt openwrt.mirror.garr.it/mirrors/openwrt mirrors.ustc.edu.cn/openwrt openwrt.c3sl.ufpr.br mirror.marwan.ma/openwrt openwrt.pixeldeck.net"
_mirror_feed1() {
	local l
	l="$(grep -v '^[[:space:]]*#' "$(_confz)" 2>/dev/null | grep -oE 'https?://[^ ]+/(releases|snapshots)/[^ ]+' | head -n1)"
	[ -n "$l" ] || return 1
	case "$l" in *.adb|*/Packages.gz) ;; *) [ "$PKG" = apk ] || l="${l%/}/Packages.gz" ;; esac
	echo "$l"
}
_mirror_swap() { printf '%s\n' "$1" | sed -E "s#^https?://[^ ]+/(releases|snapshots)/#https://$2/\1/#"; }
_mirror_write() {
	local f
	f="$(_confz)"
	[ -f "$f" ] || return 1
	cp -p "$f" "$f.zm-bak" 2>/dev/null
	sed -i -E "s#https?://[^ ]+/(releases|snapshots)/#https://$1/\1/#g" "$f"
}
_mirror_undo() { local f; rm -f "$ZM_SI_STATIC"; f="$(_confz)"; [ -f "$f.zm-bak" ] && mv -f "$f.zm-bak" "$f"; }
_mirror_keep() { rm -f "$(_confz).zm-bak"; }
_mirror_probe() {
	local r code t
	r="$(curl -s -o /dev/null -L -r 0-1023 --connect-timeout 4 --max-time 10 -w '%{http_code} %{time_total}' "$(_mirror_swap "$2" "$1")" 2>/dev/null)"
	code="${r%% *}"; t="${r##* }"
	case "$code" in 200|206) ;; *) return 1 ;; esac
	awk -v t="$t" -v h="$1" 'BEGIN { printf "%d %s\n", t * 1000 + 0.5, h }'
}
_mirror_upd_bad() {
	local h="$2"
	[ -s "$1" ] || return 1
	grep -iE 'error|failed|unable|warning|timed out|not found|404|network' "$1" 2>/dev/null | grep -v 'write error: Broken pipe' | grep -qF "$h"
}
_mirror_upd_try() {
	local out="$JOBS_DIR/mirror-upd.$$" rc h
	h="$(_mirror_host)"
	mkdir -p "$JOBS_DIR"
	_zm_run 150 $PKG_UPD > "$out" 2>&1; rc=$?
	_zm_pkg_unlock
	if [ "$rc" = 0 ] && ! _mirror_upd_bad "$out" "$h"; then rm -f "$out"; return 0; fi
	_zm_pkg_fmt < "$out" | head -n 4
	rm -f "$out"
	return 1
}
_mirror_mark() { rm -f "$ZM_SI_STATIC"; mkdir -p "$ZM_STATE_DIR"; printf '%s\t%s\t%s\n' "$1" "$(date +%s)" "$2" > "$ZM_MIRROR_STATE"; }
_mirror_auto() {
	[ -n "$ZM_MIRROR_TRIED" ] && return 1
	ZM_MIRROR_TRIED=1
	_mirror_pick_core auto
}

_mirror_label() {
	case "$1" in
		mirror-03.infra.openwrt.org) echo "Infra OpenWrt" ;; openwrt.c3sl.ufpr.br) echo "Brazil" ;; mirrors.ustc.edu.cn/openwrt) echo "China" ;;
		openwrt.tetaneutral.net) echo "France" ;; openwrt.mirror.garr.it/mirrors/openwrt) echo "Italy" ;; mirror.marwan.ma/openwrt) echo "Morocco" ;;
		openwrt.pixeldeck.net) echo "USA" ;; ftp.halifax.rwth-aachen.de/openwrt) echo "Germany" ;; downloads.openwrt.org) echo "default / OpenWrt" ;; *) echo "$1" ;;
	esac
}
_mirror_ping() {
	local r
	r="$(ping -c 3 -W 2 "${1%%/*}" 2>/dev/null | sed -n 's#.*= *[0-9.]*/\([0-9.]*\)/.*#\1#p' | head -n 1)"
	[ -n "$r" ] || return 1
	awk -v t="$r" 'BEGIN { printf "%d\n", t + 0.5 }'
}
_mirror_feeds() {
	grep -v '^[[:space:]]*#' "$(_confz)" 2>/dev/null | awk '
		{
			u = ""; n = ""
			for (i = 1; i <= NF; i++) if ($i ~ /^https?:\/\/[^ ]+\/(releases|snapshots)\//) { u = $i; if (i > 1 && $(i - 1) !~ /^src/) n = $(i - 1) }
			if (u == "") next
			p = u; sub(/^https?:\/\/[^\/]+/, "", p)
			if (n == "") {
				t = p; sub(/\/(packages\.adb|Packages\.gz)$/, "", t); sub(/\/+$/, "", t)
				if (t ~ /\/kmods\//) n = "kmods"
				else if (t ~ /\/targets\//) n = "core"
				else { n = t; sub(/.*\//, "", n) }
			}
			print n "\t" p
		}'
}
_mirror_why() {
	local m="$1" r
	r="$(printf '%s' "$m" | sed -n 's#.*://[^ ]*\.adb: *##p')"
	[ -n "$r" ] || r="$(printf '%s' "$m" | sed 's#https\{0,1\}://[^ ]*##g; s/^[[:space:]*]*//; s/[[:space:]]*$//')"
	r="$(printf '%s' "$r" | sed 's/ *(check Internet connection and network settings)//')"
	case "$r" in
		*[Nn]etwork\ error*|*[Nn]etwork\ unreachable*) echo "ошибка сети" ;;
		*[Tt]imed\ out*|*[Tt]imeout*) echo "зеркало не ответило вовремя" ;;
		*404*|*[Nn]ot\ [Ff]ound*|*[Nn]o\ such\ file*) echo "на зеркале нет этого репозитория" ;;
		*[Cc]ertificate*|*TLS*|*SSL*) echo "ошибка TLS-сертификата" ;;
		*UNTRUSTED*|*[Ss]ignature*) echo "подпись списка не прошла проверку" ;;
		*[Ff]ailed\ to\ download*) echo "список пакетов не скачался" ;;
		'') echo "ошибка при обновлении" ;;
		*) printf '%s\n' "$r" | cut -c1-120 ;;
	esac
}
_mirror_feed_check() {
	local out="$1" n p bad=0 all=0 errs I="$MP_I"
	errs="$(grep -iE 'error|fail|unable|warning|timed out|not found|404|network' "$out" 2>/dev/null | grep -v 'write error: Broken pipe')"
	while IFS='	' read -r n p; do
		[ -n "$p" ] || continue
		all=$((all + 1))
		if printf '%s\n' "$errs" | grep -qF "$p"; then
			bad=$((bad + 1))
			echo "$I     ✗ $n — $(_mirror_why "$(printf '%s\n' "$errs" | grep -F "$p" | head -n 1)")"
		else
			echo "$I     ✓ $n"
		fi
	done <<MF_EOF
$(_mirror_feeds)
MF_EOF
	MF_ALL="$all"; MF_BAD="$bad"
	[ "$all" -gt 0 ] && [ "$bad" = 0 ]
}
_mirror_nrep() { awk -v n="$1" 'BEGIN { a = n % 100; b = n % 10; print n " " ((a >= 11 && a <= 14) ? "репозиториев" : b == 1 ? "репозиторий" : (b >= 2 && b <= 4) ? "репозитория" : "репозиториев") }'; }
_mirror_hd() { if [ -n "$MP_I" ]; then echo "   → $*"; else echo "==> $*"; fi; }
_mirror_pick_core() {
	local mode="$1" cur u dir h t p n=0 k total out rc name rel arch I="" cn
	cur="$(_mirror_host)"; u="$(_mirror_feed1)"
	cn="$(_mirror_label "$cur")"
	if [ "$mode" = auto ]; then
		[ -n "$cur" ] && [ -n "$u" ] || return 1
		I="  "
		echo "==> Репозиторий OpenWrt ($cn) отвечает с ошибками — подбираем рабочее зеркало"
	else
		[ -n "$u" ] || { echo "ОШИБКА: в списке репозиториев ($(_confz)) нет адреса OpenWrt"; return 1; }
		rel="$(. /etc/openwrt_release 2>/dev/null; echo "$DISTRIB_RELEASE")"; arch="$(. /etc/openwrt_release 2>/dev/null; echo "$DISTRIB_ARCH")"
		echo "==> Подбираем зеркало OpenWrt ${rel:+$rel }${arch:+($arch) }— сейчас $cn"
	fi
	MP_I="$I"
	dir="$JOBS_DIR/mirror-pick.$$"; rm -rf "$dir"; mkdir -p "$dir"
	_mirror_hd "Меряем пинг до $(echo $ZM_MIRRORS | wc -w | tr -d ' ') зеркал"
	for h in $ZM_MIRRORS; do
		n=$((n + 1))
		( t="$(_mirror_ping "$h")" || t=-
		  p="$(_mirror_probe "$h" "$u")" && p="${p%% *}" || p=-
		  printf '%s\t%s\t%s\n' "$t" "$p" "$h" > "$dir/$n" ) &
	done
	wait
	cat "$dir"/* 2>/dev/null > "$dir/all"
	while IFS='	' read -r t p h; do
		[ -n "$h" ] || continue
		if [ "$t" != - ]; then k="пинг $t мс"; else k="на пинг не отвечает"; fi
		if [ "$mode" = auto ] && [ "$h" = "$cur" ]; then echo "$I   · $(_mirror_label "$h") ($h) — $k, сейчас выбрано и отвечает с ошибками"
		elif [ "$p" != - ]; then echo "$I   · $(_mirror_label "$h") ($h) — $k, пакеты отдаёт за $p мс"
		else echo "$I   · $(_mirror_label "$h") ($h) — $k, пакеты для этого роутера не отдаёт"; fi
	done < "$dir/all"
	awk -F'\t' -v skip="$([ "$mode" = auto ] && echo "$cur")" '$2 != "-" && $3 != skip { print ($1 == "-" ? 100000 + $2 : $1) "\t" $1 "\t" $3 }' "$dir/all" | sort -n | cut -f2- > "$dir/order"
	[ "$mode" = auto ] && { head -n 4 "$dir/order" > "$dir/o4"; mv -f "$dir/o4" "$dir/order"; }
	rm -f "$dir"/[0-9]* "$dir/all"
	total="$(grep -c . "$dir/order")"
	if [ "$total" = 0 ]; then
		rm -rf "$dir"; MP_I=""
		if [ "$mode" = auto ]; then echo "   ✗ Ни одно зеркало не отдаёт пакеты — похоже, нет интернета. Оставляем $cn"
		else echo "ОШИБКА: ни одно зеркало не отдаёт пакеты для этого роутера — похоже, нет интернета. Оставляем $cn"; fi
		return 1
	fi
	k=""; n=0
	while IFS='	' read -r t h; do n=$((n + 1)); k="$k${k:+, }$n) $(_mirror_label "$h")$([ "$t" != - ] && echo " $t мс")"; done < "$dir/order"
	_mirror_hd "Порядок проверки — от быстрого к медленному$([ "$mode" = auto ] && echo ", первые $total"): $k"
	n=0
	out="$dir/upd"
	while IFS='	' read -r t h; do
		[ -n "$h" ] || continue
		n=$((n + 1)); name="$(_mirror_label "$h")"
		_mirror_hd "[$n/$total] $name — $h$([ "$t" != - ] && echo ", пинг $t мс")"
		if [ "$h" != "$cur" ]; then
			_mirror_write "$h" || { echo "ОШИБКА: не удалось записать $(_confz)"; rm -rf "$dir"; MP_I=""; return 1; }
		fi
		echo "$I   → Обновляем список пакетов через $h"
		_zm_run 150 $PKG_UPD > "$out" 2>&1; rc=$?
		_zm_pkg_unlock
		if _mirror_feed_check "$out" && [ "$rc" = 0 ]; then
			[ "$h" != "$cur" ] && _mirror_keep
			if [ "$h" = downloads.openwrt.org ]; then rm -f "$ZM_MIRROR_STATE"; else _mirror_mark "$h" "$([ "$mode" = auto ] && echo auto || echo pick)"; fi
			rm -rf "$dir"; MP_I=""
			if [ "$mode" = auto ]; then echo "   ✓ Список пакетов обновлён через зеркало $name ($h) — все $(_mirror_nrep "$MF_ALL"). Оно останется, вернуть основное можно в «Системе»"
			elif [ "$h" = "$cur" ]; then echo "==> Готово: текущее зеркало $name — самое быстрое из рабочих, все $(_mirror_nrep "$MF_ALL") обновились. Оставляем его"
			else echo "==> Готово: выбрано зеркало $name ($h)$([ "$t" != - ] && echo ", пинг $t мс") — все $(_mirror_nrep "$MF_ALL") обновились без ошибок"; fi
			return 0
		fi
		if [ "$MF_BAD" = 0 ]; then echo "$I   ✗ $name: обновление списка пакетов завершилось с ошибкой"; _zm_pkg_fmt < "$out" | head -n 3
		else echo "$I   ✗ $name: не обновилось репозиториев — $MF_BAD из $MF_ALL"; fi
		[ "$h" != "$cur" ] && _mirror_undo
		[ "$n" -lt "$total" ] && echo "$I   → Пробуем следующее по пингу"
	done < "$dir/order"
	rm -rf "$dir"; MP_I=""
	if [ "$mode" = auto ]; then
		echo "   ✗ Ни одно зеркало не помогло — оставляем $cn"
		return 1
	fi
	echo "==> Возвращаем прежнее зеркало $cn и обновляем список пакетов"
	_zm_run 150 $PKG_UPD >/dev/null 2>&1; _zm_pkg_unlock
	echo "ОШИБКА: ни через одно зеркало все репозитории не обновились. Оставлено $cn"
	return 1
}
do_mirror_pick() { _mirror_pick_core pick; }

do_mirror_set() {
	local host="$1" u prev ms
	prev="$(_mirror_host)"
	u="$(_mirror_feed1)"
	[ -n "$u" ] || { echo "ОШИБКА: в списке репозиториев ($(_confz)) нет адреса OpenWrt"; return 1; }
	echo "==> Проверяем зеркало $host: отдаёт ли оно список пакетов этого роутера"
	if ! ms="$(_mirror_probe "$host" "$u")"; then
		echo "ОШИБКА: зеркало $host не отдаёт список пакетов для этой версии OpenWrt — оставляем ${prev:-прежнее}"
		return 1
	fi
	echo "   ✓ Отвечает за ${ms%% *} мс"
	_mirror_write "$host" || { echo "ОШИБКА: не удалось записать $(_confz)"; return 1; }
	echo "==> Обновляем список пакетов через $host"
	if ! _mirror_upd_try; then
		_mirror_undo
		echo "ОШИБКА: через $host список пакетов обновился с ошибками — вернули ${prev:-прежнее}"
		return 1
	fi
	_mirror_keep
	if [ "$host" = downloads.openwrt.org ]; then rm -f "$ZM_MIRROR_STATE"; else _mirror_mark "$host" manual; fi
	echo "==> Готово: зеркало $host работает, список пакетов обновлён без ошибок"
}

mirror_set() {
	local id="$1" host="" j
	case "$id" in
		infra)        host="mirror-03.infra.openwrt.org" ;;
		brazil)       host="openwrt.c3sl.ufpr.br" ;;
		china)        host="mirrors.ustc.edu.cn/openwrt" ;;
		france)       host="openwrt.tetaneutral.net" ;;
		italy)        host="openwrt.mirror.garr.it/mirrors/openwrt" ;;
		morocco)      host="mirror.marwan.ma/openwrt" ;;
		usa)          host="openwrt.pixeldeck.net" ;;
		germany_rwth) host="ftp.halifax.rwth-aachen.de/openwrt" ;;
		default)      host="downloads.openwrt.org" ;;
		pick) ;;
		*) echo '{"error":"неизвестное зеркало"}'; return 1 ;;
	esac
	if j="$(_zm_busy_job)"; then printf '{"error":"%s"}\n' "$(esc "идёт операция «$j» — дождитесь её окончания")"; return 1; fi
	if [ "$id" = pick ]; then job_start mirror_set do_mirror_pick
	else job_start mirror_set do_mirror_set "$host"; fi
}

_excl_dir() { echo "/opt/zapret/init.d/openwrt/custom.d"; }
_excl_file() { echo "$(_excl_dir)/20-script.sh"; }

_excl_current() {
	local f; f="$(_excl_file)"
	[ -f "$f" ] || return 0
	grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' "$f" | sort -u
}

_excl_enable_custom() {
	[ -f "$CONF" ] || return 0
	if grep -q "^[[:space:]]*option DISABLE_CUSTOM " "$CONF"; then
		sed -i "s/^\([[:space:]]*option DISABLE_CUSTOM \).*/\1'0'/" "$CONF"
	else
		sed -i "/^config main/a\\	option DISABLE_CUSTOM '0'" "$CONF"
	fi
}

_excl_write() {
	local ips="$1" f
	f="$(_excl_file)"
	mkdir -p "$(_excl_dir)"
	if [ -n "$ips" ]; then
		_excl_enable_custom
		local formatted
		formatted=$(printf '%s\n' "$ips" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')
		{
			echo "EXCEPT_SRC='{ $formatted }'"
			echo "nft insert rule inet zapret postrouting_hook index 0 \\"
			echo "  ip saddr \$EXCEPT_SRC meta mark set meta mark \\| 0x40000000"
		} > "$f"
	else
		: > "$f"
	fi
}

exclusions_status() {
	[ -f /etc/init.d/zapret ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	local current devjson="" first=1 ip name ts mac rest aip ahw aflags amac amask adev aname

	current=$(_excl_current)

	if [ -f /tmp/dhcp.leases ]; then
		while read -r ts mac ip name rest; do
			[ -z "$ip" ] && continue
			echo "$ip" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' || continue
			[ -z "$name" ] && name="*"
			[ "$name" = "*" ] && name="Неизвестное устройство"
			[ "$first" -eq 1 ] || devjson="$devjson,"
			first=0
			devjson="$devjson{\"ip\":\"$ip\",\"name\":\"$(esc "$name")\",\"excluded\":$(printf '%s\n' "$current" | grep -qx "$ip" && echo true || echo false)}"
		done < /tmp/dhcp.leases
	fi

	local lan_dev arp_tmp
	lan_dev=" $(_zm_lan_devs) "
	arp_tmp="$JOBS_DIR/excl_arp_tmp"
	rm -f "$arp_tmp" "$arp_tmp.log"
	if [ -f /proc/net/arp ]; then
		tail -n +2 /proc/net/arp | while read -r aip ahw aflags amac amask adev; do
			[ -z "$aip" ] && continue
			case "$lan_dev" in *" $adev "*) ;; *) continue ;; esac
			echo "$aip" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' || continue
			[ "$aflags" = "0x0" ] && continue
			printf '%s' "$devjson" | grep -q "\"ip\":\"$aip\"" && continue
			aname=""
			[ -f /tmp/dhcp.leases ] && aname=$(awk -v mac="$amac" 'tolower($2)==tolower(mac){print $4; exit}' /tmp/dhcp.leases)
			if [ -z "$aname" ] || [ "$aname" = "*" ]; then
				[ -f "$arp_tmp.log" ] || logread 2>/dev/null | grep -i "DHCPACK" > "$arp_tmp.log"
				aname=$(grep -i "$aip" "$arp_tmp.log" | grep -i "$amac" | tail -n1 | awk '{print $NF}')
			fi
			[ "$aname" = "$amac" ] && aname=""
			[ -n "$aname" ] || aname="Неизвестное устройство"
			printf '%s|%s\n' "$aip" "$aname" >> "$arp_tmp"
		done
		rm -f "$arp_tmp.log"
	fi
	if [ -f "$arp_tmp" ]; then
		while IFS='|' read -r aip aname; do
			[ -z "$aip" ] && continue
			[ "$first" -eq 1 ] || devjson="$devjson,"
			first=0
			devjson="$devjson{\"ip\":\"$aip\",\"name\":\"$(esc "$aname")\",\"excluded\":$(printf '%s\n' "$current" | grep -qx "$aip" && echo true || echo false)}"
		done < "$arp_tmp"
		rm -f "$arp_tmp"
	fi

	local ip2
	for ip2 in $current; do
		[ -z "$ip2" ] && continue
		printf '%s' "$devjson" | grep -q "\"ip\":\"$ip2\"" && continue
		[ "$first" -eq 1 ] || devjson="$devjson,"
		first=0
		devjson="$devjson{\"ip\":\"$ip2\",\"name\":\"Устройство offline\",\"excluded\":true}"
	done

	printf '{"devices":[%s]}\n' "$devjson"
}

exclusions_toggle() {
	local ip="$1" current new_list excluded="false"
	_zm_re "$ip" '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' || { echo '{"error":"некорректный IP-адрес"}'; return 1; }
	[ -f /etc/init.d/zapret ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	current=$(_excl_current)
	if printf '%s\n' "$current" | grep -qx "$ip"; then
		new_list=$(printf '%s\n' "$current" | grep -vx "$ip")
	else
		new_list=$(printf '%s\n%s\n' "$current" "$ip" | grep -v '^$' | sort -u)
		excluded="true"
	fi
	_excl_write "$new_list"
	zapret_restart
	printf '{"ok":true,"ip":"%s","excluded":%s}\n' "$(esc "$ip")" "$excluded"
}

exclusions_clear() {
	[ -f /etc/init.d/zapret ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	_excl_write ""
	zapret_restart
	printf '{"ok":true}\n'
}

_zl_path() {
	case "$1" in
		exclude) echo /opt/zapret/ipset/zapret-hosts-user-exclude.txt ;;
		user)    echo /opt/zapret/ipset/zapret-hosts-user.txt ;;
		google)  echo /opt/zapret/ipset/zapret-hosts-google.txt ;;
		*) return 1 ;;
	esac
}
_zl_json_text() {
	[ -f "$1" ] || return 0
	local tab; tab="$(printf '\t')"
	tr -d '\r\000-\010\013\014\016-\037' < "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$tab/\\\\t/g" | awk '{ printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }'
}
_zl_count() { local n; [ -f "$1" ] && n=$(grep -cvE '^[[:space:]]*(#.*)?$' "$1"); echo "${n:-0}"; }
_zl_info() {
	local f; f="$(_zl_path "$1")"
	printf '{"id":"%s","path":"%s","exists":%s,"count":%s,"size":%s,"mtime":%s,"auto":"%s","nochange":%s}' "$1" "$f" \
		"$([ -f "$f" ] && echo true || echo false)" "$(_zl_count "$f")" \
		"$([ -f "$f" ] && wc -c < "$f" | tr -d ' ' || echo 0)" "$([ -f "$f" ] && date -r "$f" +%s 2>/dev/null || echo 0)" \
		"$([ "$1" = exclude ] && _zx_auto_get)" "$(_nochange_in "$f" && echo true || echo false)"
}

ZX_AUTO_TAG="# zm-excl-auto"

_zx_auto_get() {
	local v
	v="$(grep -F "$ZX_AUTO_TAG=" "$CRON_FILE" 2>/dev/null | head -n1 | sed 's/.*=//')"
	case "$v" in h2|h4|h6|h12) echo "$v" ;; *) echo off ;; esac
}

zapret_excl_auto_set() {
	local v="$1" spec=""
	case "$v" in
		off) ;;
		h2|h4|h6|h12) spec="17 */${v#h} * * *" ;;
		*) echo '{"error":"неизвестный интервал"}'; return 1 ;;
	esac
	[ -z "$spec" ] || [ -x /etc/init.d/zapret ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	mkdir -p "$(dirname "$CRON_FILE")"
	touch "$CRON_FILE"
	sed -i "\\|$ZX_AUTO_TAG=|d" "$CRON_FILE"
	[ -n "$spec" ] && echo "$spec /opt/zapret-manager-luci/backend.sh zapret_excl_tick >/dev/null 2>&1 $ZX_AUTO_TAG=$v" >> "$CRON_FILE"
	/etc/init.d/cron enable >/dev/null 2>&1
	/etc/init.d/cron restart >/dev/null 2>&1
	printf '{"ok":true,"info":%s}\n' "$(_zl_info exclude)"
}

zapret_excl_tick() {
	local f tmp
	[ -x /etc/init.d/zapret ] || return 0
	f="$(_zl_path exclude)"; tmp="$f.zmauto"
	_nochange_in "$f" && return 0
	_zm_busy_job >/dev/null 2>&1 && return 0
	mkdir -p "$(dirname "$f")"
	rm -f "$tmp"
	_zm_fetch "$EXCLUDE_URL" "$tmp" 60
	if [ ! -s "$tmp" ] || grep -qi '<html\|<!doctype' "$tmp" || ! grep -q '^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]' "$tmp"; then rm -f "$tmp"; return 0; fi
	if cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
	mv -f "$tmp" "$f"; chmod 644 "$f"
	logger -t zapret-manager "Список исключений Zapret обновлён по расписанию"
	zapret_restart
	return 0
}

zapret_lists_status() {
	[ -x /etc/init.d/zapret ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	printf '{"lists":[%s,%s,%s]}\n' "$(_zl_info exclude)" "$(_zl_info user)" "$(_zl_info google)"
}

zapret_list_get() {
	local f; f="$(_zl_path "$1")" || { echo '{"error":"неизвестный список"}'; return 1; }
	printf '{"id":"%s","content":"%s","info":%s}\n' "$1" "$(_zl_json_text "$f")" "$(_zl_info "$1")"
}

zapret_list_set() {
	local f tmp
	f="$(_zl_path "$1")" || { echo '{"error":"неизвестный список"}'; return 1; }
	[ -x /etc/init.d/zapret ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	mkdir -p "$(dirname "$f")"
	tmp="$f.zmtmp"
	printf '%s\n' "$2" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | awk 'NF { for (i = 0; i < e; i++) print ""; e = 0; print; next } { e++ }' > "$tmp" || { rm -f "$tmp"; echo '{"error":"не удалось записать файл"}'; return 1; }
	mv -f "$tmp" "$f"
	chmod 644 "$f"
	zapret_restart
	printf '{"ok":true,"info":%s}\n' "$(_zl_info "$1")"
}

_nochange_strip() {
	awk '{ l = tolower($0); if (l ~ /^[ \t]*#[ \t]*nochange[ \t]*$/) next; print }'
}

zapret_nochange_set() {
	local t="${1%%:*}" st="${1#*:}" f tmp
	case "$st" in on|off) ;; *) echo '{"error":"неизвестное значение"}'; return 1 ;; esac
	[ -x /etc/init.d/zapret ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	case "$t" in
		strategy)
			[ -f "$CONF" ] || { echo '{"error":"конфигурация Zapret не найдена"}'; return 1; }
			grep -q "^[[:space:]]*option NFQWS_OPT '\$" "$CONF" || { echo '{"error":"в конфигурации не найден блок NFQWS_OPT"}'; return 1; }
			tmp="$CONF.zmnc"
			if [ "$st" = on ]; then
				_nochange_strategy || {
					awk '{ print } !d && /^[ \t]*option NFQWS_OPT \047$/ { print "#nochange"; d = 1 }' "$CONF" > "$tmp" && [ -s "$tmp" ] && cat "$tmp" > "$CONF"
					rm -f "$tmp"
				}
			else
				awk '/^[ \t]*option NFQWS_OPT \047$/ { b = 1; print; next } b && /^[ \t]*\047$/ { b = 0 } b { l = tolower($0); if (l ~ /^[ \t]*#[ \t]*nochange[ \t]*$/) next } { print }' "$CONF" > "$tmp" && [ -s "$tmp" ] && cat "$tmp" > "$CONF"
				rm -f "$tmp"
				_nochange_strategy && { echo '{"error":"пометка #nochange стоит внутри другой строки — уберите её вручную в редакторе стратегии","nochange":true}'; return 1; }
			fi
			printf '{"ok":true,"nochange":%s}\n' "$(_nochange_strategy && echo true || echo false)" ;;
		exclude|user|google)
			f="$(_zl_path "$t")"; tmp="$f.zmnc"
			mkdir -p "$(dirname "$f")"
			if [ "$st" = on ]; then
				_nochange_in "$f" || { { echo "#nochange"; [ -f "$f" ] && cat "$f"; :; } > "$tmp" && mv -f "$tmp" "$f"; chmod 644 "$f"; }
			elif [ -f "$f" ]; then
				_nochange_strip < "$f" > "$tmp" && mv -f "$tmp" "$f"; chmod 644 "$f"
				_nochange_in "$f" && { printf '{"error":"пометка #nochange стоит внутри другой строки — уберите её вручную в редакторе списка","info":%s}\n' "$(_zl_info "$t")"; return 1; }
			fi
			printf '{"ok":true,"info":%s}\n' "$(_zl_info "$t")" ;;
		*) echo '{"error":"неизвестный список"}'; return 1 ;;
	esac
}

zapret_list_restore() {
	case "$1" in
		auto=*) zapret_excl_auto_set "${1#auto=}"; return ;;
		nochange=*) zapret_nochange_set "${1#nochange=}"; return ;;
	esac
	[ "$1" = exclude ] || { echo '{"error":"восстановить можно только список исключений"}'; return 1; }
	[ -x /etc/init.d/zapret ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	local f tmp; f="$(_zl_path exclude)"; tmp="$f.zmdl"
	_nochange_in "$f" && { echo '{"error":"включено «Не изменять список» (#nochange) — панель его не меняет. Выключите этот переключатель, чтобы восстановить исходный"}'; return 1; }
	mkdir -p "$(dirname "$f")"
	rm -f "$tmp"
	_zm_fetch "$EXCLUDE_URL" "$tmp" 60
	if ! _zm_dl_sane "$tmp"; then rm -f "$tmp"; echo '{"error":"не удалось скачать список исключений — текущий список не тронут"}'; return 1; fi
	mv -f "$tmp" "$f"; chmod 644 "$f"
	zapret_restart
	zapret_list_get exclude
}

nfqws_opt_get() {
	[ -f "$CONF" ] || { printf '{"content":""}\n'; return 0; }
	local content
	content=$(sed -n "/^[[:space:]]*option NFQWS_OPT '\$/,/^[[:space:]]*'\$/p" "$CONF" | sed '1d;$d')
	printf '{"content":"%s"}\n' "$(esc_ml "$content")"
}

nfqws_opt_set() {
	local content="$1"
	[ -x /etc/init.d/zapret ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	[ -f "$CONF" ] || { echo '{"error":"конфигурация Zapret не найдена"}'; return 1; }
	grep -q "^[[:space:]]*option NFQWS_OPT '\$" "$CONF" || { echo '{"error":"в конфигурации не найден блок NFQWS_OPT"}'; return 1; }
	case "$content" in *"'"*) echo '{"error":"одинарные кавычки \u0027 в стратегии нельзя — они ломают конфиг Zapret"}'; return 1 ;; esac
	printf '%s' "$content" | grep -q -- '--' || { echo '{"error":"в стратегии нет ни одного параметра --… — сохранение отменено"}'; return 1; }
	sed -i "/^[[:space:]]*option NFQWS_OPT '/,\$d" "$CONF"
	{ echo "	option NFQWS_OPT '"; printf '%s\n' "$content"; echo "'"; } >> "$CONF"
	if _zo_doh_on; then [ -f "$ZO_DOH_FLAG" ] || { mkdir -p "$ZM_STATE_DIR"; _zo_doh_tpl > "$ZO_DOH_FLAG"; }
	else rm -f "$ZO_DOH_FLAG"; fi
	[ -f /opt/zapret/sync_config.sh ] && chmod +x /opt/zapret/sync_config.sh
	zapret_restart
	sleep 1
	printf '{"ok":true}\n'
}

_zm_pkg_files() {
	if [ "$PKG" = apk ]; then apk info -L "$1" 2>/dev/null | grep -v 'contains:$' | grep -v '^$' | sed 's#^/*#/#'
	else opkg files "$1" 2>/dev/null | grep '^/'; fi
}

_zm_pkg_reg_drop() {
	local p="$1"
	if [ "$PKG" = apk ]; then
		[ -f /etc/apk/world ] && sed -i "/^$p\$/d; /^$p[<>=~]/d" /etc/apk/world 2>/dev/null
	else
		rm -f "/usr/lib/opkg/info/$p".* 2>/dev/null
		if [ -f /usr/lib/opkg/status ]; then
			awk -v p="$p" 'BEGIN { RS = ""; ORS = "\n\n" } { split($0, l, "\n"); if (l[1] != "Package: " p) print }' /usr/lib/opkg/status > /usr/lib/opkg/status.zm 2>/dev/null &&
				cat /usr/lib/opkg/status.zm > /usr/lib/opkg/status
			rm -f /usr/lib/opkg/status.zm
		fi
	fi
}

_zm_pkg_purge() {
	local p="$1" files f try=1 left reg ca=0
	_pkg_is_installed "$p" || return 0
	_zm_ca_have && ca=1
	files="$(_zm_pkg_files "$p")"
	echo "   → Удаляем пакет $p"
	while [ "$try" -le 4 ]; do
		if [ "$try" = 1 ]; then
			_zm_run 180 $PKG_DEL "$p" >/dev/null 2>&1
		else
			[ "$try" = 4 ] && _zm_pkg_reg_drop "$p"
			if [ "$PKG" = apk ]; then
				_zm_run 180 apk del --force-broken-world "$p" >/dev/null 2>&1 || _zm_run 180 apk del --force "$p" >/dev/null 2>&1
			else
				_zm_run 180 opkg remove --force-depends --force-remove "$p" >/dev/null 2>&1
			fi
		fi
		_zm_pkg_unlock
		left=""
		for f in $files; do
			[ -f "$f" ] || [ -L "$f" ] || continue
			rm -f "$f" 2>/dev/null
			[ -f "$f" ] || [ -L "$f" ] && left="$left $f"
		done
		reg=0; _pkg_is_installed "$p" && reg=1
		if [ "$reg" = 0 ] && [ -z "$left" ]; then
			if [ -n "$ZM_PKG_QUIET" ]; then :
			elif [ "$try" = 1 ]; then echo "   ✓ Пакет $p удалён, остатков нет"
			else echo "   ✓ Пакет $p удалён с попытки $try, остатков нет"; fi
			[ "$ca" = 1 ] && _zm_ca_keep
			return 0
		fi
		[ "$try" -lt 4 ] && echo "   ↻ Пакет $p удалился не полностью — попытка $((try + 1)) из 4"
		try=$((try + 1))
		sleep 2
	done
	[ "$ca" = 1 ] && _zm_ca_keep
	[ "$reg" = 1 ] && echo "!! Пакет $p не удалился за 4 попытки — он всё ещё числится в системе"
	[ -n "$left" ] && echo "!! От пакета $p остались файлы:$left"
	return 1
}

_zm_luci_files() {
	local n
	for n in "$@"; do
		printf '%s ' "/www/luci-static/resources/view/$n" "/www/luci-static/resources/$n" "/www/luci-static/resources/protocol/$n.js" \
			"/usr/share/luci/menu.d/luci-app-$n.json" "/usr/share/luci/menu.d/luci-proto-$n.json" \
			"/usr/share/rpcd/acl.d/luci-app-$n.json" "/usr/share/rpcd/acl.d/luci-proto-$n.json" \
			"/usr/libexec/rpcd/luci.$n" "/usr/share/rpcd/ucode/luci.$n" "/usr/lib/lua/luci/i18n/$n.*.lmo"
	done
}
_zm_rm_listed() {
	local t l=""
	for t in $(_pg_trace "$1"); do case "$t" in /*) l="$l $t" ;; esac; done
	_zm_wipe $l
}

_zm_pkg_wipe() {
	local p rc=0
	for p; do _zm_pkg_purge "$p" || rc=1; done
	return $rc
}

_zm_wipe() {
	local f try=1 left
	while [ "$try" -le 4 ]; do
		left=""
		for f in "$@"; do
			[ -e "$f" ] || [ -L "$f" ] || continue
			rm -rf "$f" 2>/dev/null
			[ -e "$f" ] || [ -L "$f" ] && left="$left $f"
		done
		[ -z "$left" ] && return 0
		try=$((try + 1))
		sleep 1
	done
	echo "!! Не удалось удалить за 4 попытки:$left"
	return 1
}

_zm_rm_done() {
	if [ "$1" = 0 ] && [ -n "$ZM_RM_INNER" ]; then
		ZM_RB_NOTE=""
		echo "   ✓ Прежний $2 удалён — ставим заново"
		return 0
	fi
	if [ "$1" = 0 ]; then
		echo "==> Готово: $2 удалён полностью, остатков нет"
		_zm_rb_note
		return 0
	fi
	ZM_RB_NOTE=""
	echo "ОШИБКА: $2 удалён не полностью — что осталось, написано выше. Перезагрузите роутер и нажмите «Удалить» ещё раз"
	return 1
}

TEST_DIR="$JOBS_DIR/strategy_test"
_test_results_file() { echo "$TEST_DIR/results_$1.txt"; }
_test_running() { _job_running strategy_test; }
TEST_KEEP="$ZM_STATE_DIR/tests"
_test_keep_file() { echo "$TEST_KEEP/$(basename "$1")"; }
_test_rf() { if [ -s "$1" ]; then echo "$1"; else _test_keep_file "$1"; fi; }
_test_keep() {
	local f k
	mkdir -p "$TEST_KEEP" 2>/dev/null || return 0
	for f in "$(_test_results_file "$1")" "$(_test_detail_file "$1")"; do
		[ -s "$f" ] || continue
		k="$(_test_keep_file "$f")"
		if [ "$(wc -c < "$f")" -gt 98304 ]; then { head -n 2 "$f"; tail -c 96000 "$f" | sed 1d; } > "$k.t"; else cat "$f" > "$k.t"; fi
		mv -f "$k.t" "$k"
	done
	return 0
}
_test_unstale() {
	[ -s "$TEST_BACKUP" ] || return 0
	if [ -d /opt/zapret ] && cp -f "$TEST_BACKUP" "$CONF"; then
		echo "==> Прошлый тест был прерван — возвращаем прежние настройки Zapret"
		zapret_restart
	fi
	rm -f "$TEST_BACKUP"
}

_test_recover() {
	[ -s "$ZM_STATE_DIR/strategy_test.backup" ] || return 0
	_test_running && return 0
	[ -d /opt/zapret ] && cp -f "$ZM_STATE_DIR/strategy_test.backup" "$CONF" && zapret_restart
	rm -f "$ZM_STATE_DIR/strategy_test.backup"
}
TEST_BACKUP="$ZM_STATE_DIR/strategy_test.backup"
TEST_STOP_FLAG="$TEST_DIR/stop"
TEST_MODE_FILE="$TEST_DIR/mode"
TEST_DOMAINS_JSON="${GH_RAW}/hyperion-cs/dpi-checkers/refs/heads/main/ru/tcp-16-20/suite.v2.json"
TEST_YT_DOMAINS="youtu.be youtube.com i.ytimg.com i9.ytimg.com yt3.ggpht.com yt4.ggpht.com googleapis.com jnn-pa.googleapis.com googleusercontent.com signaler-pa.youtube.com youtubei.googleapis.com manifest.googlevideo.com yt3.googleusercontent.com rr4---sn-4g5e6nze.googlevideo.com rr4---sn-5go7yner.googlevideo.com rr4---sn-q4flrnsl.googlevideo.com rr5---sn-n8v7knez.googlevideo.com rr2---sn-q4fl6ndl.googlevideo.com rr1---sn-q4fl6n6y.googlevideo.com rr1---sn-aj5go5-53.googlevideo.com rr1---sn-4axm-n8vs.googlevideo.com rr14---sn-n8v7kn7r.googlevideo.com rr16---sn-axq7sn76.googlevideo.com rr4---sn-jvhnu5g-c35d.googlevideo.com rr1---sn-8ph2xajvh-5xge.googlevideo.com rr1---sn-xguxaxjvh-gufl.googlevideo.com rr1---sn-gvnuxaxjvh-jx3z.googlevideo.com rr1---sn-gvnuxaxjvh-jx3l.googlevideo.com rr1---sn-gvnuxaxjvh-o8ge.googlevideo.com rr5---sn-gvnuxaxjvh-n8vk.googlevideo.com rr10---sn-gvnuxaxjvh-304z.googlevideo.com rr12---sn-gvnuxaxjvh-bvwz.googlevideo.com rr3---sn-ug5onuxaxjvh-n8v6.googlevideo.com rr1---sn-ug5onuxaxjvh-p5ge.googlevideo.com rr1---sn-ug5onuxaxjvh-p3ul.googlevideo.com rr1---sn-ug5onuxaxjvh-n8v6.googlevideo.com rr1---sn-u5uuxaxjvhg0-ocje.googlevideo.com"
TEST_PARALLEL=8

_test_sort_results() {
	local f="$1" tmp
	tmp="$TEST_DIR/sort.$$"
	awk '{ n = split($0, a, " → "); if (n < 2 || a[n] !~ /^[0-9]+\/[0-9]+/) next; print a[n] + 0, $0 }' "$f" | sort -k1,1 -nr | cut -d' ' -f2- > "$tmp"
	mv "$tmp" "$f"
}

_test_prepare_urls() {
	local out="$1"
	: > "$out"
	printf '%s\n' \
		"gosuslugi.ru|https://www.gosuslugi.ru" \
		"esia.gosuslugi.ru|https://esia.gosuslugi.ru" \
		"nalog.ru|https://nalog.ru" \
		"lkfl2.nalog.ru|https://lkfl2.nalog.ru" \
		"rutube.ru|https://rutube.ru" \
		"ntc.party|https://ntc.party/" \
		"instagram.com|https://instagram.com" \
		"facebook.com|https://facebook.com" \
		"rutracker.org|https://rutracker.org" \
		"nnmclub.to|https://nnmclub.to" \
		"rutor.info|https://rutor.info" \
		"openwrt.org|https://openwrt.org" \
		"discord.com|https://discord.com" \
		"x.com|https://x.com" \
		"forum.ru-board.com|https://forum.ru-board.com" \
		"play.google.com|https://play.google.com" \
		"downloads.openwrt.org|https://downloads.openwrt.org" \
		"githubusercontent.com|https://raw.githubusercontent.com/Screamshow/Zapret-Manager/refs/heads/main/Zapret-Manager.sh" \
		>> "$out"
	curl -fsSL --connect-timeout 8 --max-time 15 "$TEST_DOMAINS_JSON" 2>/dev/null \
		| sed -n 's/.*"id":[[:space:]]*"\([^"]*\)".*"host":[[:space:]]*"\([^"]*\)".*/\1|\2/p' >> "$out"
}

_test_yt_urls() {
	local d
	for d in $TEST_YT_DOMAINS; do
		printf '%s|https://%s/\n' "$d" "$d"
	done
}

_test_kill_pid_tree() {
	local pid="$1" ch c
	[ -n "$pid" ] || return 0
	ch=$(cat "/proc/$pid/task/$pid/children" 2>/dev/null)
	for c in $ch; do _test_kill_pid_tree "$c"; done
	kill -9 "$pid" 2>/dev/null
}

_test_kill_bg_jobs() {
	local pf="$1" pid
	[ -s "$pf" ] || return 0
	while IFS= read -r pid; do
		[ -n "$pid" ] && _test_kill_pid_tree "$pid"
	done < "$pf"
	wait 2>/dev/null
}

_test_check_url() {
	local entry="$1" okfile="$2" logfile="$3" text link
	text=$(echo "$entry" | cut -d'|' -f1)
	link=$(echo "$entry" | cut -d'|' -f2)
	if curl -sL --connect-timeout 4 --max-time 6 --speed-time 3 --speed-limit 1 --range 0-65535 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) curl/8.0" -o /dev/null "$link" >/dev/null 2>&1; then
		echo 1 >> "$okfile"
		echo "[ OK ] $text" >> "$logfile"
	else
		echo "[FAIL] $text" >> "$logfile"
	fi
}

_test_check_all_urls() {
	local urls="$1" logfile="$2" okfile pidfile total run=0 ok entry
	okfile="$TEST_DIR/ok.$$"
	pidfile="$TEST_DIR/pids.$$"
	: > "$okfile"
	: > "$pidfile"
	total=$(printf '%s\n' "$urls" | grep -c '|')
	while IFS= read -r entry; do
		[ -z "$entry" ] && continue
		[ -f "$TEST_STOP_FLAG" ] && break
		_test_check_url "$entry" "$okfile" "$logfile" &
		echo $! >> "$pidfile"
		run=$((run + 1))
		if [ "$run" -ge "$TEST_PARALLEL" ]; then
			wait
			run=0
			[ -f "$TEST_STOP_FLAG" ] && break
		fi
	done <<-TEST_URLS_EOF
	$urls
	TEST_URLS_EOF
	if [ -f "$TEST_STOP_FLAG" ]; then
		_test_kill_bg_jobs "$pidfile"
	else
		wait
	fi
	ok=$(wc -l < "$okfile" | tr -d ' ')
	rm -f "$okfile" "$pidfile"
	printf '%s %s\n' "$ok" "$total"
}

_test_build_candidates() {
	local mode="$1" out="$2" n f
	: > "$out"
	case "$mode" in
		v)
			for n in 1 2 3 4 5 6 7 8 9 10; do strategy_v"$n" >> "$out"; done
			;;
		flowseal)
			f="$(_flowseal_file)"
			[ -s "$f" ] || do_flowseal_download >/dev/null 2>&1
			[ -s "$f" ] && cat "$f" >> "$out"
			;;
		v_flowseal)
			f="$(_flowseal_file)"
			[ -s "$f" ] || do_flowseal_download >/dev/null 2>&1
			[ -s "$f" ] && cat "$f" >> "$out"
			for n in 1 2 3 4 5 6 7 8 9 10; do strategy_v"$n" >> "$out"; done
			;;
		youtube)
			f="$(_yv_file)"
			[ -s "$f" ] || do_yv_download >/dev/null 2>&1
			[ -s "$f" ] && cat "$f" >> "$out"
			;;
		custom|custom_yt)
			[ -s "$TEST_CUSTOM_FILE" ] && _test_custom_clean < "$TEST_CUSTOM_FILE" >> "$out"
			;;
	esac
	case "$mode" in youtube|custom|custom_yt) ;; *) sed -i '/^#Y/d' "$out" ;; esac
}

_test_apply_block() {
	local block="$1"
	sed -i "/^[[:space:]]*option NFQWS_OPT '/,\$d" "$CONF"
	{ echo "	option NFQWS_OPT '"; echo "$block"; echo "'"; } >> "$CONF"
}

_test_detail_file() { echo "$TEST_DIR/detail_$1.txt"; }

_test_detail_domains() {
	printf 'D|%s\n' "$(printf '%s\n' "$2" | grep '|' | cut -d'|' -f1 | sed 's/[[:space:]]/_/g' | tr '\n' ' ' | sed 's/ $//')" >> "$1"
}

_test_detail_add() {
	local f="$1" name="$2" ok="$3" tot="$4" log="$5" fails
	fails="$(sed -n 's/^\[FAIL\] //p' "$log" 2>/dev/null | sed 's/[[:space:]]/_/g; s/|/\//g' | tr '\n' ' ' | sed 's/ $//')"
	printf 'S|%s|%s|%s|%s\n' "$(printf '%s' "$name" | tr '|' '/')" "${ok:-0}" "${tot:-0}" "$fails" >> "$f"
}

_test_run_set() {
	local urls="$1" name="$2" results="$3" detail="$4" log="$TEST_DIR/log_run.txt" res ok tot
	: > "$log"
	res=$(_test_check_all_urls "$urls" "$log")
	ok=$(echo "$res" | cut -d' ' -f1)
	tot=$(echo "$res" | cut -d' ' -f2)
	echo "${name} → ${ok}/${tot}" >> "$results"
	_test_detail_add "$detail" "$name" "$ok" "$tot" "$log"
	echo "   результат: ${ok} из ${tot}"
}

_test_domain_urls() {
	local d h
	for d in $(cat "$TEST_DIR/${1:-domain_list}" 2>/dev/null); do
		h="$(printf '%s' "$d" | sed -E 's#^[a-zA-Z]+://##; s#[/?#].*##')"
		[ -n "$h" ] && printf '%s|https://%s/\n' "$h" "$h"
	done
}

_test_hl_inject() {
	local csv
	csv="$(tr -s ' \n' ',,' < "$TEST_DIR/custom_dom_list" 2>/dev/null | sed 's/^,*//; s/,*$//')"
	[ -n "$csv" ] || { cat "$1"; return 0; }
	awk -v D="--hostlist-domains=$csv" '
		function flush(   i) { for (i = 1; i <= n; i++) print b[i]; if (hl) print D; n = 0; hl = 0 }
		$0 == "--new" { flush(); print; next }
		{ b[++n] = $0; if ($0 ~ /^--hostlist(-domains|-auto)?=/) hl = 1 }
		END { flush() }' "$1"
}

do_test_run() {
	local rc up=""
	pgrep -f "/opt/zapre[t]/" >/dev/null 2>&1 && up=1
	_do_test_run_core "$@"; rc=$?
	_test_keep "$1"
	if [ -z "$up" ] && [ -z "$ZA_IN" ] && [ -x /etc/init.d/zapret ]; then
		/etc/init.d/zapret stop >/dev/null 2>&1
		echo "==> Zapret был остановлен до теста — остановили его снова"
	fi
	return $rc
}
_do_test_run_core() {
	local mode="$1" results detail
	ZT_CTRL=""; ZT_CTRL_HIGH=""
	mkdir -p "$TEST_DIR"
	rm -f "$TEST_STOP_FLAG"
	results="$(_test_results_file "$mode")"
	detail="$(_test_detail_file "$mode")"
	: > "$results"
	printf 'T|%s\n' "$(date '+%d.%m.%Y %H:%M')" > "$detail"
	echo "$mode" > "$TEST_MODE_FILE"
	[ -f "$CONF" ] || { echo "ОШИБКА: Zapret не установлен"; return 1; }
	_test_unstale

	if [ "$mode" = "current" ]; then
		_add_gp_domains
		_refresh_exclude_file
		echo "==> Проверяем текущую стратегию, ничего не меняя"
		zapret_restart
		local urls_file="$TEST_DIR/urls.txt" dpi_urls yt_urls
		echo "==> Собираем список сайтов"
		_test_prepare_urls "$urls_file"
		dpi_urls="$(cat "$urls_file")"
		yt_urls="$(_test_yt_urls)"
		echo "==> Заблокированные сайты: $(printf '%s\n' "$dpi_urls" | grep -c '|')"
		_test_detail_domains "$detail" "$dpi_urls"
		_test_run_set "$dpi_urls" "Заблокированные сайты" "$results" "$detail"
		if [ -f "$TEST_STOP_FLAG" ]; then
			rm -f "$TEST_STOP_FLAG"
			echo "==> Тест остановлен"
			return 0
		fi
		echo "==> YouTube: $(printf '%s\n' "$yt_urls" | grep -c '|') адресов"
		_test_detail_domains "$detail" "$yt_urls"
		_test_run_set "$yt_urls" "YouTube" "$results" "$detail"
		rm -f "$TEST_STOP_FLAG"
		echo "==> Готово"
		return 0
	fi

	local urls total_domains
	case "$mode" in
		youtube|custom_yt) urls="$(_test_yt_urls)" ;;
		domain)
			urls="$(_test_domain_urls)"
			[ -n "$urls" ] || { echo "ОШИБКА: не указаны домены"; return 1; }
			;;
		custom_dom)
			urls="$(_test_domain_urls custom_dom_list)"
			[ -n "$urls" ] || { echo "ОШИБКА: не указаны домены"; return 1; }
			;;
		*)
			local urls_file="$TEST_DIR/urls.txt"
			echo "==> Собираем список сайтов"
			_test_prepare_urls "$urls_file"
			urls="$(cat "$urls_file")"
			;;
	esac
	total_domains=$(printf '%s\n' "$urls" | grep -c '|')

	mkdir -p "$ZM_STATE_DIR"
	cp "$CONF" "$TEST_BACKUP"
	_add_gp_domains
	_refresh_exclude_file

	local cand="$TEST_DIR/candidates.txt" cmode="$mode"
	[ "$mode" = domain ] && cmode=v_flowseal
	[ "$mode" = custom_dom ] && cmode=custom
	echo "==> Собираем стратегии"
	_test_build_candidates "$cmode" "$cand"
	if [ ! -s "$cand" ]; then
		echo "ОШИБКА: не удалось собрать ни одной стратегии"
		rm -f "$TEST_BACKUP"
		return 1
	fi
	local total_str
	total_str=$(grep -c '^#' "$cand")
	echo "==> Стратегий: $total_str, адресов: $total_domains"
	[ "$mode" = custom_dom ] && grep -qE '^--hostlist(-domains|-auto)?=' "$cand" && echo "==> В стратегиях есть списки сайтов — на время теста ваши сайты добавляются в них"
	_test_detail_domains "$detail" "$urls"

	echo "==> Контрольный тест: Zapret выключен"
	/etc/init.d/zapret stop >/dev/null 2>&1
	_test_run_set "$urls" "Контрольный тест (Zapret выключен)" "$results" "$detail"
	/etc/init.d/zapret start >/dev/null 2>&1
	ZT_CTRL="$(tail -n 1 "$results" | sed -n 's/.*→ \([0-9]*\)\/\([0-9]*\)$/\1 \2/p')"
	set -- $ZT_CTRL
	if [ "${2:-0}" -gt 0 ] && [ $(( ${1:-0} * 100 )) -ge $(( $2 * 80 )) ]; then
		ZT_CTRL_HIGH=1
		echo "!! Без Zapret открылось $1 из $2 — сайты доступны и так."
		echo "   Похоже, трафик самого роутера идёт через VPN или эти сайты у провайдера не блокируются — сравнение стратегий почти ничего не покажет"
	fi

	local lines
	lines=$(grep -n '^#' "$cand" | cut -d: -f1)
	echo "$lines" | awk '{ print NR, $0 }' | while read -r cur start; do
		[ -f "$TEST_STOP_FLAG" ] && break
		local next name
		next=$(echo "$lines" | awk -v s="$start" '$1>s{print;exit}')
		if [ -z "$next" ]; then sed -n "${start},\$p" "$cand" > "$TEST_DIR/block.txt"
		else sed -n "${start},$((next-1))p" "$cand" > "$TEST_DIR/block.txt"; fi
		name=$(head -n1 "$TEST_DIR/block.txt")
		name="${name#\#}"
		[ "$mode" = custom_dom ] && _test_hl_inject "$TEST_DIR/block.txt" > "$TEST_DIR/block.hl" && mv -f "$TEST_DIR/block.hl" "$TEST_DIR/block.txt"
		echo "==> [$cur/$total_str] $name"
		_test_apply_block "$(cat "$TEST_DIR/block.txt")"
		zapret_restart
		_test_run_set "$urls" "$name" "$results" "$detail"
	done

	ZT_STOPPED=""
	if [ -f "$TEST_STOP_FLAG" ]; then
		echo "==> Тест остановлен, возвращаем настройки"
		ZT_STOPPED=1
		rm -f "$TEST_STOP_FLAG"
	else
		echo "==> Тест завершён, возвращаем настройки"
	fi
	_test_sort_results "$results"
	local best
	best=$(grep -v '^Контрольный тест' "$results" | head -n1)
	[ -n "$best" ] && echo "==> Лучшая: $best"
	cp "$TEST_BACKUP" "$CONF"
	zapret_restart
	rm -f "$TEST_BACKUP"
	echo "==> Готово: настройки возвращены"
}

test_action() {
	local action="$1" mode="$2" doms="" d h
	case "$action" in
		start)
			case "$mode" in
				domain:*|custom_dom:*)
					case "$mode" in custom_dom:*) grep -q '^#' "$TEST_CUSTOM_FILE" 2>/dev/null || { echo '{"error":"список своих стратегий пуст — добавьте их и сохраните"}'; return 1; } ;; esac
					for d in $(printf '%s' "${mode#*:}" | tr ',;' '  '); do
						h="$(printf '%s' "$d" | sed -E 's#^[a-zA-Z]+://##; s#[/?#].*##' | tr 'A-Z' 'a-z')"
						printf '%s' "$h" | grep -qE '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$' || { printf '{"error":"%s"}\n' "$(esc "не похоже на домен: $d")"; return 1; }
						doms="$doms $h"
					done
					doms="$(printf '%s\n' $doms | awk '!s[$0]++' | head -n 30 | tr '\n' ' ')"
					[ -n "${doms# }" ] || { echo '{"error":"введите хотя бы один домен"}'; return 1; }
					mkdir -p "$TEST_DIR"
					case "$mode" in
						custom_dom:*) printf '%s\n' $doms > "$TEST_DIR/custom_dom_list"; mode=custom_dom ;;
						*) printf '%s\n' $doms > "$TEST_DIR/domain_list"; mode=domain ;;
					esac
					;;
				v|flowseal|v_flowseal|youtube|current) ;;
				custom|custom_yt)
					grep -q '^#' "$TEST_CUSTOM_FILE" 2>/dev/null || { echo '{"error":"список своих стратегий пуст — добавьте их и сохраните"}'; return 1; } ;;
				*) echo '{"error":"неизвестный режим теста"}'; return 1 ;;
			esac
			_test_running && { echo '{"error":"тест уже идёт"}'; return 1; }
			rm -f "$ZA_RUN"
			job_start strategy_test do_test_run "$mode"
			;;
		custom_set) test_custom_set "$mode" ;;
		ts_check) mkdir -p "$JOBS_DIR"; ts_check "$mode" ;;
		auto_set) test_auto_set "$mode" ;;
		auto_run)
			[ -f "$CONF" ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
			_test_running && { echo '{"error":"тест уже идёт"}'; return 1; }
			job_start strategy_test do_autobest
			;;
		auto_tick) test_auto_tick ;;
		auto_clear) rm -f "$ZA_LAST" "$ZA_LAST_YT" "$ZA_LOG"; test_status ;;
		stop)
			_test_running || { echo '{"error":"тест не запущен"}'; return 1; }
			mkdir -p "$TEST_DIR"
			touch "$TEST_STOP_FLAG"
			printf '{"ok":true}\n'
			;;
		clear)
			case "$mode" in
				v|flowseal|v_flowseal|youtube|current|domain|custom|custom_yt|custom_dom)
					rm -f "$(_test_results_file "$mode")" "$(_test_detail_file "$mode")" "$(_test_keep_file "$(_test_results_file "$mode")")" "$(_test_keep_file "$(_test_detail_file "$mode")")" ;;
				*) rm -f "$TEST_DIR"/results_*.txt "$TEST_DIR"/detail_*.txt "$TEST_KEEP"/results_*.txt "$TEST_KEEP"/detail_*.txt ;;
			esac
			printf '{"ok":true}\n'
			;;
		*) echo '{"error":"неизвестное действие"}' ;;
	esac
}

test_status() {
	local running="false" mode="" m has=""
	_test_recover
	_test_running && running="true"
	[ -f "$TEST_MODE_FILE" ] && mode=$(cat "$TEST_MODE_FILE")
	for m in v flowseal v_flowseal youtube current domain custom custom_yt custom_dom; do
		has="$has,\"has_results_$m\":$([ -s "$(_test_rf "$(_test_results_file "$m")")" ] && echo true || echo false)"
	done
	_za_running && mode=auto
	printf '{"running":%s,"mode":"%s","domains":"%s","custom_domains":"%s"%s,"custom":"%s","auto":%s,%s}\n' "$running" "$(esc "$mode")" "$(esc "$(cat "$TEST_DIR/domain_list" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')")" \
		"$(esc "$(cat "$TEST_DIR/custom_dom_list" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')")" "$has" \
		"$(esc_ml "$(cat "$TEST_CUSTOM_FILE" 2>/dev/null)")" "$(_za_json)" "$(_zt_json)"
}

test_results() {
	local mode="$1" f d
	f="$(_test_rf "$(_test_results_file "$mode")")"
	d="$(_test_rf "$(_test_detail_file "$mode")")"
	[ -s "$f" ] || { echo '{"lines":"","detail":""}'; return; }
	printf '{"lines":"%s","detail":"%s"}\n' "$(esc_ml "$(if [ "$(wc -c < "$f")" -gt 60000 ]; then tail -c 60000 "$f" | sed 1d; else cat "$f"; fi)")" "$(esc_ml "$(if [ "$(wc -c < "$d" 2>/dev/null || echo 0)" -gt 150000 ]; then head -n1 "$d"; tail -n +2 "$d" | tail -c 150000 | sed 1d; else cat "$d" 2>/dev/null; fi)")"
}

ZO_RKN_URL="${GH_RAW}/IndeecFOX/zapret4rocket/refs/heads/master/extra_strats/TCP/RKN/List.txt"
ZO_RKN_FILE="/opt/zapret/ipset/zapret-hosts-rkn.txt"
ZO_RKN_FLAG="$ZM_STATE_DIR/zapret_rkn"
ZO_USER_HL="--hostlist=/opt/zapret/ipset/zapret-hosts-user.txt"
ZO_EXCL_HL="--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt"
ZO_WSS="--wssize 1:6"
ZO_IPID="--ip-id=zero"
ZO_IPID_FLAG="$ZM_STATE_DIR/zapret_ipid"
ZO_YT_HL="--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt"
ZO_SCRIPT="/opt/zapret/init.d/openwrt/custom.d/50-script.sh"

_zo_rkn_on() { case "$ZM_RKN" in 1) return 0 ;; 0) return 1 ;; esac; _nfq_opt_body | grep -qxF -- "--hostlist=$ZO_RKN_FILE"; }
_zo_rkn_fits() { case "$ZM_FITS" in 1) return 0 ;; 0) return 1 ;; esac; _nfq_opt_body | grep -qxF -- "$ZO_EXCL_HL"; }

_zo_rkn_patch() {
	[ -s "$ZO_RKN_FILE" ] || return 1
	_zo_rkn_on && return 0
	_zo_rkn_fits || return 1
	[ -f /opt/zapret/ipset/zapret-hosts-user.txt ] || : > /opt/zapret/ipset/zapret-hosts-user.txt
	awk -v EX="$ZO_EXCL_HL" -v U="$ZO_USER_HL" -v R="--hostlist=$ZO_RKN_FILE" '
		/^[[:space:]]*option NFQWS_OPT \047[[:space:]]*$/ { inb = 1; print; next }
		inb && /^[[:space:]]*\047[[:space:]]*$/ { inb = 0 }
		inb && $0 == EX { print U; print R; next }
		{ print }' "$CONF" > "$CONF.zo" && mv -f "$CONF.zo" "$CONF"
	_zo_rkn_on
}

_zo_rkn_unpatch() {
	awk -v EX="$ZO_EXCL_HL" -v U="$ZO_USER_HL" -v R="--hostlist=$ZO_RKN_FILE" '
		/^[[:space:]]*option NFQWS_OPT \047[[:space:]]*$/ { inb = 1; print; next }
		inb && /^[[:space:]]*\047[[:space:]]*$/ { if (held) print U; held = 0; inb = 0; print; next }
		inb && $0 == U && !held { held = 1; next }
		inb && $0 == R { if (held) { print EX; held = 0 } next }
		inb && held { print U; held = 0 }
		{ print }' "$CONF" > "$CONF.zo" && mv -f "$CONF.zo" "$CONF"
}

ZO_USER_FLAG="$ZM_STATE_DIR/zapret_userlist"
ZO_USER_FILE="/opt/zapret/ipset/zapret-hosts-user.txt"
_zo_user_on() { [ -f "$ZO_USER_FLAG" ] && ! _zo_rkn_on && ! _zo_rkn_fits && _nfq_opt_body | grep -qxF -- "$ZO_USER_HL"; }
_zo_user_count() { sed 's/#.*//' "$ZO_USER_FILE" 2>/dev/null | awk 'NF { n++ } END { print n + 0 }'; }
_zo_user_patch() {
	local k
	_zo_rkn_on && return 1
	[ -f "$ZO_USER_FLAG" ] && [ -s "$ZO_USER_FLAG" ] && ! _zo_rkn_fits && _nfq_opt_body | grep -qxF -- "$ZO_USER_HL" && return 0
	_zo_rkn_fits || return 1
	[ -f "$ZO_USER_FILE" ] || : > "$ZO_USER_FILE"
	k="$(_nfq_opt_body | awk -v EX="$ZO_EXCL_HL" -v U="$ZO_USER_HL" '$0 == U { n++ } $0 == EX { print n + 1; exit }')"
	[ -n "$k" ] || return 1
	awk -v EX="$ZO_EXCL_HL" -v U="$ZO_USER_HL" '
		/^[[:space:]]*option NFQWS_OPT \047[[:space:]]*$/ { inb = 1; print; next }
		inb && /^[[:space:]]*\047[[:space:]]*$/ { inb = 0 }
		inb && !done && $0 == EX { print U; done = 1; next }
		{ print }' "$CONF" > "$CONF.zo" && mv -f "$CONF.zo" "$CONF"
	mkdir -p "$ZM_STATE_DIR"; echo "$k" > "$ZO_USER_FLAG"
	! _zo_rkn_fits && _nfq_opt_body | grep -qxF -- "$ZO_USER_HL"
}
_zo_user_unpatch() {
	local k
	k="$(cat "$ZO_USER_FLAG" 2>/dev/null)"
	case "$k" in ''|*[!0-9]*) return 0 ;; esac
	_zo_rkn_on && return 0
	_zo_rkn_fits && return 0
	awk -v EX="$ZO_EXCL_HL" -v U="$ZO_USER_HL" -v K="$k" '
		/^[[:space:]]*option NFQWS_OPT \047[[:space:]]*$/ { inb = 1; print; next }
		inb && /^[[:space:]]*\047[[:space:]]*$/ { inb = 0 }
		inb && $0 == U && ++n == K { print EX; next }
		{ print }' "$CONF" > "$CONF.zo" && mv -f "$CONF.zo" "$CONF"
}

_zo_wss_on() { _nfq_opt_body | grep -qxF -- "$ZO_WSS"; }

ZO_DOH_FLAG="$ZM_STATE_DIR/zapret_doh"
ZO_DOH_DEF="cloudflare-dns.com,dns.google,dns.comss.one,dns.quad9.net"
ZO_DOH_MK='^[ \t]*#[ \t]*DoH[ \t]*$'
_zo_doh_on() { case "$ZM_DOH" in 1) return 0 ;; 0) return 1 ;; esac; _nfq_opt_body | awk -v M="$ZO_DOH_MK" '$0 ~ M { f = 1 } END { exit !f }'; }
_zo_doh_hosts() {
	local x="" id c
	if _doh_fo_on; then
		c="$(_doh_fo_get chain "")"
		set -f
		for id in $([ -n "$ZO_DOH_PLAN" ] || _doh_fo_get pref "") $(IFS=,; echo $c); do x="$x $(_doh_url_of "$id")"; done
		set +f
	fi
	{ [ -n "$ZO_DOH_PLAN" ] || uci -q show https-dns-proxy 2>/dev/null; } | awk -v P="$ZO_DOH_PLAN" -v X="$x" '
		function add(u,   h) {
			if (u !~ /^https:\/\//) return
			h = tolower(u); sub(/^https:\/\//, "", h); sub(/[\/:?].*$/, "", h)
			if (h !~ /^[a-z0-9.-]*[a-z][a-z0-9.-]*$/ || (h in s)) return
			s[h] = 1; d[++n] = h
		}
		P == "" && /\.resolver_url=/ { v = $0; sub(/^[^=]*=/, "", v); gsub(/\047/, "", v); add(v); r++ }
		END {
			if (P != "") { add(P); r = 1 }
			if (!r) exit
			m = split(X, a, " ")
			for (i = 1; i <= m; i++) add(a[i])
			for (i = 1; i <= n; i++) {
				k = 0
				for (j = 1; j <= n; j++) if (j != i && length(d[i]) > length(d[j]) && substr(d[i], length(d[i]) - length(d[j])) == "." d[j]) k = 1
				if (!k) o = o (o == "" ? "" : ",") d[i]
			}
			print o
		}'
}
_zo_doh_doms() { local d; d="$(_zo_doh_hosts)"; echo "${d:-$ZO_DOH_DEF}"; }
ZO_DOH_OLD="--filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-hostfakesplit-mod=host=ya.ru --dpi-desync-hostfakesplit-midhost=host-2 --dpi-desync-split-seqovl=726 --dpi-desync-fooling=badsum,badseq --dpi-desync-badseq-increment=0"
ZO_DOH_NEW="--filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-hostfakesplit-mod=host=common.dot.dns.yandex.net --dpi-desync-hostfakesplit-midhost=host-2 --dpi-desync-split-seqovl=726 --dpi-desync-fooling=badsum,badseq --dpi-desync-badseq-increment=0"
_zo_doh_tpl() {
	local t
	t="$(grep '^--' "$ZO_DOH_FLAG" 2>/dev/null | grep -v '^--hostlist-domains=' | grep -vx -- '--new')"
	if ! printf '%s\n' "$t" | grep -q '^--filter-tcp=' || ! printf '%s\n' "$t" | grep -q '^--dpi-desync=' || [ "$(echo $t)" = "$ZO_DOH_OLD" ]; then
		t="$(printf '%s\n' $ZO_DOH_NEW)"
	fi
	printf '%s\n' "$t"
}
_zo_doh_stale() {
	[ "$(_nfq_opt_body | awk -v M="$ZO_DOH_MK" '
		$0 ~ M { c++; d = (c == 1); next }
		d && $0 == "--new" { d = 0 }
		d && /^[ \t]*--/ && !/^[ \t]*--hostlist-domains=/ { l = $0; gsub(/^[ \t]+|[ \t\r]+$/, "", l); o = o (o == "" ? "" : " ") l }
		END { print o }')" = "$ZO_DOH_OLD" ]
}
_zo_doh_scan() {
	_nfq_opt_body | awk -v M="$ZO_DOH_MK" '
		NR == 1 { next }
		$0 ~ M { c++; if (!opt) top = 1; d = (c == 1); next }
		d && $0 == "--new" { d = 0 }
		d && dom == "" && /^[ \t]*--hostlist-domains=/ { dom = $0; sub(/^[ \t]*--hostlist-domains=/, "", dom); sub(/[ \t\r]+$/, "", dom) }
		/^[ \t]*--/ && $0 != "--new" { opt = 1 }
		END { print (c == 0 ? "none" : (c == 1 && top) ? "top" : "mid") " " dom }'
}
_zo_doh_cut() {
	local f="$CONF.zdoh"
	awk -v M="$ZO_DOH_MK" -v C="${1:-/dev/null}" -v q="'" '
		!inb && /^[ \t]*option NFQWS_OPT \047[ \t]*$/ { inb = 1; n = 0; print; next }
		inb && $0 ~ ("^[ \t]*" q "[ \t]*$") {
			while (n > 0 && b[n] == "--new") n--
			for (i = 1; i <= n; i++) print b[i]
			inb = 0; d = 0; print; next
		}
		inb && $0 ~ M { d = 1; c++; next }
		inb && d && $0 == "--new" { d = 0; next }
		inb && d && /^[ \t]*#/ { b[++n] = $0; next }
		inb && d { if (c == 1) print > C; next }
		inb { if ($0 == "--new" && (n == 0 || b[n] == "--new")) next; b[++n] = $0; next }
		{ print }
		END { exit (inb ? 1 : 0) }' "$CONF" > "$f" && [ -s "$f" ] && cat "$f" > "$CONF"
	rm -f "$f"
}
_zo_doh_put() {
	local f="$CONF.zdoh"
	{ echo "#DoH"; _zo_doh_tpl | awk -v D="--hostlist-domains=$1" '!p && !/^--filter-/ { print D; p = 1 } { print } END { if (!p) print D }'; echo "--new"; } > "$f.b"
	awk -v F="$f.b" '!d && /^[ \t]*option NFQWS_OPT \047[ \t]*$/ { print; while ((getline l < F) > 0) print l; d = 1; next } { print } END { exit !d }' "$CONF" > "$f" && [ -s "$f" ] && cat "$f" > "$CONF"
	rm -f "$f" "$f.b"
}
_zo_doh_sync() {
	local doms cap
	[ -f "$ZO_DOH_FLAG" ] && [ -f "$CONF" ] || return 1
	grep -q "^[[:space:]]*option NFQWS_OPT '[[:space:]]*\$" "$CONF" || return 1
	_nochange_strategy && return 1
	doms="$(_zo_doh_doms)"
	[ "$(ZM_NFQ_BODY=""; _zo_doh_scan)" = "top $doms" ] && ! (ZM_NFQ_BODY=""; _zo_doh_stale) && return 1
	cap="$ZO_DOH_FLAG.cap"
	rm -f "$cap"
	_zo_doh_cut "$cap"
	grep -q '^--dpi-desync=' "$cap" 2>/dev/null && mv -f "$cap" "$ZO_DOH_FLAG"
	rm -f "$cap"
	_zo_doh_put "$doms"
	return 0
}
_zo_doh_follow() {
	[ -f "$ZO_DOH_FLAG" ] && [ -x /etc/init.d/zapret ] && [ -f "$CONF" ] || return 0
	_test_running && return 0
	[ -s "$TEST_BACKUP" ] && return 0
	_zo_doh_sync || return 0
	pgrep -f "/opt/zapre[t]/" >/dev/null 2>&1 || return 0
	chmod -R a+rX /opt/zapret/ipset /opt/zapret/files 2>/dev/null
	[ -x /opt/zapret/sync_config.sh ] && /opt/zapret/sync_config.sh >/dev/null 2>&1
	/etc/init.d/zapret restart >/dev/null 2>&1
	return 0
}

_yv_ipid_scan() {
	_nfq_opt_body | awk -v H="$ZO_YT_HL" -v Z="$ZO_IPID" -v S="$ZC_START_RX" -v E="$ZC_END_RX" '
		function flush() { if (yt && tcp) { n++; if (z) k++ } yt = 0; tcp = 0; z = 0 }
		{ l = $0; sub(/^[ \t]+/, "", l); sub(/[ \t\r]+$/, "", l) }
		tolower(l) ~ S { flush(); c = 1; next }
		c { if (tolower(l) ~ E) c = 0; next }
		l == "--new" { flush(); next }
		l == H { yt = 1 }
		l ~ /^--filter-tcp=/ { tcp = 1 }
		l == Z { z = 1 }
		END { flush(); print n + 0, k + 0 }'
}
_yv_ipid_on() { set -- ${ZM_YS:-$(_yv_ipid_scan)}; [ "${2:-0}" -gt 0 ]; }
_yv_ipid_want() { local w=""; [ -s "$ZO_IPID_FLAG" ] && read -r w < "$ZO_IPID_FLAG"; case "$w" in on|off) echo "$w" ;; esac; }
_yv_ipid_apply() {
	[ -f "$CONF" ] || return 1
	case "$1" in on|off) ;; *) return 1 ;; esac
	awk -v W="$1" -v H="$ZO_YT_HL" -v Z="$ZO_IPID" -v S="$ZC_START_RX" -v E="$ZC_END_RX" -v q="'" '
		function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
		function flush(   i, l, yt, tcp, put) {
			yt = 0; tcp = 0; put = 0
			for (i = 1; i <= nb; i++) { l = trim(b[i]); if (l == H) yt = 1; if (l ~ /^--filter-tcp=/) tcp = 1 }
			for (i = 1; i <= nb; i++) {
				l = trim(b[i])
				if (yt && tcp && ((W == "on" && l ~ /^--ip-id=/) || (W == "off" && l == Z))) continue
				print b[i]
				if (yt && tcp && W == "on" && l == H && !put) { print Z; put = 1 }
			}
			nb = 0
		}
		!inb && /^[ \t]*option NFQWS_OPT \047[ \t]*$/ { inb = 1; print; next }
		inb && $0 ~ ("^[ \t]*" q "[ \t]*$") { flush(); inb = 0; print; next }
		inb && !c && tolower(trim($0)) ~ S { flush(); c = 1; print; next }
		inb && c { print; if (tolower(trim($0)) ~ E) c = 0; next }
		inb && trim($0) == "--new" { flush(); print; next }
		inb { b[++nb] = $0; next }
		{ print }
		END { if (inb) exit 1 }' "$CONF" > "$CONF.ipid" && [ -s "$CONF.ipid" ] && { cmp -s "$CONF" "$CONF.ipid" || cat "$CONF.ipid" > "$CONF"; }
	rm -f "$CONF.ipid"
}
_yv_ipid_sync() {
	local w
	w="$(_yv_ipid_want)"
	[ -n "$w" ] && [ -f "$CONF" ] || return 0
	_nochange_strategy && return 0
	_yv_ipid_apply "$w"
	return 0
}

_zo_wss_add() {
	_zo_wss_on && return 0
	_nfq_opt_body | sed '1d;$d' | grep -q '^--' || return 1
	awk -v W="$ZO_WSS" '
		/^[[:space:]]*option NFQWS_OPT \047[[:space:]]*$/ { inb = 1; print; next }
		inb && /^[[:space:]]*\047[[:space:]]*$/ { print "--new"; print "--filter-tcp=443"; print W; inb = 0 }
		{ print }' "$CONF" > "$CONF.zo" && mv -f "$CONF.zo" "$CONF"
	_zo_wss_on
}

_zo_wss_del() {
	_zo_wss_on || return 0
	_nfq_drop_profiles '^--wssize 1:6$'
	case $? in 0|3) return 0 ;; esac
	return 1
}

_zo_reapply() {
	[ -f "$ZO_RKN_FLAG" ] && _zo_rkn_patch
	[ -f "$ZO_USER_FLAG" ] && [ ! -f "$ZO_RKN_FLAG" ] && _zo_user_patch
	[ -n "$1" ] && _zo_wss_add
	return 0
}

_zo_script() {
	local l
	[ -f "$ZO_SCRIPT" ] || return 0
	l="$(head -n 5 "$ZO_SCRIPT" 2>/dev/null | grep '^[[:space:]]*#' | tr -d '\r' | tr 'A-Z' 'a-z')"
	case "$l" in
		*quic*) echo quic4all ;;
		*"discord media"*) echo discord-media ;;
		*"discord subnets"*) echo discord ;;
		*stun*) echo stun4all ;;
		*) echo other ;;
	esac
}

_zo_script_url() {
	case "$1" in
		stun4all|quic4all|discord-media) echo "${GH_RAW}/bol-van/zapret/master/init.d/custom.d.examples.linux/50-$1" ;;
		discord) echo "${GH_RAW}/bol-van/zapret/v70.5/init.d/custom.d.examples.linux/50-discord" ;;
		*) return 1 ;;
	esac
}

zapret_opt_set() {
	local what="${1%%:*}" val="${1#*:}" url tmp n
	[ -x /etc/init.d/zapret ] && [ -f "$CONF" ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
	case "$what" in
		rkn)
			case "$val" in
				on)
					[ -f "$ZO_USER_FLAG" ] && { _zo_user_unpatch; rm -f "$ZO_USER_FLAG"; }
					_zo_rkn_on && { mkdir -p "$ZM_STATE_DIR"; touch "$ZO_RKN_FLAG"; status; return 0; }
					_zo_rkn_fits || { echo '{"error":"текущая стратегия не подходит для списков РКН — выберите другую"}'; return 1; }
					tmp="$ZO_RKN_FILE.zmdl"
					mkdir -p "$(dirname "$ZO_RKN_FILE")"
					rm -f "$tmp"
					if ! _zm_fetch "$ZO_RKN_URL" "$tmp" 30; then
						rm -f "$tmp"; printf '{"error":"не удалось скачать список РКН: %s"}\n' "$(esc "$ZM_FETCH_ERR")"; return 1
					fi
					n="$(grep -c '^[A-Za-z0-9*][A-Za-z0-9.*-]*\.[A-Za-z]' "$tmp" 2>/dev/null)"
					if [ "${n:-0}" -lt 100 ]; then
						rm -f "$tmp"; echo '{"error":"скачался неполный список РКН — попробуйте позже"}'; return 1
					fi
					tr -d '\r' < "$tmp" > "$ZO_RKN_FILE"; rm -f "$tmp"; chmod 644 "$ZO_RKN_FILE"
					_zo_rkn_patch || { echo '{"error":"не удалось включить списки РКН в стратегии"}'; return 1; }
					mkdir -p "$ZM_STATE_DIR"; touch "$ZO_RKN_FLAG" ;;
				off)
					rm -f "$ZO_RKN_FLAG"
					_zo_rkn_unpatch
					rm -f "$ZO_RKN_FILE" ;;
				*) echo '{"error":"неизвестное значение"}'; return 1 ;;
			esac ;;
		userlist)
			case "$val" in
				on)
					if [ -f "$ZO_RKN_FLAG" ] || _zo_rkn_on; then rm -f "$ZO_RKN_FLAG"; _zo_rkn_unpatch; rm -f "$ZO_RKN_FILE"; fi
					rm -f "$ZO_USER_FLAG"
					_zo_user_patch || { echo '{"error":"текущая стратегия не подходит для обхода по своему списку — выберите другую"}'; return 1; } ;;
				off) _zo_user_unpatch; rm -f "$ZO_USER_FLAG" ;;
				*) echo '{"error":"неизвестное значение"}'; return 1 ;;
			esac ;;
		ipid)
			case "$val" in on|off) ;; *) echo '{"error":"неизвестное значение"}'; return 1 ;; esac
			mkdir -p "$ZM_STATE_DIR"; echo "$val" > "$ZO_IPID_FLAG"
			_yv_ipid_apply "$val" || { echo '{"error":"блок стратегий Zapret (NFQWS_OPT) записан не так, как его пишет панель, — стратегия YouTube не тронута"}'; return 1; } ;;
		doh)
			_nochange_guard || return 1
			case "$val" in
				on) mkdir -p "$ZM_STATE_DIR"; [ -s "$ZO_DOH_FLAG" ] || _zo_doh_tpl > "$ZO_DOH_FLAG" ;;
				off) rm -f "$ZO_DOH_FLAG"; _zo_doh_cut ;;
				*) echo '{"error":"неизвестное значение"}'; return 1 ;;
			esac ;;
		wssize)
			case "$val" in
				on) _zo_wss_add || { echo '{"error":"не удалось добавить блок --wssize: в стратегии нет ни одного профиля"}'; return 1; } ;;
				off) _zo_wss_del || { echo '{"error":"блок стратегий Zapret (NFQWS_OPT) записан не так, как его пишет панель, — блок --wssize не тронут"}'; return 1; } ;;
				*) echo '{"error":"неизвестное значение"}'; return 1 ;;
			esac ;;
		script)
			case "$val" in
				off) rm -f "$ZO_SCRIPT" ;;
				*)
					url="$(_zo_script_url "$val")" || { echo '{"error":"неизвестный скрипт"}'; return 1; }
					tmp="$ZO_SCRIPT.zmdl"
					mkdir -p "$(dirname "$ZO_SCRIPT")"
					rm -f "$tmp"
					if ! _zm_fetch "$url" "$tmp" 30; then rm -f "$tmp"; printf '{"error":"не удалось скачать скрипт: %s"}\n' "$(esc "$ZM_FETCH_ERR")"; return 1; fi
					mv -f "$tmp" "$ZO_SCRIPT"; chmod 644 "$ZO_SCRIPT"
					_excl_enable_custom ;;
			esac ;;
		*) echo '{"error":"неизвестная настройка"}'; return 1 ;;
	esac
	zapret_restart
	status
}

TEST_CUSTOM_FILE="/root/custom_test.txt"

_test_custom_clean() { tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d'; }

test_custom_set() {
	local tmp="$TEST_CUSTOM_FILE.zmtmp" bad n
	printf '%s\n' "$1" | _test_custom_clean > "$tmp" || { rm -f "$tmp"; echo '{"error":"не удалось записать файл"}'; return 1; }
	if [ ! -s "$tmp" ]; then rm -f "$tmp" "$TEST_CUSTOM_FILE"; printf '{"ok":true,"count":0}\n'; return 0; fi
	[ "$(wc -c < "$tmp")" -le 65536 ] || { rm -f "$tmp"; echo '{"error":"слишком большой список — не больше 64 КБ"}'; return 1; }
	head -n 1 "$tmp" | grep -q '^#' || { rm -f "$tmp"; echo '{"error":"каждая стратегия начинается со строки #Название — первая строка должна быть такой"}'; return 1; }
	bad="$(grep -v '^#' "$tmp" | grep -v '^--' | head -n 1)"
	[ -z "$bad" ] || { rm -f "$tmp"; printf '{"error":"%s"}\n' "$(esc "строка не похожа на параметр nfqws (должна начинаться с --): $bad")"; return 1; }
	grep -q "'" "$tmp" && { rm -f "$tmp"; echo "{\"error\":\"одинарные кавычки ' в стратегиях нельзя — они ломают конфиг Zapret\"}"; return 1; }
	bad="$(awk '/^#/ { if (name != "" && !opts) { print name; exit } name = $0; opts = 0; next } { opts = 1 } END { if (name != "" && !opts) print name }' "$tmp" | head -n 1)"
	[ -z "$bad" ] || { rm -f "$tmp"; printf '{"error":"%s"}\n' "$(esc "у стратегии $bad нет ни одного параметра")"; return 1; }
	n="$(grep -c '^#' "$tmp")"
	mv -f "$tmp" "$TEST_CUSTOM_FILE"; chmod 600 "$TEST_CUSTOM_FILE"
	printf '{"ok":true,"count":%s}\n' "$n"
}

ZA_TAG="# zm-autobest"
ZA_MODE_FILE="$ZM_STATE_DIR/autobest.mode"
ZA_LAST="$ZM_STATE_DIR/autobest.last"
ZA_RUN="$TEST_DIR/autobest"
ZA_TS="$ZM_STATE_DIR/autobest.ts"

ZA_YT_FILE="$ZM_STATE_DIR/autobest.yt"
ZA_LAST_YT="$ZM_STATE_DIR/autobest.last_yt"
_za_mode() { case "$(cat "$ZA_MODE_FILE" 2>/dev/null)" in v) echo v ;; flowseal) echo flowseal ;; youtube) echo youtube ;; *) echo v_flowseal ;; esac; }
_za_yt() { [ -f "$ZA_YT_FILE" ]; }
ZA_TIME_FILE="$ZM_STATE_DIR/autobest.time"
_za_time() { grep -F "$ZA_TAG" "$CRON_FILE" 2>/dev/null | head -n 1 | awk '{ printf "%02d:%02d\n", $2, $1 }'; }
_za_running() { [ -f "$ZA_RUN" ] && _test_running; }

_za_extras_save() {
	ZA_YV="$(grep -oE '^#[[:space:]]*Yv[0-9]+$' "$CONF" | head -n1 | sed 's/^#[[:space:]]*//')"
	ZA_DV="$(grep -oE '^#[[:space:]]*Dv[0-9]+$' "$CONF" | head -n1 | sed 's/^#[[:space:]]*Dv//')"
	ZA_GV="$(grep -oE '^#Gv[1-4](Xtreme)?$' "$CONF" | head -n1 | sed 's/^#Gv//; s/Xtreme$//')"
	ZA_XT=""; grep -q "^#Gv[0-9]\+Xtreme\$" "$CONF" && ZA_XT=1
	ZA_YOFF=""; [ -f "$YV_OFF_FLAG" ] && ZA_YOFF=1
	ZA_DOFF=""; [ -f "$DV_OFF_FLAG" ] && ZA_DOFF=1
	ZA_GACT=""; _game_active && ZA_GACT=1
	return 0
}
_za_extras_restore() {
	local said=""
	ZM_NO_RESTART=1
	if [ -n "$ZA_YOFF" ]; then
		strategy_set_youtube off >/dev/null 2>&1 && said="$said, YouTube выключен"
	elif [ -n "$ZA_YV" ]; then
		[ -s "$(_yv_file)" ] || do_yv_download >/dev/null 2>&1
		if [ -s "$(_yv_file)" ] && grep -qxF "#$ZA_YV" "$(_yv_file)"; then
			case "$(strategy_set_youtube "$ZA_YV" 2>/dev/null)" in *'"ok":true'*) said="$said, YouTube $ZA_YV" ;; *) echo "!! Не удалось вернуть стратегию YouTube $ZA_YV" ;; esac
		else
			echo "!! Стратегии YouTube $ZA_YV нет в списке — YouTube остаётся от Flowseal"
		fi
	fi
	if [ -n "$ZA_DOFF" ]; then
		discord_set_dv off >/dev/null 2>&1 && said="$said, Discord выключен"
	elif [ -n "$ZA_DV" ]; then
		case "$(discord_set_dv "$ZA_DV" 2>/dev/null)" in *'"ok":true'*) said="$said, Discord Dv$ZA_DV" ;; *) echo "!! Не удалось вернуть стратегию Discord Dv$ZA_DV" ;; esac
	fi
	if [ -n "$ZA_GV" ]; then
		case "$(game_set "$ZA_GV" 2>/dev/null)" in
			*'"ok":true'*)
				said="$said, игры Gv$ZA_GV"
				[ -n "$ZA_XT" ] && ! grep -q "^#Gv[0-9]\+Xtreme\$" "$CONF" && game_toggle_xtreme >/dev/null 2>&1 && said="$said Xtreme" ;;
			*) echo "!! Не удалось вернуть игровую стратегию Gv$ZA_GV" ;;
		esac
	elif [ -z "$ZA_GACT" ] && _game_active; then
		game_set off >/dev/null 2>&1 && said="$said, игровая часть выключена, как было"
	fi
	ZM_NO_RESTART=""
	_nfq_normalize
	zapret_restart
	[ -n "$said" ] && echo "   оставили ваши настройки: ${said#, }"
	return 0
}

ZA_LOG="$ZM_STATE_DIR/autobest.log"
_za_last_write() {
	local l
	mkdir -p "$ZM_STATE_DIR"
	l="$(printf '%s|%s|%s|%s|%s|%s|%s|%s' "$(date +%s)" "$1" "$2" "$3" "$4" "$5" "$6" "$7" | tr -d '\n\r')"
	printf '%s\n' "$l" > "${ZA_LAST_TO:-$ZA_LAST}"
	printf '%s|%s\n' "$l" "$([ -n "$ZA_LAST_TO" ] && echo yt || echo main)" >> "$ZA_LOG"
	tail -n 5 "$ZA_LOG" > "$ZA_LOG.t" 2>/dev/null && mv -f "$ZA_LOG.t" "$ZA_LOG"
}
_za_need() { local n=$(( ${1:-0} * 5 / 100 )); [ "$n" -lt 2 ] && n=2; echo "$n"; }

do_autobest() {
	local mode rc=0 up=""
	pgrep -f "/opt/zapre[t]/" >/dev/null 2>&1 && up=1
	ZA_IN=1
	_do_autobest_core; rc=$?
	ZA_IN=""
	if [ -z "$up" ] && [ -x /etc/init.d/zapret ]; then
		/etc/init.d/zapret stop >/dev/null 2>&1
		echo "==> Zapret был остановлен до автоподбора — остановили его снова"
	fi
	return $rc
}
_do_autobest_core() {
	local mode rc=0
	mode="$(_za_mode)"
	mkdir -p "$TEST_DIR"; : > "$ZA_RUN"
	echo "==> Автоподбор стратегии: $(case "$mode" in v) echo v1–v10 ;; flowseal) echo Flowseal ;; youtube) echo 'только YouTube (Yv)' ;; *) echo 'v + Flowseal' ;; esac)$([ "$mode" != youtube ] && _za_yt && echo ', затем YouTube (Yv)')"
	[ -f "$CONF" ] || { echo "ОШИБКА: Zapret не установлен"; rm -f "$ZA_RUN"; return 1; }
	_test_unstale
	rm -f "$ZA_LAST_YT"
	if _nochange_strategy; then
		echo "==> Включено «Не изменять стратегию» (#nochange) — автоподбор ничего не меняет"
		_za_last_write "$mode" "" 0 0 0 "" nochange; rm -f "$ZA_RUN"; return 0
	fi
	ZT_STOPPED=""
	if [ "$mode" = youtube ]; then
		_za_youtube; rc=$?
	else
		_za_main "$mode"; rc=$?
		if [ "$rc" = 0 ] && [ -z "$ZT_STOPPED" ] && _za_yt; then
			ZA_LAST_TO="$ZA_LAST_YT"; _za_youtube; ZA_LAST_TO=""
		fi
	fi
	rm -f "$ZA_RUN"
	return "$rc"
}

_za_youtube() {
	local res best yname yok ytot cur cok ctot r applied=0
	echo "==> YouTube: подбираем стратегию Yv"
	if [ -f "$YV_OFF_FLAG" ]; then
		echo "   YouTube выключен в стратегии — его настройку не трогаем"
		_za_last_write youtube "" 0 0 0 "" yoff; return 0
	fi
	if _nochange_strategy; then
		echo "==> Включено «Не изменять стратегию» (#nochange) — YouTube не трогаем"
		_za_last_write youtube "" 0 0 0 "" nochange; return 0
	fi
	cur="$(grep -oE '^#[[:space:]]*Yv[0-9]+$' "$CONF" | head -n1 | sed 's/^#[[:space:]]*//')"
	do_test_run youtube || { _za_last_write youtube "" 0 0 0 "$cur" error; return 1; }
	res="$(_test_results_file youtube)"
	best="$(grep -v '^Контрольный тест' "$res" 2>/dev/null | head -n 1)"
	if [ -z "$best" ] || [ -n "$ZT_STOPPED" ]; then
		echo "==> YouTube: лучшую стратегию определить не удалось — оставляем текущую"
		_za_last_write youtube "" 0 0 0 "$cur" none; return 0
	fi
	yname="$(printf '%s' "$best" | sed 's/[[:space:]]*→.*$//')"
	yok="$(printf '%s' "$best" | sed -n 's/.*→[[:space:]]*\([0-9]*\)\/\([0-9]*\).*/\1/p')"
	ytot="$(printf '%s' "$best" | sed -n 's/.*→[[:space:]]*\([0-9]*\)\/\([0-9]*\).*/\2/p')"
	if [ -n "$ZT_CTRL_HIGH" ]; then
		echo "==> YouTube открывается и без Zapret — стратегию YouTube не меняем"
		_za_last_write youtube "$yname" "$yok" "$ytot" "${ZT_CTRL%% *}" "$cur" ctrl; return 0
	fi
	echo "==> Проверяем текущую настройку YouTube (${cur:-из основной стратегии}) на тех же адресах"
	r="$(_test_check_all_urls "$(_test_yt_urls)" "$TEST_DIR/log_cur_yt.txt")"
	cok="${r% *}"; ctot="${r#* }"
	echo "   текущая: ${cok}/${ctot}, лучшая из теста: $yname — ${yok}/${ytot}"
	if [ "$yname" != "$cur" ] && [ "${yok:-0}" -gt "${cok:-0}" ] 2>/dev/null && [ $(( ${yok:-0} - ${cok:-0} )) -lt "$(_za_need "$ytot")" ]; then
		echo "==> $yname лучше всего на $(( yok - cok )) — это в пределах погрешности, оставляем текущую (нужно не меньше $(_za_need "$ytot"))"
		_za_last_write youtube "$yname" "$yok" "$ytot" "$cok" "$cur" close; return 0
	fi
	if [ "$yname" != "$cur" ] && [ "${yok:-0}" -gt "${cok:-0}" ] 2>/dev/null; then
		if _nochange_strategy; then
			echo "==> Пока шёл тест, включили «Не изменять стратегию» — ничего не меняем"
			_za_last_write youtube "$yname" "$yok" "$ytot" "$cok" "$cur" nochange; return 0
		fi
		echo "==> Применяем $yname для YouTube"
		_zc_lift
		r="$(strategy_set_youtube "$yname" 2>/dev/null)"
		_zc_drop
		case "$r" in *'"ok":true'*) applied=1; echo "==> Готово: стратегия YouTube $yname применена" ;; *) echo "!! Не удалось применить $yname — YouTube оставлен как был" ;; esac
		if [ "$applied" = 1 ] && _nfq_opt_body | _ts_has; then
			date +%s > "$ZA_TS"
			echo "   ! в стратегии есть метка ts — на компьютерах с Windows нужно один раз выполнить:"
			echo "     netsh int tcp set global timestamps=enabled  (в терминале от имени администратора)"
		fi
		[ "$applied" = 1 ] && logger -t zapret-manager "Автоподбор: для YouTube применена $yname ($yok/$ytot, было $cok/$ctot)"
	else
		echo "==> Текущая настройка YouTube не хуже — оставляем её"
	fi
	_za_last_write youtube "$yname" "$yok" "$ytot" "$cok" "$cur" "$([ "$applied" = 1 ] && echo applied || echo kept)"
	return 0
}

_za_main() {
	local mode="$1" res best bname bok btot cok ctot cname urls applied=0 r
	cname="$(_nfq_names | sed 's/^#[[:space:]]*//' | grep -viE '^(udp443|DoH|nochange|Yv[0-9]+|Dv[0-9]+|Gv[0-9]+.*)$' | head -n 1)"
	[ -n "$cname" ] || cname="$(grep -m1 '^# ZMFS:' "$CONF" | sed 's/^# ZMFS://')"
	do_test_run "$mode" || { _za_last_write "$mode" "" 0 0 0 "" error; return 1; }
	res="$(_test_results_file "$mode")"
	best="$(grep -v '^Контрольный тест' "$res" 2>/dev/null | head -n 1)"
	if [ -z "$best" ] || [ -n "$ZT_STOPPED" ]; then
		echo "==> Лучшую стратегию определить не удалось — оставляем текущую"
		_za_last_write "$mode" "" 0 0 0 "" none; return 0
	fi
	bname="$(printf '%s' "$best" | sed 's/[[:space:]]*→.*$//')"
	bok="$(printf '%s' "$best" | sed -n 's/.*→[[:space:]]*\([0-9]*\)\/\([0-9]*\).*/\1/p')"
	btot="$(printf '%s' "$best" | sed -n 's/.*→[[:space:]]*\([0-9]*\)\/\([0-9]*\).*/\2/p')"
	if [ -n "$ZT_CTRL_HIGH" ]; then
		echo "==> Сайты открываются и без Zapret — стратегию не меняем"
		_za_last_write "$mode" "$bname" "$bok" "$btot" "${ZT_CTRL%% *}" "$cname" ctrl; return 0
	fi
	echo "==> Проверяем текущую стратегию${cname:+ ($cname)} на тех же сайтах"
	urls="$(cat "$TEST_DIR/urls.txt" 2>/dev/null)"
	r="$(_test_check_all_urls "$urls" "$TEST_DIR/log_cur.txt")"
	cok="${r% *}"; ctot="${r#* }"
	echo "   текущая: ${cok}/${ctot}, лучшая из теста: $bname — ${bok}/${btot}"
	if [ "${bok:-0}" -gt "${cok:-0}" ] 2>/dev/null && [ $(( ${bok:-0} - ${cok:-0} )) -lt "$(_za_need "$btot")" ]; then
		echo "==> $bname лучше всего на $(( bok - cok )) — это в пределах погрешности, оставляем текущую (нужно не меньше $(_za_need "$btot"))"
		_za_last_write "$mode" "$bname" "$bok" "$btot" "$cok" "$cname" close; return 0
	fi
	if [ "${bok:-0}" -gt "${cok:-0}" ] 2>/dev/null; then
		if _nochange_strategy; then
			echo "==> Пока шёл тест, включили «Не изменять стратегию» — ничего не меняем"
			_za_last_write "$mode" "$bname" "$bok" "$btot" "$cok" "$cname" nochange; return 0
		fi
		echo "==> Применяем $bname"
		_zc_has && echo "   · свой блок #CustomStart … #CustomEnd сохраняем — он останется в самом верху стратегии"
		_zc_lift
		case "$bname" in
			v[1-9]|v10) r="$(strategy_set_v "$bname")" ;;
			*)
				_za_extras_save
				r="$(ZM_NO_RESTART=1 strategy_set_flowseal "$bname")"
				case "$r" in *'"ok":true'*) _za_extras_restore ;; *) zapret_restart ;; esac ;;
		esac
		_zc_drop
		case "$r" in *'"ok":true'*) applied=1; echo "==> Готово: основная стратегия $bname применена" ;; *) echo "!! Не удалось применить $bname — оставлена текущая" ;; esac
		if [ "$applied" = 1 ] && _nfq_opt_body | _ts_has; then
			date +%s > "$ZA_TS"
			echo "   ! в стратегии есть метка ts — на компьютерах с Windows нужно один раз выполнить:"
			echo "     netsh int tcp set global timestamps=enabled  (в терминале от имени администратора)"
		fi
		logger -t zapret-manager "Автоподбор: применена стратегия $bname ($bok/$btot, было $cok/$ctot)"
	else
		echo "==> Текущая стратегия не хуже — оставляем её"
	fi
	_za_last_write "$mode" "$bname" "$bok" "$btot" "$cok" "$cname" "$([ "$applied" = 1 ] && echo applied || echo kept)"
	return 0
}

test_auto_set() {
	local when="${1%%|*}" mode="${1#*|}" yt="" h m
	case "$mode" in *'|'*) yt="${mode#*|}"; mode="${mode%%|*}" ;; esac
	case "$mode" in v|flowseal|v_flowseal|youtube) ;; *) mode="$(_za_mode)" ;; esac
	case "$when" in
		off) ;;
		[0-9]:[0-5][0-9]|[01][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9])
			[ -x /etc/init.d/zapret ] || { echo '{"error":"Zapret не установлен"}'; return 1; }
			h="${when%%:*}"; m="${when#*:}"; h="${h#0}"; m="${m#0}" ;;
		*) echo '{"error":"неверное время"}'; return 1 ;;
	esac
	mkdir -p "$ZM_STATE_DIR"; echo "$mode" > "$ZA_MODE_FILE"
	case "$yt" in on) : > "$ZA_YT_FILE" ;; off) rm -f "$ZA_YT_FILE" ;; esac
	mkdir -p "$(dirname "$CRON_FILE")"; touch "$CRON_FILE"
	sed -i "\\|$ZA_TAG|d" "$CRON_FILE"
	if [ "$when" != off ]; then
		echo "${m:-0} ${h:-0} * * * /opt/zapret-manager-luci/backend.sh test_action auto_tick x >/dev/null 2>&1 $ZA_TAG" >> "$CRON_FILE"
		printf '%02d:%02d\n' "${h:-0}" "${m:-0}" > "$ZA_TIME_FILE"
	fi
	/etc/init.d/cron enable >/dev/null 2>&1
	/etc/init.d/cron restart >/dev/null 2>&1
	test_status
}

test_auto_tick() {
	[ -x /etc/init.d/zapret ] && [ -f "$CONF" ] || return 0
	pgrep -f "/opt/zapre[t]/" >/dev/null 2>&1 || return 0
	[ "$(date +%Y)" -ge 2024 ] 2>/dev/null || return 0
	_test_running && return 0
	if _au_live || _zm_busy_job >/dev/null 2>&1; then
		[ -n "$ZA_WAITED" ] && return 0
		( ZA_WAITED=1; w=0
		  while { _au_live || _zm_busy_job >/dev/null 2>&1; } && [ "$w" -lt 3600 ]; do sleep 30; w=$((w + 30)); done
		  test_auto_tick ) >/dev/null 2>&1 </dev/null &
		return 0
	fi
	job_start strategy_test do_autobest >/dev/null
}

_za_last_json() { _za_line_json "$(head -n 1 "$1" 2>/dev/null)"; }
_za_line_json() {
	local last="$1" at m b bo bt co cn res kind
	[ -n "$last" ] || { echo null; return 0; }
	IFS='|' read -r at m b bo bt co cn res kind <<-ZA_EOF
	$last
	ZA_EOF
	printf '{"kind":"%s","at":%s,"mode":"%s","best":"%s","best_ok":%s,"total":%s,"cur_ok":%s,"cur":"%s","result":"%s"}' "$(esc "${kind:-main}")" \
		"$(printf '%s' "$at" | tr -cd 0-9 | grep . || echo 0)" "$(esc "$m")" "$(esc "$b")" "$(printf '%s' "$bo" | tr -cd 0-9 | grep . || echo 0)" \
		"$(printf '%s' "$bt" | tr -cd 0-9 | grep . || echo 0)" "$(printf '%s' "$co" | tr -cd 0-9 | grep . || echo 0)" "$(esc "$cn")" "$(esc "$res")"
}

_za_json() {
	local h last lasty
	h="$(_za_time)"
	last="$(_za_last_json "$ZA_LAST")"
	lasty="$(_za_last_json "$ZA_LAST_YT")"
	local log="" sep="" l
	if [ -s "$ZA_LOG" ]; then
		while IFS= read -r l; do [ -n "$l" ] && { log="$(_za_line_json "$l")$sep$log"; sep=","; }; done < "$ZA_LOG"
	fi
	local tsat="" tsp="" l
	tsat="$(cat "$ZA_TS" 2>/dev/null | tr -cd 0-9)"
	if [ -n "$tsat" ] && [ -f "$CONF" ]; then
		for l in $(_nfq_opt_body | _ts_parts | tr ' ' '_'); do tsp="$tsp${tsp:+,}\"$(esc "$(printf '%s' "$l" | tr '_' ' ')")\""; done
		[ -n "$tsp" ] || tsat=""
	fi
	printf '{"time":"%s","pref":"%s","mode":"%s","yt":%s,"running":%s,"last":%s,"last_yt":%s,"log":[%s],"ts_at":%s,"ts_parts":[%s]}' "$h" "$(cat "$ZA_TIME_FILE" 2>/dev/null || echo 04:00)" "$(_za_mode)" "$(_za_yt && echo true || echo false)" "$(_za_running && echo true || echo false)" "$last" "$lasty" "$log" "${tsat:-0}" "$tsp"
}

ZT_NTP_IP="89.109.251.21 89.109.251.22 162.159.200.1 162.159.200.123 216.239.35.0 216.239.35.4"
_zt_ntp_list() { uci -q get system.ntp.server 2>/dev/null | tr -s ' \t' '  ' | sed 's/^ //; s/ $//'; }
_zt_ntp_preset() {
	local l="$1"
	[ -n "$l" ] || { echo none; return 0; }
	[ "$l" = "$ZT_NTP_IP" ] && { echo ip; return 0; }
	printf '%s\n' $l | grep -qv 'pool\.ntp\.org$' && echo own || echo std
}

_zt_json() {
	local l
	set -- $(date '+%s %z %d.%m.%Y %H:%M:%S')
	l="$(_zt_ntp_list)"
	printf '"time":%s,"time_text":"%s","zone":"%s","utc_offset":"%s","ntp":%s,"ntp_preset":"%s","ntp_servers":"%s","dnsm":%s' \
		"$1" "$3 $4" "$(esc "$(uci -q get system.@system[0].zonename)")" "$2" \
		"$([ "$(uci -q get system.ntp.enabled)" = 0 ] && echo false || echo true)" \
		"$(_zt_ntp_preset "$l")" "$(esc "$l")" "$(_dnsm_present && echo true || echo false)"
}

_zm_gh_get() { _zm_fetch "$1" "$2" "${4:-120}" "$3"; }

_zm_panel_latest() {
	local f="$JOBS_DIR/zm_head.$$" v
	mkdir -p "$JOBS_DIR"
	_zm_gh_get "$ZM_SCRIPT_URL" "$f" 0-400 8 || { rm -f "$f"; return 1; }
	v="$(grep -m1 '^# Version:' "$f" | sed 's/^# Version:[[:space:]]*//' | tr -d '\r ')"
	rm -f "$f"
	echo "$v" | grep -qE '^[0-9]+(\.[0-9]+)*$' && echo "$v"
}

_zm_newer() { [ -n "$1" ] && _zm_ver_lt "$ZM_VERSION" "$1"; }

zm_update_status() {
	local latest
	if [ -z "$ZM_VER_FORCE" ] && [ "$(_ver_mode)" != open ]; then latest="$(ZM_VER_LOCAL=1 _zm_cached_first panel _zm_panel_latest)"
	else latest="$(_zm_cached_first panel _zm_panel_latest)"; fi
	printf '{"current":"%s","latest":"%s","newer":%s}\n' "$(esc "$ZM_VERSION")" "$(esc "$latest")" "$(_zm_newer "$latest" && echo true || echo false)"
}

ZM_CL_FILE="/opt/zapret-manager-luci/CHANGELOG.md"
ZM_CL_PENDING="$ZM_STATE_DIR/cl.pending"
ZM_CL_URLS="${GH_RAW}/Screamshow/Zapret-Manager/refs/heads/main/CHANGELOG.md https://cdn.jsdelivr.net/gh/Screamshow/Zapret-Manager@main/CHANGELOG.md"

_zm_cl_get() {
	local out="$1" u
	for u in $ZM_CL_URLS; do
		rm -f "$out"
		_zm_gh_get "$u" "$out" "" 12 && _zm_dl_sane "$out" && [ "$(wc -c < "$out")" -le 262144 ] && return 0
	done
	rm -f "$out"
	return 1
}

_zm_cl_top() {
	if grep -q '^## ' "$1" 2>/dev/null; then
		awk '/^## / { if (s) exit; s = 1 } s && !/^---[[:space:]]*$/' "$1"
	else
		grep -v '^---[[:space:]]*$' "$1"
	fi | tr -d '\r' | head -n 80
}

_zm_cl_sync() {
	local t="$ZM_CL_FILE.dl"
	mkdir -p "$(dirname "$ZM_CL_FILE")"
	if _zm_cl_get "$t"; then mv -f "$t" "$ZM_CL_FILE"; chmod 644 "$ZM_CL_FILE"; echo '{"ok":true}'
	else rm -f "$t"; echo '{"ok":false}'; fi
}

zm_changelog() {
	local mode="$1" f blk="" ver="" date="" from="" pending=false
	case "$mode" in
		local)
			[ -f "$ZM_CL_PENDING" ] || { printf '{"pending":false,"current":"%s"}\n' "$(esc "$ZM_VERSION")"; return 0; }
			pending=true
			from="$(head -n 1 "$ZM_CL_PENDING" | tr -cd '0-9.')"
			f="$ZM_CL_FILE" ;;
		remote)
			f="$JOBS_DIR/changelog.md"
			if [ ! -s "$f" ] || [ -n "$(find "$f" -mmin +10 2>/dev/null)" ]; then
				mkdir -p "$JOBS_DIR"
				if _zm_cl_get "$f.dl"; then mv -f "$f.dl" "$f"; else rm -f "$f.dl"; fi
			fi
			[ -s "$f" ] || { echo '{"error":"не удалось скачать список изменений с GitHub"}'; return 1; } ;;
		all)
			f="$JOBS_DIR/changelog.md"
			if [ ! -s "$f" ] || [ -n "$(find "$f" -mmin +10 2>/dev/null)" ]; then
				mkdir -p "$JOBS_DIR"
				if _zm_cl_get "$f.dl"; then mv -f "$f.dl" "$f"; else rm -f "$f.dl"; fi
			fi
			blk=github
			[ -s "$f" ] || { f="$ZM_CL_FILE"; blk=local; }
			[ -s "$f" ] || { echo '{"error":"список изменений не загрузился: нет связи с GitHub, а сохранённой копии на роутере пока нет"}'; return 1; }
			printf '{"current":"%s","source":"%s","text":"%s"}\n' "$(esc "$ZM_VERSION")" "$blk" \
				"$(esc_ml "$(grep -v '^---[[:space:]]*$' "$f" | tr -d '\r' | head -n 600)")"
			return 0 ;;
		seen) rm -f "$ZM_CL_PENDING"; echo '{"ok":true}'; return 0 ;;
		*) echo '{"error":"неизвестный режим"}'; return 1 ;;
	esac
	[ -s "$f" ] && blk="$(_zm_cl_top "$f")"
	ver="$(printf '%s\n' "$blk" | sed -n '/[^[:space:]]/{p;q;}' | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)"
	date="$(printf '%s\n' "$blk" | sed -n '/[^[:space:]]/{p;q;}' | grep -oE '[0-9]{2}\.[0-9]{2}\.[0-9]{4}' | head -n 1)"
	printf '{"pending":%s,"from":"%s","current":"%s","version":"%s","date":"%s","text":"%s"}\n' \
		"$pending" "$(esc "$from")" "$(esc "$ZM_VERSION")" "$(esc "$ver")" "$(esc "$date")" "$(esc_ml "$blk")"
}

_zm_update_fetch() {
	rm -f "$1"
	_zm_gh_get "$ZM_SCRIPT_URL" "$1" || { echo "не удалось скачать установщик через зеркало и GitHub"; return 1; }
	head -n1 "$1" | grep -qx '#!/bin/sh' || { echo "скачанный файл не похож на установщик (возможно, вместо него пришла страница-заглушка)"; return 1; }
	grep -q '^# Version:' "$1" || { echo "в установщике нет номера версии"; return 1; }
	tail -n 5 "$1" | grep -q 'Web UI:' || { echo "установщик скачался не полностью — попробуйте ещё раз"; return 1; }
	sh -n "$1" 2>/dev/null || { echo "установщик повреждён — установка отменена"; return 1; }
	return 0
}

_zm_job_label() {
    case "$1" in
        term) echo "Терминал" ;;
        install_zapret2|remove_zapret2) echo "Zapret2" ;;
        install_zapret|remove_zapret) echo "Zapret" ;;
        strategy_test) echo "тест стратегий" ;;
        zm_update) echo "обновление панели" ;;
        au_*) echo "автообновление" ;;
        *) echo "$1" ;;
    esac
}

_zm_busy_job() {
	local f j
	for f in "$JOBS_DIR"/*.pid; do
		[ -f "$f" ] || continue
		j="$(basename "$f" .pid)"
		case "$j" in versions|*_download) continue ;; esac
		_job_running "$j" && { _zm_job_label "$j"; return 0; }
	done
	return 1
}

zm_update_action() {
	local j
	if j="$(_zm_busy_job)"; then
		printf '{"error":"%s"}\n' "$(esc "идёт операция «$j» — дождитесь её окончания и обновите панель")"
		return 1
	fi
	job_start zm_update do_zm_update
}

do_zm_update() {
	local tmp="/tmp/zm_update_install.sh" why v
	echo "==> Скачиваем новую версию панели с GitHub"
	if ! why="$(_zm_update_fetch "$tmp")"; then
		rm -f "$tmp"
		echo "ОШИБКА: $why"
		return 1
	fi
	v="$(grep -m1 '^# Version:' "$tmp" | sed 's/^# Version:[[:space:]]*//' | tr -d '\r ')"
	echo "   ✓ Установщик скачан и проверен: версия $v"
	chmod +x "$tmp"
	rm -f "$ZM_STATE_DIR/latest.panel"
	echo "==> Запускаем установку — панель на полминуты пропадёт"
	( sleep 5; sh "$tmp" >/tmp/zm_update_install.log 2>&1; rm -f "$tmp" ) >/dev/null 2>&1 </dev/null &
	return 0
}

_zm_cached() {
	local f="$ZM_STATE_DIR/latest.$1" v age=360
	[ "$1" = panel ] && age=60
	shift
	if [ -n "$ZM_VER_LOCAL" ]; then cat "$f" 2>/dev/null; return 0; fi
	mkdir -p "$ZM_STATE_DIR"
	if [ -n "$ZM_VER_FORCE" ]; then
		v="$("$@")"
		[ -n "$v" ] && echo "$v" > "$f"
	elif [ ! -s "$f" ] || [ -n "$(find "$f" -mmin +$age 2>/dev/null)" ]; then
		if mkdir "$f.lock" 2>/dev/null; then
			( v="$("$@")"; [ -n "$v" ] && echo "$v" > "$f"; rmdir "$f.lock" ) >/dev/null 2>&1 &
		elif [ -n "$(find "$f.lock" -mmin +2 2>/dev/null)" ]; then
			rmdir "$f.lock" 2>/dev/null
		fi
	fi
	cat "$f" 2>/dev/null
}
_zm_cached_first() {
	local f="$ZM_STATE_DIR/latest.$1"
	[ -n "$ZM_VER_LOCAL" ] && { cat "$f" 2>/dev/null; return 0; }
	if [ -s "$f" ] || { [ -f "$f.try" ] && [ -z "$(find "$f.try" -mmin +10 2>/dev/null)" ]; }; then
		_zm_cached "$@"
	else
		mkdir -p "$ZM_STATE_DIR"; : > "$f.try"
		ZM_VER_FORCE=1 _zm_cached "$@"
	fi
}

health() {
local zr=0 zr2=0 hs=0 term=0 fw=false v6=false out
    if [ -f /etc/init.d/zapret ]; then zr=4; pgrep -f "/opt/zapre[t]/" >/dev/null 2>&1 && zr=1; fi
    if [ -f /etc/init.d/zapret2 ]; then zr2=4; /etc/init.d/zapret2 status >/dev/null 2>&1 && zr2=1; fi
    out="$(hosts_status)"
    case "$out" in *'"enabled":true'*|*'"geohide":"'[a-z]*) hs=1 ;; esac
    if _term_installed; then
        if _term_running; then term=1; elif _term_enabled; then term=2; else term=4; fi
    fi
    _fw4_offload_on && [ -f "$FW4_TPL" ] && [ ! -f "$FT_ZAPRET_OFF" ] && { [ -x /etc/init.d/zapret ] || [ -x /etc/init.d/zapret2 ]; } && [ "$(_flow_offloading_fix_applied)" = false ] && fw=true
    [ -f "$CONF" ] && [ "$(_ipv6_enabled_in_zapret)" = false ] && [ "$(_zm_v6_cached)" = live ] && v6=true
    printf '{"dots":{"zapret":%s,"zapret2":%s,"hosts":%s,"term":%s},"zapret":%s,"zapret2":%s,"hosts":%s,"flow_warn":%s,"ipv6_warn":%s,"gh_warn":%s,"reboot_hint":"%s","nav_hidden":"%s"}\n' \
        "$zr" "$zr2" "$hs" "$term" "$zr" "$zr2" "$hs" "$fw" "$v6" "$(_zm_ghp_warn && echo true || echo false)" "$(esc "$(_zm_reboot_hint_get)")" "$(esc "$(ui_nav_get)")"
}

VERSIONS_CACHE="$ZM_STATE_DIR/versions.json"

_ver_norm() { printf '%s' "$1" | sed 's/^[vV]//; s/-r[0-9]*$//; s/[[:space:]]//g'; }

_ver_feed_latest() {
	if [ "$PKG" = apk ]; then
		apk list "$1" 2>/dev/null | sed -n "s/^$1-\([0-9][^ ]*\) .*/\1/p" | head -n1
	else
		opkg list "$1" 2>/dev/null | awk -v p="$1" '$1 == p { v = $3 } END { print v }'
	fi
}

_ver_old() { [ -s "$ZM_VER_OLD" ] && ZM_N="$1" awk -F'\t' '$1 == ENVIRON["ZM_N"] { print $2; exit }' "$ZM_VER_OLD"; }
_ver_item() {
	local cur latest
	cur="$(_ver_norm "$2")"; latest="$(_ver_norm "$3")"
	[ -n "$cur" ] || return 0
	[ -n "$latest" ] || latest="$(_ver_norm "$(_ver_old "$1")")"
	[ -n "$latest" ] && ! _zm_ver_lt "$(echo "$cur" | tr - .)" "$(echo "$latest" | tr - .)" && latest="$cur"
	printf '{"name":"%s","installed":"%s","latest":"%s"}' "$(esc "$1")" "$(esc "$cur")" "$(esc "$latest")"
}
_jf() { jsonfilter -s "$1" -e "$2" 2>/dev/null; }

_vl() { [ -n "$ZM_VER_LOCAL" ] && return 0; "$@"; }
do_versions_refresh() {
local out="" sep="" j tmp="$VERSIONS_CACHE.tmp" ts at via
	ZM_VER_OLD="$JOBS_DIR/versions.old"
	sed 's/},{/}\n{/g' "$VERSIONS_CACHE" 2>/dev/null | sed -n 's/.*"name":"\([^"]*\)","installed":"[^"]*","latest":"\([^"]*\)".*/\1\t\2/p' > "$ZM_VER_OLD"
	add() { [ -n "$1" ] && { out="$out$sep$1"; sep=","; }; }
	j="$(zm_update_status)"
	if [ "$(_jf "$j" '@.newer')" = true ]; then
		add "$(_ver_item 'Zapret Manager' "$(_jf "$j" '@.current')" "$(_jf "$j" '@.latest')")"
	else
		add "$(_ver_item 'Zapret Manager' "$(_jf "$j" '@.current')" "$(_jf "$j" '@.current')")"
	fi
	[ -f /etc/init.d/zapret ] && add "$(_ver_item Zapret "$ZAPRET_VER" "$ZAPRET_VER")"
	if [ -f /etc/init.d/zapret2 ]; then
        add "$(_ver_item Zapret2 "$(_pkg_version zapret2)" "$(_vl _ver_feed_latest zapret2)")"
    fi
	if [ -n "$ZM_VER_LOCAL" ]; then
		ts="$(sed -n 's/^{"ts":"\([^"]*\)".*/\1/p' "$VERSIONS_CACHE" 2>/dev/null)"
		at="$(sed -n 's/.*"at":\([0-9]*\).*/\1/p' "$VERSIONS_CACHE" 2>/dev/null)"
		via="$(sed -n 's/.*"via":"\([a-z]*\)".*/\1/p' "$VERSIONS_CACHE" 2>/dev/null)"
	else
		ts="$(date '+%d.%m %H:%M')"; at="$(date +%s)"; via="${ZM_VER_VIA:-button}"
	fi
	rm -f "$ZM_VER_OLD"
	mkdir -p "$ZM_STATE_DIR"
	printf '{"ts":"%s","at":%s,"via":"%s","items":[%s]}\n' "$ts" "${at:-0}" "$via" "$out" > "$tmp" && mv "$tmp" "$VERSIONS_CACHE"
	if [ -n "$ZM_VER_LOCAL" ]; then echo "==> Установленные версии записаны"; else echo "==> Версии проверены"; fi
	[ -z "$ZM_VER_LOCAL" ] && [ "$via" = day ] && [ -n "$ZM_AU_GO" ] && _ver_bg && { _au_on panel || _au_on comp; } && _au_spawn night
	return 0
}

_ver_changed() {
	[ -s "$VERSIONS_CACHE" ] || return 0
	[ /opt/zapret-manager-luci/backend.sh -nt "$VERSIONS_CACHE" ] && return 0
	[ /usr/lib/opkg/status -nt "$VERSIONS_CACHE" ] && return 0
	[ /lib/apk/db/installed -nt "$VERSIONS_CACHE" ] && return 0
	[ -n "$(find "$JOBS_DIR" -maxdepth 1 -name '*.log' ! -name 'versions.log' -newer "$VERSIONS_CACHE" 2>/dev/null | head -n 1)" ]
}

VER_MODE_FILE="$ZM_STATE_DIR/ver.mode"
VER_CRON_TAG="# zm-versions"
_ver_mode() { case "$(cat "$VER_MODE_FILE" 2>/dev/null)" in open) echo open ;; button) echo button ;; *) echo day ;; esac; }
_ver_minute() {
	local m
	m="$(cat "$ZM_STATE_DIR/ver.minute" 2>/dev/null)"
	case "$m" in
		[0-9]|[1-5][0-9]) ;;
		*) m="$(awk 'BEGIN { srand(); print int(rand() * 60) }')"
			case "$m" in [0-9]|[1-5][0-9]) ;; *) m=17 ;; esac
			mkdir -p "$ZM_STATE_DIR"; echo "$m" > "$ZM_STATE_DIR/ver.minute" ;;
	esac
	echo "$m"
}
_ver_bg() { [ ! -f "$ZM_STATE_DIR/watch.off" ]; }
VER_EVERY_FILE="$ZM_STATE_DIR/ver.every"
VER_TIME_FILE="$ZM_STATE_DIR/ver.time"
AU_WHEN_FILE="$ZM_STATE_DIR/au.when"
_ver_every() { case "$(cat "$VER_EVERY_FILE" 2>/dev/null)" in 2) echo 2 ;; 6) echo 6 ;; 12) echo 12 ;; *) echo 24 ;; esac; }
_ver_hm() {
	local t h m
	t="$(cat "$VER_TIME_FILE" 2>/dev/null)"
	case "$t" in [0-9]:[0-5][0-9]|[01][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9]) h="${t%%:*}"; m="${t#*:}" ;; *) h=4; m="$(_ver_minute)" ;; esac
	echo "$h $m" | awk '{ print $1 + 0, $2 + 0 }'
}
_ver_time() { _ver_hm | awk '{ printf "%02d:%02d\n", $1, $2 }'; }
_ver_hours() { _ver_hm | awk -v e="$(_ver_every)" '{ n = 24 / e; for (i = 0; i < n; i++) h[i] = ($1 + i * e) % 24; for (i = 0; i < n; i++) for (j = i + 1; j < n; j++) if (h[j] < h[i]) { t = h[i]; h[i] = h[j]; h[j] = t } s = ""; for (i = 0; i < n; i++) s = s (i ? "," : "") h[i]; print s }'; }
_ver_slots() { _ver_hm | awk -v e="$(_ver_every)" '{ n = 24 / e; for (i = 0; i < n; i++) printf "%s%02d:%02d", (i ? " " : ""), ($1 + i * e) % 24, $2; print "" }'; }
_ver_next() {
	local now
	now="$(date '+%H %M')"
	_ver_hm | awk -v e="$(_ver_every)" -v now="$now" '{ split(now, c, " "); cur = c[1] * 60 + c[2]; best = -1; n = 24 / e
		for (i = 0; i < n; i++) { t = (($1 + i * e) % 24) * 60 + $2; d = t - cur; if (d <= 0) d += 1440; if (best < 0 || d < best) { best = d; bt = t } }
		printf "%02d:%02d%s\n", int(bt / 60), bt % 60, (bt <= cur ? " завтра" : "") }'
}
_au_when() { [ "$(cat "$AU_WHEN_FILE" 2>/dev/null)" = now ] && echo now || echo night; }
_ver_cron_sync() {
	local line
	mkdir -p "$(dirname "$CRON_FILE")"; [ -f "$CRON_FILE" ] || : > "$CRON_FILE"
	if [ "$(_ver_mode)" = day ] && _ver_bg; then
		line="$(_ver_hm | awk '{ print $2 }') $(_ver_hours) * * * /opt/zapret-manager-luci/backend.sh versions_cron >/dev/null 2>&1 $VER_CRON_TAG"
		grep -qxF "$line" "$CRON_FILE" 2>/dev/null && return 0
		grep -vF "$VER_CRON_TAG" "$CRON_FILE" > "$CRON_FILE.zm" 2>/dev/null; cat "$CRON_FILE.zm" > "$CRON_FILE"; rm -f "$CRON_FILE.zm"
		echo "$line" >> "$CRON_FILE"
	else
		grep -qF "$VER_CRON_TAG" "$CRON_FILE" 2>/dev/null || return 0
		grep -vF "$VER_CRON_TAG" "$CRON_FILE" > "$CRON_FILE.zm" 2>/dev/null; cat "$CRON_FILE.zm" > "$CRON_FILE"; rm -f "$CRON_FILE.zm"
	fi
	[ -n "$ZM_NO_CRON_RESTART" ] || /etc/init.d/cron restart >/dev/null 2>&1
	return 0
}
_ver_older() {
	local at
	at="$(sed -n 's/.*"at":\([0-9]*\).*/\1/p' "$VERSIONS_CACHE" 2>/dev/null)"
	case "$at" in ''|0|*[!0-9]*) return 0 ;; esac
	[ $(( $(date +%s) - at )) -ge $(( $1 * 60 )) ]
}
versions_cron() {
	local go=""
	{ [ "$(_ver_mode)" = day ] && _ver_bg; } || { _ver_cron_sync; return 0; }
	_job_running versions && return 0
	if [ "$(_ver_every)" = 24 ] || [ "$(_au_when)" = now ] || [ "$(date +%H | sed 's/^0//')" = "$(_ver_hm | awk '{ print $1 }')" ]; then go=1; fi
	ZM_AU_GO="$go" ZM_VER_FORCE=1 ZM_VER_VIA=day job_start versions do_versions_refresh >/dev/null
	return 0
}
versions_mode_set() {
	local v="${1#*:}" h m
	mkdir -p "$ZM_STATE_DIR"
	case "$1" in
		day|open|button) if [ "$1" = day ]; then rm -f "$VER_MODE_FILE"; else echo "$1" > "$VER_MODE_FILE"; fi ;;
		every:2|every:6|every:12) echo "$v" > "$VER_EVERY_FILE" ;;
		every:24) rm -f "$VER_EVERY_FILE" ;;
		time:*)
			h="${v%%:*}"; m="${v#*:}"
			case "$v" in [0-9]:[0-5][0-9]|[01][0-9]:[0-5][0-9]|2[0-3]:[0-5][0-9]) ;; *) echo '{"error":"время — в виде ЧЧ:ММ, например 04:21"}'; return 1 ;; esac
			printf '%02d:%s\n' "${h#0}" "$m" > "$VER_TIME_FILE" ;;
		au:now) echo now > "$AU_WHEN_FILE" ;;
		au:night) rm -f "$AU_WHEN_FILE" ;;
		*) echo '{"error":"неизвестная настройка проверки"}'; return 1 ;;
	esac
	_ver_cron_sync
	versions_status ''
}

_ver_sched_json() {
	printf '"minute":%s,"bg":%s,"every":%s,"time":"%s","slots":"%s","next":"%s","au_when":"%s"' "$(_ver_hm | awk '{ print $2 }')" "$(_ver_bg && echo true || echo false)" \
		"$(_ver_every)" "$(_ver_time)" "$(_ver_slots)" "$(_ver_next)" "$(_au_when)"
}
versions_status() {
	local busy=false mode
	mode="$(_ver_mode)"
	if [ "$1" = refresh ]; then
		_job_running versions || ZM_VER_FORCE=1 ZM_VER_VIA=button job_start versions do_versions_refresh >/dev/null
	elif [ "$1" = auto ] && [ "$mode" = open ] && _ver_older 10; then
		_job_running versions || ZM_VER_FORCE=1 ZM_VER_VIA=open job_start versions do_versions_refresh >/dev/null
	elif [ "$1" = auto ] && [ "$mode" = day ] && _ver_older "$(( $(_ver_every) * 60 + $(_ver_bg && echo 120 || echo 0) ))"; then
		_job_running versions || ZM_AU_GO="$([ "$(_ver_every)" = 24 ] || [ "$(_au_when)" = now ] && echo 1)" ZM_VER_FORCE=1 ZM_VER_VIA=day job_start versions do_versions_refresh >/dev/null
	elif [ "$1" = auto ] && _ver_changed; then
		_job_running versions || ZM_VER_LOCAL=1 job_start versions do_versions_refresh >/dev/null
	fi
	_job_running versions && busy=true
	if [ -s "$VERSIONS_CACHE" ]; then
		sed "s/}\$/,\"pending\":$busy,\"mode\":\"$mode\",$(_ver_sched_json)}/" "$VERSIONS_CACHE"
	else
		printf '{"ts":"","items":[],"pending":%s,"mode":"%s",%s}\n' "$busy" "$mode" "$(_ver_sched_json)"
	fi
}

AU_LOG="$ZM_STATE_DIR/autoupd.log"
AU_LOCK="$JOBS_DIR/autoupd.lock"
_au_on() { [ -f "$ZM_STATE_DIR/au.$1" ]; }
_au_live() { [ -d "$AU_LOCK" ] && kill -0 "$(cat "$AU_LOCK/pid" 2>/dev/null)" 2>/dev/null; }
_au_clean() { printf '%s' "$1" | tr '\t\r\n' '   ' | cut -c1-200; }
_au_add() {
	mkdir -p "$ZM_STATE_DIR"
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$(date '+%d.%m %H:%M')" "$(_au_clean "$1")" "$(_au_clean "$2")" "$(_au_clean "$3")" "$4" "$(_au_clean "$5")" >> "$AU_LOG"
	tail -n 5 "$AU_LOG" > "$AU_LOG.t" 2>/dev/null && mv -f "$AU_LOG.t" "$AU_LOG"
}
_au_fin() {
	[ -s "$AU_LOG" ] && grep -q "	wait	" "$AU_LOG" 2>/dev/null || return 0
	awk -F'\t' -v cur="$ZM_VERSION" -v now="$(date +%s)" -v busy="$([ -f /tmp/zm_update_install.sh ] && echo 1 || echo 0)" '
		BEGIN { OFS = "\t" }
		$6 == "wait" {
			if ($5 == cur || (!busy && cur != $4 && now - $1 > 60)) { $6 = "ok"; $7 = "" }
			else if (!busy && now - $1 > 1200) { $6 = "fail"; $7 = "новая версия не встала — панель осталась на " cur }
		}
		{ print }' "$AU_LOG" > "$AU_LOG.t" 2>/dev/null && mv -f "$AU_LOG.t" "$AU_LOG"
}
_au_items() {
sed 's/},{/}\n{/g' "$VERSIONS_CACHE" 2>/dev/null |
		sed -n 's/.*"name":"\([^"]*\)","installed":"\([^"]*\)","latest":"\([^"]*\)".*/\1\t\2\t\3/p' |
		awk -F'\t' '($1 == "Zapret Manager" || $1 == "Zapret2") && $3 != "" && $3 != $2'
}
_au_wait_free() {
	local w=0 lim=900
	AU_BUSY=""
	while AU_BUSY="$(_zm_busy_job)" || [ -f /tmp/zm_update_install.sh ]; do
		_job_running strategy_test && lim=7200
		[ "$w" -ge "$lim" ] && { [ -n "$AU_BUSY" ] || AU_BUSY="обновление панели"; return 1; }
		sleep 10; w=$((w + 10))
	done
	AU_BUSY=""
	return 0
}
_au_vnorm() { _ver_norm "$1" | tr - .; }
_au_inst() {
	sed 's/},{/}\n{/g' "$VERSIONS_CACHE" 2>/dev/null |
		ZM_N="$1" awk '{ if (match($0, /"name":"[^"]*"/)) { n = substr($0, RSTART + 8, RLENGTH - 9); if (n == ENVIRON["ZM_N"] && match($0, /"installed":"[^"]*"/)) { print substr($0, RSTART + 13, RLENGTH - 14); exit } } }'
}
AU_SKIP="$ZM_STATE_DIR/autoupd.skip"
_au_skipped() { [ -s "$AU_SKIP" ] && grep -qxF "$1	$2" "$AU_SKIP"; }
_au_skip_add() { mkdir -p "$ZM_STATE_DIR"; _au_skipped "$1" "$2" || printf '%s\t%s\n' "$1" "$2" >> "$AU_SKIP"; }
_au_skip_prune() {
	[ -s "$AU_SKIP" ] || return 0
	_au_items | awk -F'\t' -v f="$AU_SKIP" 'BEGIN { while ((getline l < f) > 0) s[l] = 1 } (($1 "\t" $3) in s) { print $1 "\t" $3 }' > "$AU_SKIP.t" 2>/dev/null
	if [ -s "$AU_SKIP.t" ]; then mv -f "$AU_SKIP.t" "$AU_SKIP"; else rm -f "$AU_SKIP.t" "$AU_SKIP"; fi
}
_au_check() {
	local n="$1" f="$2" t="$3" now
	ZM_VER_LOCAL=1 do_versions_refresh >/dev/null 2>&1
	now="$(_au_inst "$n")"
	if [ -z "$now" ]; then _au_add "$n" "$f" "$t" ok ""; return 0; fi
	if [ "$(_au_vnorm "$now")" = "$(_au_vnorm "$f")" ]; then
		_au_skip_add "$n" "$t"
		_au_add "$n" "$f" "$t" fail "установщик отработал, но версия не изменилась — осталась $f. Эту версию больше не пробуем, обновите вручную"
		return 1
	fi
	if _zm_ver_lt "$(_au_vnorm "$now")" "$(_au_vnorm "$f")"; then
		_au_skip_add "$n" "$t"
		_au_add "$n" "$f" "$now" fail "встала более старая версия $now — обновите вручную"
		return 1
	fi
	_au_add "$n" "$f" "$now" ok ""
	return 0
}
_au_one() {
	local n="$1" f="$2" t="$3" job="$4" out rc why w=0
	shift 4
	_au_wait_free || { _au_add "$n" "$f" "$t" fail "роутер занят — идёт «$AU_BUSY»; попробуем в следующий раз"; return 1; }
	echo "$n" > "$AU_LOCK/cur"
	"$@" > "$AU_LOCK/out" 2>/dev/null </dev/null
	out="$(cat "$AU_LOCK/out" 2>/dev/null)"
	case "$out" in
		*'"error"'*)
			why="$(printf '%s' "$out" | sed -n 's/.*"error":"\(.*\)".*/\1/p' | sed 's/\\"/"/g')"
			_au_add "$n" "$f" "$t" fail "${why:-обновление не запустилось}"; return 1 ;;
	esac
	sleep 3
	while _job_running "$job"; do
		[ "$w" -ge 2400 ] && break
		sleep 5; w=$((w + 5))
	done
	rc="$(grep '^__DONE__' "$JOBS_DIR/$job.log" 2>/dev/null | tail -n 1 | awk '{print $2}')"
	if [ "$rc" = 0 ]; then _au_check "$n" "$f" "$t"; return $?; fi
	why="$(grep -E 'ОШИБКА|✗' "$JOBS_DIR/$job.log" 2>/dev/null | tail -n 1 | sed 's/^[[:space:]]*//; s/^ОШИБКА:[[:space:]]*//; s/^✗[[:space:]]*//')"
	[ -n "$why" ] || { [ -z "$rc" ] && why="обновление не закончилось за 40 минут"; }
	_au_add "$n" "$f" "$t" fail "${why:-обновление не удалось}"
	return 1
}

_au_comp() {
case "$1" in
        Zapret2) _au_one "$1" "$2" "$3" install_zapret2 zapret2_action update ;;
    esac
}
autoupd_run() {
local panel=0 comp=0 list n f t out rc w=0 pn="" pf="" pt=""
	mkdir -p "$JOBS_DIR"
	if ! mkdir "$AU_LOCK" 2>/dev/null; then
		_au_live && return 0
		rm -rf "$AU_LOCK"; mkdir "$AU_LOCK" 2>/dev/null || return 0
	fi
	echo $$ > "$AU_LOCK/pid"
	_au_fin
	if [ "$1" = now ]; then
		panel=1; comp=1
		echo "проверяем версии" > "$AU_LOCK/cur"
		_ver_older 10 && ! _job_running versions && ZM_VER_FORCE=1 ZM_VER_VIA=button do_versions_refresh >/dev/null 2>&1
	else
		_au_on panel && panel=1
		_au_on comp && comp=1
	fi
	_au_skip_prune
	list="$(_au_items)"
	[ "$1" = now ] || list="$(printf '%s\n' "$list" | while IFS='	' read -r n f t; do [ -n "$n" ] && ! _au_skipped "$n" "$t" && printf '%s\t%s\t%s\n' "$n" "$f" "$t"; done)"
	[ "$comp" = 1 ] || list="$(printf '%s\n' "$list" | grep '^Zapret Manager	')"
	[ "$panel" = 1 ] || list="$(printf '%s\n' "$list" | grep -v '^Zapret Manager	')"
	if [ -z "$list" ]; then rm -rf "$AU_LOCK"; return 0; fi
	printf '%s\n' "$list" | grep -v '^Zapret Manager	' > "$AU_LOCK/plan"
	while IFS='	' read -r n f t; do
		[ -n "$n" ] && _au_comp "$n" "$f" "$t"
	done < "$AU_LOCK/plan"
	[ -s "$AU_LOCK/plan" ] && ZM_VER_LOCAL=1 do_versions_refresh >/dev/null 2>&1
	printf '%s\n' "$list" | grep '^Zapret Manager	' | head -n 1 > "$AU_LOCK/panel"
	IFS='	' read -r pn pf pt < "$AU_LOCK/panel"
	if [ -n "$pt" ]; then
		echo "Zapret Manager" > "$AU_LOCK/cur"
		if ! _au_wait_free; then _au_add "$pn" "$pf" "$pt" fail "роутер занят — идёт «$AU_BUSY»; попробуем в следующий раз"
		else
			zm_update_action > "$AU_LOCK/out" 2>/dev/null </dev/null
			out="$(cat "$AU_LOCK/out" 2>/dev/null)"
			case "$out" in
				*'"error"'*) _au_add "$pn" "$pf" "$pt" fail "$(printf '%s' "$out" | sed -n 's/.*"error":"\(.*\)".*/\1/p')" ;;
				*)
					sleep 3
					while _job_running zm_update && [ "$w" -lt 600 ]; do sleep 5; w=$((w + 5)); done
					rc="$(grep '^__DONE__' "$JOBS_DIR/zm_update.log" 2>/dev/null | tail -n 1 | awk '{print $2}')"
					if [ "$rc" = 0 ]; then _au_add "$pn" "$pf" "$pt" wait "ставится"
					else _au_add "$pn" "$pf" "$pt" fail "$(grep 'ОШИБКА' "$JOBS_DIR/zm_update.log" 2>/dev/null | tail -n 1 | sed 's/^ОШИБКА:[[:space:]]*//')"; fi ;;
			esac
		fi
	fi
	rm -rf "$AU_LOCK"
	return 0
}
_au_spawn() { ( /opt/zapret-manager-luci/backend.sh autoupd_run "$1" ) >/dev/null 2>&1 </dev/null & }
autoupd_status() {
	local live=false cur=""
	_au_fin
	_au_live && { live=true; cur="$(cat "$AU_LOCK/cur" 2>/dev/null)"; }
	printf '{"panel":%s,"comp":%s,"running":%s,"cur":"%s","log":[' \
		"$(_au_on panel && echo true || echo false)" "$(_au_on comp && echo true || echo false)" "$live" "$(esc "$cur")"
	[ -s "$AU_LOG" ] && awk -F'\t' "$ZM_JESC_AWK"'
		{ l[NR] = "{\"ts\":\"" jesc($2) "\",\"name\":\"" jesc($3) "\",\"from\":\"" jesc($4) "\",\"to\":\"" jesc($5) "\",\"res\":\"" jesc($6) "\",\"note\":\"" jesc($7) "\"}" }
		END { for (i = NR; i >= 1; i--) printf "%s%s", (i < NR ? "," : ""), l[i] }' "$AU_LOG"
	printf ']}\n'
}
autoupd() {
	local j
	case "$1" in
		status) ;;
		panel_on|comp_on) mkdir -p "$ZM_STATE_DIR"; : > "$ZM_STATE_DIR/au.${1%_on}" ;;
		panel_off|comp_off) rm -f "$ZM_STATE_DIR/au.${1%_off}" ;;
		run)
			_au_live && { echo '{"error":"обновление уже идёт"}'; return 1; }
			if j="$(_zm_busy_job)"; then printf '{"error":"%s"}\n' "$(esc "идёт операция «$j» — дождитесь её окончания")"; return 1; fi
			_au_spawn now
			sleep 1 ;;
		clear) _au_live && { echo '{"error":"дождитесь окончания обновления"}'; return 1; }; rm -f "$AU_LOG" ;;
		*) echo '{"error":"неизвестное действие"}'; return 1 ;;
	esac
	autoupd_status
}

_dnsm_present() { [ -x /usr/bin/dns-manager ] || [ -x /usr/libexec/rpcd/dns_manager ]; }

_hosts_extra() {
	[ -s "$HOSTS_FILE" ] || { echo false; return; }
	awk -v me="$(uci -q get system.@system[0].hostname 2>/dev/null)" '
		BEGIN { split("localhost localhost.localdomain ip6-localhost ip6-loopback ip6-localnet ip6-mcastprefix ip6-allnodes ip6-allrouters ip6-allhosts broadcasthost", a, " "); for (i in a) ok[a[i]] = 1; r = "false" }
		{ sub(/#.*/, ""); if (NF < 2) next
		  for (i = 2; i <= NF; i++) { n = tolower($i); if (n in ok || n == tolower(me) || n ~ /\.lan$/) continue; r = "true"; exit } }
		END { print r }' "$HOSTS_FILE" 2>/dev/null || echo false
}

_doh_url_of() {
	case "$1" in
		cloudflare)    echo "https://cloudflare-dns.com/dns-query" ;;
		google)        echo "https://dns.google/dns-query" ;;
		cloudflare_sec) echo "https://security.cloudflare-dns.com/dns-query" ;;
		cloudflare_fam) echo "https://family.cloudflare-dns.com/dns-query" ;;
		quad9)         echo "https://dns.quad9.net/dns-query" ;;
		quad9_open)    echo "https://dns10.quad9.net/dns-query" ;;
		yandex)        echo "https://common.dot.dns.yandex.net/dns-query" ;;
		xbox)          echo "https://xbox-dns.ru/dns-query" ;;
		comss)         echo "https://dns.comss.one/dns-query" ;;
		dnsai)         echo "https://dns.dns-ai.ru/dns-query" ;;
		bezmezhau)     echo "https://dns.bezmezhau.com/dns-query" ;;
		yandex_family) echo "https://family.dot.dns.yandex.net/dns-query" ;;
		yandex_safe)   echo "https://safe.dot.dns.yandex.net/dns-query" ;;
		geohide_ru)    echo "https://geohide.ru/dns-query" ;;
		geohide_eu)    echo "https://eu.geohide.ru/dns-query" ;;
		geohide_us)    echo "https://us.geohide.ru/dns-query" ;;
		malw)          echo "https://dns.malw.link/dns-query" ;;
		zapretmoe)     echo "https://dns.zapret.moe/dns-query" ;;
		webshift)      echo "https://d.webshiftvpn.ru/dns-query" ;;
		dagami)        echo "https://dns.dagami.ru/dns-query" ;;
		controld)      echo "https://freedns.controld.com/p0" ;;
		controld_sec)  echo "https://freedns.controld.com/p1" ;;
		controld_fam)  echo "https://freedns.controld.com/family" ;;
		dns4eu)        echo "https://unfiltered.joindns4.eu/dns-query" ;;
		dns4eu_sec)    echo "https://protective.joindns4.eu/dns-query" ;;
		dns4eu_fam)    echo "https://child.joindns4.eu/dns-query" ;;
		https://*)
			printf '%s' "$1" | grep -qE '^https://[A-Za-z0-9.-]+\.[A-Za-z0-9-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~%/+=&?-]*)?$' || return 1
			[ "${#1}" -le 200 ] || return 1
			echo "$1" ;;
		*) return 1 ;;
	esac
}

DOH_FO_FILE="/opt/zapret-manager-luci/doh_failover"

_doh_fo_get() { local v; v="$(_kv_last "$DOH_FO_FILE" "$1")"; echo "${v:-$2}"; }

_doh_fo_on() { [ "$(_doh_fo_get fo 0)" = 1 ] || [ "$(_doh_fo_get direct 0)" = 1 ]; }

_job_alive() { _job_running "$1"; }

_zm_ver_lt() {
	awk -v a="$1" -v b="$2" 'BEGIN { n = split(a, x, "."); m = split(b, y, "."); k = n > m ? n : m
		for (i = 1; i <= k; i++) { if (x[i] + 0 < y[i] + 0) exit 0; if (x[i] + 0 > y[i] + 0) exit 1 }
		exit 1 }'
}

AWG_RUN="$JOBS_DIR/awg"

[ -d "$AWG_RUN" ] || mkdir -p "$AWG_RUN" 2>/dev/null

_pkg_version() {
	if [ "$PKG" = "apk" ]; then
		_apk_ver "$1"
	else
		_opkg_ver "$1"
	fi
}

_term_say() { echo "==> $*"; }
_term_installed() { [ -x /usr/bin/ttyd ]; }
_term_running() { pidof ttyd >/dev/null 2>&1; }
_term_enabled() { ls /etc/rc.d/S*ttyd >/dev/null 2>&1; }
_term_version() { ttyd --version 2>/dev/null | head -n1 | awk '{ print $NF }'; }
_term_port() {
	local p
	p="$(uci -q get 'ttyd.@ttyd[0].port' 2>/dev/null)"
	case "$p" in ''|*[!0-9]*) p=7681 ;; esac
	echo "$p"
}

TERM_ALL="$ZM_STATE_DIR/ttyd.all"
_term_iface() { uci -q get 'ttyd.@ttyd[0].interface'; }
_term_mode() {
	local i
	i="$(_term_iface)"
	case "$i" in
		'') [ -f "$TERM_ALL" ] && echo all || echo home ;;
		@lan|br-lan) echo home ;;
		@tailscale|tailscale0) echo ts ;;
		*) echo other ;;
	esac
}

_term_all_guard() {
	[ -f "$TERM_ALL" ] || return 1
	[ -z "$(_term_iface)" ] || { rm -f "$TERM_ALL"; return 1; }
	_term_wan_closed && return 1
	uci -q set 'ttyd.@ttyd[0].interface=@lan'; uci -q commit ttyd
	rm -f "$TERM_ALL"
	logger -t zapret-manager "Терминал: вход из интернета в firewall открыт — терминал снова только для домашней сети"
	return 0
}

_term_set_mode() {
	_term_config
	case "$1" in
		all)
			_term_wan_closed || { echo "вход из интернета в firewall не закрыт — открыть терминал на всех интерфейсах небезопасно"; return 1; }
			uci -q delete 'ttyd.@ttyd[0].interface'
			mkdir -p "$ZM_STATE_DIR"; : > "$TERM_ALL" ;;
		home)
			uci -q set 'ttyd.@ttyd[0].interface=@lan'
			rm -f "$TERM_ALL" ;;
		*) echo "неизвестный режим"; return 1 ;;
	esac
	uci -q commit ttyd
	_term_running && /etc/init.d/ttyd restart >/dev/null 2>&1
	return 0
}

_term_config() {
	[ -f /etc/config/ttyd ] || : > /etc/config/ttyd
	uci -q get 'ttyd.@ttyd[0]' >/dev/null 2>&1 || uci -q add ttyd ttyd >/dev/null 2>&1
	_term_all_guard
	[ -n "$(_term_iface)" ] || [ -f "$TERM_ALL" ] || uci -q set 'ttyd.@ttyd[0].interface=@lan'
	[ -n "$(uci -q get 'ttyd.@ttyd[0].port')" ] || uci -q set 'ttyd.@ttyd[0].port=7681'
	[ -n "$(uci -q get 'ttyd.@ttyd[0].command')" ] || uci -q set 'ttyd.@ttyd[0].command=/bin/login'
	uci -q commit ttyd
}

_term_start() {
	local t=0
	_term_installed || { echo "ОШИБКА: терминал не установлен"; return 1; }
	_term_config
	rm -f "$ZM_STATE_DIR/ttyd.htop"
	/etc/init.d/ttyd enable >/dev/null 2>&1
	/etc/init.d/ttyd restart >/dev/null 2>&1
	while [ "$t" -lt 10 ]; do
		_term_running && break
		sleep 1; t=$((t + 1))
	done
	_term_running || { echo "ОШИБКА: ttyd не запустился"; return 1; }
	return 0
}

_term_stop() {
	[ -x /etc/init.d/ttyd ] && { /etc/init.d/ttyd stop >/dev/null 2>&1; /etc/init.d/ttyd disable >/dev/null 2>&1; }
	_term_running && { killall ttyd >/dev/null 2>&1; sleep 1; killall -9 ttyd >/dev/null 2>&1; }
	return 0
}

term_status() {
	local inst=false run=false en=false
	_term_installed && inst=true
	_term_running && run=true
	_term_enabled && en=true
	printf '{"installed":%s,"running":%s,"enabled":%s,"version":"%s","port":%s,"lan_ip":"%s","mode":"%s","iface":"%s","ts":%s,"ts_ip":"%s","wan_closed":%s,"job":%s}\n' \
		"$inst" "$run" "$en" "$(esc "$(_term_version)")" "$(_term_port)" "$(esc "$(_zm_lan_ip)")" \
		"$(_term_mode)" "$(esc "$(_term_iface)")" "$(_term_tailscale_installed && echo true || echo false)" \
		"$(esc "$(_term_tailscale_running && _zm_tmo 5 tailscale ip -4 2>/dev/null | head -n1)")" \
		"$(_term_wan_closed && echo true || echo false)" \
		"$(_job_alive term && echo true || echo false)"
}

do_term_install() {
	_ensure_deps
	_term_say "Устанавливаем терминал (ttyd)"
	$UPDATE || echo "!! Список пакетов не обновился — пробуем с тем, что есть"
	$INSTALL ttyd || { echo "ОШИБКА: ttyd не установился — проверьте интернет и доступность пакета для вашей прошивки"; return 1; }
	_term_installed || { echo "ОШИБКА: файла /usr/bin/ttyd нет — пакет встал не полностью"; return 1; }
	_term_say "Запускаем терминал"
	_term_start || return 1
	echo "   ✓ Терминал работает: порт $(_term_port), только домашняя сеть"
	_term_say "Готово: терминал ttyd $(_term_version)"
}

do_term_remove() {
	_term_say "Останавливаем терминал"
	_term_stop
	echo "   ✓ Терминал остановлен и убран из автозапуска"
	_term_say "Удаляем ttyd"
	local rc=0
	_zm_pkg_wipe luci-i18n-ttyd-ru luci-app-ttyd ttyd || rc=1
	_zm_wipe /etc/config/ttyd /etc/config/ttyd-opkg /etc/config/ttyd.apk-new /etc/init.d/ttyd /etc/rc.d/*ttyd || rc=1
	rm -f "$TERM_ALL"
	_zm_rm_listed terminal || rc=1
	rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null
	_term_installed && rc=1
	_zm_rm_done "$rc" "Терминал"
}

term_action() {
	local a="$1" j
	case "$a" in
		install|remove)
			_job_alive term && { echo '{"error":"дождитесь окончания текущей операции"}'; return 1; }
			if j="$(_zm_busy_job)"; then printf '{"error":"%s"}\n' "$(esc "Сейчас идёт операция: $j — дождитесь её окончания")"; return 1; fi
			case "$a" in
				install) job_start term do_term_install ;;
				remove)  job_start term do_term_remove ;;
			esac ;;
		start|restart)
			_term_installed || { echo '{"error":"терминал не установлен"}'; return 1; }
			_job_alive term && { echo '{"error":"дождитесь окончания текущей операции"}'; return 1; }
			_term_start >/dev/null 2>&1 || { echo '{"error":"ttyd не запустился — смотрите журнал роутера"}'; return 1; }
			printf '{"ok":true}\n' ;;
		ts_on|ts_off)
			_term_installed || { echo '{"error":"терминал не установлен"}'; return 1; }
			_job_alive term && { echo '{"error":"дождитесь окончания текущей операции"}'; return 1; }
			if j="$(_term_set_mode "$([ "$a" = ts_on ] && echo all || echo home)")"; then printf '{"ok":true,"mode":"%s"}\n' "$(_term_mode)"
			else printf '{"error":"%s"}\n' "$(esc "$j")"; return 1; fi ;;
		*) echo '{"error":"неизвестное действие"}'; return 1 ;;
	esac
}

_term_tailscale_installed() { [ -x /usr/sbin/tailscaled ] && [ -e /usr/sbin/tailscale ]; }
_term_tailscale_running() { pidof tailscaled >/dev/null 2>&1; }

_term_wan_closed() {
	local s i
	s="$(_zm_zone_sec "$(_zm_wan_zone)")" || return 1
	i="$(uci -q get "firewall.$s.input")"
	[ "$i" = REJECT ] || [ "$i" = DROP ]
}

WATCH_OFF="$ZM_STATE_DIR/watch.off"

ZM_MULTI_OK=' status system_info health versions zm_update_status lan_ip '
_zm_multi_ok() {
	case "$1" in *[!a-z0-9_]*|'') return 1 ;; multi) return 1 ;; *_status|*_get|strategy_list_*) return 0 ;; esac
	case "$ZM_MULTI_OK" in *" $1 "*) return 0 ;; esac
	return 1
}
_zm_multi() {
	local d="$JOBS_DIR/multi.$$" i=0 n line m a f sep=""
	mkdir -p "$d" || { echo '{"error":"нет места в /tmp"}'; return 1; }
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		[ "$i" -ge 16 ] && break
		m="${line%%	*}"; a=""
		case "$line" in *"	"*) a="${line#*	}" ;; esac
		if _zm_multi_ok "$m" && { [ -z "$a" ] || _zm_re "$a" '^[A-Za-z0-9_.:@-]{1,64}$'; }; then
			if [ -n "$a" ]; then ( cmd="$m"; _zm_run_cmd "$a" ) < /dev/null > "$d/$i" 2>/dev/null &
			else ( cmd="$m"; _zm_run_cmd ) < /dev/null > "$d/$i" 2>/dev/null &
			fi
		else
			: > "$d/$i"
		fi
		i=$((i + 1))
	done << ZM_MULTI_EOF
$1
ZM_MULTI_EOF
	wait
	printf '{"r":['
	n=0
	while [ "$n" -lt "$i" ]; do
		f="$d/$n"
		if [ -s "$f" ] && [ "$(head -c 1 "$f")" = "{" ] && case "$(tail -c 8 "$f" | tr -d '\n\r\t ')" in *"}") true ;; *) false ;; esac; then
			printf '%s' "$sep"; cat "$f"
		else
			printf '%s{"__fail":true}' "$sep"
		fi
		sep=","
		n=$((n + 1))
	done
	printf ']}\n'
	rm -rf "$d"
}

cmd="$1"; shift
_zm_in() {
	ZM_IN="$(cat; echo .)"
	if [ "$ZM_IN" = "@zmupload." ] && [ "$cmd" != upload_part ] && [ -f "$ZM_UP_FILE" ]; then
		ZM_IN="$(cat "$ZM_UP_FILE"; echo .)"
		rm -f "$ZM_UP_FILE"
	fi
}
if [ "$2" = @stdin ]; then _zm_in; set -- "$1" "${ZM_IN%.}"
elif [ "$1" = @stdin ]; then _zm_in; set -- "${ZM_IN%.}"; fi
case "$cmd" in
	strategy_set_v|strategy_set_flowseal|strategy_set_youtube|youtube_quic_set|discord_set_dv|discord_set_fake|game_set|game_set_fake|game_toggle_xtreme)
		[ -f "$CONF" ] && { _nochange_guard || exit 1; } ;;
	test_action)
		[ "$1" = start ] && [ "$2" != current ] && [ -f "$CONF" ] && { _nochange_guard || exit 1; }
		[ "$1" = auto_run ] && [ -f "$CONF" ] && { _nochange_guard || exit 1; } ;;
	zapret_opt_set)
		case "$1" in rkn:*|wssize:*|ipid:*) [ -f "$CONF" ] && { _nochange_guard || exit 1; } ;; esac ;;
esac
case "$cmd" in
	strategy_set_v|strategy_set_flowseal|strategy_set_youtube|youtube_quic_set|discord_set_dv|discord_set_fake|game_set|game_set_fake|game_toggle_xtreme|zapret_opt_set)
		_zc_lift ;;
esac
_zm_run_cmd() {
case "$cmd" in
	status)                  status ;;
	system_info)             system_info ;;
	job_status)               job_status "$1" ;;
	log_tail)                  log_tail "$1" ;;
	zapret_action)              zapret_action "$1" ;;
	zapret2_action)              zapret2_action "$1" ;;
	strategy_list_v)            strategy_list_v ;;
	strategy_set_v)              strategy_set_v "$1" ;;
	strategy_list_flowseal)       strategy_list_flowseal "$1" ;;
	strategy_set_flowseal)         strategy_set_flowseal "$1" ;;
	strategy_list_youtube)          strategy_list_youtube "$1" ;;
	strategy_set_youtube)            strategy_set_youtube "$1" ;;
	youtube_quic_set)                youtube_quic_set "$1" ;;
	discord_status)                 discord_status ;;
	discord_set_dv)                  discord_set_dv "$1" ;;
	discord_set_fake)                 discord_set_fake "$1" ;;
	game_status)                        game_status ;;
	game_set)                            game_set "$1" ;;
	game_set_fake)                        game_set_fake "$1" ;;
	game_toggle_xtreme)                    game_toggle_xtreme ;;
	system_status)                           system_status ;;
	system_check_connectivity)                system_check_connectivity ;;
	system_toggle_quic)                        system_toggle_quic "$1" ;;
	system_toggle_ipv6)                         system_toggle_ipv6 "$1" ;;
	system_toggle_flow_offloading_fix)           system_toggle_flow_offloading_fix "$1" ;;
	gh_proxy)                                      gh_proxy "$1" "$2" ;;
	gh_mirrors)                                    gh_mirrors ;;
	exclusions_status)                                     exclusions_status ;;
	exclusions_toggle)                                       exclusions_toggle "$1" ;;
	exclusions_clear)                                          exclusions_clear ;;
	nfqws_opt_get)                                   nfqws_opt_get ;;
	zapret_lists_status)                             zapret_lists_status ;;
	zapret_list_get)                                 zapret_list_get "$1" ;;
	zapret_list_set)                                 zapret_list_set "$1" "$2" ;;
	zapret_list_restore)                             zapret_list_restore "$1" ;;
	nfqws_opt_set)                                   nfqws_opt_set "$1" ;;
	zapret_excl_tick)                                             zapret_excl_tick ;;
	hosts_status)                      hosts_status ;;
	hosts_toggle)                       hosts_toggle "$1" ;;
	hosts_replace_geohide)              hosts_replace_geohide "$1" ;;
	hosts_reset)                        hosts_reset ;;
	hosts_file_get)                     hosts_file_get ;;
	hosts_file_set)                     hosts_file_set "$1" ;;
	upload_part)                        upload_part "$1" "$2" ;;
	test_status)                          test_status ;;
	test_action)                          test_action "$1" "$2" ;;
	test_results)                         test_results "$1" ;;
	zapret_opt_set)                       zapret_opt_set "$1" ;;
	zm_update_status)                     zm_update_status ;;
	zm_update_action)                     zm_update_action ;;
	zm_changelog)                         case "$1" in local|remote|all) zm_changelog "$1" ;; *) echo '{"error":"неизвестный режим"}' ;; esac ;;
	zm_changelog_seen)                    zm_changelog seen ;;
	zm_changelog_sync)                    _zm_cl_sync ;;
	health)                               health ;;
	versions)                             versions_status "$1" ;;
	versions_mode)                        versions_mode_set "$1" ;;
	versions_cron)                        versions_cron ;;
	versions_cron_sync)                   _ver_cron_sync ;;
	autoupd)                              autoupd "$1" ;;
	autoupd_run)                          autoupd_run "$1" ;;
	term_status)                          term_status ;;
	term_action)                          term_action "$1" "$2" ;;
	lan_ip)                               _zm_lan_ip ;;
	jobs_cancel)                          jobs_cancel "$1" ;;
	system_reboot)                        system_reboot ;;
	reboot_hint_clear)                    reboot_hint_clear ;;
	zm_watch)                             zm_watch ;;
	ui_theme_set)                         ui_theme_set "$1" ;;
	ui_nav_set)                           ui_nav_set "$1" ;;
	ui_flags_get)                         ui_flags_get ;;
	ui_flag_set)                          ui_flag_set "$1" ;;
	multi)                                _zm_multi "$1" ;;
	*) echo '{"error":"неизвестная команда"}'; exit 1 ;;
esac
}
_zm_run_cmd "$@"
zm_rc=$?
[ -n "$ZC_LIFTED" ] && _zc_drop
exit $zm_rc
ZM_INSTALLER_EOF
sed -i "s/@ZM_VERSION@/$ZM_NEW_VER/" '/opt/zapret-manager-luci/backend.sh.zm-new'
chmod 0755 '/opt/zapret-manager-luci/backend.sh.zm-new'
mv -f '/opt/zapret-manager-luci/backend.sh.zm-new' '/opt/zapret-manager-luci/backend.sh'

mkdir -p /usr/libexec/rpcd
chmod 0755 /usr/libexec/rpcd
cat > '/opt/zapret-manager-luci/rpcd-plugin.zm-new' << 'ZM_INSTALLER_EOF'
#!/bin/sh

. /usr/share/libubox/jshn.sh

BACKEND="/opt/zapret-manager-luci/backend.sh"

list_methods() {
	json_init
	json_add_object "status";                 json_close_object
	json_add_object "system_info";            json_close_object
	json_add_object "multi";                  json_add_string "calls" "string"; json_close_object
	json_add_object "job_status";             json_add_string "job" "string"; json_close_object
	json_add_object "log_tail";               json_add_string "job" "string"; json_close_object
	json_add_object "zapret_action";          json_add_string "action" "string"; json_close_object
	json_add_object "zapret2_action";         json_add_string "action" "string"; json_close_object
	json_add_object "strategy_list_v";        json_close_object
	json_add_object "strategy_set_v";         json_add_string "version" "string"; json_close_object
	json_add_object "strategy_list_flowseal"; json_add_string "action" "string"; json_close_object
	json_add_object "strategy_set_flowseal";  json_add_string "name" "string"; json_close_object
	json_add_object "strategy_list_youtube";  json_add_string "action" "string"; json_close_object
	json_add_object "strategy_set_youtube";   json_add_string "name" "string"; json_close_object
	json_add_object "youtube_quic_set";       json_add_string "mode" "string"; json_close_object
	json_add_object "discord_status";         json_close_object
	json_add_object "discord_set_dv";         json_add_string "num" "string"; json_close_object
	json_add_object "discord_set_fake";       json_add_string "file" "string"; json_close_object
	json_add_object "game_status";            json_close_object
	json_add_object "game_set";               json_add_string "choice" "string"; json_close_object
	json_add_object "game_set_fake";          json_add_string "file" "string"; json_close_object
	json_add_object "game_toggle_xtreme";     json_close_object
	json_add_object "system_status";               json_close_object
	json_add_object "system_check_connectivity";   json_close_object
	json_add_object "system_toggle_quic"; json_add_string "mode" "string"; json_close_object
	json_add_object "system_toggle_ipv6"; json_add_string "mode" "string"; json_close_object
	json_add_object "system_toggle_flow_offloading_fix"; json_add_string "mode" "string"; json_close_object
	json_add_object "gh_proxy";                    json_add_string "action" "string"; json_add_string "value" "string"; json_close_object
	json_add_object "exclusions_status";           json_close_object
	json_add_object "exclusions_toggle";           json_add_string "ip" "string"; json_close_object
	json_add_object "exclusions_clear";            json_close_object
	json_add_object "nfqws_opt_get";               json_close_object
	json_add_object "zapret_lists_status";         json_close_object
	json_add_object "zapret_list_get";             json_add_string "id" "string"; json_close_object
	json_add_object "zapret_list_set";             json_add_string "id" "string"; json_add_string "content" "string"; json_close_object
	json_add_object "zapret_list_restore";         json_add_string "id" "string"; json_close_object
	json_add_object "nfqws_opt_set";               json_add_string "content" "string"; json_close_object
	json_add_object "hosts_status";           json_close_object
	json_add_object "hosts_toggle";           json_add_string "block" "string"; json_close_object
	json_add_object "hosts_replace_geohide";  json_add_string "region" "string"; json_close_object
	json_add_object "hosts_reset";            json_close_object
	json_add_object "hosts_file_get";         json_close_object
	json_add_object "hosts_file_set";         json_add_string "content" "string"; json_close_object
	json_add_object "upload_part";            json_add_string "content" "string"; json_add_string "part" "string"; json_close_object
	json_add_object "test_status";             json_close_object
	json_add_object "test_action";             json_add_string "action" "string"; json_add_string "mode" "string"; json_close_object
	json_add_object "zapret_opt_set";          json_add_string "opt" "string"; json_close_object
	json_add_object "test_results";            json_add_string "mode" "string"; json_close_object
	json_add_object "zm_update_status";        json_close_object
	json_add_object "zm_update_action";        json_close_object
	json_add_object "zm_changelog";            json_add_string "mode" "string"; json_close_object
	json_add_object "zm_changelog_seen";       json_close_object
	json_add_object "health";                 json_close_object
	json_add_object "system_reboot";          json_close_object
	json_add_object "reboot_hint_clear";      json_close_object
	json_add_object "versions";               json_add_string "action" "string"; json_close_object
	json_add_object "versions_mode";          json_add_string "mode" "string"; json_close_object
	json_add_object "term_status";            json_close_object
	json_add_object "term_action";            json_add_string "action" "string"; json_add_string "mode" "string"; json_close_object
	json_add_object "jobs_cancel";            json_add_string "job" "string"; json_close_object
	json_add_object "ui_theme_set";           json_add_string "theme" "string"; json_close_object
	json_add_object "ui_nav_set";             json_add_string "ids" "string"; json_close_object
	json_add_object "ui_flags_get";           json_close_object
	json_add_object "ui_flag_set";            json_add_string "name" "string"; json_close_object
	json_add_object "autoupd";                json_add_string "action" "string"; json_close_object
	json_dump
}


call_method() {
	local method="$1"
	local input
	input="$(cat)"
	json_load "$input" 2>/dev/null

	case "$method" in
		status)                 "$BACKEND" status ;;
		system_info)            "$BACKEND" system_info ;;
		multi)                  json_get_var calls calls; printf '%s' "$calls" | "$BACKEND" multi @stdin ;;
		job_status)             json_get_var job job;         "$BACKEND" job_status "$job" ;;
		log_tail)                json_get_var job job;         "$BACKEND" log_tail "$job" ;;
		zapret_action)           json_get_var action action;   "$BACKEND" zapret_action "$action" ;;
		zapret2_action)          json_get_var action action;   "$BACKEND" zapret2_action "$action" ;;
		strategy_list_v)         "$BACKEND" strategy_list_v ;;
		strategy_set_v)          json_get_var version version; "$BACKEND" strategy_set_v "$version" ;;
		strategy_list_flowseal)  json_get_var action action;   "$BACKEND" strategy_list_flowseal "$action" ;;
		strategy_set_flowseal)   json_get_var name name;       "$BACKEND" strategy_set_flowseal "$name" ;;
		strategy_list_youtube)   json_get_var action action;   "$BACKEND" strategy_list_youtube "$action" ;;
		strategy_set_youtube)    json_get_var name name;       "$BACKEND" strategy_set_youtube "$name" ;;
		youtube_quic_set)        json_get_var mode mode;       "$BACKEND" youtube_quic_set "$mode" ;;
		discord_status)          "$BACKEND" discord_status ;;
		discord_set_dv)          json_get_var num num;         "$BACKEND" discord_set_dv "$num" ;;
		discord_set_fake)        json_get_var file file;       "$BACKEND" discord_set_fake "$file" ;;
		game_status)             "$BACKEND" game_status ;;
		game_set)                json_get_var choice choice;   "$BACKEND" game_set "$choice" ;;
		game_set_fake)           json_get_var file file;       "$BACKEND" game_set_fake "$file" ;;
		game_toggle_xtreme)      "$BACKEND" game_toggle_xtreme ;;
		system_status)                 "$BACKEND" system_status ;;
		system_check_connectivity)     "$BACKEND" system_check_connectivity ;;
		system_toggle_quic) json_get_var mode mode; "$BACKEND" system_toggle_quic "$mode" ;;
		system_toggle_ipv6) json_get_var mode mode; "$BACKEND" system_toggle_ipv6 "$mode" ;;
		system_toggle_flow_offloading_fix) json_get_var mode mode; "$BACKEND" system_toggle_flow_offloading_fix "$mode" ;;
		gh_proxy)                      json_get_var action action; json_get_var value value; "$BACKEND" gh_proxy "$action" "$value" ;;
		exclusions_status)             "$BACKEND" exclusions_status ;;
		exclusions_toggle)             json_get_var ip ip;          "$BACKEND" exclusions_toggle "$ip" ;;
		exclusions_clear)              "$BACKEND" exclusions_clear ;;
		nfqws_opt_get)                 "$BACKEND" nfqws_opt_get ;;
		zapret_lists_status)           "$BACKEND" zapret_lists_status ;;
		zapret_list_get)               json_get_var id id; "$BACKEND" zapret_list_get "$id" ;;
		zapret_list_set)               json_get_var id id; json_get_var content content; printf '%s' "$content" | "$BACKEND" zapret_list_set "$id" @stdin ;;
		zapret_list_restore)           json_get_var id id; "$BACKEND" zapret_list_restore "$id" ;;
		nfqws_opt_set)                 json_get_var content content; printf '%s' "$content" | "$BACKEND" nfqws_opt_set @stdin ;;
		hosts_status)            "$BACKEND" hosts_status ;;
		hosts_toggle)            json_get_var block block;     "$BACKEND" hosts_toggle "$block" ;;
		hosts_replace_geohide)   json_get_var region region;   "$BACKEND" hosts_replace_geohide "$region" ;;
		hosts_reset)             "$BACKEND" hosts_reset ;;
		hosts_file_get)          "$BACKEND" hosts_file_get ;;
		hosts_file_set)          json_get_var content content; printf '%s' "$content" | "$BACKEND" hosts_file_set @stdin ;;
		upload_part)             json_get_var content content; json_get_var part part; printf '%s' "$content" | "$BACKEND" upload_part "$part" @stdin ;;
		test_status)             "$BACKEND" test_status ;;
		test_action)             json_get_var action action; json_get_var mode mode; printf '%s' "$mode" | "$BACKEND" test_action "$action" @stdin ;;
		zapret_opt_set)          json_get_var opt opt;         "$BACKEND" zapret_opt_set "$opt" ;;
		test_results)            json_get_var mode mode; "$BACKEND" test_results "$mode" ;;
		zm_update_status)        "$BACKEND" zm_update_status ;;
		zm_update_action)        "$BACKEND" zm_update_action ;;
		zm_changelog)            json_get_var mode mode;       "$BACKEND" zm_changelog "$mode" ;;
		zm_changelog_seen)       "$BACKEND" zm_changelog_seen ;;
		health)                  "$BACKEND" health ;;
		system_reboot)           "$BACKEND" system_reboot ;;
		reboot_hint_clear)       "$BACKEND" reboot_hint_clear ;;
		versions)                json_get_var action action; "$BACKEND" versions "$action" ;;
		versions_mode)           json_get_var mode mode; "$BACKEND" versions_mode "$mode" ;;
		term_status)             "$BACKEND" term_status ;;
		term_action)             json_get_var action action; json_get_var mode mode; printf '%s' "$mode" | "$BACKEND" term_action "$action" @stdin ;;
		autoupd)                 json_get_var action action; "$BACKEND" autoupd "$action" ;;
		jobs_cancel)             json_get_var job job;         "$BACKEND" jobs_cancel "$job" ;;
		ui_theme_set)            json_get_var theme theme;     "$BACKEND" ui_theme_set "$theme" ;;
		ui_nav_set)              json_get_var ids ids;         "$BACKEND" ui_nav_set "$ids" ;;
		ui_flags_get)            "$BACKEND" ui_flags_get ;;
		ui_flag_set)             json_get_var name name;       "$BACKEND" ui_flag_set "$name" ;;
		*) echo '{"error":"unknown method"}'; return 1 ;;
	esac
}

case "$1" in
	list) list_methods ;;
	call)
		t="/tmp/zm-rpc.$$"
		call_method "$2" > "$t"
		sz="$(wc -c < "$t" 2>/dev/null | tr -d ' ')"
		if [ "${sz:-0}" -gt 400000 ]; then
			echo '{"error":"ответ роутера слишком большой — отменено, чтобы не перегрузить службу входа (rpcd)"}'
		else
			cat "$t"
		fi
		rm -f "$t"
		;;
	*) echo '{"error":"usage: zapret-manager {list|call <method>}"}'; exit 1 ;;
esac
ZM_INSTALLER_EOF
chmod 0755 '/opt/zapret-manager-luci/rpcd-plugin.zm-new'
mv -f '/opt/zapret-manager-luci/rpcd-plugin.zm-new' '/usr/libexec/rpcd/zapret-manager'

mkdir -p /usr/share/rpcd/acl.d
chmod 0755 /usr/share/rpcd/acl.d
cat > '/usr/share/rpcd/acl.d/luci-app-zapret-manager.json' << 'ZM_INSTALLER_EOF'
{
	"luci-app-zapret-manager": {
		"description": "Grant access to the Zapret Manager backend",
		"read": {
			"ubus": {
				"zapret-manager": [
					"status",
					"multi",
					"job_status",
					"log_tail",
					"system_info",
					"strategy_list_v",
					"strategy_list_flowseal",
					"strategy_list_youtube",
					"discord_status",
					"hosts_status",
					"hosts_file_get",
					"game_status",
					"system_status",
					"exclusions_status",
					"nfqws_opt_get",
					"zapret_lists_status",
					"zapret_list_get",
					"test_status",
					"test_results",
					"zm_update_status",
					"zm_changelog",
					"health",
					"versions",
					"term_status",
					"ui_flags_get"
				],
				"system": [
					"info"
				]
			}
		},
		"write": {
			"ubus": {
				"zapret-manager": [
					"zapret_action",
					"zapret2_action",
					"strategy_set_v",
					"strategy_set_flowseal",
					"strategy_set_youtube",
					"youtube_quic_set",
					"discord_set_dv",
					"discord_set_fake",
					"hosts_toggle",
					"hosts_replace_geohide",
					"hosts_reset",
					"hosts_file_set",
					"upload_part",
					"game_set",
					"game_set_fake",
					"game_toggle_xtreme",
					"system_check_connectivity",
					"system_toggle_quic",
					"system_toggle_ipv6",
					"system_toggle_flow_offloading_fix",
					"gh_proxy",
					"exclusions_toggle",
					"exclusions_clear",
					"nfqws_opt_set",
					"zapret_list_set",
					"zapret_list_restore",
					"test_action",
					"zapret_opt_set",
					"zm_update_action",
					"zm_changelog_seen",
					"autoupd",
					"term_action",
					"jobs_cancel",
					"ui_theme_set",
					"ui_nav_set",
					"ui_flag_set",
					"versions_mode",
					"system_reboot",
					"reboot_hint_clear"
				]
			}
		}
	}
}
ZM_INSTALLER_EOF
chmod 0644 '/usr/share/rpcd/acl.d/luci-app-zapret-manager.json'

mkdir -p /usr/share/luci/menu.d
chmod 0755 /usr/share/luci/menu.d
cat > '/usr/share/luci/menu.d/luci-app-zapret-manager.json' << 'ZM_INSTALLER_EOF'
{
	"admin/services/zapret-manager": {
		"title": "Zapret Manager",
		"order": 60,
		"action": {
			"type": "alias",
			"path": "admin/services/zapret-manager/dashboard"
		}
	},
	"admin/services/zapret-manager/dashboard": {
		"title": "Дашборд",
		"order": 10,
		"action": {
			"type": "view",
			"path": "zapret-manager/dashboard"
		}
	},
	"admin/services/zapret-manager/strategy": {
		"title": "Zapret",
		"order": 20,
		"action": {
			"type": "view",
			"path": "zapret-manager/strategy"
		}
	},
	"admin/services/zapret-manager/zapret2": {
		"title": "Zapret2",
		"order": 25,
		"action": {
			"type": "view",
			"path": "zapret-manager/zapret2"
		}
	},
	"admin/services/zapret-manager/hosts": {
		"title": "Hosts",
		"order": 40,
		"action": {
			"type": "view",
			"path": "zapret-manager/hosts"
		}
	},
	"admin/services/zapret-manager/terminal": {
		"title": "Терминал",
		"order": 53,
		"action": {
			"type": "view",
			"path": "zapret-manager/terminal"
		}
	}
}
ZM_INSTALLER_EOF
chmod 0644 '/usr/share/luci/menu.d/luci-app-zapret-manager.json'

mkdir -p /www/luci-static/resources/zapret-manager
chmod 0755 /www/luci-static/resources/zapret-manager
cat > '/www/luci-static/resources/zapret-manager/common.js' << 'ZM_INSTALLER_EOF'
'use strict';
'require baseclass';
'require rpc';
'require ui';

var E = function (raw) {
  return function () {
    var a = Array.prototype.slice.call(arguments),
      i = a.length - 1;
    if (i >= 1 && (typeof a[i] === 'string' || typeof a[i] === 'number')) a[i] = [String(a[i])];
    return raw.apply(null, a);
  };
}(window.E);
var UBUS_TEXT = {
  1: 'неверная команда',
  2: 'неверный параметр',
  3: 'метод не найден',
  4: 'не найдено',
  5: 'нет данных',
  6: 'нет доступа — выйдите и войдите заново',
  7: 'роутер не ответил вовремя',
  8: 'не поддерживается',
  9: 'ошибка',
  10: 'нет соединения'
};
var MULTI_RX = /^(status|system_info|health|versions|zm_update_status|lan_ip|[a-z0-9_]+_status|[a-z0-9_]+_get|strategy_list_[a-z0-9_]+)$/;
var MULTI_ARG = /^[A-Za-z0-9_.:@-]{1,64}$/;
var MULTI_NO = {
  system_info: 1,
  job_status: 1,
  log_tail: 1
};
var _mq = null,
  _multiOff = false,
  _multiFails = 0,
  _callMulti = null,
  _inflight = {};
function multiRun(q) {
  if (!_callMulti) _callMulti = rpc.declare({
    object: 'zapret-manager',
    method: 'multi',
    params: ['calls'],
    expect: {}
  });
  var direct = function (it) {
    it.direct().then(it.ok, it.bad);
  };
  _callMulti(q.map(function (it) {
    return it.m + (it.a != null ? '\t' + it.a : '');
  }).join('\n')).then(function (res) {
    if (typeof res === 'number') {
      _multiOff = true;
      throw new Error('multi: ubus ' + res);
    }
    var r = res && res.r;
    if (!Array.isArray(r) || r.length !== q.length) throw new Error('multi: bad reply');
    _multiFails = 0;
    q.forEach(function (it, i) {
      var v = r[i];
      if (v && typeof v === 'object' && !v.__fail) it.ok(v);else direct(it);
    });
  }).catch(function (e) {
    var t = String(e && e.message || e);
    if (/Method not found|Access denied|-32601|-32002/i.test(t) || ++_multiFails >= 2) _multiOff = true;
    q.forEach(direct);
  });
}
function multiFlush() {
  var q = _mq;
  _mq = null;
  _inflight = {};
  if (!q) return;
  if (q.length < 2 || _multiOff) {
    q.forEach(function (it) {
      it.direct().then(it.ok, it.bad);
    });
    return;
  }
  for (var i = 0; i < q.length; i += 12) multiRun(q.slice(i, i + 12));
}
function zmDeclare(o) {
  o.filter = function (r) {
    if (typeof r === 'number') return r === 0 ? {} : {
      error: 'Роутер: ' + (UBUS_TEXT[r] || 'ошибка ubus ' + r),
      ubus: r
    };
    return r == null ? {} : r;
  };
  var fn = rpc.declare(o);
  var canBatch = MULTI_RX.test(o.method || '') && !MULTI_NO[o.method] && (o.params || []).length <= 1;
  function single(self, args) {
    var left = 6;
    if (document.body.classList.contains('zmw-body')) return fn.apply(self, args);
    function go() {
      return fn.apply(self, args).catch(function (e) {
        if (left-- > 0 && /Object not found/i.test(String(e && e.message || e))) return new Promise(function (ok) {
          setTimeout(ok, 1500);
        }).then(go);
        throw e;
      });
    }
    return go();
  }
  return function () {
    var self = this,
      args = arguments,
      a = args.length ? args[0] : null;
    if (!canBatch || args.length > 1 || a != null && a !== '' && !MULTI_ARG.test(String(a))) return single(self, args);
    if (_multiOff) return single(self, args);
    var key = o.method + '\t' + (a != null ? String(a) : '');
    var p = _inflight[key];
    if (!p) {
      p = _inflight[key] = new Promise(function (ok, bad) {
        if (!_mq) {
          _mq = [];
          setTimeout(multiFlush, 0);
        }
        _mq.push({
          m: o.method,
          a: a != null && a !== '' ? String(a) : null,
          ok: ok,
          bad: bad,
          direct: function () {
            return single(self, args);
          }
        });
      });
    }
    return p.then(function (v) {
      return v && typeof v === 'object' ? JSON.parse(JSON.stringify(v)) : v;
    });
  };
}
var callStatus = zmDeclare({
  object: 'zapret-manager',
  method: 'status',
  expect: {}
});
var callTermStatus = zmDeclare({
  object: 'zapret-manager',
  method: 'term_status',
  expect: {}
});
var callTermAction = zmDeclare({
  object: 'zapret-manager',
  method: 'term_action',
  params: ['action', 'mode'],
  expect: {}
});
var callUiFlagsGet = zmDeclare({
  object: 'zapret-manager',
  method: 'ui_flags_get',
  expect: {}
});
var callUiFlagSet = zmDeclare({
  object: 'zapret-manager',
  method: 'ui_flag_set',
  params: ['name'],
  expect: {}
});
var callSystemInfo = zmDeclare({
  object: 'zapret-manager',
  method: 'system_info',
  expect: {}
});
var callVersions = zmDeclare({
  object: 'zapret-manager',
  method: 'versions',
  params: ['action'],
  expect: {}
});
var callJobStatus = zmDeclare({
  object: 'zapret-manager',
  method: 'job_status',
  params: ['job'],
  expect: {}
});
var callLogTail = zmDeclare({
  object: 'zapret-manager',
  method: 'log_tail',
  params: ['job'],
  expect: {}
});
var callZapretAction = zmDeclare({
  object: 'zapret-manager',
  method: 'zapret_action',
  params: ['action'],
  expect: {}
});
var callZapret2Action = zmDeclare({
  object: 'zapret-manager',
  method: 'zapret2_action',
  params: ['action'],
  expect: {}
});
var callStrategyListV = zmDeclare({
  object: 'zapret-manager',
  method: 'strategy_list_v',
  expect: {}
});
var callStrategySetV = zmDeclare({
  object: 'zapret-manager',
  method: 'strategy_set_v',
  params: ['version'],
  expect: {}
});
var callStrategyListFlowseal = zmDeclare({
  object: 'zapret-manager',
  method: 'strategy_list_flowseal',
  params: ['action'],
  expect: {}
});
var callStrategySetFlowseal = zmDeclare({
  object: 'zapret-manager',
  method: 'strategy_set_flowseal',
  params: ['name'],
  expect: {}
});
var callStrategyListYoutube = zmDeclare({
  object: 'zapret-manager',
  method: 'strategy_list_youtube',
  params: ['action'],
  expect: {}
});
var callStrategySetYoutube = zmDeclare({
  object: 'zapret-manager',
  method: 'strategy_set_youtube',
  params: ['name'],
  expect: {}
});
var callYoutubeQuicSet = zmDeclare({
  object: 'zapret-manager',
  method: 'youtube_quic_set',
  params: ['mode'],
  expect: {}
});
var callDiscordStatus = zmDeclare({
  object: 'zapret-manager',
  method: 'discord_status',
  expect: {}
});
var callDiscordSetDv = zmDeclare({
  object: 'zapret-manager',
  method: 'discord_set_dv',
  params: ['num'],
  expect: {}
});
var callDiscordSetFake = zmDeclare({
  object: 'zapret-manager',
  method: 'discord_set_fake',
  params: ['file'],
  expect: {}
});
var callGameStatus = zmDeclare({
  object: 'zapret-manager',
  method: 'game_status',
  expect: {}
});
var callGameSet = zmDeclare({
  object: 'zapret-manager',
  method: 'game_set',
  params: ['choice'],
  expect: {}
});
var callGameSetFake = zmDeclare({
  object: 'zapret-manager',
  method: 'game_set_fake',
  params: ['file'],
  expect: {}
});
var callGameToggleXtreme = zmDeclare({
  object: 'zapret-manager',
  method: 'game_toggle_xtreme',
  expect: {}
});
var callSystemStatus = zmDeclare({
  object: 'zapret-manager',
  method: 'system_status',
  expect: {}
});
var callSystemToggleIpv6 = zmDeclare({
  object: 'zapret-manager',
  method: 'system_toggle_ipv6',
  params: ['mode'],
  expect: {}
});
var callSystemToggleFlowOffloadingFix = zmDeclare({
  object: 'zapret-manager',
  method: 'system_toggle_flow_offloading_fix',
  params: ['mode'],
  expect: {}
});
var callGhProxy = zmDeclare({
  object: 'zapret-manager',
  method: 'gh_proxy',
  params: ['action', 'value'],
  expect: {}
});
var callExclusionsStatus = zmDeclare({
  object: 'zapret-manager',
  method: 'exclusions_status',
  expect: {}
});
var callExclusionsToggle = zmDeclare({
  object: 'zapret-manager',
  method: 'exclusions_toggle',
  params: ['ip'],
  expect: {}
});
var callExclusionsClear = zmDeclare({
  object: 'zapret-manager',
  method: 'exclusions_clear',
  expect: {}
});
var callZapretListsStatus = zmDeclare({
  object: 'zapret-manager',
  method: 'zapret_lists_status',
  expect: {}
});
var callZapretListGet = zmDeclare({
  object: 'zapret-manager',
  method: 'zapret_list_get',
  params: ['id'],
  expect: {}
});
var callZapretListSet = zmDeclare({
  object: 'zapret-manager',
  method: 'zapret_list_set',
  params: ['id', 'content'],
  expect: {}
});
var callZapretListRestore = zmDeclare({
  object: 'zapret-manager',
  method: 'zapret_list_restore',
  params: ['id'],
  expect: {}
});
var callNfqwsOptGet = zmDeclare({
  object: 'zapret-manager',
  method: 'nfqws_opt_get',
  expect: {}
});
var callNfqwsOptSet = zmDeclare({
  object: 'zapret-manager',
  method: 'nfqws_opt_set',
  params: ['content'],
  expect: {}
});
var callHostsStatus = zmDeclare({
  object: 'zapret-manager',
  method: 'hosts_status',
  expect: {}
});
var callHostsToggle = zmDeclare({
  object: 'zapret-manager',
  method: 'hosts_toggle',
  params: ['block'],
  expect: {}
});
var callHostsReplaceGeohide = zmDeclare({
  object: 'zapret-manager',
  method: 'hosts_replace_geohide',
  params: ['region'],
  expect: {}
});
var callHostsReset = zmDeclare({
  object: 'zapret-manager',
  method: 'hosts_reset',
  expect: {}
});
var callHostsFileGet = zmDeclare({
  object: 'zapret-manager',
  method: 'hosts_file_get',
  expect: {}
});
var callHostsFileSet = zmDeclare({
  object: 'zapret-manager',
  method: 'hosts_file_set',
  params: ['content'],
  expect: {}
});
var callUploadPart = zmDeclare({
  object: 'zapret-manager',
  method: 'upload_part',
  params: ['content', 'part'],
  expect: {}
});
function bigSend(text, fn) {
  if (typeof text !== 'string' || text.length <= 16000) return fn(text);
  var CH = 16000,
    parts = [],
    i = 0;
  while (i < text.length) {
    var e = Math.min(i + CH, text.length),
      c = text.charCodeAt(e - 1);
    if (e < text.length && c >= 0xD800 && c <= 0xDBFF) e--;
    parts.push(text.slice(i, e));
    i = e;
  }
  return parts.reduce(function (p, chunk, k) {
    return p.then(function (r) {
      return r && r.error ? r : callUploadPart(chunk, k ? 'next' : 'first');
    });
  }, Promise.resolve({})).then(function (r) {
    return r && r.error ? r : fn('@zmupload');
  });
}
function bigText(call) {
  return function (text) {
    return bigSend(text, function (v) {
      return call(v);
    });
  };
}
function bigArg2(call) {
  return function (a, text) {
    return bigSend(text, function (v) {
      return call(a, v);
    });
  };
}
var callTestStatus = zmDeclare({
  object: 'zapret-manager',
  method: 'test_status',
  expect: {}
});
var callTestAction = zmDeclare({
  object: 'zapret-manager',
  method: 'test_action',
  params: ['action', 'mode'],
  expect: {}
});
var callTestResults = zmDeclare({
  object: 'zapret-manager',
  method: 'test_results',
  params: ['mode'],
  expect: {}
});
var callZapretOptSet = zmDeclare({
  object: 'zapret-manager',
  method: 'zapret_opt_set',
  params: ['opt'],
  expect: {}
});
var callZmUpdateStatus = zmDeclare({
  object: 'zapret-manager',
  method: 'zm_update_status',
  expect: {}
});
var callZmUpdateAction = zmDeclare({
  object: 'zapret-manager',
  method: 'zm_update_action',
  expect: {}
});
var callZmChangelog = zmDeclare({
  object: 'zapret-manager',
  method: 'zm_changelog',
  params: ['mode'],
  expect: {}
});
var callZmChangelogSeen = zmDeclare({
  object: 'zapret-manager',
  method: 'zm_changelog_seen',
  expect: {}
});
function zmUpdateNotify(u) {
  if (!u || u.error || !u.current) return;
  try {
    window.dispatchEvent(new CustomEvent('zm:update', {
      detail: {
        current: u.current,
        latest: u.latest || '',
        newer: u.newer
      }
    }));
  } catch (e) {}
}
function zmUpdateFromVersions(d) {
  var it = (d && d.items || []).filter(function (x) {
    return x && x.name === 'Zapret Manager';
  })[0];
  if (!it || !it.installed) return null;
  return {
    current: it.installed,
    latest: it.latest || it.installed,
    newer: !!it.latest && it.latest !== it.installed
  };
}
var callHealth = zmDeclare({
  object: 'zapret-manager',
  method: 'health',
  expect: {}
});
var callSystemReboot = zmDeclare({
  object: 'zapret-manager',
  method: 'system_reboot',
  expect: {}
});
var callRebootHintClear = zmDeclare({
  object: 'zapret-manager',
  method: 'reboot_hint_clear',
  expect: {}
});
var callBoardInfo = rpc.declare({
  object: 'system',
  method: 'info',
  expect: {}
});
var callJobsCancel = zmDeclare({
  object: 'zapret-manager',
  method: 'jobs_cancel',
  params: ['job'],
  expect: {}
});
function parseSize(v) {
  var m = String(v == null ? '' : v).trim().match(/^([\d.,]+)\s*([KMGT]?)i?B?$/i);
  if (!m) return NaN;
  return parseFloat(m[1].replace(',', '.')) * {
    '': 1,
    K: 1024,
    M: 1048576,
    G: 1073741824,
    T: 1099511627776
  }[m[2].toUpperCase()];
}
function fmtSize(b) {
  if (!isFinite(b)) return '—';
  var u = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'],
    i = 0;
  while (b >= 1024 && i < u.length - 1) {
    b /= 1024;
    i++;
  }
  return (b >= 100 || i === 0 ? Math.round(b) : b.toFixed(1).replace(/\.0$/, '')) + ' ' + u[i];
}
function stateBadge(st, textOk) {
  if (st === 1) return badge(true, textOk || 'запущен', '');
  if (st === 2) return badge(false, '', 'остановлен');
  return badge(false, '', 'не установлен');
}
function detectMissingThemeVar() {
  if (document.documentElement.hasAttribute('data-zm-theme-checked')) return;
  document.documentElement.setAttribute('data-zm-theme-checked', '1');
  try {
    var hd = document.documentElement;
    if (hd.getAttribute('data-darkmode') === 'true') {
      hd.classList.add('zm-theme-dark');
      return;
    }
    var el = document.body,
      bg = '',
      hops = 0;
    while (el && hops < 6) {
      var c = getComputedStyle(el).backgroundColor;
      if (c && c !== 'rgba(0, 0, 0, 0)' && c !== 'transparent') {
        bg = c;
        break;
      }
      el = el.parentElement;
      hops++;
    }
    var lum = function (c) {
      var m = String(c || '').match(/rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/);
      return m ? (0.299 * +m[1] + 0.587 * +m[2] + 0.114 * +m[3]) / 255 : -1;
    };
    var lb = lum(bg),
      lt = lum(getComputedStyle(document.body).color);
    if (lb >= 0 && lb < 0.5 || lt > 0.7) document.documentElement.classList.add('zm-theme-dark');
  } catch (e) {}
}
var ZM_BUILD = '__ZM_BUILD__';
function cssUrl(path) {
  return L.resource(path) + (/^[0-9]{6,}$/.test(ZM_BUILD) ? '?v=' + ZM_BUILD : '');
}
var cacheGuardDone = false;
function cacheGuard() {
  if (cacheGuardDone) return;
  cacheGuardDone = true;
  try {
    if (document.body.classList.contains('zmw-body') || !window.fetch) return;
    var base = String(L.env.base_url || L.resource('x').replace(/\/x$/, '')),
      ver = L.env.resource_version;
    var ls = function (k, v) {
      try {
        if (v === undefined) return localStorage.getItem(k);
        localStorage.setItem(k, v);
      } catch (e) {}
      return null;
    };
    var ss = function (k, v) {
      try {
        if (v === undefined) return sessionStorage.getItem(k);
        sessionStorage.setItem(k, v);
      } catch (e) {}
      return null;
    };
    var grab = function (url, mode) {
      return fetch(url, {
        cache: mode
      }).then(function (r) {
        return r.ok ? r.text() : null;
      }).catch(function () {
        return null;
      });
    };
    var pool = function (list, fn) {
      var i = 0,
        run = function () {
          if (i >= list.length) return Promise.resolve();
          var x = list[i++];
          return fn(x).then(run, run);
        };
      return Promise.all([run(), run(), run(), run()]);
    };
    fetch(base + '/zapret-manager/build.txt?t=' + Date.now(), {
      cache: 'no-store'
    }).then(function (r) {
      return r.ok ? r.text() : '';
    }).then(function (txt) {
      var lines = String(txt || '').split(/\r?\n/).map(function (x) {
        return x.trim();
      }).filter(Boolean);
      var build = lines.shift();
      if (!/^[0-9]{6,}$/.test(build || '')) return;
      var files = lines.filter(function (p) {
        return /^[A-Za-z0-9_\/.-]+\.(js|css)$/.test(p) && p.indexOf('..') < 0;
      });
      var urls = [];
      files.forEach(function (p) {
        urls.push(base + '/' + p);
        if (/\.js$/.test(p) && ver != null) urls.push(base + '/' + p + '?v=' + ver);
        if (/\.css$/.test(p)) urls.push(base + '/' + p + '?v=' + build);
      });
      var reload = function () {
        var n = +(ss('zm.reload.' + build) || 0);
        if (n >= 2) return;
        ss('zm.reload.' + build, String(n + 1));
        toast('Панель обновлена — загружаем новую версию', 'info');
        setTimeout(function () {
          location.reload();
        }, 600);
      };
      if (/^[0-9]{6,}$/.test(ZM_BUILD) && ZM_BUILD !== build) {
        return pool(urls, function (u) {
          return grab(u, 'reload');
        }).then(function () {
          ls('zm.build', build);
          reload();
        });
      }
      if (ls('zm.build') === build) return;
      var stale = false;
      return pool(urls, function (u) {
        return grab(u, 'force-cache').then(function (a) {
          return grab(u, 'reload').then(function (b) {
            if (a != null && b != null && a !== b) stale = true;
          });
        });
      }).then(function () {
        ls('zm.build', build);
        if (stale) reload();
      });
    }).catch(function () {});
  } catch (e) {}
}
var FLAG_FONT = 'https://cdn.jsdelivr.net/npm/country-flag-emoji-polyfill@0.1/dist/TwemojiCountryFlags.woff2';
function flagsOk() {
  try {
    var c = document.createElement('canvas');
    c.width = c.height = 24;
    var x = c.getContext('2d', {
      willReadFrequently: true
    });
    if (!x) return true;
    x.textBaseline = 'top';
    x.font = '20px sans-serif';
    x.fillStyle = '#000';
    x.fillText('\uD83C\uDDE8\uD83C\uDDED', 0, 0);
    var d = x.getImageData(0, 0, 24, 24).data;
    for (var i = 0; i < d.length; i += 4) if (d[i + 3] && (d[i] !== d[i + 1] || d[i + 1] !== d[i + 2])) return true;
    return false;
  } catch (e) {
    return true;
  }
}
function flagFont() {
  if (document.getElementById('zm-flags') || flagsOk()) return;
  var fam = '';
  try {
    fam = getComputedStyle(document.body).fontFamily || '';
  } catch (e) {}
  var s = document.createElement('style');
  s.id = 'zm-flags';
  s.textContent = '@font-face{font-family:"Twemoji Country Flags";unicode-range:U+1F1E6-1F1FF,U+1F3F4,U+E0062-E0063,U+E0065,U+E0067,U+E006C,U+E006E,U+E0073-E0074,U+E0077,U+E007F;src:url("' + FLAG_FONT + '") format("woff2");font-display:swap}' + 'body,.zm-wrap{font-family:"Twemoji Country Flags",' + (fam || 'system-ui,sans-serif') + '}';
  document.head.appendChild(s);
}
var CL_HISTORY = 'https://github.com/Screamshow/Zapret-Manager/blob/main/CHANGELOG.md';
var CL_KINDS = {
  '➕': ['new', 'Новое'],
  '⚡': ['imp', 'Улучшено'],
  '🐞': ['fix', 'Исправлено'],
  '🗑': ['del', 'Убрано']
};
function clParse(text) {
  var secs = [],
    cur = null;
  function sec(title) {
    cur = {
      title: title,
      items: []
    };
    secs.push(cur);
  }
  String(text || '').split('\n').forEach(function (line, i) {
    var l = line.replace(/\*\*|`/g, '').replace(/\s+$/, ''),
      kind = null,
      k,
      m;
    if (!l.trim() || /^-{3,}$/.test(l.trim()) || /^##\s/.test(l)) return;
    if (m = /^###\s+(.+)$/.exec(l)) {
      sec(m[1].trim());
      return;
    }
    var item = /^\s*[-*+]\s+/.test(l);
    l = l.replace(/^\s*[-*+]\s+/, '').trim();
    for (k in CL_KINDS) if (l.indexOf(k) === 0) {
      kind = CL_KINDS[k];
      l = l.slice(k.length).replace(/^[️\s]+/, '');
      break;
    }
    if (!item && !kind && l.length <= 40 && i > 0 && (!cur || cur.items.length || !cur.title)) {
      sec(l);
      return;
    }
    if (!item && !kind && i === 0) return;
    if (!cur) sec('');
    cur.items.push({
      kind: kind,
      text: l
    });
  });
  return secs.filter(function (s) {
    return s.items.length;
  });
}
function changelogDialog(o) {
  return new Promise(function (resolve) {
    var wrap,
      prevFocus = document.activeElement,
      id = 'zm-cl-' + Date.now();
    var blocks = o.blocks || [{
      version: o.version,
      date: o.date,
      text: o.text
    }];
    function close(go) {
      dlgDone(close);
      document.removeEventListener('keydown', onKey, true);
      if (wrap && wrap.parentNode) wrap.parentNode.removeChild(wrap);
      document.documentElement.classList.remove('zm-wn-lock');
      try {
        if (prevFocus && prevFocus.focus) prevFocus.focus({
          preventScroll: true
        });
      } catch (e) {}
      resolve(!!go);
    }
    function onKey(ev) {
      if (ev.key === 'Escape') {
        ev.preventDefault();
        close(false);
      }
    }
    var body = [];
    blocks.forEach(function (b) {
      var secs = clParse(b.text);
      if (!secs.length) return;
      if (b.version) body.push(E('div', {
        'class': 'zm-cl-ver'
      }, [b.version, b.date ? E('small', {}, b.date) : '', o.current && b.version === o.current && blocks.length > 1 ? E('span', {
        'class': 'zm-cl-cur'
      }, 'установлена') : '']));
      secs.forEach(function (s) {
        if (s.title) body.push(E('div', {
          'class': 'zm-cl-sec'
        }, s.title));
        body.push(E('ul', {
          'class': 'zm-wn-list'
        }, s.items.map(function (it) {
          return E('li', {
            'class': it.kind ? '' : 'zm-cl-plain'
          }, [it.kind ? E('span', {
            'class': 'zm-cl-tag zm-cl-' + it.kind[0]
          }, it.kind[1]) : '', E('div', {}, it.text)]);
        })));
      });
    });
    var btns = o.onUpdate ? [E('button', {
      'class': 'cbi-button',
      'click': function () {
        close(false);
      }
    }, 'Позже'), E('button', {
      'class': 'cbi-button cbi-button-positive',
      'click': function () {
        close(true);
        o.onUpdate();
      }
    }, 'Обновить панель')] : [E('button', {
      'class': 'cbi-button cbi-button-positive',
      'click': function () {
        close(true);
      }
    }, o.okText || 'Понятно')];
    wrap = E('div', {
      'class': 'zm-dlg-wrap zm-wn-wrap',
      'role': 'dialog',
      'aria-modal': 'true',
      'aria-labelledby': id,
      'click': function (ev) {
        if (ev.target === wrap) close(false);
      }
    }, [E('div', {
      'class': 'zm-card zm-dlg zmw-modal zm-wn zm-wn-info zm-cl',
      'tabindex': '-1'
    }, [E('div', {
      'class': 'zm-wn-body'
    }, [E('div', {
      'class': 'zm-wn-head'
    }, [E('h3', {
      'id': id
    }, o.title)]), o.lead ? E('p', {
      'class': 'zm-wn-lead'
    }, o.lead) : ''].concat(body)), E('div', {
      'class': 'zm-actions zm-dlg-actions zm-wn-foot zm-cl-foot' + (o.noLink ? ' zm-cl-foot-solo' : '')
    }, [o.noLink ? '' : E('a', {
      'class': 'zm-cl-all',
      'href': CL_HISTORY,
      'target': '_blank',
      'rel': 'noreferrer'
    }, 'Вся история изменений'), E('div', {
      'class': 'zm-cl-btns'
    }, btns)])])]);
    document.documentElement.classList.add('zm-wn-lock');
    document.body.appendChild(wrap);
    dlgTrack(close, false);
    document.addEventListener('keydown', onKey, true);
    setTimeout(function () {
      try {
        wrap.querySelector('.zm-wn').focus({
          preventScroll: true
        });
      } catch (e) {}
    }, 0);
  });
}
function clBlocks(text) {
  var out = [],
    cur = null;
  String(text || '').split('\n').forEach(function (l) {
    if (/^##\s/.test(l)) {
      cur = {
        version: (/\d+\.\d+(?:\.\d+)?/.exec(l) || [''])[0],
        date: (/\d{2}\.\d{2}\.\d{4}/.exec(l) || [''])[0],
        lines: [l]
      };
      out.push(cur);
    } else {
      if (!cur) {
        cur = {
          version: '',
          date: '',
          lines: []
        };
        out.push(cur);
      }
      cur.lines.push(l);
    }
  });
  return out.map(function (b) {
    if (!b.version) {
      var f = b.lines.filter(function (x) {
        return x.trim();
      })[0] || '';
      b.version = (/\d+\.\d+(?:\.\d+)?/.exec(f) || [''])[0];
    }
    return {
      version: b.version,
      date: b.date,
      text: b.lines.join('\n')
    };
  });
}
function changelogShow(mode, o) {
  o = o || {};
  return callZmChangelog(mode).then(function (r) {
    if (mode === 'all') {
      if (!r || r.error || !r.text) {
        toast(r && r.error ? r.error : 'Не удалось получить список изменений', 'warning');
        return false;
      }
      return changelogDialog({
        title: 'Список изменений',
        blocks: clBlocks(r.text),
        current: r.current,
        okText: 'Закрыть',
        noLink: true,
        lead: r.source === 'local' ? 'GitHub недоступен — показана копия, сохранённая при установке.' : ''
      });
    }
    if (!r || r.error) {
      if (mode === 'remote') toast(r && r.error ? r.error : 'Не удалось получить список изменений', 'warning');
      return false;
    }
    if (mode === 'remote') {
      if (!r.text || o.want && r.version !== o.want) {
        toast('Список изменений для версии ' + (o.want || '') + ' ещё не опубликован', 'info');
        return false;
      }
      return changelogDialog({
        title: 'Что изменится в ' + r.version,
        lead: 'Сейчас установлена ' + (o.current || r.current) + '. Настройки после обновления сохранятся.',
        version: r.version,
        date: r.date,
        text: r.text,
        onUpdate: o.onUpdate
      });
    }
    if (!r.pending) return false;
    var match = r.text && r.version === r.current;
    return changelogDialog({
      title: 'Что нового в Zapret Manager ' + r.current,
      lead: r.from ? 'Панель обновлена: ' + r.from + ' → ' + r.current + (match ? '' : '. Список изменений не загрузился — его можно открыть на GitHub.') : '',
      version: r.version,
      date: r.date,
      text: match ? r.text : ''
    }).then(function () {
      callZmChangelogSeen().catch(function () {});
    });
  }).catch(function () {
    return false;
  });
}
var _clAuto = false;
function changelogAuto() {
  if (_clAuto) return;
  _clAuto = true;
  setTimeout(function () {
    changelogShow('local');
  }, 700);
}
function injectCss() {
  cacheGuard();
  try {
    flagFont();
  } catch (e) {}
  detectMissingThemeVar();
  changelogAuto();
  if (document.getElementById('zm-css')) return;
  var l = document.createElement('link');
  l.id = 'zm-css';
  l.rel = 'stylesheet';
  l.href = cssUrl('view/zapret-manager/style.css');
  document.head.appendChild(l);
}
function badge(ok, textOk, textBad) {
  var cls = ok ? 'zm-ok' : textBad === 'не установлен' ? 'zm-off' : 'zm-bad';
  return E('span', {
    'class': 'zm-badge ' + cls
  }, [E('span', {
    'class': 'zm-dot'
  }), ok ? textOk : textBad]);
}
function logMinPref() {
  try {
    return localStorage.getItem('zm.log.min') === '1';
  } catch (e) {
    return false;
  }
}
function logBar(logEl) {
  if (!logEl._zmBar) {
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'zm-log-min';
    var sync = function () {
      var min = logEl.classList.contains('zm-log-collapsed');
      btn.textContent = min ? '▢' : '_';
      btn.title = min ? 'Развернуть вывод' : 'Свернуть вывод';
    };
    btn.addEventListener('click', function (ev) {
      ev.preventDefault();
      ev.stopPropagation();
      var min = !logEl.classList.contains('zm-log-collapsed');
      logEl.classList.toggle('zm-log-collapsed', min);
      try {
        localStorage.setItem('zm.log.min', min ? '1' : '0');
      } catch (e) {}
      sync();
      logEl.scrollTop = logEl.scrollHeight;
    });
    var bar = document.createElement('div');
    bar.className = 'zm-log-bar';
    bar.appendChild(btn);
    logEl._zmBar = bar;
    logEl._zmSync = sync;
    if (logMinPref()) logEl.classList.add('zm-log-collapsed');
  }
  logEl._zmSync();
  return logEl._zmBar;
}
function renderLog(logEl, text) {
  logEl.innerHTML = '';
  var lines = (text || '').split('\n');
  if (lines.some(function (l) {
    return l !== '';
  })) logEl.appendChild(logBar(logEl));
  lines.forEach(function (line) {
    if (line === '') return;
    var div = document.createElement('div');
    var m = line.match(/^(==>)\s?(.*)$/);
    if (m) {
      var arrow = document.createElement('span');
      arrow.className = 'zm-log-arrow';
      arrow.textContent = m[1] + ' ';
      div.appendChild(arrow);
      var msgSpan = document.createElement('span');
      var msg = m[2];
      if (/ОШИБКА|error|не удалось/i.test(msg)) msgSpan.className = 'zm-log-msg-error';else if (/Готово|успешно|примен[её]н|установлен|удал[её]н|сгенерирован|сохран[её]н|переключ[её]н|обновл[её]н|заверш[её]н/i.test(msg) && !/(^|[\s(«])не\s+(примен[её]н|установлен|удал[её]н|сгенерирован|сохран[её]н|переключ[её]н|обновл[её]н|заверш[её]н)/i.test(msg)) msgSpan.className = 'zm-log-msg-ok';else msgSpan.className = 'zm-log-msg-info';
      msgSpan.textContent = msg;
      div.appendChild(msgSpan);
    } else if (/^\s*Подождите/.test(line)) {
      div.className = 'zm-log-wait';
      div.textContent = line.replace(/^\s+/, '');
    } else if (/^\s*(ОШИБКА|\[FAIL\])/.test(line)) {
      div.className = 'zm-log-msg-error';
      div.textContent = line;
    } else if (/^\s*\[ OK \]/.test(line)) {
      div.className = 'zm-log-step zm-log-step-ok';
      div.textContent = line;
    } else if (/^\s*✓/.test(line)) {
      div.className = 'zm-log-step zm-log-step-ok';
      div.textContent = line;
    } else if (/^\s*✗/.test(line)) {
      div.className = 'zm-log-step zm-log-step-bad';
      div.textContent = line;
    } else if (/^\s*[→↻]/.test(line)) {
      div.className = 'zm-log-step';
      div.textContent = line;
    } else if (/^\s+!/.test(line)) {
      div.className = 'zm-log-msg-warn';
      div.textContent = line;
    } else if (/^!!/.test(line)) {
      div.className = 'zm-log-msg-warn';
      div.textContent = line;
    } else {
      div.className = 'zm-log-code';
      div.textContent = line;
    }
    logEl.appendChild(div);
  });
  logEl.scrollTop = logEl.scrollHeight;
}
var _dockEl = null,
  _dockBars = [];
function dockEl() {
  if (!_dockEl || !document.body.contains(_dockEl)) {
    _dockEl = E('div', {
      'class': 'zm-dock'
    });
    document.body.appendChild(_dockEl);
  }
  return _dockEl;
}
function dockCtx(ph) {
  var n = ph && ph.parentNode,
    depth = 0,
    h;
  while (n && n !== document.body && depth < 8) {
    h = n.querySelector && n.querySelector('h3, h4');
    if (h && h.textContent) return h.textContent.replace(/\s+/g, ' ').trim().slice(0, 40);
    n = n.parentNode;
    depth++;
  }
  return '';
}
function dockSync() {
  var dk = _dockEl,
    live = [];
  _dockBars.forEach(function (el) {
    var inPage = el.parentNode && el.parentNode !== dk && document.body.contains(el);
    if (inPage) {
      if (!el._zmPh) el._zmPh = E('span', {
        'class': 'zm-dock-ph',
        'style': 'display:none'
      });
      if (el._zmPh.nextSibling !== el) el.parentNode.insertBefore(el._zmPh, el);
    }
    var ph = el._zmPh,
      phIn = !!(ph && document.body.contains(ph));
    if (!phIn && !inPage) {
      if (dk && el.parentNode === dk) dk.removeChild(el);
      return;
    }
    live.push(el);
    var vis = phIn && ph.parentNode.getClientRects().length > 0;
    if (el._zmWant && vis && el.style.display !== 'none') {
      if (el.parentNode !== dockEl()) {
        dk = _dockEl;
        dk.appendChild(el);
      }
    } else if (dk && el.parentNode === dk) {
      if (phIn) ph.parentNode.insertBefore(el, ph.nextSibling);else dk.removeChild(el);
    }
  });
  _dockBars = live;
  if (!_dockEl) return;
  var shown = Array.prototype.filter.call(_dockEl.children, function (el) {
    return el.style.display !== 'none';
  });
  var bars = shown.filter(function (el) {
    return !el._zmGlobal;
  });
  bars.forEach(function (el) {
    var c = bars.length > 1 ? dockCtx(el._zmPh) : '';
    if (c !== (el._zmCtx || '')) {
      el._zmCtx = c;
      if (el._zmRender) el._zmRender();
    }
  });
  _dockEl.classList.toggle('zm-dock-on', shown.length > 0);
  var pad = shown.length ? _dockEl.offsetHeight + 28 + 'px' : '';
  var padEl = document.querySelector('.zmw-main') || document.body;
  if (padEl !== document.body && document.body.style.paddingBottom) document.body.style.paddingBottom = '';
  if (padEl.style.paddingBottom !== pad) padEl.style.paddingBottom = pad;
  toastFit();
}
function dock(el, show) {
  el._zmWant = !!show;
  if (_dockBars.indexOf(el) < 0) _dockBars.push(el);
  dockSync();
  if (show && el.parentNode !== _dockEl) {
    el._zmTry = (el._zmTry || 0) + 1;
    if (el._zmTry < 15) setTimeout(function () {
      if (el._zmWant) dock(el, true);
    }, 300);
  } else el._zmTry = 0;
}
setInterval(dockSync, 600);
window.addEventListener('hashchange', function () {
  setTimeout(dockSync, 50);
});
var _activePolls = {};
var JOB_NAMES = {
  strategy_test: 'тест стратегий',
  zm_update: 'обновление панели',
};
var _stuck = {},
  _stopEl = null,
  _stopBusy = false;
function jobName(j) {
  if (JOB_NAMES[j]) return JOB_NAMES[j];
  if (/zapret2/.test(j)) return 'Zapret2';
  if (/zapret/.test(j)) return 'Zapret';
  return j;
}
function stopAll() {
  if (_stopBusy) return;
  return ask('Остановить все операции?\n\nВсе их процессы будут принудительно завершены. Если прервать установку, её можно просто запустить заново.').then(function (ok) {
    if (!ok) return;
    _stopBusy = true;
    renderStopBar();
    callJobsCancel('').then(function (res) {
      _stopBusy = false;
      if (res && res.error) {
        toast(res.error, 'error');
        renderStopBar();
        return;
      }
      var n = (res && res.stopped || []).length;
      toast(n ? 'Остановлено: ' + res.stopped.map(jobName).join(', ') : 'Активных операций не было', n ? 'warning' : 'info');
      _stuck = {};
      renderStopBar();
    }).catch(function () {
      _stopBusy = false;
      renderStopBar();
      toast('Роутер не ответил — попробуйте ещё раз', 'error');
    });
  });
}
function renderStopBar() {
  var keys = Object.keys(_stuck);
  if (!keys.length) {
    if (_stopEl && _stopEl.parentNode) _stopEl.parentNode.removeChild(_stopEl);
    _stopEl = null;
    dockSync();
    return;
  }
  var mins = Math.max.apply(null, keys.map(function (k) {
    return _stuck[k];
  }));
  mins = Math.max(2, Math.floor(mins / 60));
  if (!_stopEl) {
    _stopEl = E('div', {
      'class': 'zm-stopbar',
      'role': 'alert'
    });
    _stopEl._zmGlobal = true;
    _stopEl._t = E('b', {});
    _stopEl._b = E('button', {
      'class': 'cbi-button zm-stopbar-btn',
      'click': stopAll
    });
    _stopEl.appendChild(E('div', {
      'class': 'zm-stopbar-text'
    }, [_stopEl._t, E('span', {}, 'Если она зависла — остановите её. Роутер завершит все её процессы.')]));
    _stopEl.appendChild(_stopEl._b);
  }
  _stopEl._t.textContent = 'Операция «' + keys.map(jobName).join(', ') + '» не отвечает уже ' + mins + ' мин';
  _stopEl._b.disabled = !!_stopBusy;
  _stopEl._b.textContent = _stopBusy ? 'Останавливаем…' : 'Остановить все операции';
  if (_stopEl.parentNode !== dockEl()) dockEl().insertBefore(_stopEl, dockEl().firstChild);
  dockSync();
}
function pollJob(job, logEl, onDone, onTick) {
  if (_activePolls[job]) {
    clearInterval(_activePolls[job]);
    delete _activePolls[job];
  }
  logEl.classList.add('zm-show');
  var failCount = 0;
  var finished = false,
    inFlight = false,
    gone = 0,
    startHash = location.hash;
  var lastSig = null,
    progAt = Date.now(),
    lastTxt = '',
    deadPolls = 0;
  function end(ok) {
    finished = true;
    clearInterval(timer);
    delete _activePolls[job];
    if (_stuck[job] != null) {
      delete _stuck[job];
      renderStopBar();
    }
    onDone(ok);
  }
  var timer = setInterval(function () {
    if (finished || inFlight) return;
    if (location.hash !== startHash && !document.body.contains(logEl)) {
      if (++gone >= 3) {
        finished = true;
        clearInterval(timer);
        if (_activePolls[job] === timer) delete _activePolls[job];
        if (_stuck[job] != null) {
          delete _stuck[job];
          renderStopBar();
        }
      }
      return;
    }
    gone = 0;
    inFlight = true;
    Promise.all([callJobStatus(job), callLogTail(job)]).then(function (res) {
      inFlight = false;
      if (finished) return;
      failCount = 0;
      var st = res[0],
        lg = res[1];
      var txt = lg && lg.lines || '';
      if (lg && lg.error && !txt) txt = lastTxt || '==> Журнал операции не прочитался: ' + lg.error;
      lastTxt = txt;
      var sig = txt.split('\n').filter(function (l) {
        return !/^\s*Подождите/.test(l);
      }).join('\n');
      if (sig !== lastSig) {
        lastSig = sig;
        progAt = Date.now();
      }
      renderLog(logEl, txt);
      var idle = Math.round((Date.now() - progAt) / 1000);
      var done = !!(st && st.done === true);
      var tl = txt.replace(/\s+$/, ''),
        lastLine = tl.slice(tl.lastIndexOf('\n') + 1);
      if (!done && idle >= 20 && !/^\s*Подождите/.test(lastLine)) {
        var w = document.createElement('div');
        w.className = 'zm-log-wait';
        w.textContent = 'Подождите ' + new Array(Math.floor((idle - 20) / 5) + 2).join('.');
        logEl.appendChild(w);
        logEl.scrollTop = logEl.scrollHeight;
      }
      var was = _stuck[job] != null;
      if (!done && idle >= 120) _stuck[job] = idle;else delete _stuck[job];
      if (was || _stuck[job] != null) renderStopBar();
      if (typeof onTick === 'function') onTick();
      if (!done && st && st.running === false) deadPolls++;else deadPolls = 0;
      if (deadPolls >= 6) {
        renderLog(logEl, (txt ? txt.replace(/\s+$/, '') + '\n' : '') + '==> Операция прервалась: процесс на роутере завершился, не оставив итога. Обновите страницу и проверьте состояние.');
        try {
          window.dispatchEvent(new CustomEvent('zm:changed', {
            detail: {
              job: job
            }
          }));
        } catch (e) {}
        end(false);
        return;
      }
      if (done) {
        try {
          window.dispatchEvent(new CustomEvent('zm:changed', {
            detail: {
              job: job
            }
          }));
        } catch (e) {}
        if (st.rc === '130') toast('Операция остановлена', 'warning');
        if (!txt) renderLog(logEl, st.rc === '0' ? '==> Готово' : '==> Операция завершилась с ошибкой (код ' + (st.rc || '?') + ')');else if (st.rc !== '0' && st.rc !== '130' && !/(^|\n)\s*(==>\s*)?(ОШИБКА|\[FAIL\]|!!|\s+!)/.test(txt)) renderLog(logEl, txt.replace(/\s+$/, '') + '\n==> ОШИБКА: операция не завершилась (код ' + (st.rc || '?') + '), а причину роутер не назвал. Попробуйте ещё раз; если повторится — загляните в системный журнал.');
        end(st.rc === '0');
      }
    }).catch(function () {
      inFlight = false;
      if (finished) return;
      failCount++;
      if (failCount >= 40) {
        renderLog(logEl, '==> ОШИБКА: роутер не отвечает, не удалось получить статус операции.');
        end(false);
      }
    });
  }, 1200);
  _activePolls[job] = timer;
}
function floatBanner(el) {
  el.classList.add('zm-float-banner');
  el._zmWant = true;
  setTimeout(function () {
    if (el._zmWant) dock(el, true);
  }, 0);
  return el;
}
function refreshBanner(message, relogin) {
  return floatBanner(E('div', {
    'class': 'zm-refresh-banner zm-show'
  }, [E('span', {}, message || 'Список меню LuCI мог измениться — выйдите и зайдите заново, чтобы увидеть изменения.'), E('button', {
    'class': 'cbi-button cbi-button-positive',
    'click': function () {
      if (relogin === false) {
        location.reload();
        return;
      }
      fetch(L.url('admin/logout'), {
        credentials: 'same-origin'
      }).catch(function () {}).then(function () {
        location.reload();
      });
    }
  }, relogin === false ? 'Обновить' : 'Выйти из LuCI')]));
}
function toastContainer() {
  var c = document.getElementById('zm-toast-container');
  if (!c) {
    c = document.createElement('div');
    c.id = 'zm-toast-container';
    document.body.appendChild(c);
  }
  return c;
}
function toastFit() {
  var c = document.getElementById('zm-toast-container');
  if (!c) return;
  var vh = window.innerHeight,
    dt = vh;
  if (_dockEl && _dockEl.classList.contains('zm-dock-on')) {
    var r = _dockEl.getBoundingClientRect();
    if (r.height > 0 && r.top > 0) dt = r.top;
  }
  var room;
  if (document.body.classList.contains('zmw-body')) {
    var bot = dt < vh ? vh - dt + 14 + 'px' : '';
    if (c.style.bottom !== bot) c.style.bottom = bot;
    room = dt - (dt < vh ? 14 : 28) - 16;
  } else {
    room = dt - 14 - c.getBoundingClientRect().top;
  }
  room = Math.max(90, Math.floor(room));
  c.style.maxHeight = room + 'px';
  while (c.children.length > 1 && c.scrollHeight > room) c.removeChild(c.firstChild);
}
window.zmToastFit = toastFit;
function toast(message, kind, duration) {
  var container = toastContainer();
  var txt = String(message == null ? '' : message);
  Array.prototype.slice.call(container.children).forEach(function (o) {
    if (o._zmText === txt) container.removeChild(o);
  });
  var el = E('div', {
    'class': 'zm-toast zm-toast-' + (kind || 'info')
  }, [E('span', {
    'class': 'zm-toast-icon'
  }), E('span', {
    'class': 'zm-toast-text'
  }, [String(message == null ? '' : message)])]);
  el._zmText = txt;
  container.appendChild(el);
  toastFit();
  requestAnimationFrame(function () {
    el.classList.add('zm-toast-show');
  });
  var hide = function () {
    el.classList.remove('zm-toast-show');
    setTimeout(function () {
      el.parentNode && el.parentNode.removeChild(el);
    }, 250);
  };
  el.addEventListener('click', hide);
  setTimeout(hide, duration || (kind === 'error' ? 14000 : 9000));
}
function busyToast(message, sub) {
  var container = toastContainer();
  var textEl = E('span', {
      'class': 'zm-toast-main'
    }),
    subEl = E('span', {
      'class': 'zm-toast-sub'
    });
  var el = E('div', {
    'class': 'zm-toast zm-toast-busy',
    'role': 'status'
  }, [E('span', {
    'class': 'zm-toast-spin',
    'aria-hidden': 'true'
  }), E('span', {
    'class': 'zm-toast-text'
  }, [textEl, subEl])]);
  var closed = false;
  function put(m, s2) {
    textEl.textContent = String(m == null ? '' : m);
    subEl.textContent = s2 ? String(s2) : '';
    subEl.style.display = s2 ? '' : 'none';
  }
  put(message, sub);
  container.appendChild(el);
  toastFit();
  requestAnimationFrame(function () {
    el.classList.add('zm-toast-show');
  });
  return {
    set: function (m, s2) {
      if (closed) return;
      put(m, s2);
      if (!el.parentNode) {
        toastContainer().appendChild(el);
        toastFit();
        el.classList.add('zm-toast-show');
      }
    },
    close: function () {
      if (closed) return;
      closed = true;
      el.classList.remove('zm-toast-show');
      setTimeout(function () {
        el.parentNode && el.parentNode.removeChild(el);
      }, 250);
    }
  };
}
function notifyStrategyResult(res, okLabel) {
  if (res.error) {
    toast(res.error, 'error');
    return false;
  }
  toast(okLabel + ' применена', 'info');
  return true;
}
var SVC_BRANDS = [[/youtube/i, '#ff0033', 'YT'], [/discord/i, '#5865f2', 'DC'], [/telegram/i, '#229ed9', 'TG'], [/^meta\b/i, '#0866ff', 'M'], [/whatsapp/i, '#25d366', 'WA'], [/instagram/i, '#e1306c', 'IG'], [/facebook/i, '#1877f2', 'FB'], [/twitter|^x\b/i, '#16181c', 'X'], [/tiktok/i, '#fe2c55', 'TT'], [/google play/i, '#01875f', 'GP'], [/gemini|google ai/i, '#4285f4', 'AI'], [/chatgpt|openai|claude|\bai\b|(^|[^а-яё])ии([^а-яё]|$)/i, '#10a37f', 'AI'], [/githubusercontent|github raw/i, '#57606a', 'GR'], [/github/i, '#24292f', 'GH'], [/google/i, '#4285f4', 'G'], [/roblox/i, '#e2231a', 'RB'], [/supercell|brawl|clash/i, '#f59e0b', 'SC'], [/rezka/i, '#3f8f3f', 'HD'], [/spotify/i, '#1db954', 'SP'], [/twitch/i, '#9146ff', 'TW'], [/netflix/i, '#e50914', 'NF'], [/steam/i, '#1b2838', 'ST'], [/cloudflare/i, '#f38020', 'CF'], [/amazon|aws|cloudfront/i, '#ff9900', 'AW'], [/linkedin/i, '#0a66c2', 'IN'], [/soundcloud/i, '#ff5500', 'SC'], [/reddit/i, '#ff4500', 'RD'], [/nalog/i, '#1f4e8c', 'НЛ'], [/rutor|rutracker|torrent/i, '#6b7280', 'RT'], [/hetzner/i, '#d50c2d', 'HZ'], [/ovh/i, '#123f6d', 'OV'], [/digitalocean/i, '#0080ff', 'DO'], [/hodca|h\.o\.d\.c\.a|хостинг/i, '#0f766e', 'HC']];
var SVC_PALETTE = ['#6366f1', '#0ea5e9', '#14b8a6', '#10b981', '#84cc16', '#f59e0b', '#f97316', '#ef4444', '#ec4899', '#8b5cf6', '#64748b', '#0891b2'];
var SVC_KEY_ICO = {
  geoblock: ['#0ea5e9', 'ГБ'],
  block: ['#ef4444', 'ЗБ'],
  news: ['#64748b', 'НВ'],
  anime: ['#ec4899', 'АН'],
  porn: ['#be123c', '18'],
  hodca: ['#0f766e', 'HC'],
  russia_inside: ['#2563eb', 'ВС'],
  russia_outside: ['#7c3aed', 'РФ'],
  ukraine_inside: ['#0057b7', 'UA'],
  custom: ['#0891b2', 'СВ']
};
function svcIco(name, key) {
  name = String(name || '');
  var kk = SVC_KEY_ICO[String(key || '').replace(/^c_itdoginfo_/, '')];
  if (kk) return {
    color: kk[0],
    ico: kk[1]
  };
  for (var i = 0; i < SVC_BRANDS.length; i++) if (SVC_BRANDS[i][0].test(name) || key && SVC_BRANDS[i][0].test(key)) return {
    color: SVC_BRANDS[i][1],
    ico: SVC_BRANDS[i][2]
  };
  var src = String(key || name),
    h = 0;
  for (var j = 0; j < src.length; j++) h = h * 31 + src.charCodeAt(j) >>> 0;
  var words = name.replace(/^[^A-Za-zА-Яа-яЁё0-9]+/, '').split(/[\s._\-·(),]+/).filter(function (w) {
    return w;
  });
  var ico = words.length > 1 ? words[0].charAt(0) + words[1].charAt(0) : (words[0] || '?').slice(0, 2);
  return {
    color: SVC_PALETTE[h % SVC_PALETTE.length],
    ico: ico.toUpperCase()
  };
}
function svcTx(v) {
  return typeof v === 'string' || typeof v === 'number' ? [String(v)] : v;
}
function svcCard(o) {
  var ic = svcIco(o.name, o.key);
  var on = o.on || o.inc;
  return E('div', {
    'class': 'zm-svc' + (on ? ' zm-svc-on' : '') + (o.inc && !o.on ? ' zm-svc-inc' : '') + (o.cls ? ' ' + o.cls : ''),
    'title': o.title || (o.inc && !o.on ? 'Входит в «Всё сразу» (Russia inside)' : typeof o.name === 'string' ? o.name : ''),
    'click': o.click
  }, [E('div', {
    'class': 'zm-svc-ico',
    'style': 'background:' + (o.color || ic.color)
  }, o.ico || ic.ico), E('div', {
    'class': 'zm-svc-text'
  }, [E('div', {
    'class': 'zm-svc-name'
  }, svcTx(o.name)), o.inc && !o.on ? E('div', {
    'class': 'zm-svc-sub'
  }, 'входит в «Всё сразу»') : o.sub ? E('div', {
    'class': 'zm-svc-sub'
  }, svcTx(o.sub)) : E([])]), o.extra || E([]), o.right || E('div', {
    'class': 'zm-switch' + (on ? ' zm-switch-on' : '') + (o.inc && !o.on ? ' zm-switch-inc' : '')
  }, [E('span')])]);
}
function swRow(on, label, hint, click, disabled) {
  return E('div', {
    'class': 'zm-swrow' + (disabled ? ' zm-swrow-off' : ''),
    'click': function (ev) {
      if (!disabled && click) click(ev);
    }
  }, [E('div', {
    'class': 'zm-switch' + (on ? ' zm-switch-on' : '')
  }, [E('span')]), E('div', {
    'class': 'zm-swrow-text'
  }, [E('div', {
    'class': 'zm-swrow-label'
  }, label), hint ? E('div', {
    'class': 'zm-hint'
  }, hint) : E([])])]);
}
var _dlgOpen = [];
function _dlgRoute() {
  return String(location.hash || '').replace(/^#\/?/, '').split(/[/?]/)[0];
}
function dlgTrack(close, val) {
  _dlgOpen.push({
    close: close,
    val: val,
    route: _dlgRoute()
  });
}
function dlgDone(close) {
  _dlgOpen = _dlgOpen.filter(function (it) {
    return it.close !== close;
  });
}
window.addEventListener('hashchange', function () {
  if (!document.body || !document.body.classList.contains('zmw-body')) return;
  var r = _dlgRoute();
  _dlgOpen.slice().forEach(function (it) {
    if (it.route !== r) {
      try {
        it.close(it.val);
      } catch (e) {}
    }
  });
});
function dialog(o) {
  o = o || {};
  return new Promise(function (done) {
    var vals = {},
      okBtn,
      wrap,
      body = E('div', {
        'class': 'zm-dlg-body'
      });
    (o.blocks || []).forEach(function (b) {
      if (b && b.id) vals[b.id] = b.value;
    });
    function close(res) {
      dlgDone(close);
      document.removeEventListener('keydown', onKey);
      if (wrap && wrap.parentNode) wrap.parentNode.removeChild(wrap);
      done(res);
    }
    function onKey(ev) {
      if (ev.key === 'Escape') close(null);
    }
    function allowed() {
      return !o.canOk || !!o.canOk(vals);
    }
    function draw() {
      body.innerHTML = '';
      (o.blocks || []).forEach(function (b) {
        if (!b || b.show && !b.show(vals)) return;
        if (b.type === 'note') {
          body.appendChild(E('div', {
            'class': 'zm-dlg-note' + (b.kind ? ' zm-dlg-note-' + b.kind : '')
          }, b.text));
        } else if (b.type === 'list') {
          body.appendChild(E('div', {
            'class': 'zm-dlg-title'
          }, b.title));
          body.appendChild(E('ul', {
            'class': 'zm-dlg-list'
          }, ((typeof b.items === 'function' ? b.items(vals) : b.items) || []).map(function (t) {
            return E('li', {}, t);
          })));
        } else if (b.type === 'choice') {
          body.appendChild(E('div', {
            'class': 'zm-dlg-title'
          }, b.title));
          if (b.hint) body.appendChild(E('div', {
            'class': 'zm-hint',
            'style': 'margin:0 0 4px'
          }, b.hint));
          (b.options || []).forEach(function (x) {
            var on = vals[b.id] === x.id;
            body.appendChild(E('div', {
              'class': 'zm-dlg-opt' + (on ? ' zm-active' : '') + (x.disabled ? ' zm-dlg-opt-off' : ''),
              'click': function () {
                if (x.disabled || on) return;
                vals[b.id] = x.id;
                draw();
              }
            }, [E('div', {
              'class': 'zm-dlg-radio'
            }, [E('span')]), E('div', {}, [E('div', {
              'class': 'zm-swrow-label'
            }, x.label), x.hint ? E('div', {
              'class': 'zm-hint' + (x.warn ? ' zm-dlg-warn' : '')
            }, x.hint) : E([])])]));
          });
        } else if (b.type === 'switch') {
          body.appendChild(swRow(!!vals[b.id], b.label, b.hint, function () {
            vals[b.id] = !vals[b.id];
            draw();
          }, b.disabled));
        } else if (b.type === 'input') {
          if (b.title) body.appendChild(E('div', {
            'class': 'zm-dlg-title'
          }, b.title));
          var inp = E('input', {
            'type': 'text',
            'class': 'cbi-input-text zm-dlg-input',
            'spellcheck': 'false',
            'autocapitalize': 'off',
            'autocomplete': 'off',
            'placeholder': b.placeholder || '',
            'aria-label': b.title || b.placeholder || ''
          });
          inp.value = vals[b.id] == null ? '' : String(vals[b.id]);
          inp.addEventListener('input', function () {
            vals[b.id] = inp.value;
            if (okBtn) {
              if (allowed()) okBtn.removeAttribute('disabled');else okBtn.setAttribute('disabled', '');
            }
          });
          inp.addEventListener('keydown', function (ev) {
            if (ev.key === 'Enter') {
              ev.preventDefault();
              if (allowed()) close(vals);
            }
          });
          body.appendChild(inp);
          if (b.hint) body.appendChild(E('div', {
            'class': 'zm-hint',
            'style': 'margin:6px 0 0'
          }, b.hint));
          if (!o._focus) o._focus = inp;
        }
      });
      if (okBtn) {
        if (allowed()) okBtn.removeAttribute('disabled');else okBtn.setAttribute('disabled', '');
      }
    }
    okBtn = E('button', {
      'class': 'cbi-button ' + (o.danger ? 'cbi-button-remove' : 'cbi-button-positive'),
      'click': function () {
        if (allowed()) close(vals);
      }
    }, o.okText || 'Продолжить');
    wrap = E('div', {
      'class': 'zm-dlg-wrap',
      'click': function (ev) {
        if (ev.target === wrap) close(null);
      }
    }, [E('div', {
      'class': 'zm-card zm-dlg zmw-modal'
    }, [E('h3', {}, o.title || ''), o.intro ? E('p', {
      'class': 'zm-dlg-intro'
    }, o.intro) : E([]), body, o.altText ? E('div', {
      'class': 'zm-actions zm-dlg-actions zm-dlg-actions-3'
    }, [okBtn, E('button', {
      'class': 'cbi-button',
      'click': function () {
        close('alt');
      }
    }, o.altText), E('button', {
      'class': 'cbi-button',
      'click': function () {
        close(null);
      }
    }, o.cancelText || 'Отмена')]) : E('div', {
      'class': 'zm-actions zm-dlg-actions'
    }, [o.cancelText === '' ? E([]) : E('button', {
      'class': 'cbi-button',
      'click': function () {
        close(null);
      }
    }, o.cancelText || 'Отмена'), okBtn])])]);
    draw();
    document.addEventListener('keydown', onKey);
    document.body.appendChild(wrap);
    dlgTrack(close, null);
    setTimeout(function () {
      try {
        (o._focus || okBtn).focus();
        if (o._focus) o._focus.select();
      } catch (e) {}
    }, 0);
  });
}
var ASK_DANGER = /^(удалить|очистить|убрать|остановить|сбросить|отменить|заменить|свернуть)$/i;
function askVerb(title) {
  var words = String(title).replace(/[«»"()?!.,:;—–]/g, ' ').split(/\s+/),
    i,
    w,
    found = [];
  for (i = 0; i < words.length; i++) {
    w = words[i].toLowerCase();
    if (w.length > 3 && w !== 'есть' && w !== 'быть' && /(ть|ти|ться)$/.test(w)) found.push(w);
  }
  if (found.length > 1 && found[0] === 'отменить') found.shift();
  return found.length ? found[0].charAt(0).toUpperCase() + found[0].slice(1) : '';
}
function ask(text, o) {
  o = o || {};
  var t = String(text || ''),
    cut = t.indexOf('\n\n');
  var title = (cut < 0 ? t : t.slice(0, cut)).trim(),
    rest = cut < 0 ? '' : t.slice(cut + 2).trim();
  if (!rest && title.length > 70) {
    var dot = title.search(/[.?!]\s/);
    if (dot > 0 && dot < title.length - 2) {
      rest = title.slice(dot + 1).trim();
      title = title.slice(0, dot + 1).trim();
    }
  }
  var verb = o.okText || (/\?\s*$/.test(title) ? askVerb(title) : '') || (/\?\s*$/.test(title) ? 'Да' : 'Продолжить');
  var danger = o.danger != null ? !!o.danger : ASK_DANGER.test(verb) || /несохранённ|будут удалены|пропадут/i.test(t);
  return dialog({
    title: title,
    intro: rest,
    okText: verb,
    cancelText: o.cancelText || 'Отмена',
    danger: danger
  }).then(function (v) {
    return !!v;
  });
}
function saveBar(o) {
  o = o || {};
  var el = E('div', {
    'class': 'zm-savebar',
    'style': 'display:none'
  });
  var state = {
      dirty: false,
      busy: false
    },
    ap = null,
    drawn = null,
    busyT = null;
  var applyWord = /примен|включ/i.test(o.saveLabel || 'Сохранить и применить');
  function running() {
    return state.busy || !!ap;
  }
  function visible() {
    return state.dirty && !running();
  }
  function busySub() {
    var what = (ap && ap.text || state.text || '').replace(/^Есть несохранённые изменения:?\s*/, '').replace(/^Изменения:\s*/, '');
    if (/^\d+$/.test(what)) what = 'изменений: ' + what;
    return [what, o.busyHint || ''].filter(Boolean).join(' · ');
  }
  function paintBusy() {
    if (!running() || !document.body.contains(el._zmPh || el)) {
      if (busyT) {
        busyT.close();
        busyT = null;
      }
      return;
    }
    var ctx = el._zmCtx ? el._zmCtx + ': ' : '';
    var main = ctx + (o.busyText || (applyWord ? 'Применяем изменения…' : 'Сохраняем изменения…'));
    if (busyT) busyT.set(main, busySub());else busyT = busyToast(main, busySub());
  }
  function render() {
    var vis = visible();
    var ctx = el._zmCtx ? el._zmCtx + ': ' : '';
    paintBusy();
    var key = [vis, ctx, state.text, state.label].join('\u0001');
    if (key === drawn) return;
    drawn = key;
    el.innerHTML = '';
    el.style.display = vis ? '' : 'none';
    el.classList.remove('zm-savebar-run', 'zm-savebar-done');
    if (!vis) return;
    el.appendChild(E('span', {
      'class': 'zm-savebar-dot'
    }));
    el.appendChild(E('span', {
      'class': 'zm-savebar-text'
    }, [ctx + (state.text || o.text || 'Есть несохранённые изменения')]));
    el.appendChild(E('div', {
      'class': 'zm-savebar-btns'
    }, [E('button', {
      'class': 'cbi-button',
      'click': function () {
        if (o.onCancel) o.onCancel();
      }
    }, o.cancelLabel || 'Отменить'), E('button', {
      'class': 'cbi-button cbi-button-positive',
      'click': save
    }, state.label || o.saveLabel || 'Сохранить и применить')]));
  }
  function place() {
    var show = visible();
    el._zmWant = show;
    if (show) setTimeout(function () {
      if (visible()) dock(el, true);
    }, 0);else dock(el, false);
  }
  function finish() {
    ap = null;
  }
  function giveUp(a) {
    if (ap !== a) return;
    ap = null;
    render();
    place();
  }
  function save() {
    if (ap || state.busy) return;
    var a = ap = {
      t0: Date.now(),
      sawBusy: false,
      text: state.text,
      wait: false
    };
    render();
    place();
    var r;
    try {
      r = o.onSave ? o.onSave() : undefined;
    } catch (e) {
      giveUp(a);
      throw e;
    }
    if (r === false) {
      giveUp(a);
      return;
    }
    if (r && typeof r.then === 'function') {
      a.wait = true;
      r.then(function (v) {
        a.wait = false;
        if (v === false) giveUp(a);else if (ap === a && !state.dirty && !state.busy) {
          finish();
          render();
          place();
        }
      }, function () {
        a.wait = false;
        giveUp(a);
      });
    }
    setTimeout(function () {
      if (ap === a && !a.wait && !a.sawBusy && !state.busy && state.dirty) giveUp(a);
    }, 2500);
  }
  el.set = function (dirty, busy, text, label) {
    state.dirty = !!dirty;
    state.busy = !!busy;
    state.text = text || '';
    state.label = label || '';
    if (ap) {
      if (state.busy) ap.sawBusy = true;else if (!state.dirty) finish();else if (ap.sawBusy && !ap.wait) ap = null;
    }
    render();
    place();
    return el;
  };
  el.isDirty = function () {
    return state.dirty;
  };
  el._zmRender = render;
  render();
  return el;
}
function editorBar(ta, o) {
  var orig = ta.value,
    busy = false;
  var bar = saveBar({
    saveLabel: o.saveLabel,
    text: o.text,
    onCancel: function () {
      if (o.onCancel) {
        o.onCancel();
        return;
      }
      ta.value = orig;
      sync();
    },
    onSave: function () {
      busy = true;
      sync();
      Promise.resolve(o.onSave(ta.value)).then(function (ok) {
        busy = false;
        if (ok !== false) orig = ta.value;
        sync();
      }, function () {
        busy = false;
        sync();
      });
    }
  });
  function sync() {
    bar.set(ta.value !== orig, busy);
  }
  ta.addEventListener('input', sync);
  bar.reset = function (v) {
    if (v != null) ta.value = v;
    orig = ta.value;
    busy = false;
    sync();
  };
  bar.dirty = function () {
    return ta.value !== orig;
  };
  return bar;
}
function blockCard(card, title, hint, text) {
  card.innerHTML = '';
  card.appendChild(E('h3', {}, title));
  if (hint) card.appendChild(E('p', {
    'class': 'zm-hint'
  }, hint));
  card.appendChild(E('div', {
    'class': 'zm-refresh-banner zm-show zm-block-banner'
  }, [E('span', {}, text)]));
  return card;
}
function svcGrid(list) {
  return E('div', {
    'class': 'zm-svc-grid'
  }, list);
}
function svcGroup(o) {
  var body = E('div', {
    'style': o.open ? '' : 'display:none'
  }, [o.body]);
  var head = svcCard({
    name: o.name,
    sub: o.sub,
    key: o.key,
    color: o.color,
    ico: o.ico,
    on: false,
    cls: 'zm-svc-group' + (o.open ? ' zm-svc-open' : ''),
    right: E('span', {
      'style': 'display:inline-flex; align-items:center; gap:10px'
    }, [o.badge || E([]), E('span', {
      'class': 'zm-svc-chev'
    }, '›')]),
    click: function () {
      var open = body.style.display === 'none';
      body.style.display = open ? '' : 'none';
      head.classList.toggle('zm-svc-open', open);
      if (o.toggle) o.toggle(open);
    }
  });
  return E('div', {
    'class': 'zm-svc-groupwrap'
  }, [head, body]);
}
function rebootWait(note) {
  var t0 = Date.now();
  var count = E('span', {
    'class': 'zm-reboot-count',
    'role': 'timer',
    'aria-live': 'off'
  }, '0:00');
  var state = E('p', {
    'class': 'zm-reboot-text'
  }, 'Страница переподключится сама.');
  var ov = E('div', {
    'class': 'zm-reboot-ov',
    'role': 'dialog',
    'aria-modal': 'true',
    'aria-label': 'Роутер перезагружается'
  }, [E('div', {
    'class': 'zm-reboot-box'
  }, [E('span', {
    'class': 'zm-reboot-spin',
    'aria-hidden': 'true'
  }), E('h3', {
    'class': 'zm-reboot-title'
  }, 'Роутер перезагружается'), state, E('div', {
    'class': 'zm-reboot-meta'
  }, [E('span', {}, 'прошло'), count])])]);
  document.body.appendChild(ov);
  function tick() {
    var sec = Math.round((Date.now() - t0) / 1000);
    count.textContent = Math.floor(sec / 60) + ':' + ('0' + sec % 60).slice(-2);
    if (sec >= 25) state.textContent = sec < 150 ? 'Ждём, когда роутер снова ответит…' : 'Роутер отвечает дольше обычного — подождите ещё немного.';
    if (sec < 25) {
      setTimeout(tick, 1000);
      return;
    }
    var ctl = window.AbortController ? new AbortController() : null;
    var tm = ctl ? setTimeout(function () {
      ctl.abort();
    }, 4000) : 0;
    fetch(location.pathname + location.search, {
      cache: 'no-store',
      credentials: 'same-origin',
      signal: ctl ? ctl.signal : undefined
    }).then(function (r) {
      clearTimeout(tm);
      if (r.ok) location.reload();else setTimeout(tick, 3000);
    }, function () {
      clearTimeout(tm);
      setTimeout(tick, 3000);
    });
  }
  tick();
}
function rebootRouter() {
  return ask('Перезагрузить роутер?\n\nИнтернет пропадёт на 1–2 минуты, потом всё поднимется само.').then(function (ok) {
    if (!ok) return Promise.resolve(false);
    return callSystemReboot().then(function (r) {
      if (r && r.error) {
        toast(r.error, 'error');
        return false;
      }
      rebootWait(E('span', {
        'class': 'zm-hint',
        'style': 'margin:0'
      }));
      return true;
    }, function () {
      toast('Роутер не ответил', 'error');
      return false;
    });
  });
}
function rebootBanner(text) {
  var btn = E('button', {
    'class': 'cbi-button cbi-button-positive',
    'click': function () {
      btn.disabled = true;
      rebootRouter().then(function (ok) {
        if (!ok) btn.disabled = false;
      });
    }
  }, 'Перезагрузить');
  var el = E('div', {
    'class': 'zm-refresh-banner zm-show zm-reboot-banner'
  }, [E('span', {}, String(text)), btn]);
  el.appendChild(E('button', {
    'type': 'button',
    'class': 'zm-banner-x',
    'title': 'Закрыть',
    'aria-label': 'Закрыть',
    'click': function () {
      el._zmWant = false;
      if (el._zmPh && el._zmPh.parentNode) el._zmPh.parentNode.removeChild(el._zmPh);
      if (el.parentNode) el.parentNode.removeChild(el);
      dockSync();
      callRebootHintClear().catch(function () {});
    }
  }, '×'));
  return floatBanner(el);
}
function alertBanners(h, done) {
  var box = E('div', {
    'class': 'zm-alerts'
  });
  function one(text, btn, key, call, okText) {
    box.appendChild(E('div', {
      'class': 'zm-refresh-banner zm-show'
    }, [E('span', {}, text), E('button', {
      'class': 'cbi-button cbi-button-positive',
      'click': function (ev) {
        var b = ev.currentTarget;
        b.disabled = true;
        toast('Применяем…', 'warning');
        call('on').then(function (r) {
          if (r && r.error) {
            toast(r.error, 'error');
            b.disabled = false;
            if (done) done();
            return;
          }
          if (r && r[key] === false) {
            toast('Не получилось — попробуйте ещё раз', 'error');
            b.disabled = false;
            return;
          }
          toast(okText, 'info');
          if (done) done();
        }).catch(function () {
          b.disabled = false;
          toast('Роутер не ответил', 'error');
        });
      }
    }, btn)]));
  }
  if (h && h.reboot_hint) box.appendChild(rebootBanner(h.reboot_hint));
  if (h && h.flow_warn) one('Включён Flow Offloading, а поправка для Zapret не применена — Zapret может работать с перебоями.', 'Применить поправку', 'flow_offloading_fix', callSystemToggleFlowOffloadingFix, 'Поправка для Zapret применена');
  if (h && h.ipv6_warn) one('Роутер работает по IPv6, а в Zapret IPv6 выключен — часть сайтов может открываться без обхода.', 'Включить IPv6', 'ipv6_enabled', callSystemToggleIpv6, 'IPv6 в Zapret включён');
  var ghHid = 0;
  try {
    ghHid = parseInt(localStorage.getItem('zm.gh_warn_hide'), 10) || 0;
  } catch (e) {}
  if (h && h.gh_warn && Date.now() - ghHid > 86400000) {
    var ghBox = E('div', {
      'class': 'zm-refresh-banner zm-show'
    }, [E('span', {}, 'GitHub сейчас не отвечает — списки, стратегии и обновления не скачиваются. Можно повторять такие загрузки через зеркала.'), E('button', {
      'class': 'cbi-button cbi-button-positive',
      'click': function (ev) {
        var b = ev.currentTarget;
        b.disabled = true;
        toast('Включаем зеркало…', 'warning');
        callGhProxy('set', 'auto').then(function (r) {
          if (r && r.error) {
            toast(r.error, 'error');
            b.disabled = false;
            return;
          }
          toast('Включено: если GitHub не ответит, загрузка повторится через зеркала', 'info');
          if (ghBox.parentNode) ghBox.parentNode.removeChild(ghBox);
          if (done) done();
        }).catch(function () {
          b.disabled = false;
          toast('Роутер не ответил', 'error');
        });
      }
    }, 'Включить зеркала'), E('button', {
      'class': 'cbi-button',
      'click': function () {
        try {
          localStorage.setItem('zm.gh_warn_hide', String(Date.now()));
        } catch (e) {}
        if (ghBox.parentNode) ghBox.parentNode.removeChild(ghBox);
      }
    }, 'Не сейчас')]);
    box.appendChild(ghBox);
  }
  return box;
}
var _uiFlags = null;
function uiFlags() {
  if (!_uiFlags) _uiFlags = callUiFlagsGet().then(function (r) {
    return r && r.flags || {};
  }).catch(function () {
    return {};
  });
  return _uiFlags;
}
function uiFlagLocal(key, set) {
  try {
    if (set) localStorage.setItem('zm.flag.' + key, '1');
    return localStorage.getItem('zm.flag.' + key) === '1';
  } catch (e) {
    return !!set;
  }
}
function uiFlagSet(key) {
  uiFlagLocal(key, true);
  uiFlags().then(function (f) {
    f[key] = 1;
  });
  return callUiFlagSet(key).catch(function () {});
}
function copyText(text, okMsg) {
  var done = function () {
    toast(okMsg || 'Скопировано', 'info');
  };
  var old = function () {
    var ta = E('textarea', {
      'readonly': '',
      'style': 'position:fixed;top:-1000px;left:-1000px;opacity:0'
    });
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    var ok = false;
    try {
      ok = document.execCommand('copy');
    } catch (e) {}
    document.body.removeChild(ta);
    if (ok) done();else toast('Не удалось скопировать — выделите команду и нажмите Ctrl+C', 'warning');
  };
  if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(text).then(done, old);else old();
}
function warnDialog(o) {
  o = o || {};
  return new Promise(function (resolve) {
    var wrap,
      okBtn,
      prevFocus = document.activeElement,
      id = 'zm-wd-' + Date.now();
    var cb = E('input', {
      'type': 'checkbox',
      'id': id
    });
    function close(go) {
      dlgDone(close);
      document.removeEventListener('keydown', onKey, true);
      if (wrap && wrap.parentNode) wrap.parentNode.removeChild(wrap);
      document.documentElement.classList.remove('zm-wn-lock');
      try {
        if (prevFocus && prevFocus.focus) prevFocus.focus({
          preventScroll: true
        });
      } catch (e) {}
      resolve(!!go);
    }
    function onKey(ev) {
      if (ev.key === 'Escape' && !o.info) {
        ev.preventDefault();
        close(false);
      }
    }
    function sync() {
      okBtn.disabled = !cb.checked;
      okBtn.classList.toggle('zm-wn-btn-off', !cb.checked);
    }
    if (o.noCheck) cb.checked = true;
    okBtn = E('button', {
      'class': 'cbi-button cbi-button-positive',
      'click': function () {
        if (cb.checked) close(true);
      }
    }, o.okText || (o.info ? 'Понятно' : 'Продолжить'));
    cb.addEventListener('change', sync);
    var ico = o.kind === 'info' ? 'i' : '!';
    function li(it) {
      return E('li', it[3] ? {
        'class': 'zm-wn-' + it[3]
      } : {}, [E('i', {
        'aria-hidden': 'true'
      }, it[2] || ico), E('div', {}, [E('b', {}, it[0]), it[1] ? E('span', {}, ' — ' + it[1]) : ''])]);
    }
    wrap = E('div', {
      'class': 'zm-dlg-wrap zm-wn-wrap',
      'role': 'dialog',
      'aria-modal': 'true',
      'aria-labelledby': id + '-t',
      'click': function (ev) {
        if (ev.target === wrap && !o.info) close(false);
      }
    }, [E('div', {
      'class': 'zm-card zm-dlg zmw-modal zm-wn' + (o.kind === 'info' ? ' zm-wn-info' : ''),
      'tabindex': '-1'
    }, [E('div', {
      'class': 'zm-wn-body'
    }, [E('div', {
      'class': 'zm-wn-head'
    }, [E('div', {
      'class': 'zm-wn-ico',
      'aria-hidden': 'true'
    }, ico), E('h3', {
      'id': id + '-t'
    }, o.title || '')]), o.lead ? E('p', {
      'class': 'zm-wn-lead'
    }, o.lead) : '', (o.items || []).length ? E('ul', {
      'class': 'zm-wn-list'
    }, o.items.map(li)) : '', E('div', {}, (o.groups || []).filter(function (g) {
      return g && g.items && g.items.length;
    }).map(function (g) {
      return E('div', {
        'class': 'zm-wn-group'
      }, [E('div', {
        'class': 'zm-wn-gt'
      }, g.title), E('ul', {
        'class': 'zm-wn-list'
      }, g.items.map(li))]);
    })), o.tip ? E('div', {
      'class': 'zm-wn-tip'
    }, [o.tip.title ? E('b', {}, o.tip.title + ' ') : '', o.tip.text || '']) : '', o.note ? E('div', {
      'class': 'zm-dlg-note zm-dlg-note-' + (o.noteKind || 'warn')
    }, o.note) : '', o.noCheck ? '' : E('label', {
      'class': 'zm-wn-check',
      'for': id
    }, [cb, E('span', {}, o.check || 'Понимаю')])]), E('div', {
      'class': 'zm-actions zm-dlg-actions zm-wn-foot'
    }, o.info || o.noCheck ? [okBtn] : [E('button', {
      'class': 'cbi-button',
      'click': function () {
        close(false);
      }
    }, 'Отмена'), okBtn])])]);
    sync();
    document.documentElement.classList.add('zm-wn-lock');
    document.body.appendChild(wrap);
    dlgTrack(close, false);
    document.addEventListener('keydown', onKey, true);
    setTimeout(function () {
      try {
        wrap.querySelector('.zm-wn').focus({
          preventScroll: true
        });
      } catch (e) {}
    }, 0);
  });
}
function warnSeen(key) {
  if (uiFlagLocal(key)) return Promise.resolve(true);
  return uiFlags().then(function (f) {
    if (f[key]) uiFlagLocal(key, true);
    return !!f[key];
  });
}
function warnOnce(key, open) {
  return warnSeen(key).then(function (seen) {
    if (seen) return true;
    return Promise.resolve(open()).then(function (ok) {
      if (ok) uiFlagSet(key);
      return !!ok;
    });
  });
}
var TS_CMD = 'netsh int tcp set global timestamps=enabled';
function tsWarn(o) {
  o = o || {};
  return new Promise(function (resolve) {
    var wrap,
      okBtn,
      prevFocus = document.activeElement;
    var cb = E('input', {
      'type': 'checkbox',
      'id': 'zm-ts-agree'
    });
    function close(go) {
      dlgDone(close);
      document.removeEventListener('keydown', onKey, true);
      if (wrap && wrap.parentNode) wrap.parentNode.removeChild(wrap);
      document.documentElement.classList.remove('zm-wn-lock');
      try {
        if (prevFocus && prevFocus.focus) prevFocus.focus({
          preventScroll: true
        });
      } catch (e) {}
      resolve(!!go);
    }
    function onKey(ev) {
      if (ev.key === 'Escape' && !o.info) {
        ev.preventDefault();
        close(false);
      }
    }
    function sync() {
      okBtn.disabled = !cb.checked;
      okBtn.classList.toggle('zm-wn-btn-off', !cb.checked);
    }
    function kbd(t) {
      return E('kbd', {
        'class': 'zm-kbd'
      }, t);
    }
    var cmd = E('div', {
      'class': 'zm-ts-cmd'
    }, [E('code', {}, TS_CMD), E('button', {
      'type': 'button',
      'class': 'cbi-button',
      'click': function () {
        copyText(TS_CMD, 'Команда скопирована');
      }
    }, 'Скопировать')]);
    var parts = (o.parts || []).filter(Boolean);
    okBtn = E('button', {
      'class': 'cbi-button cbi-button-positive',
      'click': function () {
        if (cb.checked) close(true);
      }
    }, o.okText || (o.info ? 'Понятно' : 'Применить стратегию'));
    cb.addEventListener('change', sync);
    wrap = E('div', {
      'class': 'zm-dlg-wrap zm-wn-wrap',
      'role': 'dialog',
      'aria-modal': 'true',
      'aria-labelledby': 'zm-ts-title',
      'click': function (ev) {
        if (ev.target === wrap && !o.info) close(false);
      }
    }, [E('div', {
      'class': 'zm-card zm-dlg zmw-modal zm-wn zm-ts',
      'tabindex': '-1'
    }, [E('div', {
      'class': 'zm-wn-body'
    }, [E('div', {
      'class': 'zm-wn-head'
    }, [E('div', {
      'class': 'zm-wn-ico',
      'aria-hidden': 'true'
    }, '!'), E('h3', {
      'id': 'zm-ts-title'
    }, o.title || (o.info ? 'Автоподбор поставил стратегию с меткой ts' : 'Перед применением: настройте Windows'))]), o.lead ? E('p', {
      'class': 'zm-wn-lead',
      'style': 'margin-bottom:8px'
    }, o.lead) : '', E('p', {
      'class': 'zm-wn-lead',
      'style': 'margin-bottom:8px'
    }, ['Стратегия с меткой ', E('b', {}, 'ts')].concat(parts.length ? [' (', E('span', {
      'class': 'zm-ts-where'
    }, parts.map(function (t) {
      return E('span', {}, t);
    })), ')'] : [], [' на компьютерах с Windows работает, только если включены метки времени TCP. Телефонам, Mac и ТВ ничего делать не нужно.'])), E('ol', {
      'class': 'zm-ts-steps'
    }, [E('li', {}, [E('div', {}, [kbd('Win'), ' + ', kbd('X'), ' → ', E('b', {}, '«Терминал (администратор)»'), ', вставьте команду и нажмите ', kbd('Enter'), ':', cmd])]), E('li', {}, [E('div', {}, ['Ответ ', E('b', {}, '«ОК.»'), ' — готово, перезагрузка не нужна. Один раз на каждом компьютере.'])])]), o.note ? E('div', {
      'class': 'zm-dlg-note zm-dlg-note-warn'
    }, o.note) : '', E('label', {
      'class': 'zm-wn-check',
      'for': 'zm-ts-agree'
    }, [cb, E('span', {}, 'Понимаю: на компьютерах с Windows нужно выполнить эту команду')])]), E('div', {
      'class': 'zm-actions zm-dlg-actions zm-wn-foot'
    }, o.info ? [okBtn] : [E('button', {
      'class': 'cbi-button',
      'click': function () {
        close(false);
      }
    }, 'Отмена'), okBtn])])]);
    sync();
    document.documentElement.classList.add('zm-wn-lock');
    document.body.appendChild(wrap);
    dlgTrack(close, false);
    document.addEventListener('keydown', onKey, true);
    setTimeout(function () {
      try {
        wrap.querySelector('.zm-wn').focus({
          preventScroll: true
        });
      } catch (e) {}
    }, 0);
  });
}
return baseclass.extend({
  injectCss: injectCss,
  badge: badge,
  pollJob: pollJob,
  alertBanners: alertBanners,
  svcCard: svcCard,
  svcGrid: svcGrid,
  svcGroup: svcGroup,
  renderLog: renderLog,
  refreshBanner: refreshBanner,
  floatBanner: floatBanner,
  toast: toast,
  notifyStrategyResult: notifyStrategyResult,
  status: callStatus,
  systemInfo: callSystemInfo,
  zapretAction: callZapretAction,
  zapret2Action: callZapret2Action,
  strategyListV: callStrategyListV,
  strategySetV: callStrategySetV,
  strategyListFlowseal: callStrategyListFlowseal,
  strategySetFlowseal: callStrategySetFlowseal,
  strategyListYoutube: callStrategyListYoutube,
  strategySetYoutube: callStrategySetYoutube,
  youtubeQuicSet: callYoutubeQuicSet,
  discordStatus: callDiscordStatus,
  discordSetDv: callDiscordSetDv,
  discordSetFake: callDiscordSetFake,
  gameStatus: callGameStatus,
  gameSet: callGameSet,
  gameSetFake: callGameSetFake,
  gameToggleXtreme: callGameToggleXtreme,
  systemStatus: callSystemStatus,
  exclusionsStatus: callExclusionsStatus,
  exclusionsToggle: callExclusionsToggle,
  exclusionsClear: callExclusionsClear,
  nfqwsOptGet: callNfqwsOptGet,
  zapretListsStatus: callZapretListsStatus,
  zapretListGet: callZapretListGet,
  zapretListSet: bigArg2(callZapretListSet),
  zapretListRestore: callZapretListRestore,
  nfqwsOptSet: bigText(callNfqwsOptSet),
  hostsStatus: callHostsStatus,
  hostsToggle: callHostsToggle,
  hostsReplaceGeohide: callHostsReplaceGeohide,
  hostsReset: callHostsReset,
  hostsFileGet: callHostsFileGet,
  hostsFileSet: bigText(callHostsFileSet),
  testStatus: callTestStatus,
  testAction: bigArg2(callTestAction),
  zapretOptSet: callZapretOptSet,
  testResults: callTestResults,
  zmUpdateStatus: callZmUpdateStatus,
  changelogShow: changelogShow,
  zmUpdateAction: callZmUpdateAction,
  zmUpdateNotify: zmUpdateNotify,
  zmUpdateFromVersions: zmUpdateFromVersions,
  health: callHealth,
  termStatus: callTermStatus,
  termAction: bigArg2(callTermAction),
  versions: callVersions,
  boardInfo: callBoardInfo,
  swRow: swRow,
  dialog: dialog,
  ask: ask,
  saveBar: saveBar,
  tsWarn: tsWarn,
  busyToast: busyToast,
  warnDialog: warnDialog,
  warnOnce: warnOnce,
  warnSeen: warnSeen,
  uiFlagSet: uiFlagSet,
  editorBar: editorBar,
  blockCard: blockCard,
  parseSize: parseSize,
  fmtSize: fmtSize,
  stateBadge: stateBadge
});
ZM_INSTALLER_EOF
chmod 0644 '/www/luci-static/resources/zapret-manager/common.js'

mkdir -p /www/luci-static/resources/view/zapret-manager
chmod 0755 /www/luci-static/resources/view/zapret-manager
cat > '/www/luci-static/resources/view/zapret-manager/dashboard.js' << 'ZM_INSTALLER_EOF'
'use strict';
'require view';
'require ui';
'require zapret-manager.common as zm';
var E = (function(raw) { return function() { var a = Array.prototype.slice.call(arguments), i = a.length - 1; if (i >= 1 && (typeof a[i] === 'string' || typeof a[i] === 'number')) a[i] = [ String(a[i]) ]; return raw.apply(null, a); }; })(window.E);

return view.extend({
	load: function() {
		zm.injectCss();
		return Promise.all([
			zm.status(),
			zm.hostsStatus().catch(function() { return { items: [] }; }),
			zm.systemStatus().catch(function() { return {}; }),
			zm.systemInfo().catch(function() { return {}; }),
			zm.zmUpdateStatus().catch(function() { return {}; }),
			zm.health().catch(function() { return {}; }),
			zm.boardInfo().catch(function() { return {}; })
		]);
	},

	render: function(all) {
		var data = all[0], hostsData = all[1], sysData = all[2];
		var sysInfo = all[3] || {};
		var zmUpdate = all[4] || {};
		var healthData = all[5] || {};
		var boardInfo = all[6] || {};
		var wrap = E('div', { 'class': 'zm-wrap' });
		var overviewEl = E('div', {});
		var cards = E('div', { 'class': 'zm-cards' });

		function row(label, node) {
			return E('div', { 'class': 'zm-row' }, [ E('span', { 'class': 'zm-label' }, label), node ]);
		}

		function st(h, key, fallback) {
			return (h && typeof h[key] === 'number') ? h[key] : fallback;
		}

		function sysStrip(sys) {
			var p2 = function(x) { return (x < 10 ? '0' : '') + x; };
			function chip(tone, text, title) {
				return E('span', { 'class': 'zm-badge ' + tone, 'title': title }, [ E('span', { 'class': 'zm-dot' }), text ]);
			}
			var fm = { hw: 'аппаратный', sw: 'программный' }[sys.flow_mode] || '', fon = !!fm;
			var zf = sys.flow_offloading_fix === true;
			var c = [
				chip(sys.quic_blocked ? 'zm-ok' : 'zm-off', sys.quic_blocked ? 'QUIC блокируется' : 'QUIC не блокируется', 'Блокировка QUIC (UDP 80 и 443): браузеры переходят на обычный HTTPS, его Zapret обрабатывает надёжнее'),
				chip(sys.ipv6_enabled ? 'zm-ok' : 'zm-off', sys.ipv6_enabled ? 'IPv6 в Zapret' : 'IPv6 в Zapret выключен', 'Обрабатывает ли Zapret трафик IPv6'),
				chip(fon ? 'zm-sx-info' : 'zm-off', 'Flow Offloading ' + (fm || 'выключен'), 'Ускорение маршрутизации/NAT (Сеть → Межсетевой экран)')
			];
			var zIn = sys.zapret_installed !== false, idle = ' — пока Flow Offloading выключен, она ни на что не влияет';
			if ((fon && zIn) || zf) c.push(chip(zf ? (fon ? 'zm-ok' : 'zm-off') : sys.zapret_fix_off ? 'zm-off' : 'zm-bad',
				zf ? 'поправка для Zapret' : sys.zapret_fix_off ? 'поправка для Zapret отключена' : 'нет поправки для Zapret',
				zf ? 'Поправка Flow Offloading для Zapret применена' + (fon ? '' : idle) : sys.zapret_fix_off ? 'Поправка для Zapret отключена вручную — сама не включится' : 'Flow Offloading включён, а поправки для Zapret нет — часть соединений может идти мимо Zapret'));
			var mh = String(sysInfo.mirror_host || '');
			if (mh) {
				var def = mh === 'downloads.openwrt.org', how = def ? '' : String(sysInfo.mirror_how || '');
				var at = how && +sysInfo.mirror_at > 0 ? new Date(sysInfo.mirror_at * 1000) : null, when = at ? ' ' + p2(at.getDate()) + '.' + p2(at.getMonth() + 1) : '';
				c.push(chip(def ? 'zm-off' : how === 'auto' ? 'zm-warn' : 'zm-sx-info',
					def ? 'Зеркало OpenWrt · основное' : 'Зеркало ' + String(sysInfo.mirror || mh) + (how === 'auto' ? ' · автовыбор' + when : how === 'pick' ? ' · подобрано' + when : ''),
					'Откуда ставятся пакеты OpenWrt: ' + mh + (how === 'auto' ? '\nОсновной репозиторий отвечал с ошибками — панель переключилась сама' : how === 'pick' ? '\nПодобрано кнопкой «Подобрать зеркало»' : how === 'manual' ? '\nВыбрано вручную' : '')));
			}
			return E('div', { 'class': 'zm-sysline' }, [ E('span', { 'class': 'zm-label' }, 'Система') ].concat(c));
		}
		function renderOverview(d, hosts, sys, h) {
			var hostsAi = (hosts.items || []).filter(function(it) { return /^ai_/.test(it.id); });
			var hostsOther = (hosts.items || []).filter(function(it) { return !/^ai_/.test(it.id); });
			var hostsEnabled = hostsOther.filter(function(it) { return it.enabled; }).length + (hostsAi.some(function(it) { return it.enabled; }) ? 1 : 0);
			var hostsTotal = hostsOther.length + (hostsAi.length ? 1 : 0);

			var zrSt = st(h, 'zapret', d.zapret === 'installed' ? (d.zapret_running ? 1 : 2) : 0);
			var zr2St = st(h, 'zapret2', d.zapret2 === 'installed' ? (d.zapret2_running ? 1 : 2) : 0);

			var items = [];
			if (zrSt !== 0) items.push(row('Zapret', zm.stateBadge(zrSt)));
			if (zrSt !== 0 && d.strategy) items.push(row('Стратегия', E('span', { 'style': 'display:inline-flex; gap:8px; flex-wrap:wrap; align-items:center' }, [ E('span', {}, [ String(d.strategy) ]),
				d.rkn_on ? E('span', { 'class': 'zm-badge zm-ok' }, [ E('span', { 'class': 'zm-dot' }), 'по спискам РКН' ]) : d.ulist_on ? E('span', { 'class': 'zm-badge zm-ok' }, [ E('span', { 'class': 'zm-dot' }), 'по вашему списку' ]) : '',
				d.testing ? E('span', { 'class': 'zm-badge zm-warn', 'title': 'Пока идёт тест, роутер по очереди пробует стратегии. Потом вернётся ваша' }, [ E('span', { 'class': 'zm-dot' }), 'идёт тест' + (d.test_now ? ': сейчас ' + d.test_now : '') ]) : '' ])));
			if (zr2St !== 0) items.push(row('Zapret2', zm.stateBadge(zr2St)));

			var offBadge = function(text) { return E('span', { 'class': 'zm-badge zm-off' }, [ E('span', { 'class': 'zm-dot' }), text ]); };
			var trSt = h && h.dots && typeof h.dots.term === 'number' ? h.dots.term : 0;
			if (trSt !== 0) items.push(row('Терминал', trSt === 1 ? zm.badge(true, 'работает', '') : trSt === 2 ? zm.badge(false, '', 'не работает') : trSt === 4 ? offBadge('выключен') : zm.badge(false, '', 'не установлен')));
			if (hosts.geohide || hostsEnabled > 0) items.push(row('Домены в hosts', hosts.geohide
				? zm.badge(true, hosts.geohide === 'malw' ? 'dns.malw.link' : 'GeoHide ' + hosts.geohide.toUpperCase(), '')
				: zm.badge(true, 'включено ' + hostsEnabled + ' из ' + hostsTotal, '')));

			var half = Math.ceil(items.length / 2);

			return E('div', { 'class': 'zm-card', 'style': 'margin-bottom:4px' }, [
				E('h3', {}, 'Компоненты'),
				items.length ? E('div', { 'class': 'bt-cols' }, [
					E('div', { 'class': 'bt-col' }, items.slice(0, half)),
					E('div', { 'class': 'bt-col' }, items.slice(half))
				]) : E('p', { 'class': 'zm-hint', 'style': 'margin-top:0' }, 'Пока ничего не установлено и не настроено — нужное ставится в разделах меню слева. Здесь появятся только установленные компоненты.'),
				sysStrip(sys || {})
			]);
		}

		function renderCards() {
			cards.innerHTML = '';

			var mem = boardInfo.memory || {};
			var ramAvail = mem.available != null ? mem.available : ((mem.free || 0) + (mem.buffered || 0) + (mem.cached || 0));
			var ru = zm.parseSize(sysInfo.root_used), rf = zm.parseSize(sysInfo.root_free);
			var tu = zm.parseSize(sysInfo.tmp_used), tf = zm.parseSize(sysInfo.tmp_free);

			var rows = [
				row('Модель', E('span', {}, [ String(sysInfo.model || '—') ])),
				row('Архитектура', E('span', {}, [ String(sysInfo.arch || '—') ])),
				row('Платформа', E('span', {}, [ String(sysInfo.target || '—') ])),
				row('OpenWrt', E('span', {}, [ String(sysInfo.openwrt || '—') ]))
			];
			function meter(label, val, pct, mid, hi) {
				pct = Math.max(0, Math.min(100, pct || 0));
				return E('div', { 'class': 'zm-meter zmw-mem-row' + (pct >= hi ? ' zm-meter-hi zmw-mem-hi' : pct >= mid ? ' zm-meter-mid zmw-mem-mid' : '') }, [
					E('div', { 'class': 'zm-meter-head zmw-mem-head' }, [
						E('span', { 'class': 'zm-meter-label zmw-mem-label' }, label),
						E('span', { 'class': 'zm-meter-val zmw-mem-val' }, val)
					]),
					E('div', { 'class': 'zm-meter-bar zmw-mem-bar' }, [ E('i', { 'style': 'width:' + pct.toFixed(0) + '%' }) ])
				]);
			}
			function usage(label, used, total) {
				return total > 0 ? meter(label, zm.fmtSize(used) + ' из ' + zm.fmtSize(total), used / total * 100, 65, 85) : null;
			}
			var memRows = [];
			var t = parseFloat(sysInfo.cpu_temp);
			if (!isNaN(t)) memRows.push(meter('Температура ЦП', sysInfo.cpu_temp + ' °C', t, 65, 80));
			memRows.push(usage('ОЗУ', mem.total - ramAvail, mem.total));
			memRows.push(usage('Флеш', ru, ru + rf));
			memRows.push(usage('/tmp', tu, tu + tf));
			memRows = memRows.filter(Boolean);
			var up = parseInt(boardInfo.uptime, 10), extras = [];
			if (up > 0) {
				var dd = Math.floor(up / 86400), hh = Math.floor(up % 86400 / 3600), mm = Math.floor(up % 3600 / 60);
				extras.push(row('Время работы', E('span', {}, (dd ? dd + ' дн ' : '') + (dd || hh ? hh + ' ч ' : '') + mm + ' мин')));
			}
			var ims = parseInt(sysInfo.inet_ms, 10);
			extras.push(row('Интернет', sysInfo.inet === 'ok'
				? E('span', { 'class': 'zm-badge ' + (ims >= 200 ? 'zm-warn' : 'zm-ok') }, [ E('span', { 'class': 'zm-dot' }), isNaN(ims) ? 'есть' : 'есть · ' + ims + ' мс' ])
				: sysInfo.inet === 'nodns'
					? E('span', { 'class': 'zm-badge zm-warn', 'title': 'Сайты по IP-адресу отвечают, а имена сайтов роутер найти не может — поэтому панель ничего не скачивает' }, [ E('span', { 'class': 'zm-dot' }), 'есть, но не работает DNS роутера' ])
					: sysInfo.inet === 'fail'
						? E('span', { 'class': 'zm-badge zm-bad' }, [ E('span', { 'class': 'zm-dot' }), 'нет' ])
						: E('span', { 'class': 'zm-badge zm-off' }, [ E('span', { 'class': 'zm-dot' }), 'проверяем…' ])));
			if (sysInfo.inet === 'nodns') extras.push(E('p', { 'class': 'zm-hint', 'style': 'margin:4px 0 0' },
				'Проверьте настройки DNS роутера. Если DNS не трогали — перезагрузите роутер.'));
			rows = rows.concat(extras);

			cards.appendChild(E('div', { 'class': 'zm-card' }, [
				E('h3', {}, 'Система'),
				E('div', { 'class': 'bt-cols' }, [
					E('div', { 'class': 'bt-col' }, rows),
					E('div', { 'class': 'bt-col zm-meters' }, memRows)
				])
			]));
		}

		function refreshOverview() {
			Promise.all([
				zm.status(),
				zm.hostsStatus().catch(function() { return { items: [] }; }),
				zm.systemStatus().catch(function() { return {}; }),
				zm.health().catch(function() { return {}; })
			]).then(function(res) {
				overviewEl.innerHTML = '';
				overviewEl.appendChild(renderOverview(res[0], res[1], res[2], res[3]));
				if (res[3] && typeof res[3].zapret === 'number') {
					try { window.dispatchEvent(new CustomEvent('zm:health', { detail: res[3] })); } catch (e) {}
				}
			});
		}

		var verEl = E('div', {});
		var verTimer = null, verData = null;

		function renderVersions() {
			verEl.innerHTML = '';
			var d = verData || { items: [], pending: true };
			var items = d.items || [];
			var checked = +d.at > 0;
			var card = E('div', { 'class': 'zm-card' }, [ E('h3', {}, 'Версии') ]);
			if (!items.length) {
				card.appendChild(E('p', { 'class': 'zm-hint' }, d.pending ? 'Проверяем версии установленных пакетов…'
					: d.ts === '' && !checked ? 'Версии ещё не проверялись — нажмите «Проверить».' : 'Пакеты Zapret Manager пока не установлены.'));
			} else {
				var rows = items.map(function(it) {
					var fresh = !it.latest || it.latest === it.installed;
					return row(it.name, E('span', { 'style': 'display:inline-flex; align-items:center; gap:8px; flex-wrap:wrap' }, [
						E('span', {}, [ String(it.installed || '') ]),
						!it.latest && !checked ? E('span', { 'class': 'zm-badge zm-off', 'title': 'Нажмите «Проверить», чтобы узнать, есть ли версия новее' }, [ E('span', { 'class': 'zm-dot' }), 'не проверялась' ])
							: fresh ? E('span', { 'class': 'zm-badge zm-ok' }, [ E('span', { 'class': 'zm-dot' }), 'актуальна' ])
							: E('span', { 'class': 'zm-badge zm-warn' }, [ E('span', { 'class': 'zm-dot' }), 'доступна ' + it.latest ])
					]));
				});
				var half = Math.ceil(rows.length / 2);
				card.appendChild(E('div', { 'class': 'bt-cols' }, [
					E('div', { 'class': 'bt-col' }, rows.slice(0, half)),
					E('div', { 'class': 'bt-col' }, rows.slice(half))
				]));
			}
			var mm = ('0' + (parseInt(d.minute, 10) || 0)).slice(-2), nx = d.next || '04:' + mm, ev = +d.every || 24;
			var how = d.mode === 'open' ? 'версии проверяются при каждом открытии Дашборда'
				: d.mode === 'button' ? 'новые версии ищутся только по этой кнопке'
				: d.bg === false ? 'фоновые проверки выключены — проверка при открытии Дашборда'
				: 'роутер проверяет сам ' + (ev < 24 ? 'каждые ' + ev + ' ч' : 'раз в сутки') + ', следующая — в ' + nx;
			var said = d.pending ? 'Проверяем новые версии…'
				: checked && d.ts ? 'Проверено: ' + d.ts + ' · ' + how
				: d.mode === 'button' ? 'Новые версии ищутся только по этой кнопке — так роутер не нагружается'
				: d.mode === 'open' ? 'Версии ещё не проверялись · ' + how
				: 'Версии ещё не проверялись — роутер проверит сам в ' + nx + ', или нажмите «Проверить»';
			card.appendChild(E('div', { 'class': 'zm-actions' }, [
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'disabled': d.pending ? '' : null,
					'click': function() { loadVersions('refresh'); }
				}, d.pending ? 'Проверяем…' : checked ? 'Проверить снова' : 'Проверить'),
				E('span', { 'class': 'zm-hint', 'style': 'margin:0' }, said)
			]));
			verEl.appendChild(card);
		}

		function loadVersions(action) {
			if (verTimer) { clearTimeout(verTimer); verTimer = null; }
			if (action === 'refresh' && verData) { verData.pending = true; renderVersions(); }
			(zm.versions ? zm.versions(action || '') : Promise.resolve({ items: [] })).then(function(res) {
				verData = res || { items: [] };
				renderVersions();
				if (!verData.pending) applyZmUpdate(zm.zmUpdateFromVersions(verData));
				if (verData.pending && document.body.contains(verEl)) verTimer = setTimeout(function() { loadVersions(''); }, 4000);
			}).catch(function() { verData = { items: (verData && verData.items) || [] }; renderVersions(); });
		}

		overviewEl.appendChild(renderOverview(data, hostsData, sysData, healthData));
		renderCards();
		var updateEl = E('div', {});
		var updateLog = E('pre', { 'class': 'zm-log' });
		wrap.appendChild(updateEl);
		wrap.appendChild(updateLog);
		if (!document.body.classList.contains('zmw-body')) wrap.appendChild(zm.alertBanners(healthData, function() { location.reload(); }));
		if (!document.body.classList.contains('zmw-body')) wrap.appendChild(E('div', { 'class': 'zm-header' }, [
			E('h2', {}, 'Zapret Manager для LuCI и Web')
		]));
		wrap.appendChild(overviewEl);
		wrap.appendChild(cards);
		wrap.appendChild(verEl);
		renderVersions();
		loadVersions('auto');

		this.refreshOverview = refreshOverview;

		var sysTick = 0, sysBusy = false;
		var sysTimer = setInterval(function() {
			if (!document.body.contains(cards)) { if (sysTick > 2) clearInterval(sysTimer); sysTick++; return; }
			if (document.hidden || sysBusy) return;
			sysBusy = true;
			sysTick++;
			Promise.all([
				zm.systemInfo().catch(function() { return null; }),
				zm.boardInfo().catch(function() { return null; })
			]).then(function(r) {
				if (r[0] && !r[0].error) sysInfo = r[0];
				if (r[1] && r[1].memory) boardInfo = r[1];
				renderCards();
				try { window.dispatchEvent(new CustomEvent('zm:sysinfo', { detail: { sys: r[0] && !r[0].error ? r[0] : null, board: r[1] && r[1].memory ? r[1] : null } })); } catch (e) {}
				if (sysTick % 3 === 0) refreshOverview();
				if (sysTick % 60 === 0) zm.zmUpdateStatus().then(applyZmUpdate).catch(function() {});
			}).catch(function() {}).then(function() { sysBusy = false; });
		}, 10000);

		var zmUpdateBusy = false;
		function applyZmUpdate(u) {
			if (!u || u.error || !u.current) return;
			var was = [ zmUpdate.current, zmUpdate.latest, zmUpdate.newer ].join('|');
			zmUpdate = { current: u.current, latest: u.latest || '', newer: u.newer };
			zm.zmUpdateNotify(zmUpdate);
			if (zmUpdateBusy || was === [ zmUpdate.current, zmUpdate.latest, zmUpdate.newer ].join('|')) return;
			renderZmUpdate();
		}
		function waitForServerAndReload() {
			setTimeout(function() { location.href = L.url('admin/logout'); }, 4000);
		}
		function renderZmUpdate() {
			updateEl.innerHTML = '';
			if (!zmUpdate.latest || zmUpdate.latest === zmUpdate.current || zmUpdate.newer === false) return;
			updateEl.appendChild(zm.floatBanner(E('div', { 'class': 'zm-refresh-banner zm-show' }, [
				E('span', {}, [ 'Доступна новая версия панели Zapret Manager: ' + zmUpdate.latest + ' (у вас установлена ' + zmUpdate.current + ').' ]),
				E('button', { 'class': 'cbi-button zm-cl-link', 'type': 'button', 'click': function() {
					var upd = this.parentNode.querySelector('.cbi-button-positive');
					zm.changelogShow('remote', { want: zmUpdate.latest, current: zmUpdate.current, onUpdate: upd ? function() { upd.click(); } : null });
				} }, 'Что изменится'),
				E('button', {
					'class': 'cbi-button cbi-button-positive',
					'click': function() {
						if (zmUpdateBusy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
						zmUpdateBusy = true;
						zm.toast('Скачиваем и проверяем новую версию…', 'info', 4000);
						zm.zmUpdateAction().then(function(res) {
							if (res.error) { zmUpdateBusy = false; zm.toast('Обновление не началось: ' + res.error, 'error', 8000); return; }
							var go = function(v) {
								zm.toast('Устанавливаем версию ' + (v || zmUpdate.latest) + ' — через 4 секунды вы будете выведены из LuCI. Подождите полминуты и зайдите заново', 'warning', 8000);
								waitForServerAndReload();
							};
							if (!res.started) { zmUpdateBusy = false; go(res.version); return; }
							try { updateLog.scrollIntoView({ block: 'nearest' }); } catch (e) {}
							zm.pollJob('zm_update', updateLog, function(ok) {
								zmUpdateBusy = false;
								if (ok) { go(''); return; }
								var m = /ОШИБКА:\s*([^\n]+)/.exec(updateLog.textContent || '');
								zm.toast('Обновление не началось: ' + (m ? m[1] : 'причина — в журнале на странице'), 'error', 8000);
							});
						}).catch(function() { zmUpdateBusy = false; });
					}
				}, 'Обновить панель')
			])));
		}
		renderZmUpdate();
		zm.zmUpdateNotify(zmUpdate);

		return wrap;
	}
});
ZM_INSTALLER_EOF
chmod 0644 '/www/luci-static/resources/view/zapret-manager/dashboard.js'

cat > '/www/luci-static/resources/view/zapret-manager/terminal.js' << 'ZM_INSTALLER_EOF'
'use strict';
'require view';
'require zapret-manager.common as zm';
var E = (function(raw) { return function() { var a = Array.prototype.slice.call(arguments), i = a.length - 1; if (i >= 1 && (typeof a[i] === 'string' || typeof a[i] === 'number')) a[i] = [ String(a[i]) ]; return raw.apply(null, a); }; })(window.E);

return view.extend({
	load: function() {
		zm.injectCss();
		return zm.termStatus();
	},

	render: function(data) {
		data = data || {};
		var wrap = E('div', { 'class': 'zm-wrap' });
		var card = E('div', { 'class': 'zm-card' });
		var headEl = E('div', {});
		var viewEl = E('div', { 'style': 'display:none; margin:0 0 14px' });
		var actEl = E('div', {});
		var logEl = E('pre', { 'class': 'zm-log' });
		var busy = false, frame = null, autoTried = false;
		var canEmbed = window.location.protocol === 'http:';
		var keep = window.zmTermKeep || null;
		function dropFrame() { frame = null; if (keep) keep.drop(); }
		var DONE = { install: 'Терминал установлен', remove: 'Терминал удалён' };

		function addr() { return 'http://' + window.location.hostname + ':' + (data.port || 7681) + '/'; }

		function termTitle() { return 'ttyd · ' + window.location.hostname + ':' + (data.port || 7681); }

		function frameUrl() {
			var base = addr(), bg = '';
			if (window.zmTermUrl && String(window.zmTermUrl).indexOf(base) === 0) return window.zmTermUrl;
			try { bg = getComputedStyle(document.documentElement).getPropertyValue('--console').trim(); } catch (e) { bg = ''; }
			if (!/^#[0-9a-f]{6}$/i.test(bg)) bg = '#0d1117';
			var theme = {
				background: bg, foreground: '#e6edf3', cursor: '#e6edf3',
				black: '#000000', red: '#d81e00', green: '#5ea702', yellow: '#cfae00', blue: '#427ab3', magenta: '#89658e', cyan: '#00a7aa', white: '#dbded8',
				brightBlack: '#686a66', brightRed: '#f54235', brightGreen: '#99e343', brightYellow: '#fdeb61', brightBlue: '#84b0d8', brightMagenta: '#bc94b7', brightCyan: '#37e6e8', brightWhite: '#f1f1f0'
			};
			window.zmTermUrl = base + '?disableLeaveAlert=true&theme=' + encodeURIComponent(JSON.stringify(theme));
			return window.zmTermUrl;
		}

		function refresh() {
			return zm.termStatus().then(function(d) { data = d || {}; renderAll(); autoStart(); });
		}

		function follow(action) {
			busy = true;
			dropFrame();
			renderAll();
			zm.pollJob('term', logEl, function(ok) {
				busy = false;
				zm.toast(ok ? (DONE[action] || 'Готово') : 'Не получилось — подробности в журнале', ok ? 'info' : 'error');
				refresh();
			});
		}

		function job(action, text) {
			if (busy) { zm.toast('Дождитесь окончания текущей операции', 'warning'); return; }
			zm.termAction(action, '').then(function(res) {
				if (res.error) { zm.toast(res.error, 'error'); return; }
				zm.toast(text, 'warning');
				follow(action);
			}).catch(function() { zm.toast('Роутер не ответил', 'error'); });
		}

		function quick(action, okText) {
			if (busy) { zm.toast('Дождитесь окончания текущей операции', 'warning'); return; }
			busy = true;
			dropFrame();
			renderAll();
			zm.termAction(action, '').then(function(res) {
				busy = false;
				if (res.error) zm.toast(res.error, 'error'); else if (okText) zm.toast(okText, 'info');
				refresh();
			}).catch(function() { busy = false; zm.toast('Роутер не ответил', 'error'); renderAll(); });
		}

		function autoStart() {
			if (autoTried || busy || data.job || !data.installed || data.running) return;
			autoTried = true;
			quick('start', '');
		}

		function btn(cls, text, fn) {
			return E('button', { 'class': 'cbi-button ' + cls, 'disabled': busy ? '' : null, 'click': fn }, text);
		}

		function renderHead() {
			headEl.innerHTML = '';
			if (data.installed) return;
			headEl.appendChild(E('h3', {}, 'Терминал'));
			headEl.appendChild(E('p', { 'class': 'zm-hint', 'style': 'margin-top:-6px' }, 'Командная строка роутера прямо в браузере (ttyd). Ставится пакет ttyd из репозитория OpenWrt (около 1 МБ), терминал запустится сам и откроется здесь.'));
		}

		function renderView() {
			var show = !!data.installed && !!data.running && canEmbed && !busy;
			if (keep) {
				viewEl.style.display = 'none';
				if (!show) keep.hide(); else keep.open(frameUrl(), termTitle());
				return;
			}
			if (!show) { viewEl.style.display = 'none'; return; }
			if (!frame) {
				frame = E('iframe', { 'class': 'zm-term-frame', 'src': frameUrl() });
				viewEl.innerHTML = '';
				viewEl.appendChild(E('div', { 'class': 'zm-term' }, [
					E('div', { 'class': 'zm-term-bar' }, [
						E('span', { 'class': 'zm-term-dots' }, [ E('i', {}), E('i', {}), E('i', {}) ]),
						E('span', { 'class': 'zm-term-title' }, termTitle())
					]),
					E('div', { 'class': 'zm-term-body' }, [ frame ])
				]));
			}
			viewEl.style.display = '';
		}

		function renderActions() {
			actEl.innerHTML = '';
			var b = [];
			if (!data.installed) {
				b.push(btn('cbi-button-positive', 'Установить', function() { job('install', 'Устанавливаем терминал — ход работы виден в окне вывода'); }));
				actEl.appendChild(E('div', { 'class': 'zm-actions' }, b));
				return;
			}
			if (data.running) b.push(E('a', { 'class': 'cbi-button cbi-button-positive', 'href': addr(), 'target': '_blank', 'rel': 'noopener' }, 'Открыть в новой вкладке'));
			b.push(btn('', 'Перезапустить', function() { quick('restart', 'Терминал перезапущен'); }));
			b.push(btn('cbi-button-remove', 'Удалить', function() {
				zm.dialog({ title: 'Удалить терминал?', danger: true, okText: 'Удалить терминал',
					blocks: [ { type: 'list', title: 'Что произойдёт', items: [
						'Терминал остановится',
						'Пакет ttyd удалится вместе с настройками'
					] } ]
				}).then(function(v) { if (v) job('remove', 'Удаляем терминал — ход работы виден в окне вывода'); });
			}));
			actEl.appendChild(E('div', { 'class': 'zm-actions' }, b));
			if (data.running && !canEmbed) actEl.appendChild(E('p', { 'class': 'zm-hint' }, 'Панель открыта по https, а терминал работает по http — встроить его сюда нельзя, он откроется в отдельной вкладке.'));
		}

		var accCard = E('div', { 'class': 'zm-card' });
		function renderAccess() {
			accCard.innerHTML = '';
			accCard.style.display = data.installed && data.ts ? '' : 'none';
			if (accCard.style.display) return;
			var m = data.mode || 'home', on = m === 'all';
			accCard.appendChild(E('h3', {}, [ 'Доступ через Tailscale ', on ? E('span', { 'class': 'zm-badge zm-ok' }, [ E('span', { 'class': 'zm-dot' }), 'дома и в Tailscale' ])
				: m === 'ts' ? E('span', { 'class': 'zm-badge zm-warn' }, [ E('span', { 'class': 'zm-dot' }), 'только Tailscale' ])
				: m === 'other' ? E('span', { 'class': 'zm-badge zm-warn' }, [ E('span', { 'class': 'zm-dot' }), 'своя настройка' ])
				: E('span', { 'class': 'zm-badge zm-off' }, [ E('span', { 'class': 'zm-dot' }), 'только дома' ]) ]));
			var hint = on ? 'Работает дома и через Tailscale. Из интернета закрыт.'
				: m === 'ts' ? 'Сейчас только через Tailscale — дома не откроется.'
				: m === 'other' ? 'Выбран интерфейс «' + (data.iface || '') + '». Включите, чтобы работал и дома, и через Tailscale.'
				: 'Сейчас только дома. Вне дома вместо терминала будет пустая страница.';
			if (!data.wan_closed && !on) hint = 'Нельзя: в firewall открыт вход из интернета (зона wan → Входящие: отклонять).';
			accCard.appendChild(zm.swRow(on, 'Открывать через Tailscale', hint, function() {
				quick(on ? 'ts_off' : 'ts_on', on ? 'Терминал теперь только для домашней сети' : 'Терминал открывается и через Tailscale');
			}, busy || (!on && !data.wan_closed)));
			var addrs = [];
			if (data.lan_ip) addrs.push(E('b', {}, 'http://' + data.lan_ip + ':7788'));
			if (data.ts_ip) addrs.push(E('b', {}, 'http://' + data.ts_ip + ':7788'));
			if (on && addrs.length) accCard.appendChild(E('p', { 'class': 'zm-hint' }, [ 'Вне дома откройте панель: ', addrs[0], addrs[1] ? E([ ' или ', addrs[1] ]) : '' ]));
		}

		function renderAll() { renderHead(); renderView(); renderActions(); renderAccess(); }

		card.appendChild(headEl);
		card.appendChild(viewEl);
		card.appendChild(actEl);
		wrap.appendChild(card);
		wrap.appendChild(accCard);
		wrap.appendChild(logEl);
		renderAll();
		if (data.job) follow(''); else autoStart();
		return wrap;
	}
});
ZM_INSTALLER_EOF
chmod 0644 '/www/luci-static/resources/view/zapret-manager/terminal.js'

cat > '/www/luci-static/resources/view/zapret-manager/hosts.js' << 'ZM_INSTALLER_EOF'
'use strict';
'require view';
'require zapret-manager.common as zm';
var E = (function(raw) { return function() { var a = Array.prototype.slice.call(arguments), i = a.length - 1; if (i >= 1 && (typeof a[i] === 'string' || typeof a[i] === 'number')) a[i] = [ String(a[i]) ]; return raw.apply(null, a); }; })(window.E);

var LABELS = {
	nalog: [ 'nalog.ru', 'Налоговая' ],
	ntc: [ 'ntc.party', 'Форум про обход блокировок' ],
	instagram: [ 'Instagram', 'Instagram и Facebook' ],
	librusec: [ 'lib.rus.ec', 'Библиотека' ],
	ai_openai: [ 'ChatGPT', 'OpenAI, Sora' ],
	ai_claude: [ 'Claude', 'Anthropic' ],
	ai_gemini: [ 'Gemini', 'Google' ],
	ai_aistudio: [ 'Google AI Studio', 'AI Studio, NotebookLM, Labs' ],
	ai_grok: [ 'Grok', 'xAI' ],
	ai_copilot: [ 'Copilot', 'Microsoft, Bing' ],
	ai_deepl: [ 'DeepL', 'Переводчик' ],
	ai_elevenlabs: [ 'ElevenLabs', 'Озвучка' ],
	ai_windsurf: [ 'Windsurf', 'Codeium' ],
	ai_trae: [ 'Trae.ai', 'Редактор кода' ],
	ai_manus: [ 'Manus', 'AI-агент' ],
	ai_notion: [ 'Notion', 'Заметки' ],
	twitch: [ 'Twitch', 'Стримы' ],
	telegram: [ 'Telegram Web', 'Веб-версия' ],
	spotify: [ 'Spotify', 'Музыка' ],
	spotifyext: [ 'Spotify extended', 'Расширенный список' ],
	rutor: [ 'rutor.info', 'Торренты' ],
	rutracker: [ 'rutracker.org', 'Торренты' ],
	scell: [ 'Supercell', 'Clash, Brawl Stars' ],
	roblox: [ 'Картинки Roblox', 'tr.rbxcdn.com — аватары и превью' ],
	githubraw: [ 'GitHub Raw', 'githubusercontent.com' ],
	github: [ 'GitHub', 'Код и релизы' ],
	tapeop: [ 'tapeop.dev', 'Сайт' ],
	finland: [ 'Финские IP для Discord', 'Голосовые серверы Discord' ]
};

function lbl(id) { return (LABELS[id] || [ id ])[0]; }
function isAi(id) { return /^ai_/.test(id); }

return view.extend({
	load: function() {
		zm.injectCss();
		return zm.hostsStatus();
	},

	render: function(data) {
		var wrap = E('div', { 'class': 'zm-wrap' });
		var grid = E('div');
		var busy = false, pick = null, lastItems = data.items || [];
		var hostsLog = E('pre', { 'class': 'zm-log' });

		function curOn(items) {
			var m = {};
			(items || []).forEach(function(it) { if (it.enabled) m[it.id] = true; });
			return m;
		}

		function changes() {
			var cur = curOn(lastItems), out = [];
			if (!pick) return out;
			lastItems.forEach(function(it) { if (!!pick[it.id] !== !!cur[it.id]) out.push(it.id); });
			return out;
		}

		var bar = zm.saveBar({
			onCancel: function() { pick = null; renderGrid(lastItems); },
			onSave: applyPick
		});

		var aiOpen = false;

		function renderGrid(items) {
			lastItems = items || [];
			grid.innerHTML = '';
			var sel = pick || curOn(lastItems);
			function edit(fn) {
				if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
				var p = {};
				for (var k in sel) if (sel[k]) p[k] = true;
				fn(p);
				pick = p;
				renderGrid(lastItems);
			}
			function tile(it) {
				var l = LABELS[it.id] || [ it.id, '' ];
				return zm.svcCard({ name: l[0], key: it.id, on: !!sel[it.id], title: l[1] ? l[0] + ' — ' + l[1] : l[0], click: function() {
					edit(function(p) { if (p[it.id]) delete p[it.id]; else p[it.id] = true; });
				} });
			}
			function aiGroup(ai) {
				var on = ai.filter(function(it) { return sel[it.id]; }).length, all = on === ai.length;
				function setAll(v) { edit(function(p) { ai.forEach(function(it) { if (v) p[it.id] = true; else delete p[it.id]; }); }); }
				var sw = E('div', { 'class': 'zm-switch' + (on ? ' zm-switch-on' : '') + (on && !all ? ' zm-switch-inc' : ''), 'title': all ? 'Снять все' : 'Выбрать все', 'click': function(ev) {
					ev.stopPropagation();
					setAll(!all);
				} }, [ E('span') ]);
				return zm.svcGroup({
					name: 'AI-сервисы', sub: 'ChatGPT, Claude, Gemini', key: 'ai', open: aiOpen,
					badge: E('span', { 'style': 'display:inline-flex; align-items:center; gap:10px' }, [
						E('span', { 'class': 'zm-badge ' + (on ? 'zm-ok' : 'zm-off') }, on + ' из ' + ai.length),
						sw
					]),
					body: zm.svcGrid(ai.map(tile)),
					toggle: function(o) { aiOpen = o; }
				});
			}
			var ai = lastItems.filter(function(it) { return isAi(it.id); });
			grid.appendChild(E('h4', { 'style': 'margin:0' }, 'Сервисы'));
			grid.appendChild(zm.svcGrid(lastItems.filter(function(it) { return !isAi(it.id); }).map(tile)));
			if (ai.length) {
				grid.appendChild(E('h4', { 'style': 'margin:18px 0 0' }, 'AI-сервисы'));
				grid.appendChild(aiGroup(ai));
			}
			var n = changes().length;
			bar.set(n > 0 || busy, busy, n ? 'Есть несохранённые изменения: ' + n : '');
		}

		function hostsRisk(replace, info) {
			return zm.warnOnce('warn_hosts', function() {
				return zm.warnDialog({
					info: info,
					title: 'Адреса из hosts важнее VPN и DoH',
					lead: 'Запись в hosts привязывает сайт к одному IP-адресу: роутер отдаёт его сразу, не спрашивая DNS. Поэтому:',
					items: [
						[ 'Адрес перестал работать — сервис не откроется', 'даже через VPN или DoH' ],
						[ 'Адреса в списках устаревают', 'сегодня работает, завтра может перестать' ]
					],
					tip: { title: 'Сервис не открывается?', text: 'Снимите его галочку на этой странице или нажмите «Восстановить hosts».' },
					note: replace ? 'Замена удалит весь текущий hosts — отмеченные сервисы и ваши записи.' : '',
					noteKind: 'bad',
					check: 'Понимаю: с неработающим адресом в hosts сервис не откроется даже с VPN или DoH',
					okText: info ? '' : replace ? 'Заменить hosts' : 'Применить'
				});
			});
		}

		function applyPick() {
			var list = changes();
			if (!list.length || busy) return;
			if (list.some(function(id) { return !!pick[id]; })) {
				return hostsRisk(false).then(function(ok) { if (ok) applyNow(list); return ok ? undefined : false; });
			}
			applyNow(list);
		}

		function applyNow(list) {
			if (busy) return;
			busy = true;
			bar.set(true, true);
			var log = [ '==> Применяем изменения в /etc/hosts' ];
			hostsLog.classList.add('zm-show');
			zm.renderLog(hostsLog, log.join('\n'));
			var i = 0, failed = 0;
			(function next() {
				if (i >= list.length) {
					log.push(failed ? '==> ОШИБКА: не всё применилось — смотрите строки выше' : '==> Готово — /etc/hosts обновлён, dnsmasq перечитал его');
					zm.renderLog(hostsLog, log.join('\n'));
					zm.toast(failed ? 'Не всё применилось' : 'Изменения применены', failed ? 'error' : 'info');
					busy = false;
					pick = null;
					zm.hostsStatus().then(function(r) { data = r; renderGrid(r.items); renderGeoGrid(); }).catch(function() { renderGrid(lastItems); });
					syncEditor();
					return;
				}
				var id = list[i++], want = !!pick[id];
				log.push('   → ' + (want ? 'Добавляем' : 'Убираем') + ' адреса ' + lbl(id));
				zm.renderLog(hostsLog, log.join('\n'));
				zm.hostsToggle(id).then(function(res) {
					if (res.error) { failed++; log.push('   ✗ ' + lbl(id) + ': ' + res.error); }
					else log.push('   ✓ ' + lbl(id) + (res.enabled ? ' включён' : ' выключен'));
					next();
				}).catch(function() { failed++; log.push('   ✗ ' + lbl(id) + ': роутер не ответил'); next(); });
			})();
		}

		renderGrid(data.items);
		if ((data.items || []).some(function(it) { return it.enabled; }) || (data.geohide && data.geohide !== '') || data.extra) setTimeout(function() {
			if (document.body.contains(wrap)) hostsRisk(false, true);
		}, 400);

		var card = E('div', { 'class': 'zm-card' }, [
			E('h3', {}, 'Домены в /etc/hosts'),
			E('p', { 'class': 'zm-hint', 'style': 'margin-top:-6px' }, 'Отметьте сервисы и нажмите «Сохранить и применить» — их адреса пропишутся в /etc/hosts.'),
			grid,
			hostsLog,
			bar
		]);
		wrap.appendChild(card);

		var geoLogEl = E('pre', { 'class': 'zm-log' });
		var geoGrid = E('div', { 'class': 'zm-grid' });

		var HOSTS_SRC = { ru: 'GeoHide RU', eu: 'GeoHide EU', us: 'GeoHide US', malw: 'dns.malw.link' };
		function renderGeoGrid() {
			geoGrid.innerHTML = '';
			[ 'ru', 'eu', 'us', 'malw' ].forEach(function(r) {
				geoGrid.appendChild(E('div', { 'class': 'zm-tile' + (data.geohide === r ? ' zm-active' : ''), 'click': function() { replaceGeohide(r); } }, HOSTS_SRC[r]));
			});
		}
		renderGeoGrid();

		var geoCard = E('div', { 'class': 'zm-card' }, [
			E('h3', {}, 'Заменить весь hosts'),
			E('p', { 'class': 'zm-hint' }, 'Внимание: это ПОЛНОСТЬЮ заменит файл /etc/hosts на готовый список (GeoHide DNS или dns.malw.link) — все блоки выше и любые ваши собственные записи будут удалены.'),
			geoGrid,
			geoLogEl
		]);
		wrap.appendChild(geoCard);

		var resetLogEl = E('pre', { 'class': 'zm-log' });
		var resetBtn = E('button', { 'class': 'cbi-button cbi-button-remove', 'click': resetHosts }, 'Восстановить hosts');

		var resetCard = E('div', { 'class': 'zm-card' }, [
			E('h3', {}, 'Восстановить hosts'),
			E('p', { 'class': 'zm-hint' }, 'Вернёт /etc/hosts к чистому виду — уберёт и блоки выше, и готовый список (GeoHide, dns.malw.link), и всё, что было добавлено вручную.'),
			E('div', { 'class': 'zm-actions' }, [ resetBtn ]),
			resetLogEl
		]);
		wrap.appendChild(resetCard);

		function refreshAll(keepEditor) {
			zm.hostsStatus().then(function(res) {
				data = res;
				renderGrid(res.items);
				renderGeoGrid();
			});
			if (!keepEditor) syncEditor();
		}

		function syncEditor() {
			if (!editorOpen) return;
			if (hostsBar.dirty()) zm.toast('Файл hosts изменился, а в редакторе остались несохранённые правки. Нажмите «Перечитать» — иначе при сохранении новые строки пропадут', 'warning');
			else refreshHostsFile();
		}

		function replaceGeohide(region) {
			if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
			hostsRisk(true).then(function(ok) { if (ok) replaceNow(region); });
		}

		function replaceNow(region) {
			if (busy) return;
			busy = true;
			zm.toast('Заменяем hosts на ' + HOSTS_SRC[region], 'warning');
			geoLogEl.classList.add('zm-show');
			zm.renderLog(geoLogEl, '==> Скачиваем и заменяем /etc/hosts');
			zm.hostsReplaceGeohide(region).then(function(res) {
				busy = false;
				if (res.error) { zm.renderLog(geoLogEl, '==> ОШИБКА: ' + res.error); zm.toast(res.error, 'error'); return; }
				zm.renderLog(geoLogEl, '==> Готово — hosts заменён на ' + HOSTS_SRC[region] + '.');
				zm.toast('hosts заменён на ' + HOSTS_SRC[region], 'info');
				refreshAll();
			}).catch(function() { busy = false; zm.renderLog(geoLogEl, '==> ОШИБКА: роутер не ответил — проверьте hosts и попробуйте ещё раз'); zm.toast('Роутер не ответил', 'error'); refreshAll(); });
		}

		function resetHosts() {
			if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
			busy = true;
			zm.toast('Восстанавливаем hosts', 'warning');
			resetLogEl.classList.add('zm-show');
			zm.renderLog(resetLogEl, '==> Восстанавливаем hosts');
			zm.hostsReset().then(function(res) {
				busy = false;
				if (res.error) { zm.renderLog(resetLogEl, '==> ОШИБКА: ' + res.error); zm.toast(res.error, 'error'); return; }
				zm.renderLog(resetLogEl, '==> Готово — hosts восстановлен.');
				zm.toast('hosts восстановлен', 'info');
				refreshAll();
			}).catch(function() { busy = false; zm.renderLog(resetLogEl, '==> ОШИБКА: роутер не ответил — проверьте hosts и попробуйте ещё раз'); zm.toast('Роутер не ответил', 'error'); refreshAll(); });
		}

		var editorCard = E('div', { 'class': 'zm-card' });
		var editorOpen = false;
		var hostsEl = E('textarea', { 'class': 'zm-config-editor', 'spellcheck': 'false', 'style': 'display:none' });
		var hostsBar = zm.editorBar(hostsEl, {
			onSave: function(v) {
				zm.toast('Сохраняем /etc/hosts и перезапускаем dnsmasq', 'warning');
				return zm.hostsFileSet(v).then(function(res) {
					if (res.error) { zm.toast(res.error, 'error'); return false; }
					zm.toast('hosts сохранён, dnsmasq перезапущен', 'info');
					refreshAll(true);
					return true;
				}).catch(function() { zm.toast('Роутер не ответил', 'error'); return false; });
			}
		});

		var bigInfo = null;

		function refreshHostsFile() {
			zm.hostsFileGet().then(function(res) {
				if (res.error) { zm.toast(res.error, 'error'); return; }
				var was = !!bigInfo;
				bigInfo = res.too_big ? res : null;
				if (bigInfo || was) renderEditorCard();
				if (!bigInfo) hostsBar.reset(res.content || '');
			});
		}

		function renderEditorCard() {
			editorCard.innerHTML = '';
			editorCard.appendChild(E('h3', {}, 'Редактор /etc/hosts'));
			if (!editorOpen) {
				editorCard.appendChild(E('p', { 'class': 'zm-hint' }, 'Прямое редактирование всего файла /etc/hosts.'));
				editorCard.appendChild(E('div', { 'class': 'zm-actions' }, [
					E('button', {
						'class': 'cbi-button',
						'click': function() {
							editorOpen = true;
							refreshHostsFile();
							renderEditorCard();
						}
					}, 'Открыть редактор hosts')
				]));
				return;
			}
			if (bigInfo) {
				hostsEl.style.display = 'none';
				editorCard.appendChild(E('div', { 'class': 'zm-refresh-banner zm-show zm-block-banner' }, [ E('span', {}, 'Файл hosts большой: ' + bigInfo.lines + ' строк, ' + Math.round(bigInfo.size / 1024) + ' КБ (например, список GeoHide). Чтобы не перегружать роутер и не уронить вход в панель, редактор для такого файла отключён. Вернуть обычный hosts можно кнопкой «Восстановить hosts» выше.') ]));
				editorCard.appendChild(E('div', { 'class': 'zm-actions' }, [ E('button', { 'class': 'cbi-button', 'click': function() { editorOpen = false; renderEditorCard(); } }, 'Свернуть') ]));
				return;
			}
			editorCard.appendChild(E('p', { 'class': 'zm-hint' }, 'Сохранение перезапускает dnsmasq. Резервная копия предыдущей версии остаётся в /etc/hosts.bak.'));
			hostsEl.style.display = '';
			editorCard.appendChild(hostsEl);
			editorCard.appendChild(E('div', { 'class': 'zm-actions' }, [
				E('button', {
					'class': 'cbi-button',
					'click': function() {
						var zmGo = function() { refreshHostsFile(); zm.toast('Содержимое перечитано с диска', 'info'); };
						if (hostsBar.dirty()) return zm.ask('Отменить несохранённые изменения и перечитать файл?').then(function(ok) { return ok ? zmGo() : undefined; });
						return zmGo();
					}
				}, 'Перечитать файл'),
				E('button', {
					'class': 'cbi-button',
					'click': function() {
						var zmGo = function() { editorOpen = false; hostsBar.reset(); renderEditorCard(); };
						if (hostsBar.dirty()) return zm.ask('Есть несохранённые изменения. Свернуть без сохранения?').then(function(ok) { return ok ? zmGo() : undefined; });
						return zmGo();
					}
				}, 'Свернуть')
			]));
			editorCard.appendChild(hostsBar);
		}
		renderEditorCard();
		wrap.appendChild(editorCard);

		return wrap;
	}
});
ZM_INSTALLER_EOF
chmod 0644 '/www/luci-static/resources/view/zapret-manager/hosts.js'

cat > '/www/luci-static/resources/view/zapret-manager/strategy.js' << 'ZM_INSTALLER_EOF'
'use strict';
'require view';
'require zapret-manager.common as zm';
var E = (function(raw) { return function() { var a = Array.prototype.slice.call(arguments), i = a.length - 1; if (i >= 1 && (typeof a[i] === 'string' || typeof a[i] === 'number')) a[i] = [ String(a[i]) ]; return raw.apply(null, a); }; })(window.E);

var tsChecking = false;
function tsCheck(spec) {
	return zm.testAction('ts_check', spec).then(function(r) {
		return r && !r.error && r.ts ? (r.parts || []) : null;
	}, function() { return null; });
}
function tsGate(spec, go, ask, note) {
	if (tsChecking) return;
	tsChecking = true;
	tsCheck(spec).then(function(parts) {
		tsChecking = false;
		var plain = function() { if (ask) return zm.ask(ask).then(function(ok) { if (ok) go(); }); go(); };
		if (!parts) return plain();
		return zm.warnSeen('warn_ts').then(function(seen) {
			if (seen) return plain();
			return zm.tsWarn({ parts: parts, note: note }).then(function(ok) { if (ok) { zm.uiFlagSet('warn_ts'); go(); } });
		});
	});
}

var TABS = [
	{ id: 'strategy', label: 'Стратегии' },
	{ id: 'test', label: 'Тест стратегий' },
	{ id: 'youtube', label: 'YouTube' },
	{ id: 'game', label: 'Игры' },
	{ id: 'discord', label: 'Discord' },
	{ id: 'lists', label: 'Редактор списков' },
	{ id: 'exclusions', label: 'Исключение устройств' }
];

var TEST_MODE_LABELS = {
	v: 'v1–v10', flowseal: 'Flowseal', v_flowseal: 'v + Flowseal', youtube: 'YouTube', current: 'Текущая', domain: 'По домену',
	custom: 'Свои', custom_yt: 'Свои · YouTube', custom_dom: 'Свои · ваши сайты', auto: 'Автоподбор'
};
var TEST_RESULT_MODES = ['current', 'domain', 'v', 'flowseal', 'v_flowseal', 'youtube', 'custom', 'custom_yt', 'custom_dom'];
var ZONE_RU = { 'Europe/Kaliningrad': 'Калининград', 'Europe/Moscow': 'Москва', 'Europe/Samara': 'Самара', 'Asia/Yekaterinburg': 'Екатеринбург', 'Asia/Omsk': 'Омск', 'Asia/Krasnoyarsk': 'Красноярск',
	'Asia/Irkutsk': 'Иркутск', 'Asia/Yakutsk': 'Якутск', 'Asia/Vladivostok': 'Владивосток', 'Asia/Magadan': 'Магадан', 'Asia/Kamchatka': 'Камчатка', 'UTC': 'UTC' };
var AUTO_MODES = [ { id: 'v', label: 'v1–v10' }, { id: 'flowseal', label: 'Flowseal' }, { id: 'v_flowseal', label: 'v + Flowseal' }, { id: 'youtube', label: 'Только YouTube' } ];
var CUSTOM_SCRIPTS = [
	{ id: 'off', label: 'Нет' },
	{ id: 'stun4all', label: '50-stun4all', hint: 'обход для STUN на всех портах — голос и видео в Discord, Telegram, WhatsApp и других' },
	{ id: 'quic4all', label: '50-quic4all', hint: 'обход для QUIC на всех портах' },
	{ id: 'discord-media', label: '50-discord-media', hint: 'голосовые серверы Discord (discord.media)' },
	{ id: 'discord', label: '50-discord', hint: 'подсети голосовых серверов Discord (старый вариант из zapret 70.5)' }
];

var GAME_FAKES = [
	'stun.bin', 'stun2.bin', 'quic_initial_4pda_to.bin',
	'quic_initial_tencent_com.bin', 'tls_clienthello_sochi_park.bin',
	'quic_initial_www_google_com.bin', 'quic_initial_steamcommunity_com.bin',
	'quic_initial_5ka_ru.bin', 'quic_initial_rutube_ru.bin'
];

return view.extend({
	load: function() {
		zm.injectCss();
		return Promise.all([
			zm.status(),
			zm.strategyListV(),
			zm.testStatus(),
			zm.strategyListYoutube(),
			zm.gameStatus(),
			zm.discordStatus(),
			zm.exclusionsStatus(),
			Promise.resolve({})
		]);
	},

	render: function(all) {
		var statusData = all[0], vListData = all[1], testData = all[2], ytInitialData = all[3], gameData = all[4], discordData = all[5], exclusionsData = all[6];
		var latestVersion = (all[7] && all[7].version) || '';
		var wrap = E('div', { 'class': 'zm-wrap' });
		var mainSection = E('div', {});
		var activeTab = 'strategy';
		var zapretInstalled = statusData.zapret === 'installed';

		var tabBar = E('div', { 'class': 'zm-actions', 'style': 'margin:10px 0' });
		var panels = {};
		var tabHooks = {};
		var refreshers = {};
		function refreshAll() {
			Object.keys(refreshers).forEach(function(k) { try { refreshers[k](); } catch (e) {} });
		}
		TABS.forEach(function(t) {
			panels[t.id] = E('div', { 'style': t.id === activeTab ? '' : 'display:none' });
		});

		function renderTabBar() {
			tabBar.innerHTML = '';
			TABS.forEach(function(t) {
				tabBar.appendChild(E('button', {
					'class': 'cbi-button' + (t.id === activeTab ? ' cbi-button-positive' : ''),
					'click': function() {
						activeTab = t.id;
						TABS.forEach(function(t2) { panels[t2.id].style.display = t2.id === activeTab ? '' : 'none'; });
						renderTabBar();
						if (tabHooks[t.id]) tabHooks[t.id]();
					}
				}, t.label));
			});
		}

		(function buildStrategyPanel() {
			var status = statusData, vList = vListData;
			var lastFlowseal = null;
			var logEl = E('pre', { 'class': 'zm-log' });
			var busy = false;

			var zBusy = false;
			var zLogEl = E('pre', { 'class': 'zm-log' });
			var zBannerEl = E('div', {});
			var zCardWrap = E('div', {});

			function renderZCard(d) {
				zCardWrap.innerHTML = '';
				var zActions = [];
				if (d.zapret === 'installed') {
					zActions.push(E('button', {
						'class': 'cbi-button cbi-button-remove',
						'click': function() {
							zm.dialog({ title: 'Удалить Zapret?', danger: true, okText: 'Удалить Zapret',
								blocks: [ { type: 'list', title: 'Что произойдёт', items: [
									'Zapret остановится, его правила файрвола снимутся',
									'Пакеты, стратегии и списки удалятся',
									'Задания Zapret уберутся из расписания'
								] }, { type: 'note', kind: 'warn', text: 'Сайты, которые открывались благодаря Zapret, перестанут открываться.' } ]
							}).then(function(v) { if (v) doZapretAction('remove'); });
						}
					}, 'Удалить'));
					if (/^[0-9]+\.[0-9]+$/.test(latestVersion) && d.zapret_version && latestVersion !== d.zapret_version) {
						zActions.push(E('button', {
							'class': 'cbi-button',
							'click': function() { doZapretAction('update'); }
						}, 'Обновить до ' + latestVersion));
					}
					zActions.push(E('button', {
						'class': 'cbi-button',
						'click': function() { doZapretAction(d.zapret_running ? 'stop' : 'start'); }
					}, d.zapret_running ? 'Остановить' : 'Запустить'));
					if (d.zapret_running) zActions.push(E('button', {
						'class': 'cbi-button',
						'click': function() { doZapretAction('restart'); }
					}, 'Перезапустить'));
				} else {
					zActions.push(E('button', {
						'class': 'cbi-button cbi-button-positive',
						'disabled': (d.zapret2 === 'installed' && !d.expert) ? '' : null,
						'click': function() { doZapretAction('install'); }
					}, 'Установить и настроить'));
				}
				var zBlock = d.zapret !== 'installed' && d.zapret2 === 'installed' && !d.expert;

				var fields = [
					E('span', { 'style': 'display:inline-flex; align-items:center; gap:8px' }, [ E('span', { 'class': 'zm-label' }, 'Статус'),
						d.zapret === 'installed'
							? zm.badge(d.zapret_running === true, 'запущен', 'остановлен')
							: zm.badge(false, '', 'не установлен')
					])
				];
				if (d.zapret_version) fields.push(E('span', { 'style': 'display:inline-flex; align-items:center; gap:8px' }, [ E('span', { 'class': 'zm-label' }, 'Версия'), E('span', {}, [ String(d.zapret_version) ]) ]));
				if (d.strategy) fields.push(E('span', { 'style': 'display:inline-flex; align-items:center; gap:8px' }, [ E('span', { 'class': 'zm-label' }, 'Стратегия'), E('span', {}, [ String(d.strategy) ]) ]));

				if (zBlock) {
					zCardWrap.appendChild(zm.blockCard(E('div', { 'class': 'zm-card', 'style': 'margin-bottom:10px' }), 'Zapret', 'Обход DPI-блокировок: стратегии, YouTube, Discord, игры и списки.', 'Стоит Zapret2 — он несовместим с Zapret. Чтобы поставить Zapret, удалите Zapret2.'));
					return;
				}
				zCardWrap.appendChild(E('div', { 'class': 'zm-card', 'style': 'margin-bottom:10px' }, [
					E('h3', {}, 'Zapret'),
					E('div', { 'class': 'zm-row', 'style': 'justify-content:space-between; width:100%' }, [
						E('div', { 'style': 'display:flex; gap:22px; flex-wrap:wrap; align-items:center' }, fields),
						E('div', { 'class': 'zm-actions', 'style': 'margin:0' }, zActions)
					])
				]));
			}

			function doZapretAction(action) {
				if (zBusy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
				var job = (action === 'install' || action === 'update') ? 'install_zapret'
					: (action === 'remove') ? 'remove_zapret' : null;
				var LABELS = { install: 'Устанавливаем и настраиваем Zapret', update: 'Обновляем Zapret', remove: 'Удаляем Zapret', start: 'Запускаем Zapret', stop: 'Останавливаем Zapret', restart: 'Перезапускаем Zapret' };
				zm.toast(LABELS[action] || 'Выполняем', 'warning');
				if (job) zBusy = true;

				zm.zapretAction(action).then(function(res) {
					if (res && res.error) { zBusy = false; zm.toast(res.error, 'error'); return; }
					if (job && res && res.started) {
						zm.pollJob(job, zLogEl, function(ok) {
							zBusy = false;
							zm.toast(ok ? 'Готово' : 'Операция завершилась с ошибкой', ok ? 'info' : 'error');
							zm.status().then(function(d) { status = d; renderZCard(d); renderBanner(); renderV(); refreshAll(); });
							if (ok && (action === 'install' || action === 'remove')) {
								zBannerEl.innerHTML = '';
								zBannerEl.appendChild(action === 'install'
									? zm.refreshBanner('В меню LuCI добавлен пункт Zapret — выйдите и зайдите заново, чтобы он открывался.')
									: zm.refreshBanner('Пункт Zapret убран из меню LuCI — обновите страницу.', false));
							}
						});
					} else if (res) {
						zBusy = false;
						if (action === 'restart') zm.toast(res.zapret_running ? 'Zapret перезапущен' : 'Zapret не запустился — проверьте стратегию', res.zapret_running ? 'info' : 'error');
						status = res;
						renderZCard(res);
						renderBanner();
						renderV();
					}
				}).catch(function() { zBusy = false; });
			}

			renderZCard(status);
			mainSection.appendChild(zCardWrap);
			mainSection.appendChild(zLogEl);
			mainSection.appendChild(zBannerEl);

			var currentBanner = E('div', { 'class': 'zm-current-banner zm-current-top' });
			panels.strategy.appendChild(currentBanner);

			var vGrid = E('div', { 'class': 'zm-grid zm-vgrid' });
			var vCard = E('div', { 'class': 'zm-card zm-vcard' }, [
				E('h3', {}, 'Стратегии v1 – v10'),
				vGrid
			]);

			var fGrid = E('div', { 'class': 'zm-grid' }), fBusy = false;
			var fBtn = E('button', { 'class': 'cbi-button', 'click': function() { fLoad(); } }, 'Загрузить список');
			var fCard = E('div', { 'class': 'zm-card' }, [
				E('h3', {}, 'Стратегии Flowseal'),
				E('p', { 'class': 'zm-hint' }, 'Стратегия Flowseal полностью заменяет текущую. В ней уже есть основной блок, игровой, блоки для YouTube и Discord.'),
				E('div', { 'class': 'zm-actions' }, [ fBtn ]),
				fGrid
			]);
			function fBtnPaint() {
				fBtn.disabled = fBusy;
				fBtn.textContent = fBusy ? 'Загружаем…' : (lastFlowseal && lastFlowseal.items && lastFlowseal.items.length ? 'Обновить список' : 'Загрузить список');
			}
			function fFollow() {
				fBusy = true; fBtnPaint();
				if (!lastFlowseal || !lastFlowseal.items || !lastFlowseal.items.length) {
					fGrid.innerHTML = '';
					fGrid.appendChild(E('p', { 'class': 'zm-hint' }, 'Скачиваем список с GitHub… Пока он грузится, можно выбирать другие стратегии.'));
				}
				zm.pollJob('flowseal_download', logEl, function(ok) {
					zm.toast(ok ? 'Список Flowseal загружен' : 'Список Flowseal не загрузился — похоже, GitHub сейчас недоступен', ok ? 'info' : 'error');
					zm.strategyListFlowseal('cached').then(function(r) { fBusy = false; renderFlowseal(r || {}); }, function() { fBusy = false; renderFlowseal(lastFlowseal || {}); });
				});
			}
			function fLoad() {
				if (fBusy) return;
				fBusy = true; fBtnPaint();
				zm.toast('Загружаем список Flowseal', 'warning');
				zm.strategyListFlowseal('refresh').then(function(res) {
					if (res && res.started) { fFollow(); return; }
					fBusy = false;
					if (res && res.error) { zm.toast(res.error, 'error'); renderFlowseal(lastFlowseal || {}); return; }
					renderFlowseal(res || {});
				}).catch(function() { fBusy = false; renderFlowseal(lastFlowseal || {}); zm.toast('Роутер не ответил', 'error'); });
			}

			function renderBanner() {
				currentBanner.className = 'zm-current-banner zm-current-top' + (status.strategy ? '' : ' zm-current-empty');
				currentBanner.innerHTML = '';
				if (status.strategy) {
					currentBanner.appendChild(E('span', {}, 'Сейчас применено: '));
					currentBanner.appendChild(E('b', {}, [ String(status.strategy) ]));
					if (status.testing) currentBanner.appendChild(E('span', { 'class': 'zm-badge zm-warn', 'style': 'margin-left:10px', 'title': 'Пока идёт тест, роутер по очереди пробует стратегии. Потом вернётся ваша' }, [ E('span', { 'class': 'zm-dot' }), 'идёт тест' + (status.test_now ? ': сейчас ' + status.test_now : '') ]));
					if (status.rkn_on) currentBanner.appendChild(E('span', { 'class': 'zm-badge zm-ok', 'style': 'margin-left:10px', 'title': 'Стратегия работает только для сайтов из списка РКН и вашего списка' }, [ E('span', { 'class': 'zm-dot' }), 'по спискам РКН' ]));
					else if (status.rkn) currentBanner.appendChild(E('span', { 'class': 'zm-badge zm-warn', 'style': 'margin-left:10px', 'title': 'Списки РКН включены, но с этой стратегией не работают — выберите другую' }, [ E('span', { 'class': 'zm-dot' }), 'списки РКН ждут другую стратегию' ]));
					else if (status.ulist_on) currentBanner.appendChild(E('span', { 'class': 'zm-badge zm-ok', 'style': 'margin-left:10px', 'title': 'Стратегия работает только для сайтов из вашего списка хостов' }, [ E('span', { 'class': 'zm-dot' }), 'по вашему списку' ]));
					else if (status.ulist) currentBanner.appendChild(E('span', { 'class': 'zm-badge zm-warn', 'style': 'margin-left:10px', 'title': 'Обход по своему списку включён, но с этой стратегией не работает — выберите другую' }, [ E('span', { 'class': 'zm-dot' }), 'свой список ждёт другую стратегию' ]));
				} else {
					currentBanner.appendChild(E('span', {}, 'Стратегия ещё не выбрана'));
				}
			}

			function renderV() {
				vGrid.innerHTML = '';
				(vList.items || []).forEach(function(it) {
					var words = (' ' + (status.strategy || '') + ' ');
					vGrid.appendChild(E('div', {
						'class': 'zm-tile' + (!status.flowseal && words.indexOf(' ' + it.id + ' ') !== -1 ? ' zm-active' : ''),
						'click': function() {
							if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
							tsGate('v:' + it.id, function() {
							busy = true;
							zm.toast('Применяем стратегию ' + it.id + '', 'warning');
							zm.strategySetV(it.id).then(function(res) {
								busy = false;
								if (!zm.notifyStrategyResult(res, it.id)) return;
								refreshAll();
							}).catch(function() { busy = false; });
							});
						}
					}, [ String(it.id) ]));
				});
			}

			function renderFlowseal(res) {
				lastFlowseal = res;
				fGrid.innerHTML = '';
				(res.items || []).forEach(function(it) {
					fGrid.appendChild(E('div', {
						'class': 'zm-tile' + (status.flowseal === it.id ? ' zm-active' : ''),
						'click': function() {
							if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
							tsGate('flowseal:' + it.id, function() {
							busy = true;
							zm.toast('Применяем стратегию ' + it.label + '', 'warning');
							zm.strategySetFlowseal(it.id).then(function(r2) {
								busy = false;
								if (!zm.notifyStrategyResult(r2, it.id)) return;
								refreshAll();
							}).catch(function() { busy = false; });
							});
						}
					}, [ String(it.label) ]));
				});
				if (!res.items || !res.items.length)
					fGrid.appendChild(E('p', { 'class': 'zm-hint' }, fBusy ? 'Скачиваем список с GitHub… Пока он грузится, можно выбирать другие стратегии.'
						: 'Список Flowseal ещё не загружен. Нажмите «Загрузить список» — он скачается с GitHub. Остальные стратегии можно выбирать и без него.'));
				fBtnPaint();
			}

			var extraCard = E('div', { 'class': 'zm-card' }), extraBusy = '';
			function renderExtra() {
				extraCard.innerHTML = '';
				extraCard.appendChild(E('h3', {}, 'Дополнения к стратегии'));
				if (status.zapret !== 'installed') { extraCard.appendChild(E('p', { 'class': 'zm-hint' }, 'Станут доступны после установки Zapret.')); return; }
				var dohDoms = String(status.zdoh_doms || '').split(',').filter(Boolean).join(', ');
				var dohHint = status.zdoh && !status.zdoh_on
					? '⚠ Стратегия помечена «Не изменять» — блок не добавлен. Снимите пометку в «Редактировать текущую стратегию».'
					: 'Пробивает блокировку шифрованного DNS: блок встаёт первым в стратегии. ' + (status.zdoh_own
						? 'Домены берутся из DoH роутера и меняются вместе с ним: ' + dohDoms + '.'
						: 'DoH на роутере не настроен — взяты популярные серверы: ' + dohDoms + '.');
				extraCard.appendChild(zm.swRow(!!(status.zdoh || status.zdoh_on), extraBusy === 'doh' ? 'Обход блокировки DoH — применяем…' : 'Обход блокировки DoH', dohHint, function() { toggleExtra('doh', !(status.zdoh || status.zdoh_on)); }, !!extraBusy));
				var rknHint = status.rkn && !status.rkn_on
					? '⚠ Текущая стратегия не подходит для списков РКН. Они включатся сами, когда вы выберете подходящую.'
					: 'Основная стратегия будет обходить блокировку только для сайтов из списка РКН' + (status.rkn_on && status.rkn_count > 0 ? ' (' + status.rkn_count + ' доменов)' : '') + ' и вашего списка хостов, а не для всех сайтов, кроме исключений. Помогает, если стратегия мешает обычным сайтам. Список скачивается из проекта zapret4rocket и сохраняется при смене стратегии.';
				extraCard.appendChild(zm.swRow(!!status.rkn, extraBusy === 'rkn' ? 'Обход по спискам РКН — применяем…' : 'Обход по спискам РКН', rknHint, function() { toggleExtra('rkn', !status.rkn); }, !!extraBusy));
				var ulN = +status.ulist_count || 0;
				var ulHint = status.ulist && !status.ulist_on
					? '⚠ Текущая стратегия не подходит для обхода по своему списку. Он включится сам, когда вы выберете подходящую.'
					: 'Основная стратегия будет обходить блокировку только для сайтов из вашего списка /opt/zapret/ipset/zapret-hosts-user.txt' + (status.ulist_on ? ' (' + (ulN ? ulN + ' ' + (ulN % 10 === 1 && ulN % 100 !== 11 ? 'домен' : ulN % 10 >= 2 && ulN % 10 <= 4 && (ulN % 100 < 12 || ulN % 100 > 14) ? 'домена' : 'доменов') : 'список пуст') + ')' : '') + ', а не для всех сайтов, кроме исключений. Список правится на вкладке «Редактор списков». Включается что-то одно: со списками РКН ваш список уже учитывается.';
				extraCard.appendChild(zm.swRow(!!status.ulist, extraBusy === 'userlist' ? 'Обход по пользовательским спискам — применяем…' : 'Обход по пользовательским спискам', ulHint, function() { toggleExtra('userlist', !status.ulist); }, !!extraBusy));
				if (status.ulist_on && !ulN) extraCard.appendChild(E('p', { 'class': 'zm-hint zm-ab-warn', 'style': 'margin:-4px 0 10px 52px' }, 'Список пуст — основная стратегия сейчас не применяется ни к одному сайту. Добавьте домены на вкладке «Редактор списков».'));
				extraCard.appendChild(zm.swRow(!!status.wssize, extraBusy === 'wssize' ? 'Блок --wssize 1:6 — применяем…' : 'Блок --wssize 1:6', 'Отдельный блок в конце стратегии: для HTTPS уменьшает окно TCP в начале соединения. Помогает с некоторыми блокировками, но может снизить скорость и стабильность. Сохраняется при смене стратегии.', function() { toggleExtra('wssize', !status.wssize); }, !!extraBusy));
			}
			function toggleExtra(what, on) {
				if (busy || extraBusy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
				extraBusy = what; renderExtra();
				zm.toast(what === 'doh' ? (on ? 'Добавляем блок обхода DoH и перезапускаем Zapret' : 'Убираем блок обхода DoH') : what === 'rkn' ? (on ? 'Скачиваем список РКН и перезапускаем Zapret' : 'Выключаем списки РКН') : what === 'userlist' ? (on ? 'Переводим стратегию на ваш список и перезапускаем Zapret' : 'Возвращаем обход для всех сайтов, кроме исключений') : (on ? 'Добавляем блок --wssize' : 'Убираем блок --wssize'), 'warning');
				zm.zapretOptSet(what + ':' + (on ? 'on' : 'off')).then(function(res) {
					extraBusy = '';
					if (!res || res.error) { zm.toast((res && res.error) || 'Роутер не ответил', 'error'); renderExtra(); return; }
					status = res;
					if (!zBusy) renderZCard(res);
					renderExtra(); renderBanner(); renderV();
					if (lastFlowseal) renderFlowseal(lastFlowseal);
					zm.toast(what === 'doh' ? (on ? 'Обход блокировки DoH включён' : 'Обход блокировки DoH выключен') : what === 'rkn' ? (on ? (res.rkn_on ? 'Списки РКН включены' : 'Списки РКН включатся с подходящей стратегией') : 'Списки РКН выключены')
						: what === 'userlist' ? (on ? 'Стратегия работает только по вашему списку' : 'Стратегия снова работает для всех сайтов, кроме исключений')
						: (on ? 'Блок --wssize добавлен' : 'Блок --wssize убран'), 'info');
					refreshAll();
				}).catch(function() { extraBusy = ''; zm.toast('Роутер не ответил', 'error'); renderExtra(); });
			}

			function refreshState() {
				zm.status().then(function(s) {
					status = s;
					if (!zBusy) renderZCard(s);
					renderBanner();
					renderV();
					if (!extraBusy) renderExtra();
					if (lastFlowseal) renderFlowseal(lastFlowseal);
				});
			}

			tabHooks.strategy = refreshState;
			refreshers.strategy = refreshState;
			renderBanner();
			renderV();
			renderExtra();

			panels.strategy.appendChild(vCard);
			panels.strategy.appendChild(fCard);
			panels.strategy.appendChild(extraCard);
			panels.strategy.appendChild(logEl);

			renderFlowseal({});
			zm.strategyListFlowseal('cached').then(function(res) {
				renderFlowseal(res || {});
				if (res && res.running) fFollow();
			}, function() { renderFlowseal({}); });

			var nfqwsCard = E('div', { 'class': 'zm-card' });
			var nfqwsOpen = false;
			var nfqwsEl = E('textarea', { 'class': 'zm-config-editor', 'spellcheck': 'false', 'style': 'display:none' });
			var nfqwsBar = zm.editorBar(nfqwsEl, {
				onSave: function(v) {
					return tsCheck('text:' + v).then(function(parts) {
						return parts ? zm.warnOnce('warn_ts', function() { return zm.tsWarn({ parts: parts, okText: 'Сохранить стратегию' }); }) : true;
					}).then(function(ok) {
					if (!ok) return false;
					zm.toast('Сохраняем стратегию и перезапускаем Zapret', 'warning');
					return zm.nfqwsOptSet(v).then(function(res) {
						if (res.error) { zm.toast(res.error, 'error'); return false; }
						nfqNo = /#\s*nochange/i.test(v); renderNfqNo();
						zm.toast('Сохранено, Zapret перезапущен', 'info');
						refreshAll();
						return true;
					}).catch(function() { zm.toast('Роутер не ответил', 'error'); return false; });
					});
				}
			});

			var nfqNo = false, nfqNoBusy = false, nfqNoBox = E('div', { 'class': 'zm-list-nc' });
			function renderNfqNo() {
				nfqNoBox.innerHTML = '';
				nfqNoBox.appendChild(zm.swRow(nfqNo, 'Не изменять стратегию', 'Панель не будет менять стратегию: выбор стратегий, YouTube, Discord, игры, тест и переустановка её не тронут. В блок NFQWS_OPT добавляется строка #nochange.', function() {
					if (nfqNoBusy) return;
					if (nfqwsOpen && nfqwsBar.dirty()) { zm.toast('Сначала сохраните или отмените изменения в стратегии', 'warning'); return; }
					nfqNoBusy = true; renderNfqNo();
					var was = nfqNo;
					zm.zapretListRestore('nochange=strategy:' + (was ? 'off' : 'on')).then(function(r) {
						nfqNoBusy = false;
						if (r && typeof r.nochange === 'boolean') nfqNo = r.nochange;
						if (!r || r.error) { zm.toast((r && r.error) || 'Роутер не ответил', 'error'); renderNfqNo(); return; }
						zm.toast(was ? 'Панель снова может менять стратегию' : 'Стратегия защищена: панель её не изменит', 'info');
						renderNfqNo();
						if (nfqwsOpen) refreshNfqwsOpt();
					}).catch(function() { nfqNoBusy = false; zm.toast('Роутер не ответил', 'error'); renderNfqNo(); });
				}, nfqNoBusy));
			}
			function refreshNfqwsOpt() {
				return zm.nfqwsOptGet().then(function(res) {
					if (res.error) { if (nfqwsOpen) zm.toast(res.error, 'error'); return; }
					nfqNo = /#\s*nochange/i.test(res.content || '');
					renderNfqNo();
					if (nfqwsOpen) nfqwsBar.reset(res.content || '');
				});
			}

			function renderNfqwsCard() {
				nfqwsCard.innerHTML = '';
				nfqwsCard.appendChild(E('h3', {}, 'Редактировать текущую стратегию'));
				if (!nfqwsOpen) {
					nfqwsCard.appendChild(E('p', { 'class': 'zm-hint' }, 'Ручная правка блока NFQWS_OPT — для опытных пользователей.'));
					nfqwsCard.appendChild(E('div', { 'class': 'zm-actions' }, [
						E('button', {
							'class': 'cbi-button',
							'click': function() {
								nfqwsOpen = true;
								refreshNfqwsOpt();
								renderNfqwsCard();
							}
						}, 'Открыть редактор стратегии')
					]));
					nfqwsCard.appendChild(nfqNoBox);
					return;
				}
				nfqwsCard.appendChild(E('p', { 'class': 'zm-hint' }, 'Блок NFQWS_OPT из /etc/config/zapret. «Сохранить и применить» перезапустит Zapret. Чтобы панель не меняла эту стратегию (смена стратегий, YouTube, Discord, игры, тест, переустановка), включите «Не изменять стратегию».'));
				nfqwsCard.appendChild(E('p', { 'class': 'zm-hint' }, 'Свою стратегию поверх выбранной впишите между строками #CustomStart и #CustomEnd — при смене стратегии, YouTube, Discord, игр и QUIC панель её сохранит и поставит в самый верх, как консольный Zapret Manager.'));
				nfqwsEl.style.display = '';
				nfqwsCard.appendChild(nfqwsEl);
				nfqwsCard.appendChild(E('div', { 'class': 'zm-actions' }, [
					E('button', {
						'class': 'cbi-button',
						'click': function() {
							var zmGo = function() { refreshNfqwsOpt(); zm.toast('Содержимое перечитано с диска', 'info'); };
							if (nfqwsBar.dirty()) return zm.ask('Отменить несохранённые изменения и перечитать файл?').then(function(ok) { return ok ? zmGo() : undefined; });
							return zmGo();
						}
					}, 'Перечитать файл'),
					E('button', {
						'class': 'cbi-button',
						'click': function() {
							var zmGo = function() { nfqwsOpen = false; nfqwsBar.reset(); renderNfqwsCard(); };
							if (nfqwsBar.dirty()) return zm.ask('Есть несохранённые изменения. Свернуть без сохранения?').then(function(ok) { return ok ? zmGo() : undefined; });
							return zmGo();
						}
					}, 'Свернуть')
				]));
				nfqwsCard.appendChild(nfqNoBox);
				nfqwsCard.appendChild(nfqwsBar);
			}
			renderNfqNo();
			renderNfqwsCard();
			if (zapretInstalled) refreshNfqwsOpt().catch(function() {});
			refreshers.nfqNo = function() { if (!nfqwsOpen || !nfqwsBar.dirty()) refreshNfqwsOpt().catch(function() {}); };
			panels.strategy.appendChild(nfqwsCard);
		})();

		(function buildTestPanel() {
			var logEl = E('pre', { 'class': 'zm-log' });
			var busy = testData.running === true;
			var curMode = testData.mode || '';
			var status = testData;
			var launchCard = E('div', { 'class': 'zm-card' });
			var resCard = E('div', { 'class': 'zm-card' });
			var resMode = null, resData = {}, openRows = {}, mainPick = /^(v|flowseal|v_flowseal)$/.test(testData.mode || '') ? testData.mode : 'v_flowseal';
			var domInput = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'placeholder': 'x.com discord.com rutracker.org', 'style': 'flex:1 1 220px; min-width:0' });
			domInput.value = testData.domains || '';
			domInput.addEventListener('keydown', function(ev) { if (ev.key === 'Enter') startDomain(); });

			var TILES = [
				{ id: 'current', title: 'Текущая стратегия', sub: 'Проверяет, что стоит сейчас, ничего не меняя: заблокированные сайты и YouTube.', buttons: [ { mode: 'current', label: 'Проверить' } ] },
				{ id: 'domain', title: 'По домену', sub: 'Все стратегии v и Flowseal на ваших сайтах. Через пробел, до 30 штук.', domain: true },
				{ id: 'main', title: 'Стратегии v и Flowseal', sub: 'Выберите, что перебирать, и нажмите «Проверить». Проверка идёт по списку заблокированных сайтов.', choice: [ { id: 'v', label: 'v1–v10' }, { id: 'flowseal', label: 'Flowseal' }, { id: 'v_flowseal', label: 'v + Flowseal' } ] },
				{ id: 'youtube', title: 'YouTube', sub: 'Перебирает стратегии Yv на адресах YouTube.', buttons: [ { mode: 'youtube', label: 'Проверить' } ] },
				{ id: 'custom', title: 'Свои стратегии', sub: 'Ваш список стратегий: на заблокированных сайтах, на YouTube или на ваших сайтах. Список хранится в /root/custom_test.txt — так же, как в консольном Zapret Manager.', custom: true }
			];
			var customPick = /^custom(_yt|_dom)?$/.test(testData.mode || '') ? testData.mode : 'custom', customOpen = false, customText = testData.custom || '';
			var cdomInput = E('input', { 'type': 'text', 'class': 'cbi-input-text', 'placeholder': 'Ваши сайты через пробел: x.com discord.com', 'style': 'flex:1 1 100%; min-width:0' });
			cdomInput.value = testData.custom_domains || '';
			cdomInput.addEventListener('keydown', function(ev) { if (ev.key === 'Enter') startCustomDom(); });
			var customEl = E('textarea', { 'class': 'zm-config-editor', 'spellcheck': 'false', 'wrap': 'off', 'placeholder': '#Моя1\n--filter-tcp=443\n--dpi-desync=fake\n#Моя2\n--filter-tcp=443\n--dpi-desync=multidisorder' });
			customEl.value = customText;
			var customBar = zm.editorBar(customEl, {
				onSave: function(v) {
					return zm.testAction('custom_set', v).then(function(r) {
						if (!r || r.error) { zm.toast((r && r.error) || 'Роутер не ответил', 'error'); return false; }
						customText = v.trim() ? v : '';
						zm.toast(r.count ? 'Список сохранён: ' + r.count + ' ' + (r.count % 10 === 1 && r.count % 100 !== 11 ? 'стратегия' : r.count % 10 >= 2 && r.count % 10 <= 4 && (r.count % 100 < 12 || r.count % 100 > 14) ? 'стратегии' : 'стратегий') : 'Список очищен', 'info');
						renderLaunch();
						return true;
					}).catch(function() { zm.toast('Роутер не ответил', 'error'); return false; });
				}
			});
			var customCard = E('div', { 'class': 'zm-card', 'style': 'display:none' });
			function customCount() { return (customText.match(/^#/mg) || []).length; }
			function renderCustomCard() {
				customCard.style.display = customOpen ? '' : 'none';
				customCard.innerHTML = '';
				if (!customOpen) return;
				customCard.appendChild(E('h3', {}, 'Свои стратегии для теста'));
				customCard.appendChild(E('p', { 'class': 'zm-hint' }, 'Каждая стратегия начинается со строки #Название, дальше её параметры nfqws — по одному в строке, с --. Одинарные кавычки нельзя.'));
				customCard.appendChild(customEl);
				customCard.appendChild(E('div', { 'class': 'zm-actions' }, [
					E('button', { 'class': 'cbi-button', 'click': function() {
						var zmGo = function() { customOpen = false; customBar.reset(customText); renderCustomCard(); renderLaunch(); };
						if (customBar.dirty()) return zm.ask('Есть несохранённые изменения. Свернуть без сохранения?').then(function(ok) { return ok ? zmGo() : undefined; });
						return zmGo();
					} }, 'Свернуть')
				]));
				customCard.appendChild(customBar);
			}

			function renderLaunch() {
				launchCard.innerHTML = '';
				launchCard.appendChild(E('h3', {}, 'Тест стратегий'));
				launchCard.appendChild(E('p', { 'class': 'zm-hint', 'style': 'margin-top:-6px' }, 'Тест идёт в фоне — можно уйти со страницы. После теста настройки Zapret возвращаются как были.'));
				if (busy) {
					launchCard.appendChild(E('div', { 'class': 'zm-refresh-banner zm-show zm-tt-run' }, [
						E('span', {}, [ 'Идёт тест: ' + (TEST_MODE_LABELS[curMode] || curMode || '…') + '…' ]),
						E('button', { 'class': 'cbi-button cbi-button-remove', 'click': doStop }, 'Остановить')
					]));
				}
				launchCard.appendChild(E('div', { 'class': 'zm-tt-grid' }, TILES.map(function(t) {
					var ctl;
					if (t.custom) {
						var cn = customCount();
						ctl = E('div', { 'class': 'zm-tt-ctl' }, [
							E('div', { 'class': 'zm-seg' }, [ { id: 'custom', label: 'Заблокированные' }, { id: 'custom_yt', label: 'YouTube' }, { id: 'custom_dom', label: 'Ваши сайты' } ].map(function(c) {
								return E('div', { 'class': 'zm-seg-item' + (c.id === customPick ? ' zm-active' : ''), 'click': function() { if (!busy && c.id !== customPick) { customPick = c.id; renderLaunch(); if (c.id === 'custom_dom' && !cdomInput.value) cdomInput.focus(); } } }, c.label);
							})),
							customPick === 'custom_dom' ? cdomInput : E([]),
							customPick === 'custom_dom' ? E('p', { 'class': 'zm-hint', 'style': 'flex:1 1 100%; margin:0' }, 'До 30 сайтов. Если стратегия работает по списку сайтов (--hostlist), на время теста ваши сайты добавляются в этот список.') : E([]),
							E('button', { 'class': 'cbi-button', 'click': function() { customOpen = !customOpen; if (customOpen) customBar.reset(customText); renderCustomCard(); renderLaunch(); } }, customOpen ? 'Скрыть список' : (cn ? 'Список · ' + cn : 'Добавить стратегии')),
							E('button', { 'class': 'cbi-button cbi-button-positive', 'disabled': busy || !cn ? '' : null, 'click': function() { if (customPick === 'custom_dom') startCustomDom(); else doStart(customPick); } }, 'Проверить')
						]);
						cdomInput.disabled = busy;
					} else if (t.domain) {
						ctl = E('div', { 'class': 'zm-tt-ctl' }, [ domInput, E('button', { 'class': 'cbi-button cbi-button-positive', 'disabled': busy ? '' : null, 'click': startDomain }, 'Проверить') ]);
						domInput.disabled = busy;
					} else if (t.choice) {
						ctl = E('div', { 'class': 'zm-tt-ctl' }, [
							E('div', { 'class': 'zm-seg' }, t.choice.map(function(c) {
								return E('div', { 'class': 'zm-seg-item' + (c.id === mainPick ? ' zm-active' : ''), 'click': function() { if (!busy && c.id !== mainPick) { mainPick = c.id; renderLaunch(); } } }, c.label);
							})),
							E('button', { 'class': 'cbi-button cbi-button-positive', 'disabled': busy ? '' : null, 'click': function() { doStart(mainPick); } }, 'Проверить')
						]);
					} else {
						ctl = E('div', { 'class': 'zm-tt-ctl' }, t.buttons.map(function(b, i) {
							return E('button', { 'class': 'cbi-button' + (i === t.buttons.length - 1 ? ' cbi-button-positive' : ''), 'disabled': busy ? '' : null, 'click': function() { doStart(b.mode); } }, b.label);
						}));
					}
					var run = busy && (curMode === t.id || (t.id === 'main' && /^(v|flowseal|v_flowseal)$/.test(curMode)) || (t.id === 'custom' && /^custom_(yt|dom)$/.test(curMode)));
					var had = t.id === 'main' ? (status.has_results_v || status.has_results_flowseal || status.has_results_v_flowseal) : t.id === 'custom' ? (status.has_results_custom || status.has_results_custom_yt || status.has_results_custom_dom) : status['has_results_' + t.id];
					return E('div', { 'class': 'zm-tt-tile' + (run ? ' zm-tt-active' : '') + (t.custom ? ' zm-tt-wide' : '') }, [
						E('div', { 'class': 'zm-tt-head' }, [ E('b', {}, t.title), run ? zm.badge(true, 'идёт', '') : (had ? E('span', { 'class': 'zm-hint', 'style': 'margin:0' }, 'есть результат') : E([])) ]),
						E('p', { 'class': 'zm-hint' }, t.sub),
						ctl
					]);
				})));
			}

			var autoCard = E('div', { 'class': 'zm-card' }), autoInfo = testData.auto || {}, autoBusy = false, timeInfo = testData, autoOwn = false;
			zm.warnSeen('warn_ts').then(function(seen) {
				if (seen) return;
				return tsCheck('current').then(function(parts) {
					if (!parts || !parts.length) return;
					var auto = autoInfo.ts_at > 0;
					return zm.tsWarn({ info: true, parts: parts,
						title: auto ? 'Автоподбор поставил стратегию с меткой ts' : 'В вашей стратегии есть метка ts',
						lead: auto ? 'Ночью автоподбор нашёл стратегию, которая открывает больше сайтов, и применил её.' : '' }).then(function() { zm.uiFlagSet('warn_ts'); });
				});
			});
			var AUTO_TIMES = [ '01:00', '02:00', '03:00', '04:00', '05:00', '06:00' ];
			function p2(n) { return (n < 10 ? '0' : '') + n; }
			function routerNow() {
				if (!timeInfo.time) return null;
				var off = String(timeInfo.utc_offset || '+0000'), sg = off.charAt(0) === '-' ? -1 : 1;
				return new Date((timeInfo.time + sg * ((+off.slice(1, 3)) * 3600 + (+off.slice(3, 5)) * 60)) * 1000);
			}
			function whenText(ts) {
				var now = routerNow(), off = String(timeInfo.utc_offset || '+0000'), sg = off.charAt(0) === '-' ? -1 : 1;
				var d = new Date((ts + sg * ((+off.slice(1, 3)) * 3600 + (+off.slice(3, 5)) * 60)) * 1000);
				var hm = p2(d.getUTCHours()) + ':' + p2(d.getUTCMinutes());
				if (now) {
					var days = Math.round((Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()) - Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate())) / 86400000);
					if (days === 0) return 'сегодня в ' + hm;
					if (days === 1) return 'вчера в ' + hm;
				}
				return p2(d.getUTCDate()) + '.' + p2(d.getUTCMonth() + 1) + '.' + d.getUTCFullYear() + ' в ' + hm;
			}
			function nextText(t) {
				var now = routerNow();
				if (!now || !/^\d\d:\d\d$/.test(t)) return t;
				var mins = (+t.slice(0, 2)) * 60 + (+t.slice(3, 5)), cur = now.getUTCHours() * 60 + now.getUTCMinutes();
				return (mins > cur ? 'сегодня в ' : 'завтра в ') + t;
			}
			function autoSet(when, mode, okText, yt) {
				if (autoBusy) return;
				autoBusy = true; renderAuto();
				zm.testAction('auto_set', when + '|' + mode + (yt ? '|' + yt : '')).then(function(r) {
					autoBusy = false;
					if (!r || r.error) { zm.toast((r && r.error) || 'Роутер не ответил', 'error'); renderAuto(); return; }
					autoInfo = r.auto || {}; timeInfo = r;
					zm.toast(okText || (autoInfo.time ? 'Автоподбор: каждый день в ' + autoInfo.time : 'Автоподбор выключен'), 'info');
					renderAuto();
				}).catch(function() { autoBusy = false; zm.toast('Роутер не ответил', 'error'); renderAuto(); });
			}
			function renderAuto() {
				var on = !!autoInfo.time, mode = autoInfo.mode || 'v_flowseal', t = autoInfo.time || autoInfo.pref || '04:00', yt = !!autoInfo.yt;
				var preset = AUTO_TIMES.indexOf(t) >= 0 && !autoOwn;
				autoCard.innerHTML = '';
				autoCard.appendChild(E('h3', {}, [ 'Автоподбор стратегии ', on ? zm.badge(true, 'ежедневно в ' + autoInfo.time, '') : E([]) ]));
				autoCard.appendChild(E('p', { 'class': 'zm-hint', 'style': 'margin-top:-6px' }, 'Роутер проверяет стратегии на списке заблокированных сайтов и сравнивает лучшую с текущей. Новая стратегия применяется, только если открывает заметно больше сайтов — минимум на 2 или на 5%, чтобы случайный сбой не менял стратегию. Настройки Discord, игр, QUIC и дополнения к стратегии сохраняются, YouTube — тоже, если не включён подбор для него.'));
				autoCard.appendChild(zm.swRow(on, 'Запускать ежедневно', on ? 'Следующий запуск: ' + nextText(autoInfo.time) + '. Проверка длится 5–10 минут, Zapret в это время перезапускается.' : 'Выключено — стратегия меняется только вручную.', function() {
					if (autoBusy) return;
					autoSet(on ? 'off' : t, mode);
				}, autoBusy));
				if (on) {
					var ctl = [ E('div', { 'class': 'zm-seg' + (autoBusy ? ' zm-seg-busy' : '') }, AUTO_TIMES.map(function(x) {
						return E('div', { 'class': 'zm-seg-item' + (preset && x === t ? ' zm-active' : ''), 'click': function() { if (autoBusy || (preset && x === t)) return; autoOwn = false; autoSet(x, mode); } }, x);
					}).concat([ E('div', { 'class': 'zm-seg-item' + (!preset ? ' zm-active' : ''), 'click': function() { if (!autoOwn && preset) { autoOwn = true; renderAuto(); } } }, 'Другое') ])) ];
					if (!preset) {
						var inp = E('input', { 'type': 'time', 'lang': 'ru', 'class': 'cbi-input-text zm-ab-time', 'value': t, 'step': '300', 'disabled': autoBusy ? '' : null });
						ctl.push(inp, E('button', { 'class': 'cbi-button', 'disabled': autoBusy ? '' : null, 'click': function() {
							if (!/^\d\d:\d\d$/.test(inp.value)) { zm.toast('Укажите время в формате ЧЧ:ММ', 'warning'); return; }
							autoOwn = AUTO_TIMES.indexOf(inp.value) < 0;
							autoSet(inp.value, mode);
						} }, 'Сохранить'));
					}
					autoCard.appendChild(E('div', { 'class': 'zm-row zm-ab-row' }, [ E('span', { 'class': 'zm-label' }, 'Время запуска'), E('div', { 'class': 'zm-ab-ctl' }, ctl) ]));
				}
				autoCard.appendChild(E('div', { 'class': 'zm-row zm-ab-row' }, [ E('span', { 'class': 'zm-label' }, 'Стратегии'),
					E('div', { 'class': 'zm-seg' + (autoBusy ? ' zm-seg-busy' : '') }, AUTO_MODES.map(function(m) {
						return E('div', { 'class': 'zm-seg-item' + (m.id === mode ? ' zm-active' : ''), 'click': function() { if (!autoBusy && m.id !== mode) autoSet(autoInfo.time || 'off', m.id, 'Автоподбор будет проверять: ' + (m.id === 'youtube' ? 'только стратегии YouTube (Yv)' : m.label + (yt ? ' и YouTube' : ''))); } }, m.label);
					}))
				]));
				if (mode !== 'youtube') autoCard.appendChild(zm.swRow(yt, 'Подбирать и стратегию для YouTube',
					yt ? 'Сначала подбирается основная стратегия, затем для YouTube (Yv) — на адресах YouTube. Новая ставится, только если открывает заметно больше.' : 'Выключено — настройка YouTube остаётся как есть.',
					function() { if (!autoBusy) autoSet(autoInfo.time || 'off', mode, yt ? 'Подбор для YouTube выключен' : 'Включено: после основной стратегии — подбор для YouTube', yt ? 'off' : 'on'); }, autoBusy));
				else autoCard.appendChild(E('p', { 'class': 'zm-hint' }, 'Меняется только стратегия YouTube (Yv), основная стратегия остаётся как есть.'));
				function lastRes(l) {
					var yv = l.mode === 'youtube', unit = yv ? ' адресов YouTube' : ' сайтов', cur = l.cur || (yv ? 'из основной стратегии' : 'текущая');
					return l.result === 'applied' ? [ E('b', { 'class': 'zm-ab-ok' }, 'применена ' + l.best), ' — ' + l.best_ok + ' из ' + l.total + unit + ' (было ' + cur + ' — ' + l.cur_ok + ' из ' + l.total + ')' ]
						: l.result === 'kept' ? [ E('b', {}, 'оставлена ' + cur), ' — ' + l.cur_ok + ' из ' + l.total + unit + '; лучшая из проверенных ' + l.best + ' — ' + l.best_ok + ' из ' + l.total ]
						: l.result === 'nochange' ? [ 'пропущен — включено «Не изменять стратегию»' ]
						: l.result === 'yoff' ? [ 'пропущен — YouTube выключен в стратегии' ]
						: l.result === 'close' ? [ E('b', {}, 'оставлена ' + cur), ' — ' + l.cur_ok + ' из ' + l.total + unit + '; ' + l.best + ' — ' + l.best_ok + ' из ' + l.total + ', разница в пределах погрешности' ]
						: l.result === 'ctrl' ? [ E('b', { 'class': 'zm-ab-warn' }, 'пропущен'), ' — без Zapret открылось ' + l.cur_ok + ' из ' + l.total + unit + ': похоже, трафик роутера идёт через VPN' ]
						: l.result === 'none' ? [ 'лучшую стратегию определить не удалось, оставлена текущая' ] : [ E('b', { 'class': 'zm-ab-bad' }, 'ошибка'), ' — подробности в журнале теста' ];
				}
				var last = autoInfo.last, abLog = autoInfo.log || [];
				if (abLog.length) {
					var jl = E('div', { 'class': 'zm-ab-log' }, [ E('div', { 'class': 'zm-ab-log-row zm-ab-log-head' }, [ E('span', {}, 'Когда'), E('span', {}, 'Что'), E('span', {}, 'Итог') ]) ]);
					abLog.forEach(function(x) {
						jl.appendChild(E('div', { 'class': 'zm-ab-log-row' }, [
							E('span', { 'class': 'zm-ab-log-when' }, whenText(x.at)),
							E('span', { 'class': 'zm-ab-log-kind' }, x.kind === 'yt' || x.mode === 'youtube' ? 'YouTube' : 'Основная'),
							E('span', { 'class': 'zm-ab-log-res' }, lastRes(x))
						]));
					});
					autoCard.appendChild(E('h4', { 'class': 'zm-au-h', 'style': 'margin-top:14px' }, [ 'Журнал автоподбора', E('span', { 'class': 'zm-hint' }, 'последние 5') ]));
					autoCard.appendChild(jl);
				} else if (last && last.at) {
					var ly = autoInfo.last_yt, lastEl = E('div', { 'class': 'zm-ab-last' }, [ E('span', { 'class': 'zm-label' }, 'Последний запуск ' + whenText(last.at) + (last.mode === 'youtube' ? ', YouTube: ' : ': ')) ].concat(lastRes(last)));
					if (ly && ly.at && last.mode !== 'youtube') lastEl.appendChild(E('div', { 'style': 'margin-top:6px' }, [ E('span', { 'class': 'zm-label' }, 'YouTube: ') ].concat(lastRes(ly))));
					autoCard.appendChild(lastEl);
				}
				var yr = timeInfo.time ? new Date(timeInfo.time * 1000).getFullYear() : 0;
				if (on && yr && yr < 2024) autoCard.appendChild(E('p', { 'class': 'zm-hint' }, '⚠ Время на роутере неверное — расписание не сработает. Настройте его на странице «Система».'));
				var now = routerNow();
				autoCard.appendChild(E('div', { 'class': 'zm-actions zm-ab-actions' }, [
					E('button', { 'class': 'cbi-button cbi-button-positive', 'disabled': busy || !zapretInstalled ? '' : null, 'click': function() {
						if (busy) { zm.toast('Дождитесь окончания текущего теста', 'warning'); return; }
						return zm.ask('Запустить автоподбор сейчас?\n\nПроверка займёт 5–10 минут. Zapret в это время перезапускается со стратегиями по очереди.').then(function(ok) {
							if (!ok) return;
							busy = true; curMode = 'auto'; renderLaunch(); renderAuto();
							zm.testAction('auto_run', '').then(function(res) {
								if (res && res.error) { busy = false; curMode = ''; zm.toast(res.error, 'error'); renderLaunch(); renderAuto(); return; }
								zm.toast('Автоподбор запущен', 'info');
								startPolling();
							}).catch(function() { busy = false; curMode = ''; renderLaunch(); renderAuto(); zm.toast('Роутер не ответил', 'error'); });
						});
					} }, busy && curMode === 'auto' ? 'Идёт автоподбор…' : 'Запустить сейчас'),
					(last && last.at) || abLog.length ? E('button', { 'class': 'cbi-button', 'disabled': busy ? '' : null, 'click': function() {
						zm.testAction('auto_clear', '').then(function(r) { if (r && !r.error) { autoInfo = r.auto || {}; timeInfo = r; renderAuto(); } });
					} }, abLog.length ? 'Очистить журнал' : 'Удалить результат') : E([]),
					E('span', { 'class': 'zm-hint zm-ab-clock' }, 'Время роутера: ' + (now ? p2(now.getUTCHours()) + ':' + p2(now.getUTCMinutes()) : '—') + (timeInfo.zone ? ' · ' + (ZONE_RU[timeInfo.zone] || timeInfo.zone.replace(/^.*\//, '').replace(/_/g, ' ')) : ''))
				]));
			}

			function startDomain() {
				var v = domInput.value.trim();
				if (!v) { zm.toast('Введите хотя бы один домен', 'warning'); domInput.focus(); return; }
				doStart('domain:' + v.replace(/[\s,;]+/g, ' '));
			}

			function startCustomDom() {
				var v = cdomInput.value.trim();
				if (!customCount()) { zm.toast('Сначала добавьте свои стратегии', 'warning'); return; }
				if (!v) { zm.toast('Введите хотя бы один свой сайт', 'warning'); cdomInput.focus(); return; }
				doStart('custom_dom:' + v.replace(/[\s,;]+/g, ' '));
			}

			function doStart(mode) {
				if (busy) { zm.toast('Дождитесь окончания текущего теста', 'warning'); return; }
				busy = true;
				curMode = /^(domain|custom_dom):/.test(mode) ? mode.replace(/:.*$/, '') : mode;
				renderLaunch();
				zm.toast('Запускаем тест…', 'warning');
				zm.testAction('start', mode).then(function(res) {
					if (res && res.error) { busy = false; curMode = ''; zm.toast(res.error, 'error'); renderLaunch(); return; }
					startPolling();
				}).catch(function() { busy = false; curMode = ''; renderLaunch(); zm.toast('Роутер не ответил', 'error'); });
			}

			function doStop() {
				zm.toast('Останавливаем тест…', 'warning');
				zm.testAction('stop').then(function(res) {
					if (res && res.error) zm.toast(res.error, 'error');
				});
			}

			function startPolling() {
				logEl.classList.add('zm-show');
				zm.pollJob('strategy_test', logEl, function(ok) {
					var done = curMode;
					busy = false;
					curMode = '';
					zm.toast(ok ? 'Тест завершён' : 'Тест завершился с ошибкой — смотрите журнал', ok ? 'info' : 'error');
					refreshAll();
					zm.testStatus().then(function(res) {
						status = res;
						autoInfo = res.auto || {}; timeInfo = res;
						renderAuto();
						renderLaunch();
						if (done === 'auto') done = autoInfo.mode || 'v_flowseal';
						delete resData[done];
						loadResults(status['has_results_' + done] ? done : resMode);
					});
				});
			}

			function parse(res) {
				var out = { ts: '', rows: [], control: null };
				var doms = [];
				(res.detail || '').split('\n').forEach(function(l) {
					if (!l) return;
					var p = l.split('|');
					if (p[0] === 'T') out.ts = p[1];
					else if (p[0] === 'D') doms = (p[1] || '').split(' ').filter(Boolean);
					else if (p[0] === 'S') {
						var fails = (p[4] || '').split(' ').filter(Boolean), fm = {};
						fails.forEach(function(f) { fm[f] = true; });
						var row = { name: p[1], ok: +p[2], tot: +p[3], doms: doms.map(function(d) { return { name: d.replace(/_/g, ' '), ok: !fm[d] }; }) };
						if (/^Контрольный тест/.test(row.name)) out.control = row; else out.rows.push(row);
					}
				});
				if (!out.rows.length && res.lines) {
					res.lines.split('\n').forEach(function(l) {
						var m = l.match(/^(.*?)\s*→\s*(\d+)\/(\d+)\s*$/);
						if (!m) return;
						var row = { name: m[1], ok: +m[2], tot: +m[3], doms: [] };
						if (/^Контрольный тест/.test(row.name)) out.control = row; else out.rows.push(row);
					});
				}
				return out;
			}

			function loadResults(mode) {
				var avail = TEST_RESULT_MODES.filter(function(m) { return status['has_results_' + m]; });
				if (!mode || avail.indexOf(mode) < 0) mode = avail[0] || null;
				resMode = mode;
				if (!mode) { renderResults(); return; }
				if (resData[mode]) { renderResults(); return; }
				renderResults(true);
				zm.testResults(mode).then(function(res) {
					resData[mode] = parse(res || {});
					openRows = {};
					if (mode === 'current' || mode === 'domain' || mode === 'custom_dom') resData[mode].rows.forEach(function(r, i) { if (mode === 'current' || i === 0) openRows[mode + ':' + r.name] = true; });
					renderResults();
				}).catch(function() { renderResults(); });
			}

			function scoreCls(r, ctrl) {
				if (r.tot > 0 && r.ok === r.tot) return 'zm-tt-good';
				if (ctrl && r.ok > ctrl.ok) return 'zm-tt-mid';
				if (!ctrl && r.ok * 2 >= r.tot) return 'zm-tt-mid';
				return 'zm-tt-bad';
			}

			function customBlock(name) {
				var out = [], on = false;
				String(customText || '').split('\n').forEach(function(l) {
					l = l.trim();
					if (!l) return;
					if (l.charAt(0) === '#') { on = l.slice(1).trim() === name; if (on) out.push(l); return; }
					if (on) out.push(l);
				});
				return out.length > 1 ? out.join('\n') : '';
			}

			function applyStrategy(mode, name) {
				var call;
				if (mode === 'custom' || mode === 'custom_yt' || mode === 'custom_dom') {
					var block = customBlock(name);
					if (!block) { zm.toast('Стратегии «' + name + '» уже нет в вашем списке', 'warning'); return; }
					return tsGate('text:' + block, function() {
						zm.toast('Применяем ' + name + '…', 'warning');
						zm.nfqwsOptSet(block).then(function(r) {
							if (r && r.error) { zm.toast(r.error, 'error'); return; }
							zm.toast('Стратегия ' + name + ' применена', 'info');
							refreshAll();
						}).catch(function() { zm.toast('Роутер не ответил', 'error'); });
					}, 'Применить свою стратегию «' + name + '»?\n\nОна заменит весь блок стратегий Zapret (NFQWS_OPT) — вместе с частями для YouTube, Discord и игр. Вернуть их можно выбором стратегии на вкладке «Стратегии».',
						'Своя стратегия заменит весь блок стратегий Zapret (NFQWS_OPT) — вместе с частями для YouTube, Discord и игр.');
				}
				var spec;
				if (/^v([1-9]|10)$/.test(name)) { call = function() { return zm.strategySetV(name); }; spec = 'v:' + name; }
				else if (mode === 'youtube') { call = function() { return zm.strategySetYoutube(name); }; spec = 'youtube:' + name; }
				else { call = function() { return zm.strategySetFlowseal(name); }; spec = 'flowseal:' + name; }
				return tsGate(spec, function() {
					zm.toast('Применяем ' + name + '…', 'warning');
					call().then(function(r) {
						if (r && r.error) { zm.toast(r.error, 'error'); return; }
						zm.toast('Стратегия ' + name + ' применена', 'info');
						refreshAll();
					}).catch(function() { zm.toast('Роутер не ответил', 'error'); });
				}, 'Применить стратегию ' + name + '?');
			}

			function chips(list) {
				var bad = list.filter(function(d) { return !d.ok; }), good = list.filter(function(d) { return d.ok; });
				var box = E('div', { 'class': 'zm-tt-doms' });
				if (bad.length) box.appendChild(E('div', { 'class': 'zm-tt-domgrp' }, [
					E('div', { 'class': 'zm-tt-domhead zm-tt-bad' }, [ 'Не открылись · ' + bad.length ]),
					E('div', { 'class': 'zm-chips' }, bad.map(function(d) { return E('span', { 'class': 'zm-chip zm-chip-bad' }, [ E('span', { 'class': 'zm-dot' }), d.name ]); }))
				]));
				if (good.length) box.appendChild(E('div', { 'class': 'zm-tt-domgrp' }, [
					E('div', { 'class': 'zm-tt-domhead zm-tt-good' }, [ 'Открылись · ' + good.length ]),
					E('div', { 'class': 'zm-chips' }, good.map(function(d) { return E('span', { 'class': 'zm-chip zm-chip-ok' }, [ E('span', { 'class': 'zm-dot' }), d.name ]); }))
				]));
				return box;
			}

			function rowEl(mode, r, rank, ctrl, isCtrl) {
				var key = mode + ':' + r.name, open = !!openRows[key], pct = r.tot ? Math.round(r.ok * 100 / r.tot) : 0;
				var cls = isCtrl ? 'zm-tt-ctrl' : scoreCls(r, ctrl);
				var canApply = !isCtrl && mode !== 'current';
				var head = E('div', { 'class': 'zm-tt-row-head', 'click': function() {
					if (!r.doms.length) return;
					openRows[key] = !openRows[key];
					renderResults();
				} }, [
					E('span', { 'class': 'zm-tt-rank' }, [ isCtrl ? '—' : String(rank) ]),
					E('span', { 'class': 'zm-tt-name', 'title': r.name }, [ isCtrl ? 'Без Zapret' : r.name ]),
					E('span', { 'class': 'zm-tt-bar' }, [ E('span', { 'class': 'zm-tt-fill ' + cls, 'style': 'width:' + pct + '%' }) ]),
					E('span', { 'class': 'zm-tt-score ' + cls }, [ r.ok + ' / ' + r.tot ]),
					canApply ? E('button', { 'class': 'cbi-button zm-tt-apply', 'click': function(ev) { ev.stopPropagation(); applyStrategy(mode, r.name); } }, 'Применить') : E('span', { 'class': 'zm-tt-apply-ph' }),
					E('span', { 'class': 'zm-tt-chev' + (open ? ' zm-tt-open' : '') + (r.doms.length ? '' : ' zm-tt-nochev') }, '›')
				]);
				var body = open && r.doms.length ? chips(r.doms) : null;
				if (body && canApply) body.appendChild(E('div', { 'class': 'zm-tt-apply-m' }, [ E('button', { 'class': 'cbi-button cbi-button-positive', 'click': function() { applyStrategy(mode, r.name); } }, [ 'Применить ' + r.name ]) ]));
				return E('div', { 'class': 'zm-tt-row' + (open ? ' zm-tt-row-open' : '') + (isCtrl ? ' zm-tt-row-ctrl' : '') }, [ head, body || E([]) ]);
			}

			function resPad(s, n) { s = String(s); while (s.length < n) s += ' '; return s; }
			function resSave() {
				var d = resData[resMode], mode = resMode;
				if (!d) return;
				var bt = zm.busyToast('Готовим файл с результатами…');
				Promise.all([ zm.systemInfo().catch(function() { return {}; }), zm.status().catch(function() { return statusData || {}; }) ]).then(function(rr) {
					bt.close();
					var si = rr[0] || {}, st = rr[1] || {}, rows = d.rows.slice(), L = [], now = new Date();
					if (mode !== 'current') rows.sort(function(a, b) { return b.ok - a.ok; });
					var tot = rows.length ? rows[0].tot : (d.control ? d.control.tot : 0), w = 10;
					rows.forEach(function(r) { w = Math.max(w, String(r.name).length); });
					w = Math.min(w + 2, 42);
					function pct(r) { return r.tot ? Math.round(r.ok * 100 / r.tot) + '%' : '—'; }
					L.push('Zapret Manager — результаты теста стратегий');
					L.push('');
					function kv(k, v) { L.push(resPad(k + ':', 16) + v); }
					kv('Тест', mode === 'current' ? 'Текущая стратегия' : (TEST_MODE_LABELS[mode] || mode));
					if (d.ts) kv('Проверено', d.ts);
					kv('Роутер', [ si.model, si.hostname && si.hostname !== si.model ? '(' + si.hostname + ')' : '' ].filter(Boolean).join(' ') || '—');
					if (si.openwrt) kv('OpenWrt', si.openwrt + (si.arch ? ' · ' + si.arch : ''));
					if (st.strategy) kv('Сейчас стоит', st.strategy);
					if (tot) kv('Адресов', String(tot));
					if (mode === 'domain' && status.domains) kv('Сайты', status.domains);
					if (mode === 'custom_dom' && status.custom_domains) kv('Сайты', status.custom_domains);
					L.push('');
					if (d.control) { kv('Без Zapret', d.control.ok + ' / ' + d.control.tot + ' (' + pct(d.control) + ')'); L.push(''); }
					L.push(resPad('№', 4) + resPad('Стратегия', w) + 'Открылось');
					L.push(new Array(4 + w + 18).join('-'));
					rows.forEach(function(r, i) { L.push(resPad(i + 1, 4) + resPad(r.name, w) + resPad(r.ok + ' / ' + r.tot, 10) + pct(r)); });
					var det = rows.filter(function(r) { return r.doms && r.doms.length; });
					if (d.control && d.control.doms && d.control.doms.length) det.unshift(d.control);
					if (det.length) {
						L.push('');
						L.push('Подробно — какие адреса не открылись');
						det.forEach(function(r) {
							var bad = r.doms.filter(function(x) { return !x.ok; }).map(function(x) { return x.name; });
							L.push('');
							L.push((r === d.control ? 'Без Zapret' : r.name) + ' — ' + r.ok + ' из ' + r.tot + ':');
							L.push(bad.length ? '   не открылись: ' + bad.join(', ') : '   открылось всё');
						});
					}
					L.push('');
					L.push('Файл сохранён ' + now.toLocaleString('ru-RU'));
					var m = /(\d{1,2})\.(\d{1,2})\.(\d{4})\D+(\d{1,2}):(\d{2})/.exec(String(d.ts || '')), p2 = function(n) { return ('0' + n).slice(-2); };
					var stamp = m ? m[3] + '-' + p2(m[2]) + '-' + p2(m[1]) + '_' + p2(m[4]) + '-' + m[5] : now.getFullYear() + '-' + p2(now.getMonth() + 1) + '-' + p2(now.getDate()) + '_' + p2(now.getHours()) + '-' + p2(now.getMinutes());
					var who = String(si.model || si.hostname || 'router').replace(/[^A-Za-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '') || 'router';
					var what = { v_flowseal: 'v+flowseal', custom_yt: 'custom-youtube', custom_dom: 'custom-sites' }[mode] || String(mode).replace(/[^A-Za-z0-9+.-]+/g, '-');
					var a = E('a', { 'href': URL.createObjectURL(new Blob([ '\ufeff' + L.join('\r\n') + '\r\n' ], { type: 'text/plain;charset=utf-8' })), 'download': who + '_' + stamp + '_zapret-test-' + what + '.txt', 'style': 'display:none' });
					document.body.appendChild(a);
					a.click();
					setTimeout(function() { URL.revokeObjectURL(a.href); if (a.parentNode) a.parentNode.removeChild(a); }, 2000);
					zm.toast('Результаты сохранены в файл', 'info');
				}).catch(function() { bt.close(); zm.toast('Не удалось подготовить файл', 'error'); });
			}

			function renderResults(loading) {
				resCard.innerHTML = '';
				resCard.appendChild(E('h3', {}, 'Результаты'));
				var avail = TEST_RESULT_MODES.filter(function(m) { return status['has_results_' + m]; });
				if (!avail.length) {
					resCard.appendChild(E('p', { 'class': 'zm-hint' }, 'Пока пусто — запустите любой тест выше.'));
					return;
				}
				resCard.appendChild(E('div', { 'class': 'zm-tt-tabs' }, [
					E('div', { 'class': 'zm-seg' }, avail.map(function(m) {
						return E('div', { 'class': 'zm-seg-item' + (m === resMode ? ' zm-active' : ''), 'click': function() { if (m !== resMode) loadResults(m); } }, TEST_MODE_LABELS[m] || m);
					})),
					E('div', { 'class': 'zm-tt-btns' }, [
					E('button', { 'class': 'cbi-button', 'disabled': resData[resMode] && !loading ? null : '', 'title': 'Скачать результаты этого теста текстовым файлом', 'click': resSave }, 'Сохранить в файл'),
					E('button', { 'class': 'cbi-button', 'click': function() {
						zm.dialog({ title: 'Удалить результаты «' + (TEST_MODE_LABELS[resMode] || resMode) + '»?', danger: true, okText: 'Удалить результаты',
							blocks: [ { type: 'list', title: 'Что произойдёт', items: [
								'Результаты этого теста удалятся',
								'Результаты других тестов останутся'
							] } ]
						}).then(function(ok) { if (ok) zm.testAction('clear', resMode).then(function() {
							status['has_results_' + resMode] = false;
							delete resData[resMode];
							renderLaunch();
							loadResults(null);
						}); });
					} }, 'Удалить')
					])
				]));
				var d = resData[resMode];
				if (loading || !d) { resCard.appendChild(E('p', { 'class': 'zm-hint' }, 'Загружаем…')); return; }
				var rows = d.rows.slice();
				if (resMode !== 'current') rows.sort(function(a, b) { return b.ok - a.ok; });
				var total = rows.length ? rows[0].tot : (d.control ? d.control.tot : 0);
				var meta = [];
				if (d.ts) meta.push('Проверено ' + d.ts);
				if (resMode !== 'current') meta.push(rows.length + ' ' + (rows.length % 10 === 1 && rows.length % 100 !== 11 ? 'стратегия' : rows.length % 10 >= 2 && rows.length % 10 <= 4 && (rows.length % 100 < 12 || rows.length % 100 > 14) ? 'стратегии' : 'стратегий'));
				if (total) meta.push(total + ' адр.');
				if (resMode === 'domain' && status.domains) meta.push(status.domains);
				if (resMode === 'custom_dom' && status.custom_domains) meta.push(status.custom_domains);
				resCard.appendChild(E('p', { 'class': 'zm-hint zm-tt-meta' }, [ meta.join(' · ') ]));
				if (resMode !== 'current' && d.control && d.control.tot > 0 && d.control.ok * 100 >= d.control.tot * 80)
					resCard.appendChild(E('div', { 'class': 'zm-au-pause', 'style': 'margin:0 0 10px' }, 'Без Zapret открылось ' + d.control.ok + ' из ' + d.control.tot + ' — сайты доступны и так. Похоже, трафик самого роутера идёт через VPN или эти сайты у провайдера не блокируются, поэтому сравнение стратегий почти ничего не показывает. Автоподбор в таком случае стратегию не меняет.'));
				var list = E('div', { 'class': 'zm-tt-list' });
				if (d.control) list.appendChild(rowEl(resMode, d.control, 0, null, true));
				rows.forEach(function(r, i) { list.appendChild(rowEl(resMode, r, i + 1, d.control, false)); });
				resCard.appendChild(list);
				resCard.appendChild(E('p', { 'class': 'zm-hint' }, resMode === 'current' ? 'Нажмите на строку, чтобы скрыть или показать сайты.' : 'Нажмите на строку — покажет, какие сайты открылись. Зелёный — всё открылось, жёлтый — лучше, чем без Zapret, красный — не лучше.'));
			}

			renderLaunch();
			renderAuto();
			renderCustomCard();
			loadResults(TEST_RESULT_MODES.filter(function(m) { return status['has_results_' + m]; })[0]);
			if (busy) startPolling();

			panels.test.appendChild(launchCard);
			panels.test.appendChild(customCard);
			panels.test.appendChild(logEl);
			panels.test.appendChild(resCard);
			panels.test.appendChild(autoCard);
		})();

		(function buildYoutubePanel() {
			var status = statusData, initial = ytInitialData;
			var logEl = E('pre', { 'class': 'zm-log' });
			var grid = E('div', { 'class': 'zm-grid' });
			var lastList = null;
			var current = '';
			var busy = false;

			function currentYv(s) {
				var words = (s.strategy || '').split(' ');
				for (var i = 0; i < words.length; i++) {
					if (/^Yv[0-9]+z?$/.test(words[i])) return words[i].replace(/z$/, '');
				}
				return '';
			}

			function renderGrid(res) {
				lastList = res;
				grid.innerHTML = '';
				grid.appendChild(E('div', {
					'class': 'zm-tile' + (yvOff && !current ? ' zm-active' : ''),
					'click': function() {
						if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
						if (yvOff && !current) return;
						busy = true;
						zm.toast('Выключаем YouTube-стратегию', 'warning');
						zm.strategySetYoutube('off').then(function(r2) {
							busy = false;
							if (r2.error) { zm.toast(r2.error, 'error'); return; }
							zm.toast(r2.removed ? 'YouTube-стратегия выключена' : 'YouTube-стратегии и так не было — теперь она не будет добавляться', 'info');
							refreshAll();
						}).catch(function() { busy = false; });
					}
				}, yvOff && !current ? 'Выключена' : 'Выключить'));
				(res.items || []).forEach(function(it) {
					grid.appendChild(E('div', {
						'class': 'zm-tile' + (current === it.id ? ' zm-active' : ''),
						'click': function() {
							if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
							if (current === it.id) return;
							tsGate('youtube:' + it.id, function() {
							busy = true;
							zm.toast('Применяем стратегию ' + it.id + '', 'warning');
							zm.strategySetYoutube(it.id).then(function(r2) {
								busy = false;
								if (!zm.notifyStrategyResult(r2, it.id)) return;
								refreshAll();
							}).catch(function() { busy = false; });
							});
						}
					}, [ String(it.id) ]));
				});
				if (!res.items || !res.items.length)
					grid.appendChild(E('p', { 'class': 'zm-hint' }, 'Список пуст — нажмите «Обновить список».'));
			}

			var quicOn = !!status.quic_yt, quicBlocked = false;
			var quicCard = E('div', { 'class': 'zm-card' });

			function renderQuic() {
				quicCard.innerHTML = '';
				quicCard.appendChild(E('h3', {}, 'QUIC для YouTube'));
				quicCard.appendChild(E('p', { 'class': 'zm-hint' }, 'Браузеры и приложение YouTube часто грузят видео по QUIC (UDP 443), а не по TCP. Этот блок обходит блокировку и для QUIC. Работает вместе с выбранной стратегией.'));
				quicCard.appendChild(E('div', { 'class': 'zm-row' }, [
					E('span', { 'class': 'zm-label' }, 'Статус'),
					zm.badge(quicOn, 'включён', 'выключен')
				]));
				if (quicBlocked) quicCard.appendChild(E('p', { 'class': 'zm-hint' }, quicOn
					? 'QUIC сейчас заблокирован на странице «Система» — блок не работает, пока блокировка включена.'
					: 'QUIC сейчас заблокирован на странице «Система» — YouTube и так идёт по TCP, блок не нужен.'));
				quicCard.appendChild(E('div', { 'class': 'zm-actions' }, [
					E('button', {
						'class': quicOn ? 'cbi-button cbi-button-remove' : 'cbi-button cbi-button-positive',
						'click': function() {
							if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
							busy = true;
							zm.toast(quicOn ? 'Выключаем QUIC для YouTube' : 'Включаем QUIC для YouTube', 'warning');
							zm.youtubeQuicSet(quicOn ? 'off' : 'on').then(function(res) {
								busy = false;
								if (res.error) { zm.toast(res.error, 'error'); return; }
								zm.toast(res.quic ? 'QUIC для YouTube включён' : 'QUIC для YouTube выключен', 'info');
								refreshAll();
							}).catch(function() { busy = false; });
						}
					}, quicOn ? 'Выключить' : 'Включить')
				]));
			}

			var ipidCard = E('div', { 'class': 'zm-card' }), ipidBusy = false;
			var ipid = { on: !!status.ipid, want: status.ipid_want || '', yt: !!status.yt_tcp };

			function renderIpid() {
				ipidCard.innerHTML = '';
				var on = ipid.yt ? ipid.on : ipid.want === 'on';
				ipidCard.appendChild(E('h3', {}, 'Маскировка подменных пакетов'));
				ipidCard.appendChild(zm.swRow(on, ipidBusy ? 'Блок --ip-id=zero — применяем…' : 'Блок --ip-id=zero',
					[ 'Добавляет строку --ip-id=zero в стратегию YouTube и сохраняется при её смене.', E('br'), 'Попробуйте включить, если YouTube плохо грузится.' ],
					function() { toggleIpid(!on); }, ipidBusy));
				if (!ipid.yt) ipidCard.appendChild(E('p', { 'class': 'zm-hint zm-ab-warn' }, on
					? 'Стратегии для YouTube сейчас нет — маскировка включится сама, когда вы её выберете.'
					: 'Стратегии для YouTube сейчас нет — сначала выберите её выше.'));
			}

			function toggleIpid(on) {
				if (busy || ipidBusy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
				ipidBusy = true; renderIpid();
				zm.toast(on ? 'Включаем маскировку и перезапускаем Zapret' : 'Выключаем маскировку и перезапускаем Zapret', 'warning');
				zm.zapretOptSet('ipid:' + (on ? 'on' : 'off')).then(function(res) {
					ipidBusy = false;
					if (!res || res.error) { zm.toast((res && res.error) || 'Роутер не ответил', 'error'); renderIpid(); return; }
					ipid = { on: !!res.ipid, want: res.ipid_want || '', yt: !!res.yt_tcp };
					renderIpid();
					zm.toast(on ? (ipid.yt ? 'Маскировка включена' : 'Маскировка включится вместе со стратегией YouTube') : 'Маскировка выключена', 'info');
					refreshAll();
				}).catch(function() { ipidBusy = false; zm.toast('Роутер не ответил', 'error'); renderIpid(); });
			}

			function refreshState() {
				zm.status().then(function(s) {
					current = currentYv(s);
					yvOff = !!s.yv_off;
					quicOn = !!s.quic_yt;
					if (!ipidBusy) { ipid = { on: !!s.ipid, want: s.ipid_want || '', yt: !!s.yt_tcp }; renderIpid(); }
					if (lastList) renderGrid(lastList);
					renderQuic();
				});
				zm.systemStatus().then(function(ss) {
					quicBlocked = !!(ss && ss.quic_blocked);
					renderQuic();
				}).catch(function() {});
			}

			refreshers.youtube = refreshState;
			tabHooks.youtube = refreshState;
			var yvOff = !!status.yv_off;
			current = currentYv(status);
			renderQuic();
			renderIpid();

			var card = E('div', { 'class': 'zm-card' }, [
				E('h3', {}, 'Стратегии для YouTube'),
				E('div', { 'class': 'zm-actions' }, [
					E('button', {
						'class': 'cbi-button',
						'click': function() {
							if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
							busy = true;
							zm.toast('Обновляем список YouTube-стратегий', 'warning');
							grid.innerHTML = 'Загрузка списка';
							zm.strategyListYoutube('refresh').then(function(res) {
								if (res.started) {
									zm.pollJob('youtube_download', logEl, function(ok) {
										busy = false;
										zm.toast(ok ? 'Список YouTube-стратегий обновлён' : 'Не удалось обновить список', ok ? 'info' : 'error');
										zm.strategyListYoutube().then(renderGrid);
									});
								} else {
									busy = false;
									renderGrid(res);
									zm.toast('Список YouTube-стратегий обновлён', 'info');
								}
							}).catch(function() { busy = false; });
						}
					}, 'Обновить список')
				]),
				grid,
				E('p', { 'class': 'zm-hint' }, 'Меняет только YouTube-часть текущей стратегии. «Выключить» убирает её совсем — например, если YouTube уже работает через VPN.')
			]);

			panels.youtube.appendChild(card);
			panels.youtube.appendChild(logEl);
			panels.youtube.appendChild(ipidCard);
			panels.youtube.appendChild(quicCard);
			refreshState();

			if (!initial.started) {
				renderGrid(initial);
			} else {
				busy = true;
				grid.appendChild(E('p', { 'class': 'zm-hint' }, 'Загружаем список…'));
				zm.pollJob('youtube_download', logEl, function(ok) {
					busy = false;
					if (!ok) { grid.innerHTML = ''; grid.appendChild(E('p', { 'class': 'zm-hint' }, 'Список не загрузился — нажмите «Обновить список».')); return; }
					zm.strategyListYoutube().then(renderGrid);
				});
			}
		})();

		(function buildGamePanel() {
			var data = gameData;
			var gvGrid = E('div', { 'class': 'zm-grid' });
			var xtremeRow = E('div', {});
			var fakeGrid = E('div', { 'class': 'zm-grid' });
			var busy = false;

			function renderGv() {
				gvGrid.innerHTML = '';
				var off = !data.active;
				gvGrid.appendChild(E('div', {
					'class': 'zm-tile' + (off ? ' zm-active' : ''),
					'click': function() {
						if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
						if (off) return;
						busy = true;
						zm.toast('Выключаем игровую стратегию', 'warning');
						zm.gameSet('off').then(function(res) {
							busy = false;
							if (res.error) { zm.toast(res.error, 'error'); return; }
							zm.toast('Игровая стратегия выключена', 'info');
							refreshAll();
						}).catch(function() { busy = false; });
					}
				}, off ? 'Выключена' : 'Выключить'));
				[1, 2, 3, 4].forEach(function(n) {
					gvGrid.appendChild(E('div', {
						'class': 'zm-tile' + (data.active && data.current === ('Gv' + n) ? ' zm-active' : ''),
						'click': function() {
							if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
							if (data.active && data.current === ('Gv' + n)) return;
							tsGate('gv:' + n, function() {
							busy = true;
							zm.toast('Применяем игровую стратегию Gv' + n + '', 'warning');
							zm.gameSet(String(n)).then(function(res) {
								busy = false;
								if (res.error) { zm.toast(res.error, 'error'); return; }
								zm.toast(res.game === 'none' ? 'Игровая стратегия снята' : res.game + ' применена', 'info');
								refreshAll();
							}).catch(function() { busy = false; });
							});
						}
					}, 'Gv' + n));
				});
			}

			function renderXtreme() {
				var xtreme = data.xtreme === true;
				xtremeRow.innerHTML = '';
				xtremeRow.appendChild(E('div', { 'class': 'zm-row' }, [
					E('span', { 'class': 'zm-label' }, 'Статус'),
					zm.badge(xtreme, 'включён', 'выключен')
				]));
				xtremeRow.appendChild(E('p', { 'class': 'zm-hint' }, 'Может мешать работе других приложений. Включайте только для проверки игр.'));
				xtremeRow.appendChild(E('div', { 'class': 'zm-actions' }, [
					E('button', {
						'class': xtreme ? 'cbi-button cbi-button-remove' : 'cbi-button cbi-button-positive',
						'click': function() {
							if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
							busy = true;
							zm.toast(xtreme ? 'Выключаем Xtreme' : 'Включаем Xtreme', 'warning');
							zm.gameToggleXtreme().then(function(res) {
								busy = false;
								if (res.error) { zm.toast(res.error, 'error'); return; }
								zm.toast(res.xtreme ? 'Xtreme включён' : 'Xtreme выключен', 'info');
								refreshAll();
							}).catch(function() { busy = false; });
						}
					}, xtreme ? 'Выключить Xtreme' : 'Включить Xtreme')
				]));
			}

			function renderFake() {
				fakeGrid.innerHTML = '';
				GAME_FAKES.forEach(function(f) {
					fakeGrid.appendChild(E('div', {
						'class': 'zm-tile' + (data.fake === f ? ' zm-active' : ''),
						'click': function() {
							if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
							busy = true;
							zm.toast('Меняем fake-файл на ' + f + '', 'warning');
							zm.gameSetFake(f).then(function(res) {
								busy = false;
								if (res.error) { zm.toast(res.error, 'error'); return; }
								zm.toast(f + ' установлен', 'info');
								refreshAll();
							}).catch(function() { busy = false; });
						}
					}, f));
				});
			}

			function refreshState() {
				zm.gameStatus().then(function(res) {
					data = res;
					renderGv();
					renderXtreme();
					renderFake();
				});
			}

			refreshers.game = refreshState;
			tabHooks.game = refreshState;
			renderGv();
			renderXtreme();
			renderFake();

			var gvCard = E('div', { 'class': 'zm-card' }, [
				E('h3', {}, 'Игровая стратегия'),
				gvGrid,
				E('p', { 'class': 'zm-hint' }, '«Выключить» убирает игровую часть из Zapret совсем, вместе с её портами.')
			]);

			var xtremeCard = E('div', { 'class': 'zm-card' }, [
				E('h3', {}, 'Xtreme режим'),
				xtremeRow
			]);

			var fakeCard = E('div', { 'class': 'zm-card' }, [
				E('h3', {}, 'Fake-файл для игровой стратегии'),
				fakeGrid,
				E('p', { 'class': 'zm-hint' }, 'Работает, только когда выбрана игровая стратегия.')
			]);

			panels.game.appendChild(gvCard);
			panels.game.appendChild(xtremeCard);
			panels.game.appendChild(fakeCard);
		})();

		(function buildDiscordPanel() {
			var data = discordData;
			var dvGrid = E('div', { 'class': 'zm-grid' });
			var fakeGrid = E('div', { 'class': 'zm-grid' });
			var busy = false;

			function renderDv() {
				dvGrid.innerHTML = '';
				var off = !data.active;
				dvGrid.appendChild(E('div', {
					'class': 'zm-tile' + (off ? ' zm-active' : ''),
					'click': function() {
						if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
						if (off) return;
						busy = true;
						zm.toast('Выключаем стратегию Discord', 'warning');
						zm.discordSetDv('off').then(function(res) {
							busy = false;
							if (res.error) { zm.toast(res.error, 'error'); return; }
							zm.toast(res.removed ? 'Стратегия Discord выключена' : 'Стратегии Discord и так не было — теперь она не будет добавляться', 'info');
							refreshAll();
						}).catch(function() { busy = false; });
					}
				}, off ? 'Выключена' : 'Выключить'));
				(data.available || []).forEach(function(dv) {
					dvGrid.appendChild(E('div', {
						'class': 'zm-tile' + (data.active && data.current === dv ? ' zm-active' : ''),
						'click': function() {
							if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
							if (data.active && data.current === dv) return;
							tsGate('dv:' + dv.replace('Dv', ''), function() {
							busy = true;
							zm.toast('Применяем стратегию ' + dv + '', 'warning');
							zm.discordSetDv(dv.replace('Dv', '')).then(function(res) {
								busy = false;
								if (!zm.notifyStrategyResult(res, dv)) return;
								refreshAll();
							}).catch(function() { busy = false; });
							});
						}
					}, dv));
				});
			}

			function renderFake() {
				fakeGrid.innerHTML = '';
				GAME_FAKES.forEach(function(f) {
					fakeGrid.appendChild(E('div', {
						'class': 'zm-tile' + (data.active && data.current_fake === f ? ' zm-active' : ''),
						'click': function() {
							if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
							busy = true;
							zm.toast('Меняем fake-файл на ' + f + '', 'warning');
							zm.discordSetFake(f).then(function(res) {
								busy = false;
								if (!zm.notifyStrategyResult(res, f)) return;
								refreshAll();
							}).catch(function() { busy = false; });
						}
					}, f));
				});
			}

			var scriptCard = E('div', { 'class': 'zm-card' }), scriptBusy = '';
			function renderScripts() {
				scriptCard.innerHTML = '';
				scriptCard.appendChild(E('h3', {}, 'Скрипты и hosts для Discord'));
				var cur = data.script || 'off', on = CUSTOM_SCRIPTS.filter(function(s) { return s.id === cur; })[0];
				scriptCard.appendChild(E('div', { 'class': 'zm-row' }, [ E('span', { 'class': 'zm-label' }, 'Скрипт custom.d'),
					E('div', { 'class': 'zm-seg' + (scriptBusy ? ' zm-seg-busy' : '') }, CUSTOM_SCRIPTS.map(function(s) {
						return E('div', { 'class': 'zm-seg-item' + (s.id === cur ? ' zm-active' : ''), 'click': function() {
							if (s.id === cur || scriptBusy) return;
							if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
							scriptBusy = 'script'; renderScripts();
							zm.toast(s.id === 'off' ? 'Убираем скрипт и перезапускаем Zapret' : 'Скачиваем ' + s.label + ' и перезапускаем Zapret', 'warning');
							zm.zapretOptSet('script:' + s.id).then(function(r) {
								scriptBusy = '';
								if (!r || r.error) { zm.toast((r && r.error) || 'Роутер не ответил', 'error'); renderScripts(); return; }
								zm.toast(s.id === 'off' ? 'Скрипт убран' : 'Скрипт ' + s.label + ' установлен', 'info');
								refreshState();
							}).catch(function() { scriptBusy = ''; zm.toast('Роутер не ответил', 'error'); renderScripts(); });
						} }, s.label);
					}))
				]));
				scriptCard.appendChild(E('p', { 'class': 'zm-hint' }, cur === 'other'
					? 'Сейчас стоит свой скрипт 50-script.sh — панель его не узнаёт. Выбор другого варианта заменит его.'
					: (on && on.hint ? 'Сейчас: ' + on.hint + '. ' : '') + 'Готовые скрипты из примеров zapret добавляют свои правила обхода поверх стратегии. Ставится один скрипт: выбор другого заменяет прежний.'));
				scriptCard.appendChild(zm.swRow(!!data.finland, scriptBusy === 'fin' ? 'Финские IP для Discord — применяем…' : 'Финские IP для Discord', 'Добавляет в hosts адреса голосовых серверов finland10000–10199.discord.media → 104.25.158.178. Помогает, если голос в Discord не подключается.', function() {
					if (scriptBusy) return;
					scriptBusy = 'fin'; renderScripts();
					zm.hostsToggle('finland').then(function(r) {
						scriptBusy = '';
						if (!r || r.error) { zm.toast((r && r.error) || 'Роутер не ответил', 'error'); renderScripts(); return; }
						data.finland = !!r.enabled;
						zm.toast(r.enabled ? 'Финские IP добавлены в hosts' : 'Финские IP убраны из hosts', 'info');
						renderScripts();
					}).catch(function() { scriptBusy = ''; zm.toast('Роутер не ответил', 'error'); renderScripts(); });
				}, !!scriptBusy));
			}

			function refreshState() {
				zm.discordStatus().then(function(res) {
					data = res;
					renderDv();
					renderFake();
					if (!scriptBusy) renderScripts();
				});
			}

			refreshers.discord = refreshState;
			tabHooks.discord = refreshState;
			renderDv();
			renderFake();
			renderScripts();

			var dvCard = E('div', { 'class': 'zm-card' }, [
				E('h3', {}, 'Стратегия для Discord'),
				dvGrid,
				E('p', { 'class': 'zm-hint' }, 'Стратегия Discord — это два блока: голос (discord,stun) и discord.media. «Выключить» убирает оба, и при смене основной стратегии они не вернутся. Любая Dv включает их снова.')
			]);

			var fakeCard = E('div', { 'class': 'zm-card' }, [
				E('h3', {}, 'Fake-файл для discord,stun'),
				fakeGrid,
				E('p', { 'class': 'zm-hint' }, 'Работает, только когда включена стратегия Discord.')
			]);

			panels.discord.appendChild(dvCard);
			panels.discord.appendChild(fakeCard);
			panels.discord.appendChild(scriptCard);
		})();

		(function buildListsPanel() {
			var LISTS = [
				{ id: 'exclude', title: 'Список исключений', hint: 'Сайты, которые Zapret не трогает никогда. По одному домену в строке, поддомены входят сами.', restore: true },
				{ id: 'user', title: 'Список пользовательских хостов', hint: 'Свои сайты, к которым Zapret применяет стратегию. По одному домену в строке.' },
				{ id: 'google', title: 'Список Google', hint: 'Домены YouTube и Google для YouTube-стратегии и QUIC. Панель сама дописывает сюда нужные домены при выборе стратегии.' }
			];
			var busy = false;
			var intro = E('p', { 'class': 'zm-hint zm-lists-intro' }, 'Нажмите на список, чтобы развернуть его. «Сохранить и применить» записывает файл и перезапускает Zapret. Строка #nochange в списке запрещает панели менять его при обновлениях и восстановлении.');
			panels.lists.appendChild(intro);

			function plural(n, a, b, c) { var m = n % 10, h = n % 100; return m === 1 && h !== 11 ? a : (m >= 2 && m <= 4 && (h < 12 || h > 14) ? b : c); }
			function countText(n) { return n + ' ' + plural(n, 'запись', 'записи', 'записей'); }
			function countOf(text) { return String(text || '').split('\n').filter(function(l) { l = l.trim(); return l && l.charAt(0) !== '#'; }).length; }

			LISTS.forEach(function(L) {
				var st = { open: false, loaded: false, saved: '', info: null };
				var ta = E('textarea', { 'class': 'zm-config-editor zm-list-editor', 'spellcheck': 'false', 'wrap': 'off', 'placeholder': 'example.com' });
				var countEl = E('span', { 'class': 'zm-badge zm-off zm-list-count' }, '…');
				var dirtyEl = E('span', { 'class': 'zm-list-dirty', 'style': 'display:none', 'title': 'Есть несохранённые изменения' }, 'не сохранено');
				var chev = E('span', { 'class': 'zm-list-chev', 'aria-hidden': 'true' }, '›');
				var body = E('div', { 'class': 'zm-list-body', 'style': 'display:none' });
				var btnSave = E('button', { 'class': 'cbi-button cbi-button-positive' }, 'Сохранить и применить');
				var btnReload = E('button', { 'class': 'cbi-button' }, 'Перечитать файл');
				var lbar = zm.saveBar({
					onCancel: function() { ta.value = st.saved; syncCount(); },
					onSave: function() { btnSave.click(); }
				});
				var btnRestore = L.restore ? E('button', { 'class': 'cbi-button' }, 'Восстановить исходный') : null;

				function dirty() { return st.loaded && ta.value !== st.saved; }
				function syncCount() {
					var n = st.loaded ? countOf(ta.value) : (st.info ? st.info.count : 0);
					countEl.textContent = st.info && !st.info.exists && !dirty() ? 'нет файла' : countText(n);
					countEl.className = 'zm-badge zm-list-count ' + (n ? 'zm-ok' : 'zm-off');
					if (typeof renderAutoBox === 'function') renderAutoBox();
					if (typeof renderNc === 'function' && ncBox) renderNc();
					dirtyEl.style.display = dirty() ? '' : 'none';
					btnSave.disabled = !st.loaded;
					lbar.set(dirty() || (busy && st.open && lbar.isDirty()), busy && lbar.isDirty());
				}
				function load(quiet) {
					return zm.zapretListGet(L.id).then(function(r) {
						if (r.error) { zm.toast(r.error, 'error'); syncCount(); return; }
						st.saved = r.content || ''; if (st.saved && st.saved.slice(-1) !== '\n') st.saved += '\n';
						ta.value = st.saved; st.loaded = true; st.info = r.info || st.info; syncCount();
						if (!quiet) zm.toast(L.title + ': перечитан из файла', 'info');
					});
				}
				function toggle() {
					var zmGo = function() {
						st.open = !st.open;
						if (!st.open && st.loaded) { ta.value = st.saved; syncCount(); }
						card.classList.toggle('zm-list-open', st.open);
						body.style.display = st.open ? '' : 'none';
						head.setAttribute('aria-expanded', st.open ? 'true' : 'false');
						if (st.open) (st.loaded ? Promise.resolve() : load(true)).then(function() { ta.focus(); });
					};
					if (st.open && dirty()) return zm.ask('В «' + L.title + '» есть несохранённые изменения. Свернуть и отменить их?').then(function(ok) { return ok ? zmGo() : undefined; });
					return zmGo();
				}

				ta.addEventListener('input', syncCount);
				btnSave.addEventListener('click', function() {
					if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
					busy = true; btnSave.disabled = true; syncCount();
					zm.toast('Сохраняем «' + L.title + '» и перезапускаем Zapret', 'warning');
					zm.zapretListSet(L.id, ta.value).then(function(r) {
						busy = false;
						if (r.error) { zm.toast(r.error, 'error'); syncCount(); return; }
						st.info = r.info || st.info;
						return load(true).then(function() { syncCount(); zm.toast(L.title + ' сохранён, Zapret перезапущен', 'info'); });
					}).catch(function() { busy = false; syncCount(); zm.toast('Роутер не ответил', 'error'); });
				});
				btnReload.addEventListener('click', function() {
					var zmGo = function() { load(false); };
					if (dirty()) return zm.ask('Отменить несохранённые изменения и перечитать «' + L.title + '» из файла?').then(function(ok) { return ok ? zmGo() : undefined; });
					return zmGo();
				});
				if (btnRestore) btnRestore.addEventListener('click', function() {
					if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
					return zm.ask('Заменить список исключений исходным из репозитория Zapret Manager? Ваши правки в нём пропадут.').then(function(ok) {
						if (!ok) return;
						busy = true;
						zm.toast('Скачиваем исходный список исключений', 'warning');
						zm.zapretListRestore(L.id).then(function(r) {
							busy = false;
							if (r.error) { zm.toast(r.error, 'error'); syncCount(); return; }
							st.saved = r.content || ''; if (st.saved && st.saved.slice(-1) !== '\n') st.saved += '\n';
							ta.value = st.saved; st.loaded = true; st.info = r.info || st.info; syncCount();
							zm.toast('Список исключений восстановлен, Zapret перезапущен', 'info');
						}).catch(function() { busy = false; syncCount(); zm.toast('Роутер не ответил', 'error'); });
					});
				});

				var head = E('div', { 'class': 'zm-list-head', 'role': 'button', 'tabindex': '0', 'aria-expanded': 'false', 'click': toggle,
					'keydown': function(ev) { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); toggle(); } } }, [
					chev,
					E('div', { 'class': 'zm-list-titles' }, [
						E('div', { 'class': 'zm-list-title' }, L.title),
						E('div', { 'class': 'zm-list-path' }, '/opt/zapret/ipset/' + ({ exclude: 'zapret-hosts-user-exclude.txt', user: 'zapret-hosts-user.txt', google: 'zapret-hosts-google.txt' })[L.id])
					]),
					dirtyEl,
					countEl
				]);
				body.appendChild(E('p', { 'class': 'zm-hint zm-list-hint' }, L.hint));
				body.appendChild(ta);
				body.appendChild(E('div', { 'class': 'zm-actions zm-list-actions' }, [ btnReload, btnRestore ]));
				var ncBox = E('div', { 'class': 'zm-list-nc' }), ncBusy = false;
				function ncOn() { return st.loaded ? /#\s*nochange/i.test(st.saved) : !!(st.info && st.info.nochange); }
				function renderNc() {
					var on = ncOn();
					ncBox.innerHTML = '';
					ncBox.appendChild(zm.swRow(on, 'Не изменять список', 'Панель не будет трогать этот список при установке, обновлении, смене стратегии' + (L.restore ? ', тесте и автообновлении' : ' и тесте') + '. В файл добавляется строка #nochange.', function() {
						if (ncBusy || busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
						if (dirty()) { zm.toast('Сначала сохраните или отмените изменения в списке', 'warning'); return; }
						ncBusy = true; renderNc();
						zm.zapretListRestore('nochange=' + L.id + ':' + (on ? 'off' : 'on')).then(function(r) {
							ncBusy = false;
							if (r && r.info) st.info = r.info;
							if (!r || r.error) { zm.toast((r && r.error) || 'Роутер не ответил', 'error'); renderNc(); return; }
							zm.toast(on ? L.title + ': панель снова может его обновлять' : L.title + ': панель больше не будет его менять', 'info');
							return load(true);
						}).catch(function() { ncBusy = false; zm.toast('Роутер не ответил', 'error'); renderNc(); });
					}, ncBusy));
				}
				body.appendChild(ncBox);
				var autoBox = L.restore ? E('div', { 'class': 'zm-list-auto' }) : null, autoBusy = false;
				function renderAutoBox() {
					if (!autoBox) return;
					var cur = (st.info && st.info.auto) || 'off', locked = ncOn();
					autoBox.innerHTML = '';
					autoBox.appendChild(E('div', { 'class': 'zm-row zm-list-auto-row' }, [
						E('span', { 'class': 'zm-label' }, 'Обновлять список'),
						E('div', { 'class': 'zm-seg' + (autoBusy ? ' zm-seg-busy' : '') }, [ [ 'off', 'Выкл' ], [ 'h2', '2 ч' ], [ 'h4', '4 ч' ], [ 'h6', '6 ч' ], [ 'h12', '12 ч' ] ].map(function(o) {
							return E('div', { 'class': 'zm-seg-item' + (o[0] === cur ? ' zm-active' : ''), 'click': function() {
								if (o[0] === cur || autoBusy) return;
								autoBusy = true; renderAutoBox();
								zm.zapretListRestore('auto=' + o[0]).then(function(r) {
									autoBusy = false;
									if (!r || r.error) { zm.toast((r && r.error) || 'Роутер не ответил', 'error'); renderAutoBox(); return; }
									st.info = r.info || st.info;
									zm.toast(o[0] === 'off' ? 'Автообновление списка исключений выключено' : 'Список исключений будет обновляться каждые ' + o[1], 'info');
									renderAutoBox();
								}).catch(function() { autoBusy = false; zm.toast('Роутер не ответил', 'error'); renderAutoBox(); });
							} }, o[1]);
						}))
					]));
					autoBox.appendChild(E('p', { 'class': 'zm-hint', 'style': 'margin:4px 0 0' }, locked && cur !== 'off'
						? 'Включено «Не изменять список» — автообновление пропускается.'
						: 'Панель сама скачивает свежий список из репозитория Zapret Manager и перезапускает Zapret, если он изменился. Свои правки при этом заменяются; чтобы список не трогали, включите «Не изменять список».'));
				}
				if (autoBox) { body.appendChild(autoBox); renderAutoBox(); }
				body.appendChild(lbar);
				var card = E('div', { 'class': 'zm-card zm-list-card' }, [ head, body ]);
				panels.lists.appendChild(card);
				L.refresh = function() {
					if (st.loaded && !dirty()) return load(true);
					if (!st.loaded) return zm.zapretListsStatus().then(function(r) {
						(r.lists || []).forEach(function(i) { if (i.id === L.id) { st.info = i; syncCount(); } });
					});
				};
				syncCount();
			});

			function refreshAllLists() {
				zm.zapretListsStatus().then(function(r) {
					if (r.error) return;
					LISTS.forEach(function(L) { L.refresh && L.refresh(); });
				});
			}
			refreshAllLists();
			tabHooks.lists = refreshAllLists;
		})();

		(function buildExclusionsPanel() {
			var data = exclusionsData;

			if (data.error) {
				panels.exclusions.appendChild(E('div', { 'class': 'zm-card' }, [
					E('h3', {}, 'Исключение устройств'),
					E('p', { 'class': 'zm-hint' }, data.error)
				]));
				return;
			}

			var grid = E('div', { 'class': 'zm-svc-grid' });
			var busy = false;

			function renderGrid(devices) {
				grid.innerHTML = '';
				(devices || []).forEach(function(d) {
					grid.appendChild(zm.svcCard({ name: d.name || d.ip, sub: d.name ? d.ip : 'без имени', key: d.ip, on: !!d.excluded,
						'click': function() {
							if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
							busy = true;
							zm.toast('Переключаем исключение для ' + d.ip + '', 'warning');
							zm.exclusionsToggle(d.ip).then(function(res) {
								busy = false;
								if (res.error) { zm.toast(res.error, 'error'); return; }
								zm.toast(d.ip + (res.excluded ? ' исключён' : ' больше не исключён'), 'info');
								zm.exclusionsStatus().then(function(r) { renderGrid(r.devices); });
							}).catch(function() { busy = false; });
						}
					}));
				});
				if (!devices || !devices.length)
					grid.appendChild(E('p', { 'class': 'zm-hint', 'style': 'grid-column: 1 / -1; margin: 0' }, 'Устройства не найдены — нажмите «Обновить список».'));
			}

			renderGrid(data.devices);

			var manualInput = E('input', { 'type': 'text', 'placeholder': '192.168.1.100', 'class': 'cbi-input-text' });

			var card = E('div', { 'class': 'zm-card' }, [
				E('h3', {}, 'Исключение устройств из Zapret'),
				grid,
				E('p', { 'class': 'zm-hint' }, 'Включённые устройства ходят мимо Zapret.'),
				E('div', { 'class': 'zm-actions' }, [
					E('button', {
						'class': 'cbi-button',
						'click': function() {
							if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
							busy = true;
							zm.toast('Обновляем список устройств', 'warning');
							zm.exclusionsStatus().then(function(res) {
								busy = false;
								renderGrid(res.devices);
								zm.toast('Список устройств обновлён', 'info');
							}).catch(function() { busy = false; });
						}
					}, 'Обновить список'),
					manualInput,
					E('button', {
						'class': 'cbi-button',
						'click': function() {
							if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
							var ip = manualInput.value.trim();
							if (!/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(ip)) {
								zm.toast('Некорректный IPv4 адрес', 'error');
								return;
							}
							busy = true;
							zm.toast('Добавляем ' + ip + ' в исключения', 'warning');
							zm.exclusionsToggle(ip).then(function(res) {
								busy = false;
								if (res.error) { zm.toast(res.error, 'error'); return; }
								manualInput.value = '';
								zm.toast(ip + (res.excluded ? ' добавлен в исключения' : ' убран из исключений'), 'info');
								zm.exclusionsStatus().then(function(r) { renderGrid(r.devices); });
							}).catch(function() { busy = false; });
						}
					}, 'Добавить вручную'),
					E('button', {
						'class': 'cbi-button cbi-button-remove',
						'click': function() {
							if (busy) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
							busy = true;
							zm.toast('Очищаем все исключения', 'warning');
							zm.exclusionsClear().then(function() {
								busy = false;
								zm.toast('Все исключения очищены', 'info');
								zm.exclusionsStatus().then(function(res) { renderGrid(res.devices); });
							}).catch(function() { busy = false; });
						}
					}, 'Очистить все')
				])
			]);

			panels.exclusions.appendChild(card);
		})();

		if (zapretInstalled) {
			renderTabBar();
			mainSection.appendChild(tabBar);
			TABS.forEach(function(t) { mainSection.appendChild(panels[t.id]); });
		}
		wrap.appendChild(mainSection);
		return wrap;
	}
});
ZM_INSTALLER_EOF
chmod 0644 '/www/luci-static/resources/view/zapret-manager/strategy.js'

cat > '/www/luci-static/resources/view/zapret-manager/zapret2.js' << 'ZM_INSTALLER_EOF'
'use strict';
'require view';
'require zapret-manager.common as zm';
var E = (function(raw) { return function() { var a = Array.prototype.slice.call(arguments), i = a.length - 1; if (i >= 1 && (typeof a[i] === 'string' || typeof a[i] === 'number')) a[i] = [ String(a[i]) ]; return raw.apply(null, a); }; })(window.E);

return view.extend({
	load: function() {
		zm.injectCss();
		return zm.status();
	},

	render: function(data) {
		var view = this;
		var wrap = E('div', { 'class': 'zm-wrap' });
		var cards = E('div', { 'class': 'zm-cards' });
		var logEl = E('pre', { 'class': 'zm-log' });
		var bannerEl = E('div', {});

		function renderCards(d) {
			cards.innerHTML = '';

			var z2Actions = [];
			if (d.zapret2 === 'installed' && d.z2_luci) {
				var web = document.body.classList.contains('zmw-body');
				z2Actions.push(E('a', { 'class': 'cbi-button cbi-button-action', 'href': web ? location.protocol + '//' + location.hostname + '/cgi-bin/luci/' + d.z2_luci : L.url(d.z2_luci),
					'target': web ? '_blank' : null, 'rel': web ? 'noopener' : null, 'title': 'Настройки Zapret2 в LuCI: стратегия, списки, режимы' }, 'Перейти в настройки'));
			}
			if (d.zapret2 === 'installed') {
				z2Actions.push(E('button', {
					'class': 'cbi-button cbi-button-remove',
					'click': function() {
						zm.dialog({ title: 'Удалить Zapret2?', danger: true, okText: 'Удалить Zapret2',
							blocks: [ { type: 'list', title: 'Что произойдёт', items: [
								'Zapret2 остановится, его правила файрвола снимутся',
								'Пакеты и настройки удалятся',
								'Задания Zapret2 уберутся из расписания'
							] }, { type: 'note', kind: 'warn', text: 'Сайты, которые открывались благодаря Zapret2, перестанут открываться.' } ]
						}).then(function(v) { if (v) view.doAction2('remove'); });
					}
				}, 'Удалить'));
				z2Actions.push(E('button', {
					'class': 'cbi-button',
					'click': function() { view.doAction2(d.zapret2_running ? 'stop' : 'start'); }
				}, d.zapret2_running ? 'Остановить' : 'Запустить'));
				if (d.zapret2_running) z2Actions.push(E('button', {
					'class': 'cbi-button',
					'click': function() { view.doAction2('restart'); }
				}, 'Перезапустить'));
			} else {
				z2Actions.push(E('button', {
					'class': 'cbi-button cbi-button-positive',
					'disabled': (d.zapret === 'installed' && !d.expert) ? '' : null,
					'click': function() { view.doAction2('install'); }
				}, 'Установить'));
			}
			var z2Block = d.zapret2 !== 'installed' && d.zapret === 'installed' && !d.expert;

			if (z2Block) {
				cards.appendChild(zm.blockCard(E('div', { 'class': 'zm-card' }), 'Zapret2', 'Только для архитектуры aarch64_cortex-a53. Несовместим с основным Zapret.', 'Стоит Zapret — он несовместим с Zapret2. Чтобы поставить Zapret2, удалите Zapret.'));
				return;
			}
			var z2Card = E('div', { 'class': 'zm-card' }, [
				E('h3', {}, 'Zapret2'),
				E('div', { 'class': 'zm-row' }, [
					E('span', { 'class': 'zm-label' }, 'Статус'),
					d.zapret2 === 'installed'
						? zm.badge(d.zapret2_running === true, 'запущен', 'остановлен')
						: zm.badge(false, '', 'не установлен')
				]),
				E('p', { 'class': 'zm-hint' }, 'Только для архитектуры aarch64_cortex-a53. Несовместим с основным Zapret.'),
				E('div', { 'class': 'zm-actions' }, z2Actions)
			]);

			cards.appendChild(z2Card);
		}

		renderCards(data);
		wrap.appendChild(cards);
		wrap.appendChild(logEl);
		wrap.appendChild(bannerEl);

		this.logEl = logEl;
		this.bannerEl = bannerEl;
		this.renderCards = renderCards;

		return wrap;
	},

	doAction2: function(action) {
		var view = this;
		if (view.busy2) { zm.toast('Дождитесь завершения текущей операции', 'warning'); return; }
		var job = (action === 'install' || action === 'update') ? 'install_zapret2'
			: (action === 'remove') ? 'remove_zapret2' : null;
		var LABELS = { install: 'Устанавливаем Zapret2', update: 'Обновляем Zapret2', remove: 'Удаляем Zapret2', start: 'Запускаем Zapret2', stop: 'Останавливаем Zapret2', restart: 'Перезапускаем Zapret2' };
		zm.toast(LABELS[action] || 'Выполняем', 'warning');
		if (job) view.busy2 = true;

		zm.zapret2Action(action).then(function(res) {
			if (res && res.error) { view.busy2 = false; zm.toast(res.error, 'error'); return; }
			if (job && res && res.started) {
				zm.pollJob(job, view.logEl, function(ok) {
					view.busy2 = false;
					zm.toast(ok ? 'Готово' : 'Операция завершилась с ошибкой', ok ? 'info' : 'error');
					zm.status().then(function(d) { view.renderCards(d); });
					if (ok && (action === 'install' || action === 'remove')) {
						view.bannerEl.innerHTML = '';
						view.bannerEl.appendChild(action === 'install'
							? zm.refreshBanner('В меню LuCI добавлен пункт Zapret2 — выйдите и зайдите заново, чтобы он открывался.')
							: zm.refreshBanner('Пункт Zapret2 убран из меню LuCI — обновите страницу.', false));
					}
				});
			} else if (res) {
				view.busy2 = false;
				if (action === 'restart') zm.toast(res.zapret2_running ? 'Zapret2 перезапущен' : 'Zapret2 не запустился', res.zapret2_running ? 'info' : 'error');
				view.renderCards(res);
			}
		}).catch(function() { view.busy2 = false; });
	}
});
ZM_INSTALLER_EOF
chmod 0644 '/www/luci-static/resources/view/zapret-manager/zapret2.js'

cat > '/www/luci-static/resources/view/zapret-manager/style.css' << 'ZM_INSTALLER_EOF'
.zm-wrap { display: flex; flex-direction: column; gap: 16px; max-width: 1100px; }

.zm-header { display: flex; align-items: baseline; gap: 10px; margin-bottom: -4px; flex-wrap: wrap; }
.zm-header h2 { margin: 0; font-size: 22px; font-weight: 700; }

.zm-cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 14px; }

.zm-card {
	min-width: 0;
	box-sizing: border-box;
	background: var(--background-color-medium, #fff);
	border: 1px solid rgba(0,0,0,.08);
	border-radius: 12px;
	padding: 18px 20px;
	box-shadow: 0 1px 3px rgba(0,0,0,.05), 0 1px 2px rgba(0,0,0,.04);
	overflow-wrap: break-word;
	transition: box-shadow .15s;
}

html.zm-theme-dark .zm-card {
	background: #1c2128;
	border-color: rgba(255,255,255,.10);
	box-shadow: 0 1px 3px rgba(0,0,0,.25), 0 1px 2px rgba(0,0,0,.2);
}
.zm-card:hover { box-shadow: 0 2px 8px rgba(0,0,0,.08); }

.zm-card h3 { margin: 0 0 12px 0; font-size: 15px; font-weight: 600; display: flex; align-items: center; gap: 8px; }

.zm-row { display: flex; align-items: center; gap: 12px; margin: 7px 0; font-size: 13px; flex-wrap: wrap; }
.zm-row .zm-label { opacity: .65; flex-shrink: 0; }
.zm-row > span:last-child { overflow-wrap: anywhere; }

.zm-badge { display: inline-flex; align-items: center; gap: 6px; padding: 3px 11px; border-radius: 999px; font-size: 12px; font-weight: 600; white-space: nowrap; }
.zm-dot { width: 8px; height: 8px; border-radius: 50%; display: inline-block; flex-shrink: 0; }

.zm-ok    { background: rgba(46,160,67,.12); color: #1a7f37; }
.zm-ok .zm-dot { background: #1a7f37; }
.zm-bad   { background: rgba(207,34,46,.10); color: #cf222e; }
.zm-bad .zm-dot { background: #cf222e; }
.zm-warn  { background: rgba(191,135,0,.12); color: #9a6700; }
.zm-warn .zm-dot { background: #9a6700; }
.zm-off   { background: rgba(110,118,129,.12); color: #57606a; }
.zm-off .zm-dot { background: #57606a; }
html.zm-theme-dark .zm-ok   { background: rgba(63,185,80,.15); color: #3fb950; }
html.zm-theme-dark .zm-ok .zm-dot { background: #3fb950; }
html.zm-theme-dark .zm-bad  { background: rgba(248,81,73,.15); color: #ff7b72; }
html.zm-theme-dark .zm-bad .zm-dot { background: #f85149; }
html.zm-theme-dark .zm-warn { background: rgba(210,153,34,.16); color: #e3b341; }
html.zm-theme-dark .zm-warn .zm-dot { background: #d29922; }
html.zm-theme-dark .zm-off  { background: rgba(139,148,158,.16); color: #a3acb7; }
html.zm-theme-dark .zm-off .zm-dot { background: #8b949e; }
html.zm-theme-dark .zm-tile.zm-active { color: #3fb950; }
html.zm-theme-dark .zm-refresh-banner { color: #e3b341; }

.zm-actions { display: flex; gap: 12px; flex-wrap: wrap; align-items: center; margin: 14px 0; }

.zm-meters { display: flex; flex-direction: column; gap: 13px; padding-top: 7px; }
body:not(.zmw-body) .zm-meter-head { display: flex; justify-content: space-between; align-items: baseline; gap: 12px; font-size: 13px; margin-bottom: 6px; }
body:not(.zmw-body) .zm-meter-label { opacity: .65; }
body:not(.zmw-body) .zm-meter-val { font-weight: 600; font-variant-numeric: tabular-nums; white-space: nowrap; }
body:not(.zmw-body) .zm-meter-bar { height: 6px; border-radius: 6px; background: rgba(110,118,129,.18); overflow: hidden; }
body:not(.zmw-body) .zm-meter-bar i { display: block; height: 100%; border-radius: 6px; background: linear-gradient(90deg, #0969da, #3b8eea); transition: width .6s cubic-bezier(.2,.8,.2,1); }
body:not(.zmw-body) .zm-meter-mid .zm-meter-bar i { background: linear-gradient(90deg, #f59e0b, #fbbf24); }
body:not(.zmw-body) .zm-meter-hi .zm-meter-bar i { background: linear-gradient(90deg, #ef4444, #f87171); }
html.zm-theme-dark body:not(.zmw-body) .zm-meter-bar { background: rgba(255,255,255,.1); }
.zm-actions .cbi-button { margin: 0; }

.zm-grid { display: flex; flex-wrap: wrap; gap: 9px; }
.zm-vcard { container: zmv / inline-size; }
.zm-grid.zm-vgrid { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); }
.zm-grid.zm-vgrid > .zm-tile { min-width: 0; padding-left: 6px; padding-right: 6px; }
@container zmv (min-width: 760px) { .zm-grid.zm-vgrid { grid-template-columns: repeat(10, minmax(0, 1fr)); } }

.zm-tile {
	flex: 0 1 auto;
	min-width: 90px;
	max-width: 100%;
	border: 1px solid rgba(0,0,0,.1);
	border-radius: 9px;
	padding: 10px 16px;
	cursor: pointer;
	text-align: center;
	font-size: 13px;
	line-height: 1.35;
	overflow-wrap: break-word;
	transition: border-color .15s, background .15s, transform .1s;
	background: var(--background-color-low, #fafafa);
}
html.zm-theme-dark .zm-tile:not(.zm-active) {
	background: #22272e;
	border-color: rgba(255,255,255,.12);
}
.zm-tile:hover { border-color: #1a7f37; transform: translateY(-1px); }
.zm-tile.zm-active {
	border-color: #1a7f37; background: rgba(26,127,55,.16);
	font-weight: 700; color: #15803d;
	box-shadow: 0 0 0 2px rgba(26,127,55,.35);
}
.zm-tile.zm-active::before { content: none; }

.zm-log {
	background: #0d1117; color: #e6edf3;
	font-family: ui-monospace, "SF Mono", "Cascadia Code", Consolas, "Liberation Mono", monospace;
	font-size: 13.5px; line-height: 1.7;
	border: 1px solid rgba(255,255,255,.10);
	border-radius: 10px; padding: 16px 18px;
	white-space: pre-wrap; word-break: break-word; overflow-wrap: anywhere;
	max-height: 520px; min-height: 220px;
	overflow-x: hidden; overflow-y: auto;
	margin-top: 14px; display: none;
	box-shadow: inset 0 0 0 1px rgba(0,0,0,.2);
}
.zm-log.zm-show { display: block; }
.zm-term {
	box-sizing: border-box; min-width: 0; overflow: hidden;
	background: #0d1117; color: #8b949e;
	border: 1px solid rgba(255,255,255,.10); border-radius: 10px;
	box-shadow: inset 0 0 0 1px rgba(0,0,0,.2);
}
.zm-term-bar {
	display: flex; align-items: center; gap: 12px;
	height: 38px; padding: 0 16px; box-sizing: border-box;
	border-bottom: 1px solid rgba(255,255,255,.07);
	font-family: ui-monospace, "SF Mono", "Cascadia Code", Consolas, "Liberation Mono", monospace;
	font-size: 12.5px; line-height: 1; color: #8b949e; user-select: none;
}
.zm-term-dots { display: inline-flex; gap: 8px; flex: 0 0 auto; }
.zm-term-dots i { display: block; width: 10px; height: 10px; border-radius: 50%; background: #ff5f57; }
.zm-term-dots i:nth-child(2) { background: #febc2e; }
.zm-term-dots i:nth-child(3) { background: #28c840; }
.zm-term-title { flex: 1 1 auto; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.zm-term-body { padding: 8px 11px 10px; background: inherit; }
.zm-term-frame {
	display: block; width: 100%; border: 0; background: #0d1117;
	height: 480px; height: clamp(320px, calc(100vh - 340px), 780px);
}
@media (max-width: 600px) {
	.zm-term-bar { padding: 0 12px; }
	.zm-term-body { padding: 6px 5px 8px; }
	.zm-term-frame { height: clamp(280px, calc(100vh - 300px), 620px); }
}
.zm-log { scrollbar-width: auto; scrollbar-color: auto; }
.zm-log::-webkit-scrollbar { width: 14px; }
.zm-log::-webkit-scrollbar-track { background: transparent; margin: 8px 0; }
.zm-log::-webkit-scrollbar-thumb { background: rgba(255,255,255,.2); border-radius: 10px; border: 4px solid transparent; background-clip: padding-box; min-height: 40px; }
.zm-log::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,.34); background-clip: padding-box; }
@supports not selector(::-webkit-scrollbar) { .zm-log { scrollbar-width: thin; scrollbar-color: rgba(255,255,255,.25) transparent; } }
.zm-config-editor { scrollbar-width: auto; scrollbar-color: auto; }
.zm-config-editor::-webkit-scrollbar { width: 14px; height: 14px; }
.zm-config-editor::-webkit-scrollbar-button { display: none; }
.zm-config-editor::-webkit-scrollbar-track, .zm-config-editor::-webkit-scrollbar-corner, .zm-config-editor::-webkit-resizer { background: transparent; }
.zm-config-editor::-webkit-scrollbar-track { margin: 8px; }
.zm-config-editor::-webkit-scrollbar-thumb { background: rgba(255,255,255,.2); border-radius: 10px; border: 4px solid transparent; background-clip: padding-box; min-height: 40px; }
.zm-config-editor::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,.34); background-clip: padding-box; }
@supports not selector(::-webkit-scrollbar) { .zm-config-editor { scrollbar-width: thin; scrollbar-color: rgba(255,255,255,.25) transparent; } }
.zm-log:empty::before { content: "Ожидание вывода…"; opacity: .4; }
.zm-log-bar { position: sticky; top: 16px; height: 0; z-index: 3; }
.zm-log-min {
	position: absolute; right: -8px; top: -8px; width: 30px; height: 24px; padding: 0; margin: 0;
	border: 1px solid rgba(255,255,255,.14); border-radius: 7px; background: rgba(255,255,255,.06);
	color: #c9d1d9; font: 700 13px/1 ui-monospace, Consolas, monospace; cursor: pointer;
	display: flex; align-items: center; justify-content: center; transition: background .15s, color .15s;
}
.zm-log-min:hover { background: rgba(255,255,255,.16); color: #fff; }
.zm-log.zm-log-collapsed { min-height: 0; max-height: none; overflow: hidden; padding-right: 48px; }
.zm-log.zm-log-collapsed > div:not(.zm-log-bar):not(:last-child) { display: none; }
.zm-log.zm-log-collapsed > div:last-child { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

.zm-config-editor {
	width: 100%; box-sizing: border-box; min-height: 420px;
	background: #0d1117; color: #e6edf3;
	font-family: ui-monospace, "SF Mono", "Cascadia Code", Consolas, "Liberation Mono", monospace;
	font-size: 13px; line-height: 1.6;
	border: 1px solid rgba(255,255,255,.1); border-radius: 10px;
	padding: 14px 16px; margin: 10px 0;
	white-space: pre; overflow: auto; resize: vertical;
}
html.zm-theme-dark .zm-config-editor { border-color: rgba(255,255,255,.14); }

.zm-lists-intro { margin: 0 0 12px; }
.zm-list-card { padding: 0; margin-bottom: 12px; overflow: hidden; }
.zm-list-head { display: flex; align-items: center; gap: 14px; padding: 14px 20px; cursor: pointer; user-select: none; outline: none; transition: background .15s; }
@media (hover: hover) { .zm-list-head:hover { background: rgba(127,127,127,.06); } }
.zm-list-head:focus-visible { box-shadow: inset 0 0 0 2px rgba(34,158,217,.55); }
.zm-list-chev { flex: 0 0 22px; width: 22px; height: 22px; display: inline-flex; align-items: center; justify-content: center; border-radius: 6px; background: rgba(127,127,127,.12); font-size: 16px; font-weight: 700; line-height: 1; transition: transform .2s; }
.zm-list-open .zm-list-chev { transform: rotate(90deg); }
.zm-list-titles { flex: 1 1 auto; min-width: 0; }
.zm-list-title { font-size: 15px; font-weight: 600; line-height: 1.3; }
.zm-list-path { margin-top: 3px; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 12px; opacity: .6; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.zm-list-count { flex: 0 0 auto; min-width: 92px; justify-content: center; }
.zm-list-body { padding: 4px 20px 18px; border-top: 1px solid rgba(127,127,127,.15); }
.zm-list-hint { margin: 12px 0 10px; }
textarea.zm-list-editor { display: block; width: 100%; box-sizing: border-box; min-height: 320px; resize: vertical; white-space: pre; overflow-wrap: normal; overflow-x: auto; tab-size: 4; }
.zm-list-actions { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; margin-top: 12px; }
.zm-list-actions .cbi-button { margin: 0; }
.zm-list-dirty { flex: 0 0 auto; font-size: 12px; white-space: nowrap; font-weight: 600; color: #9a6700; display: inline-flex; align-items: center; gap: 6px; }
.zm-list-dirty::before { content: ""; width: 8px; height: 8px; border-radius: 50%; background: currentColor; }
html.zm-theme-dark .zm-list-dirty { color: #d29922; }
@media (max-width: 600px) {
	.zm-list-head { padding: 12px 14px; gap: 10px; }
	.zm-list-body { padding: 4px 14px 14px; }
	.zm-list-count { min-width: 0; }
	.zm-list-actions .cbi-button { flex: 1 1 100%; }
	.zm-list-dirty { font-size: 0; gap: 0; }
}
@media (max-width: 600px) {
	.zm-config-editor { font-size: 16px; min-height: 320px; }
}

.zm-log-arrow { color: #56d4dd; font-weight: 700; }
.zm-log-msg-info { color: #e3c04a; }
.zm-log-msg-ok { color: #3fb950; font-weight: 600; }
.zm-log-msg-error { color: #ff7b72; font-weight: 600; }
.zm-log-msg-warn { color: #ffa657; }
.zm-log-code { color: #8b949e; }

.zm-hint { font-size: 12px; opacity: .65; margin-top: 6px; line-height: 1.5; overflow-wrap: break-word; }

.zm-refresh-banner {
	display: flex; align-items: center; justify-content: space-between; gap: 14px;
	background: rgba(191,135,0,.12); border: 2px solid rgba(191,135,0,.35);
	color: #9a6700; border-radius: 12px; padding: 16px 20px; font-size: 15px; font-weight: 500;
	margin-top: 12px;
}
.zm-refresh-banner button { flex-shrink: 0; }
.zm-refresh-banner:not(.zm-reboot-banner) { flex-wrap: wrap; }
.zm-refresh-banner:not(.zm-reboot-banner) > span:first-child { flex: 1 1 0; min-width: min(260px, 100%); line-height: 1.45; }
@media (max-width: 640px) {
	.zm-refresh-banner:not(.zm-reboot-banner) { padding: 12px 14px; font-size: 14px; gap: 10px 12px; }
	.zm-refresh-banner:not(.zm-reboot-banner) > span:first-child { flex-basis: 100%; }
	.zm-refresh-banner:not(.zm-reboot-banner) > .cbi-button { flex: 1 1 auto; margin: 0; min-width: 0; white-space: normal; }
	.zm-refresh-banner:not(.zm-reboot-banner) > .cbi-button.zm-cl-link { flex: 0 0 auto; }
}

#zm-toast-container {
	position: fixed; top: 20px; right: 20px; z-index: 10000;
	display: flex; flex-direction: column; gap: 14px;
	max-width: 520px; overflow: hidden; pointer-events: none;
}
#zm-toast-container > .zm-toast { pointer-events: auto; flex-shrink: 0; }
.zm-toast {
	display: flex; align-items: flex-start; gap: 14px;
	background: #1c2128; color: #e6edf3;
	padding: 24px 28px; border-radius: 16px;
	box-shadow: 0 10px 40px rgba(0,0,0,.4);
	font-size: 18px; line-height: 1.5; font-weight: 500; cursor: pointer;
	opacity: 0; transform: translateX(24px);
	transition: opacity .22s ease, transform .22s ease;
	border-left: 6px solid #1a7f37;
}
.zm-toast-show { opacity: 1; transform: translateX(0); }
.zm-toast-error { border-left-color: #cf222e; }
.zm-toast-warning { border-left-color: #9a6700; }
.zm-toast-icon { flex-shrink: 0; width: 10px; height: 10px; border-radius: 50%; background: currentColor; align-self: center; }
.zm-toast-info .zm-toast-icon { color: #3fb950; }
.zm-toast-error .zm-toast-icon { color: #ff7b72; }
.zm-toast-warning .zm-toast-icon { color: #e3b341; }
.zm-toast-text { overflow-wrap: anywhere; }
.zm-toast-busy { border-left-color: #1aa3ff; cursor: default; }
.zm-toast-spin { flex-shrink: 0; align-self: center; width: 18px; height: 18px; box-sizing: border-box; border-radius: 50%; border: 2px solid rgba(255,255,255,.25); border-top-color: #58b7ff; animation: zm-savebar-spin .8s linear infinite; }
html.zm-theme-dark .zm-toast-spin { border-color: rgba(0,0,0,.14); border-top-color: #0b72d1; }
.zm-toast-main, .zm-toast-sub { display: block; }
.zm-toast-sub { margin-top: 2px; font-size: .82em; font-weight: 500; opacity: .72; }
html.zm-theme-dark .zm-toast {
	background: #ffffff; color: #1f2328;
	box-shadow: 0 12px 44px rgba(0,0,0,.6), 0 0 0 1px rgba(255,255,255,.1);
}
html.zm-theme-dark .zm-toast-info .zm-toast-icon { color: #1a7f37; }
html.zm-theme-dark .zm-toast-error .zm-toast-icon { color: #cf222e; }
html.zm-theme-dark .zm-toast-warning .zm-toast-icon { color: #9a6700; }

.zm-current-banner {
	display: flex; align-items: center; gap: 10px; flex-wrap: wrap;
	background: rgba(26,127,55,.07); border: 1px solid rgba(26,127,55,.22);
	border-radius: 10px; padding: 10px 16px; font-size: 13px; margin-bottom: 4px;
}
.zm-current-banner b { font-weight: 700; }
.zm-current-banner.zm-current-empty {
	background: rgba(110,118,129,.08); border-color: rgba(110,118,129,.2);
}
.zm-current-banner.zm-current-top { margin: 0 0 10px; }

.bt-cols { display: grid; grid-template-columns: 1fr 1fr; column-gap: 44px; }
.bt-col { min-width: 0; }
.bt-col .zm-label { flex: 0 0 170px; }
@media (max-width: 860px) {
	.bt-cols { grid-template-columns: 1fr; }
	.bt-col .zm-label { flex: 0 0 128px; }
}
@media (max-width: 420px) {
	.bt-col .zm-label { flex: 0 0 108px; font-size: 12px; }
}

.cbi-page-actions { display: none !important; }
.zm-svc-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 10px; margin-top: 12px; }
.zm-svc { display: flex; align-items: center; gap: 11px; min-width: 0; padding: 10px 12px; border-radius: 12px; cursor: pointer; user-select: none;
	border: 1px solid rgba(0,0,0,.1); background: var(--background-color-low, #fafafa); transition: border-color .15s, background .15s, transform .1s; }
html.zm-theme-dark .zm-svc { background: #22272e; border-color: rgba(255,255,255,.1); }
.zm-svc:hover { transform: translateY(-1px); border-color: #1aa3ff; }
.zm-svc.zm-svc-on { border-color: rgba(26,163,255,.6); background: rgba(26,163,255,.08); }
.zm-svc-ico { width: 34px; height: 34px; border-radius: 10px; flex-shrink: 0; display: grid; place-items: center; color: #fff; font-weight: 800; font-size: 12.5px; letter-spacing: -.02em; }
.zm-svc-text { display: flex; flex-direction: column; min-width: 0; flex: 1; }
.zm-svc-name { font-weight: 700; font-size: 13.5px; }
.zm-svc-sub { font-size: 11.5px; opacity: .6; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.zm-switch { width: 38px; height: 22px; border-radius: 999px; background: rgba(110,118,129,.35); position: relative; flex-shrink: 0; transition: background .15s; }
.zm-switch > span { position: absolute; top: 3px; left: 3px; width: 16px; height: 16px; border-radius: 50%; background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,.3); transition: left .15s; }
.zm-switch.zm-switch-on { background: #1aa3ff; } .zm-switch.zm-switch-on > span { left: 19px; }
@media (max-width: 600px) {
	.zm-svc-grid { grid-template-columns: 1fr; }
}
.zm-seg { display: inline-flex; padding: 3px; gap: 3px; border-radius: 9px; border: 1px solid rgba(0,0,0,.1); background: var(--background-color-low, #fafafa); }
html.zm-theme-dark .zm-seg { background: #22272e; border-color: rgba(255,255,255,.12); }
.zm-seg-item { padding: 5px 14px; border-radius: 7px; cursor: pointer; font-size: 13px; font-weight: 600; opacity: .7; transition: background .15s, opacity .15s; }
.zm-seg-item:hover { opacity: 1; }
.zm-seg-item.zm-active { opacity: 1; background: #1a7f37; color: #fff; cursor: default; }
.zm-svc { min-height: 58px; box-sizing: border-box; }
.zm-svc-text { overflow: hidden; }
.zm-svc-name { overflow: hidden; display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 2; line-clamp: 2; line-height: 1.25; overflow-wrap: anywhere; }
.zm-svc-text:has(.zm-svc-sub) .zm-svc-name { -webkit-line-clamp: 1; line-clamp: 1; }
.zm-svc-grid + .zm-hint, .zm-svc-groupwrap + .zm-hint { margin-top: 12px; }
.zm-svc-groupwrap { margin-top: 12px; }
.zm-svc-groupwrap > div:last-child > .zm-svc-grid { margin-top: 10px; }
@media (max-width: 600px) { .zm-svc-grid { gap: 8px; } .zm-svc { min-height: 50px; padding: 8px 10px; gap: 10px; } .zm-svc-ico { width: 30px; height: 30px; border-radius: 9px; font-size: 11.5px; } }
.zm-svc-group { width: 100%; }
.zm-svc-chev { display: inline-block; font-size: 20px; line-height: 1; opacity: .55; transition: transform .15s; }
.zm-svc-open .zm-svc-chev { transform: rotate(90deg); }
@keyframes zmFindFade { from { opacity: 0; } to { opacity: 1; } }
@media (max-width: 600px) { .zm-seg { display: flex; flex-wrap: wrap; max-width: 100%; box-sizing: border-box; } .zm-seg-item { white-space: nowrap; max-width: 100%; overflow: hidden; text-overflow: ellipsis; box-sizing: border-box; } }
.zm-log-wait { color: #e3c04a; font-weight: 600; white-space: pre-wrap; }
.zm-badge.zm-sx-info { background: rgba(59,130,246,.14); color: #2563eb; }
html.zm-theme-dark .zm-badge.zm-sx-info { background: rgba(88,166,255,.16); color: #79c0ff; }
.zm-sx-info .zm-dot { background: currentColor; }
.zm-sysline { display: flex; align-items: center; flex-wrap: wrap; gap: 6px 8px; margin-top: 12px; padding-top: 12px; border-top: 1px solid rgba(127,127,127,.18); }
.zm-sysline > .zm-label { flex: 0 0 auto; margin-right: 6px; }
.zm-sysline .zm-badge { cursor: pointer; user-select: none; transition: filter .15s ease, transform .15s ease; }
.zm-sysline .zm-badge:hover { filter: brightness(.94); transform: translateY(-1px); }
.zm-sysline .zm-badge:focus-visible { outline: 2px solid currentColor; outline-offset: 2px; }
html.zm-theme-dark .zm-sysline .zm-badge:hover { filter: brightness(1.18); }
.zm-chips { display: flex; flex-wrap: wrap; gap: 6px; }
.zm-chip { display: inline-flex; align-items: center; gap: 6px; padding: 3px 10px; border-radius: 999px; font-size: 12px; font-weight: 600; background: rgba(110,118,129,.14); }
.zm-chip .zm-dot { width: 7px; height: 7px; background: currentColor; }
.zm-chip-ok { background: rgba(46,160,67,.12); color: #1a7f37; }
.zm-chip-bad { background: rgba(207,34,46,.10); color: #cf222e; }
.zm-tt-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
@media (max-width: 800px) { .zm-tt-grid { grid-template-columns: 1fr; } }
.zm-tt-tile { border: 1px solid rgba(0,0,0,.1); border-radius: 12px; padding: 12px 14px; background: rgba(0,0,0,.02); display: flex; flex-direction: column; gap: 6px; min-width: 0; }
html.zm-theme-dark .zm-tt-tile { border-color: rgba(255,255,255,.12); background: rgba(255,255,255,.03); }
.zm-tt-tile.zm-tt-active { border-color: #2d5bff; box-shadow: 0 0 0 1px #2d5bff inset; }
.zm-tt-tile .zm-hint { margin: 0; flex: 1; }
.zm-tt-grid .zm-tt-tile.zm-tt-wide { grid-column: 1 / -1; }
.zm-ab-row .zm-label { min-width: 120px; }
.zm-ab-ctl { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
.zm-ab-time { width: auto !important; min-width: 110px; }
.zm-ab-last { margin: 12px 0 4px; padding: 10px 12px; border-radius: 10px; background: rgba(127,127,127,.08); font-size: 13px; line-height: 1.5; }
.zm-ab-last .zm-label { opacity: .7; }
.zm-ab-ok { color: #1a7f37; }
.zm-ab-bad { color: #cf222e; }
.zm-ab-actions { align-items: center; }
.zm-ab-clock { margin: 0 0 0 auto !important; }
@media (max-width: 600px) { .zm-ab-row .zm-label { min-width: 0; width: 100%; } .zm-ab-clock { margin: 0 !important; width: 100%; } }
.zm-tt-head { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
.zm-tt-ctl { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-top: 4px; }
.zm-tt-run { margin-bottom: 12px; }
.zm-tt-tabs { display: flex; align-items: center; justify-content: space-between; gap: 10px; flex-wrap: wrap; }
.zm-tt-tabs .zm-seg { flex-wrap: wrap; }
.zm-tt-btns { display: flex; gap: 8px; flex-wrap: wrap; }
.zm-tt-meta { margin: 10px 0 8px; }
.zm-tt-list { display: flex; flex-direction: column; gap: 6px; }
.zm-tt-row { border: 1px solid rgba(0,0,0,.08); border-radius: 10px; background: rgba(0,0,0,.015); overflow: hidden; }
html.zm-theme-dark .zm-tt-row { border-color: rgba(255,255,255,.1); background: rgba(255,255,255,.025); }
.zm-tt-row-ctrl { border-style: dashed; }
.zm-tt-row-head { display: grid; grid-template-columns: 28px minmax(0, 1.3fr) minmax(60px, 1fr) 64px 100px 18px; align-items: center; gap: 10px; padding: 7px 10px; cursor: pointer; }
.zm-tt-row-head:hover { background: rgba(45,91,255,.06); }
.zm-tt-rank { font-size: 12px; opacity: .55; text-align: right; font-variant-numeric: tabular-nums; }
.zm-tt-name { font-weight: 600; font-size: 13px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.zm-tt-bar { height: 7px; border-radius: 99px; background: rgba(110,118,129,.18); overflow: hidden; }
.zm-tt-fill { display: block; height: 100%; border-radius: 99px; }
.zm-tt-fill.zm-tt-good { background: #2ea043; } .zm-tt-fill.zm-tt-mid { background: #d4a72c; } .zm-tt-fill.zm-tt-bad { background: #e5534b; } .zm-tt-fill.zm-tt-ctrl { background: #8b949e; }
.zm-tt-score { font-weight: 700; font-size: 13px; text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
.zm-tt-score.zm-tt-good, .zm-tt-domhead.zm-tt-good { color: #1a7f37; } .zm-tt-score.zm-tt-mid { color: #9a6700; } .zm-tt-score.zm-tt-bad, .zm-tt-domhead.zm-tt-bad { color: #cf222e; } .zm-tt-score.zm-tt-ctrl { opacity: .7; }
.zm-tt-apply { padding: 3px 10px !important; font-size: 12px !important; min-height: 0 !important; }
.zm-tt-apply { justify-self: end; }
.zm-tt-apply-m { display: none; }
.zm-tt-chev { font-size: 18px; opacity: .5; transition: transform .15s; text-align: center; }
.zm-tt-chev.zm-tt-open { transform: rotate(90deg); } .zm-tt-chev.zm-tt-nochev { visibility: hidden; }
.zm-tt-doms { padding: 4px 12px 12px 48px; display: flex; flex-direction: column; gap: 10px; }
.zm-tt-domhead { font-size: 12px; font-weight: 700; margin-bottom: 6px; }
@media (max-width: 600px) {
	.zm-tt-row-head { grid-template-columns: 22px minmax(0, 1fr) 56px 16px; }
	.zm-tt-bar, .zm-tt-apply, .zm-tt-apply-ph { display: none; }
	.zm-tt-doms { padding-left: 12px; }
	.zm-tt-apply-m { display: block; }
}
.zm-alerts { display: flex; flex-direction: column; gap: 10px; }
.zm-alerts:empty { display: none; }
.zm-wrap > .zm-alerts { margin-bottom: 2px; }.zm-log-step { color: #a5b4c3; white-space: pre-wrap; }
.zm-log-step-ok { color: #3fb950; }
.zm-log-step-bad { color: #ff7b72; font-weight: 600; }
.zm-savebar { position: sticky; bottom: 12px; z-index: 6; display: flex; align-items: center; flex-wrap: wrap; gap: 10px 14px; margin-top: 16px; padding: 12px 14px 12px 16px; border-radius: 14px; background: var(--background-color-high, #fff); color: var(--text-color-highest, #1f2328); border: 1px solid rgba(26,163,255,.45); box-shadow: 0 14px 34px -14px rgba(0,0,0,.35); animation: zm-savebar-in .18s ease-out; }
html.zm-theme-dark .zm-savebar { background: #22272e; color: #e6edf3; border-color: rgba(26,163,255,.5); }
.zm-savebar-dot { width: 9px; height: 9px; border-radius: 50%; background: #f59e0b; box-shadow: 0 0 0 4px rgba(245,158,11,.18); flex-shrink: 0; }
.zm-savebar-text { flex: 1 1 200px; font-weight: 600; font-size: 13.5px; }
.zm-savebar-btns { display: flex; gap: 8px; flex-wrap: wrap; margin-left: auto; }
.zm-savebar-btns .cbi-button { margin: 0; }
@keyframes zm-savebar-in { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: none; } }
@keyframes zm-savebar-spin { to { transform: rotate(360deg); } }
.zm-savebar.zm-savebar-run { border-color: rgba(26,163,255,.65); }
.zm-savebar.zm-savebar-done { border-color: rgba(22,163,74,.55); }
.zm-savebar.zm-savebar-done .zm-savebar-dot { background: #16a34a; box-shadow: 0 0 0 4px rgba(22,163,74,.18); }
@media (prefers-reduced-motion: reduce) { .zm-toast-spin { animation-duration: 1.4s !important; animation-iteration-count: infinite !important; } }
.zm-stopbar { position: fixed; left: 50%; bottom: 18px; transform: translateX(-50%); z-index: 10000; display: flex; align-items: center; gap: 16px; width: min(720px, calc(100vw - 32px)); box-sizing: border-box; padding: 14px 16px 14px 18px; border-radius: 16px; background: #fff5f5; border: 1px solid rgba(220,38,38,.45); color: #7f1d1d; box-shadow: 0 18px 40px -16px rgba(220,38,38,.55); animation: zm-savebar-in .2s ease-out; }
html.zm-theme-dark .zm-stopbar { background: #2a1416; color: #fecaca; border-color: rgba(248,113,113,.5); }
.zm-stopbar-text { display: flex; flex-direction: column; gap: 3px; flex: 1; min-width: 0; font-size: 13px; line-height: 1.35; }
.zm-stopbar-text b { font-size: 14px; }
.zm-stopbar-btn, .zm-stopbar .cbi-button.zm-stopbar-btn { flex-shrink: 0; background: #dc2626 !important; border-color: #dc2626 !important; color: #fff !important; font-weight: 700; margin: 0; }
.zm-stopbar-btn:hover { background: #b91c1c !important; }
@media (max-width: 600px) { .zm-stopbar { flex-direction: column; align-items: stretch; } }
.zm-svc.zm-svc-inc { opacity: .78; border-style: dashed; }
.zm-switch.zm-switch-inc { opacity: .55; }
.zm-swrow { display: flex; align-items: flex-start; gap: 12px; margin: 12px 0; cursor: pointer; }
.zm-swrow .zm-switch { margin-top: 1px; }
.zm-swrow-label { font-weight: 600; }
.zm-swrow .zm-hint { margin: 2px 0 0; }
.zm-swrow.zm-swrow-off { opacity: .5; cursor: not-allowed; }
.zm-block-banner { margin-top: 14px; }
.zm-dock { position: fixed; left: 50%; bottom: 16px; transform: translateX(-50%); z-index: 9999; width: min(860px, calc(100vw - 32px)); display: none; flex-direction: column; gap: 10px; pointer-events: none; }
.zm-dock.zm-dock-on { display: flex; }
.zm-dock > * { pointer-events: auto; }
.zm-dock .zm-savebar { position: static; margin: 0; box-shadow: 0 18px 44px -14px rgba(0,0,0,.45); }
.zm-dock .zm-stopbar { position: static; left: auto; bottom: auto; transform: none; width: auto; }
.zm-dock .zm-refresh-banner { margin: 0; background: #fff6dd; box-shadow: 0 18px 44px -14px rgba(0,0,0,.45); animation: zm-savebar-in .18s ease-out; }
html.zm-theme-dark .zm-dock .zm-refresh-banner { background: #2f2a1c; color: #e3b341; }
.zm-reboot-ov { position: fixed; inset: 0; z-index: 10000; display: flex; align-items: center; justify-content: center; padding: 16px; background: rgba(10,12,18,.55); backdrop-filter: blur(3px); }
.zm-reboot-box { box-sizing: border-box; width: 100%; max-width: 380px; display: flex; flex-direction: column; align-items: center; padding: 28px 26px 22px; border-radius: 20px; text-align: center; background: var(--surface-solid, #ffffff); color: var(--text, #1f2328); box-shadow: 0 24px 70px -20px rgba(0,0,0,.55); }
html.zm-theme-dark .zm-reboot-box { background: var(--surface-solid, #1c2128); color: var(--text, #e6edf3); }
.zm-reboot-spin { width: 44px; height: 44px; box-sizing: border-box; border-radius: 50%; border: 3px solid rgba(26,140,255,.18); border-top-color: #1a8cff; animation: zm-savebar-spin .9s linear infinite; margin-bottom: 16px; }
.zm-reboot-title { margin: 0 0 8px !important; padding: 0 !important; border: 0 !important; font-size: 19px !important; font-weight: 750; line-height: 1.25; letter-spacing: -.01em; }
.zm-reboot-title::before { display: none !important; }
.zm-reboot-text { margin: 0; max-width: 300px; font-size: 14px; line-height: 1.5; opacity: .72; text-wrap: balance; }
.zm-reboot-meta { display: inline-flex; align-items: center; gap: 6px; margin-top: 16px; padding: 5px 12px; border-radius: 999px; background: rgba(127,140,160,.14); font-size: 12.5px; }
.zm-reboot-meta > span:first-child { opacity: .7; }
.zm-reboot-count { font-weight: 700; font-variant-numeric: tabular-nums; min-width: 2.6em; text-align: left; }
@media (prefers-reduced-motion: reduce) { .zm-reboot-spin { animation-duration: 1.6s !important; animation-iteration-count: infinite !important; } }
.zm-refresh-banner.zm-reboot-banner { flex-direction: row !important; align-items: center !important; flex-wrap: nowrap; gap: 12px; padding: 10px 12px 10px 16px; font-size: 13.5px; }
.zm-reboot-banner > span { flex: 1 1 auto; min-width: 0; line-height: 1.4; }
.zm-reboot-banner > .cbi-button { margin: 0; white-space: nowrap; }
.zm-reboot-banner > .zm-banner-x { flex: 0 0 auto; width: 28px; height: 28px; min-width: 0 !important; margin: 0 !important; padding: 0 !important; border: 0 !important; border-radius: 8px; background: transparent !important; box-shadow: none !important; color: inherit !important; font-size: 20px; line-height: 1; opacity: .55; cursor: pointer; }
.zm-reboot-banner > .zm-banner-x:hover { opacity: 1; background: rgba(127,127,127,.18) !important; }
.zm-seg-busy { opacity: .6; pointer-events: none; }
.zm-list-auto { margin: 12px 0 4px; }
.zm-list-nc { margin: 12px 0 0; }
.zm-list-auto-row { margin: 0; }
@media (max-width: 600px) { .zm-list-auto-row { flex-wrap: wrap; } .zm-list-auto-row .zm-label { flex: 0 0 100%; } .zm-list-auto-row .zm-seg { flex-wrap: nowrap; width: 100%; } .zm-list-auto-row .zm-seg-item { flex: 1 1 0; padding: 6px 2px; text-align: center; } }
.zm-ab-log { border: 1px solid rgba(127,127,127,.2); border-radius: 10px; overflow: hidden; font-size: 13px; margin: 8px 0 4px; }
.zm-ab-log-row { display: grid; grid-template-columns: 130px 86px minmax(0, 1fr); gap: 10px; padding: 9px 12px; align-items: baseline; border-top: 1px solid rgba(127,127,127,.12); line-height: 1.45; }
.zm-ab-log-row.zm-ab-log-head { border-top: 0; padding: 8px 12px; background: rgba(127,127,127,.07); font-size: 12px; font-weight: 600; opacity: .75; }
.zm-ab-log-when { opacity: .65; }
.zm-ab-log-kind { font-weight: 600; }
.zm-ab-log-res { overflow-wrap: anywhere; }
.zm-ab-warn { color: #9a6700; }
html.zm-theme-dark .zm-ab-warn { color: #d29922; }
@media (max-width: 600px) {
	.zm-ab-log-row { grid-template-columns: minmax(0, 1fr) auto; gap: 2px 10px; }
	.zm-ab-log-row.zm-ab-log-head { display: none; }
	.zm-ab-log-res { grid-column: 1 / -1; }
}
.zm-au-h { margin: 0 0 4px; font-size: 13px; font-weight: 600; display: flex; align-items: baseline; gap: 8px; flex-wrap: wrap; }
.zm-au-h .zm-hint { margin: 0; font-weight: 400; }
.zm-au-pause { margin: 6px 0 0; padding: 10px 12px; border-radius: 10px; background: rgba(191,135,0,.10); color: #6b4700; font-size: 12px; line-height: 1.5; }
html.zm-theme-dark .zm-au-pause { color: #e3b341; background: rgba(210,153,34,.14); }

.zm-wn-wrap { background: rgba(10,12,18,.45); -webkit-backdrop-filter: blur(8px); backdrop-filter: blur(8px); animation: zmFindFade .15s ease-out; }
html.zm-wn-lock, html.zm-wn-lock body { overflow: hidden; }
.zm-wn-head { display: flex; align-items: center; gap: 12px; margin: 0 0 10px; }
.zm-wn-head h3 { margin: 0 !important; line-height: 1.3; }
.zm-wn { max-width: 560px; max-height: calc(100vh - 32px); max-height: calc(100dvh - 32px); display: flex; flex-direction: column; overflow: hidden; padding: 22px 24px 18px; border-radius: 18px; }
.zm-wn-body { flex: 1 1 auto; min-height: 0; overflow: auto; margin: 0 -6px; padding: 0 6px; overscroll-behavior: contain; }
.zm-wn-foot { flex: 0 0 auto; margin: 0 !important; padding-top: 14px; }
.zm-wn-ico { flex: 0 0 auto; width: 40px; height: 40px; border-radius: 50%; display: grid; place-items: center; margin: 0; background: rgba(217,119,6,.14); color: #d97706; font-size: 21px; font-weight: 800; }
.zm-wn h3 { margin: 0 0 8px !important; font-size: 20px !important; }
.zm-wn-lead { margin: 0 0 10px; font-size: 14px; line-height: 1.5; opacity: .8; }
.zm-wn-list { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 6px; }
.zm-wn-list li { display: grid; grid-template-columns: 16px minmax(0, 1fr); gap: 6px; padding: 8px 12px; border-radius: 12px; background: rgba(110,118,129,.09); font-size: 13.5px; line-height: 1.45; }
.zm-wn-list li i { font-style: normal; font-weight: 800; color: #d97706; text-align: center; }
.zm-wn-list li b { font-size: 13.5px; }
.zm-wn-list li span { opacity: .72; }
.zm-wn-check { display: flex; align-items: flex-start; gap: 10px; margin: 12px 0 2px; padding: 10px 14px; border-radius: 12px; border: 1px dashed rgba(217,119,6,.6); font-size: 13.5px; font-weight: 600; line-height: 1.45; cursor: pointer; }
.zm-wn-check input { width: 18px; height: 18px; margin: 1px 0 0; flex-shrink: 0; cursor: pointer; }
html .zm-wn-check input[type="checkbox"] {
	-webkit-appearance: checkbox; appearance: auto; position: static; display: inline-block;
	width: 18px; height: 18px; min-width: 0; min-height: 0; padding: 0;
	background: none; border: 0; border-radius: 0; box-shadow: none; transform: none; transition: none; flex: 0 0 auto;
}
html .zm-wn-check input[type="checkbox"]::before, html .zm-wn-check input[type="checkbox"]::after { content: none; display: none; }
.zm-wn-gt { margin: 14px 0 6px; font-size: 12px; font-weight: 700; letter-spacing: .04em; text-transform: uppercase; opacity: .6; }
.zm-wn-group:first-child .zm-wn-gt { margin-top: 4px; }
.zm-wn-list li.zm-wn-del i { color: #cf222e; }
.zm-wn-list li.zm-wn-add i { color: #1a7f37; }
.zm-wn-list li.zm-wn-ret i { color: #2563eb; }
.zm-wn-list li.zm-wn-same i { color: #6e7681; }
.zm-wn-list li.zm-wn-same { opacity: .85; }
html.zm-theme-dark .zm-wn-list li.zm-wn-add i { color: #3fb950; }
html.zm-theme-dark .zm-wn-list li.zm-wn-ret i { color: #60a5fa; }
html.zm-theme-dark .zm-wn-list li.zm-wn-del i { color: #f85149; }
.zm-wn-tip { margin: 10px 0 0; padding: 9px 12px; border-radius: 12px; background: rgba(37,99,235,.08); font-size: 13px; line-height: 1.5; }
html.zm-theme-dark .zm-wn-tip { background: rgba(96,165,250,.1); }
.zm-wn .zm-dlg-note { margin-top: 12px; }
.zm-wn-btn-off, .zm-wn-foot .cbi-button[disabled] { opacity: .45; cursor: not-allowed; }
.zm-wn-info .zm-wn-ico { background: rgba(59,130,246,.14); color: #3b82f6; font-family: Georgia, "Times New Roman", serif; font-style: italic; }
.zm-wn-info .zm-wn-list li { grid-template-columns: 20px minmax(0, 1fr); }
.zm-wn-info .zm-wn-list li i { color: #3b82f6; font-weight: 700; }
html.zm-theme-dark .zm-wn-list li { background: rgba(255,255,255,.05); }
@media (max-width: 600px) {
	.zm-wn { padding: 20px 16px 14px; }
	.zm-wn h3 { font-size: 18px !important; }
	.zm-wn-foot .cbi-button { flex: 1 1 auto; }
}
@media (max-width: 600px) {
	.zm-wn.zm-wn { padding: 16px 14px 12px; }
	.zm-wn-head { gap: 10px; margin-bottom: 8px; }
	.zm-wn-ico { width: 32px; height: 32px; font-size: 17px; }
	.zm-wn .zm-wn-head h3 { font-size: 16.5px !important; }
	.zm-wn-lead { font-size: 13px; line-height: 1.45; margin-bottom: 8px; }
	.zm-wn-list { gap: 5px; }
	.zm-wn-list li { padding: 6px 10px; font-size: 12.5px; line-height: 1.4; }
	.zm-wn-list li b { font-size: 12.5px; }
	.zm-wn-tip { margin-top: 8px; padding: 7px 10px; font-size: 12.5px; line-height: 1.4; }
	.zm-wn .zm-dlg-note { margin-top: 8px; font-size: 12.5px; }
	.zm-wn-check { margin-top: 8px; padding: 8px 10px; font-size: 12.5px; line-height: 1.4; }
	.zm-wn-foot { padding-top: 10px; }
	.zm-ts-steps { gap: 6px; }
	.zm-ts-steps li { font-size: 12.5px; line-height: 1.45; grid-template-columns: 24px minmax(0, 1fr); gap: 8px; }
	.zm-ts-steps li::before { width: 22px; height: 22px; font-size: 12px; }
	.zm-ts-cmd { margin-top: 6px; padding: 7px 7px 7px 10px; font-size: 12.5px; }
}
.zm-wn-wrap { z-index: 9990; }
.zm-wn:focus { outline: none; }
.zm-ts { max-width: 580px; }
.zm-ts-where { display: inline; }
.zm-ts-where span + span { margin-left: 4px; }
.zm-ts-where span { padding: 1px 8px; border-radius: 999px; font-size: 12px; font-weight: 600; background: rgba(110,118,129,.14); font-family: ui-monospace, "SF Mono", Consolas, monospace; }
.zm-ts-steps { counter-reset: zmts; list-style: none; margin: 4px 0 0; padding: 0; display: flex; flex-direction: column; gap: 9px; }
.zm-ts-steps li { counter-increment: zmts; display: grid; grid-template-columns: 28px minmax(0, 1fr); gap: 10px; align-items: start; font-size: 13.5px; line-height: 1.55; }
.zm-ts-steps li::before { content: counter(zmts); width: 26px; height: 26px; border-radius: 50%; display: grid; place-items: center; font-weight: 700; font-size: 13px; background: rgba(26,163,255,.14); color: #0969da; }
.zm-ts-cmd { display: flex; align-items: center; gap: 10px; margin: 8px 0 2px; padding: 9px 9px 9px 14px; border-radius: 12px; background: #0d1117; color: #e6edf3; font-family: ui-monospace, "SF Mono", "Cascadia Code", Consolas, monospace; font-size: 13.5px; }
.zm-ts-cmd code { flex: 1 1 auto; min-width: 0; overflow-wrap: anywhere; background: none; color: inherit; padding: 0; user-select: all; -webkit-user-select: all; }
.zm-ts-cmd .cbi-button { flex-shrink: 0; margin: 0 !important; }
.zm-kbd { display: inline-block; padding: 0 6px; border-radius: 6px; border: 1px solid rgba(110,118,129,.45); border-bottom-width: 2px; font-weight: 600; font-size: 12px; line-height: 1.6; font-family: inherit; }
.zm-ts .zm-dlg-note { margin-top: 12px; }
html.zm-theme-dark .zm-ts-steps li::before { color: #58a6ff; }
@media (max-width: 600px) { .zm-ts-cmd { flex-wrap: wrap; } .zm-ts-cmd .cbi-button { flex: 1 1 100%; } }
.zm-dlg-wrap { position: fixed; top: 0; right: 0; bottom: 0; left: 0; z-index: 10000; display: flex; align-items: center; justify-content: center; padding: 16px; background: rgba(0,0,0,.5); }
.zm-dlg { width: 100%; max-width: 540px; max-height: 88vh; overflow: auto; box-shadow: 0 12px 40px rgba(0,0,0,.3); }
.zm-dlg h3 { font-size: 17px; margin-bottom: 8px; }
.zm-dlg-intro { margin: 0 0 6px; font-size: 13px; line-height: 1.5; opacity: .8; white-space: pre-line; overflow-wrap: anywhere; }
.zm-dlg-input { width: 100% !important; box-sizing: border-box; margin: 4px 0 0; }
.zm-dlg-title { margin: 16px 0 6px; font-size: 13px; font-weight: 600; }
.zm-dlg-list { margin: 0; padding-left: 20px; font-size: 13px; line-height: 1.6; }
.zm-dlg-note { margin: 12px 0 0; padding: 9px 12px; border-radius: 10px; font-size: 12.5px; line-height: 1.5; background: rgba(110,118,129,.12); }
.zm-dlg-note-warn { background: rgba(191,135,0,.14); color: #9a6700; }
.zm-dlg-note-bad { background: rgba(207,34,46,.10); color: #cf222e; }
.zm-dlg-opt { display: flex; align-items: flex-start; gap: 11px; margin: 7px 0; padding: 10px 12px; border: 1px solid rgba(110,118,129,.3); border-radius: 10px; cursor: pointer; transition: border-color .15s, background .15s; }
.zm-dlg-opt:hover { border-color: rgba(26,163,255,.6); }
.zm-dlg-opt.zm-active { border-color: #1aa3ff; background: rgba(26,163,255,.08); cursor: default; }
.zm-dlg-opt.zm-dlg-opt-off { opacity: .5; cursor: not-allowed; }
.zm-dlg-opt .zm-hint { margin: 2px 0 0; }
.zm-dlg-radio { width: 16px; height: 16px; margin-top: 2px; border-radius: 50%; border: 2px solid rgba(110,118,129,.6); flex-shrink: 0; display: flex; align-items: center; justify-content: center; box-sizing: border-box; }
.zm-dlg-opt.zm-active .zm-dlg-radio { border-color: #1aa3ff; }
.zm-dlg-opt.zm-active .zm-dlg-radio > span { width: 8px; height: 8px; border-radius: 50%; background: #1aa3ff; }
.zm-hint.zm-dlg-warn { opacity: 1; color: #9a6700; }
.zm-dlg-actions { justify-content: flex-end; margin: 18px 0 0; }
.zm-dlg-actions.zm-dlg-actions-3 { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.zm-dlg-actions.zm-dlg-actions-3 > .cbi-button { width: 100%; margin: 0; }
.zm-dlg-actions.zm-dlg-actions-3 > .cbi-button:first-child { grid-column: 1 / -1; }
@media (max-width: 480px) { .zm-dlg-actions.zm-dlg-actions-3 { grid-template-columns: 1fr; } }
html.zm-theme-dark .zm-dlg-note-warn, html.zm-theme-dark .zm-hint.zm-dlg-warn { color: #e3b341; }
html.zm-theme-dark .zm-dlg-note-bad { color: #ff7b72; }
@media (max-width: 600px) { .zm-dlg-actions .cbi-button { flex: 1 1 auto; } }
.zm-ab-actions { margin: 16px 0 0; }
.zm-ab-warn { color: #9a6700; }
.zm-hint.zm-ab-warn { opacity: 1; }
.zm-hint .zm-ab-warn { color: #6b4700; font-weight: 600; }
html.zm-theme-dark .zm-hint .zm-ab-warn { color: #f0c05a; }
html.zm-theme-dark .zm-ab-warn { color: #e3b341; }

.zm-cl-ver { display: flex; align-items: baseline; gap: 8px; margin: 4px 2px 8px; font-size: 14px; font-weight: 700; }
.zm-cl-ver small { font-size: 12.5px; font-weight: 500; opacity: .6; }
.zm-cl-sec { margin: 12px 2px 6px; font-size: 13px; font-weight: 700; opacity: .85; }
.zm-wn-list + .zm-cl-ver { margin-top: 20px; padding-top: 14px; border-top: 1px solid rgba(127,127,127,.2); }
.zm-cl-cur { align-self: center; font-size: 11px; font-weight: 700; line-height: 1; padding: 4px 8px; border-radius: 999px; background: var(--grad-soft, rgba(37,99,235,.12)); color: var(--a1, #2563eb); }
.zm-wn.zm-cl .zm-wn-list li { grid-template-columns: 86px minmax(0, 1fr); align-items: baseline; gap: 10px; }
.zm-wn.zm-cl .zm-wn-list li.zm-cl-plain { grid-template-columns: minmax(0, 1fr); }
.zm-wn.zm-cl .zm-wn-list li .zm-cl-tag { justify-self: start; opacity: 1; font-size: 11px; font-weight: 700; line-height: 1; padding: 4px 8px; border-radius: 999px; white-space: nowrap; }
.zm-wn.zm-cl .zm-wn-list li .zm-cl-new { background: rgba(22,163,74,.16); color: #15803d; }
.zm-wn.zm-cl .zm-wn-list li .zm-cl-imp { background: rgba(124,58,237,.13); color: #6d28d9; }
.zm-wn.zm-cl .zm-wn-list li .zm-cl-fix { background: rgba(37,99,235,.13); color: #1d4ed8; }
.zm-wn.zm-cl .zm-wn-list li .zm-cl-del { background: rgba(100,116,139,.16); color: #475569; }
html.zm-theme-dark .zm-wn.zm-cl .zm-wn-list li .zm-cl-new { background: rgba(74,222,128,.14); color: #4ade80; }
html.zm-theme-dark .zm-wn.zm-cl .zm-wn-list li .zm-cl-imp { background: rgba(167,139,250,.16); color: #c4b5fd; }
html.zm-theme-dark .zm-wn.zm-cl .zm-wn-list li .zm-cl-fix { background: rgba(96,165,250,.15); color: #93c5fd; }
html.zm-theme-dark .zm-wn.zm-cl .zm-wn-list li .zm-cl-del { background: rgba(148,163,184,.16); color: #cbd5e1; }
.zm-cl-foot { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.zm-cl-all { font-size: 13px; font-weight: 600; color: var(--a1, #2563eb); text-decoration: none; }
.zm-cl-all:hover { text-decoration: underline; }
.zm-cl-btns { display: flex; gap: 8px; }
.zm-cl-foot.zm-cl-foot-solo { justify-content: flex-end; }
.zm-refresh-banner .zm-cl-link, .zm-refresh-banner .zm-cl-link:hover { background: transparent !important; border: 0 !important; box-shadow: none !important; color: var(--a1, #2563eb) !important; font-weight: 600; text-decoration: underline; text-underline-offset: 3px; padding: 0 6px !important; transform: none !important; }
@media (max-width: 600px) {
	.zm-wn.zm-cl .zm-wn-list li { grid-template-columns: minmax(0, 1fr); gap: 4px; }
	.zm-cl-foot { flex-direction: column-reverse; align-items: stretch; }
	.zm-cl-all { text-align: center; padding: 4px 0; }
	.zm-cl-btns .cbi-button { flex: 1 1 0; }
}
html.zm-theme-dark .zm-ts-steps li::before { background: rgba(88,166,255,.16); color: #79c0ff; }
ZM_INSTALLER_EOF
chmod 0644 '/www/luci-static/resources/view/zapret-manager/style.css'


_zmi_say "Убираем страницы, исключённые из интерфейса форка"
# Remove only panel assets. Installed services and their configuration stay intact.
for _zm_page in doh awg tailscale steer adblock mixomo system monitor tgproxy forkozz bytetube; do
	rm -f "/www/luci-static/resources/view/zapret-manager/$_zm_page.js"
done
rm -f /www/luci-static/resources/bytetube/common.js \
	/www/luci-static/resources/bytetube/presets.js \
	/www/luci-static/resources/view/bytetube/style.css

rm -f /opt/zapret-manager-luci/netshift.uc /opt/zapret-manager-luci/b64.uc
# Rebuild the component list instead of showing the previous fork's cache.
rm -f /opt/zapret-manager-luci/state/versions.json

_zmi_ok "Страницы LuCI записаны"
rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null || true
ZM_BUILD_ID="$(date +%s)"
{
	echo "$ZM_BUILD_ID"
	for _zm_f in /www/luci-static/resources/zapret-manager/*.js /www/luci-static/resources/view/zapret-manager/*.js /www/luci-static/resources/view/zapret-manager/*.css; do
		[ -f "$_zm_f" ] && echo "${_zm_f#/www/luci-static/resources/}"
	done
} > /www/luci-static/resources/zapret-manager/build.txt.zm-new 2>/dev/null || true
sed -i "s/__ZM_BUILD__/$ZM_BUILD_ID/g" /www/luci-static/resources/zapret-manager/common.js 2>/dev/null || true
mv -f /www/luci-static/resources/zapret-manager/build.txt.zm-new /www/luci-static/resources/zapret-manager/build.txt 2>/dev/null || true
chmod 0644 /www/luci-static/resources/zapret-manager/build.txt 2>/dev/null || true

ZM_RPC_WANT="$(grep -c 'json_add_object' /usr/libexec/rpcd/zapret-manager 2>/dev/null || true)"
_zm_rpcd_ready() {
	ubus -t 5 list zapret-manager >/dev/null 2>&1 || return 1
	_zm_have="$(ubus -v list zapret-manager 2>/dev/null | grep -c '^[[:space:]]*"' || true)"
	[ "$_zm_have" = "$ZM_RPC_WANT" ] || [ "$_zm_have" = 0 ]
}
_zm_rpcd_wait() {
	_zm_i=0
	while [ "$_zm_i" -lt "$1" ]; do
		if _zm_rpcd_ready; then return 0; fi
		sleep 1
		_zm_i=$((_zm_i + 1))
	done
	return 1
}
_zmi_say "Подключаем панель к LuCI"
/etc/init.d/rpcd reload >/dev/null 2>&1 || /etc/init.d/rpcd restart >/dev/null 2>&1 || true
if [ -x /etc/init.d/rpcd ] && command -v ubus >/dev/null 2>&1; then
	if _zm_rpcd_wait 10; then _zmi_ok "LuCI видит панель"
	else
		_zmi_step "LuCI пока не видит панель — перезапускаем службу rpcd"
		/etc/init.d/rpcd restart >/dev/null 2>&1 || true
		if _zm_rpcd_wait 15; then _zmi_ok "LuCI видит панель"
		else _zmi_warn "Служба rpcd не подхватила панель. Если страница покажет «Object not found», выполните: /etc/init.d/rpcd restart"; fi
	fi
fi

_zmi_say "Проверяем пакеты, которые нужны панели"
_zmi_pkg curl "Без него панель не сможет ничего скачивать." || true
_zmi_pkg unzip "Без него не установится Zapret." || true
_zmi_say "Записываем файлы Web UI"


mkdir -p /www/zm
chmod 0755 /www/zm
cat > '/www/zm/app.js' << 'ZM_INSTALLER_EOF'
(function () {
'use strict';

var BUILD = '__ZMW_BUILD__';
var RES = '/luci-static/resources/';
var NULL_SID = '00000000000000000000000000000000';
var K_SID = 'zmw.sid', K_THEME = 'zmw.theme', K_USER = 'zmw.user', K_NOTE = 'zmw.note', K_ANIM = 'zmw.anim', K_NAV = 'zmw.nav';

function store(kind) {
	try { return kind === 'local' ? window.localStorage : window.sessionStorage; } catch (e) { return null; }
}
function sget(k) {
	var v = null;
	try { var s = store('session'); v = s && s.getItem(k); } catch (e) {}
	if (v) return v;
	try { var l = store('local'); v = l && l.getItem(k); } catch (e) {}
	return v || null;
}
function sset(k, v, persist) {
	['session', 'local'].forEach(function (kind) {
		try {
			var s = store(kind); if (!s) return;
			if (v == null || (kind === 'local') !== !!persist) s.removeItem(k);
			else s.setItem(k, v);
		} catch (e) {}
	});
}

var sid = sget(K_SID);

function isNode(x) { return x != null && typeof x === 'object' && typeof x.nodeType === 'number'; }
function isObj(x) { return x != null && typeof x === 'object' && !Array.isArray(x) && !isNode(x); }
function typeOf(x) { return x === null ? 'null' : Array.isArray(x) ? 'array' : typeof x; }

function domAttr(node, attrs) {
	for (var k in attrs) {
		if (!Object.prototype.hasOwnProperty.call(attrs, k)) continue;
		var v = attrs[k];
		if (v == null) continue;
		if (typeof v === 'function') node.addEventListener(k, v);
		else if (typeof v === 'object') node.setAttribute(k, JSON.stringify(v));
		else node.setAttribute(k, v);
	}
}

function domAppend(node, ch) {
	if (Array.isArray(ch)) {
		for (var i = 0; i < ch.length; i++) {
			var c = ch[i];
			if (isNode(c)) node.appendChild(c);
			else if (Array.isArray(c)) domAppend(node, c);
			else if (c != null) node.appendChild(document.createTextNode(String(c)));
		}
	}
	else if (typeof ch === 'function') domAppend(node, ch(node));
	else if (isNode(ch)) node.appendChild(ch);
	else if (ch != null) node.textContent = String(ch);
}

function E(tag, attrs, data) {
	var node;
	if (isNode(tag)) node = tag;
	else if (Array.isArray(tag)) {
		node = document.createDocumentFragment();
		domAppend(node, tag);
		return node;
	}
	else if (typeof tag === 'string' && tag.charAt(0) === '<') {
		var t = document.createElement('template');
		t.innerHTML = tag.trim();
		node = t.content.firstChild;
	}
	else node = document.createElement(tag);
	if (attrs != null && !isObj(attrs)) { data = attrs; attrs = null; }
	if (attrs) domAttr(node, attrs);
	if (data !== undefined) domAppend(node, data);
	return node;
}

function tr(s) { return s; }

var dom = {
	elem: isNode,
	create: E,
	attr: function (n, k, v) { if (isObj(k)) domAttr(n, k); else { var o = {}; o[k] = v; domAttr(n, o); } },
	append: domAppend,
	content: function (n, ch) { while (n.firstChild) n.removeChild(n.firstChild); domAppend(n, ch); return n; },
	parse: function (html) { return E(html); }
};

function extend(Base, props) {
	var C = function () {
		if (typeof this.__init__ === 'function') return this.__init__.apply(this, arguments);
	};
	C.prototype = Object.create(Base.prototype);
	C.prototype.constructor = C;
	for (var k in props) if (Object.prototype.hasOwnProperty.call(props, k)) C.prototype[k] = props[k];
	C.prototype.super = function (name, args) {
		var fn = Base.prototype[name];
		return typeof fn === 'function' ? fn.apply(this, args || []) : undefined;
	};
	C.extend = function (p) { return extend(C, p); };
	C.__zmClass = true;
	return C;
}
function RootClass() {}
var baseclass = { extend: function (p) { return extend(RootClass, p); } };
baseclass.singleton = function (p) { return new (baseclass.extend(p))(); };

var UBUS_ERR = [ 'OK', 'неверная команда', 'неверный аргумент', 'метод не найден', 'объект не найден',
	'нет данных', 'доступ запрещён', 'таймаут', 'не поддерживается', 'неизвестная ошибка', 'нет соединения' ];

var rpcSeq = 0;

function ubus(object, method, params, useSid) {
	var left = 6;
	function go() {
		return ubusOnce(object, method, params, useSid).catch(function (e) {
			if (left-- > 0 && e && e.rpcCode === -32000 && /Object not found/i.test(e.message || ''))
				return new Promise(function (ok) { setTimeout(ok, 1500); }).then(go);
			throw e;
		});
	}
	return go();
}

function sessionAlive(s) {
	function ask() {
		return ubusOnce('session', 'access', { scope: 'ubus', object: 'zapret-manager', 'function': 'status' }, s)
			.then(function (r) { return r[0] === 0 && r[1] && r[1].access === true ? 1 : 0; }, function (e) { return e && e.rpcCode === -32002 ? 0 : -1; });
	}
	return ask().then(function (a) {
		if (a === 1) return true;
		return new Promise(function (res) { setTimeout(res, 2500); }).then(ask).then(function (b) { return b !== 0; });
	});
}

function ubusOnce(object, method, params, useSid) {
	var ac = window.AbortController ? new AbortController() : null;
	var tm = ac ? setTimeout(function () { ac.abort(); }, 60000) : 0;
	return fetch('/ubus', {
		method: 'POST',
		signal: ac ? ac.signal : undefined,
		headers: { 'Content-Type': 'application/json' },
		cache: 'no-store',
		credentials: 'omit',
		body: JSON.stringify({
			jsonrpc: '2.0', id: ++rpcSeq, method: 'call',
			params: [ useSid || sid || NULL_SID, object, method, params || {} ]
		})
	}).then(function (r) {
		clearTimeout(tm);
		if (r.status === 404) {
			var e404 = new Error('На роутере не отвечает /ubus — нужен пакет uhttpd-mod-ubus.');
			e404.noUbus = true;
			throw e404;
		}
		return r.json().catch(function () { throw new Error('Некорректный ответ роутера (HTTP ' + r.status + ')'); });
	}).then(function (msg) {
		if (msg && msg.error) {
			var e = new Error(msg.error.message || 'Ошибка RPC');
			e.rpcCode = msg.error.code;
			if (msg.error.code === -32002 && !useSid && sid) {
				var was = sid;
				return sessionAlive(was).then(function (alive) {
					if (!alive && sid === was) { e.authLost = true; authLost(); }
					throw e;
				});
			}
			if (msg.error.code === -32002 && !useSid) { e.authLost = true; authLost(); }
			throw e;
		}
		if (!msg || !Array.isArray(msg.result)) throw new Error('Некорректный ответ ubus');
		if (object === 'zapret-manager' && !/(status|info|health|list|tail|log|latest|version|export|get)/.test(method)) scheduleShellRefresh();
		return msg.result;
	}, function (err) {
		clearTimeout(tm);
		if (err && err.name === 'AbortError') throw new Error('роутер не ответил за 60 секунд');
		throw err;
	});
}

var MEMO_TTL = { 'zapret-manager.system_info': 4000, 'zapret-manager.health': 4000, 'system.info': 3000 }, memoCache = {};
function ubusMemo(obj, method, params) {
	var ttl = MEMO_TTL[obj + '.' + method], k = obj + '.' + method + '.' + sid, now = Date.now(), m = memoCache[k];
	if (!ttl || Object.keys(params).length) return ubus(obj, method, params);
	if (m && now - m.t < ttl) return m.p;
	var p = ubus(obj, method, params);
	memoCache[k] = { t: now, p: p };
	p.catch(function () { if (memoCache[k] && memoCache[k].p === p) delete memoCache[k]; });
	return p;
}

function declare(o) {
	return function () {
		var args = arguments, params = {};
		(o.params || []).forEach(function (p, i) { if (args[i] !== undefined) params[p] = args[i]; });
		return ubusMemo(o.object, o.method, params).then(function (res) {
			var code = res[0];
			var ret = res.length > 1 ? res[1] : res[0];
			if (code !== 0) {
				var text = 'ubus ' + o.object + '.' + o.method + ': ' + (UBUS_ERR[code] || ('код ' + code));
				if (code === 6) toast('Недостаточно прав: ' + o.object + '.' + o.method, 'error');
				if (!o.expect) return code;
				var k0 = Object.keys(o.expect)[0];
				if (k0 === undefined || isObj(o.expect[k0])) return { error: text };
				return o.expect[k0];
			}
			if (o.expect) {
				for (var key in o.expect) {
					if (ret != null && key !== '') ret = ret[key];
					if (ret == null || typeOf(ret) !== typeOf(o.expect[key])) ret = o.expect[key];
					break;
				}
			}
			if (typeof o.filter === 'function') ret = o.filter(ret, params);
			return ret;
		});
	};
}

var rpc = { declare: declare, getSessionID: function () { return sid; }, setSessionID: function (s) { sid = s; } };

function fsCall(method, params, pick) {
	return ubus('file', method, params).then(function (res) {
		if (res[0] !== 0) throw new Error((UBUS_ERR[res[0]] || ('код ' + res[0])) + ' (' + (params.path || params.command || method) + ')');
		var r = res[1] || {};
		return pick ? r[pick] : r;
	});
}

var fs = {
	exec: function (command, params, env) {
		var p = { command: command };
		if (Array.isArray(params)) p.params = params;
		if (isObj(env)) p.env = env;
		return fsCall('exec', p);
	},
	exec_direct: function (command, params) {
		return fs.exec(command, params).then(function (r) { return r.stdout || ''; });
	},
	read: function (path) { return fsCall('read', { path: path }, 'data'); },
	read_direct: function (path) { return fs.read(path); },
	write: function (path, data, mode) { return fsCall('write', { path: path, data: data == null ? '' : String(data), mode: mode }); },
	stat: function (path) { return fsCall('stat', { path: path }); },
	list: function (path) { return fsCall('list', { path: path }, 'entries'); },
	remove: function (path) { return fsCall('remove', { path: path }); }
};

var uciValues = {}, uciChanges = {};
var uci = {
	load: function (confs) {
		var list = Array.isArray(confs) ? confs : [ confs ];
		return Promise.all(list.map(function (c) {
			return ubus('uci', 'get', { config: c }).then(function (res) {
				uciValues[c] = (res[0] === 0 && res[1] && res[1].values) || {};
				return c;
			});
		}));
	},
	unload: function (confs) {
		(Array.isArray(confs) ? confs : [ confs ]).forEach(function (c) { delete uciValues[c]; delete uciChanges[c]; });
	},
	get: function (conf, sec, opt) {
		var ch = uciChanges[conf] && uciChanges[conf][sec];
		if (opt == null) {
			var base = uciValues[conf] && uciValues[conf][sec];
			if (!base && !ch) return null;
			var o = {}, k;
			for (k in base) o[k] = base[k];
			for (k in ch) { if (ch[k] === null) delete o[k]; else o[k] = ch[k]; }
			return o;
		}
		if (ch && Object.prototype.hasOwnProperty.call(ch, opt)) return ch[opt] === null ? null : ch[opt];
		var s = uciValues[conf] && uciValues[conf][sec];
		return s && s[opt] != null ? s[opt] : null;
	},
	get_first: function (conf, type, opt) {
		var vals = uciValues[conf] || {};
		for (var s in vals) if (!type || vals[s]['.type'] === type) return uci.get(conf, s, opt);
		return null;
	},
	set: function (conf, sec, opt, val) {
		uciChanges[conf] = uciChanges[conf] || {};
		uciChanges[conf][sec] = uciChanges[conf][sec] || {};
		uciChanges[conf][sec][opt] = (val == null || val === '') ? null : val;
	},
	unset: function (conf, sec, opt) { uci.set(conf, sec, opt, null); },
	sections: function (conf, type, cb) {
		var vals = uciValues[conf] || {}, out = [];
		Object.keys(vals).forEach(function (s) {
			if (!type || vals[s]['.type'] === type) { out.push(vals[s]); if (cb) cb(vals[s], s); }
		});
		return out;
	},
	changes: function () { return Promise.resolve(uciChanges); },
	save: function () {
		var jobs = [];
		Object.keys(uciChanges).forEach(function (conf) {
			Object.keys(uciChanges[conf]).forEach(function (sec) {
				var ch = uciChanges[conf][sec], sets = {}, dels = [], hasSet = false;
				Object.keys(ch).forEach(function (k) {
					if (ch[k] === null) dels.push(k); else { sets[k] = ch[k]; hasSet = true; }
				});
				if (hasSet) jobs.push(ubus('uci', 'set', { config: conf, section: sec, values: sets }));
				if (dels.length) jobs.push(ubus('uci', 'delete', { config: conf, section: sec, options: dels }));
			});
		});
		var confs = Object.keys(uciChanges);
		uciChanges = {};
		return Promise.all(jobs).then(function () { return confs.length ? uci.load(confs) : []; });
	},
	apply: function () {
		return uci.save().then(function () { return ubus('uci', 'apply', { rollback: false }); });
	}
};

var pollJobs = [], pollTimer = null, pollTickN = 0;
function pollEnsure() {
	if (pollTimer) return;
	pollTimer = setInterval(function () {
		pollTickN++;
		if (document.hidden) return;
		pollJobs.forEach(function (j) {
			if (j.busy || pollTickN % j.interval !== 0) return;
			j.busy = true;
			Promise.resolve().then(j.fn).catch(function () {}).then(function () { j.busy = false; });
		});
	}, 1000);
}
var poll = {
	add: function (fn, interval) {
		pollJobs.push({ fn: fn, interval: Math.max(1, +interval || 5), busy: false });
		pollEnsure();
		return true;
	},
	remove: function (fn) {
		var n = pollJobs.length;
		pollJobs = pollJobs.filter(function (j) { return j.fn !== fn; });
		return n !== pollJobs.length;
	},
	start: function () { pollEnsure(); return true; },
	stop: function () { return true; },
	active: function () { return pollJobs.length > 0; },
	_reset: function () { pollJobs = []; }
};

var modalEl = null;
var ui = {
	changes: { setIndicator: function () {}, renderChangeIndicator: function () {}, init: function () {} },
	addNotification: function (title, content, cls) {
		var txt = (title ? title + ': ' : '') + (isNode(content) ? content.textContent : (content || ''));
		toast(txt, /danger|error/.test(cls || '') ? 'error' : (/warning/.test(cls || '') ? 'warning' : 'info'));
		return null;
	},
	showModal: function (title, children) {
		ui.hideModal();
		modalEl = E('div', { 'class': 'zmw-modal-wrap' }, [
			E('div', { 'class': 'zmw-modal' }, [ title ? E('h3', {}, [ title ]) : null, E('div', {}, children) ])
		]);
		document.body.appendChild(modalEl);
		requestAnimationFrame(function () { modalEl && modalEl.classList.add('zmw-in'); });
		return modalEl;
	},
	hideModal: function () { if (modalEl) { modalEl.remove(); modalEl = null; } },
	createHandlerFn: function (ctx, fn) {
		var args = [].slice.call(arguments, 2);
		if (typeof fn === 'string') fn = ctx[fn];
		return function (ev) { return fn.apply(ctx, args.concat([ ev ])); };
	},
	awaitReconnect: function () { setTimeout(function () { location.reload(); }, 5000); }
};

var ViewBase = extend(RootClass, {
	load: function () {},
	render: function () {},
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,
	addFooter: function () { return E('div'); }
});
var viewMod = { extend: function (p) { return ViewBase.extend(p); } };

var L = {
	env: { resource: RES.replace(/\/$/, ''), sessionid: sid },
	resource: function () { return RES + [].slice.call(arguments).join('/'); },
	url: function () {
		var p = [].slice.call(arguments).join('/').replace(/^\/+/, '');
		if (/(^|\/)logout$/.test(p)) return '/?logout=1' + location.hash;
		return '/cgi-bin/luci/' + p;
	},
	bind: function (fn, self) { var a = [].slice.call(arguments, 2); return function () { return fn.apply(self, a.concat([].slice.call(arguments))); }; },
	isObject: isObj,
	toArray: function (x) { return x == null ? [] : Array.isArray(x) ? x : [ x ]; },
	resolveDefault: function (p, d) { return Promise.resolve(p).catch(function () { return d; }); },
	sortedKeys: function (o) { return Object.keys(o || {}).sort(); },
	hasSystemFeature: function () { return false; },
	raise: function (t, m) { var e = new Error(m || t); e.name = t; throw e; },
	error: function (t, m) { L.raise(t, m); },
	dom: dom, ui: ui, Poll: poll, Class: baseclass,
	require: function (n) { return requireModule(n); }
};
window.L = L;
window.E = E;
window._ = tr;

var BUILTIN = { baseclass: baseclass, rpc: rpc, ui: ui, view: viewMod, fs: fs, uci: uci, poll: poll, dom: dom };
var srcCache = {}, modCache = {};

function modUrl(name) { return RES + name.replace(/\./g, '/') + '.js'; }

function fetchSrc(name) {
	if (!srcCache[name]) {
		srcCache[name] = fetch(modUrl(name) + '?v=' + BUILD, { cache: 'no-cache' }).then(function (r) {
			if (!r.ok) throw new Error('Не удалось загрузить ' + name + ' (HTTP ' + r.status + ')');
			return r.text();
		});
		srcCache[name].catch(function () { delete srcCache[name]; });
	}
	return srcCache[name];
}

var SRC_PATCHES = [
	[ /E\('h2', \{\}, 'Zapret Manager для LuCI и Web'\)/g, "E('h2', {}, 'Zapret Manager')" ],
	[ /выведены из LuCI/g, 'выведены из панели' ],
	[ /(var tabBar = E\('div', \{ 'class': 'zm-actions)'/g, "$1 zmw-tabs'" ]
];

var REQ_RE = /^[ \t]*'require[ \t]+([A-Za-z0-9_.\-\/]+)(?:[ \t]+as[ \t]+([A-Za-z_$][A-Za-z0-9_$]*))?[ \t]*'[ \t]*;?/gm;

function evaluate(name, src) {
	SRC_PATCHES.forEach(function (p) { src = src.replace(p[0], p[1]); });
	var deps = [], m;
	REQ_RE.lastIndex = 0;
	while ((m = REQ_RE.exec(src))) deps.push({ name: m[1], as: m[2] || m[1].split(/[.\/]/).pop() });
	return Promise.all(deps.map(function (d) { return requireModule(d.name); })).then(function (insts) {
		var names = [ 'E', '_', 'N_', 'L' ].concat(deps.map(function (d) { return d.as; }));
		var fn = Function.apply(null, names.concat([ src + '\n//# sourceURL=' + location.origin + modUrl(name) ]));
		return fn.apply(window, [ E, tr, tr, L ].concat(insts));
	});
}

function postPatch(name, inst) {
	if (name === 'zapret-manager.common' && inst) {
		inst.refreshBanner = function () {
			return inst.floatBanner(E('div', { 'class': 'zm-refresh-banner zm-show' }, [
				E('span', {}, 'Состав компонентов изменился — обновите раздел, чтобы увидеть актуальное состояние.'),
				E('button', { 'class': 'cbi-button cbi-button-positive', 'click': function () { refreshShellStatus(); route(true); } }, 'Обновить')
			]));
		};
		var origPoll = inst.pollJob;
		inst.pollJob = function (job, logEl, onDone, onTick) {
			return origPoll.call(this, job, logEl, function (ok) {
				try { if (typeof onDone === 'function') onDone(ok); }
				finally { setTimeout(function () { refreshShellStatus(); refreshMemory(); }, 1000); }
			}, onTick);
		};
		setTimeout(refreshShellStatus, 300);
	}
	return inst;
}

function requireModule(name) {
	if (BUILTIN[name]) return Promise.resolve(BUILTIN[name]);
	if (!modCache[name]) {
		modCache[name] = fetchSrc(name).then(function (src) { return evaluate(name, src); }).then(function (res) {
			return postPatch(name, (typeof res === 'function' && res.__zmClass) ? new res() : res);
		});
		modCache[name].catch(function () { delete modCache[name]; });
	}
	return modCache[name];
}

var ICONS = {
	dashboard: '<rect x="3" y="3" width="7.5" height="9" rx="2"/><rect x="13.5" y="3" width="7.5" height="5.5" rx="2"/><rect x="13.5" y="11.5" width="7.5" height="9.5" rx="2"/><rect x="3" y="15" width="7.5" height="6" rx="2"/>',
	shield: '<path d="M12 3l7.5 3v5.6c0 4.6-3.2 8.4-7.5 9.4-4.3-1-7.5-4.8-7.5-9.4V6L12 3z"/><path d="M8.8 12.2l2.2 2.2 4.3-4.4"/>',
	bolt: '<path d="M13.2 2.8L5 13.5h6.2l-1.1 7.7 8.4-10.9h-6.3l1-7.5z"/>',
	list: '<path d="M8.5 6.5h11.5M8.5 12h11.5M8.5 17.5h11.5"/><circle cx="4.3" cy="6.5" r="1"/><circle cx="4.3" cy="12" r="1"/><circle cx="4.3" cy="17.5" r="1"/>',
	logout: '<path d="M14.5 4h3a2.5 2.5 0 0 1 2.5 2.5v11a2.5 2.5 0 0 1-2.5 2.5h-3"/><path d="M10 16.5L5.5 12 10 7.5M5.5 12H15"/>',
	sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M4.6 4.6l1.4 1.4M18 18l1.4 1.4M2.5 12h2M19.5 12h2M4.6 19.4L6 18M18 6l1.4-1.4"/>',
	moon: '<path d="M20.5 14.2A8.5 8.5 0 0 1 9.8 3.5a8.5 8.5 0 1 0 10.7 10.7z"/>',
	ink: '<rect x="3.5" y="3.5" width="13" height="13" rx="1.5"/><path d="M8 20.5h12.5V8"/>',
	bento: '<rect x="3.5" y="3.5" width="10" height="10" rx="2.5"/><rect x="15.5" y="3.5" width="5" height="10" rx="2"/><rect x="3.5" y="15.5" width="5" height="5" rx="2"/><rect x="10.5" y="15.5" width="10" height="5" rx="2"/>',
	minimal: '<path d="M4 12h16"/>',
	retro: '<rect x="3" y="4" width="18" height="16"/><path d="M3 8.5h18M16 6.2h3"/>',
	depth: '<path d="M12 3l8 4.5v9L12 21l-8-4.5v-9z"/><path d="M12 12l8-4.5M12 12v9M12 12L4 7.5"/>',
	graphite: '<path d="M4.5 17a8 8 0 1 1 15 0"/><path d="M12 13l3.8-3.8"/><circle cx="12" cy="13" r="1.2"/>',
	oled: '<circle cx="12" cy="12" r="8.5"/><path d="M12 3.5a8.5 8.5 0 0 0 0 17z" fill="currentColor"/>',
	stars: '<circle cx="5" cy="7" r="1.6"/><circle cx="12" cy="4.5" r="1.6"/><circle cx="19" cy="9" r="1.6"/><circle cx="8" cy="17" r="1.6"/><circle cx="17" cy="18.5" r="1.6"/><path d="M6.5 7.6l3.9 3M12.6 6l5.6 2.3M9.1 15.8l2.3-4.6M18.4 10.6l-1.1 6.3M9.6 17.4l5.8 1"/><circle cx="12" cy="11" r="1.4"/>',
	matrix: '<path d="M6 3v5M6 12v3M6 19v2M12 3v2M12 9v7M12 20v1M18 3v8M18 15v3"/>',
	palette: '<path d="M12 3a9 9 0 1 0 0 18c1.1 0 1.8-.8 1.8-1.7 0-.5-.2-.9-.5-1.2-.3-.3-.5-.7-.5-1.2 0-.9.8-1.7 1.7-1.7H16a5 5 0 0 0 5-5C21 6.6 17 3 12 3z"/><circle cx="7.5" cy="11" r="1.2"/><circle cx="10.5" cy="7" r="1.2"/><circle cx="15.5" cy="7.5" r="1.2"/>',
	refresh: '<path d="M20 11.5A8 8 0 0 0 5.6 6.8L4 8.5"/><path d="M4 4v4.5h4.5"/><path d="M4 12.5a8 8 0 0 0 14.4 4.7l1.6-1.7"/><path d="M20 20v-4.5h-4.5"/>',
	menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
	close: '<path d="M6 6l12 12M18 6L6 18"/>',
	eye: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
	gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>',
	eyeOff: '<path d="M3 3l18 18"/><path d="M10.6 5.6A10 10 0 0 1 12 5.5c6 0 9.5 6.5 9.5 6.5a17 17 0 0 1-3.1 3.9M6.2 6.9C3.9 8.6 2.5 12 2.5 12S6 18.5 12 18.5c1.7 0 3.2-.5 4.5-1.2"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/>',
	user: '<circle cx="12" cy="8" r="4"/><path d="M4 20.5c1.3-3.8 4.3-5.5 8-5.5s6.7 1.7 8 5.5"/>',
	lock: '<rect x="4.5" y="10.5" width="15" height="10" rx="2.5"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/>',
	arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
	alert: '<path d="M12 3.5l9.5 16.5h-19L12 3.5z"/><path d="M12 10v4.5M12 17.3v.2"/>',
	terminal: '<rect x="3" y="4.5" width="18" height="15" rx="2.2"/><path d="M7 9.5l3 2.5-3 2.5M12.5 15h4.5"/>',
	info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.5"/><path d="M12 7.7v.1"/>',
};

function icon(name, cls) {
	var s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
	s.setAttribute('viewBox', '0 0 24 24');
	s.setAttribute('fill', 'none');
	s.setAttribute('stroke', 'currentColor');
	s.setAttribute('stroke-width', '1.8');
	s.setAttribute('stroke-linecap', 'round');
	s.setAttribute('stroke-linejoin', 'round');
	s.setAttribute('aria-hidden', 'true');
	s.setAttribute('class', 'zmw-i' + (cls ? ' ' + cls : ''));
	s.innerHTML = ICONS[name] || '';
	return s;
}

var logoSeq = 0;
function logo(cls) {
	var id = 'zmwz' + (++logoSeq);
	return E('div', { 'class': 'zmw-logo' + (cls ? ' ' + cls : '') }, [
		E('<svg viewBox="0 0 1250 1250" aria-hidden="true">' +
			'<defs><linearGradient id="' + id + '" x1="0" y1="0" x2="0" y2="1">' +
			'<stop offset="0" stop-color="#00b6ff"/><stop offset="1" stop-color="#0090ff"/>' +
			'</linearGradient></defs>' +
			'<g fill="url(#' + id + ')" stroke="#0a0a0a" stroke-width="22" stroke-linejoin="miter">' +
			'<polygon points="455,170 1072,118 1215,25 688,615 25,1235 735,338 262,383"/>' +
			'<polygon points="1025,462 722,860 1215,800 1005,1022 315,1095"/>' +
			'</g></svg>')
	]);
}

function toast(message, kind, duration) {
	var c = document.getElementById('zm-toast-container');
	if (!c) { c = E('div', { id: 'zm-toast-container' }); document.body.appendChild(c); }
	var el = E('div', { 'class': 'zm-toast zm-toast-' + (kind || 'info') }, [
		E('span', { 'class': 'zm-toast-icon' }),
		E('span', { 'class': 'zm-toast-text' }, [ message ])
	]);
	Array.prototype.slice.call(c.children).forEach(function (o) { if (o !== el && o._zmText === String(message)) o.remove(); });
	el._zmText = String(message);
	c.appendChild(el);
	if (window.zmToastFit) window.zmToastFit();
	requestAnimationFrame(function () { el.classList.add('zm-toast-show'); });
	var hide = function () {
		el.classList.remove('zm-toast-show');
		setTimeout(function () { el.remove(); }, 250);
	};
	el.addEventListener('click', hide);
	setTimeout(hide, duration || (kind === 'error' ? 12000 : 6000));
}

var mqDark = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
var THEMES = [
	{ id: 'micro', name: 'Светлая', ico: 'sun', fonts: 'Onest:wght@400;500;600;700', color: '#f4f5f8' },
	{ id: 'light', name: 'Лёгкая', ico: 'sun' },
	{ id: 'dark', name: 'Тёмная', ico: 'moon', dark: true },
	{ id: 'ink', name: 'Контур', ico: 'ink' },
	{ id: 'bento', name: 'Бенто', ico: 'bento', fonts: 'Onest:wght@400;500;600;700&family=Unbounded:wght@600;800', color: '#efebe4' },
	{ id: 'minimal', name: 'Минимал', ico: 'minimal', fonts: 'IBM+Plex+Sans:wght@300;400;500', color: '#ffffff' },
	{ id: 'retro', name: 'Ретро 98', ico: 'retro', color: '#008080' },
	{ id: 'depth', name: 'Объём 3D', ico: 'depth', dark: true, fonts: 'Onest:wght@400;500;600;700&family=Unbounded:wght@600;800', color: '#0a0e18' },
	{ id: 'graphite', name: 'Графит', ico: 'graphite', dark: true, fonts: 'Space+Grotesk:wght@400;500;700', color: '#141416' },
	{ id: 'oled', name: 'OLED', ico: 'oled', dark: true, fonts: 'Inter:wght@400;500;600;700;800', color: '#000000' },
	{ id: 'matrix', name: 'Матрица', ico: 'matrix', dark: true, fonts: 'Share+Tech+Mono', color: '#000000' }
];
function themeById(id) { return THEMES.filter(function (x) { return x.id === id; })[0]; }
function themePref() { var t = sget(K_THEME); return themeById(t) ? t : 'auto'; }
var fontsFailed = false;
function themeFonts(t) {
	if (fontsFailed || !t || !t.fonts || document.getElementById('zmw-font-' + t.id)) return;
	var l = document.createElement('link'), done = false;
	l.id = 'zmw-font-' + t.id;
	l.rel = 'stylesheet';
	l.media = 'print';
	l.onload = function () { done = true; l.media = 'all'; };
	l.onerror = function () { done = true; fontsFailed = true; l.remove(); };
	l.href = 'https://fonts.googleapis.com/css2?family=' + t.fonts + '&display=swap';
	document.head.appendChild(l);
	setTimeout(function () { if (!done) { fontsFailed = true; l.remove(); } }, 3000);
}
function themeEffective() { var p = themePref(); return p === 'auto' ? 'micro' : p; }
function applyTheme() {
	var t = themeEffective();
	var h = document.documentElement;
	var th = themeById(t) || THEMES[0];
	themeFonts(th);
	h.setAttribute('data-theme', t);
	h.classList.toggle('zm-theme-dark', !!th.dark);
	h.setAttribute('data-zm-theme-checked', '1');
	var mc = document.querySelector('meta[name="theme-color"]');
	if (mc) mc.setAttribute('content', th.color || (t === 'dark' ? '#0a0c12' : t === 'ink' ? '#ffffff' : '#f3f5fa'));
	if (dust) { dust.recolor(); glassReset(); }
	var cur = th;
	Array.prototype.forEach.call(document.querySelectorAll('.zmw-theme-toggle'), function (b) {
		b.innerHTML = '';
		b.appendChild(icon('palette'));
		b.title = 'Тема оформления: ' + cur.name;
		b.setAttribute('aria-label', 'Тема оформления');
		b.setAttribute('aria-haspopup', 'menu');
	});
}
var dust = null;
function animOn() { return sget(K_ANIM) === '1'; }
function dustRgb() {
	var v = '', x = document.createElement('canvas').getContext('2d'), m;
	try { v = getComputedStyle(document.documentElement).getPropertyValue('--a1').trim(); } catch (e) {}
	if (!x) return [ 56, 140, 200 ];
	x.fillStyle = '#388cc8';
	if (v) x.fillStyle = v;
	m = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(x.fillStyle);
	if (m) return [ parseInt(m[1], 16), parseInt(m[2], 16), parseInt(m[3], 16) ];
	m = /(\d+),\s*(\d+),\s*(\d+)/.exec(x.fillStyle);
	return m ? [ +m[1], +m[2], +m[3] ] : [ 56, 140, 200 ];
}
function dustStart() {
	if (dust) return;
	var c = E('canvas', { 'class': 'zmw-dust', 'aria-hidden': 'true' });
	var ctx = c.getContext && c.getContext('2d');
	if (!ctx) return;
	var dots = [], mx = -9999, my = -9999, w = 0, h = 0, raf = 0, rgb = [ 56, 140, 200 ], dk = false;
	function seed() {
		return { x: Math.random() * (w || 1), y: Math.random() * (h || 1), vx: (Math.random() - 0.5) * 0.45, vy: (Math.random() - 0.5) * 0.45, r: 1.3 + Math.random() * 2.3 };
	}
	function size() {
		var d = Math.min(window.devicePixelRatio || 1, 2), n;
		w = window.innerWidth; h = window.innerHeight;
		c.width = Math.round(w * d); c.height = Math.round(h * d);
		ctx.setTransform(d, 0, 0, d, 0, 0);
		n = Math.max(36, Math.min(110, Math.round(w * h / 18000)));
		while (dots.length < n) dots.push(seed());
		if (dots.length > n) dots.length = n;
	}
	function frame() {
		raf = 0;
		if (document.hidden) return;
		ctx.clearRect(0, 0, w, h);
		var i, j, d, dx, dy, dist, pull, base = 'rgba(' + rgb.join(',') + ',', la = dk ? 0.42 : 0.4, da = dk ? 0.8 : 0.78;
		ctx.lineWidth = 1;
		for (i = 0; i < dots.length; i++) {
			d = dots[i];
			dx = mx - d.x; dy = my - d.y;
			dist = Math.sqrt(dx * dx + dy * dy) || 1;
			if (dist < 180) {
				pull = (180 - dist) / 180;
				d.vx += (dx / dist) * pull * 0.08;
				d.vy += (dy / dist) * pull * 0.08;
			}
			d.vx *= 0.985; d.vy *= 0.985;
			if (Math.abs(d.vx) < 0.08) d.vx += (Math.random() - 0.5) * 0.04;
			if (Math.abs(d.vy) < 0.08) d.vy += (Math.random() - 0.5) * 0.04;
			d.x += d.vx; d.y += d.vy;
			if (d.x < -10) d.x = w + 10;
			if (d.x > w + 10) d.x = -10;
			if (d.y < -10) d.y = h + 10;
			if (d.y > h + 10) d.y = -10;
			ctx.beginPath();
			ctx.arc(d.x, d.y, d.r, 0, Math.PI * 2);
			ctx.fillStyle = base + da + ')';
			ctx.fill();
			for (j = i + 1; j < dots.length; j++) {
				dx = dots[j].x - d.x; dy = dots[j].y - d.y;
				if (dx > 120 || dx < -120 || dy > 120 || dy < -120) continue;
				dist = Math.sqrt(dx * dx + dy * dy);
				if (dist < 120) {
					ctx.beginPath();
					ctx.moveTo(d.x, d.y);
					ctx.lineTo(dots[j].x, dots[j].y);
					ctx.strokeStyle = base + ((1 - dist / 120) * la).toFixed(3) + ')';
					ctx.stroke();
				}
			}
		}
		raf = requestAnimationFrame(frame);
	}
	function move(e) { mx = e.clientX; my = e.clientY; }
	function leave() { mx = -9999; my = -9999; }
	function vis() { if (!document.hidden && !raf) raf = requestAnimationFrame(frame); }
	window.addEventListener('pointermove', move, { passive: true });
	window.addEventListener('pointerleave', leave);
	document.addEventListener('mouseleave', leave);
	window.addEventListener('blur', leave);
	window.addEventListener('resize', size);
	document.addEventListener('visibilitychange', vis);
	dust = {
		el: c,
		recolor: function () { rgb = dustRgb(); dk = document.documentElement.classList.contains('zm-theme-dark'); },
		stop: function () {
			if (raf) cancelAnimationFrame(raf);
			raf = 0;
			window.removeEventListener('pointermove', move);
			window.removeEventListener('pointerleave', leave);
			document.removeEventListener('mouseleave', leave);
			window.removeEventListener('blur', leave);
			window.removeEventListener('resize', size);
			document.removeEventListener('visibilitychange', vis);
			if (c.parentNode) c.parentNode.removeChild(c);
			document.documentElement.classList.remove('zm-dust-on');
			glassStop();
			dust = null;
		}
	};
	document.documentElement.classList.add('zm-dust-on');
	glassStart();
	dustPlace();
	size();
	dust.recolor();
	vis();
}
var glass = null;
var GLASS_SKIP = /(^|\s)zm-(badge|switch|dot|chip|ab-chip|seg-item|mon-fill|mon-stackseg|lat|toast|bar|fill)(\s|$)/;
function glassAlpha(bg) {
	var m = /rgba?\(([^)]+)\)/.exec(bg), v;
	if (m) { v = m[1].split(/[\s,\/]+/).filter(Boolean).map(Number); return v.length > 3 ? v[3] : 1; }
	m = /\/\s*([\d.]+)\s*\)$/.exec(bg);
	if (m) return +m[1];
	return /^color\(/.test(bg) ? 1 : 0;
}
function glassOne(el) {
	var cls = typeof el.className === 'string' ? el.className : '', cs, bg, w, h;
	if (el.zmGg === glass.g && el.zmGc === cls) return;
	if (el.hasAttribute('data-zm-glass')) { el.style.removeProperty('background-color'); el.removeAttribute('data-zm-glass'); }
	if (/^(BUTTON|INPUT|SELECT|TEXTAREA|OPTION|CANVAS|IMG|SVG|PATH)$/i.test(el.tagName) || GLASS_SKIP.test(cls)) { el.zmGg = glass.g; el.zmGc = cls; return; }
	w = el.offsetWidth; h = el.offsetHeight;
	if (!w || !h) return;
	el.zmGg = glass.g; el.zmGc = cls;
	if (w < 60 || h < 28 || w * h < 2400) return;
	cs = getComputedStyle(el); bg = cs.backgroundColor;
	if (cs.backgroundImage !== 'none' || glassAlpha(bg) < 0.8) return;
	el.style.setProperty('background-color', 'color-mix(in srgb, ' + bg + ' var(' + (el.classList.contains('zm-active') ? '--zm-glass-on' : '--zm-glass-auto') + ', 60%), transparent)', 'important');
	el.setAttribute('data-zm-glass', '1');
}
function glassScan() {
	if (!glass) return;
	glass.t = 0;
	var v = document.getElementById('zmw-view');
	if (v) Array.prototype.forEach.call(v.querySelectorAll('.zm-card *'), glassOne);
}
function glassKick() { if (glass && !glass.t) glass.t = setTimeout(glassScan, 150); }
function glassClear() {
	Array.prototype.forEach.call(document.querySelectorAll('[data-zm-glass]'), function (el) { el.style.removeProperty('background-color'); el.removeAttribute('data-zm-glass'); });
}
function glassReset() {
	if (!glass) return;
	glass.g++;
	glassClear();
	glassKick();
}
function glassStart() {
	if (glass || !window.MutationObserver) return;
	glass = { t: 0, g: 1, o: new MutationObserver(glassKick) };
	glass.o.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: [ 'class' ] });
	window.addEventListener('resize', glassKick);
	glassKick();
}
function glassStop() {
	if (!glass) return;
	glass.o.disconnect();
	if (glass.t) clearTimeout(glass.t);
	window.removeEventListener('resize', glassKick);
	glass = null;
	glassClear();
}
function dustPlace() {
	if (!dust) return;
	var host = loginEl || document.body;
	if (dust.el.parentNode !== host) host.insertBefore(dust.el, host.firstChild);
}
function dustSync() {
	if (animOn()) dustStart();
	else if (dust) dust.stop();
}
var themeMenuEl = null;
function closeThemeMenu() {
	if (!themeMenuEl) return;
	themeMenuEl.remove();
	themeMenuEl = null;
	themeMenuBtn = null;
	window.removeEventListener('resize', placeThemeMenu);
	document.removeEventListener('click', themeMenuOutside, true);
	document.removeEventListener('keydown', themeMenuKey, true);
}
var themeMenuBtn = null;
function placeThemeMenu() {
	var m = themeMenuEl, b = themeMenuBtn, pad = 8, vw, vh, r, w, top, left;
	if (!m) return;
	vw = document.documentElement.clientWidth || window.innerWidth;
	vh = window.innerHeight;
	r = b && b.isConnected ? b.getBoundingClientRect() : { top: 0, bottom: 56, right: vw - pad };
	m.style.right = 'auto';
	m.style.width = vw <= 480 ? (vw - pad * 2) + 'px' : '';
	w = m.offsetWidth;
	left = vw <= 480 ? pad : Math.min(Math.max(pad, Math.round(r.right - w)), vw - w - pad);
	top = Math.round(r.bottom + 8);
	m.style.left = Math.max(pad, left) + 'px';
	m.style.top = top + 'px';
	m.style.maxHeight = Math.max(200, vh - top - pad) + 'px';
}
function themeMenuOutside(e) { if (themeMenuEl && !themeMenuEl.contains(e.target) && !(e.target.closest && e.target.closest('.zmw-theme-toggle'))) closeThemeMenu(); }
function themeMenuKey(e) { if (e.key === 'Escape') closeThemeMenu(); }
var themeDirty = false;
function themeSave(id) {
	if (!sid || sid === NULL_SID) { themeDirty = true; return; }
	ubus('zapret-manager', 'ui_theme_set', { theme: id }).then(function (r) {
		themeDirty = !(r && r[0] === 0 && r[1] && r[1].ok);
		if (r && r[0] === 6) toast('Тема не сохранилась на роутере — выйдите из панели и войдите снова', 'warning');
	}).catch(function () { themeDirty = true; });
}
function themeSync() {
	fetch('/zm/theme.txt?t=' + Date.now(), { cache: 'no-store', credentials: 'omit' }).then(function (r) { return r.ok ? r.text() : ''; }).then(function (t) {
		t = String(t || '').trim();
		if (themeDirty) return;
		if (!t) { if (sget(K_THEME)) themeSave(sget(K_THEME)); return; }
		if (t !== 'auto' && !themeById(t)) return;
		if (t === themePref() || (t === 'auto' && !sget(K_THEME))) return;
		sset(K_THEME, t === 'auto' ? null : t, true);
		applyTheme();
	}).catch(function () {});
}
function setTheme(id) {
	sset(K_THEME, id, true);
	themeSave(id);
	document.documentElement.classList.add('zmw-theme-anim');
	applyTheme();
	setTimeout(function () { document.documentElement.classList.remove('zmw-theme-anim'); }, 400);
}
if (mqDark && mqDark.addEventListener) mqDark.addEventListener('change', function () { if (themePref() === 'auto') applyTheme(); });
function toggleTheme(ev) {
	var btn = ev && ev.currentTarget;
	if (themeMenuEl) { closeThemeMenu(); return; }
	var cur = themeEffective();
	var items = [ E('div', { 'class': 'zmw-theme-group' }, [ 'Тема оформления' ]) ];
	THEMES.forEach(function (t) { items.push(themeOpt(t, cur)); });
	items.push(animOpt());
	themeMenuEl = E('div', { 'class': 'zmw-theme-menu', 'role': 'menu' }, items);
	function animOpt() {
		var on = animOn();
		var b = E('button', {
			'type': 'button', 'role': 'menuitemcheckbox', 'aria-checked': on ? 'true' : 'false',
			'class': 'zmw-theme-opt zmw-anim-opt' + (on ? ' zmw-anim-on' : ''),
			'title': 'Созвездие на фоне: точки соединяются линиями и тянутся к курсору',
			'click': function (e) {
				e.stopPropagation();
				sset(K_ANIM, animOn() ? '0' : '1', true);
				dustSync();
				b.parentNode.replaceChild(animOpt(), b);
			}
		}, [ icon('stars'), E('span', {}, [ 'Анимация' ]), E('span', { 'class': 'zmw-anim-sw', 'aria-hidden': 'true' }, [ E('i') ]) ]);
		return b;
	}
	function themeOpt(t, cur) {
		return E('button', {
			'type': 'button', 'role': 'menuitemradio', 'aria-checked': t.id === cur ? 'true' : 'false',
			'class': 'zmw-theme-opt' + (t.id === cur ? ' zmw-on' : ''),
			'click': function (e) { e.stopPropagation(); closeThemeMenu(); if (t.id !== cur) setTheme(t.id); }
		}, [ icon(t.ico), E('span', {}, [ t.name ]), E('span', { 'class': 'zmw-theme-mark' }) ]);
	}
	document.body.appendChild(themeMenuEl);
	themeMenuBtn = btn || null;
	placeThemeMenu();
	setTimeout(function () {
		document.addEventListener('click', themeMenuOutside, true);
		document.addEventListener('keydown', themeMenuKey, true);
		window.addEventListener('resize', placeThemeMenu);
	}, 0);
}

var ROUTES = [
	{ id: 'dashboard', title: 'Дашборд', sub: 'Состояние всех компонентов', icon: 'dashboard', group: 'Обзор' },
	{ id: 'strategy', title: 'Zapret', sub: 'Стратегии, тесты, YouTube, игры, Discord и списки', icon: 'shield', group: 'Обход блокировок', dot: 'zapret' },
	{ id: 'zapret2', title: 'Zapret2', sub: 'Установка и управление Zapret2', icon: 'bolt', group: 'Обход блокировок', dot: 'zapret2' },
	{ id: 'hosts', title: 'Hosts', sub: 'Домены в hosts и списки GeoHide', icon: 'list', group: 'Сеть', dot: 'hosts' },
	{ id: 'terminal', title: 'Терминал', sub: 'Командная строка роутера в браузере (ttyd)', icon: 'terminal', group: 'Сеть', dot: 'term' }
];
var ROUTE_BY_ID = {};
ROUTES.forEach(function (r) { ROUTE_BY_ID[r.id] = r; });

function currentRoute() {
	var id = (location.hash || '').replace(/^#\/?/, '').split(/[/?]/)[0];
	return ROUTE_BY_ID[id] ? id : 'dashboard';
}

var root, shell = null, viewEl, titleEl, subEl, navLinks = {}, navDots = {}, deviceEl, updateEl, memEl;

var NAV_LOCK = { dashboard: 1 }, NAV_BUILTIN = { dashboard: 1 };
var navHidden = navParse(sget(K_NAV)), navEdit = null, navSaving = false, navGroups = [], navGear = null, navNav = null, navHealth = null;
function navParse(v) { var o = {}; String(v || '').split(/[\s,]+/).forEach(function (k) { if (/^[a-z0-9_]{1,32}$/.test(k) && !NAV_LOCK[k]) o[k] = 1; }); return o; }
function navList(o) { return ROUTES.map(function (r) { return r.id; }).filter(function (k) { return o[k]; }); }
function navCount() { return navList(navHidden).length; }
function navApply() {
	var edit = !!navEdit, cur = edit ? navEdit : navHidden;
	if (navNav) navNav.classList.toggle('zmw-nav-editing', edit);
	ROUTES.forEach(function (r) {
		var a = navLinks[r.id]; if (!a) return;
		var off = !!cur[r.id];
		a.hidden = !edit && off;
		a.classList.toggle('zmw-nav-off', edit && off);
		if (a._eye) { a._eye.innerHTML = ''; a._eye.appendChild(icon(off ? 'eyeOff' : 'eye')); a._eye.setAttribute('aria-pressed', off ? 'false' : 'true'); a._eye.title = off ? 'Показать в меню' : 'Скрыть из меню'; }
	});
	navGroups.forEach(function (g) { g.el.hidden = !edit && g.ids.every(function (k) { return navHidden[k]; }); });
	if (navGear) {
		var n = navCount();
		navGear.classList.toggle('zmw-on', edit);
		navGear.classList.toggle('zmw-has', n > 0);
		navGear.title = edit ? 'Сохранить меню' : n ? 'Настроить меню · скрыто: ' + n : 'Настроить меню';
		navGear.setAttribute('aria-label', edit ? 'Готово' : 'Настроить меню');
		navGear.setAttribute('aria-expanded', edit ? 'true' : 'false');
	}
}
function navOpen() {
	if (navEdit) { navDone(); return; }
	navEdit = {}; Object.keys(navHidden).forEach(function (k) { navEdit[k] = 1; });
	navApply();
	if (navNav) navNav.scrollTop = 0;
}
function navToggle(id) {
	if (!navEdit || NAV_LOCK[id]) return;
	if (navEdit[id]) delete navEdit[id]; else navEdit[id] = 1;
	navApply();
}
function navUninstalled() {
	if (!navEdit) return;
	var h = navHealth || {}, d = h.dots || {}, n = 0;
	ROUTES.forEach(function (r) {
		if (!r.dot || NAV_BUILTIN[r.id]) return;
		var st = typeof d[r.dot] === 'number' ? d[r.dot] : h[r.dot];
		if (st === 0 && !navEdit[r.id]) { navEdit[r.id] = 1; n++; }
	});
	navApply();
	toast(n ? 'Отмечено неустановленных и невключённых: ' + n + ' — нажмите «Готово»' : (navHealth ? 'Неустановленных разделов нет' : 'Состояние компонентов ещё загружается — попробуйте через пару секунд'), 'info');
}
function navAll() { if (navEdit) { navEdit = {}; navApply(); } }
function navDone() {
	if (!navEdit) return;
	var next = navEdit, was = navList(navHidden).join(' '), now = navList(next).join(' ');
	navEdit = null; navHidden = next;
	sset(K_NAV, now || null, true);
	navApply();
	if (was === now) return;
	navSaving = true;
	ubus('zapret-manager', 'ui_nav_set', { ids: now }).then(function (r) {
		var d = r && r[1];
		if (r && r[0] === 6) throw new Error('нет прав — выйдите из панели и войдите снова');
		if (!r || r[0] !== 0) throw new Error('роутер не ответил (код ' + (r ? r[0] : '?') + ')');
		if (!d || d.error || !d.ok) throw new Error((d && d.error) || 'неизвестный ответ');
		toast(now ? 'Меню сохранено · скрыто: ' + navList(next).length : 'Меню сохранено · показаны все разделы', 'info');
	}).catch(function (e) {
		toast('Меню не сохранилось на роутере: ' + ((e && e.message) || e) + '. В этом браузере оно уже изменено', 'error');
	}).then(function () { navSaving = false; });
}
function navFromHealth(h) {
	navHealth = h;
	if (!h || typeof h.nav_hidden !== 'string' || navEdit || navSaving) return;
	var srv = navList(navParse(h.nav_hidden)).join(' ');
	if (srv === navList(navHidden).join(' ')) return;
	navHidden = navParse(srv); sset(K_NAV, srv || null, true); navApply();
}
document.addEventListener('keydown', function (ev) { if (navEdit && ev.key === 'Escape') { ev.preventDefault(); navDone(); } });
var alertsEl = E('div', { 'class': 'zmw-alerts' }), alertsKey = '';

var termKeep = { host: null, frame: null, src: '' };
var TERM_SHOW = 'margin:0 0 18px', TERM_HIDE = 'margin:0; height:0; overflow:hidden; visibility:hidden; border-width:0; box-shadow:none';

function termHide() { if (termKeep.host) termKeep.host.setAttribute('style', TERM_HIDE); }

function termDrop() {
	if (termKeep.host && termKeep.host.parentNode) termKeep.host.parentNode.removeChild(termKeep.host);
	termKeep.host = null; termKeep.frame = null; termKeep.src = '';
}

function termOpen(src, title) {
	if (!viewEl || !sid || currentRoute() !== 'terminal') return false;
	if (termKeep.frame && termKeep.src !== src) termDrop();
	if (!termKeep.host || termKeep.host.parentNode !== viewEl) {
		termDrop();
		termKeep.frame = E('iframe', { 'class': 'zm-term-frame', 'src': src });
		termKeep.host = E('div', { 'class': 'zmw-term-keep zm-term', 'style': TERM_HIDE }, [
			E('div', { 'class': 'zm-term-bar' }, [
				E('span', { 'class': 'zm-term-dots' }, [ E('i', {}), E('i', {}), E('i', {}) ]),
				E('span', { 'class': 'zm-term-title' }, title || 'ttyd')
			]),
			E('div', { 'class': 'zm-term-body' }, [ termKeep.frame ])
		]);
		termKeep.src = src;
		viewEl.insertBefore(termKeep.host, viewEl.firstChild);
	}
	termKeep.host.setAttribute('style', TERM_SHOW);
	return true;
}

window.zmTermKeep = { open: termOpen, hide: termHide, drop: termDrop };

function viewReset() {
	viewEl.style.minHeight = '';
	var n = viewEl.firstChild, next;
	while (n) { next = n.nextSibling; if (n !== termKeep.host) viewEl.removeChild(n); n = next; }
	viewEl.appendChild(alertsEl);
}

document.addEventListener('click', function (ev) {
	var btn = ev.target && ev.target.closest ? ev.target.closest('#zmw-view .zmw-tabs .cbi-button') : null;
	if (!btn || !viewEl) return;
	var bar = btn.closest('.zmw-tabs'), y0 = bar.getBoundingClientRect().top;
	viewEl.style.minHeight = viewEl.offsetHeight + 'px';
	requestAnimationFrame(function () { requestAnimationFrame(function () {
		var nb = document.contains(bar) ? bar : viewEl.querySelector('.zmw-tabs');
		if (!nb) { viewEl.style.minHeight = ''; return; }
		var target = window.scrollY + nb.getBoundingClientRect().top - y0, vtop = viewEl.getBoundingClientRect().top + window.scrollY;
		viewEl.style.minHeight = '';
		var need = target + window.innerHeight - vtop;
		if (viewEl.offsetHeight < need) viewEl.style.minHeight = Math.ceil(need) + 'px';
		if (Math.abs(window.scrollY - target) > 1) window.scrollTo(0, target);
	}); });
}, true);

function mountAlerts() {
	if (viewEl && alertsEl.parentNode !== viewEl) viewEl.insertBefore(alertsEl, viewEl.firstChild);
	else if (viewEl && viewEl.firstChild !== alertsEl) viewEl.insertBefore(alertsEl, viewEl.firstChild);
}

function renderAlerts(h) {
	var key = (h && h.flow_warn ? 'f' : '') + (h && h.ipv6_warn ? '6' : '') + (h && h.gh_warn ? 'g' : '') + (h && h.reboot_hint ? 'r' + h.reboot_hint : '');
	if (key === alertsKey) return;
	alertsKey = key;
	if (!key) { alertsEl.innerHTML = ''; return; }
	requireModule('zapret-manager.common').then(function(zm) {
		alertsEl.innerHTML = '';
		alertsEl.appendChild(zm.alertBanners(h, function() { alertsKey = '?'; setTimeout(refreshShellStatus, 1500); }));
		mountAlerts();
	}).catch(function() {});
}

function buildShell() {
	var nav = E('nav', { 'class': 'zmw-nav', 'aria-label': 'Разделы' });
	var lastGroup = null;
	function navEdges() {
		var more = nav.scrollHeight - nav.clientHeight > 2;
		nav.classList.toggle('zmw-fade-t', more && nav.scrollTop > 2);
		nav.classList.toggle('zmw-fade-b', more && nav.scrollTop + nav.clientHeight < nav.scrollHeight - 2);
	}
	nav.addEventListener('scroll', navEdges, { passive: true });
	window.addEventListener('resize', navEdges);
	setTimeout(navEdges, 0); setTimeout(navEdges, 600);
	navNav = nav; navGroups = [];
	ROUTES.forEach(function (r) {
		if (r.group !== lastGroup) {
			var gEl = E('div', { 'class': 'zmw-nav-group' }, [ E('span', {}, [ r.group ]) ]);
			if (!navGroups.length) {
				navGear = E('button', { 'class': 'zmw-nav-gear', 'type': 'button', 'aria-label': 'Настроить меню', 'aria-expanded': 'false', 'click': function (ev) { ev.preventDefault(); navOpen(); } }, [ icon('gear'), E('span', { 'class': 'zmw-nav-gear-done' }, [ 'Готово' ]), E('i', {}) ]);
				gEl.appendChild(navGear);
			}
			navGroups.push({ el: gEl, ids: [] });
			nav.appendChild(gEl); lastGroup = r.group;
		}
		navGroups[navGroups.length - 1].ids.push(r.id);
		var dot = r.dot ? E('span', { 'class': 'zmw-nav-dot' }) : null;
		var tail = NAV_LOCK[r.id] ? E('span', { 'class': 'zmw-nav-lock' }, [ 'всегда' ]) : E('span', { 'class': 'zmw-nav-eye', 'role': 'switch', 'aria-label': 'Показывать «' + r.title + '» в меню' });
		var a = E('a', { 'class': 'zmw-nav-item', 'href': '#/' + r.id, 'data-route': r.id }, [
			E('span', { 'class': 'zmw-nav-ico' }, [ icon(r.icon) ]),
			E('span', { 'class': 'zmw-nav-label' }, [ r.title ]),
			dot,
			tail
		]);
		if (!NAV_LOCK[r.id]) a._eye = tail;
		a.addEventListener('click', function (ev) {
			if (navEdit) { ev.preventDefault(); navToggle(r.id); return; }
			closeDrawer();
		});
		navLinks[r.id] = a;
		if (dot) navDots[r.dot] = dot;
		nav.appendChild(a);
	});
	nav.appendChild(E('div', { 'class': 'zmw-nav-editfoot' }, [
		E('button', { 'class': 'zmw-nav-btn zmw-nav-btn-wide', 'type': 'button', 'click': function () { navUninstalled(); } }, [ 'Скрыть неустановленные' ]),
		E('button', { 'class': 'zmw-nav-btn', 'type': 'button', 'click': function () { navAll(); } }, [ 'Показать все' ]),
		E('button', { 'class': 'zmw-nav-btn zmw-nav-btn-done', 'type': 'button', 'click': function () { navDone(); } }, [ 'Готово' ])
	]));
	navApply();

	deviceEl = E('div', { 'class': 'zmw-device' }, [
		E('span', { 'class': 'zmw-device-model' }, [ 'Роутер' ]),
		E('span', { 'class': 'zmw-device-sub' }, [ '' ])
	]);
	updateEl = E('a', { 'class': 'zmw-update', 'href': '#/dashboard', 'hidden': '' }, [ 'Доступно обновление' ]);
	memEl = E('div', { 'class': 'zmw-mem' });

	var side = E('aside', { 'class': 'zmw-side', 'id': 'zmw-side' }, [
		E('div', { 'class': 'zmw-brand' }, [
			logo(),
			E('div', { 'class': 'zmw-brand-text' }, [ E('div', { 'class': 'zmw-brand-name' }, [ 'Zapret ', E('b', {}, [ 'Manager' ]) ]) ]),
			E('button', { 'class': 'zmw-icon-btn zmw-drawer-close', 'type': 'button', 'aria-label': 'Закрыть меню', 'click': closeDrawer }, [ icon('close') ])
		]),
		updateEl,
		nav,
		E('div', { 'class': 'zmw-side-foot' }, [
			deviceEl,
			memEl
		])
	]);

	titleEl = E('h1', { 'class': 'zmw-title' }, [ '' ]);
	subEl = E('div', { 'class': 'zmw-sub' }, [ '' ]);
	viewEl = E('main', { 'class': 'zmw-view', 'id': 'zmw-view' });

	var themeBtn = E('button', { 'class': 'zmw-icon-btn zmw-theme-toggle', 'type': 'button', 'click': toggleTheme });
	var top = E('header', { 'class': 'zmw-top' }, [
		E('button', { 'class': 'zmw-icon-btn zmw-burger', 'type': 'button', 'aria-label': 'Меню', 'click': openDrawer }, [ icon('menu') ]),
		E('div', { 'class': 'zmw-titles' }, [ titleEl, subEl ]),
		E('div', { 'class': 'zmw-top-actions' }, [
			E('button', { 'class': 'zmw-icon-btn', 'type': 'button', 'title': 'Обновить страницу', 'click': function (ev) {
				var b = ev.currentTarget; b.classList.add('zmw-spin'); setTimeout(function () { b.classList.remove('zmw-spin'); }, 700);
				route(true);
			} }, [ icon('refresh') ]),
			themeBtn,
			E('button', { 'class': 'zmw-icon-btn zmw-logout', 'type': 'button', 'title': 'Выйти', 'click': function () { logout(); } }, [ icon('logout'), E('span', {}, [ 'Выйти' ]) ])
		])
	]);

	shell = E('div', { 'class': 'zmw-shell' }, [
		side,
		E('div', { 'class': 'zmw-main' }, [ top, viewEl, E('footer', { 'class': 'zmw-foot' }, [ '' ]) ]),
		E('div', { 'class': 'zmw-scrim', 'click': closeDrawer })
	]);
	root.appendChild(shell);
	applyTheme();
}

function openDrawer() { document.body.classList.add('zmw-drawer-open'); }
function closeDrawer() { if (navEdit) navDone(); document.body.classList.remove('zmw-drawer-open'); }

var callStatus = declare({ object: 'zapret-manager', method: 'status', expect: {} });
var callSysInfo = declare({ object: 'zapret-manager', method: 'system_info', expect: {} });
var callHealth = declare({ object: 'zapret-manager', method: 'health', expect: {} });
var callUpd = declare({ object: 'zapret-manager', method: 'zm_update_status', expect: {} });
var callBoardInfo = declare({ object: 'system', method: 'info', expect: {} });

function parseSize(v) {
	var m = String(v || '').trim().match(/^([\d.,]+)\s*([KMGT]?)i?B?$/i);
	if (!m) return NaN;
	var n = parseFloat(m[1].replace(',', '.'));
	var mul = { '': 1, K: 1024, M: 1048576, G: 1073741824, T: 1099511627776 }[m[2].toUpperCase()];
	return n * mul;
}
function fmtSize(b) {
	if (!isFinite(b)) return '—';
	var u = [ 'Б', 'КБ', 'МБ', 'ГБ', 'ТБ' ], i = 0;
	while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
	return (b >= 100 || i === 0 ? Math.round(b) : b.toFixed(1).replace(/\.0$/, '')) + ' ' + u[i];
}
var memRows = {};
function memInsert(r) {
	var before = null;
	Object.keys(memRows).forEach(function (k) { var o = memRows[k]; if (o !== r && o.el.parentNode && o.order > r.order && (!before || o.order < before.order)) before = o; });
	memEl.insertBefore(r.el, before ? before.el : null);
}
function fmtPair(used, total) {
	var a = fmtSize(used), b = fmtSize(total), ua = a.split(' ')[1], ub = b.split(' ')[1];
	if (ua && ua === ub) return a.split(' ')[0] + ' / ' + b;
	var k = [ 'Б', 'КБ', 'МБ', 'ГБ', 'ТБ' ].indexOf(ub), v = k > 0 && isFinite(used) ? used / Math.pow(1024, k) : NaN;
	if (v >= 0.1) return (v >= 100 ? Math.round(v) : v.toFixed(1).replace(/\.0$/, '')) + ' / ' + b;
	if (isFinite(used) && used >= 10 * 1024) a = a.replace(/\.\d+ /, ' ');
	return a + ' / ' + b;
}
function memFit(v) {
	v.classList.remove('zmw-mem-fit');
	if (v.clientWidth && v.scrollWidth > v.clientWidth) v.classList.add('zmw-mem-fit');
}
function memRow(key, label, used, total) {
	var pct = total > 0 ? Math.max(0, Math.min(100, used / total * 100)) : 0;
	var r = memRows[key];
	if (!r) {
		r = memRows[key] = {
			el: E('div', { 'class': 'zmw-mem-row' }, [
				E('div', { 'class': 'zmw-mem-head' }, [ E('span', { 'class': 'zmw-mem-label' }, [ label ]), E('span', { 'class': 'zmw-mem-val' }) ]),
				E('div', { 'class': 'zmw-mem-bar' }, [ E('i') ])
			])
		};
		r.order = key === 'ram' ? 0 : key === 'flash' ? 1 : 2;
		memInsert(r);
	}
	r.el.querySelector('.zmw-mem-val').textContent = fmtPair(used, total);
	[].forEach.call(memEl.querySelectorAll('.zmw-mem-val'), memFit);
	var bar = r.el.querySelector('i');
	bar.style.width = pct.toFixed(1) + '%';
	r.el.classList.toggle('zmw-mem-hi', pct >= 85);
	r.el.classList.toggle('zmw-mem-mid', pct >= 65 && pct < 85);
	r.el.title = label + ': занято ' + fmtSize(used) + ' из ' + fmtSize(total) + ' (' + Math.round(pct) + '%)';
}
function tempRow(t) {
	var r = memRows.temp;
	if (!r) {
		r = memRows.temp = {
			order: -1,
			el: E('div', { 'class': 'zmw-mem-row' }, [
				E('div', { 'class': 'zmw-mem-head' }, [ E('span', { 'class': 'zmw-mem-label' }, [ 'Температура' ]), E('span', { 'class': 'zmw-mem-val' }) ]),
				E('div', { 'class': 'zmw-mem-bar' }, [ E('i') ])
			])
		};
		memInsert(r);
	}
	r.el.querySelector('.zmw-mem-val').textContent = t + ' °C';
	r.el.querySelector('i').style.width = Math.max(0, Math.min(100, t)).toFixed(0) + '%';
	r.el.classList.toggle('zmw-mem-hi', t >= 80);
	r.el.classList.toggle('zmw-mem-mid', t >= 65 && t < 80);
	r.el.title = 'Температура процессора: ' + t + ' °C';
}

function loadRow(pct) {
	var r = memRows.load;
	if (!r) {
		r = memRows.load = {
			order: -2,
			el: E('div', { 'class': 'zmw-mem-row' }, [
				E('div', { 'class': 'zmw-mem-head' }, [ E('span', { 'class': 'zmw-mem-label' }, [ 'Нагрузка ЦП' ]), E('span', { 'class': 'zmw-mem-val' }) ]),
				E('div', { 'class': 'zmw-mem-bar' }, [ E('i') ])
			])
		};
		memInsert(r);
	}
	pct = Math.max(0, Math.min(100, pct));
	r.el.querySelector('.zmw-mem-val').textContent = pct + '%';
	r.el.querySelector('i').style.width = pct + '%';
	r.el.classList.toggle('zmw-mem-hi', pct >= 90);
	r.el.classList.toggle('zmw-mem-mid', pct >= 70 && pct < 90);
	r.el.title = 'Нагрузка процессора: ' + pct + '%';
}

function applyBoard(i) {
	var m = i && i.memory;
	if (!m || !m.total) return;
	var avail = m.available != null ? m.available : (m.free + (m.buffered || 0) + (m.cached || 0));
	memRow('ram', 'ОЗУ', m.total - avail, m.total);
}
function applySys(i) {
	if (!i || i.error) return;
	var ru = parseSize(i.root_used), rf = parseSize(i.root_free);
	if (isFinite(ru) && isFinite(rf)) memRow('flash', 'Флеш', ru, ru + rf);
	var t = parseFloat(i.cpu_temp);
	if (!isNaN(t)) tempRow(t);
	var cl = parseInt(i.cpu_load, 10);
	if (!isNaN(cl)) loadRow(cl);
}
var sharedSysAt = 0, sharedHealthAt = 0;
window.addEventListener('zm:sysinfo', function (ev) {
	var d = (ev && ev.detail) || {};
	if (!shell || !sid) return;
	sharedSysAt = Date.now();
	if (d.board) applyBoard(d.board);
	if (d.sys) applySys(d.sys);
});
function refreshMemory() {
	if (!shell || !sid) return;
	if (Date.now() - sharedSysAt < 9000) return;
	callBoardInfo().then(applyBoard).catch(function () {});
	callSysInfo().then(applySys).catch(function () {});
}

var statusBusy = false;
var DOT_TEXT = { 1: 'работает', 2: 'ошибка — не работает', 3: 'работает частично', 4: 'установлен, не запущен или не настроен' };
function refreshShellStatus() {
	if (!shell || !sid || statusBusy) return;
	statusBusy = true;
	callHealth().then(function (h) {
		if (h && typeof h.zapret === 'number') return h;
		return callStatus().then(function (d) {
			d = d || {};
			return {
				zapret: d.zapret === 'installed' ? (d.zapret_running ? 1 : 2) : 0,
				zapret2: d.zapret2 === 'installed' ? (d.zapret2_running ? 1 : 2) : 0
			};
		});
	}).then(applyHealth).catch(function () {}).then(function () { statusBusy = false; });
}
function applyHealth(h) {
	if (!h) return;
	navFromHealth(h);
	renderAlerts(h);
	Object.keys(navDots).forEach(function(k) {
		var title = null;
		if (k === 'awg' && h.awg_total) title = 'туннелей работает: ' + (h.awg_up || 0) + ' из ' + h.awg_total;
		else if (k === 'awg' && h.awg === 1) title = 'установлен, туннелей нет';
		else if (k === 'awg' && h.awg === 3) title = 'установлен не полностью — откройте вкладку и нажмите «Доустановить»';
		if (h.dots && h.dots[k] === 4) title = null;
		setDot(navDots[k], h.dots && typeof h.dots[k] === 'number' ? h.dots[k] : h[k], title);
	});
}
window.addEventListener('zm:health', function (ev) {
	var h = ev && ev.detail;
	if (!shell || !sid || !h || typeof h.zapret !== 'number') return;
	sharedHealthAt = Date.now();
	applyHealth(h);
});
function setDot(el, st, title) {
	if (!el) return;
	el.className = 'zmw-nav-dot' + (st === 1 ? ' zmw-on' : st === 2 ? ' zmw-stop' : st === 3 ? ' zmw-part' : st === 4 ? ' zmw-idle' : '');
	el.title = title || DOT_TEXT[st] || '';
}

function loadShellInfo() {
	callSysInfo().then(function (i) {
		if (!i || i.error) return;
		deviceEl.firstChild.textContent = String(i.model || 'Роутер').replace(/\s*\(.*\)\s*$/, '') || i.model;
		deviceEl.title = [ i.model, i.openwrt ? 'OpenWrt ' + i.openwrt : '', i.arch ].filter(Boolean).join('\n');
		deviceEl.children[1].textContent = '';
	}).catch(function () {});
	callUpd().then(applyUpd).catch(function () {});
}
function applyUpd(u) {
	if (!u || u.error || !shell || !updateEl) return;
	var on = !!(u.latest && u.current && u.latest !== u.current && u.newer !== false);
	updateEl.hidden = !on;
	if (on) updateEl.textContent = 'Доступна версия ' + u.latest;
}
window.addEventListener('zm:update', function (ev) { if (sid) applyUpd(ev && ev.detail); });

var shellTimer = null;
var shellRefreshTimer = null;
function scheduleShellRefresh() {
	clearTimeout(shellRefreshTimer);
	shellRefreshTimer = setTimeout(function () { refreshShellStatus(); }, 1200);
}
window.addEventListener('zm:changed', scheduleShellRefresh);

function startShellPolling() {
	if (shellTimer) return;
	shellTimer = setInterval(function () { if (!document.hidden && Date.now() - sharedHealthAt > 25000) refreshShellStatus(); }, 30000);
	setInterval(function () { if (!document.hidden) refreshMemory(); }, 10000);
	setInterval(function () { if (!document.hidden && sid) callUpd().then(applyUpd).catch(function () {}); }, 600000);
}

var routeToken = 0;

function skeleton() {
	return E('div', { 'class': 'zmw-skel-wrap' }, [
		E('div', { 'class': 'zmw-skel zmw-skel-bar' }),
		E('div', { 'class': 'zmw-skel-grid' }, [
			E('div', { 'class': 'zmw-skel zmw-skel-card' }),
			E('div', { 'class': 'zmw-skel zmw-skel-card' }),
			E('div', { 'class': 'zmw-skel zmw-skel-card' })
		]),
		E('div', { 'class': 'zmw-skel zmw-skel-wide' })
	]);
}

function errorCard(err, retry) {
	return E('div', { 'class': 'zmw-error' }, [
		E('div', { 'class': 'zmw-error-ico' }, [ icon('alert') ]),
		E('div', {}, [
			E('h3', {}, [ 'Не удалось открыть страницу' ]),
			E('p', {}, [ (err && err.message) || String(err) ]),
			E('button', { 'class': 'cbi-button cbi-button-positive', 'click': retry }, [ 'Повторить' ])
		])
	]);
}

function navReveal() {
	try {
		var al = navLinks[currentRoute()], nv = al && al.parentNode, pad = 26;
		if (!nv || nv.scrollHeight <= nv.clientHeight || !al.offsetHeight) return;
		var t = al.offsetTop - nv.offsetTop, h = al.offsetHeight;
		if (t - pad < nv.scrollTop) nv.scrollTop = Math.max(0, t - pad);
		else if (t + h + pad > nv.scrollTop + nv.clientHeight) nv.scrollTop = t + h + pad - nv.clientHeight;
	} catch (e) {}
}

function route(force) {
	if (!shell || !sid) return;
	var id = currentRoute();
	var r = ROUTE_BY_ID[id];
	var token = ++routeToken;

	Object.keys(navLinks).forEach(function (k) { navLinks[k].classList.toggle('zmw-active', k === id); });
	navReveal(); setTimeout(navReveal, 400);
	titleEl.textContent = r.title;
	subEl.textContent = r.sub || '';
	subEl.hidden = !r.sub;
	document.title = r.title + ' · Zapret Manager';

	poll._reset();
	ui.hideModal();
	refreshShellStatus();
	termHide();
	viewReset();
	viewEl.appendChild(skeleton());
	if (!force) window.scrollTo(0, 0);

	fetchSrc('view.zapret-manager.' + (r.view || id))
		.then(function (src) { return evaluate('view.zapret-manager.' + (r.view || id), src); })
		.then(function (Cls) {
			if (token !== routeToken) return;
			var v = (typeof Cls === 'function' && Cls.__zmClass) ? new Cls() : Cls;
			if (r.part) v.zmPart = r.part;
			return Promise.resolve(v.load()).then(function (data) {
				if (token !== routeToken) return;
				return Promise.resolve(v.render(data));
			}).then(function (node) {
				if (token !== routeToken || !node) return;
				var page = E('div', { 'class': 'zmw-page' }, [ node ]);
				viewReset();
				viewEl.appendChild(page);
			});
		})
		.catch(function (err) {
			if (token !== routeToken || (err && err.authLost)) return;
			console.error(err);
			viewReset();
			viewEl.appendChild(errorCard(err, function () { route(true); }));
		});
}

var loginEl = null, authLostShown = false;

function matrixRain(c, msg) {
	var x = c.getContext && c.getContext('2d');
	if (!x) return function () {};
	var chars = 'アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン0123456789ZAPRETMANAGER';
	var who = sget(K_USER) || 'root', lines = [ '> follow the white rabbit_', '> knock, knock, ' + who + '_', '> the router has you…_' ];
	var size = 16, drops = [], w = 0, h = 0, li = 0, n = 0, timer = 0;
	function fit() {
		var r = c.getBoundingClientRect(), d = Math.min(window.devicePixelRatio || 1, 2);
		w = Math.max(1, Math.round(r.width)); h = Math.max(1, Math.round(r.height));
		c.width = w * d; c.height = h * d; x.setTransform(d, 0, 0, d, 0, 0);
		x.fillStyle = '#000'; x.fillRect(0, 0, w, h);
		drops = [];
		for (var i = 0; i < Math.ceil(w / size); i++) drops.push(Math.random() * -h / size);
	}
	function step() {
		x.fillStyle = 'rgba(0,0,0,0.08)'; x.fillRect(0, 0, w, h);
		x.font = size + 'px monospace';
		for (var i = 0; i < drops.length; i++) {
			var y = drops[i] * size;
			x.fillStyle = Math.random() > .975 ? '#d8ffe0' : '#00ff41';
			x.fillText(chars.charAt(Math.floor(Math.random() * chars.length)), i * size, y);
			if (y > h && Math.random() > .975) drops[i] = 0;
			drops[i]++;
		}
	}
	function frame() {
		if (!document.body.contains(c)) { stop(); return; }
		if (document.documentElement.getAttribute('data-theme') !== 'matrix' || document.hidden) return;
		if (!w) fit();
		step();
		if (msg && ++n % 64 === 0) { li = (li + 1) % lines.length; msg.textContent = lines[li]; }
	}
	function onResize() { w = 0; }
	function stop() { clearInterval(timer); window.removeEventListener('resize', onResize); }
	window.addEventListener('resize', onResize);
	timer = setInterval(frame, 50);
	return stop;
}

function showLogin(note, noteKind) {
	if (loginEl) return;
	var user = E('input', { 'type': 'text', 'name': 'username', 'autocomplete': 'username', 'autocapitalize': 'off', 'spellcheck': 'false', 'value': sget(K_USER) || 'root', 'required': '' });
	var pass = E('input', { 'type': 'password', 'name': 'password', 'autocomplete': 'current-password', 'placeholder': '••••••••' });
	var eye = E('button', { 'type': 'button', 'class': 'zmw-eye', 'tabindex': '-1', 'aria-label': 'Показать пароль' }, [ icon('eye') ]);
	eye.addEventListener('click', function () {
		var show = pass.type === 'password';
		pass.type = show ? 'text' : 'password';
		eye.innerHTML = ''; eye.appendChild(icon(show ? 'eyeOff' : 'eye'));
		pass.focus();
	});
	var remember = E('input', { 'type': 'checkbox', 'checked': '' });
	var errEl = E('div', { 'class': 'zmw-login-msg' + (note ? ' zmw-show zmw-' + (noteKind || 'info') : '') }, [ note || '' ]);
	var btn = E('button', { 'type': 'submit', 'class': 'zmw-btn-primary' }, [ E('span', {}, [ 'Войти' ]), icon('arrow') ]);

	var mxRain = E('canvas', { 'class': 'zmw-mx-rain', 'aria-hidden': 'true' });
	var mxMsg = E('div', { 'class': 'zmw-mx-msg', 'aria-hidden': 'true' }, [ '> follow the white rabbit_' ]);
	var card = E('form', { 'class': 'zmw-login-card', 'autocomplete': 'on' }, [
		logo('zmw-logo-lg'),
		E('div', { 'class': 'zmw-mx-title' }, [ 'ZAPRET_MANAGER' ]),
		E('p', { 'class': 'zmw-mx-sub' }, [ 'wake up, ' + (sget(K_USER) || 'root') + '… · ' + location.hostname ]),
		E('h1', {}, [ 'Zapret Manager' ]),
		E('p', { 'class': 'zmw-login-sub' }, [ 'Панель управления роутером ', E('b', {}, [ location.hostname ]) ]),
		E('label', { 'class': 'zmw-field' }, [ E('span', { 'class': 'zmw-field-label' }, [ 'Пользователь' ]), E('div', { 'class': 'zmw-input' }, [ icon('user'), user ]) ]),
		E('label', { 'class': 'zmw-field' }, [ E('span', { 'class': 'zmw-field-label' }, [ 'Пароль' ]), E('div', { 'class': 'zmw-input' }, [ icon('lock'), pass, eye ]) ]),
		E('label', { 'class': 'zmw-check' }, [ remember, E('span', { 'class': 'zmw-check-box' }), E('span', {}, [ 'Запомнить на этом устройстве' ]) ]),
		errEl,
		btn,
		E('div', { 'class': 'zmw-login-foot' }, [ 'Логин и пароль те же, что и для LuCI' ])
	]);

	function fail(msg) {
		errEl.className = 'zmw-login-msg zmw-show zmw-error';
		errEl.textContent = msg;
		card.classList.remove('zmw-shake'); void card.offsetWidth; card.classList.add('zmw-shake');
		btn.disabled = false;
		btn.classList.remove('zmw-loading');
	}

	card.addEventListener('submit', function (ev) {
		ev.preventDefault();
		if (btn.disabled) return;
		btn.disabled = true;
		btn.classList.add('zmw-loading');
		errEl.className = 'zmw-login-msg';
		ubus('session', 'login', { username: user.value.trim(), password: pass.value, timeout: 3600 }, NULL_SID).then(function (res) {
			if (res[0] === 6 || !res[1] || !res[1].ubus_rpc_session) { fail('Неверный логин или пароль'); return; }
			var s = res[1].ubus_rpc_session;
			var acl = res[1].acls && res[1].acls.ubus;
			if (acl && !acl['zapret-manager'] && !acl['*']) { fail('У пользователя нет доступа к Zapret Manager'); return; }
			return ubus('zapret-manager', 'status', {}, s).then(function (st) {
				if (st[0] === 3 || st[0] === 4) { fail('rpcd-плагин zapret-manager не найден — переустановите панель'); return; }
				sid = s;
				L.env.sessionid = s;
				sset(K_SID, s, remember.checked);
				sset(K_USER, user.value.trim(), true);
				mxMsg.textContent = '> access granted_';
				closeLogin();
				startApp();
			});
		}).catch(function (e) {
			if (e && e.rpcCode === -32000 && /Object not found/i.test(e.message || '')) fail('Служба rpcd на роутере ещё запускается — подождите минуту и нажмите «Войти» снова');
			else fail(e && e.noUbus ? e.message : ('Роутер не отвечает: ' + ((e && e.message) || e)));
		});
	});

	loginEl = E('div', { 'class': 'zmw-login' }, [
		mxRain,
		E('div', { 'class': 'zmw-orbs', 'aria-hidden': 'true' }, [ E('i'), E('i'), E('i') ]),
		E('div', { 'class': 'zmw-grid-bg', 'aria-hidden': 'true' }),
		card,
		mxMsg,
		E('button', { 'type': 'button', 'class': 'zmw-icon-btn zmw-login-theme zmw-theme-toggle', 'click': toggleTheme })
	]);
	document.body.classList.add('zmw-locked');
	root.appendChild(loginEl);
	dustPlace();
	loginEl.zmMxStop = matrixRain(mxRain, mxMsg);
	applyTheme();
	setTimeout(function () { (user.value ? pass : user).focus(); }, 60);
}

function closeLogin() {
	if (!loginEl) return;
	var el = loginEl;
	loginEl = null;
	authLostShown = false;
	dustPlace();
	if (el.zmMxStop) setTimeout(el.zmMxStop, 400);
	el.classList.add('zmw-leave');
	document.body.classList.remove('zmw-locked');
	setTimeout(function () { el.remove(); }, 380);
}

function authLost() {
	if (authLostShown || loginEl) return;
	authLostShown = true;
	sid = null;
	sset(K_SID, null);
	poll._reset();
	termDrop();
	freshLogin('Сессия истекла — войдите снова.', 'warning');
}

function dropCaches() {
	srcCache = {};
	modCache = {};
	try { if (window.caches && caches.keys) caches.keys().then(function (ks) { ks.forEach(function (k) { caches.delete(k); }); }).catch(function () {}); } catch (e) {}
	try { var s = store('session'); if (s) Object.keys(s).forEach(function (k) { if (/^zmw\./.test(k) && k !== K_THEME && k !== K_USER && k !== K_NOTE) s.removeItem(k); }); } catch (e) {}
}

function freshLogin(note, kind) {
	dropCaches();
	var shown = false;
	var show = function () { if (!shown) { shown = true; showLogin(note, kind); } };
	var t = setTimeout(show, 2500);
	fetch('/zm-webui.html?t=' + Date.now(), { cache: 'no-store' }).then(function (r) { return r.ok ? r.text() : ''; }).then(function (html) {
		var m = /app\.js\?v=([0-9A-Za-z_]+)/.exec(html || '');
		if (m && m[1] !== BUILD && !shown) {
			clearTimeout(t);
			shown = true;
			try { var s = store('session'); if (s) s.setItem(K_NOTE, JSON.stringify([ (note ? note + ' ' : '') + 'Панель обновлена — загружена новая версия.', kind || 'info' ])); } catch (e) {}
			location.replace('/?fresh=' + Date.now() + location.hash);
			return;
		}
		clearTimeout(t);
		show();
	}).catch(function () { clearTimeout(t); show(); });
}

function logout() {
	var s = sid;
	sid = null;
	sset(K_SID, null);
	var done = function () {
		poll._reset();
		termDrop();
		if (viewEl) viewEl.innerHTML = '';
		freshLogin('Вы вышли из панели.', 'info');
	};
	if (!s) return done();
	ubus('session', 'destroy', {}, s).catch(function () {}).then(done);
}

var started = false;
function startApp() {
	if (themeDirty && sget(K_THEME)) themeSave(sget(K_THEME));
	if (!shell) buildShell();
	document.body.classList.add('zmw-ready');
	if (!started) {
		started = true;
		window.addEventListener('hashchange', function () { route(); });
		startShellPolling();
	}
	loadShellInfo();
	refreshShellStatus();
	refreshMemory();
	route();
}

function boot() {
	root = document.getElementById('zmw-root');
	document.body.classList.add('zmw-body');
	applyTheme();
	themeSync();
	dustSync();

	document.addEventListener('keydown', function (e) { if (e.key === 'Escape') { closeDrawer(); } });

	var note = null;
	try { var ss = store('session'); note = ss && JSON.parse(ss.getItem(K_NOTE) || 'null'); if (ss) ss.removeItem(K_NOTE); } catch (e) {}
	if (/[?&]fresh=/.test(location.search)) {
		try { history.replaceState(null, '', '/' + location.hash); } catch (e) {}
	}
	if (note && !sid) { showLogin(note[0], note[1]); return; }

	if (/[?&]logout=1/.test(location.search)) {
		var s = sid;
		sid = null;
		sset(K_SID, null);
		try { history.replaceState(null, '', '/' + location.hash); } catch (e) {}
		if (s) ubus('session', 'destroy', {}, s).catch(function () {});
		freshLogin('Вы вышли из панели. Войдите снова.', 'info');
		return;
	}

	if (!sid) { showLogin(); return; }

	ubus('session', 'access', { scope: 'ubus', object: 'zapret-manager', 'function': 'status' }, sid).then(function (res) {
		if (!(res[0] === 0 && res[1] && res[1].access)) { sid = null; sset(K_SID, null); showLogin(); return; }
		return Promise.all([
			ubus('session', 'access', { scope: 'ubus', object: 'zapret-manager', 'function': 'ui_theme_set' }, sid),
			ubus('session', 'access', { scope: 'ubus', object: 'zapret-manager', 'function': 'zapret_action' }, sid)
		]).then(function (rr) {
			var r2 = rr[0], w = rr[1];
			if (r2[0] === 0 && r2[1] && r2[1].access === false && w[0] === 0 && w[1] && w[1].access === true) {
				var old = sid;
				sid = null; sset(K_SID, null);
				ubus('session', 'destroy', {}, old).catch(function () {});
				showLogin('Панель обновилась — войдите снова, чтобы заработали новые функции и сохранялась тема.', 'info');
				return;
			}
			startApp();
		}, function () { startApp(); });
	}).catch(function (e) {
		sid = null; sset(K_SID, null);
		showLogin(e && e.noUbus ? e.message : null, 'error');
	});
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
else boot();

})();
ZM_INSTALLER_EOF
cat > '/www/zm/app.css' << 'ZM_INSTALLER_EOF'

:root {
	--font: "Inter", system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
	--mono: ui-monospace, "JetBrains Mono", "SF Mono", "Cascadia Code", Consolas, "Liberation Mono", monospace;

	--a1: #7c5cff;
	--a2: #3b82f6;
	--a3: #22d3ee;
	--grad: linear-gradient(135deg, var(--a1) 0%, var(--a2) 55%, var(--a3) 100%);
	--grad-soft: linear-gradient(135deg, rgba(124,92,255,.16), rgba(34,211,238,.10));
	--ring: 0 0 0 3px rgba(124,92,255,.28);

	--radius: 18px;
	--radius-sm: 12px;
	--side-w: 272px;

	--bg: #f3f5fa;
	--bg-glow-1: rgba(124,92,255,.12);
	--bg-glow-2: rgba(34,211,238,.10);
	--surface: rgba(255,255,255,.82);
	--surface-solid: #ffffff;
	--surface-2: #f5f6fb;
	--surface-3: #eceff6;
	--side-bg: rgba(255,255,255,.66);
	--border: rgba(15,23,42,.08);
	--border-2: rgba(15,23,42,.14);
	--text: #0f172a;
	--text-2: #334155;
	--muted: #64748b;
	--shadow: 0 1px 2px rgba(15,23,42,.04), 0 12px 32px -18px rgba(15,23,42,.18);
	--shadow-lg: 0 24px 60px -24px rgba(15,23,42,.35);
	--input-bg: #ffffff;
	--console: #0b1020;
	--console-border: rgba(15,23,42,.12);

	--ok: #059669; --ok-bg: rgba(16,185,129,.12); --ok-dot: #10b981;
	--bad: #dc2626; --bad-bg: rgba(239,68,68,.10); --bad-dot: #ef4444;
	--warn: #b45309; --warn-bg: rgba(245,158,11,.14); --warn-dot: #f59e0b;
	--off: #64748b; --off-bg: rgba(100,116,139,.12);

	--background-color-medium: var(--surface-solid);
	--background-color-low: var(--surface-2);
	color-scheme: light;
}

html[data-theme="dark"] {
	--bg: #07090f;
	--bg-glow-1: rgba(124,92,255,.20);
	--bg-glow-2: rgba(34,211,238,.10);
	--surface: rgba(22,27,38,.72);
	--surface-solid: #121722;
	--surface-2: rgba(255,255,255,.045);
	--surface-3: rgba(255,255,255,.08);
	--side-bg: rgba(12,15,23,.72);
	--border: rgba(255,255,255,.07);
	--border-2: rgba(255,255,255,.13);
	--text: #e8ebf4;
	--text-2: #c3c9d8;
	--muted: #8a93a8;
	--shadow: 0 1px 0 rgba(255,255,255,.03) inset, 0 16px 40px -22px rgba(0,0,0,.8);
	--shadow-lg: 0 30px 80px -30px rgba(0,0,0,.9);
	--input-bg: rgba(255,255,255,.04);
	--console: #070a12;
	--console-border: rgba(255,255,255,.08);

	--ok: #34d399; --ok-bg: rgba(52,211,153,.12); --ok-dot: #34d399;
	--bad: #f87171; --bad-bg: rgba(248,113,113,.12); --bad-dot: #f87171;
	--warn: #fbbf24; --warn-bg: rgba(251,191,36,.12); --warn-dot: #fbbf24;
	--off: #94a3b8; --off-bg: rgba(148,163,184,.12);
	color-scheme: dark;
}

*, *::before, *::after { box-sizing: border-box; }

html, body { margin: 0; padding: 0; }
body.zmw-body {
	font-family: var(--font);
	font-size: 14px;
	line-height: 1.5;
	color: var(--text);
	background-color: var(--bg);
	background-image:
		radial-gradient(900px 600px at -10% -20%, var(--bg-glow-1), transparent 60%),
		radial-gradient(800px 520px at 110% -10%, var(--bg-glow-2), transparent 60%);
	background-attachment: fixed;
	-webkit-font-smoothing: antialiased;
	-moz-osx-font-smoothing: grayscale;
	min-height: 100vh;
	overflow-x: hidden;
}
body.zmw-locked { overflow: hidden; }
html.zmw-theme-anim body, html.zmw-theme-anim .zmw-side, html.zmw-theme-anim .zm-card,
html.zmw-theme-anim .zmw-top, html.zmw-theme-anim .cbi-button { transition: background-color .35s, color .35s, border-color .35s !important; }

a { color: inherit; }
::selection { background: rgba(124,92,255,.35); }

::-webkit-scrollbar { width: 12px; height: 12px; }
::-webkit-scrollbar-button { display: none; width: 0; height: 0; }
::-webkit-scrollbar-track, ::-webkit-scrollbar-corner { background: transparent; }
::-webkit-scrollbar-thumb {
	background: rgba(128,128,140,.38); border-radius: 10px;
	border: 3px solid transparent; background-clip: padding-box; min-height: 36px;
}
::-webkit-scrollbar-thumb:hover { background: rgba(128,128,140,.6); background-clip: padding-box; }
html.zm-theme-dark ::-webkit-scrollbar-thumb { background: rgba(255,255,255,.16); background-clip: padding-box; }
html.zm-theme-dark ::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,.3); background-clip: padding-box; }
@supports not selector(::-webkit-scrollbar) {
	* { scrollbar-width: thin; scrollbar-color: rgba(128,128,140,.45) transparent; }
}
#zmw-view .zm-config-editor::-webkit-scrollbar-track, #zmw-view textarea::-webkit-scrollbar-track { margin: 10px 0; }
#zmw-view .zm-config-editor::-webkit-scrollbar-corner, #zmw-view textarea::-webkit-scrollbar-corner, #zmw-view textarea::-webkit-resizer { background: transparent; }

.zmw-i { width: 20px; height: 20px; flex-shrink: 0; display: block; }

.zmw-logo {
	width: 42px; height: 42px; border-radius: 13px;
	background:
		radial-gradient(120% 90% at 30% 0%, rgba(56,189,248,.35), transparent 60%),
		linear-gradient(160deg, #13223f 0%, #0a1426 55%, #060c18 100%);
	display: grid; place-items: center; flex-shrink: 0;
	box-shadow: 0 8px 22px -8px rgba(14,165,233,.75), inset 0 1px 0 rgba(255,255,255,.14), inset 0 0 0 1px rgba(56,189,248,.28);
	position: relative;
	overflow: visible;
}
.zmw-logo svg { width: 32px; height: 32px; filter: drop-shadow(0 0 6px rgba(56,189,248,.55)) drop-shadow(0 2px 2px rgba(0,0,0,.45)); }
.zmw-logo-lg { width: 76px; height: 76px; border-radius: 22px; margin: 0 auto 18px; }
.zmw-logo-lg svg { width: 58px; height: 58px; animation: zmw-zap 4.5s ease-in-out infinite; }
.zmw-logo-lg::after {
	content: ""; position: absolute; inset: -12px; border-radius: 30px;
	background: radial-gradient(circle, rgba(14,165,233,.55), rgba(124,92,255,.25) 60%, transparent 75%);
	filter: blur(18px); z-index: -1;
}
@keyframes zmw-zap {
	0%, 86%, 100% { filter: drop-shadow(0 0 8px rgba(56,189,248,.55)) drop-shadow(0 2px 2px rgba(0,0,0,.45)); }
	90% { filter: drop-shadow(0 0 18px rgba(125,211,252,1)) drop-shadow(0 0 4px #fff); }
	94% { filter: drop-shadow(0 0 6px rgba(56,189,248,.45)) drop-shadow(0 2px 2px rgba(0,0,0,.45)); }
}

.zmw-icon-btn {
	display: inline-flex; align-items: center; justify-content: center; gap: 8px;
	height: 40px; min-width: 40px; padding: 0 10px;
	border-radius: 12px; border: 1px solid var(--border);
	background: var(--surface); color: var(--text-2);
	cursor: pointer; font: 600 13px/1 var(--font);
	transition: background .15s, border-color .15s, color .15s, transform .1s;
	backdrop-filter: blur(10px); -webkit-backdrop-filter: blur(10px);
}
.zmw-icon-btn:hover { border-color: var(--border-2); color: var(--text); background: var(--surface-solid); }
.zmw-icon-btn:active { transform: scale(.96); }
.zmw-icon-btn:focus-visible { outline: none; box-shadow: var(--ring); }
.zmw-icon-btn .zmw-i { width: 19px; height: 19px; }
.zmw-spin .zmw-i { animation: zmw-spin .7s cubic-bezier(.4,0,.2,1); }
@keyframes zmw-spin { to { transform: rotate(360deg); } }

.zmw-shell { display: flex; min-height: 100vh; opacity: 0; transition: opacity .35s; }
body.zmw-ready .zmw-shell { opacity: 1; }
body.zmw-locked .zmw-shell { filter: blur(6px); pointer-events: none; }

.zmw-side {
	position: sticky; top: 0; height: 100vh;
	width: var(--side-w); flex-shrink: 0;
	display: flex; flex-direction: column;
	padding: 20px 14px 16px;
	background: var(--side-bg);
	border-right: 1px solid var(--border);
	backdrop-filter: blur(18px) saturate(140%); -webkit-backdrop-filter: blur(18px) saturate(140%);
	z-index: 40;
	overflow: hidden;
}
.zmw-side > .zmw-brand, .zmw-side > .zmw-update, .zmw-side > .zmw-side-foot { flex-shrink: 0; }
.zmw-side > .zmw-nav { min-height: 0; overflow-y: auto; overscroll-behavior: contain; scrollbar-width: thin; margin: 0 -8px; padding: 0 8px; }
.zmw-nav.zmw-fade-t { -webkit-mask-image: linear-gradient(to bottom, transparent, #000 22px); mask-image: linear-gradient(to bottom, transparent, #000 22px); }
.zmw-nav.zmw-fade-b { -webkit-mask-image: linear-gradient(to top, transparent, #000 22px); mask-image: linear-gradient(to top, transparent, #000 22px); }
.zmw-nav.zmw-fade-t.zmw-fade-b { -webkit-mask-image: linear-gradient(to bottom, transparent, #000 22px, #000 calc(100% - 22px), transparent); mask-image: linear-gradient(to bottom, transparent, #000 22px, #000 calc(100% - 22px), transparent); }
.zmw-nav::-webkit-scrollbar { width: 6px; }
.zmw-nav::-webkit-scrollbar-thumb { background: var(--border-2); border-radius: 6px; }
.zmw-nav::-webkit-scrollbar-track { background: transparent; }
@media (max-height: 520px) {
	.zmw-side { overflow-y: auto; }
	.zmw-side > .zmw-nav { flex: none; overflow: visible; -webkit-mask-image: none; mask-image: none; }
}

.zmw-brand { display: flex; align-items: center; gap: 12px; padding: 2px 8px 14px; }
.zmw-brand-text { min-width: 0; flex: 1; }
.zmw-brand-name { font-weight: 750; font-size: 20px; line-height: 1.15; letter-spacing: -.01em; white-space: nowrap; }
.zmw-brand-name b { font-weight: inherit; background: linear-gradient(90deg, #1a8cff, #7c5cff); -webkit-background-clip: text; background-clip: text; color: transparent; }
html[data-theme="dark"] .zmw-brand-name b, html[data-theme="depth"] .zmw-brand-name b, html.zm-theme-dark .zmw-brand-name b { background: linear-gradient(90deg, #38bdf8, #a78bfa); -webkit-background-clip: text; background-clip: text; }
.zmw-brand .zmw-logo svg { width: 36px; height: 36px; }
@media (max-width: 960px) {
	.zmw-brand-name { font-size: 18px; }
	.zmw-brand .zmw-logo svg { width: 32px; height: 32px; }
}
.zmw-drawer-close { display: none; }

.zmw-update {
	display: block; margin: 0 6px 12px; padding: 9px 12px;
	border-radius: 12px; font-size: 12.5px; font-weight: 600; text-decoration: none;
	color: var(--text); background: var(--grad-soft); border: 1px solid rgba(124,92,255,.35);
}
.zmw-update::before { content: "✦ "; color: var(--a1); }
.zmw-update[hidden] { display: none; }

.zmw-nav { display: flex; flex-direction: column; gap: 2px; flex: 1; }
.zmw-nav-group {
	font-size: 11px; font-weight: 700; letter-spacing: .08em; text-transform: uppercase;
	color: var(--muted); opacity: .8; padding: 12px 12px 4px;
}
.zmw-nav-group:first-child { padding-top: 4px; }
.zmw-nav-group { display: flex; align-items: center; justify-content: space-between; gap: 8px; opacity: 1; }
.zmw-nav-group > span { opacity: .8; }
.zmw-nav-group[hidden], .zmw-nav-item[hidden] { display: none; }
.zmw-nav-gear {
	position: relative; height: 24px; min-width: 24px; margin: -4px -6px -4px 0; padding: 0; flex: none;
	display: inline-flex; align-items: center; justify-content: center; gap: 0;
	border-radius: 8px; cursor: pointer; outline: none; box-sizing: border-box;
	border: 1px solid var(--border); background: var(--surface-2); color: var(--muted);
	font: inherit; font-size: 12px; font-weight: 650; letter-spacing: 0; text-transform: none; line-height: 1;
	transition: color .15s, border-color .15s, background .15s, box-shadow .15s;
}
.zmw-nav-gear .zmw-i { width: 14px; height: 14px; display: block; transition: transform .35s; }
.zmw-nav-gear:hover { color: var(--text); border-color: var(--a1); }
.zmw-nav-gear:hover .zmw-i { transform: rotate(60deg); }
.zmw-nav-gear:focus-visible { box-shadow: 0 0 0 2px var(--a1); }
.zmw-nav-gear-done { display: none; }
.zmw-nav-gear.zmw-on { padding: 0 11px; color: #fff; background: var(--grad); border-color: transparent; }
.zmw-nav-gear.zmw-on .zmw-i { display: none; }
.zmw-nav-gear.zmw-on .zmw-nav-gear-done { display: inline; }
.zmw-nav-gear > i { display: none; position: absolute; top: 2px; right: 2px; width: 6px; height: 6px; border-radius: 50%; background: var(--a1); box-shadow: 0 0 0 1.5px var(--surface-2); pointer-events: none; }
.zmw-nav-gear.zmw-has > i { display: block; }
.zmw-nav-gear.zmw-on > i { display: none; }
.zmw-nav-editfoot, .zmw-nav-eye, .zmw-nav-lock { display: none; }
.zmw-nav-editing .zmw-nav-editfoot { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 6px; padding: 10px 4px 4px; }
.zmw-nav-editfoot .zmw-nav-btn { min-width: 0; padding: 8px 10px; text-align: center; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.zmw-nav-editfoot .zmw-nav-btn-wide { grid-column: 1 / -1; }
.zmw-nav-editfoot .zmw-nav-btn-done { color: #fff; background: var(--grad); border-color: transparent; }
.zmw-nav-editfoot .zmw-nav-btn-done:hover { color: #fff; border-color: transparent; filter: brightness(1.08); }
.zmw-nav-btn { border: 1px solid var(--border); background: var(--surface-2); color: var(--text-2); border-radius: 9px; padding: 6px 10px; font: inherit; font-size: 12.5px; font-weight: 600; cursor: pointer; }
.zmw-nav-btn:hover { color: var(--text); border-color: var(--a1); }
.zmw-nav-editing .zmw-nav-eye {
	display: grid; place-items: center; width: 26px; height: 26px; border-radius: 8px; flex: none; margin-right: -6px;
	color: var(--a1); background: var(--grad-soft);
}
.zmw-nav-editing .zmw-nav-eye .zmw-i { width: 15px; height: 15px; }
.zmw-nav-editing .zmw-nav-lock { display: block; font-size: 11.5px; font-weight: 600; color: var(--muted); }
.zmw-nav-editing .zmw-nav-item.zmw-active .zmw-nav-lock { color: inherit; opacity: .75; }
.zmw-nav-editing .zmw-nav-item { cursor: pointer; user-select: none; }
.zmw-nav-editing .zmw-nav-item.zmw-active::before { display: none; }
.zmw-nav-editing .zmw-nav-item.zmw-nav-off { opacity: .45; }
.zmw-nav-editing .zmw-nav-item.zmw-nav-off .zmw-nav-eye { color: var(--muted); background: var(--surface-2); }
.zmw-nav-editing .zmw-nav-item.zmw-nav-off .zmw-nav-label { text-decoration: line-through; text-decoration-color: rgba(127,127,127,.5); }
.zmw-nav-item {
	position: relative;
	display: flex; align-items: center; gap: 12px;
	padding: 5px 12px; border-radius: 12px;
	text-decoration: none; color: var(--text-2);
	font-weight: 550; font-size: 14px;
	transition: background .15s, color .15s;
}
.zmw-nav-item:hover { background: var(--surface-2); color: var(--text); }
.zmw-nav-ico {
	width: 28px; height: 28px; border-radius: 10px;
	display: grid; place-items: center; flex-shrink: 0;
	background: var(--surface-2); border: 1px solid var(--border);
	color: var(--muted);
	transition: background .2s, color .2s, border-color .2s, box-shadow .2s;
}
.zmw-nav-ico .zmw-i { width: 18px; height: 18px; }
.zmw-nav-label { flex: 1; min-width: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.zmw-nav-item.zmw-active { background: var(--grad-soft); color: var(--text); }
.zmw-nav-item.zmw-active::before {
	content: ""; position: absolute; left: -9px; top: 10px; bottom: 10px; width: 4px;
	border-radius: 4px; background: var(--grad);
}
.zmw-nav-item.zmw-active .zmw-nav-ico {
	background: var(--grad); color: #fff; border-color: transparent;
	box-shadow: 0 6px 16px -6px rgba(99,102,241,.8);
}
.zmw-nav-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; display: none; }
.zmw-nav-dot.zmw-on, .zmw-nav-dot.zmw-stop, .zmw-nav-dot.zmw-part, .zmw-nav-dot.zmw-idle { display: block; }
.zmw-nav-dot.zmw-idle { background: #9aa3b2; box-shadow: 0 0 0 3px rgba(154,163,178,.18); }
.zmw-nav-dot.zmw-part { background: var(--warn-dot); box-shadow: 0 0 0 3px var(--warn-bg), 0 0 10px var(--warn-dot); }
.zmw-nav-dot.zmw-on { background: var(--ok-dot); box-shadow: 0 0 0 3px var(--ok-bg), 0 0 10px var(--ok-dot); }
.zmw-nav-dot.zmw-stop { background: var(--bad-dot); box-shadow: 0 0 0 3px var(--bad-bg), 0 0 10px var(--bad-dot); animation: zmw-blink 1.6s ease-in-out infinite; }
@keyframes zmw-blink { 50% { opacity: .45; } }

.zmw-side-foot { display: flex; flex-direction: column; gap: 7px; padding: 10px 6px 8px; margin-top: 12px; border-top: 1px solid var(--border); }
@keyframes zmw-pulse {
	0% { box-shadow: 0 0 0 0 rgba(16,185,129,.55); }
	70% { box-shadow: 0 0 0 8px rgba(16,185,129,0); }
	100% { box-shadow: 0 0 0 0 rgba(16,185,129,0); }
}
.zmw-device { padding: 0 9px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; font-size: 12.5px; line-height: 1.35; }
.zmw-device-sub:empty { display: none; }
.zmw-device-model { font-weight: 650; color: var(--text); }
.zmw-device-sub { font-size: 12px; color: var(--muted); }
.zmw-mem { display: flex; flex-direction: column; gap: 9px; padding: 2px 6px; }
.zmw-mem:empty { display: none; }
.zmw-mem-head { display: flex; justify-content: space-between; gap: 8px; font-size: 11.5px; margin-bottom: 4px; }
.zmw-mem-label { color: var(--muted); font-weight: 600; }
.zmw-mem-val { color: var(--text-2); font-weight: 600; font-variant-numeric: tabular-nums; white-space: nowrap; }
.zmw-mem-bar { height: 6px; border-radius: 6px; background: var(--surface-3); overflow: hidden; }
.zmw-mem-bar i { display: block; height: 100%; width: 0; border-radius: 6px; background: var(--grad); transition: width .6s cubic-bezier(.2,.8,.2,1); }
.zmw-mem-mid .zmw-mem-bar i { background: linear-gradient(90deg, #f59e0b, #fbbf24); }
.zmw-mem-hi .zmw-mem-bar i { background: linear-gradient(90deg, #ef4444, #f87171); }
.zmw-side .zmw-mem { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); grid-auto-rows: 1fr; gap: 5px; padding: 0; }
.zmw-side .zmw-mem:empty { display: none; }
.zmw-side .zmw-mem-row:last-child:nth-child(odd) { grid-column: 1 / -1; }
html[data-theme="matrix"] .zmw-side .zmw-mem-val { font-size: 11px; letter-spacing: -.02em; }
html[data-theme="matrix"] .zmw-side .zmw-mem-val.zmw-mem-fit { font-size: 10px; letter-spacing: -.04em; }
.zmw-side .zmw-mem-row { min-width: 0; display: flex; flex-direction: column; justify-content: space-between; padding: 5px 8px 6px; border-radius: 9px; background: var(--surface-2); border: 1px solid var(--border); }
.zmw-side .zmw-mem-head { flex-direction: column; gap: 0; margin-bottom: 4px; }
.zmw-side .zmw-mem-label { font-size: 11px; line-height: 1.25; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.zmw-side .zmw-mem-val { font-size: 12px; line-height: 1.3; color: var(--text); overflow: hidden; text-overflow: ellipsis; }
.zmw-side .zmw-mem-val.zmw-mem-fit { font-size: 10.5px; letter-spacing: -.02em; }
.zmw-side .zmw-mem-bar { height: 4px; }
html.zm-dust-on .zmw-side .zmw-mem-row { background: transparent; }
#zmw-view .zm-meter .zmw-mem-head { font-size: 13px; margin-bottom: 6px; align-items: baseline; }
#zmw-view .zm-meter .zmw-mem-label { font-weight: 500; }

.zmw-main { flex: 1; min-width: 0; display: flex; flex-direction: column; }

.zmw-top {
	--zmw-top-bg: var(--bg);
	position: sticky; top: 0; z-index: 30;
	display: flex; align-items: center; gap: 14px;
	padding: 18px 32px 14px;
	background: var(--zmw-top-bg);
}
.zmw-top::after { content: ''; position: absolute; left: 0; right: 0; top: 100%; height: 18px; pointer-events: none; background: linear-gradient(to bottom, var(--zmw-top-bg), transparent); }
html[data-theme="dark"] .zmw-top { --zmw-top-bg: rgb(7,9,15); }
html[data-theme="light"] .zmw-top { --zmw-top-bg: rgb(243,245,250); }
.zmw-burger { display: none; }
.zmw-titles { flex: 1; min-width: 0; }
.zmw-title { margin: 0; font-size: 24px; font-weight: 750; letter-spacing: -.02em; line-height: 1.2; }
.zmw-sub { font-size: 13px; color: var(--muted); margin-top: 2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.zmw-top-actions { display: flex; gap: 8px; align-items: center; }
.zmw-logout span { padding-right: 2px; }
.zmw-title { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

.zmw-view { padding: 6px 32px 24px; flex: 1; width: 100%; max-width: 1320px; }
.zmw-foot { padding: 8px 32px 24px; font-size: 12px; color: var(--muted); opacity: .6; }

.zmw-page { animation: zmw-page-in .42s cubic-bezier(.2,.8,.2,1) both; }
@keyframes zmw-page-in { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: none; } }

.zmw-scrim { display: none; }

.zmw-skel-wrap { display: flex; flex-direction: column; gap: 16px; }
.zmw-skel-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 16px; }
.zmw-skel {
	border-radius: var(--radius);
	background: linear-gradient(90deg, var(--surface-2) 0%, var(--surface-3) 40%, var(--surface-2) 80%);
	background-size: 300% 100%;
	animation: zmw-shimmer 1.4s infinite linear;
	border: 1px solid var(--border);
}
.zmw-skel-bar { height: 64px; }
.zmw-skel-card { height: 170px; }
.zmw-skel-wide { height: 240px; }
@keyframes zmw-shimmer { from { background-position: 100% 0; } to { background-position: -200% 0; } }

.zmw-error {
	display: flex; gap: 16px; align-items: flex-start;
	padding: 22px 24px; border-radius: var(--radius);
	background: var(--surface); border: 1px solid rgba(239,68,68,.3);
	box-shadow: var(--shadow);
}
.zmw-error-ico { width: 44px; height: 44px; border-radius: 12px; display: grid; place-items: center; background: var(--bad-bg); color: var(--bad); flex-shrink: 0; }
.zmw-error h3 { margin: 0 0 6px; font-size: 16px; }
.zmw-error p { margin: 0 0 14px; color: var(--muted); overflow-wrap: anywhere; }

.zmw-login {
	position: fixed; inset: 0; z-index: 200;
	display: grid; grid-template-columns: minmax(0, 1fr); place-items: center; padding: 20px; box-sizing: border-box;
	background: var(--bg);
	overflow-x: hidden; overflow-y: auto;
	animation: zmw-fade .4s ease both;
}
.zmw-login.zmw-leave { animation: zmw-fade-out .38s ease both; }
@keyframes zmw-fade { from { opacity: 0; } to { opacity: 1; } }
@keyframes zmw-fade-out { to { opacity: 0; transform: scale(1.02); } }

.zmw-orbs { position: absolute; inset: 0; overflow: hidden; pointer-events: none; }
.zmw-orbs i { position: absolute; border-radius: 50%; filter: blur(70px); opacity: .55; }
.zmw-orbs i:nth-child(1) { width: 520px; height: 520px; background: #7c5cff; left: -140px; top: -160px; animation: zmw-float1 18s ease-in-out infinite alternate; }
.zmw-orbs i:nth-child(2) { width: 460px; height: 460px; background: #22d3ee; right: -140px; bottom: -160px; opacity: .38; animation: zmw-float2 22s ease-in-out infinite alternate; }
.zmw-orbs i:nth-child(3) { width: 320px; height: 320px; background: #3b82f6; right: 18%; top: 12%; opacity: .25; animation: zmw-float1 26s ease-in-out infinite alternate-reverse; }
html[data-theme="light"] .zmw-orbs i { opacity: .28; }
@keyframes zmw-float1 { to { transform: translate(120px, 80px) scale(1.1); } }
@keyframes zmw-float2 { to { transform: translate(-100px, -60px) scale(1.15); } }

.zmw-grid-bg {
	position: absolute; inset: 0; pointer-events: none;
	background-image:
		linear-gradient(var(--border) 1px, transparent 1px),
		linear-gradient(90deg, var(--border) 1px, transparent 1px);
	background-size: 44px 44px;
	-webkit-mask-image: radial-gradient(ellipse at center, #000 20%, transparent 70%);
	mask-image: radial-gradient(ellipse at center, #000 20%, transparent 70%);
	opacity: .7;
}

.zmw-login-card {
	position: relative; z-index: 1;
	box-sizing: border-box; min-width: 0;
	width: 100%; max-width: 400px;
	padding: 36px 32px 28px;
	border-radius: 26px;
	background: var(--surface);
	border: 1px solid var(--border-2);
	box-shadow: var(--shadow-lg);
	backdrop-filter: blur(24px) saturate(150%); -webkit-backdrop-filter: blur(24px) saturate(150%);
	text-align: center;
	animation: zmw-card-in .6s cubic-bezier(.2,.8,.2,1) both;
}
@keyframes zmw-card-in { from { opacity: 0; transform: translateY(18px) scale(.98); } to { opacity: 1; transform: none; } }
.zmw-login-card h1 {
	margin: 0; font-size: 26px; font-weight: 800; letter-spacing: -.02em;
	background: linear-gradient(135deg, var(--text) 30%, var(--a1) 75%, var(--a3));
	-webkit-background-clip: text; background-clip: text; color: transparent;
}
.zmw-login-sub { margin: 6px 0 24px; color: var(--muted); font-size: 13.5px; }
.zmw-login-sub b { color: var(--text-2); font-weight: 650; }
.zmw-shake { animation: zmw-shake .45s cubic-bezier(.36,.07,.19,.97) both; }
@keyframes zmw-shake { 10%,90% { transform: translateX(-1px); } 20%,80% { transform: translateX(3px); } 30%,50%,70% { transform: translateX(-6px); } 40%,60% { transform: translateX(6px); } }

.zmw-field { display: block; text-align: left; margin-bottom: 14px; }
.zmw-field-label { display: block; font-size: 12.5px; font-weight: 650; color: var(--text-2); margin: 0 0 6px 2px; }
.zmw-input {
	display: flex; align-items: center; gap: 10px;
	height: 48px; padding: 0 6px 0 14px;
	border-radius: 14px; border: 1px solid var(--border-2);
	background: var(--input-bg);
	color: var(--muted);
	transition: border-color .15s, box-shadow .15s;
}
.zmw-input:focus-within { border-color: var(--a1); box-shadow: var(--ring); color: var(--a1); }
.zmw-input .zmw-i { width: 18px; height: 18px; }
.zmw-input input {
	flex: 1; min-width: 0; height: 100%;
	border: 0; outline: 0; background: transparent;
	color: var(--text); font: 500 15px/1 var(--font);
}
.zmw-input input::placeholder { color: var(--muted); opacity: .6; }
.zmw-eye { border: 0; background: transparent; color: var(--muted); width: 36px; height: 36px; border-radius: 10px; display: grid; place-items: center; cursor: pointer; }
.zmw-eye:hover { background: var(--surface-2); color: var(--text); }

.zmw-check { display: flex; align-items: center; gap: 10px; margin: 4px 2px 16px; font-size: 13px; color: var(--text-2); cursor: pointer; text-align: left; user-select: none; }
.zmw-check input { position: absolute; opacity: 0; pointer-events: none; }
.zmw-check-box {
	width: 20px; height: 20px; border-radius: 7px; flex-shrink: 0;
	border: 1.5px solid var(--border-2); background: var(--input-bg);
	display: grid; place-items: center; transition: background .15s, border-color .15s;
}
.zmw-check input:checked + .zmw-check-box { background: var(--grad); border-color: transparent; }
.zmw-check input:checked + .zmw-check-box::after { content: ""; width: 10px; height: 5px; border: 2px solid #fff; border-top: 0; border-right: 0; transform: rotate(-45deg) translate(1px, -1px); }
.zmw-check input:focus-visible + .zmw-check-box { box-shadow: var(--ring); }

.zmw-login-msg { display: none; text-align: left; font-size: 13px; font-weight: 550; padding: 10px 12px; border-radius: 12px; margin-bottom: 14px; }
.zmw-login-msg.zmw-show { display: block; }
.zmw-login-msg.zmw-error { background: var(--bad-bg); color: var(--bad); }
.zmw-login-msg.zmw-warning { background: var(--warn-bg); color: var(--warn); }
.zmw-login-msg.zmw-info { background: var(--grad-soft); color: var(--text-2); }

.zmw-btn-primary {
	position: relative; width: 100%; height: 50px;
	display: inline-flex; align-items: center; justify-content: center; gap: 8px;
	border: 0; border-radius: 14px; cursor: pointer;
	background: var(--grad); background-size: 160% 100%; background-position: 0 0;
	color: #fff; font: 700 15px/1 var(--font); letter-spacing: .01em;
	box-shadow: 0 12px 28px -10px rgba(99,102,241,.8), inset 0 1px 0 rgba(255,255,255,.25);
	transition: background-position .35s, transform .1s, box-shadow .2s;
}
.zmw-btn-primary:hover { background-position: 100% 0; box-shadow: 0 16px 32px -10px rgba(99,102,241,.9), inset 0 1px 0 rgba(255,255,255,.25); }
.zmw-btn-primary:active { transform: scale(.985); }
.zmw-btn-primary:focus-visible { outline: none; box-shadow: var(--ring), 0 12px 28px -10px rgba(99,102,241,.8); }
.zmw-btn-primary .zmw-i { width: 18px; height: 18px; transition: transform .2s; }
.zmw-btn-primary:hover .zmw-i { transform: translateX(3px); }
.zmw-btn-primary.zmw-loading span, .zmw-btn-primary.zmw-loading .zmw-i { opacity: 0; }
.zmw-btn-primary.zmw-loading::after {
	content: ""; position: absolute; width: 20px; height: 20px; border-radius: 50%;
	border: 2.5px solid rgba(255,255,255,.35); border-top-color: #fff;
	animation: zmw-spin .7s linear infinite;
}
.zmw-login-foot { margin-top: 18px; font-size: 12.5px; color: var(--muted); }
.zmw-login-theme { position: absolute; top: 18px; right: 18px; z-index: 2; }

.zmw-modal-wrap { position: fixed; inset: 0; z-index: 300; display: grid; place-items: center; padding: 20px; background: rgba(5,7,12,.55); backdrop-filter: blur(6px); opacity: 0; transition: opacity .2s; }
.zmw-modal-wrap.zmw-in { opacity: 1; }
.zmw-modal { width: 100%; max-width: 560px; max-height: 85vh; overflow: auto; padding: 24px; border-radius: 20px; background: var(--surface-solid); border: 1px solid var(--border-2); box-shadow: var(--shadow-lg); }
.zmw-modal h3 { margin: 0 0 12px; }

#zmw-view .zm-wrap { max-width: none; gap: 18px; }

#zmw-view .zm-header { align-items: center; gap: 12px; margin: 0; padding: 20px 24px; border-radius: var(--radius); background: var(--grad-soft); border: 1px solid rgba(124,92,255,.22); position: relative; overflow: hidden; }
#zmw-view .zm-header::after { content: ""; position: absolute; right: -60px; top: -80px; width: 240px; height: 240px; border-radius: 50%; background: var(--grad); filter: blur(60px); opacity: .22; pointer-events: none; }
#zmw-view .zm-header h2 { font-size: 22px; font-weight: 800; letter-spacing: -.02em; background: linear-gradient(135deg, var(--text) 35%, var(--a1) 80%, var(--a3)); -webkit-background-clip: text; background-clip: text; color: transparent; }

#zmw-view :not(.zm-cards) > .zm-card + .zm-current-banner,
#zmw-view .zm-current-banner + .zm-card,
#zmw-view :not(.zm-cards) > .zm-card + .zm-log,
#zmw-view .zm-card + .zm-refresh-banner,
#zmw-view .zm-card + .zm-cards,
#zmw-view .zm-cards + .zm-card { margin-top: 18px; }
#zmw-view .zm-wrap > * + * { margin-top: 0 !important; }
#zmw-view :not(.zm-cards):not(.bt-cols):not(.zm-wrap) > .zm-card:not(:last-child) { margin-bottom: 18px; }
#zmw-view .zm-current-banner { margin-bottom: 0; }

#zmw-view .zm-cards { grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 18px; }

#zmw-view .zm-card {
	background: var(--surface);
	border: 1px solid var(--border);
	border-radius: var(--radius);
	padding: 22px 24px;
	box-shadow: var(--shadow);
	backdrop-filter: blur(14px); -webkit-backdrop-filter: blur(14px);
	color: var(--text);
	transition: border-color .2s, box-shadow .2s;
}
#zmw-view .zm-card:hover { border-color: var(--border-2); box-shadow: var(--shadow); }
#zmw-view .zm-card.zm-list-card { padding: 0; overflow: hidden; }
#zmw-view .zm-card.zm-list-card:not(:last-child) { margin-bottom: 14px; }
#zmw-view .zm-list-head { padding: 16px 24px; }
#zmw-view .zm-list-body { padding: 2px 24px 20px; border-top-color: var(--border); }
#zmw-view .zm-list-actions { margin: 14px 0 0; }
@media (max-width: 600px) { #zmw-view .zm-list-head { padding: 14px 16px; } #zmw-view .zm-list-body { padding: 2px 16px 16px; } }
#zmw-view .zm-card h3 { margin: 0 0 14px; font-size: 16px; font-weight: 700; letter-spacing: -.01em; color: var(--text); }
#zmw-view .zm-card h3::before {
	content: ""; width: 4px; height: 18px; border-radius: 4px; background: var(--grad); flex-shrink: 0;
}
#zmw-view .zm-card h4 { color: var(--text); }
#zmw-view .zm-card p { color: var(--text-2); }

#zmw-view .zm-row { font-size: 13.5px; margin: 9px 0; gap: 12px; }
#zmw-view .zm-row .zm-label { opacity: 1; color: var(--muted); }
#zmw-view .bt-cols { column-gap: 48px; }
#zmw-view .bt-col .zm-row { padding: 6px 0; margin: 0; border-bottom: 1px dashed var(--border); }
#zmw-view .bt-col .zm-row:last-child { border-bottom: 0; }
#zmw-view .zm-sysline { border-top-color: var(--border); }

#zmw-view .zm-hint, #zmw-view p.zm-hint, .zm-dock .zm-hint, .zm-dock p.zm-hint, .zmw-modal .zm-hint, .zmw-modal p.zm-hint { opacity: 1; color: var(--muted); font-size: 12.5px; line-height: 1.6; }
#zmw-view a:not(.cbi-button), .zm-dock a:not(.cbi-button), .zmw-modal a:not(.cbi-button) { color: var(--a2); text-decoration-color: rgba(59,130,246,.35); text-underline-offset: 3px; }
html[data-theme="dark"] #zmw-view a:not(.cbi-button), html[data-theme="dark"] .zm-dock a:not(.cbi-button), html[data-theme="dark"] .zmw-modal a:not(.cbi-button) { color: #8ab4ff; }

#zmw-view .zm-badge, .zm-dock .zm-badge, .zmw-modal .zm-badge { padding: 4px 11px 4px 9px; font-size: 12px; font-weight: 650; gap: 7px; letter-spacing: .01em; }
#zmw-view .zm-ok { background: var(--ok-bg); color: var(--ok); }
#zmw-view .zm-ok .zm-dot { background: var(--ok-dot); box-shadow: 0 0 8px var(--ok-dot); animation: zmw-pulse 2.4s 3; }
#zmw-view .zm-bad { background: var(--bad-bg); color: var(--bad); }
#zmw-view .zm-bad .zm-dot { background: var(--bad-dot); }
#zmw-view .zm-warn { background: var(--warn-bg); color: var(--warn); }
#zmw-view .zm-warn .zm-dot { background: var(--warn-dot); }
#zmw-view .zm-off { background: var(--off-bg); color: var(--off); }
#zmw-view .zm-off .zm-dot { background: var(--off); }

#zmw-view .cbi-button, .zmw-modal .cbi-button, .zm-refresh-banner .cbi-button, .zm-dock .cbi-button {
	display: inline-flex; align-items: center; justify-content: center; gap: 6px;
	min-height: 38px; height: auto; padding: 8px 16px; margin: 0;
	border-radius: 12px; border: 1px solid var(--border-2);
	background: var(--surface-solid); color: var(--text);
	font: 600 13.5px/1.25 var(--font); letter-spacing: .005em;
	text-decoration: none; white-space: normal; text-align: center;
	cursor: pointer; box-shadow: 0 1px 2px rgba(0,0,0,.06);
	transition: border-color .15s, background .15s, transform .1s, box-shadow .15s, color .15s;
	-webkit-appearance: none; appearance: none;
}
html[data-theme="dark"] #zmw-view .cbi-button, html[data-theme="dark"] .zm-dock .cbi-button, html[data-theme="dark"] .zmw-modal .cbi-button { background: rgba(255,255,255,.05); }
#zmw-view .cbi-button:hover, .zm-dock .cbi-button:hover, .zmw-modal .cbi-button:hover { border-color: rgba(124,92,255,.55); background: var(--surface-solid); transform: translateY(-1px); box-shadow: 0 6px 16px -10px rgba(99,102,241,.6); }
html[data-theme="dark"] #zmw-view .cbi-button:hover, html[data-theme="dark"] .zm-dock .cbi-button:hover, html[data-theme="dark"] .zmw-modal .cbi-button:hover { background: rgba(255,255,255,.08); }
#zmw-view .cbi-button:active, .zm-dock .cbi-button:active, .zmw-modal .cbi-button:active { transform: translateY(0) scale(.98); }
#zmw-view .cbi-button:focus-visible, .zm-dock .cbi-button:focus-visible, .zmw-modal .cbi-button:focus-visible { outline: none; box-shadow: var(--ring); }
#zmw-view .cbi-button[disabled], #zmw-view .cbi-button:disabled, .zm-dock .cbi-button[disabled], .zm-dock .cbi-button:disabled, .zmw-modal .cbi-button[disabled], .zmw-modal .cbi-button:disabled { opacity: .5; cursor: not-allowed; transform: none; box-shadow: none; }

#zmw-view .cbi-button-positive, .zm-refresh-banner .cbi-button-positive,
html[data-theme="dark"] #zmw-view .cbi-button-positive, .zm-dock .cbi-button-positive, html[data-theme="dark"] .zm-dock .cbi-button-positive, .zmw-modal .cbi-button-positive, html[data-theme="dark"] .zmw-modal .cbi-button-positive {
	background: var(--grad); background-size: 150% 100%; color: #fff; border-color: transparent;
	box-shadow: 0 8px 20px -10px rgba(99,102,241,.9), inset 0 1px 0 rgba(255,255,255,.22);
}
#zmw-view .cbi-button-positive:hover, html[data-theme="dark"] #zmw-view .cbi-button-positive:hover, .zm-dock .cbi-button-positive:hover, html[data-theme="dark"] .zm-dock .cbi-button-positive:hover, .zmw-modal .cbi-button-positive:hover, html[data-theme="dark"] .zmw-modal .cbi-button-positive:hover {
	background: var(--grad); background-size: 150% 100%; background-position: 100% 0;
	border-color: transparent; color: #fff;
	box-shadow: 0 12px 26px -10px rgba(99,102,241,1), inset 0 1px 0 rgba(255,255,255,.22);
}
#zmw-view .cbi-button-remove, html[data-theme="dark"] #zmw-view .cbi-button-remove, .zm-dock .cbi-button-remove, html[data-theme="dark"] .zm-dock .cbi-button-remove, .zmw-modal .cbi-button-remove, html[data-theme="dark"] .zmw-modal .cbi-button-remove {
	background: var(--bad-bg); color: var(--bad); border-color: rgba(239,68,68,.28); box-shadow: none;
}
#zmw-view .cbi-button-remove:hover, html[data-theme="dark"] #zmw-view .cbi-button-remove:hover, .zm-dock .cbi-button-remove:hover, html[data-theme="dark"] .zm-dock .cbi-button-remove:hover, .zmw-modal .cbi-button-remove:hover, html[data-theme="dark"] .zmw-modal .cbi-button-remove:hover {
	background: rgba(239,68,68,.18); border-color: rgba(239,68,68,.5); color: var(--bad);
	box-shadow: 0 8px 20px -12px rgba(239,68,68,.8);
}

#zmw-view .zm-actions { gap: 10px; margin: 16px 0; }

#zmw-view .zm-actions.zmw-tabs {
	display: flex; flex-wrap: nowrap; gap: 4px;
	padding: 5px; margin: 0 0 4px !important;
	border-radius: 16px; background: var(--surface); border: 1px solid var(--border);
	box-shadow: var(--shadow);
	overflow-x: auto; scrollbar-width: none;
	backdrop-filter: blur(14px);
	width: max-content; max-width: 100%;
}
#zmw-view .zm-actions.zmw-tabs::-webkit-scrollbar { display: none; }
#zmw-view .zmw-tabs .cbi-button, .zm-dock .zmw-tabs .cbi-button, .zmw-modal .zmw-tabs .cbi-button {
	flex-shrink: 0; white-space: nowrap;
	border: 0; background: transparent; box-shadow: none; color: var(--muted);
	min-height: 36px; padding: 7px 16px; border-radius: 11px;
}
#zmw-view .zmw-tabs .cbi-button:hover, .zm-dock .zmw-tabs .cbi-button:hover, .zmw-modal .zmw-tabs .cbi-button:hover { background: var(--surface-2); color: var(--text); transform: none; box-shadow: none; }
#zmw-view .zmw-tabs .cbi-button-positive, #zmw-view .zmw-tabs .cbi-button-positive:hover, .zm-dock .zmw-tabs .cbi-button-positive, .zm-dock .zmw-tabs .cbi-button-positive:hover, .zmw-modal .zmw-tabs .cbi-button-positive, .zmw-modal .zmw-tabs .cbi-button-positive:hover {
	background: var(--grad); color: #fff;
	box-shadow: 0 6px 16px -8px rgba(99,102,241,.9);
}

#zmw-view .cbi-input-text, #zmw-view input[type="text"], #zmw-view input[type="number"],
#zmw-view input[type="password"], #zmw-view input[type="url"], #zmw-view select, #zmw-view .bt-input,
.zmw-modal input[type="text"], .zmw-modal select {
	height: 40px; padding: 0 14px;
	border-radius: 12px; border: 1px solid var(--border-2);
	background: var(--input-bg); color: var(--text);
	font: 500 14px/1 var(--font);
	outline: none; box-shadow: none;
	transition: border-color .15s, box-shadow .15s;
	max-width: 100%;
}
#zmw-view select, .zmw-modal select {
	-webkit-appearance: none; appearance: none; cursor: pointer;
	padding-right: 38px;
	background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%238a93a8' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M6 9l6 6 6-6'/%3E%3C/svg%3E");
	background-repeat: no-repeat; background-position: right 12px center; background-size: 16px;
}
#zmw-view select option { background: var(--surface-solid); color: var(--text); }
#zmw-view .zm-actions > .cbi-input-text[type="text"] { flex: 1 1 240px; min-width: 0; }
#zmw-view .cbi-input-text:focus, #zmw-view input:focus, #zmw-view select:focus, #zmw-view .bt-input:focus { border-color: var(--a1); box-shadow: var(--ring); }
#zmw-view input::placeholder { color: var(--muted); opacity: .7; }

#zmw-view .zm-grid { gap: 10px; }
#zmw-view .zm-vgrid > .zm-tile { padding-left: 6px; padding-right: 6px; }
#zmw-view .zm-tile {
	background: var(--surface-2);
	border: 1px solid var(--border);
	border-radius: 13px;
	padding: 11px 16px;
	font-size: 13.5px; font-weight: 550; color: var(--text-2);
	transition: border-color .15s, background .15s, transform .12s, box-shadow .15s, color .15s;
}
html.zm-theme-dark #zmw-view .zm-tile:not(.zm-active) { background: var(--surface-2); border-color: var(--border); }
#zmw-view .zm-tile:hover { border-color: rgba(124,92,255,.55); color: var(--text); transform: translateY(-2px); box-shadow: 0 10px 20px -14px rgba(99,102,241,.7); }
html.zm-theme-dark #zmw-view .zm-tile:not(.zm-active):hover { border-color: rgba(124,92,255,.55); }
#zmw-view .zm-tile.zm-active {
	background: var(--grad-soft);
	border-color: rgba(124,92,255,.65);
	color: var(--text); font-weight: 700;
	box-shadow: 0 0 0 1px rgba(124,92,255,.45) inset, 0 10px 24px -14px rgba(99,102,241,.9);
}
#zmw-view .zm-tile.zm-active::before { content: none; }
html[data-theme="dark"] #zmw-view .zm-tile.zm-active::before { color: #a594ff; }

#zmw-view .zm-log {
	background: var(--console);
	color: #dfe6f3;
	border: 1px solid var(--console-border);
	border-radius: 16px;
	padding: 0 20px 18px;
	font: 13px/1.75 var(--mono);
	box-shadow: inset 0 1px 0 rgba(255,255,255,.04), var(--shadow);
	position: relative;
	background-image: none;
	overflow-x: hidden; overflow-y: auto;
	scrollbar-width: auto; scrollbar-color: auto;
}
#zmw-view .zm-log::before {
	content: ''; display: block;
	position: sticky; top: 0; z-index: 2;
	height: 40px; margin: 0 -20px 6px;
	background:
		radial-gradient(circle at 20px 20px, #ff5f57 5px, transparent 5.5px),
		radial-gradient(circle at 38px 20px, #febc2e 5px, transparent 5.5px),
		radial-gradient(circle at 56px 20px, #28c840 5px, transparent 5.5px),
		var(--console);
	background-repeat: no-repeat;
	opacity: 1;
}
#zmw-view .zm-log:empty::before { content: ''; opacity: 1; }
#zmw-view .zm-log:empty::after { content: "Ожидание вывода…"; color: #8b949e; }
#zmw-view .zm-log.bt-panel { padding-top: 16px; }
#zmw-view .zm-log.bt-panel::before { display: none; }
#zmw-view .zm-log::-webkit-scrollbar { width: 14px; height: 14px; }
#zmw-view .zm-log::-webkit-scrollbar-track { background: transparent; margin: 44px 0 12px; }
#zmw-view .zm-log.bt-panel::-webkit-scrollbar-track { margin: 12px 0; }
#zmw-view .zm-log::-webkit-scrollbar-thumb {
	background: rgba(255,255,255,.18); border-radius: 10px;
	border: 4px solid transparent; background-clip: padding-box; min-height: 40px;
}
#zmw-view .zm-log::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,.32); background-clip: padding-box; }
#zmw-view .zm-log::-webkit-scrollbar-corner { background: transparent; }
@supports not selector(::-webkit-scrollbar) {
	#zmw-view .zm-log { scrollbar-width: thin; scrollbar-color: rgba(255,255,255,.25) transparent; }
}
#zmw-view .zm-log-arrow { color: #67e8f9; }
#zmw-view .zm-log-msg-info { color: #fcd34d; }
#zmw-view .zm-log-msg-ok { color: #4ade80; }
#zmw-view .zm-log-msg-error { color: #fb7185; }
#zmw-view .zm-log-msg-warn { color: #fdba74; }
#zmw-view .zm-log-code { color: #94a3b8; }

#zmw-view .zm-config-editor {
	background: var(--console); color: #e2e8f0;
	border: 1px solid var(--console-border); border-radius: 16px;
	padding: 16px 18px; font: 13px/1.65 var(--mono);
	outline: none;
	transition: border-color .15s, box-shadow .15s;
}
#zmw-view .zm-config-editor:focus { border-color: var(--a1); box-shadow: var(--ring); }

#zmw-view .zm-refresh-banner, .zm-refresh-banner {
	background: var(--warn-bg); border: 1px solid rgba(245,158,11,.35);
	color: var(--warn); border-radius: var(--radius); padding: 14px 18px;
	font-size: 14px; font-weight: 600; margin-top: 0;
}
#zmw-view .zm-current-banner {
	background: var(--grad-soft); border: 1px solid rgba(124,92,255,.28);
	border-radius: 14px; padding: 12px 16px; font-size: 13.5px; color: var(--text);
}
#zmw-view .zm-current-banner.zm-current-empty { background: var(--surface-2); border-color: var(--border); color: var(--muted); }
#zmw-view .zm-current-banner.zm-current-top { margin: 14px 0 0 !important; }
#zmw-view .zm-current-banner.zm-current-top + .zm-card { margin-top: 18px !important; }
#zmw-view .bt-current-cmd { background: var(--console); color: #86efac; border-radius: 12px; font-family: var(--mono); }
#zmw-view .zm-svc, html.zm-theme-dark #zmw-view .zm-svc { background: var(--surface-2); border-color: var(--border); border-radius: 14px; }
#zmw-view .zm-svc:hover { border-color: rgba(124,92,255,.55); box-shadow: 0 10px 20px -14px rgba(99,102,241,.7); }
#zmw-view .zm-svc.zm-svc-on, html.zm-theme-dark #zmw-view .zm-svc.zm-svc-on { background: var(--grad-soft); border-color: rgba(124,92,255,.6); }
#zmw-view .zm-svc-name { color: var(--text); } #zmw-view .zm-svc-sub { color: var(--muted); opacity: 1; }
#zmw-view .zm-switch { background: var(--border-2); }
#zmw-view .zm-switch.zm-switch-on { background: var(--grad); }

#zmw-view .bt-table td { border-top-color: rgba(255,255,255,.08); }
#zmw-view .bt-chip { border-radius: 7px; }

#zmw-view iframe { border: 1px solid var(--border-2) !important; border-radius: 16px !important; background: #fff; box-shadow: var(--shadow); }
#zmw-view .zm-term {
	background: var(--console); border: 1px solid var(--console-border); border-radius: 16px;
	box-shadow: inset 0 1px 0 rgba(255,255,255,.04), var(--shadow);
}
#zmw-view .zm-term-bar { height: 40px; padding: 0 20px; font-family: var(--mono); }
#zmw-view .zm-term-body { padding: 8px 15px 12px; }
#zmw-view .zm-term iframe.zm-term-frame { border: 0 !important; border-radius: 0 !important; background: var(--console); box-shadow: none; }
@media (max-width: 600px) {
	#zmw-view .zm-term-bar { padding: 0 14px; }
	#zmw-view .zm-term-body { padding: 6px 9px 10px; }
}

#zmw-view pre:not(.zm-log) { font-family: var(--mono); }
#zmw-view hr { border: 0; border-top: 1px solid var(--border); }

.zmw-body #zm-toast-container {
	top: auto; bottom: 28px; right: 28px; left: auto;
	gap: 12px; max-width: 520px; width: calc(100% - 56px);
	align-items: flex-end; justify-content: flex-end;
	z-index: 10001;
	pointer-events: none; overflow: hidden;
	transition: bottom .18s ease;
}
.zmw-body #zm-toast-container > .zm-toast { flex-shrink: 0; }
.zmw-body .zm-toast {
	--toast-bg: #161b26; --toast-fg: #f4f6fb; --toast-border: rgba(255,255,255,.08);
	pointer-events: auto;
	align-items: center; gap: 16px;
	width: 100%;
	padding: 20px 24px 20px 20px;
	border-radius: 18px;
	border: 1px solid var(--toast-border); border-left: 6px solid var(--ok);
	background: var(--toast-bg);
	color: var(--toast-fg);
	box-shadow: 0 18px 50px rgba(0,0,0,.35), 0 2px 8px rgba(0,0,0,.2);
	font-size: 16.5px; font-weight: 600; line-height: 1.45;
	opacity: 0; transform: translateY(16px) scale(.98);
	transition: opacity .25s ease, transform .3s cubic-bezier(.2,.8,.2,1);
}
html.zm-theme-dark .zmw-body .zm-toast, html.zm-theme-dark.zmw-body .zm-toast {
	--toast-bg: #ffffff; --toast-fg: #141821; --toast-border: rgba(0,0,0,.06);
	box-shadow: 0 18px 50px rgba(0,0,0,.55), 0 0 0 1px rgba(255,255,255,.08);
}
.zmw-body .zm-toast-error { border-left-color: var(--bad); }
.zmw-body .zm-toast-warning { border-left-color: var(--warn); }
.zmw-body .zm-toast.zm-toast-show { opacity: 1; transform: none; }
.zmw-body .zm-toast-icon {
	width: 10px; height: 10px; border-radius: 50%;
	flex-shrink: 0; align-self: center;
	box-shadow: 0 0 0 4px rgba(0,0,0,.06);
}
html body.zmw-body .zm-toast .zm-toast-icon { color: #fff; }
html body.zmw-body .zm-toast { background: var(--toast-bg); color: var(--toast-fg); }
.zmw-body .zm-toast-info .zm-toast-icon { background: #1f9d55; }
.zmw-body .zm-toast-error .zm-toast-icon { background: #d93b3b; }
.zmw-body .zm-toast-warning .zm-toast-icon { background: #d08a00; }
.zmw-body .zm-toast-busy { border-left-color: var(--a1, #7c5cff); }
.zmw-body .zm-toast-spin { border-color: rgba(255,255,255,.24); border-top-color: #a9b6ff; }
html.zm-theme-dark .zmw-body .zm-toast-spin, html.zm-theme-dark.zmw-body .zm-toast-spin { border-color: rgba(124,92,255,.25); border-top-color: var(--a1, #7c5cff); }
@media (max-width: 1180px) {
	.zmw-logout span { display: none; }
}
@media (max-width: 1080px) and (min-width: 961px), (max-width: 760px) {
	.zmw-sub { display: none; }
}

@media (max-width: 960px) {
	:root { --side-w: min(86vw, 300px); }
	.zmw-side {
		position: fixed; left: 0; top: 0; bottom: 0; height: auto;
		transform: translateX(-104%);
		transition: transform .32s cubic-bezier(.2,.8,.2,1);
		box-shadow: var(--shadow-lg);
		background: var(--surface-solid);
	}
	body.zmw-drawer-open .zmw-side { transform: none; }
	.zmw-drawer-close { display: inline-flex; }
	.zmw-scrim {
		display: block; position: fixed; inset: 0; z-index: 35;
		background: rgba(5,7,12,.5); backdrop-filter: blur(3px);
		opacity: 0; pointer-events: none; transition: opacity .3s;
	}
	body.zmw-drawer-open .zmw-scrim { opacity: 1; pointer-events: auto; }
	body.zmw-drawer-open { overflow: hidden; }
	.zmw-burger { display: inline-flex; }
	.zmw-top { padding: 12px 16px; gap: 10px; }
	.zmw-view { padding: 4px 16px 20px; }
	.zmw-foot { padding: 4px 16px 20px; }
	.zmw-title { font-size: 20px; }
}

@media (max-width: 600px) {
	.zmw-sub { display: none; }
	.zmw-top-actions { gap: 5px; }
	.zmw-icon-btn { height: 36px; min-width: 36px; padding: 0 8px; border-radius: 11px; }
	.zmw-top { gap: 8px; }
	.zmw-title { font-size: 18px; white-space: normal; text-overflow: clip; display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 2; line-height: 1.12; overflow-wrap: anywhere; }
	#zmw-view .zm-card { padding: 18px 16px; border-radius: 16px; }
	#zmw-view .zm-cards { grid-template-columns: 1fr; }
	#zmw-view .zm-header { padding: 16px; }
	#zmw-view .zm-actions .cbi-button, .zm-dock .zm-actions .cbi-button, .zmw-modal .zm-actions .cbi-button { flex: 1 1 auto; }
	#zmw-view .zmw-tabs .cbi-button, .zm-dock .zmw-tabs .cbi-button, .zmw-modal .zmw-tabs .cbi-button { flex: 0 0 auto; }
	#zmw-view .zm-actions.zmw-tabs { width: 100%; }
	#zmw-view .zm-refresh-banner, .zm-refresh-banner { flex-direction: column; align-items: stretch; text-align: left; }
	.zmw-nav-item { padding: 7px 12px; }
	.zmw-login-card { padding: 30px 20px 22px; border-radius: 22px; }
	.zmw-body #zm-toast-container { left: 12px; right: 12px; bottom: 12px; width: auto; max-width: none; }
	#zmw-view .zm-log { font-size: 12.5px; padding: 0 14px 14px; }
	#zmw-view .zm-log::before { margin: 0 -14px 6px; }
}

@media (prefers-reduced-motion: reduce) {
	*, *::before, *::after { animation-duration: .01ms !important; animation-iteration-count: 1 !important; transition-duration: .01ms !important; }
	html .zm-toast-spin, html .zm-reboot-spin, html .zmw-btn-primary.zmw-loading::after { animation-duration: 1.4s !important; animation-iteration-count: infinite !important; }
}
.zmw-modal.zm-wn { max-height: calc(100vh - 32px); max-height: calc(100dvh - 32px); }
.zmw-modal.zm-wn .zm-wn-list li { background: var(--surface-2); }
.zmw-modal.zm-wn .zm-wn-lead, .zmw-modal.zm-wn .zm-wn-list li span { color: var(--muted); opacity: 1; }
.zmw-modal.zm-wn .zm-wn-check input { accent-color: var(--a1); }
.zmw-modal.zm-wn .zm-wn-tip { background: var(--grad-soft); }
.zmw-modal.zm-ts .zm-ts-where span { background: var(--surface-3); color: var(--text-2); }
.zmw-modal.zm-ts .zm-ts-steps li::before { background: var(--grad-soft); color: var(--a1); }
.zmw-modal.zm-ts .zm-kbd { border-color: var(--border-2); background: var(--surface-2); }
#zmw-view .zm-seg { background: var(--surface-2); border-color: var(--border); border-radius: 12px; }
#zmw-view .zm-seg-item { border-radius: 9px; color: var(--text-2); }
#zmw-view .zm-seg-item.zm-active { background: var(--grad); color: #fff; box-shadow: 0 6px 16px -10px rgba(99,102,241,.9); }
#zmw-view .zm-log-bar { top: 46px; }
#zmw-view .zm-log-min { top: -38px; right: -10px; border-radius: 8px; border-color: rgba(255,255,255,.12); background: rgba(255,255,255,.05); color: #cbd5e1; }
#zmw-view .zm-log-min:hover { background: rgba(124,92,255,.35); border-color: rgba(124,92,255,.6); color: #fff; }
#zmw-view .zm-log.zm-log-collapsed { padding-bottom: 12px; }
.zmw-logo, .zmw-logo-lg { background: none; box-shadow: none; border-radius: 0; }
.zmw-logo svg { filter: drop-shadow(0 2px 3px rgba(0,120,220,.25)); }
.zmw-logo-lg::after { opacity: .55; }
html[data-theme="dark"] .zmw-logo svg { filter: drop-shadow(0 0 1px rgba(255,255,255,.55)) drop-shadow(0 0 10px rgba(0,182,255,.45)); }

.zmw-theme-menu {
	position: fixed; z-index: 1000; min-width: 184px; padding: 6px;
	display: flex; flex-direction: column; gap: 2px;
	background: var(--surface-solid); border: 1px solid var(--border-2); border-radius: 14px;
	box-shadow: var(--shadow-lg); animation: zmw-menu-in .14s ease-out;
}
@keyframes zmw-menu-in { from { opacity: 0; transform: translateY(-4px); } to { opacity: 1; transform: none; } }
.zmw-theme-opt {
	display: flex; align-items: center; gap: 10px; width: 100%; padding: 9px 10px;
	border: 0; border-radius: 10px; background: none; color: var(--text); font: inherit; font-size: 14px;
	cursor: pointer; text-align: left;
}
.zmw-theme-opt:hover { background: var(--surface-2); }
.zmw-theme-opt.zmw-on { background: var(--grad-soft); font-weight: 650; }
.zmw-theme-opt .zmw-i { width: 18px; height: 18px; flex-shrink: 0; }
.zmw-theme-opt > span:nth-of-type(1) { flex: 1; }
.zmw-theme-mark { color: var(--a1); width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
.zmw-dust { position: fixed; inset: 0; width: 100%; height: 100%; pointer-events: none; z-index: 0; }
.zmw-login .zmw-dust { position: absolute; }
html.zm-dust-on .zmw-shell { position: relative; z-index: 1; }
html[data-theme="matrix"] .zmw-login .zmw-dust { display: none; }
.zmw-anim-sw { flex: none; margin-left: auto; width: 30px; height: 18px; border-radius: 999px; background: var(--border-2); position: relative; transition: background .2s; }
.zmw-anim-sw i { position: absolute; top: 2px; left: 2px; width: 14px; height: 14px; border-radius: 50%; background: #ffffff; box-shadow: 0 1px 2px rgba(0,0,0,.3); transition: transform .2s, background .2s; }
.zmw-anim-on .zmw-anim-sw { background: var(--a1); }
.zmw-anim-on .zmw-anim-sw i { transform: translateX(12px); background: var(--surface-solid, #ffffff); }
html[data-theme="retro"] .zmw-anim-sw, html[data-theme="retro"] .zmw-anim-sw i, html[data-theme="minimal"] .zmw-anim-sw, html[data-theme="minimal"] .zmw-anim-sw i { border-radius: 0; }
@media (prefers-reduced-motion: reduce) { .zmw-anim-sw, .zmw-anim-sw i { transition: none; } }
.zmw-theme-opt.zmw-on .zmw-theme-mark { background: currentColor; }

html[data-theme="ink"] {
	--a1: #0a9cff; --a2: #0a9cff; --a3: #00c0ff;
	--grad: linear-gradient(180deg, #00c0ff, #0a9cff);
	--grad-soft: #d6f0ff;
	--ring: 0 0 0 3px rgba(10,156,255,.35);
	--radius: 6px; --radius-sm: 4px;
	--bg: #ffffff; --bg-glow-1: transparent; --bg-glow-2: transparent;
	--surface: #ffffff; --surface-solid: #ffffff; --surface-2: #e8f6ff; --surface-3: #d6f0ff;
	--side-bg: #e8f6ff;
	--border: #0a0a0a; --border-2: #0a0a0a;
	--text: #0a0a0a; --text-2: #1f2a36; --muted: #3d4a57;
	--shadow: 5px 5px 0 #0a0a0a; --shadow-lg: 8px 8px 0 #0a0a0a;
	--input-bg: #ffffff; --console: #0a0a0a; --console-border: #0a0a0a;
	--ok: #0a0a0a; --ok-bg: #19c45a; --ok-dot: #0a0a0a;
	--bad: #0a0a0a; --bad-bg: #ff4d3d; --bad-dot: #0a0a0a;
	--warn: #0a0a0a; --warn-bg: #ffc21a; --warn-dot: #0a0a0a;
	--off: #0a0a0a; --off-bg: #eeeeee;
	color-scheme: light;
}
html[data-theme="ink"] ::selection { background: #00c0ff; color: #0a0a0a; }
html[data-theme="ink"] body.zmw-body { background-image: none; }
html[data-theme="ink"] .zmw-orbs, html[data-theme="ink"] .zmw-grid-bg { display: none; }
html[data-theme="ink"] .zmw-top { --zmw-top-bg: #ffffff; background: var(--zmw-top-bg); }
html[data-theme="ink"] .zmw-side { background: #e8f6ff; border-right: 2.5px solid #0a0a0a; backdrop-filter: none; -webkit-backdrop-filter: none; box-shadow: none; }
html[data-theme="ink"] .zmw-nav-item { border: 2px solid transparent; border-radius: 6px; }
html[data-theme="ink"] .zmw-nav-item:hover { background: #d6f0ff; border-color: #0a0a0a; }
html[data-theme="ink"] .zmw-nav-item.zmw-active { background: #0a9cff; color: #0a0a0a; border-color: #0a0a0a; box-shadow: 3px 3px 0 #0a0a0a; font-weight: 700; }
html[data-theme="ink"] .zmw-nav-item.zmw-active::before { display: none; }
html[data-theme="ink"] .zmw-nav-item.zmw-active .zmw-nav-ico { color: #0a0a0a; }
html[data-theme="ink"] .zmw-mem-bar { height: 10px; border: 2px solid #0a0a0a; border-radius: 3px; background: #ffffff; }
html[data-theme="ink"] .zmw-mem-bar i { border-radius: 0; background: #0a9cff; }
html[data-theme="ink"] .zmw-mem-mid .zmw-mem-bar i { background: #ffc21a; }
html[data-theme="ink"] .zmw-mem-hi .zmw-mem-bar i { background: #ff4d3d; }
html[data-theme="ink"] .zmw-icon-btn, html[data-theme="ink"] .zmw-btn-primary {
	border: 2px solid #0a0a0a; border-radius: 6px; box-shadow: 3px 3px 0 #0a0a0a; background: #ffffff; color: #0a0a0a;
	transition: transform .08s, box-shadow .08s;
}
html[data-theme="ink"] .zmw-btn-primary { background: #0a9cff; }
html[data-theme="ink"] .zmw-icon-btn:active, html[data-theme="ink"] .zmw-btn-primary:active { transform: translate(2px, 2px); box-shadow: 1px 1px 0 #0a0a0a; }
html[data-theme="ink"] .zmw-login-card, html[data-theme="ink"] .zmw-modal, html[data-theme="ink"] .zmw-theme-menu {
	border: 2.5px solid #0a0a0a; border-radius: 8px; box-shadow: 6px 6px 0 #0a0a0a; background: #ffffff; backdrop-filter: none; -webkit-backdrop-filter: none;
}
html[data-theme="ink"] .zmw-theme-opt { border: 2px solid transparent; border-radius: 5px; }
html[data-theme="ink"] .zmw-theme-opt.zmw-on { background: #0a9cff; border-color: #0a0a0a; }
html[data-theme="ink"] .zmw-theme-mark { color: #0a0a0a; }
html[data-theme="ink"] .zmw-input { border: 2px solid #0a0a0a; border-radius: 6px; }
html[data-theme="ink"] .zmw-check-box { border: 2px solid #0a0a0a; border-radius: 3px; }

html[data-theme="ink"] #zmw-view .zm-card {
	background: #ffffff; border: 2.5px solid #0a0a0a; border-radius: 6px; box-shadow: 5px 5px 0 #0a0a0a;
	backdrop-filter: none; -webkit-backdrop-filter: none;
}
html[data-theme="ink"] #zmw-view .zm-card:hover { box-shadow: 5px 5px 0 #0a0a0a; border-color: #0a0a0a; }
html[data-theme="ink"] #zmw-view .zm-card h3::before { background: #0a9cff; border: 1.5px solid #0a0a0a; }
html[data-theme="ink"] #zmw-view .cbi-button, html[data-theme="ink"] .zm-dock .cbi-button, html[data-theme="ink"] .zmw-modal .cbi-button {
	border: 2px solid #0a0a0a; border-radius: 6px; box-shadow: 3px 3px 0 #0a0a0a; background: #ffffff; color: #0a0a0a;
	transition: transform .08s, box-shadow .08s;
}
html[data-theme="ink"] #zmw-view .cbi-button:hover, html[data-theme="ink"] .zm-dock .cbi-button:hover, html[data-theme="ink"] .zmw-modal .cbi-button:hover { background: #e8f6ff; transform: none; box-shadow: 3px 3px 0 #0a0a0a; }
html[data-theme="ink"] #zmw-view .cbi-button:active, html[data-theme="ink"] .zm-dock .cbi-button:active, html[data-theme="ink"] .zmw-modal .cbi-button:active { transform: translate(2px, 2px); box-shadow: 1px 1px 0 #0a0a0a; }
html[data-theme="ink"] #zmw-view .cbi-button-positive, html[data-theme="ink"] #zmw-view .cbi-button-positive:hover, html[data-theme="ink"] .zm-dock .cbi-button-positive, html[data-theme="ink"] .zm-dock .cbi-button-positive:hover, html[data-theme="ink"] .zmw-modal .cbi-button-positive, html[data-theme="ink"] .zmw-modal .cbi-button-positive:hover { background: #0a9cff; color: #0a0a0a; border-color: #0a0a0a; }
html[data-theme="ink"] #zmw-view .cbi-button-remove, html[data-theme="ink"] #zmw-view .cbi-button-remove:hover, html[data-theme="ink"] .zm-dock .cbi-button-remove, html[data-theme="ink"] .zm-dock .cbi-button-remove:hover, html[data-theme="ink"] .zmw-modal .cbi-button-remove, html[data-theme="ink"] .zmw-modal .cbi-button-remove:hover { background: #ff4d3d; color: #0a0a0a; border-color: #0a0a0a; }
html[data-theme="ink"] #zmw-view .cbi-button-action, html[data-theme="ink"] #zmw-view .cbi-button-action:hover, html[data-theme="ink"] .zm-dock .cbi-button-action, html[data-theme="ink"] .zm-dock .cbi-button-action:hover, html[data-theme="ink"] .zmw-modal .cbi-button-action, html[data-theme="ink"] .zmw-modal .cbi-button-action:hover { background: #d6f0ff; color: #0a0a0a; }
html[data-theme="ink"] #zmw-view .cbi-button[disabled], html[data-theme="ink"] .zm-dock .cbi-button[disabled], html[data-theme="ink"] .zmw-modal .cbi-button[disabled] { box-shadow: none; opacity: .5; }
html[data-theme="ink"] #zmw-view .zmw-tabs .cbi-button, html[data-theme="ink"] .zm-dock .zmw-tabs .cbi-button, html[data-theme="ink"] .zmw-modal .zmw-tabs .cbi-button { box-shadow: none; }
html[data-theme="ink"] #zmw-view .zmw-tabs .cbi-button-positive, html[data-theme="ink"] .zm-dock .zmw-tabs .cbi-button-positive, html[data-theme="ink"] .zmw-modal .zmw-tabs .cbi-button-positive { box-shadow: 3px 3px 0 #0a0a0a; }
html[data-theme="ink"] #zmw-view .zm-tile {
	background: #ffffff; border: 2px solid #0a0a0a; border-radius: 6px; box-shadow: 3px 3px 0 #0a0a0a; color: #0a0a0a;
}
html[data-theme="ink"] #zmw-view .zm-tile:hover { background: #e8f6ff; transform: none; }
html[data-theme="ink"] #zmw-view .zm-tile.zm-active { background: #0a9cff; color: #0a0a0a; border-color: #0a0a0a; box-shadow: 3px 3px 0 #0a0a0a; }
html[data-theme="ink"] #zmw-view .zm-tile.zm-active::before { color: #0a0a0a; }
html[data-theme="ink"] #zmw-view .zm-badge, html[data-theme="ink"] .zm-dock .zm-badge, html[data-theme="ink"] .zmw-modal .zm-badge { border: 2px solid #0a0a0a; color: #0a0a0a; }
html[data-theme="ink"] #zmw-view .zm-badge .zm-dot, html[data-theme="ink"] .zm-dock .zm-badge .zm-dot, html[data-theme="ink"] .zmw-modal .zm-badge .zm-dot { box-shadow: none; animation: none; }
html[data-theme="ink"] #zmw-view input[type="text"], html[data-theme="ink"] #zmw-view input[type="password"],
html[data-theme="ink"] #zmw-view input[type="number"], html[data-theme="ink"] #zmw-view select,
html[data-theme="ink"] #zmw-view textarea:not(.zm-config-editor) { border: 2px solid #0a0a0a; border-radius: 6px; background: #ffffff; }
html[data-theme="ink"] #zmw-view .zm-config-editor, html[data-theme="ink"] #zmw-view .zm-log { border: 2.5px solid #0a0a0a; border-radius: 6px; box-shadow: 5px 5px 0 #0a0a0a; }
html[data-theme="ink"] #zmw-view .zm-current-banner, html[data-theme="ink"] #zmw-view .zm-refresh-banner { border: 2px solid #0a0a0a; border-radius: 6px; background: #d6f0ff; box-shadow: 3px 3px 0 #0a0a0a; }
 html[data-theme="ink"] #zmw-view .zm-svc {
	background: #ffffff; border: 2px solid #0a0a0a; border-radius: 6px; box-shadow: 3px 3px 0 #0a0a0a;
}
 html[data-theme="ink"] #zmw-view .zm-svc.zm-svc-on { background: #0a9cff; border-color: #0a0a0a; }
html[data-theme="ink"] #zmw-view .zm-seg { border: 2px solid #0a0a0a; border-radius: 6px; background: #ffffff; }
html[data-theme="ink"] #zmw-view .zm-seg-item { border-radius: 3px; color: #0a0a0a; }
html[data-theme="ink"] #zmw-view .zm-seg-item.zm-active { background: #0a9cff; color: #0a0a0a; box-shadow: none; outline: 2px solid #0a0a0a; }
html[data-theme="ink"] #zmw-view .zm-switch { border: 2px solid #0a0a0a; background: #ffffff; }
html[data-theme="ink"] #zmw-view .zm-switch > span { border: 2px solid #0a0a0a; box-shadow: none; top: 1px; left: 1px; }
html[data-theme="ink"] #zmw-view .zm-switch.zm-switch-on { background: #0a9cff; }
html[data-theme="ink"] #zmw-view a:not(.cbi-button), html[data-theme="ink"] .zm-dock a:not(.cbi-button), html[data-theme="ink"] .zmw-modal a:not(.cbi-button) { color: #0060c0; text-decoration: underline; text-underline-offset: 2px; }
html[data-theme="ink"] .zmw-logo svg { filter: none; }
html[data-theme="ink"] .zmw-logo-lg::after { display: none; }
html[data-theme="bento"] {
	--font: "Onest", system-ui, sans-serif;
	--a1: #1c1a17; --a2: #1c1a17; --a3: #5b554c;
	--grad: #1c1a17; --grad-soft: #e4ddd0; --ring: 0 0 0 3px rgba(28,26,23,.2);
	--radius: 28px; --radius-sm: 16px;
	--bg: #efebe4; --bg-glow-1: transparent; --bg-glow-2: transparent;
	--surface: #ffffff; --surface-solid: #ffffff; --surface-2: #f6f2ea; --surface-3: #eee8dd;
	--side-bg: #efebe4; --border: rgba(28,26,23,.06); --border-2: rgba(28,26,23,.12);
	--text: #1c1a17; --text-2: #3d3830; --muted: #6f685d;
	--shadow: none; --shadow-lg: 0 24px 60px -24px rgba(28,26,23,.35);
	--input-bg: #f6f2ea;
	--ok: #1f5a2c; --ok-bg: #d8f0dc; --ok-dot: #2f7d4f;
	--bad: #8a1c14; --bad-bg: #ffd9d4; --bad-dot: #d64532;
	--warn: #7a4a0f; --warn-bg: #ffe2b8; --warn-dot: #d98a1c;
	--off: #6f685d; --off-bg: #eee8dd;
	color-scheme: light;
}
html[data-theme="bento"] body.zmw-body { background-image: none; }
html[data-theme="bento"] .zmw-orbs, html[data-theme="bento"] .zmw-grid-bg { display: none; }
html[data-theme="bento"] .zmw-top { --zmw-top-bg: rgb(239,235,228); background: var(--zmw-top-bg); }
html[data-theme="bento"] .zmw-title { font-family: "Unbounded", sans-serif; font-weight: 800; letter-spacing: -.03em; }
html[data-theme="bento"] .zmw-side { background: transparent; border-right: 0; box-shadow: none; backdrop-filter: none; -webkit-backdrop-filter: none; }
@media (max-width: 960px) {
	html[data-theme="bento"] .zmw-side { background: var(--side-bg); box-shadow: var(--shadow-lg); }
}
html[data-theme="bento"] .zmw-nav-item { border-radius: 999px; }
html[data-theme="bento"] .zmw-nav-item:hover { background: #ffffff; }
html[data-theme="bento"] .zmw-nav-item.zmw-active { background: #1c1a17; color: #ffffff; }
html[data-theme="bento"] .zmw-nav-item.zmw-active::before { display: none; }
html[data-theme="bento"] .zmw-nav-item.zmw-active .zmw-nav-ico { color: #ffffff; }
html[data-theme="bento"] .zmw-mem-bar { height: 8px; background: #e4ddd0; }
html[data-theme="bento"] .zmw-mem-bar i { background: #1c1a17; }
html[data-theme="bento"] #zmw-view .zm-card { background: #ffffff; border: 0; border-radius: 30px; box-shadow: none; backdrop-filter: none; -webkit-backdrop-filter: none; padding: 26px 28px; }
html[data-theme="bento"] #zmw-view .zm-cards > .zm-card:nth-child(4n+2) { background: #dcecff; }
html[data-theme="bento"] #zmw-view .zm-cards > .zm-card:nth-child(4n+3) { background: #ffe6c4; }
html[data-theme="bento"] #zmw-view .zm-cards > .zm-card:nth-child(4n+4) { background: #dff2e2; }
html[data-theme="bento"] #zmw-view .zm-card h3::before { display: none; }
html[data-theme="bento"] #zmw-view .zm-card h3 { font-size: 15px; font-weight: 600; color: inherit; opacity: .8; }
html[data-theme="bento"] #zmw-view .cbi-button, html[data-theme="bento"] .zmw-icon-btn, html[data-theme="bento"] .zm-dock .cbi-button, html[data-theme="bento"] .zmw-modal .cbi-button { border-radius: 14px; border: 0; background: #f6f2ea; color: #1c1a17; box-shadow: none; }
html[data-theme="bento"] #zmw-view .cbi-button:hover, html[data-theme="bento"] .zmw-icon-btn:hover, html[data-theme="bento"] .zm-dock .cbi-button:hover, html[data-theme="bento"] .zmw-modal .cbi-button:hover { background: #e4ddd0; transform: none; }
html[data-theme="bento"] #zmw-view .cbi-button-positive, html[data-theme="bento"] #zmw-view .cbi-button-positive:hover, html[data-theme="bento"] .zmw-btn-primary, html[data-theme="bento"] .zm-dock .cbi-button-positive, html[data-theme="bento"] .zm-dock .cbi-button-positive:hover, html[data-theme="bento"] .zmw-modal .cbi-button-positive, html[data-theme="bento"] .zmw-modal .cbi-button-positive:hover { background: #1c1a17; color: #ffffff; border: 0; box-shadow: none; }
html[data-theme="bento"] #zmw-view .cbi-button-remove, html[data-theme="bento"] #zmw-view .cbi-button-remove:hover, html[data-theme="bento"] .zm-dock .cbi-button-remove, html[data-theme="bento"] .zm-dock .cbi-button-remove:hover, html[data-theme="bento"] .zmw-modal .cbi-button-remove, html[data-theme="bento"] .zmw-modal .cbi-button-remove:hover { background: #ffd9d4; color: #8a1c14; }
html[data-theme="bento"] #zmw-view .zm-tile { border-radius: 18px; border: 0; background: #f6f2ea; }
html[data-theme="bento"] #zmw-view .zm-tile.zm-active { background: #1c1a17; color: #ffffff; border: 0; }
html[data-theme="bento"] #zmw-view .zm-badge, html[data-theme="bento"] .zm-dock .zm-badge, html[data-theme="bento"] .zmw-modal .zm-badge { border-radius: 999px; }
html[data-theme="bento"] #zmw-view .zm-log, html[data-theme="bento"] #zmw-view .zm-config-editor { border-radius: 24px; }
html[data-theme="bento"] .zmw-login-card, html[data-theme="bento"] .zmw-modal, html[data-theme="bento"] .zmw-theme-menu { border: 0; border-radius: 28px; background: #ffffff; backdrop-filter: none; }

html[data-theme="minimal"] {
	--font: "IBM Plex Sans", system-ui, sans-serif;
	--a1: #0078e8; --a2: #0078e8; --a3: #0078e8;
	--grad: #0078e8; --grad-soft: transparent; --ring: 0 0 0 2px rgba(0,120,232,.35);
	--radius: 0px; --radius-sm: 0px;
	--bg: #ffffff; --bg-glow-1: transparent; --bg-glow-2: transparent;
	--surface: #ffffff; --surface-solid: #ffffff; --surface-2: #fafafa; --surface-3: #f0f0f0;
	--side-bg: #ffffff; --border: #ececec; --border-2: #e0e0e0;
	--text: #111111; --text-2: #333333; --muted: #6b6b6b;
	--shadow: none; --shadow-lg: 0 20px 60px -30px rgba(0,0,0,.25);
	--input-bg: #ffffff;
	--ok: #111111; --ok-bg: transparent; --ok-dot: #0078e8;
	--bad: #b3261e; --bad-bg: transparent; --bad-dot: #b3261e;
	--warn: #111111; --warn-bg: transparent; --warn-dot: #c77700;
	--off: #6b6b6b; --off-bg: transparent;
	color-scheme: light;
}
html[data-theme="minimal"] body.zmw-body { background-image: none; font-weight: 300; }
html[data-theme="minimal"] .zmw-orbs, html[data-theme="minimal"] .zmw-grid-bg { display: none; }
html[data-theme="minimal"] .zmw-top { --zmw-top-bg: #ffffff; background: var(--zmw-top-bg); }
html[data-theme="minimal"] .zmw-title { font-weight: 300; font-size: 34px; letter-spacing: -.03em; }
html[data-theme="minimal"] .zmw-side { background: #ffffff; border-right: 1px solid #ececec; box-shadow: none; backdrop-filter: none; -webkit-backdrop-filter: none; }
html[data-theme="minimal"] .zmw-logo svg { filter: grayscale(1) brightness(.2); }
html[data-theme="minimal"] .zmw-nav-item { border-radius: 0; font-weight: 400; color: #6b6b6b; }
html[data-theme="minimal"] .zmw-nav-item:hover { background: none; color: #111111; }
html[data-theme="minimal"] .zmw-nav-item.zmw-active { background: none; color: #111111; font-weight: 500; }
html[data-theme="minimal"] .zmw-nav-item.zmw-active::before { background: #111111; width: 2px; border-radius: 0; }
html[data-theme="minimal"] .zmw-nav-ico { opacity: .5; }
html[data-theme="minimal"] .zmw-mem-bar { height: 2px; background: #ececec; border-radius: 0; }
html[data-theme="minimal"] .zmw-mem-bar i { background: #111111; border-radius: 0; }
html[data-theme="minimal"] #zmw-view .zm-card { border: 0; border-top: 1px solid #ececec; border-radius: 0; box-shadow: none; background: transparent; backdrop-filter: none; -webkit-backdrop-filter: none; padding: 28px 0; }
html[data-theme="minimal"] #zmw-view .zm-card:hover { box-shadow: none; }
html[data-theme="minimal"] #zmw-view .zm-card h3 { font-weight: 400; font-size: 13px; text-transform: uppercase; letter-spacing: .12em; color: #6b6b6b; }
html[data-theme="minimal"] #zmw-view .zm-card h3::before { display: none; }
html[data-theme="minimal"] #zmw-view .cbi-button, html[data-theme="minimal"] .zmw-icon-btn, html[data-theme="minimal"] .zm-dock .cbi-button, html[data-theme="minimal"] .zmw-modal .cbi-button { border-radius: 0; border: 1px solid #111111; background: #ffffff; color: #111111; box-shadow: none; font-weight: 400; }
html[data-theme="minimal"] #zmw-view .cbi-button:hover, html[data-theme="minimal"] .zmw-icon-btn:hover, html[data-theme="minimal"] .zm-dock .cbi-button:hover, html[data-theme="minimal"] .zmw-modal .cbi-button:hover { background: #111111; color: #ffffff; transform: none; }
html[data-theme="minimal"] #zmw-view .cbi-button-positive, html[data-theme="minimal"] #zmw-view .cbi-button-positive:hover, html[data-theme="minimal"] .zmw-btn-primary, html[data-theme="minimal"] .zm-dock .cbi-button-positive, html[data-theme="minimal"] .zm-dock .cbi-button-positive:hover, html[data-theme="minimal"] .zmw-modal .cbi-button-positive, html[data-theme="minimal"] .zmw-modal .cbi-button-positive:hover { background: #111111; color: #ffffff; border: 1px solid #111111; box-shadow: none; }
html[data-theme="minimal"] #zmw-view .cbi-button-remove, html[data-theme="minimal"] .zm-dock .cbi-button-remove, html[data-theme="minimal"] .zmw-modal .cbi-button-remove { border-color: #b3261e; color: #b3261e; background: #ffffff; }
html[data-theme="minimal"] #zmw-view .cbi-button-remove:hover, html[data-theme="minimal"] .zm-dock .cbi-button-remove:hover, html[data-theme="minimal"] .zmw-modal .cbi-button-remove:hover { background: #b3261e; color: #ffffff; }
html[data-theme="minimal"] #zmw-view .zm-tile { border-radius: 0; border: 1px solid #e0e0e0; background: #ffffff; font-weight: 400; }
html[data-theme="minimal"] #zmw-view .zm-tile.zm-active { border-color: #111111; background: #ffffff; color: #111111; box-shadow: inset 0 0 0 1px #111111; }
html[data-theme="minimal"] #zmw-view .zm-tile.zm-active::before { color: #0078e8; }
html[data-theme="minimal"] #zmw-view .zm-badge, html[data-theme="minimal"] .zm-dock .zm-badge, html[data-theme="minimal"] .zmw-modal .zm-badge { padding-left: 0; font-weight: 400; }
html[data-theme="minimal"] #zmw-view .zm-badge .zm-dot, html[data-theme="minimal"] .zm-dock .zm-badge .zm-dot, html[data-theme="minimal"] .zmw-modal .zm-badge .zm-dot { width: 6px; height: 6px; box-shadow: none; animation: none; }
html[data-theme="minimal"] #zmw-view .zm-log, html[data-theme="minimal"] #zmw-view .zm-config-editor { border-radius: 0; }
html[data-theme="minimal"] .zmw-login-card, html[data-theme="minimal"] .zmw-modal, html[data-theme="minimal"] .zmw-theme-menu { border-radius: 0; border: 1px solid #111111; box-shadow: none; background: #ffffff; backdrop-filter: none; }
html[data-theme="minimal"] .zmw-theme-opt { border-radius: 0; }

html[data-theme="retro"] {
	--font: Tahoma, Verdana, "Segoe UI", sans-serif;
	--a1: #000080; --a2: #000080; --a3: #1084d0;
	--grad: linear-gradient(90deg, #000080, #1084d0); --grad-soft: #dcdcdc; --ring: 0 0 0 1px #000000;
	--radius: 0px; --radius-sm: 0px;
	--bg: #008080; --bg-glow-1: transparent; --bg-glow-2: transparent;
	--surface: #c0c0c0; --surface-solid: #c0c0c0; --surface-2: #d4d0c8; --surface-3: #ffffff;
	--side-bg: #c0c0c0; --border: #808080; --border-2: #000000;
	--text: #000000; --text-2: #000000; --muted: #404040;
	--shadow: none; --shadow-lg: none;
	--input-bg: #ffffff; --console: #000000; --console-border: #808080;
	--ok: #006400; --ok-bg: transparent; --ok-dot: #008000;
	--bad: #a00000; --bad-bg: transparent; --bad-dot: #ff0000;
	--warn: #806000; --warn-bg: transparent; --warn-dot: #c0a000;
	--off: #404040; --off-bg: transparent;
	color-scheme: light;
}
html[data-theme="retro"] body.zmw-body { background-image: none; font-size: 13px; }
html[data-theme="retro"] .zmw-orbs, html[data-theme="retro"] .zmw-grid-bg { display: none; }
html[data-theme="retro"] .zmw-top { --zmw-top-bg: #008080; background: var(--zmw-top-bg); }
html[data-theme="retro"] .zmw-title, html[data-theme="retro"] .zmw-sub { color: #ffffff; }
html[data-theme="retro"] .zmw-title { font-size: 20px; font-weight: 700; letter-spacing: 0; }
html[data-theme="retro"] .zmw-side { background: #c0c0c0; border-right: 2px solid #000000; box-shadow: inset -1px 0 0 #808080, inset 1px 1px 0 #ffffff; backdrop-filter: none; -webkit-backdrop-filter: none; }
html[data-theme="retro"] .zmw-nav-item { border-radius: 0; }
html[data-theme="retro"] .zmw-nav-item:hover { background: #d4d0c8; }
html[data-theme="retro"] .zmw-nav-item.zmw-active { background: #000080; color: #ffffff; }
html[data-theme="retro"] .zmw-nav-item.zmw-active::before { display: none; }
html[data-theme="retro"] .zmw-nav-item.zmw-active .zmw-nav-ico { color: #ffffff; }
html[data-theme="retro"] .zmw-nav-ico { border-radius: 0; }
html[data-theme="retro"] #zmw-view .zm-seg { border-radius: 0; background: #ffffff; border-top: 2px solid #808080; border-left: 2px solid #808080; border-right: 2px solid #ffffff; border-bottom: 2px solid #ffffff; }
html[data-theme="retro"] #zmw-view .zm-seg-item { border-radius: 0; }
 html[data-theme="retro"] #zmw-view .zm-chip { border-radius: 0; }
html[data-theme="retro"] .zmw-mem-bar { height: 16px; border-radius: 0; background: #ffffff; border-top: 1px solid #808080; border-left: 1px solid #808080; border-right: 1px solid #ffffff; border-bottom: 1px solid #ffffff; padding: 2px; box-sizing: border-box; }
html[data-theme="retro"] .zmw-mem-bar i { border-radius: 0; background: repeating-linear-gradient(90deg, #000080 0 8px, transparent 8px 10px); }
html[data-theme="retro"] .zmw-mem-mid .zmw-mem-bar i, html[data-theme="retro"] .zmw-mem-hi .zmw-mem-bar i { background: repeating-linear-gradient(90deg, #a00000 0 8px, transparent 8px 10px); }
html[data-theme="retro"] #zmw-view .zm-card {
	background: #c0c0c0; border-radius: 0; backdrop-filter: none; -webkit-backdrop-filter: none;
	border-top: 2px solid #ffffff; border-left: 2px solid #ffffff; border-right: 2px solid #000000; border-bottom: 2px solid #000000;
	box-shadow: inset -1px -1px 0 #808080, inset 1px 1px 0 #dfdfdf;
}
html[data-theme="retro"] #zmw-view .zm-card { padding: 0 14px 14px; }
html[data-theme="retro"] #zmw-view .zm-card h3 { margin: 3px -11px 14px; padding: 5px 8px; background: linear-gradient(90deg, #000080, #1084d0); color: #ffffff; font-size: 13px; font-weight: 700; }
html[data-theme="retro"] #zmw-view .zm-card h3::before { display: none; }
html[data-theme="retro"] #zmw-view .zm-card h3 .zm-badge { color: #ffffff; background: rgba(255,255,255,.14); padding: 0 6px; }
html[data-theme="retro"] #zmw-view .cbi-button, html[data-theme="retro"] .zmw-icon-btn, html[data-theme="retro"] .zmw-btn-primary, html[data-theme="retro"] .zm-dock .cbi-button, html[data-theme="retro"] .zmw-modal .cbi-button {
	border-radius: 0; background: #c0c0c0; color: #000000; box-shadow: inset -1px -1px 0 #808080, inset 1px 1px 0 #dfdfdf;
	border-top: 2px solid #ffffff; border-left: 2px solid #ffffff; border-right: 2px solid #000000; border-bottom: 2px solid #000000; font-weight: 400;
}
html[data-theme="retro"] #zmw-view .cbi-button:hover, html[data-theme="retro"] .zmw-icon-btn:hover, html[data-theme="retro"] .zm-dock .cbi-button:hover, html[data-theme="retro"] .zmw-modal .cbi-button:hover { background: #c0c0c0; transform: none; }
html[data-theme="retro"] #zmw-view .cbi-button:active, html[data-theme="retro"] .zmw-icon-btn:active, html[data-theme="retro"] .zm-dock .cbi-button:active, html[data-theme="retro"] .zmw-modal .cbi-button:active { border-top-color: #000000; border-left-color: #000000; border-right-color: #ffffff; border-bottom-color: #ffffff; }
html[data-theme="retro"] #zmw-view .cbi-button-positive, html[data-theme="retro"] #zmw-view .cbi-button-positive:hover, html[data-theme="retro"] .zm-dock .cbi-button-positive, html[data-theme="retro"] .zm-dock .cbi-button-positive:hover, html[data-theme="retro"] .zmw-modal .cbi-button-positive, html[data-theme="retro"] .zmw-modal .cbi-button-positive:hover { background: #c0c0c0; color: #000000; font-weight: 700; outline: 1px dotted #000000; outline-offset: -5px; }
html[data-theme="retro"] #zmw-view .cbi-button-remove, html[data-theme="retro"] #zmw-view .cbi-button-remove:hover, html[data-theme="retro"] .zm-dock .cbi-button-remove, html[data-theme="retro"] .zm-dock .cbi-button-remove:hover, html[data-theme="retro"] .zmw-modal .cbi-button-remove, html[data-theme="retro"] .zmw-modal .cbi-button-remove:hover { background: #c0c0c0; color: #a00000; }
html[data-theme="retro"] #zmw-view .zm-tile { border-radius: 0; background: #ffffff; border-top: 2px solid #808080; border-left: 2px solid #808080; border-right: 2px solid #ffffff; border-bottom: 2px solid #ffffff; }
html[data-theme="retro"] #zmw-view .zm-tile.zm-active { background: #000080; color: #ffffff; }
html[data-theme="retro"] #zmw-view .zm-badge, html[data-theme="retro"] .zm-dock .zm-badge, html[data-theme="retro"] .zmw-modal .zm-badge { border-radius: 0; padding-left: 0; }
html[data-theme="retro"] #zmw-view .zm-badge .zm-dot, html[data-theme="retro"] .zm-dock .zm-badge .zm-dot, html[data-theme="retro"] .zmw-modal .zm-badge .zm-dot { box-shadow: none; animation: none; }
html[data-theme="retro"] #zmw-view input, html[data-theme="retro"] #zmw-view select, html[data-theme="retro"] #zmw-view textarea:not(.zm-config-editor), html[data-theme="retro"] .zmw-input {
	border-radius: 0; background: #ffffff; border-top: 2px solid #808080; border-left: 2px solid #808080; border-right: 2px solid #ffffff; border-bottom: 2px solid #ffffff;
}
html[data-theme="retro"] #zmw-view .zm-log, html[data-theme="retro"] #zmw-view .zm-config-editor { border-radius: 0; }
html[data-theme="retro"] .zmw-login-card, html[data-theme="retro"] .zmw-modal, html[data-theme="retro"] .zmw-theme-menu {
	border-radius: 0; background: #c0c0c0; backdrop-filter: none; box-shadow: inset -1px -1px 0 #808080, inset 1px 1px 0 #dfdfdf;
	border-top: 2px solid #ffffff; border-left: 2px solid #ffffff; border-right: 2px solid #000000; border-bottom: 2px solid #000000;
}
html[data-theme="retro"] .zmw-theme-opt { border-radius: 0; }
html[data-theme="retro"] .zmw-theme-opt:hover, html[data-theme="retro"] .zmw-theme-opt.zmw-on { background: #000080; color: #ffffff; }
html[data-theme="retro"] .zmw-foot { color: #ffffff; }

html[data-theme="depth"] {
	--font: "Onest", system-ui, sans-serif;
	--a1: #00b6ff; --a2: #0090ff; --a3: #7fdcff;
	--grad: linear-gradient(180deg, #33c6ff, #0090ff); --grad-soft: rgba(0,182,255,.14); --ring: 0 0 0 3px rgba(0,182,255,.4);
	--radius: 20px; --radius-sm: 14px;
	--bg: #0a0e18; --bg-glow-1: rgba(0,182,255,.18); --bg-glow-2: rgba(255,140,60,.10);
	--surface: #16203a; --surface-solid: #16203a; --surface-2: rgba(127,220,255,.06); --surface-3: rgba(127,220,255,.12);
	--side-bg: rgba(10,14,24,.85); --border: rgba(127,220,255,.16); --border-2: rgba(127,220,255,.3);
	--text: #e8eefc; --text-2: #c7d3ea; --muted: #9fb0cc;
	--shadow: 0 1px 0 rgba(255,255,255,.08) inset, 0 10px 0 -2px #0c1426, 0 28px 50px -12px rgba(0,0,0,.8);
	--shadow-lg: 0 40px 90px -30px rgba(0,0,0,.9);
	--input-bg: rgba(255,255,255,.05); --console: #060910; --console-border: rgba(127,220,255,.2);
	--ok: #5ef0a8; --ok-bg: rgba(94,240,168,.12); --ok-dot: #5ef0a8;
	--bad: #ff7b7b; --bad-bg: rgba(255,123,123,.12); --bad-dot: #ff7b7b;
	--warn: #ffc48a; --warn-bg: rgba(255,196,138,.12); --warn-dot: #ff9a4d;
	--off: #9fb0cc; --off-bg: rgba(159,176,204,.12);
	color-scheme: dark;
}
html[data-theme="depth"] .zmw-title { font-family: "Unbounded", sans-serif; font-weight: 800; }
html[data-theme="depth"] .zmw-top { --zmw-top-bg: rgb(10,14,24); background: var(--zmw-top-bg); }
html[data-theme="depth"] #zmw-view { perspective: 1600px; }
html[data-theme="depth"] #zmw-view .zm-card {
	background: linear-gradient(160deg, #1b2740, #121a2c); border: 1px solid rgba(127,220,255,.2);
	transform: translateZ(0); transition: transform .35s cubic-bezier(.2,.8,.2,1), box-shadow .35s;
}
html[data-theme="depth"] #zmw-view .zm-card:hover { transform: rotateX(4deg) translateY(-4px); box-shadow: 0 1px 0 rgba(255,255,255,.1) inset, 0 14px 0 -2px #0c1426, 0 40px 60px -14px rgba(0,0,0,.85), 0 0 40px -10px rgba(0,182,255,.35); border-color: rgba(127,220,255,.4); }
html[data-theme="depth"] #zmw-view .cbi-button, html[data-theme="depth"] .zmw-icon-btn, html[data-theme="depth"] .zm-dock .cbi-button, html[data-theme="depth"] .zmw-modal .cbi-button {
	background: #1e2b48; border: 1px solid rgba(127,220,255,.25); color: #e8eefc;
	box-shadow: 0 4px 0 #0c1426, 0 8px 16px -6px rgba(0,0,0,.7); transition: transform .08s, box-shadow .08s;
}
html[data-theme="depth"] #zmw-view .cbi-button:hover, html[data-theme="depth"] .zmw-icon-btn:hover, html[data-theme="depth"] .zm-dock .cbi-button:hover, html[data-theme="depth"] .zmw-modal .cbi-button:hover { background: #253559; transform: translateY(-1px); }
html[data-theme="depth"] #zmw-view .cbi-button:active, html[data-theme="depth"] .zmw-icon-btn:active, html[data-theme="depth"] .zm-dock .cbi-button:active, html[data-theme="depth"] .zmw-modal .cbi-button:active { transform: translateY(4px); box-shadow: 0 0 0 #0c1426; }
html[data-theme="depth"] #zmw-view .cbi-button-positive, html[data-theme="depth"] #zmw-view .cbi-button-positive:hover, html[data-theme="depth"] .zmw-btn-primary, html[data-theme="depth"] .zm-dock .cbi-button-positive, html[data-theme="depth"] .zm-dock .cbi-button-positive:hover, html[data-theme="depth"] .zmw-modal .cbi-button-positive, html[data-theme="depth"] .zmw-modal .cbi-button-positive:hover { background: linear-gradient(180deg, #33c6ff, #0090ff); color: #04111f; border-color: #0090ff; box-shadow: 0 4px 0 #005a9e, 0 10px 24px -8px rgba(0,182,255,.8); }
html[data-theme="depth"] #zmw-view .cbi-button-remove, html[data-theme="depth"] #zmw-view .cbi-button-remove:hover, html[data-theme="depth"] .zm-dock .cbi-button-remove, html[data-theme="depth"] .zm-dock .cbi-button-remove:hover, html[data-theme="depth"] .zmw-modal .cbi-button-remove, html[data-theme="depth"] .zmw-modal .cbi-button-remove:hover { background: linear-gradient(180deg, #ff8a7a, #e84a3a); color: #1a0503; border-color: #e84a3a; box-shadow: 0 4px 0 #8f2419; }
html[data-theme="depth"] #zmw-view .zm-tile { background: #1e2b48; border: 1px solid rgba(127,220,255,.2); box-shadow: 0 4px 0 #0c1426; transition: transform .15s, box-shadow .15s; }
html[data-theme="depth"] #zmw-view .zm-tile:hover { transform: translateY(-2px); box-shadow: 0 6px 0 #0c1426, 0 14px 24px -10px rgba(0,182,255,.5); }
html[data-theme="depth"] #zmw-view .zm-tile.zm-active { background: linear-gradient(180deg, #33c6ff, #0090ff); color: #04111f; border-color: #0090ff; box-shadow: 0 4px 0 #005a9e; }
html[data-theme="depth"] .zmw-side { box-shadow: 10px 0 40px -20px rgba(0,0,0,.8); }
html[data-theme="depth"] .zmw-nav-item.zmw-active { background: linear-gradient(180deg, rgba(0,182,255,.25), rgba(0,144,255,.12)); box-shadow: 0 3px 0 #0c1426, inset 0 1px 0 rgba(255,255,255,.08); }
html[data-theme="depth"] .zmw-mem-bar { background: #0c1426; box-shadow: inset 0 2px 3px rgba(0,0,0,.6); }
html[data-theme="depth"] .zmw-mem-bar i { background: linear-gradient(180deg, #7fdcff, #0090ff); box-shadow: 0 0 10px rgba(0,182,255,.6); }
html[data-theme="depth"] .zmw-login-card, html[data-theme="depth"] .zmw-modal, html[data-theme="depth"] .zmw-theme-menu { background: linear-gradient(160deg, #1b2740, #121a2c); border: 1px solid rgba(127,220,255,.25); }

.zmw-theme-menu { max-height: calc(100vh - 90px); overflow-y: auto; }
html[data-theme="bento"] #zmw-view .zm-tile.zm-active::before { color: #9fe0b0; }
html[data-theme="bento"] .zmw-theme-opt.zmw-on { background: #1c1a17; color: #ffffff; }
html[data-theme="bento"] .zmw-theme-opt.zmw-on .zmw-theme-mark { color: #9fe0b0; }
html[data-theme="minimal"] .zmw-theme-opt.zmw-on { background: #f3f3f3; }
html[data-theme="retro"] #zmw-view .zm-tile.zm-active::before { color: #ffff00; }
html[data-theme="retro"] .zmw-theme-opt:hover .zmw-theme-mark, html[data-theme="retro"] .zmw-theme-opt.zmw-on .zmw-theme-mark { color: #ffff00; }
html[data-theme="retro"] .zmw-nav-item { padding-left: 12px; }
html[data-theme="depth"] #zmw-view .zm-tile.zm-active::before { color: #04111f; }
html[data-theme="depth"] .zmw-theme-mark { color: #7fdcff; }
html[data-theme="bento"] #zmw-view .zm-seg-item.zm-active, html[data-theme="retro"] #zmw-view .zm-seg-item.zm-active { color: #ffffff; }
.zmw-theme-menu { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 2px 4px; width: 340px; max-width: calc(100vw - 16px); }
.zmw-theme-group { grid-column: 1 / -1; padding: 8px 10px 4px; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .1em; color: var(--muted); }
.zmw-theme-group:first-child { padding-top: 4px; }
.zmw-theme-opt { min-width: 0; }
.zmw-theme-opt > span:nth-of-type(1) { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

html[data-theme="micro"] {
	--font: "Onest", system-ui, sans-serif;
	--a1: #2d5bff; --a2: #2d5bff; --a3: #2d5bff;
	--grad: #2d5bff; --grad-soft: #e6ecff; --ring: 0 0 0 3px #2d5bff55;
	--radius: 20px; --radius-sm: 20px;
	--bg: #f4f5f8; --bg-glow-1: transparent; --bg-glow-2: transparent;
	--surface: #ffffff; --surface-solid: #ffffff; --surface-2: #f7f8fb; --surface-3: #eceff5;
	--side-bg: #ffffff; --border: #e3e6ee; --border-2: #e3e6ee;
	--text: #000000; --text-2: #000000; --muted: #000000;
	--shadow: 0 1px 2px rgba(0,0,0,.04); --shadow-lg: 0 30px 70px -30px rgba(0,0,0,.45);
	--input-bg: #f7f8fb;
	--ok: #11643e; --ok-bg: #dcf5e9; --ok-dot: #11643e;
	--warn: #7a4d00; --warn-bg: #fff1d6; --warn-dot: #7a4d00;
	--bad: #9a1f1f; --bad-bg: #ffe1e1; --bad-dot: #9a1f1f;
	--off: #4a5266; --off-bg: #eceff5;
	color-scheme: light;
}
html[data-theme="micro"] body.zmw-body { background: #f4f5f8; }
html[data-theme="micro"] .zmw-orbs, html[data-theme="micro"] .zmw-grid-bg { display: none; }
html[data-theme="micro"] .zmw-top { --zmw-top-bg: #f4f5f8; background: var(--zmw-top-bg); }
html[data-theme="micro"] .zmw-title { font-family: "Onest", sans-serif; color: #000000; }
html[data-theme="micro"] .zmw-sub, html[data-theme="micro"] .zmw-foot { color: #000000; }
html[data-theme="micro"] .zmw-side { background: #ffffff; border-right: 1px solid #e3e6ee; box-shadow: none; backdrop-filter: none; -webkit-backdrop-filter: none; color: #000000; }
html[data-theme="micro"] .zmw-brand-name, html[data-theme="micro"] .zmw-mem-row { color: #000000; }
html[data-theme="micro"] .zmw-nav-group, html[data-theme="micro"] .zmw-mem-label { color: #000000; }
html[data-theme="micro"] .zmw-nav-item { color: #000000; border-radius: 12px; }
html[data-theme="micro"] .zmw-nav-item:hover { background: #f0f3fa; color: #000000; }
html[data-theme="micro"] .zmw-nav-item.zmw-active { background: #2d5bff; color: #ffffff; box-shadow: inset 0 0 0 2px #000000; font-weight: 700; }
html[data-theme="micro"] .zmw-nav-item.zmw-active::before { display: none; }
html[data-theme="micro"] .zmw-nav-item.zmw-active .zmw-nav-ico { color: #ffffff; }
html[data-theme="micro"] .zmw-mem-bar { background: #e3e6ee; border-radius: 6px; }
html[data-theme="micro"] .zmw-mem-bar i { background: #2d5bff; border-radius: inherit; }
html[data-theme="micro"] #zmw-view .zm-card { background: #ffffff; border: 1px solid #e3e6ee; border-radius: 20px; box-shadow: 0 1px 2px rgba(0,0,0,.04); backdrop-filter: none; -webkit-backdrop-filter: none; color: #000000; }
html[data-theme="micro"] #zmw-view .zm-card:hover { border-color: #e3e6ee; }
html[data-theme="micro"] #zmw-view .zm-card h3 { color: #000000; } html[data-theme="micro"] #zmw-view .zm-card h3::before { background: #2d5bff; }
html[data-theme="micro"] #zmw-view .zm-hint, html[data-theme="micro"] #zmw-view p.zm-hint, html[data-theme="micro"] #zmw-view .zm-label, html[data-theme="micro"] .zm-dock .zm-hint, html[data-theme="micro"] .zm-dock p.zm-hint, html[data-theme="micro"] .zmw-modal .zm-hint, html[data-theme="micro"] .zmw-modal p.zm-hint { color: #000000; opacity: 1; }
html[data-theme="micro"] #zmw-view a:not(.cbi-button), html[data-theme="micro"] .zm-dock a:not(.cbi-button), html[data-theme="micro"] .zmw-modal a:not(.cbi-button) { color: #2d5bff; }
html[data-theme="micro"] #zmw-view .cbi-button, html[data-theme="micro"] .zmw-icon-btn, html[data-theme="micro"] .zm-dock .cbi-button, html[data-theme="micro"] .zmw-modal .cbi-button { background: #f7f8fb; color: #000000; border: 1px solid #e3e6ee; border-radius: 14px; box-shadow: 0 1px 2px rgba(0,0,0,.06); }
html[data-theme="micro"] #zmw-view .cbi-button:hover, html[data-theme="micro"] .zmw-icon-btn:hover, html[data-theme="micro"] .zm-dock .cbi-button:hover, html[data-theme="micro"] .zmw-modal .cbi-button:hover { background: #eceff5; color: #000000; }
html[data-theme="micro"] #zmw-view .cbi-button-positive, html[data-theme="micro"] #zmw-view .cbi-button-positive:hover, html[data-theme="micro"] .zmw-btn-primary, html[data-theme="micro"] .zm-dock .cbi-button-positive, html[data-theme="micro"] .zm-dock .cbi-button-positive:hover, html[data-theme="micro"] .zmw-modal .cbi-button-positive, html[data-theme="micro"] .zmw-modal .cbi-button-positive:hover { background: #2d5bff; color: #ffffff; border-color: #2d5bff; }
html[data-theme="micro"] #zmw-view .cbi-button-remove, html[data-theme="micro"] #zmw-view .cbi-button-remove:hover, html[data-theme="micro"] .zm-dock .cbi-button-remove, html[data-theme="micro"] .zm-dock .cbi-button-remove:hover, html[data-theme="micro"] .zmw-modal .cbi-button-remove, html[data-theme="micro"] .zmw-modal .cbi-button-remove:hover { background: #ffe1e1; color: #9a1f1f; border-color: #ffe1e1; }
html[data-theme="micro"] #zmw-view .cbi-button-action, html[data-theme="micro"] #zmw-view .cbi-button-action:hover, html[data-theme="micro"] .zm-dock .cbi-button-action, html[data-theme="micro"] .zm-dock .cbi-button-action:hover, html[data-theme="micro"] .zmw-modal .cbi-button-action, html[data-theme="micro"] .zmw-modal .cbi-button-action:hover { background: #e6ecff; color: #000000; }
html[data-theme="micro"] #zmw-view .zm-tile:not(.zm-active), html[data-theme="micro"] #zmw-view .zm-tile { background: #f7f8fb; color: #000000; border: 1px solid #e3e6ee; border-radius: 14px; }
html[data-theme="micro"] #zmw-view .zm-tile.zm-active { background: #2d5bff; color: #ffffff; border-color: #2d5bff; }
html[data-theme="micro"] #zmw-view .zm-tile.zm-active::before { color: #ffffff; }
html[data-theme="micro"] #zmw-view .zm-seg-item { color: #000000; } html[data-theme="micro"] #zmw-view .zm-seg-item.zm-active { background: #2d5bff; color: #ffffff; }
html[data-theme="micro"] #zmw-view .zm-badge, html[data-theme="micro"] .zm-dock .zm-badge, html[data-theme="micro"] .zmw-modal .zm-badge { border-radius: 999px; }
html[data-theme="micro"] #zmw-view input, html[data-theme="micro"] #zmw-view select, html[data-theme="micro"] #zmw-view textarea:not(.zm-config-editor), html[data-theme="micro"] .zmw-input { background: #f7f8fb; color: #000000; border: 1px solid #e3e6ee; border-radius: 14px; }
html[data-theme="micro"] #zmw-view .zm-current-banner, html[data-theme="micro"] #zmw-view .zm-refresh-banner { background: #e6ecff; color: #000000; border-color: #2d5bff; }
html[data-theme="micro"] #zmw-view .zm-switch.zm-switch-on { background: #2d5bff; }
html[data-theme="micro"] .zmw-check input:checked + .zmw-check-box { background: #2d5bff; } html[data-theme="micro"] .zmw-check input:checked + .zmw-check-box::after { border-color: #ffffff; }
html[data-theme="micro"] .zmw-login-card, html[data-theme="micro"] .zmw-modal, html[data-theme="micro"] .zmw-theme-menu { background: #ffffff; color: #000000; border: 1px solid #e3e6ee; backdrop-filter: none; -webkit-backdrop-filter: none; }
html[data-theme="micro"] .zmw-theme-opt { color: #000000; } html[data-theme="micro"] .zmw-theme-opt:hover { background: #f7f8fb; }
html[data-theme="micro"] .zmw-theme-opt.zmw-on { background: #2d5bff; color: #ffffff; } html[data-theme="micro"] .zmw-theme-opt.zmw-on .zmw-theme-mark, html[data-theme="micro"] .zmw-theme-opt.zmw-on .zmw-i { color: #ffffff; }
html[data-theme="micro"] .zmw-theme-group { color: #000000; }
html[data-theme="micro"] #zmw-view .cbi-button, html[data-theme="micro"] .zmw-icon-btn, html[data-theme="micro"] .zmw-btn-primary, html[data-theme="micro"] .zm-dock .cbi-button, html[data-theme="micro"] .zmw-modal .cbi-button { transition: transform .12s, box-shadow .12s, background .2s, border-radius .25s; }
html[data-theme="micro"] #zmw-view .cbi-button:hover, html[data-theme="micro"] .zmw-icon-btn:hover, html[data-theme="micro"] .zm-dock .cbi-button:hover, html[data-theme="micro"] .zmw-modal .cbi-button:hover { transform: scale(1.03); }
html[data-theme="micro"] #zmw-view .cbi-button:active, html[data-theme="micro"] .zmw-icon-btn:active, html[data-theme="micro"] .zmw-btn-primary:active, html[data-theme="micro"] .zm-dock .cbi-button:active, html[data-theme="micro"] .zmw-modal .cbi-button:active { transform: scale(.95); box-shadow: none; }
html[data-theme="micro"] #zmw-view .cbi-button-positive:hover, html[data-theme="micro"] .zmw-btn-primary:hover, html[data-theme="micro"] .zm-dock .cbi-button-positive:hover, html[data-theme="micro"] .zmw-modal .cbi-button-positive:hover { border-radius: 22px; box-shadow: 0 12px 24px -10px rgba(45,91,255,.7); }
html[data-theme="micro"] #zmw-view .zm-tile { transition: transform .2s cubic-bezier(.2,.8,.2,1), box-shadow .2s; }
html[data-theme="micro"] #zmw-view .zm-tile:hover { transform: translateY(-2px); box-shadow: 0 10px 18px -12px rgba(45,91,255,.6); }
html[data-theme="micro"] #zmw-view .zm-badge .zm-dot, html[data-theme="micro"] .zm-dock .zm-badge .zm-dot, html[data-theme="micro"] .zmw-modal .zm-badge .zm-dot { animation: zmw-micro-ring 2s 3; }
@keyframes zmw-micro-ring { 0% { box-shadow: 0 0 0 0 rgba(30,180,110,.45); } 70% { box-shadow: 0 0 0 7px rgba(30,180,110,0); } 100% { box-shadow: 0 0 0 0 rgba(30,180,110,0); } }
html[data-theme="micro"] .zmw-nav-item { transition: background .2s, transform .15s; }
html[data-theme="micro"] .zmw-nav-item:active { transform: scale(.97); }
html[data-theme="micro"] .zmw-nav-group > span, html[data-theme="micro"] .zmw-foot, html[data-theme="micro"] #zmw-view .zm-row .zm-label, html[data-theme="micro"] #zmw-view .zm-hint, html[data-theme="micro"] .zm-dock .zm-hint, html[data-theme="micro"] #zmw-view .zm-svc-sub, html[data-theme="micro"] #zmw-view .zm-reboot-meta > span:first-child, html[data-theme="micro"] #zmw-view .zm-ab-log-when, html[data-theme="micro"] #zmw-view .zm-list-path, html[data-theme="micro"] #zmw-view .zm-ab-last .zm-label, html[data-theme="micro"] #zmw-view .zm-tt-rank, html[data-theme="micro"] #zmw-view .zm-seg-item { color: #000000; opacity: 1; }
html[data-theme="micro"] #zmw-view .zm-seg-item.zm-active { color: #ffffff; }
html[data-theme="ink"] #zmw-view .zm-actions.zmw-tabs { background: #ffffff; border: 2.5px solid #0a0a0a; border-radius: 6px; box-shadow: 4px 4px 0 #0a0a0a; backdrop-filter: none; }
html[data-theme="ink"] #zmw-view .zmw-tabs .cbi-button, html[data-theme="ink"] .zm-dock .zmw-tabs .cbi-button, html[data-theme="ink"] .zmw-modal .zmw-tabs .cbi-button { background: transparent; border: 2px solid transparent; border-radius: 4px; box-shadow: none; color: #0a0a0a; transform: none; }
html[data-theme="ink"] #zmw-view .zmw-tabs .cbi-button:hover, html[data-theme="ink"] .zm-dock .zmw-tabs .cbi-button:hover, html[data-theme="ink"] .zmw-modal .zmw-tabs .cbi-button:hover { background: #e8f6ff; border-color: transparent; box-shadow: none; }
html[data-theme="ink"] #zmw-view .zmw-tabs .cbi-button-positive, html[data-theme="ink"] #zmw-view .zmw-tabs .cbi-button-positive:hover, html[data-theme="ink"] .zm-dock .zmw-tabs .cbi-button-positive, html[data-theme="ink"] .zm-dock .zmw-tabs .cbi-button-positive:hover, html[data-theme="ink"] .zmw-modal .zmw-tabs .cbi-button-positive, html[data-theme="ink"] .zmw-modal .zmw-tabs .cbi-button-positive:hover { background: #0a9cff; border-color: #0a0a0a; color: #0a0a0a; box-shadow: none; }
html[data-theme="bento"] #zmw-view .zm-actions.zmw-tabs { background: #ffffff; border: 0; border-radius: 999px; box-shadow: none; backdrop-filter: none; }
html[data-theme="bento"] #zmw-view .zmw-tabs .cbi-button, html[data-theme="bento"] .zm-dock .zmw-tabs .cbi-button, html[data-theme="bento"] .zmw-modal .zmw-tabs .cbi-button { background: transparent; border: 0; border-radius: 999px; color: #6f685d; box-shadow: none; }
html[data-theme="bento"] #zmw-view .zmw-tabs .cbi-button:hover, html[data-theme="bento"] .zm-dock .zmw-tabs .cbi-button:hover, html[data-theme="bento"] .zmw-modal .zmw-tabs .cbi-button:hover { background: #f6f2ea; color: #1c1a17; }
html[data-theme="bento"] #zmw-view .zmw-tabs .cbi-button-positive, html[data-theme="bento"] #zmw-view .zmw-tabs .cbi-button-positive:hover, html[data-theme="bento"] .zm-dock .zmw-tabs .cbi-button-positive, html[data-theme="bento"] .zm-dock .zmw-tabs .cbi-button-positive:hover, html[data-theme="bento"] .zmw-modal .zmw-tabs .cbi-button-positive, html[data-theme="bento"] .zmw-modal .zmw-tabs .cbi-button-positive:hover { background: #1c1a17; color: #ffffff; }
html[data-theme="minimal"] #zmw-view .zm-actions.zmw-tabs { background: transparent; border: 0; border-bottom: 1px solid #e0e0e0; border-radius: 0; box-shadow: none; padding: 0; gap: 24px; backdrop-filter: none; }
html[data-theme="minimal"] #zmw-view .zmw-tabs .cbi-button, html[data-theme="minimal"] .zm-dock .zmw-tabs .cbi-button, html[data-theme="minimal"] .zmw-modal .zmw-tabs .cbi-button { background: transparent; border: 0; border-bottom: 2px solid transparent; border-radius: 0; color: #6b6b6b; padding: 10px 0; box-shadow: none; font-weight: 400; }
html[data-theme="minimal"] #zmw-view .zmw-tabs .cbi-button:hover, html[data-theme="minimal"] .zm-dock .zmw-tabs .cbi-button:hover, html[data-theme="minimal"] .zmw-modal .zmw-tabs .cbi-button:hover { background: transparent; color: #111111; }
html[data-theme="minimal"] #zmw-view .zmw-tabs .cbi-button-positive, html[data-theme="minimal"] #zmw-view .zmw-tabs .cbi-button-positive:hover, html[data-theme="minimal"] .zm-dock .zmw-tabs .cbi-button-positive, html[data-theme="minimal"] .zm-dock .zmw-tabs .cbi-button-positive:hover, html[data-theme="minimal"] .zmw-modal .zmw-tabs .cbi-button-positive, html[data-theme="minimal"] .zmw-modal .zmw-tabs .cbi-button-positive:hover { background: transparent; color: #111111; border-bottom-color: #111111; font-weight: 500; }
html[data-theme="retro"] #zmw-view .zm-actions.zmw-tabs { background: transparent; border: 0; border-bottom: 2px solid #ffffff; border-radius: 0; box-shadow: none; padding: 0 0 0 4px; gap: 2px; align-items: flex-end; backdrop-filter: none; }
html[data-theme="retro"] #zmw-view .zmw-tabs .cbi-button, html[data-theme="retro"] .zm-dock .zmw-tabs .cbi-button, html[data-theme="retro"] .zmw-modal .zmw-tabs .cbi-button { background: #c0c0c0; color: #000000; border-radius: 0; border-top: 2px solid #ffffff; border-left: 2px solid #ffffff; border-right: 2px solid #000000; border-bottom: 0; box-shadow: inset -1px 0 0 #808080; min-height: 30px; padding: 5px 16px; margin: 0; outline: none; font-weight: 400; }
html[data-theme="retro"] #zmw-view .zmw-tabs .cbi-button:hover, html[data-theme="retro"] .zm-dock .zmw-tabs .cbi-button:hover, html[data-theme="retro"] .zmw-modal .zmw-tabs .cbi-button:hover { background: #c0c0c0; color: #000000; }
html[data-theme="retro"] #zmw-view .zmw-tabs .cbi-button-positive, html[data-theme="retro"] #zmw-view .zmw-tabs .cbi-button-positive:hover, html[data-theme="retro"] .zm-dock .zmw-tabs .cbi-button-positive, html[data-theme="retro"] .zm-dock .zmw-tabs .cbi-button-positive:hover, html[data-theme="retro"] .zmw-modal .zmw-tabs .cbi-button-positive, html[data-theme="retro"] .zmw-modal .zmw-tabs .cbi-button-positive:hover { background: #c0c0c0; color: #000000; font-weight: 700; min-height: 34px; outline: none; margin-bottom: -2px; padding-bottom: 7px; }
html[data-theme="depth"] #zmw-view .zm-actions.zmw-tabs { background: #16203a; border: 1px solid rgba(127,220,255,.2); box-shadow: 0 6px 0 -2px #0c1426; }
html[data-theme="depth"] #zmw-view .zmw-tabs .cbi-button, html[data-theme="depth"] .zm-dock .zmw-tabs .cbi-button, html[data-theme="depth"] .zmw-modal .zmw-tabs .cbi-button { background: transparent; border: 0; box-shadow: none; color: #9fb0cc; }
html[data-theme="depth"] #zmw-view .zmw-tabs .cbi-button:hover, html[data-theme="depth"] .zm-dock .zmw-tabs .cbi-button:hover, html[data-theme="depth"] .zmw-modal .zmw-tabs .cbi-button:hover { background: rgba(127,220,255,.08); color: #e8eefc; transform: none; }
html[data-theme="depth"] #zmw-view .zmw-tabs .cbi-button-positive, html[data-theme="depth"] #zmw-view .zmw-tabs .cbi-button-positive:hover, html[data-theme="depth"] .zm-dock .zmw-tabs .cbi-button-positive, html[data-theme="depth"] .zm-dock .zmw-tabs .cbi-button-positive:hover, html[data-theme="depth"] .zmw-modal .zmw-tabs .cbi-button-positive, html[data-theme="depth"] .zmw-modal .zmw-tabs .cbi-button-positive:hover { background: linear-gradient(180deg, #33c6ff, #0090ff); color: #04111f; box-shadow: 0 3px 0 #005a9e; }
html[data-theme="micro"] #zmw-view .zm-actions.zmw-tabs { background: #ffffff; border: 1px solid #e3e6ee; border-radius: 16px; box-shadow: 0 1px 2px rgba(0,0,0,.04); backdrop-filter: none; }
html[data-theme="micro"] #zmw-view .zmw-tabs .cbi-button, html[data-theme="micro"] .zm-dock .zmw-tabs .cbi-button, html[data-theme="micro"] .zmw-modal .zmw-tabs .cbi-button { background: transparent; border: 0; border-radius: 11px; color: #000000; box-shadow: none; transform: none; }
html[data-theme="micro"] #zmw-view .zmw-tabs .cbi-button:hover, html[data-theme="micro"] .zm-dock .zmw-tabs .cbi-button:hover, html[data-theme="micro"] .zmw-modal .zmw-tabs .cbi-button:hover { background: #f0f3fa; color: #000000; transform: none; }
html[data-theme="micro"] #zmw-view .zmw-tabs .cbi-button-positive, html[data-theme="micro"] #zmw-view .zmw-tabs .cbi-button-positive:hover, html[data-theme="micro"] .zm-dock .zmw-tabs .cbi-button-positive, html[data-theme="micro"] .zm-dock .zmw-tabs .cbi-button-positive:hover, html[data-theme="micro"] .zmw-modal .zmw-tabs .cbi-button-positive, html[data-theme="micro"] .zmw-modal .zmw-tabs .cbi-button-positive:hover { background: #2d5bff; color: #ffffff; box-shadow: 0 6px 14px -8px rgba(45,91,255,.9); border-radius: 11px; }
html[data-theme="micro"] #zmw-view .zmw-tabs .cbi-button:active, html[data-theme="micro"] .zm-dock .zmw-tabs .cbi-button:active, html[data-theme="micro"] .zmw-modal .zmw-tabs .cbi-button:active { transform: scale(.96); }
html[data-theme="retro"] #zmw-view .zm-current-banner { background: #ffffe1; border: 1px solid #000000; border-radius: 0; color: #000000; }
#zmw-view .zm-log-wait { color: #fcd34d; }
#zmw-view .zm-tt-tile, #zmw-view .zm-tt-row, html.zm-theme-dark #zmw-view .zm-tt-tile, html.zm-theme-dark #zmw-view .zm-tt-row { background: var(--surface-2); border-color: var(--border); }
#zmw-view .zm-tt-tile { border-radius: 14px; }
#zmw-view .zm-tt-tile.zm-tt-active { border-color: var(--accent, #2d5bff); box-shadow: 0 0 0 1px var(--accent, #2d5bff) inset; }
#zmw-view .zm-tt-name, #zmw-view .zm-tt-head b { color: var(--text); }
#zmw-view .zm-tt-row-head:hover { background: var(--surface-3, rgba(45,91,255,.06)); }
#zmw-view .zm-tt-bar { background: var(--border); }
#zmw-view .zm-chip { background: var(--surface-3, rgba(110,118,129,.14)); color: var(--text); }
#zmw-view .zm-chip-ok { background: rgba(46,160,67,.14); color: #16a34a; }
#zmw-view .zm-chip-bad { background: rgba(220,38,38,.12); color: #dc2626; }
.zmw-alerts { display: flex; flex-direction: column; gap: 10px; }
.zmw-alerts:not(:empty) { margin-bottom: 16px; }
.zmw-alerts .zm-alerts { gap: 10px; }
html[data-theme="ink"] #zmw-view .zm-switch.zm-switch-on > span { left: 17px; }
html[data-theme="ink"] #zmw-view .zm-svc.zm-svc-on .zm-switch.zm-switch-on { background: #0a0a0a; }
html[data-theme="ink"] #zmw-view .zm-svc.zm-svc-on .zm-svc-sub { color: #0a0a0a; opacity: .75; }
html[data-theme="retro"] #zmw-view .zm-refresh-banner { background: #ffffe1; border: 1px solid #000000; border-radius: 0; color: #000000; box-shadow: none; }#zmw-view .zm-log-step { color: #a9b4c7; }
#zmw-view .zm-log-step-ok { color: #4ade80; }
#zmw-view .zm-log-step-bad { color: #fb7185; }
#zmw-view .zm-savebar, .zm-dock .zm-savebar, .zmw-modal .zm-savebar { background: var(--surface-solid); border: 1px solid rgba(124,92,255,.45); border-radius: var(--radius-sm); box-shadow: var(--shadow-lg); color: var(--text); }
#zmw-view .zm-savebar-dot, .zm-dock .zm-savebar-dot, .zmw-modal .zm-savebar-dot { background: var(--warn-dot); box-shadow: 0 0 0 4px var(--warn-bg); }
#zmw-view .zm-savebar.zm-savebar-done, .zm-dock .zm-savebar.zm-savebar-done, .zmw-modal .zm-savebar.zm-savebar-done { border-color: var(--ok-dot); }
#zmw-view .zm-savebar-done .zm-savebar-dot, .zm-dock .zm-savebar-done .zm-savebar-dot, .zmw-modal .zm-savebar-done .zm-savebar-dot { background: var(--ok-dot); box-shadow: 0 0 0 4px var(--ok-bg); }
.zm-stopbar { font-family: var(--font); }
html[data-theme="dark"] .zm-stopbar, html[data-theme="depth"] .zm-stopbar { background: #2a1416; color: #fecaca; border-color: rgba(248,113,113,.5); }
#zmw-view .zm-swrow-label { color: var(--text); }
#zmw-view .zm-svc.zm-svc-inc { border-style: dashed; }
.zm-stopbar .cbi-button.zm-stopbar-btn { padding: 10px 18px; border-radius: 12px; font-size: 14px; line-height: 1.2; box-shadow: 0 8px 20px -10px rgba(220,38,38,.8); }
@media (min-width: 961px) {
	html body.zmw-body .zm-dock, html body.zmw-body .zmw-modal { left: calc(var(--side-w) + (100vw - var(--side-w)) / 2); width: min(860px, calc(100vw - var(--side-w) - 48px)); }
}
.zm-dock .zm-savebar, .zmw-modal .zm-savebar { background: var(--surface-solid); border: 1px solid rgba(124,92,255,.45); border-radius: var(--radius-sm); color: var(--text); box-shadow: var(--shadow-lg); }
.zmw-body .zm-dock .zm-refresh-banner, .zmw-body .zmw-modal .zm-refresh-banner { margin: 0 !important; background: var(--surface-solid); border: 1px solid rgba(245,158,11,.5); border-radius: var(--radius-sm); color: var(--text); box-shadow: var(--shadow-lg); display: flex; align-items: center; justify-content: space-between; gap: 14px; }
.zm-dock .zm-savebar-dot, .zmw-modal .zm-savebar-dot { background: var(--warn-dot); box-shadow: 0 0 0 4px var(--warn-bg); }
.zm-dock .cbi-button, .zmw-modal .cbi-button { font-family: var(--font); }
#zmw-view .zm-ab-warn { color: var(--warn); }

html #zmw-view select:not([multiple]), html .zmw-modal select:not([multiple]) {
	background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%238a93a8' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M6 9l6 6 6-6'/%3E%3C/svg%3E");
	background-repeat: no-repeat; background-position: right 12px center; background-size: 16px; padding-right: 38px;
}
html[data-theme="graphite"] {
	--font: "Space Grotesk", system-ui, sans-serif;
	--a1: #ffb020; --a2: #ffb020; --a3: #ffcf6e;
	--grad: #ffb020; --grad-soft: rgba(255,176,32,.12); --ring: 0 0 0 3px rgba(255,176,32,.35);
	--radius: 12px; --radius-sm: 8px;
	--bg: #141416; --bg-glow-1: transparent; --bg-glow-2: transparent;
	--surface: #1c1c20; --surface-solid: #1c1c20; --surface-2: rgba(255,255,255,.035); --surface-3: rgba(255,255,255,.07);
	--side-bg: #18181b; --border: #2b2b31; --border-2: #3a3a42;
	--text: #ececef; --text-2: #c9c9cf; --muted: #9a9aa3;
	--shadow: 0 1px 0 rgba(255,255,255,.03) inset; --shadow-lg: 0 30px 70px -30px rgba(0,0,0,.9);
	--input-bg: #141416; --console: #0e0e10; --console-border: #2b2b31;
	--ok: #7ee2a8; --ok-bg: rgba(126,226,168,.10); --ok-dot: #4ade80;
	--bad: #ff8a80; --bad-bg: rgba(255,90,78,.12); --bad-dot: #ff5a4e;
	--warn: #ffcf6e; --warn-bg: rgba(255,176,32,.12); --warn-dot: #ffb020;
	--off: #9a9aa3; --off-bg: rgba(154,154,163,.10);
	color-scheme: dark;
}
html[data-theme="graphite"] body.zmw-body { background-image: none; }
html[data-theme="graphite"] .zmw-orbs, html[data-theme="graphite"] .zmw-grid-bg { display: none; }
html[data-theme="graphite"] .zmw-top { --zmw-top-bg: rgb(20,20,22); background: var(--zmw-top-bg); }
html[data-theme="graphite"] .zmw-title { font-weight: 700; letter-spacing: -.02em; }
html[data-theme="graphite"] .zmw-side { background: #18181b; border-right: 1px solid #2b2b31; box-shadow: none; backdrop-filter: none; -webkit-backdrop-filter: none; }
html[data-theme="graphite"] .zmw-nav-item { color: #b4b4bc; }
html[data-theme="graphite"] .zmw-nav-item:hover { background: rgba(255,255,255,.04); color: #ececef; }
html[data-theme="graphite"] .zmw-nav-item.zmw-active { background: rgba(255,176,32,.10); color: #ffcf6e; box-shadow: none; }
html[data-theme="graphite"] .zmw-nav-item.zmw-active::before { background: #ffb020; }
html[data-theme="graphite"] .zmw-nav-ico { background: #222227; border-color: #2f2f35; color: #9a9aa3; }
html[data-theme="graphite"] .zmw-nav-item.zmw-active .zmw-nav-ico { background: #ffb020; color: #1b1300; border-color: #ffb020; box-shadow: none; }
html[data-theme="graphite"] .zmw-mem-bar { background: #2b2b31; box-shadow: none; }
html[data-theme="graphite"] .zmw-mem-bar i { background: #ffb020; box-shadow: none; }
html[data-theme="graphite"] #zmw-view .zm-card { background: #1c1c20; border: 1px solid #2b2b31; box-shadow: none; backdrop-filter: none; -webkit-backdrop-filter: none; }
html[data-theme="graphite"] #zmw-view .zm-card:hover { border-color: #3a3a42; box-shadow: none; }
html[data-theme="graphite"] #zmw-view .zm-card h3 { font-weight: 700; letter-spacing: -.01em; color: #ececef; }
html[data-theme="graphite"] #zmw-view .zm-card h3::before { background: #ffb020; }
html[data-theme="graphite"] #zmw-view .cbi-button, html[data-theme="graphite"] .zmw-icon-btn, html[data-theme="graphite"] .zm-dock .cbi-button, html[data-theme="graphite"] .zmw-modal .cbi-button { background: #26262b; border: 1px solid #34343a; color: #ececef; box-shadow: none; }
html[data-theme="graphite"] #zmw-view .cbi-button:hover, html[data-theme="graphite"] .zmw-icon-btn:hover, html[data-theme="graphite"] .zm-dock .cbi-button:hover, html[data-theme="graphite"] .zmw-modal .cbi-button:hover { background: #2f2f35; border-color: #46464f; transform: none; box-shadow: none; }
html[data-theme="graphite"] #zmw-view .cbi-button-positive, html[data-theme="graphite"] #zmw-view .cbi-button-positive:hover, html[data-theme="graphite"] .zmw-btn-primary, html[data-theme="graphite"] .zm-dock .cbi-button-positive, html[data-theme="graphite"] .zm-dock .cbi-button-positive:hover, html[data-theme="graphite"] .zmw-modal .cbi-button-positive, html[data-theme="graphite"] .zmw-modal .cbi-button-positive:hover { background: #ffb020; color: #1b1300; border-color: #ffb020; box-shadow: none; }
html[data-theme="graphite"] #zmw-view .cbi-button-action, html[data-theme="graphite"] #zmw-view .cbi-button-action:hover, html[data-theme="graphite"] .zm-dock .cbi-button-action, html[data-theme="graphite"] .zmw-modal .cbi-button-action { background: rgba(255,176,32,.14); color: #ffcf6e; border-color: rgba(255,176,32,.45); }
html[data-theme="graphite"] #zmw-view .cbi-button-remove, html[data-theme="graphite"] #zmw-view .cbi-button-remove:hover, html[data-theme="graphite"] .zm-dock .cbi-button-remove, html[data-theme="graphite"] .zm-dock .cbi-button-remove:hover, html[data-theme="graphite"] .zmw-modal .cbi-button-remove, html[data-theme="graphite"] .zmw-modal .cbi-button-remove:hover { background: rgba(255,90,78,.12); color: #ff8a80; border-color: rgba(255,90,78,.45); box-shadow: none; }
html[data-theme="graphite"] #zmw-view .zm-tile { background: #222227; border: 1px solid #2f2f35; box-shadow: none; }
html[data-theme="graphite"] #zmw-view .zm-tile:hover { border-color: #46464f; }
html[data-theme="graphite"] #zmw-view .zm-tile.zm-active { background: #ffb020; color: #1b1300; border-color: #ffb020; }
html[data-theme="graphite"] #zmw-view .zm-tile.zm-active::before { color: #1b1300; }
html[data-theme="graphite"] #zmw-view .zm-badge .zm-dot, html[data-theme="graphite"] .zm-dock .zm-badge .zm-dot, html[data-theme="graphite"] .zmw-modal .zm-badge .zm-dot { box-shadow: none; }
html[data-theme="graphite"] #zmw-view input:not([type=checkbox]):not([type=radio]):not([type=range]), html[data-theme="graphite"] #zmw-view select, html[data-theme="graphite"] #zmw-view textarea:not(.zm-config-editor), html[data-theme="graphite"] .zmw-input, html[data-theme="graphite"] .zmw-modal input:not([type=checkbox]):not([type=radio]), html[data-theme="graphite"] .zmw-modal select { background: #141416; border-color: #34343a; color: #ececef; }
html[data-theme="graphite"] #zmw-view .zm-seg { background: #141416; border-color: #2b2b31; }
html[data-theme="graphite"] #zmw-view .zm-seg-item.zm-active { background: #ffb020; color: #1b1300; }
html[data-theme="graphite"] .zmw-login-card, html[data-theme="graphite"] .zmw-modal, html[data-theme="graphite"] .zmw-theme-menu { background: #1c1c20; border: 1px solid #34343a; backdrop-filter: none; -webkit-backdrop-filter: none; }
html[data-theme="graphite"] .zmw-theme-opt.zmw-on { background: rgba(255,176,32,.12); color: #ffcf6e; }
html[data-theme="graphite"] .zmw-theme-mark { color: #ffb020; }
html[data-theme="graphite"] #zmw-view .zm-actions.zmw-tabs { background: #1c1c20; border: 1px solid #2b2b31; box-shadow: none; backdrop-filter: none; -webkit-backdrop-filter: none; }
html[data-theme="graphite"] #zmw-view .zmw-tabs .cbi-button, html[data-theme="graphite"] .zm-dock .zmw-tabs .cbi-button, html[data-theme="graphite"] .zmw-modal .zmw-tabs .cbi-button { background: transparent; border: 0; box-shadow: none; color: #9a9aa3; }
html[data-theme="graphite"] #zmw-view .zmw-tabs .cbi-button:hover, html[data-theme="graphite"] .zm-dock .zmw-tabs .cbi-button:hover, html[data-theme="graphite"] .zmw-modal .zmw-tabs .cbi-button:hover { background: rgba(255,255,255,.04); color: #ececef; transform: none; }
html[data-theme="graphite"] #zmw-view .zmw-tabs .cbi-button-positive, html[data-theme="graphite"] #zmw-view .zmw-tabs .cbi-button-positive:hover, html[data-theme="graphite"] .zm-dock .zmw-tabs .cbi-button-positive, html[data-theme="graphite"] .zm-dock .zmw-tabs .cbi-button-positive:hover, html[data-theme="graphite"] .zmw-modal .zmw-tabs .cbi-button-positive, html[data-theme="graphite"] .zmw-modal .zmw-tabs .cbi-button-positive:hover { background: #ffb020; color: #1b1300; box-shadow: none; }
html[data-theme="graphite"] .zmw-brand-name b { background: none; -webkit-background-clip: border-box; background-clip: border-box; color: #ffb020; }
html[data-theme="graphite"] .zm-stopbar { background: #2a1614; color: #ffd0cb; border-color: rgba(255,90,78,.5); }
html[data-theme="oled"] {
	--font: "Inter", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
	--a1: #ffffff; --a2: #ffffff; --a3: #d4d4d4;
	--grad: #ffffff; --grad-soft: rgba(255,255,255,.08); --ring: 0 0 0 3px rgba(255,255,255,.28);
	--radius: 18px; --radius-sm: 12px;
	--bg: #000000; --bg-glow-1: transparent; --bg-glow-2: transparent;
	--surface: #000000; --surface-solid: #0a0a0a; --surface-2: rgba(255,255,255,.04); --surface-3: rgba(255,255,255,.08);
	--side-bg: #000000; --border: #1c1c1c; --border-2: #2a2a2a;
	--text: #ffffff; --text-2: #d4d4d4; --muted: #8a8a8a;
	--shadow: none; --shadow-lg: 0 30px 80px -30px rgba(0,0,0,1);
	--input-bg: #000000; --console: #000000; --console-border: #1c1c1c;
	--ok: #6ee7a0; --ok-bg: rgba(110,231,160,.10); --ok-dot: #4ade80;
	--bad: #ff8a80; --bad-bg: rgba(255,90,78,.12); --bad-dot: #ff5a4e;
	--warn: #fcd34d; --warn-bg: rgba(252,211,77,.10); --warn-dot: #f5b70a;
	--off: #8a8a8a; --off-bg: rgba(138,138,138,.10);
	color-scheme: dark;
}
html[data-theme="oled"] body.zmw-body { background-image: none; }
html[data-theme="oled"] .zmw-orbs, html[data-theme="oled"] .zmw-grid-bg { display: none; }
html[data-theme="oled"] .zmw-top { --zmw-top-bg: rgb(0,0,0); background: var(--zmw-top-bg); }
html[data-theme="oled"] .zmw-title { font-weight: 800; letter-spacing: -.025em; }
html[data-theme="oled"] .zmw-side { background: #000000; border-right: 1px solid #1c1c1c; box-shadow: none; backdrop-filter: none; -webkit-backdrop-filter: none; }
html[data-theme="oled"] .zmw-nav-item { color: #a3a3a3; }
html[data-theme="oled"] .zmw-nav-item:hover { background: rgba(255,255,255,.06); color: #ffffff; }
html[data-theme="oled"] .zmw-nav-item.zmw-active { background: rgba(255,255,255,.10); color: #ffffff; box-shadow: none; }
html[data-theme="oled"] .zmw-nav-item.zmw-active::before { background: #ffffff; }
html[data-theme="oled"] .zmw-nav-ico { background: #0d0d0d; border-color: #262626; color: #8a8a8a; }
html[data-theme="oled"] .zmw-nav-item.zmw-active .zmw-nav-ico { background: #ffffff; color: #000000; border-color: #ffffff; box-shadow: none; }
html[data-theme="oled"] .zmw-mem-bar { background: #1c1c1c; box-shadow: none; }
html[data-theme="oled"] .zmw-mem-bar i { background: #ffffff; box-shadow: none; }
html[data-theme="oled"] #zmw-view .zm-card { background: #000000; border: 1px solid #1c1c1c; box-shadow: none; backdrop-filter: none; -webkit-backdrop-filter: none; }
html[data-theme="oled"] #zmw-view .zm-card:hover { border-color: #333333; box-shadow: none; }
html[data-theme="oled"] #zmw-view .zm-card h3 { font-weight: 700; letter-spacing: -.01em; color: #ffffff; }
html[data-theme="oled"] #zmw-view .cbi-button, html[data-theme="oled"] .zmw-icon-btn, html[data-theme="oled"] .zm-dock .cbi-button, html[data-theme="oled"] .zmw-modal .cbi-button { background: #0d0d0d; border: 1px solid #2a2a2a; color: #ffffff; box-shadow: none; }
html[data-theme="oled"] #zmw-view .cbi-button:hover, html[data-theme="oled"] .zmw-icon-btn:hover, html[data-theme="oled"] .zm-dock .cbi-button:hover, html[data-theme="oled"] .zmw-modal .cbi-button:hover { background: #262626; border-color: #3d3d3d; transform: none; box-shadow: none; }
html[data-theme="oled"] #zmw-view .cbi-button-positive, html[data-theme="oled"] #zmw-view .cbi-button-positive:hover, html[data-theme="oled"] .zmw-btn-primary, html[data-theme="oled"] .zm-dock .cbi-button-positive, html[data-theme="oled"] .zm-dock .cbi-button-positive:hover, html[data-theme="oled"] .zmw-modal .cbi-button-positive, html[data-theme="oled"] .zmw-modal .cbi-button-positive:hover { background: #ffffff; color: #000000; border-color: #ffffff; box-shadow: none; }
html[data-theme="oled"] #zmw-view .cbi-button-action, html[data-theme="oled"] #zmw-view .cbi-button-action:hover, html[data-theme="oled"] .zm-dock .cbi-button-action, html[data-theme="oled"] .zmw-modal .cbi-button-action { background: rgba(255,255,255,.14); color: #ffffff; border-color: rgba(255,255,255,.45); }
html[data-theme="oled"] #zmw-view .cbi-button-remove, html[data-theme="oled"] #zmw-view .cbi-button-remove:hover, html[data-theme="oled"] .zm-dock .cbi-button-remove, html[data-theme="oled"] .zm-dock .cbi-button-remove:hover, html[data-theme="oled"] .zmw-modal .cbi-button-remove, html[data-theme="oled"] .zmw-modal .cbi-button-remove:hover { background: rgba(255,90,78,.12); color: #ff8a80; border-color: rgba(255,90,78,.45); box-shadow: none; }
html[data-theme="oled"] #zmw-view .zm-tile { background: #0d0d0d; border: 1px solid #262626; box-shadow: none; }
html[data-theme="oled"] #zmw-view .zm-tile:hover { border-color: #3d3d3d; }
html[data-theme="oled"] #zmw-view .zm-tile.zm-active::before { color: #000000; }
html[data-theme="oled"] #zmw-view .zm-badge .zm-dot, html[data-theme="oled"] .zm-dock .zm-badge .zm-dot, html[data-theme="oled"] .zmw-modal .zm-badge .zm-dot { box-shadow: none; }
html[data-theme="oled"] #zmw-view input:not([type=checkbox]):not([type=radio]):not([type=range]), html[data-theme="oled"] #zmw-view select, html[data-theme="oled"] #zmw-view textarea:not(.zm-config-editor), html[data-theme="oled"] .zmw-input, html[data-theme="oled"] .zmw-modal input:not([type=checkbox]):not([type=radio]), html[data-theme="oled"] .zmw-modal select { background: #000000; border-color: #2a2a2a; color: #ffffff; }
html[data-theme="oled"] #zmw-view .zm-seg { background: #000000; border-color: #1c1c1c; }
html[data-theme="oled"] #zmw-view .zm-seg-item.zm-active { background: #ffffff; color: #000000; }
html[data-theme="oled"] .zmw-login-card, html[data-theme="oled"] .zmw-modal, html[data-theme="oled"] .zmw-theme-menu { background: #000000; border: 1px solid #2a2a2a; backdrop-filter: none; -webkit-backdrop-filter: none; }
html[data-theme="oled"] .zmw-theme-opt.zmw-on { background: rgba(255,255,255,.12); color: #ffffff; }
html[data-theme="oled"] .zmw-theme-mark { color: #ffffff; }
html[data-theme="oled"] #zmw-view .zm-actions.zmw-tabs { background: #000000; border: 1px solid #1c1c1c; box-shadow: none; backdrop-filter: none; -webkit-backdrop-filter: none; }
html[data-theme="oled"] #zmw-view .zmw-tabs .cbi-button, html[data-theme="oled"] .zm-dock .zmw-tabs .cbi-button, html[data-theme="oled"] .zmw-modal .zmw-tabs .cbi-button { background: transparent; border: 0; box-shadow: none; color: #8a8a8a; }
html[data-theme="oled"] #zmw-view .zmw-tabs .cbi-button:hover, html[data-theme="oled"] .zm-dock .zmw-tabs .cbi-button:hover, html[data-theme="oled"] .zmw-modal .zmw-tabs .cbi-button:hover { background: rgba(255,255,255,.06); color: #ffffff; transform: none; }
html[data-theme="oled"] #zmw-view .zmw-tabs .cbi-button-positive, html[data-theme="oled"] #zmw-view .zmw-tabs .cbi-button-positive:hover, html[data-theme="oled"] .zm-dock .zmw-tabs .cbi-button-positive, html[data-theme="oled"] .zm-dock .zmw-tabs .cbi-button-positive:hover, html[data-theme="oled"] .zmw-modal .zmw-tabs .cbi-button-positive, html[data-theme="oled"] .zmw-modal .zmw-tabs .cbi-button-positive:hover { background: #ffffff; color: #000000; box-shadow: none; }
html[data-theme="oled"] .zmw-brand-name b { background: none; -webkit-background-clip: border-box; background-clip: border-box; color: #ffffff; }
html[data-theme="oled"] .zm-stopbar { background: #1a0705; color: #ffd0cb; border-color: rgba(255,90,78,.5); }
html[data-theme="oled"] .zmw-nav-item { border-radius: 999px; }
html[data-theme="oled"] .zmw-nav-item.zmw-active { background: #ffffff; color: #000000; }
html[data-theme="oled"] .zmw-nav-item.zmw-active::before { display: none; }
html[data-theme="oled"] .zmw-nav-item.zmw-active .zmw-nav-ico { background: #000000; color: #ffffff; border-color: #000000; }
html[data-theme="oled"] .zmw-nav-gear.zmw-on, html[data-theme="oled"] .zmw-nav-editfoot .zmw-nav-btn-done { background: #ffffff; color: #000000; border-color: #ffffff; }
html[data-theme="oled"] .zmw-nav-editing .zmw-nav-eye { color: #ffffff; background: rgba(255,255,255,.12); }
html[data-theme="oled"] .zmw-nav-gear > i { background: #ffffff; }
html[data-theme="oled"] #zmw-view .zm-card { border-radius: 20px; }
html[data-theme="oled"] #zmw-view .zm-card h3::before { background: #ffffff; }
html[data-theme="oled"] #zmw-view .cbi-button, html[data-theme="oled"] .zmw-icon-btn, html[data-theme="oled"] .zm-dock .cbi-button, html[data-theme="oled"] .zmw-modal .cbi-button, html[data-theme="oled"] .zmw-btn-primary { border-radius: 999px; }
html[data-theme="oled"] #zmw-view .zmw-tabs .cbi-button { border-radius: 999px; }
html[data-theme="oled"] #zmw-view .zm-actions.zmw-tabs { border-radius: 999px; }
html[data-theme="oled"] #zmw-view .zm-seg, html[data-theme="oled"] #zmw-view .zm-seg-item { border-radius: 999px; }
html[data-theme="oled"] #zmw-view .zm-tile { border-radius: 16px; }
html[data-theme="oled"] #zmw-view .zm-tile.zm-active { background: #ffffff; color: #000000; border-color: #ffffff; }
html[data-theme="oled"] .zmw-login-card, html[data-theme="oled"] .zmw-modal { border-radius: 24px; }
html[data-theme="oled"] .zmw-theme-opt.zmw-on { background: rgba(255,255,255,.10); color: #ffffff; }
html[data-theme="oled"] .zmw-mem-bar { background: #1c1c1c; }
html[data-theme="oled"] #zmw-view .zm-switch.zm-switch-on > span { background: #000000; }
html[data-theme="oled"] .zmw-check input:checked + .zmw-check-box::after { border-color: #000000; }
html[data-theme="oled"] .zmw-nav-item.zmw-active .zmw-nav-ico .zmw-i { color: #ffffff; }
.zmw-mx-rain, .zmw-mx-title, .zmw-mx-sub, .zmw-mx-msg { display: none; }
.zmw-mx-rain { position: absolute; inset: 0; width: 100%; height: 100%; pointer-events: none; }
.zmw-mx-msg { position: absolute; left: 18px; bottom: 14px; z-index: 2; font: 13px/1.4 "Share Tech Mono", ui-monospace, monospace; color: #00ff41; text-shadow: 0 0 8px rgba(0,255,65,.6); pointer-events: none; }
@media (max-width: 600px) { html[data-theme="matrix"] .zmw-mx-msg { left: 12px; bottom: 10px; font-size: 12px; } }
html[data-theme="matrix"] {
	--font: "Share Tech Mono", ui-monospace, "JetBrains Mono", Consolas, monospace;
	--a1: #00ff41; --a2: #00ff41; --a3: #7dffa0;
	--grad: #00ff41; --grad-soft: rgba(0,255,65,.08); --ring: 0 0 0 2px rgba(0,255,65,.6);
	--radius: 2px; --radius-sm: 2px;
	--bg: #000000; --bg-glow-1: transparent; --bg-glow-2: transparent;
	--surface: #020a04; --surface-solid: #020a04; --surface-2: rgba(0,255,65,.04); --surface-3: rgba(0,255,65,.08);
	--side-bg: #000000; --border: #0d3d1a; --border-2: #15652b;
	--text: #b8ffcc; --text-2: #8ef0a8; --muted: #3bb15f;
	--shadow: 0 0 0 1px rgba(0,255,65,.06); --shadow-lg: 0 0 60px -20px rgba(0,255,65,.35);
	--input-bg: #000000; --console: #000000; --console-border: #15652b;
	--ok: #00ff41; --ok-bg: rgba(0,255,65,.10); --ok-dot: #00ff41;
	--bad: #ff5f56; --bad-bg: rgba(255,95,86,.12); --bad-dot: #ff5f56;
	--warn: #e5ff00; --warn-bg: rgba(229,255,0,.10); --warn-dot: #e5ff00;
	--off: #3bb15f; --off-bg: rgba(59,177,95,.10);
	color-scheme: dark;
}
html[data-theme="matrix"] body.zmw-body { background-image: none; font-size: 14.5px; }
html[data-theme="matrix"] .zmw-orbs, html[data-theme="matrix"] .zmw-grid-bg { display: none; }
html[data-theme="matrix"] .zmw-top { --zmw-top-bg: #000000; background: var(--zmw-top-bg); }
html[data-theme="matrix"] .zmw-title { font-weight: 400; letter-spacing: .06em; color: #00ff41; text-shadow: 0 0 8px rgba(0,255,65,.55); }
html[data-theme="matrix"] .zmw-side { background: #000000; border-right: 1px solid #0d3d1a; box-shadow: none; backdrop-filter: none; -webkit-backdrop-filter: none; }
html[data-theme="matrix"] .zmw-logo svg { filter: hue-rotate(-90deg) saturate(1.6) brightness(1.1) drop-shadow(0 0 6px rgba(0,255,65,.6)); }
html[data-theme="matrix"] .zmw-brand-name { letter-spacing: .04em; }
html[data-theme="matrix"] .zmw-brand-name b { background: none; -webkit-background-clip: border-box; background-clip: border-box; color: #00ff41; text-shadow: 0 0 8px rgba(0,255,65,.55); }
html[data-theme="matrix"] .zmw-nav-item { border-radius: 0; color: #4fd07a; }
html[data-theme="matrix"] .zmw-nav-item:hover { background: rgba(0,255,65,.06); color: #b8ffcc; }
html[data-theme="matrix"] .zmw-nav-item.zmw-active { background: #00ff41; color: #001a07; box-shadow: 0 0 16px -4px rgba(0,255,65,.7); }
html[data-theme="matrix"] .zmw-nav-item.zmw-active::before { display: none; }
html[data-theme="matrix"] .zmw-nav-ico { background: transparent; border-color: #0d3d1a; border-radius: 0; color: #00ff41; }
html[data-theme="matrix"] .zmw-nav-item.zmw-active .zmw-nav-ico { background: #001a07; color: #00ff41; border-color: #001a07; box-shadow: none; }
html[data-theme="matrix"] .zmw-mem-bar { background: #0d3d1a; border-radius: 0; }
html[data-theme="matrix"] .zmw-mem-bar i { background: #00ff41; border-radius: 0; box-shadow: 0 0 8px rgba(0,255,65,.7); }
html[data-theme="matrix"] #zmw-view .zm-card { background: #020a04; border: 1px solid #0d3d1a; border-radius: 0; box-shadow: inset 0 0 40px -20px rgba(0,255,65,.25); backdrop-filter: none; -webkit-backdrop-filter: none; }
html[data-theme="matrix"] #zmw-view .zm-card:hover { border-color: #15652b; box-shadow: inset 0 0 40px -16px rgba(0,255,65,.3); }
html[data-theme="matrix"] #zmw-view .zm-card h3 { font-weight: 400; letter-spacing: .08em; text-transform: uppercase; color: #00ff41; text-shadow: 0 0 8px rgba(0,255,65,.55); }
html[data-theme="matrix"] #zmw-view .zm-card h3::before { background: #00ff41; border-radius: 0; width: 8px; box-shadow: 0 0 8px #00ff41; }
html[data-theme="matrix"] #zmw-view .cbi-button, html[data-theme="matrix"] .zmw-icon-btn, html[data-theme="matrix"] .zm-dock .cbi-button, html[data-theme="matrix"] .zmw-modal .cbi-button { border-radius: 0; background: transparent; border: 1px solid #15652b; color: #8ef0a8; box-shadow: none; font-weight: 400; letter-spacing: .04em; }
html[data-theme="matrix"] #zmw-view .cbi-button:hover, html[data-theme="matrix"] .zmw-icon-btn:hover, html[data-theme="matrix"] .zm-dock .cbi-button:hover, html[data-theme="matrix"] .zmw-modal .cbi-button:hover { background: rgba(0,255,65,.08); border-color: #00ff41; color: #ffffff; transform: none; box-shadow: none; }
html[data-theme="matrix"] #zmw-view .cbi-button-positive, html[data-theme="matrix"] #zmw-view .cbi-button-positive:hover, html[data-theme="matrix"] .zmw-btn-primary, html[data-theme="matrix"] .zm-dock .cbi-button-positive, html[data-theme="matrix"] .zm-dock .cbi-button-positive:hover, html[data-theme="matrix"] .zmw-modal .cbi-button-positive, html[data-theme="matrix"] .zmw-modal .cbi-button-positive:hover { background: #00ff41; color: #001a07; border-color: #00ff41; box-shadow: 0 0 16px -4px rgba(0,255,65,.8); }
html[data-theme="matrix"] #zmw-view .cbi-button-action, html[data-theme="matrix"] #zmw-view .cbi-button-action:hover, html[data-theme="matrix"] .zm-dock .cbi-button-action, html[data-theme="matrix"] .zmw-modal .cbi-button-action { background: rgba(0,255,65,.12); color: #00ff41; border-color: #00ff41; }
html[data-theme="matrix"] #zmw-view .cbi-button-remove, html[data-theme="matrix"] #zmw-view .cbi-button-remove:hover, html[data-theme="matrix"] .zm-dock .cbi-button-remove, html[data-theme="matrix"] .zm-dock .cbi-button-remove:hover, html[data-theme="matrix"] .zmw-modal .cbi-button-remove, html[data-theme="matrix"] .zmw-modal .cbi-button-remove:hover { background: transparent; color: #ff5f56; border-color: rgba(255,95,86,.6); box-shadow: none; }
html[data-theme="matrix"] #zmw-view .zm-tile { border-radius: 0; background: #000000; border: 1px solid #0d3d1a; box-shadow: none; }
html[data-theme="matrix"] #zmw-view .zm-tile:hover { border-color: #00ff41; }
html[data-theme="matrix"] #zmw-view .zm-tile.zm-active { background: rgba(0,255,65,.12); color: #ffffff; border-color: #00ff41; box-shadow: 0 0 14px -6px rgba(0,255,65,.8); }
html[data-theme="matrix"] #zmw-view .zm-tile.zm-active::before { color: #00ff41; }
html[data-theme="matrix"] #zmw-view .zm-badge, html[data-theme="matrix"] .zm-dock .zm-badge, html[data-theme="matrix"] .zmw-modal .zm-badge { border-radius: 0; letter-spacing: .04em; }
html[data-theme="matrix"] #zmw-view .zm-badge .zm-dot, html[data-theme="matrix"] .zm-dock .zm-badge .zm-dot, html[data-theme="matrix"] .zmw-modal .zm-badge .zm-dot { border-radius: 0; }
html[data-theme="matrix"] #zmw-view input:not([type=checkbox]):not([type=radio]):not([type=range]), html[data-theme="matrix"] #zmw-view select, html[data-theme="matrix"] #zmw-view textarea:not(.zm-config-editor), html[data-theme="matrix"] .zmw-input, html[data-theme="matrix"] .zmw-modal input:not([type=checkbox]):not([type=radio]), html[data-theme="matrix"] .zmw-modal select { border-radius: 0; background: #000000; border: 1px solid #15652b; color: #b8ffcc; }
html[data-theme="matrix"] #zmw-view .zm-log, html[data-theme="matrix"] #zmw-view .zm-config-editor { border-radius: 0; }
html[data-theme="matrix"] #zmw-view .zm-seg { border-radius: 0; background: #000000; border-color: #0d3d1a; }
html[data-theme="matrix"] #zmw-view .zm-seg-item { border-radius: 0; }
html[data-theme="matrix"] #zmw-view .zm-seg-item.zm-active { background: #00ff41; color: #001a07; }
html[data-theme="matrix"] .zmw-login-card, html[data-theme="matrix"] .zmw-modal, html[data-theme="matrix"] .zmw-theme-menu { border-radius: 0; background: #020a04; border: 1px solid #00ff41; box-shadow: 0 0 0 1px rgba(0,255,65,.15), 0 0 50px -10px rgba(0,255,65,.35); backdrop-filter: none; -webkit-backdrop-filter: none; }
html[data-theme="matrix"] .zmw-theme-opt { border-radius: 0; }
html[data-theme="matrix"] .zmw-theme-opt.zmw-on, html[data-theme="matrix"] .zmw-theme-opt:hover { background: rgba(0,255,65,.10); color: #00ff41; }
html[data-theme="matrix"] .zmw-theme-mark { color: #00ff41; }
html[data-theme="matrix"] #zmw-view .zm-actions.zmw-tabs { background: #000000; border: 1px solid #0d3d1a; border-radius: 0; box-shadow: none; backdrop-filter: none; -webkit-backdrop-filter: none; }
html[data-theme="matrix"] #zmw-view .zmw-tabs .cbi-button, html[data-theme="matrix"] .zm-dock .zmw-tabs .cbi-button, html[data-theme="matrix"] .zmw-modal .zmw-tabs .cbi-button { background: transparent; border: 0; box-shadow: none; color: #3bb15f; }
html[data-theme="matrix"] #zmw-view .zmw-tabs .cbi-button:hover, html[data-theme="matrix"] .zm-dock .zmw-tabs .cbi-button:hover, html[data-theme="matrix"] .zmw-modal .zmw-tabs .cbi-button:hover { background: rgba(0,255,65,.06); color: #b8ffcc; transform: none; }
html[data-theme="matrix"] #zmw-view .zmw-tabs .cbi-button-positive, html[data-theme="matrix"] #zmw-view .zmw-tabs .cbi-button-positive:hover, html[data-theme="matrix"] .zm-dock .zmw-tabs .cbi-button-positive, html[data-theme="matrix"] .zm-dock .zmw-tabs .cbi-button-positive:hover, html[data-theme="matrix"] .zmw-modal .zmw-tabs .cbi-button-positive, html[data-theme="matrix"] .zmw-modal .zmw-tabs .cbi-button-positive:hover { background: #00ff41; color: #001a07; box-shadow: none; }
html[data-theme="matrix"] .zm-stopbar { background: #1a0705; color: #ffb3ad; border-color: rgba(255,95,86,.5); }
html[data-theme="matrix"] .zm-wn, html[data-theme="matrix"] .zm-dlg { border-radius: 0 !important; border: 1px solid #00ff41; }
html[data-theme="matrix"] .zmw-btn-primary { border-radius: 0; background: #00ff41; color: #001a07; letter-spacing: .3em; font-weight: 400; text-transform: uppercase; box-shadow: 0 0 18px rgba(0,255,65,.55); }
html[data-theme="matrix"] .zmw-btn-primary:hover { background: #7dffa0; box-shadow: 0 0 24px rgba(0,255,65,.75); }
html[data-theme="matrix"] .zmw-btn-primary .zmw-i { display: none; }
html[data-theme="matrix"] .zmw-login { background: #000000; }
html[data-theme="matrix"] .zmw-mx-rain { display: block; }
html[data-theme="matrix"] .zmw-login::after { content: ""; position: absolute; inset: 0; pointer-events: none; background: radial-gradient(ellipse at center, transparent 35%, rgba(0,0,0,.85) 100%); }
html[data-theme="matrix"] .zmw-login-card { z-index: 2; max-width: 360px; padding: 26px 26px 20px; border-radius: 0; background: rgba(0,10,3,.84); border: 1px solid #00ff41; box-shadow: 0 0 0 1px rgba(0,255,65,.15), 0 0 40px rgba(0,255,65,.25), inset 0 0 30px rgba(0,255,65,.08); text-align: left; backdrop-filter: none; -webkit-backdrop-filter: none; }
html[data-theme="matrix"] .zmw-login-card .zmw-logo-lg, html[data-theme="matrix"] .zmw-login-card > h1, html[data-theme="matrix"] .zmw-login-card > .zmw-login-sub { display: none; }
html[data-theme="matrix"] .zmw-mx-title { display: block; font-size: 24px; letter-spacing: .14em; color: #00ff41; text-shadow: 0 0 8px rgba(0,255,65,.55); margin: 0 0 2px; overflow-wrap: anywhere; }
html[data-theme="matrix"] .zmw-mx-sub { display: block; font-size: 13px; color: #3bd16f; margin: 0 0 18px; }
html[data-theme="matrix"] .zmw-field-label { text-transform: uppercase; letter-spacing: .1em; color: #3bd16f; font-weight: 400; font-size: 11.5px; }
html[data-theme="matrix"] .zmw-input { height: 40px; border-radius: 0; border-color: #0f6b2c; background: rgba(0,0,0,.6); color: #00ff41; }
html[data-theme="matrix"] .zmw-input::before { content: ">"; color: #00ff41; text-shadow: 0 0 8px rgba(0,255,65,.55); }
html[data-theme="matrix"] .zmw-input > .zmw-i { display: none; }
html[data-theme="matrix"] .zmw-input input { color: #b8ffcc; caret-color: #00ff41; font-family: "Share Tech Mono", ui-monospace, "JetBrains Mono", Consolas, monospace; }
html[data-theme="matrix"] .zmw-input:focus-within { border-color: #00ff41; box-shadow: 0 0 0 1px rgba(0,255,65,.35), 0 0 16px -4px rgba(0,255,65,.6); }
html[data-theme="matrix"] .zmw-eye { color: #3bb15f; border-radius: 0; }
html[data-theme="matrix"] .zmw-check { color: #3bd16f; }
html[data-theme="matrix"] .zmw-check-box { border-radius: 0; border-color: #15652b; background: #000000; }
html[data-theme="matrix"] .zmw-check input:checked + .zmw-check-box { background: #00ff41; }
html[data-theme="matrix"] .zmw-check input:checked + .zmw-check-box::after { border-color: #001a07; }
html[data-theme="matrix"] .zmw-login-msg { border-radius: 0; }
html[data-theme="matrix"] .zmw-login-foot { color: #1f8f43; text-align: center; }
html[data-theme="matrix"] .zmw-mx-msg { display: block; }
html[data-theme="matrix"] .zmw-login-theme { z-index: 3; }
html.zm-dust-on { --zm-glass: 52%; --zm-glass-side: 66%; --zm-glass-auto: 58%; --zm-glass-on: 84%; }
html.zm-dust-on.zm-theme-dark { --zm-glass-auto: 62%; }
html.zm-dust-on[data-theme="bento"] { --zm-glass-auto: 64%; }
html.zm-dust-on[data-theme="retro"] { --zm-glass-auto: 62%; --zm-glass-on: 84%; }
html.zm-dust-on[data-theme="bento"] { --zm-glass: 62%; --zm-glass-side: 74%; }
html.zm-dust-on[data-theme="retro"] { --zm-glass: 58%; --zm-glass-side: 72%; }
html.zm-dust-on[data-theme] #zmw-view .zm-card, html.zm-dust-on[data-theme] #zmw-view .zm-actions.zmw-tabs {
	background-color: color-mix(in srgb, var(--surface-solid) var(--zm-glass), transparent);
	background-image: none; backdrop-filter: none; -webkit-backdrop-filter: none;
	transition: background-color .35s ease;
}
html.zm-dust-on[data-theme="bento"] #zmw-view .zm-cards > .zm-card:nth-child(4n+2) { background-color: color-mix(in srgb, #dcecff var(--zm-glass), transparent); }
html.zm-dust-on[data-theme="bento"] #zmw-view .zm-cards > .zm-card:nth-child(4n+3) { background-color: color-mix(in srgb, #ffe6c4 var(--zm-glass), transparent); }
html.zm-dust-on[data-theme="bento"] #zmw-view .zm-cards > .zm-card:nth-child(4n+4) { background-color: color-mix(in srgb, #dff2e2 var(--zm-glass), transparent); }
html.zm-dust-on[data-theme="minimal"] #zmw-view .zm-card { background-color: transparent; }
html.zm-dust-on[data-theme] .zmw-side { background-color: color-mix(in srgb, var(--surface-solid) var(--zm-glass-side), transparent); background-image: none; backdrop-filter: none; -webkit-backdrop-filter: none; }
@media (max-width: 960px) { html.zm-dust-on[data-theme] .zmw-side { background-color: var(--surface-solid); } }
html.zm-dust-on[data-theme] .zmw-login-card { background-color: color-mix(in srgb, var(--surface-solid) 78%, transparent); background-image: none; }
html.zm-dust-on[data-theme="matrix"] .zmw-login-card { background-color: rgba(0,10,3,.84); }
html.zm-dust-on[data-theme="micro"], html.zm-dust-on[data-theme="light"], html.zm-dust-on[data-theme="ink"] { --zm-glass: 36%; }
html.zm-dust-on:not(.zm-theme-dark) { --zm-glass-in: 44%; --zm-glass-in3: 52%; --zm-pan: var(--surface-2); --zm-pan3: var(--surface-3); }
html.zm-dust-on[data-theme="ink"] { --zm-pan: #ffffff; }
html.zm-dust-on[data-theme="bento"] { --zm-glass-in: 62%; --zm-glass-in3: 66%; }
html.zm-dust-on[data-theme="retro"] { --zm-glass-in: 62%; --zm-glass-in3: 66%; }
html.zm-dust-on:not(.zm-theme-dark)[data-theme] #zmw-view .zm-card :is( .zm-svc:not(.zm-svc-on), .zm-seg, .zm-tt-tile, .zm-tt-row, .zm-current-banner.zm-current-empty) {
	background-color: color-mix(in srgb, var(--zm-pan) var(--zm-glass-in), transparent);
	backdrop-filter: none; -webkit-backdrop-filter: none;
	transition: background-color .35s ease;
}
.zmw-theme-menu { overscroll-behavior: contain; box-sizing: border-box; }
@media (max-width: 480px) {
	.zmw-theme-menu { gap: 2px; padding: 6px; border-radius: 16px; }
	.zmw-theme-opt { padding: 10px; }
}
@media (max-width: 420px) {
	.zmw-top { padding: 10px 12px; gap: 6px; }
	.zmw-top-actions { gap: 4px; }
	.zmw-icon-btn { height: 34px; min-width: 34px; padding: 0 7px; }
	.zmw-icon-btn .zmw-i { width: 18px; height: 18px; }
	.zmw-title { font-size: 17px; }
}
@media (max-width: 360px) {
	.zmw-top { flex-wrap: wrap; row-gap: 6px; }
	.zmw-top-actions { margin-left: auto; }
	.zmw-titles { order: 3; flex: 1 1 100%; }
	.zmw-title { -webkit-line-clamp: 2; overflow-wrap: normal; }
}
ZM_INSTALLER_EOF
cat > '/www/zm-webui.html' << 'ZM_INSTALLER_EOF'
<!doctype html>
<html lang="ru" data-theme="micro">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#f3f5fa">
<meta name="robots" content="noindex, nofollow">
<title>Zapret Manager</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg%20xmlns=%27http://www.w3.org/2000/svg%27%20viewBox=%270%200%201250%201250%27%3E%3Cdefs%3E%3ClinearGradient%20id=%27z%27%20x1=%270%27%20y1=%270%27%20x2=%270%27%20y2=%271%27%3E%3Cstop%20offset=%270%27%20stop-color=%27%2300b6ff%27/%3E%3Cstop%20offset=%271%27%20stop-color=%27%230090ff%27/%3E%3C/linearGradient%3E%3C/defs%3E%3Cg%20fill=%27url%28%23z%29%27%20stroke=%27%230a0a0a%27%20stroke-width=%2722%27%20stroke-linejoin=%27miter%27%3E%3Cpolygon%20points=%27455,170%201072,118%201215,25%20688,615%2025,1235%20735,338%20262,383%27/%3E%3Cpolygon%20points=%271025,462%20722,860%201215,800%201005,1022%20315,1095%27/%3E%3C/g%3E%3C/svg%3E">
<link rel="apple-touch-icon" href="data:image/svg+xml,%3Csvg%20xmlns=%27http://www.w3.org/2000/svg%27%20viewBox=%270%200%201250%201250%27%3E%3Cdefs%3E%3ClinearGradient%20id=%27z%27%20x1=%270%27%20y1=%270%27%20x2=%270%27%20y2=%271%27%3E%3Cstop%20offset=%270%27%20stop-color=%27%2300b6ff%27/%3E%3Cstop%20offset=%271%27%20stop-color=%27%230090ff%27/%3E%3C/linearGradient%3E%3C/defs%3E%3Cg%20fill=%27url%28%23z%29%27%20stroke=%27%230a0a0a%27%20stroke-width=%2722%27%20stroke-linejoin=%27miter%27%3E%3Cpolygon%20points=%27455,170%201072,118%201215,25%20688,615%2025,1235%20735,338%20262,383%27/%3E%3Cpolygon%20points=%271025,462%20722,860%201215,800%201005,1022%20315,1095%27/%3E%3C/g%3E%3C/svg%3E">
<link rel="stylesheet" href="/zm/app.css?v=__ZMW_BUILD__">
<script>
(function(){try{var t=null,re=/^(micro|light|dark|ink|bento|minimal|retro|depth|graphite|oled|matrix)$/;try{var x=new XMLHttpRequest();x.open('GET','/zm/theme.txt?t='+Date.now(),false);x.send(null);if(x.status===200){var v=String(x.responseText||'').trim();if(re.test(v)){t=v;try{localStorage.setItem('zmw.theme',v);}catch(e){}}}}catch(e){}if(!t)t=localStorage.getItem('zmw.theme')||sessionStorage.getItem('zmw.theme');if(!/^(micro|light|dark|ink|bento|minimal|retro|depth|graphite|oled|matrix)$/.test(t||''))t='micro';document.documentElement.setAttribute('data-theme',t);if(/^(dark|depth|graphite|oled|matrix)$/.test(t))document.documentElement.classList.add('zm-theme-dark');}catch(e){}})();
</script>
</head>
<body class="zmw-body">
<div id="zmw-root"></div>
<noscript><p style="padding:24px;font-family:sans-serif">Для работы панели Zapret Manager нужен JavaScript.</p></noscript>
<script src="/zm/app.js?v=__ZMW_BUILD__"></script>
</body>
</html>
ZM_INSTALLER_EOF
ZMW_BUILD="$(date +%s)"
sed -i "s/__ZMW_BUILD__/$ZMW_BUILD/g" /www/zm/app.js /www/zm/app.css /www/zm-webui.html
chmod 0644 /www/zm/app.js /www/zm/app.css /www/zm-webui.html
mkdir -p /etc/crontabs 2>/dev/null || true
[ -f /etc/crontabs/root ] || : > /etc/crontabs/root 2>/dev/null || true
sed -i '/# zm-rpcd-watch$/d' /etc/crontabs/root 2>/dev/null || true
_zmi_prune_panel_cron() {
    [ -f "$1" ] || return 0
    awk '/\/opt\/zapret-manager-luci\/backend[.]sh/ && / (adblock_[a-z_]+|steer_[a-z_]+|forkop_[a-z_]+|doh_[a-z_]+|dns_net_[a-z_]+|tg_[a-z_]+|tgws_[a-z_]+|tsc_[a-z_]+|awg_[a-z_]+|mixomo_[a-z_]+|bytetube_[a-z_]+|backup_[a-z_]+|zm_cleanup|zm_autoclean|zm_refs_heal|monitor|monitor_procs)( |$)/ { next } { print }' "$1" > "$1.zm-new"
    cat "$1.zm-new" > "$1"; rm -f "$1.zm-new"
}
_zmi_prune_panel_cron /etc/crontabs/root
_zmi_prune_panel_cron /opt/zapret-manager-luci/state/cron.saved

if [ -s /opt/zapret-manager-luci/state/cron.saved ]; then
	while IFS= read -r _zm_l; do
		[ -n "$_zm_l" ] || continue
		grep -qxF "$_zm_l" /etc/crontabs/root 2>/dev/null || echo "$_zm_l" >> /etc/crontabs/root
	done < /opt/zapret-manager-luci/state/cron.saved
	rm -f /opt/zapret-manager-luci/state/cron.saved
	_zmi_ok "Расписание панели восстановлено из сохранённых настроек"
fi
if [ -f /opt/zapret-manager-luci/state/watch.off ]; then
	_zmi_ok "Фоновые проверки ранее выключены — сохраняем настройку"
else
	echo '*/2 * * * * /opt/zapret-manager-luci/backend.sh zm_watch >/dev/null 2>&1 # zm-rpcd-watch' >> /etc/crontabs/root 2>/dev/null || true
fi
ZM_NO_CRON_RESTART=1 /opt/zapret-manager-luci/backend.sh versions_cron_sync >/dev/null 2>&1 || true
if [ "${ZM_FORKOP_TRANSACTION:-0}" != 1 ]; then
case "$(uci -q get system.@system[0].cronloglevel)" in
	''|5|8)
	uci -q set system.@system[0].cronloglevel='9' && uci -q commit system ;;
esac
if [ -x /etc/init.d/cron ]; then
	/etc/init.d/cron enable >/dev/null 2>&1 || true
	/etc/init.d/cron restart >/dev/null 2>&1 || true
fi
fi
if [ -s /opt/zapret-manager-luci/state/ui.theme ]; then
	cp -f /opt/zapret-manager-luci/state/ui.theme /www/zm/theme.txt 2>/dev/null || true
	chmod 0644 /www/zm/theme.txt 2>/dev/null || true
fi

_zmi_ok "Файлы Web UI записаны"
_zmi_say "Включаем Web UI"
ZMW_RESTART=0
ZMW_OK=1
if [ ! -f /etc/config/uhttpd ]; then
	ZMW_OK=0
elif [ ! -e /usr/lib/uhttpd_ubus.so ]; then
	_zmi_pkg uhttpd-mod-ubus "Web UI без него не откроется, панель в LuCI работает." || true
	[ -e /usr/lib/uhttpd_ubus.so ] || ZMW_OK=0
	ZMW_RESTART=1
fi
if [ "$ZMW_OK" = 0 ]; then
	:
elif ! uci -q get uhttpd.zmweb >/dev/null; then
	uci set uhttpd.zmweb=uhttpd
	uci add_list uhttpd.zmweb.listen_http='0.0.0.0:7788'
	uci add_list uhttpd.zmweb.listen_http='[::]:7788'
	uci set uhttpd.zmweb.home='/www'
	uci set uhttpd.zmweb.index_page='zm-webui.html'
	uci set uhttpd.zmweb.ubus_prefix='/ubus'
	uci set uhttpd.zmweb.no_dirlists='1'
	uci set uhttpd.zmweb.rfc1918_filter='1'
	uci set uhttpd.zmweb.max_requests='12'
	uci set uhttpd.zmweb.max_connections='100'
	uci set uhttpd.zmweb.script_timeout='120'
	uci set uhttpd.zmweb.network_timeout='30'
	uci set uhttpd.zmweb.http_keepalive='20'
	uci set uhttpd.zmweb.tcp_keepalive='1'
	uci commit uhttpd
	ZMW_RESTART=1
fi
[ "$ZMW_RESTART" = "1" ] && { /etc/init.d/uhttpd restart >/dev/null 2>&1 || true; }





if [ -n "$_zm_old_ver" ] && [ "$_zm_old_ver" != "$ZM_NEW_VER" ]; then
	mkdir -p /opt/zapret-manager-luci/state
	echo "$_zm_old_ver" > /opt/zapret-manager-luci/state/cl.pending 2>/dev/null || true
fi
case "$(/opt/zapret-manager-luci/backend.sh zm_changelog_sync 2>/dev/null || true)" in
	*'"ok":true'*) _zmi_ok "Список изменений версии $ZM_NEW_VER загружен — панель покажет его при входе" ;;
esac
if [ "${ZM_FORKOP_TRANSACTION:-0}" != 1 ]; then
( sleep 30; /opt/zapret-manager-luci/backend.sh zm_watch ) >/dev/null 2>&1 </dev/null &
fi

ZMW_PORT="$(uci -q get uhttpd.zmweb.listen_http | tr ' ' '\n' | head -n1 | sed 's/.*://')"
ZMW_IP="$(/opt/zapret-manager-luci/backend.sh lan_ip 2>/dev/null || true)"
[ -n "$ZMW_IP" ] || ZMW_IP="192.168.1.1"

for _zm_c in "zms Zapret-Manager.sh" "zmsA Zapret-Manager.sh" "zmw ZapretManager_LuCI.sh"; do
	cat > "/usr/bin/${_zm_c%% *}" <<ZM_GET_EOF
#!/bin/sh
u="https://raw.githubusercontent.com/Screamshow/Zapret-Manager/main/${_zm_c#* }"
ZM_GET_EOF
	cat >> "/usr/bin/${_zm_c%% *}" <<'ZM_GET_EOF'
t="/tmp/zm-get.$$.sh"
get() { rm -f "$t"; if command -v curl >/dev/null 2>&1; then curl -fsSL --connect-timeout 10 --max-time 120 -o "$t" "$1"; else wget -q -O "$t" "$1"; fi && [ -s "$t" ] && ! head -c 512 "$t" | grep -qiE '<(!doctype|html)'; }
if get "$u"; then :; else
	ok=""; ms="$(/opt/zapret-manager-luci/backend.sh gh_mirrors 2>/dev/null)"
	[ -n "$ms" ] && echo "GitHub не ответил напрямую — пробуем зеркала"
	for m in $ms; do
		echo "  · $m…"
		get "https://$m/$u" && { echo "  ✓ Скачано через $m"; ok=1; break; }
		echo "  · $m не отдал файл"
	done
	[ -n "$ok" ] || { rm -f "$t"; echo "Не удалось скачать $u${ms:+ — ни напрямую, ни через зеркала}"; exit 1; }
fi
sh "$t" "$@"; r=$?; rm -f "$t"; exit $r
ZM_GET_EOF
	chmod +x "/usr/bin/${_zm_c%% *}"
done
if [ "$ZMW_OK" = 1 ]; then _zmi_ok "Web UI включён на порту ${ZMW_PORT:-7788}"
else _zmi_warn "Web UI не включён: на роутере нет веб-сервера uhttpd или не установился uhttpd-mod-ubus"; fi
echo -e "\n${GREEN}Готово: Zapret Manager для LuCI и Web $ZM_NEW_VER установлен${NC}\n"
echo -e "${CYAN}LuCI:   ${NC}Службы → Zapret Manager"
[ "$ZMW_OK" = 1 ] && echo -e "${CYAN}Web UI: ${NC}http://${ZMW_IP}:${ZMW_PORT:-7788}"
echo
