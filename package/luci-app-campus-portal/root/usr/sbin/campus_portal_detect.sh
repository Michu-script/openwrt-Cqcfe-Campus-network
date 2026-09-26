#!/bin/sh

. /lib/functions.sh
[ -f /lib/functions/network.sh ] && . /lib/functions/network.sh
[ -f /usr/share/libubox/jshn.sh ] && . /usr/share/libubox/jshn.sh

CANDIDATES=""
DETECT_IFACE=""
DETECT_IP=""
DETECT_MAC=""

append_unique_iface() {
	local iface="$1"

	[ -n "$iface" ] || return 0

	case " $CANDIDATES " in
	*" $iface "*) ;;
	*) CANDIDATES="${CANDIDATES:+$CANDIDATES }$iface" ;;
	esac
}

iface_exists() {
	[ -n "$1" ] && [ -d "/sys/class/net/$1" ]
}

get_iface_ip() {
	local iface="$1"

	command -v ip >/dev/null 2>&1 || return 0

	ip -4 addr show dev "$iface" 2>/dev/null \
		| awk '/inet / { sub(/\/.*/, "", $2); print $2 }' \
		| awk '/^10\./ { print; exit }'
}

get_iface_mac() {
	local iface="$1"

	[ -r "/sys/class/net/$iface/address" ] || return 0

	tr '[:lower:]' '[:upper:]' <"/sys/class/net/$iface/address" | tr -d ':-\r\n'
}

load_network_candidates() {
	local wan_name=""
	local wan_device=""

	command -v network_find_wan >/dev/null 2>&1 || return 0

	network_find_wan wan_name >/dev/null 2>&1 || return 0
	[ -n "$wan_name" ] || return 0

	command -v network_get_device >/dev/null 2>&1 && network_get_device wan_device "$wan_name"
	append_unique_iface "$wan_device"
}

load_ubus_candidates() {
	local status=""
	local device=""
	local l3_device=""

	command -v ubus >/dev/null 2>&1 || return 0
	command -v json_load >/dev/null 2>&1 || return 0

	status="$(ubus call network.interface.wan status 2>/dev/null)" || return 0
	[ -n "$status" ] || return 0

	json_init
	json_load "$status"
	json_get_var device device
	json_get_var l3_device l3_device

	append_unique_iface "$device"
	append_unique_iface "$l3_device"
}

build_candidates() {
	load_network_candidates
	load_ubus_candidates
	append_unique_iface "phy1-sta0"
	append_unique_iface "phy1-ap0"
	append_unique_iface "wan"
	append_unique_iface "wwan"
}

detect_identity() {
	local iface=""
	local first_iface=""
	local ip=""

	build_candidates

	for iface in $CANDIDATES; do
		iface_exists "$iface" || continue

		[ -z "$first_iface" ] && first_iface="$iface"

		ip="$(get_iface_ip "$iface")"
		if [ -n "$ip" ]; then
			DETECT_IFACE="$iface"
			DETECT_IP="$ip"
			break
		fi
	done

	[ -z "$DETECT_IFACE" ] && DETECT_IFACE="$first_iface"

	if [ -n "$DETECT_IFACE" ]; then
		DETECT_MAC="$(get_iface_mac "$DETECT_IFACE")"
	fi
}

output_env() {
	printf 'iface=%s\n' "$DETECT_IFACE"
	printf 'ip=%s\n' "$DETECT_IP"
	printf 'mac=%s\n' "$DETECT_MAC"
}

main() {
	detect_identity
	output_env
}

main "$@"
