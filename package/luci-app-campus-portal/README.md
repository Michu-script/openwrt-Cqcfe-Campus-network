# luci-app-campus-portal

OpenWrt package source generated from the local `login_action.php` and captured portal JS behavior.

## Applicable systems

This package is intended for campus networks using `dr.com / eportal` style authentication.

Typical characteristics:

1. Login API is `/eportal/portal/login`
2. Online-state API is `/eportal/portal/online_list`
3. Login uses `GET + JSONP`
4. Required fields usually include `wlan_user_ip`, `wlan_user_mac`, `program_index`, `page_index`

## Login mechanism (derived from PHP/JS)

1. Gateway base URL (default): `http://login.cqcfe.com:801`
2. Login API: `/eportal/portal/login` (JSONP response)
3. Online-state API: `/eportal/portal/online_list` (JSONP response)
4. Core login parameters:
   - `user_account` / `user_password`
   - `wlan_user_ip` / `wlan_user_ipv6` / `wlan_user_mac`
   - `program_index` / `page_index`
   - `login_method` / `terminal_type` / `lang` / `jsVersion`

## Authentication flow

1. The daemon runs `ping cn.bing.com` every 5 seconds.
2. If ping succeeds, the plugin treats the network as reachable.
3. If ping fails, it calls `/eportal/portal/online_list` to verify portal login state.
4. If portal state is offline, it calls `/eportal/portal/login`.
5. After login, it verifies the result again using the online-state API.

This avoids false positives caused by HTTP cache and avoids repeated blind login attempts.

## Auto-detected client identity

1. The package first tries to resolve the `wan` side device used by the router.
2. It also checks `phy1-sta0` and `phy1-ap0`.
3. IPv4 is accepted only if it is in the `10.*` range.
4. If no valid IPv4 is found, the field stays empty.
5. MAC is taken from the selected interface, otherwise left empty.

## Runtime logic

1. Daemon checks `cn.bing.com` every 5 seconds using `ping`.
2. If connectivity check fails, it queries portal online state.
3. If not online, it triggers portal login.
4. During workday silent hours (default `00:00-05:00`) it skips all checks; holidays and rest days are never silent.
5. Consecutive login failures use progressive backoff, and reaching the retry cap enters a longer cooldown.
6. Each successful login is appended to a local history log and only the latest 5 records are kept.
7. Important operations are written to `/tmp/campus_portal.log`.
8. Runtime state is written to `/tmp/campus_portal_state.json` for LuCI display:
   - current login state
   - last internet check result
   - last action, time, and message
   - last 5 successful login records
   - recent operation logs

## Layout

- `Makefile`: OpenWrt package definition (`PKGARCH:=all`)
- `root/etc/config/campus_portal`: UCI config
- `root/etc/init.d/campus_portal`: procd init script
- `root/usr/sbin/campus_portal_daemon.sh`: daemon
- `root/usr/sbin/campus_portal_detect.sh`: interface detection helper
- `root/usr/lib/lua/luci/controller/campus_portal.lua`: LuCI menu
- `root/usr/lib/lua/luci/model/cbi/campus_portal.lua`: LuCI settings page

## Build as ipk in OpenWrt SDK/Buildroot

Place this folder as:

- `package/luci-app-campus-portal/`

Then run:

```sh
./scripts/feeds update -a
./scripts/feeds install -a
make package/luci-app-campus-portal/compile V=s
```

Output artifact example:

- `bin/packages/*/base/luci-app-campus-portal_1.0.0-1_all.ipk`

## Post-install

```sh
opkg install luci-app-campus-portal_1.0.0-1_all.ipk
/etc/init.d/campus_portal enable
/etc/init.d/campus_portal start
```

LuCI menu:

- `Services -> Campus Portal`
