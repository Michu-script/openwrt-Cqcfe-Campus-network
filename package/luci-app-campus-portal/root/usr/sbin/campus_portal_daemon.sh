#!/bin/sh

. /lib/functions.sh
. /usr/share/libubox/jshn.sh

DETECT_SCRIPT="/usr/sbin/campus_portal_detect.sh"
HISTORY_FILE="/tmp/campus_portal_login_history.log"
HISTORY_TMP="/tmp/campus_portal_login_history.log.tmp"
LOG_FILE="/tmp/campus_portal.log"
LOG_TMP="/tmp/campus_portal.log.tmp"
STATE_FILE="/tmp/campus_portal_state.json"
STATE_TMP="/tmp/campus_portal_state.json.tmp"
DAY_CACHE_FILE="/tmp/campus_portal_day.cache"
IDENTITY_CACHE_FILE="/tmp/campus_portal_identity.cache"

IDENTITY_TTL="60"

ENABLED=1
GATEWAY="http://login.cqcfe.com:801"
LOGIN_API_PATH="/eportal/portal/login"
ONLINE_API_PATH="/eportal/portal/online_list"
ACCOUNT=""
PASSWORD=""
ACCOUNT_PREFIX=",0,"
CLIENT_IP=""
CLIENT_IPV6=""
CLIENT_MAC=""
PROGRAM_INDEX="ncVFE21678594699"
PAGE_INDEX="E9c9Ye1683864938"
LOGIN_METHOD="1"
TERMINAL_TYPE="1"
LANG_CODE="zh-cn"
JS_VERSION="4.2.1"
CHECK_URL="cn.bing.com"
CHECK_TIMEOUT="5"
CHECK_INTERVAL="5"

SILENT_ENABLED=1
SILENT_START="00:00"
SILENT_END="05:00"
SILENT_SLEEP="60"

HOLIDAY_ENABLED=1
HOLIDAY_API="https://timor.tech/api/holiday/info"
HOLIDAY_LIST=""
WORKDAY_LIST=""

MAX_RETRY="10"
RETRY_COOLDOWN="1800"
BACKOFF_MAX="300"

LOGIN_STATE="unknown"
INTERNET_CHECK="unknown"
LAST_CHECK_HTTP="ping_unknown"
LAST_CHECK_DETAIL=""
LAST_CHECK_TARGET="cn.bing.com"
LAST_CHECK_TIME=""
LAST_ACTION="none"
LAST_ACTION_TIME=""
LAST_MESSAGE="starting"
ACCOUNT_MASKED=""
DETECTED_IFACE=""

DAY_TYPE="unknown"
SILENT_STATE="active"
FAIL_COUNT=0
NEXT_SLEEP=5

log() {
	local message="$*"

	logger -t campus-portal "$message"

	{
		if [ -f "$LOG_FILE" ]; then
			tail -n 499 "$LOG_FILE" 2>/dev/null || true
		fi
		printf '%s %s\n' "$(now_human)" "$message"
	} >"$LOG_TMP"

	mv "$LOG_TMP" "$LOG_FILE"
}

now_human() {
	date "+%Y-%m-%d %H:%M:%S"
}

sanitize_int() {
	local value="$1"
	local fallback="$2"
	case "$value" in
	''|*[!0-9]*)
		echo "$fallback"
		;;
	*)
		if [ "$value" -gt 0 ]; then
			echo "$value"
		else
			echo "$fallback"
		fi
		;;
	esac
}

mask_account() {
	local acc="$1"
	local len

	len="${#acc}"
	if [ "$len" -le 4 ]; then
		printf '****'
		return
	fi

	printf '%s****' "${acc%????}"
}

normalize_api_path() {
	local p="$1"
	[ -z "$p" ] && p="/"
	case "$p" in
	/*) printf '%s' "$p" ;;
	*) printf '/%s' "$p" ;;
	esac
}

join_url() {
	local base="$1"
	local path="$2"
	printf '%s%s' "${base%/}" "$(normalize_api_path "$path")"
}

extract_host_root() {
	printf '%s' "$GATEWAY" | sed -n 's#^\(https\?://[^/]*\).*$#\1/#p'
}

extract_jsonp() {
	local body="$1"
	body="${body#*\(}"
	body="${body%)}"
	body="${body%;}"
	printf '%s' "$body"
}

is_success_json() {
	local json="$1"
	printf '%s' "$json" | grep -Eq '"result"[[:space:]]*:[[:space:]]*(1|"ok")|"code"[[:space:]]*:[[:space:]]*(1|"ok")'
}

is_online_json() {
	local json="$1"
	printf '%s' "$json" | grep -Eq '"result"[[:space:]]*:[[:space:]]*(1|"ok")'
}

is_empty_client_ip() {
	case "$1" in
	''|'10.25.57.76') return 0 ;;
	*) return 1 ;;
	esac
}

is_empty_client_mac() {
	case "$1" in
	''|'000000000000') return 0 ;;
	*) return 1 ;;
	esac
}

extract_ping_target() {
	local target="$CHECK_URL"

	target="${target#*://}"
	target="${target%%/*}"
	target="${target%%:*}"

	[ -n "$target" ] || target="cn.bing.com"
	printf '%s' "$target"
}

in_list() {
	local needle="$1"
	local list="$2"
	local item

	[ -n "$list" ] || return 1

	for item in $(printf '%s' "$list" | tr ',;' '  '); do
		[ "$item" = "$needle" ] && return 0
	done

	return 1
}

hm_to_min() {
	local hm="$1"
	local h="${hm%%:*}"
	local m="${hm#*:}"

	h="${h#0}"
	[ -n "$h" ] || h=0
	m="${m#0}"
	[ -n "$m" ] || m=0

	case "$h" in ''|*[!0-9]*) h=0 ;; esac
	case "$m" in ''|*[!0-9]*) m=0 ;; esac

	printf '%s' "$((h * 60 + m))"
}

fetch_day_type() {
	local d="$1"
	local resp=""
	local t=""

	[ "$HOLIDAY_ENABLED" -eq 1 ] || return 2
	[ -n "$HOLIDAY_API" ] || return 2

	resp="$(curl -s --connect-timeout 3 --max-time 5 "$HOLIDAY_API/$d" 2>/dev/null)"
	[ -n "$resp" ] || return 2

	t="$(printf '%s' "$resp" | sed -n 's/.*"type":[[:space:]]*{[[:space:]]*"type":[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n 1)"
	[ -n "$t" ] || return 2

	case "$t" in
	0|3) printf '1' ;;
	*) printf '0' ;;
	esac
	return 0
}

day_type_of() {
	local d="$1"
	local dow="$2"
	local t=""

	in_list "$d" "$WORKDAY_LIST" && { printf '1'; return 0; }
	in_list "$d" "$HOLIDAY_LIST" && { printf '0'; return 0; }

	t="$(fetch_day_type "$d")"
	case "$t" in
	1) printf '1'; return 0 ;;
	0) printf '0'; return 0 ;;
	esac

	case "$dow" in
	6|7) printf '0' ;;
	*) printf '1' ;;
	esac
	return 0
}

refresh_day_type() {
	local d=""
	local dow=""
	local cached_date=""
	local cached_type=""

	d="$(date +%Y-%m-%d)"
	dow="$(date +%u)"

	if [ -f "$DAY_CACHE_FILE" ]; then
		read cached_date cached_type <"$DAY_CACHE_FILE" 2>/dev/null
	fi

	if [ "$cached_date" = "$d" ] && [ -n "$cached_type" ]; then
		DAY_TYPE="$cached_type"
	else
		DAY_TYPE="$(day_type_of "$d" "$dow")"
		printf '%s %s\n' "$d" "$DAY_TYPE" >"$DAY_CACHE_FILE"
		log "day type resolved: date=$d dow=$dow type=$DAY_TYPE"
	fi

	if [ "$DAY_TYPE" = "1" ]; then
		DAY_TYPE="workday"
	else
		DAY_TYPE="restday"
	fi
}

refresh_client_identity() {
	local line=""
	local key=""
	local value=""
	local detected_ip=""
	local detected_mac=""
	local detected_iface=""
	local output=""
	local now=""
	local last=0
	local cache_iface=""
	local cache_ip=""
	local cache_mac=""

	if ! is_empty_client_ip "$CLIENT_IP" && ! is_empty_client_mac "$CLIENT_MAC"; then
		return 0
	fi

	now="$(date +%s)"
	if [ -f "$IDENTITY_CACHE_FILE" ]; then
		read last cache_iface cache_ip cache_mac <"$IDENTITY_CACHE_FILE" 2>/dev/null
		case "$last" in ''|*[!0-9]*) last=0 ;; esac
	fi

	if [ -n "$cache_ip$cache_mac" ] && [ $((now - last)) -lt "$IDENTITY_TTL" ]; then
		DETECTED_IFACE="$cache_iface"
		is_empty_client_ip "$CLIENT_IP" && CLIENT_IP="$cache_ip"
		is_empty_client_mac "$CLIENT_MAC" && CLIENT_MAC="$cache_mac"
		return 0
	fi

	[ -x "$DETECT_SCRIPT" ] || return 0

	output="$("$DETECT_SCRIPT" 2>/dev/null)" || return 0

	for line in $output; do
		key="${line%%=*}"
		value="${line#*=}"

		case "$key" in
		iface) detected_iface="$value" ;;
		ip) detected_ip="$value" ;;
		mac) detected_mac="$value" ;;
		esac
	done

	DETECTED_IFACE="$detected_iface"
	printf '%s %s %s %s\n' "$now" "$detected_iface" "$detected_ip" "$detected_mac" >"$IDENTITY_CACHE_FILE"

	is_empty_client_ip "$CLIENT_IP" && CLIENT_IP="$detected_ip"
	is_empty_client_mac "$CLIENT_MAC" && CLIENT_MAC="$detected_mac"
	return 0
}

is_silent_window() {
	local now_min=""
	local start_min=""
	local end_min=""

	[ "$SILENT_ENABLED" -eq 1 ] || return 1

	now_min="$(hm_to_min "$(date +%H:%M)")"
	start_min="$(hm_to_min "$SILENT_START")"
	end_min="$(hm_to_min "$SILENT_END")"

	[ "$start_min" -eq "$end_min" ] && return 1

	if [ "$start_min" -lt "$end_min" ]; then
		if [ "$now_min" -ge "$start_min" ] && [ "$now_min" -lt "$end_min" ]; then
			return 0
		fi
	else
		if [ "$now_min" -ge "$start_min" ] || [ "$now_min" -lt "$end_min" ]; then
			return 0
		fi
	fi

	return 1
}

next_backoff() {
	local failures="$1"

	case "$failures" in
	1) printf '%s' "$CHECK_INTERVAL" ;;
	2) printf '15' ;;
	3) printf '30' ;;
	4) printf '60' ;;
	5) printf '120' ;;
	*) printf '%s' "$BACKOFF_MAX" ;;
	esac
}

record_success_login() {
	local record_time=""
	local record_account=""
	local record_iface=""
	local record_ip=""
	local record_mac=""
	local record_gateway=""

	record_time="$(now_human)"
	record_account="${ACCOUNT_MASKED:-}"
	record_iface="${DETECTED_IFACE:-}"
	record_ip="${CLIENT_IP:-}"
	record_mac="${CLIENT_MAC:-}"
	record_gateway="${GATEWAY:-}"

	[ -n "$record_account" ] || record_account="-"
	[ -n "$record_iface" ] || record_iface="-"
	[ -n "$record_ip" ] || record_ip="-"
	[ -n "$record_mac" ] || record_mac="-"
	[ -n "$record_gateway" ] || record_gateway="-"

	{
		if [ -f "$HISTORY_FILE" ]; then
			tail -n 4 "$HISTORY_FILE" 2>/dev/null || true
		fi
		printf '%s|%s|%s|%s|%s|%s\n' \
			"$record_time" \
			"$record_account" \
			"$record_iface" \
			"$record_ip" \
			"$record_mac" \
			"$record_gateway"
	} >"$HISTORY_TMP"

	mv "$HISTORY_TMP" "$HISTORY_FILE"
	log "login history appended: account=$record_account iface=$record_iface ip=$record_ip mac=$record_mac gateway=$record_gateway"
}

verify_portal_online_after_login() {
	local try=1

	while [ "$try" -le 3 ]; do
		if check_portal_online; then
			return 0
		fi

		sleep 1
		try=$((try + 1))
	done

	return 1
}

write_state() {
	json_init
	json_add_string timestamp "$(now_human)"
	json_add_string service_enabled "$ENABLED"
	json_add_string login_state "$LOGIN_STATE"
	json_add_string internet_check "$INTERNET_CHECK"
	json_add_string last_check_http "$LAST_CHECK_HTTP"
	json_add_string last_check_detail "$LAST_CHECK_DETAIL"
	json_add_string last_check_target "$LAST_CHECK_TARGET"
	json_add_string last_check_time "$LAST_CHECK_TIME"
	json_add_string last_action "$LAST_ACTION"
	json_add_string last_action_time "$LAST_ACTION_TIME"
	json_add_string last_message "$LAST_MESSAGE"
	json_add_string account_masked "$ACCOUNT_MASKED"
	json_add_string detected_iface "$DETECTED_IFACE"
	json_add_string resolved_client_ip "$CLIENT_IP"
	json_add_string resolved_client_mac "$CLIENT_MAC"
	json_add_string day_type "$DAY_TYPE"
	json_add_string silent_state "$SILENT_STATE"
	json_add_string fail_count "$FAIL_COUNT"
	json_add_string next_sleep "$NEXT_SLEEP"
	json_dump >"$STATE_TMP"
	mv "$STATE_TMP" "$STATE_FILE"
}

load_cfg() {
	config_load campus_portal || return 1

	config_get_bool ENABLED main enabled 1
	config_get GATEWAY main gateway "http://login.cqcfe.com:801"
	config_get LOGIN_API_PATH main login_api "/eportal/portal/login"
	config_get ONLINE_API_PATH main online_api "/eportal/portal/online_list"
	config_get ACCOUNT main account ""
	config_get PASSWORD main password ""
	config_get ACCOUNT_PREFIX main account_prefix ",0,"
	config_get CLIENT_IP main client_ip ""
	config_get CLIENT_IPV6 main client_ipv6 ""
	config_get CLIENT_MAC main client_mac ""
	config_get PROGRAM_INDEX main program_index "ncVFE21678594699"
	config_get PAGE_INDEX main page_index "E9c9Ye1683864938"
	config_get LOGIN_METHOD main login_method "1"
	config_get TERMINAL_TYPE main terminal_type "1"
	config_get LANG_CODE main lang "zh-cn"
	config_get JS_VERSION main js_version "4.2.1"
	config_get CHECK_URL main check_url "cn.bing.com"
	config_get CHECK_TIMEOUT main check_timeout "5"
	config_get CHECK_INTERVAL main check_interval "5"

	config_get_bool SILENT_ENABLED main silent_enabled 1
	config_get SILENT_START main silent_start "00:00"
	config_get SILENT_END main silent_end "05:00"
	config_get SILENT_SLEEP main silent_sleep "60"

	config_get_bool HOLIDAY_ENABLED main holiday_enabled 1
	config_get HOLIDAY_API main holiday_api "https://timor.tech/api/holiday/info"
	config_get HOLIDAY_LIST main holiday_list ""
	config_get WORKDAY_LIST main workday_list ""

	config_get MAX_RETRY main max_retry "10"
	config_get RETRY_COOLDOWN main retry_cooldown "1800"
	config_get BACKOFF_MAX main backoff_max "300"

	GATEWAY="${GATEWAY%/}"
	LOGIN_API_PATH="$(normalize_api_path "$LOGIN_API_PATH")"
	ONLINE_API_PATH="$(normalize_api_path "$ONLINE_API_PATH")"
	CHECK_TIMEOUT="$(sanitize_int "$CHECK_TIMEOUT" 5)"
	CHECK_INTERVAL="$(sanitize_int "$CHECK_INTERVAL" 5)"
	SILENT_SLEEP="$(sanitize_int "$SILENT_SLEEP" 60)"
	MAX_RETRY="$(sanitize_int "$MAX_RETRY" 10)"
	RETRY_COOLDOWN="$(sanitize_int "$RETRY_COOLDOWN" 1800)"
	BACKOFF_MAX="$(sanitize_int "$BACKOFF_MAX" 300)"
	LAST_CHECK_TARGET="$(extract_ping_target)"

	CLIENT_MAC="$(printf '%s' "$CLIENT_MAC" | tr '[:lower:]' '[:upper:]' | tr -d ':-')"
	ACCOUNT_MASKED="$(mask_account "$ACCOUNT")"

	refresh_client_identity
	refresh_day_type

	return 0
}

check_connectivity() {
	local output=""
	local detail=""

	output="$(ping -c 1 -W "$CHECK_TIMEOUT" "$LAST_CHECK_TARGET" 2>&1)"
	if [ $? -eq 0 ]; then
		detail="$(printf '%s\n' "$output" | sed -n 's/.*time=\([0-9.]*\).*/\1 ms/p' | head -n 1)"
		[ -n "$detail" ] || detail="pong"
		LAST_CHECK_HTTP="ping_ok"
		LAST_CHECK_DETAIL="$detail"
		return 0
	fi

	LAST_CHECK_HTTP="ping_fail"
	LAST_CHECK_DETAIL="$(printf '%s\n' "$output" | tail -n 1 | tr -d '\r')"
	[ -n "$LAST_CHECK_DETAIL" ] || LAST_CHECK_DETAIL="ping failed"
	return 1
}

check_portal_online() {
	local callback
	local api
	local ip64
	local ipv664
	local response
	local json

	[ -n "$CLIENT_IP" ] || return 1

	callback="dr$(date +%s)$$"
	api="$(join_url "$GATEWAY" "$ONLINE_API_PATH")"
	ip64="$(printf '%s' "$CLIENT_IP" | base64 | tr -d '\r\n')"
	ipv664="$(printf '%s' "$CLIENT_IPV6" | base64 | tr -d '\r\n')"

	response="$(curl -L -s --get \
		--connect-timeout "$CHECK_TIMEOUT" \
		--max-time "$CHECK_TIMEOUT" \
		"$api" \
		--data-urlencode "callback=$callback" \
		--data-urlencode "user_account=" \
		--data-urlencode "user_password=123" \
		--data-urlencode "wlan_user_mac=$CLIENT_MAC" \
		--data-urlencode "wlan_user_ip=$ip64" \
		--data-urlencode "wlan_user_ipv6=$ipv664" \
		--data-urlencode "jsVersion=$JS_VERSION" \
		--data-urlencode "v=$(date +%s)" 2>/dev/null)"

	[ -z "$response" ] && return 1

	json="$(extract_jsonp "$response")"
	is_online_json "$json"
}

do_portal_login() {
	local callback
	local api
	local referer
	local response
	local json

	[ -n "$CLIENT_IP" ] || return 1

	callback="dr$(date +%s)$$"
	api="$(join_url "$GATEWAY" "$LOGIN_API_PATH")"
	referer="$(extract_host_root)"
	[ -z "$referer" ] && referer="$GATEWAY/"

	response="$(curl -L -s --get \
		--connect-timeout "$CHECK_TIMEOUT" \
		--max-time "$CHECK_TIMEOUT" \
		"$api" \
		-H "Accept: */*" \
		-H "User-Agent: openwrt-campus-portal/1.0" \
		-H "Referer: $referer" \
		--data-urlencode "callback=$callback" \
		--data-urlencode "login_method=$LOGIN_METHOD" \
		--data-urlencode "user_account=${ACCOUNT_PREFIX}${ACCOUNT}" \
		--data-urlencode "user_password=$PASSWORD" \
		--data-urlencode "wlan_user_ip=$CLIENT_IP" \
		--data-urlencode "wlan_user_ipv6=$CLIENT_IPV6" \
		--data-urlencode "wlan_user_mac=$CLIENT_MAC" \
		--data-urlencode "wlan_ac_ip=" \
		--data-urlencode "wlan_ac_name=" \
		--data-urlencode "jsVersion=$JS_VERSION" \
		--data-urlencode "terminal_type=$TERMINAL_TYPE" \
		--data-urlencode "lang=$LANG_CODE" \
		--data-urlencode "program_index=$PROGRAM_INDEX" \
		--data-urlencode "page_index=$PAGE_INDEX" \
		--data-urlencode "v=$(date +%s)" 2>/dev/null)"

	[ -z "$response" ] && return 1

	json="$(extract_jsonp "$response")"
	is_success_json "$json"
}

handle_exit() {
	LAST_ACTION="stopped"
	LAST_ACTION_TIME="$(now_human)"
	LAST_MESSAGE="daemon_stopped"
	write_state
	exit 0
}

run_once() {
	NEXT_SLEEP="$CHECK_INTERVAL"

	if ! load_cfg; then
		LAST_CHECK_TIME="$(now_human)"
		LAST_ACTION="error"
		LAST_ACTION_TIME="$LAST_CHECK_TIME"
		LAST_MESSAGE="load_config_failed"
		write_state
		NEXT_SLEEP=5
		return
	fi

	LAST_CHECK_TIME="$(now_human)"

	if [ "$ENABLED" -ne 1 ]; then
		LOGIN_STATE="disabled"
		INTERNET_CHECK="skip"
		SILENT_STATE="active"
		LAST_ACTION="none"
		LAST_ACTION_TIME="$LAST_CHECK_TIME"
		LAST_MESSAGE="service_disabled"
		log "service disabled"
		write_state
		NEXT_SLEEP="$CHECK_INTERVAL"
		return
	fi

	if [ "$DAY_TYPE" = "workday" ] && is_silent_window; then
		LOGIN_STATE="silent"
		INTERNET_CHECK="skip"
		SILENT_STATE="silent"
		LAST_ACTION="none"
		LAST_ACTION_TIME="$LAST_CHECK_TIME"
		LAST_MESSAGE="silent_hours_skip"
		log "silent hours (workday), skip all checks"
		write_state
		NEXT_SLEEP="$SILENT_SLEEP"
		return
	fi

	SILENT_STATE="active"

	if check_connectivity; then
		FAIL_COUNT=0
		LOGIN_STATE="online"
		INTERNET_CHECK="ok"
		LAST_ACTION="none"
		LAST_ACTION_TIME="$LAST_CHECK_TIME"
		LAST_MESSAGE="bing_reachable"
		write_state
		NEXT_SLEEP="$CHECK_INTERVAL"
		return
	fi

	INTERNET_CHECK="fail"
	log "ping failed: target=$LAST_CHECK_TARGET detail=$LAST_CHECK_DETAIL"

	if [ -z "$CLIENT_IP" ]; then
		LOGIN_STATE="unknown"
		LAST_ACTION="skip_login"
		LAST_ACTION_TIME="$LAST_CHECK_TIME"
		LAST_MESSAGE="missing_client_ip"
		log "skip login: missing client ip"
		write_state
		NEXT_SLEEP="$CHECK_INTERVAL"
		return
	fi

	if check_portal_online; then
		FAIL_COUNT=0
		LOGIN_STATE="online"
		LAST_ACTION="none"
		LAST_ACTION_TIME="$LAST_CHECK_TIME"
		LAST_MESSAGE="bing_failed_but_portal_online"
		log "portal online while ping failed"
		write_state
		NEXT_SLEEP="$CHECK_INTERVAL"
		return
	fi

	LOGIN_STATE="offline"
	log "portal reported offline, login required"

	if [ -z "$ACCOUNT" ] || [ -z "$PASSWORD" ]; then
		LAST_ACTION="skip_login"
		LAST_ACTION_TIME="$LAST_CHECK_TIME"
		LAST_MESSAGE="missing_account_or_password"
		log "skip login: missing account or password"
		write_state
		NEXT_SLEEP="$CHECK_INTERVAL"
		return
	fi

	LAST_ACTION="login_attempt"
	LAST_ACTION_TIME="$(now_human)"
	log "login attempt: iface=$DETECTED_IFACE ip=$CLIENT_IP mac=$CLIENT_MAC fail_count=$FAIL_COUNT"

	if do_portal_login; then
		log "portal login api returned success"
		if verify_portal_online_after_login; then
			LOGIN_STATE="online"
			LAST_ACTION="login_success"
			LAST_MESSAGE="auto_login_success"
			record_success_login
			log "portal login verified online"
			FAIL_COUNT=0
			write_state
			NEXT_SLEEP="$CHECK_INTERVAL"
			return
		fi

		LOGIN_STATE="unknown"
		LAST_ACTION="login_uncertain"
		LAST_MESSAGE="login_success_but_verify_failed"
		log "portal login api succeeded but online verification failed after retries"
	else
		LOGIN_STATE="offline"
		LAST_ACTION="login_failed"
		LAST_MESSAGE="auto_login_failed"
		log "portal login api failed"
	fi

	FAIL_COUNT=$((FAIL_COUNT + 1))

	if [ "$FAIL_COUNT" -ge "$MAX_RETRY" ]; then
		LAST_MESSAGE="auto_login_failed_cooldown_${RETRY_COOLDOWN}s"
		log "reached max retry=$MAX_RETRY, cooldown ${RETRY_COOLDOWN}s"
		FAIL_COUNT=0
		NEXT_SLEEP="$RETRY_COOLDOWN"
	else
		NEXT_SLEEP="$(next_backoff "$FAIL_COUNT")"
		log "consecutive failures=$FAIL_COUNT, next retry in ${NEXT_SLEEP}s"
	fi

	write_state
}

main() {
	if ! command -v curl >/dev/null 2>&1; then
		log "curl not found, daemon exits"
		exit 1
	fi

	if ! command -v ping >/dev/null 2>&1; then
		log "ping not found, daemon exits"
		exit 1
	fi

	trap handle_exit INT TERM
	log "daemon started"
	write_state

	while true; do
		run_once
		sleep "$NEXT_SLEEP"
	done
}

main "$@"
