local fs = require "nixio.fs"
local sys = require "luci.sys"
local jsonc = require "luci.jsonc"
local util = require "luci.util"

local STATE_FILE = "/tmp/campus_portal_state.json"
local HISTORY_FILE = "/tmp/campus_portal_login_history.log"
local LOG_FILE = "/tmp/campus_portal.log"
local DETECT_SCRIPT = "/usr/sbin/campus_portal_detect.sh"

local function read_state()
	local raw = fs.readfile(STATE_FILE)
	if not raw or raw == "" then
		return {}
	end

	local obj = jsonc.parse(raw)
	if type(obj) ~= "table" then
		return {}
	end

	return obj
end

local function read_detect()
	local result = {
		iface = "",
		ip = "",
		mac = ""
	}

	if not fs.access(DETECT_SCRIPT) then
		return result
	end

	local raw = sys.exec(DETECT_SCRIPT .. " 2>/dev/null")
	for line in raw:gmatch("[^\r\n]+") do
		local key, value = line:match("^([%w_]+)=(.*)$")
		if key then
			result[key] = value
		end
	end

	return result
end

local function read_history()
	local records = {}
	local raw = fs.readfile(HISTORY_FILE)

	if not raw or raw == "" then
		return records
	end

	for line in raw:gmatch("[^\r\n]+") do
		local item = {}
		item.time, item.account, item.iface, item.ip, item.mac, item.gateway =
			line:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")

		if item.time then
			table.insert(records, 1, item)
		end
	end

	return records
end

local function read_log_tail(limit)
	local raw = fs.readfile(LOG_FILE)
	local lines = {}
	local start
	local out = {}
	local i

	if not raw or raw == "" then
		return ""
	end

	for line in raw:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	start = math.max(#lines - limit + 1, 1)
	for i = start, #lines do
		table.insert(out, lines[i])
	end

	return table.concat(out, "\n")
end

local function first_nonempty(...)
	local i

	for i = 1, select("#", ...) do
		local value = select(i, ...)
		if value and value ~= "" then
			return value
		end
	end

	return ""
end

local function is_empty_ip(value)
	return not value or value == "" or value == "10.25.57.76"
end

local function is_empty_mac(value)
	return not value or value == "" or value == "000000000000"
end

local function map_login_state(value)
	if value == "online" then
		return "在线"
	elseif value == "offline" then
		return "离线"
	elseif value == "disabled" then
		return "已禁用"
	elseif value == "silent" then
		return "静默中"
	end

	return "未知"
end

local function map_check_state(value)
	if value == "ok" then
		return "成功"
	elseif value == "fail" then
		return "失败"
	elseif value == "skip" then
		return "跳过"
	end

	return "未知"
end

local function map_day_type(value)
	if value == "workday" then
		return "工作日"
	elseif value == "restday" then
		return "休息日/节假日"
	end

	return "未判定"
end

local function map_silent_state(value)
	if value == "silent" then
		return "静默中"
	elseif value == "active" then
		return "正常"
	end

	return "未知"
end

local state = read_state()
local detect = read_detect()
local history = read_history()
local log_tail_text = read_log_tail(20)

m = Map("campus_portal", "校园网自动登录",
	"移植自 LoginCqcfe 的 Dr.COM 认证方案。联网正常时仅用 ping 检测；断网时先查询校园网在线状态，未登录则自动提交登录。支持工作日静默时段、节假日识别、失败退避与失败上限。")

s = m:section(NamedSection, "main", "campus_portal", "运行状态与配置")
s.anonymous = true
s.addremove = false

status = s:option(DummyValue, "_login_state", "当前登录状态")
function status.cfgvalue()
	return map_login_state(state.login_state)
end

check = s:option(DummyValue, "_last_check", "最后一次联网检查")
function check.cfgvalue()
	local result = map_check_state(state.internet_check)
	local time = state.last_check_time or "-"
	local target = state.last_check_target or "cn.bing.com"
	local detail = state.last_check_detail or "-"
	return string.format("%s (时间: %s, 目标: %s, 详情: %s)", result, time, target, detail)
end

action = s:option(DummyValue, "_last_action", "最后动作")
function action.cfgvalue()
	local name = state.last_action or "-"
	local time = state.last_action_time or "-"
	local message = state.last_message or "-"
	return string.format("%s (时间: %s, 说明: %s)", name, time, message)
end

day_type = s:option(DummyValue, "_day_type", "今日类型")
function day_type.cfgvalue()
	return map_day_type(state.day_type)
end

silent_state = s:option(DummyValue, "_silent_state", "静默状态")
function silent_state.cfgvalue()
	return map_silent_state(state.silent_state)
end

fail_count = s:option(DummyValue, "_fail_count", "连续失败次数 / 下次等待")
function fail_count.cfgvalue()
	local count = state.fail_count or "0"
	local next_sleep = state.next_sleep or "-"
	return string.format("连续失败: %s 次, 下次检测等待: %s 秒", count, next_sleep)
end

detected_iface = s:option(DummyValue, "_detected_iface", "自动识别接口")
function detected_iface.cfgvalue()
	return first_nonempty(state.detected_iface, detect.iface, "-")
end

detected_ip = s:option(DummyValue, "_resolved_client_ip", "自动识别终端 IPv4")
function detected_ip.cfgvalue()
	return first_nonempty(state.resolved_client_ip, detect.ip, "-")
end

detected_mac = s:option(DummyValue, "_resolved_client_mac", "自动识别终端 MAC")
function detected_mac.cfgvalue()
	return first_nonempty(state.resolved_client_mac, detect.mac, "-")
end

enabled = s:option(Flag, "enabled", "启用守护进程")
enabled.default = "1"
enabled.rmempty = false

account = s:option(Value, "account", "账号")
account.rmempty = true
account.placeholder = "请输入校园网账号"
account.description = "仅填写学号本身，前缀由下方“账号前缀”自动拼接。"

account_prefix = s:option(Value, "account_prefix", "账号前缀")
account_prefix.default = ",0,"
account_prefix.rmempty = true
account_prefix.placeholder = ",0,"
account_prefix.description = "提交登录时账号前面拼接的字符串，重庆财经抓包为 ,0,（即 user_account=,0,学号）。留空表示账号原样提交（与 LoginCqcfe 一致）。"

password = s:option(Value, "password", "密码")
password.password = true
password.rmempty = true
password.placeholder = "请输入校园网密码"

gateway = s:option(Value, "gateway", "网关地址")
gateway.rmempty = false
gateway.placeholder = "http://login.cqcfe.com:801"
gateway.description = "重庆财经默认 http://login.cqcfe.com:801；其他校区请替换为对应网关。"

client_ip = s:option(Value, "client_ip", "终端 IPv4")
client_ip.rmempty = true
client_ip.placeholder = "留空自动识别 10.x.x.x"
client_ip.description = "留空时自动读取 wan 侧接口的 10.* IPv4，并兼顾 phy1-sta0 / phy1-ap0。"
function client_ip.cfgvalue(self, section)
	local value = Value.cfgvalue(self, section)
	if is_empty_ip(value) then
		return first_nonempty(state.resolved_client_ip, detect.ip, "")
	end
	return value
end

client_ipv6 = s:option(Value, "client_ipv6", "终端 IPv6")
client_ipv6.rmempty = true
client_ipv6.placeholder = "::"

client_mac = s:option(Value, "client_mac", "终端 MAC")
client_mac.rmempty = true
client_mac.placeholder = "留空自动识别"
client_mac.description = "留空时自动读取已识别接口的 MAC 地址。"
function client_mac.cfgvalue(self, section)
	local value = Value.cfgvalue(self, section)
	if is_empty_mac(value) then
		return first_nonempty(state.resolved_client_mac, detect.mac, "")
	end
	return value
end

program_index = s:option(Value, "program_index", "方案索引(program_index)")
program_index.rmempty = false

page_index = s:option(Value, "page_index", "页面索引(page_index)")
page_index.rmempty = false

check_interval = s:option(Value, "check_interval", "检测间隔(秒)")
check_interval.datatype = "uinteger"
check_interval.default = "5"
check_interval.rmempty = false

check_timeout = s:option(Value, "check_timeout", "请求超时(秒)")
check_timeout.datatype = "uinteger"
check_timeout.default = "5"
check_timeout.rmempty = false

check_url = s:option(Value, "check_url", "联网检测主机")
check_url.default = "cn.bing.com"
check_url.rmempty = false
check_url.placeholder = "cn.bing.com"
check_url.description = "使用 ping 检测。支持填写域名，也兼容旧格式 http://cn.bing.com/。"

online_api = s:option(Value, "online_api", "在线状态接口路径")
online_api.default = "/eportal/portal/online_list"
online_api.rmempty = false

login_api = s:option(Value, "login_api", "登录接口路径")
login_api.default = "/eportal/portal/login"
login_api.rmempty = false

login_method = s:option(Value, "login_method", "登录方式(login_method)")
login_method.default = "1"
login_method.datatype = "uinteger"
login_method.rmempty = false

terminal_type = s:option(Value, "terminal_type", "终端类型(terminal_type)")
terminal_type.default = "1"
terminal_type.datatype = "uinteger"
terminal_type.rmempty = false

lang = s:option(Value, "lang", "语言(lang)")
lang.default = "zh-cn"
lang.rmempty = false

js_version = s:option(Value, "js_version", "脚本版本(jsVersion)")
js_version.default = "4.2.1"
js_version.rmempty = false

silent_enabled = s:option(Flag, "silent_enabled", "启用静默时段")
silent_enabled.default = "1"
silent_enabled.rmempty = false
silent_enabled.description = "仅在工作日（含调休补班日）的静默时段内完全跳过检测与登录；休息日、节假日全天不静默。"

silent_start = s:option(Value, "silent_start", "静默开始时间")
silent_start.default = "00:00"
silent_start.rmempty = false
silent_start.placeholder = "00:00"
silent_start.description = "24 小时制 HH:MM。开始时间大于结束时间时表示跨天时段。"

silent_end = s:option(Value, "silent_end", "静默结束时间")
silent_end.default = "05:00"
silent_end.rmempty = false
silent_end.placeholder = "05:00"

silent_sleep = s:option(Value, "silent_sleep", "静默期休眠(秒)")
silent_sleep.datatype = "uinteger"
silent_sleep.default = "60"
silent_sleep.rmempty = false
silent_sleep.description = "静默期间的循环休眠间隔，适当调大可进一步降低资源占用。"

holiday_enabled = s:option(Flag, "holiday_enabled", "启用在线节假日识别")
holiday_enabled.default = "1"
holiday_enabled.rmempty = false
holiday_enabled.description = "每天仅请求一次节假日接口，结果缓存至当日。关闭后仅依据手动列表与星期判断。"

holiday_api = s:option(Value, "holiday_api", "节假日接口地址")
holiday_api.default = "https://timor.tech/api/holiday/info"
holiday_api.rmempty = false
holiday_api.description = "接口最终请求格式为 地址/YYYY-MM-DD。默认使用 timor.tech。"

holiday_list = s:option(Value, "holiday_list", "手动节假日列表")
holiday_list.rmempty = true
holiday_list.placeholder = "2026-10-01,2026-10-02,2026-10-03"
holiday_list.description = "逗号或分号分隔的日期(YYYY-MM-DD)。填写的日期强制按休息日处理，优先级最高。"

workday_list = s:option(Value, "workday_list", "手动补班日列表")
workday_list.rmempty = true
workday_list.placeholder = "2026-10-11"
workday_list.description = "逗号或分号分隔的日期(YYYY-MM-DD)。填写的日期强制按工作日处理（含周末补班）。"

max_retry = s:option(Value, "max_retry", "失败上限(次)")
max_retry.datatype = "uinteger"
max_retry.default = "10"
max_retry.rmempty = false
max_retry.description = "连续登录失败达到该次数后进入冷却休眠，避免断网时段无限重试。"

retry_cooldown = s:option(Value, "retry_cooldown", "失败冷却休眠(秒)")
retry_cooldown.datatype = "uinteger"
retry_cooldown.default = "1800"
retry_cooldown.rmempty = false
retry_cooldown.description = "达到失败上限后休眠的秒数，默认 1800 秒（30 分钟），之后自动恢复尝试。"

backoff_max = s:option(Value, "backoff_max", "退避最大值(秒)")
backoff_max.datatype = "uinteger"
backoff_max.default = "300"
backoff_max.rmempty = false
backoff_max.description = "渐进退避序列为 首次间隔→15→30→60→120→该值，登录成功后立即重置。"

history_title = s:option(DummyValue, "_history_title", "最近5次成功登录记录")
function history_title.cfgvalue()
	if #history == 0 then
		return "暂无成功登录记录"
	end
	return string.format("共显示最近 %d 条记录", math.min(#history, 5))
end

local i
for i = 1, 5 do
	local opt = s:option(DummyValue, "_history_" .. i, "成功记录 " .. i)
	function opt.cfgvalue()
		local item = history[i]
		if not item then
			return "-"
		end

		return string.format(
			"%s | 账号: %s | 接口: %s | IPv4: %s | MAC: %s | 网关: %s",
			item.time or "-",
			item.account or "-",
			item.iface or "-",
			item.ip or "-",
			item.mac or "-",
			item.gateway or "-"
		)
	end
end

log_path = s:option(DummyValue, "_log_path", "日志文件")
function log_path.cfgvalue()
	return LOG_FILE
end

log_tail = s:option(DummyValue, "_log_tail", "最近日志")
log_tail.rawhtml = true
function log_tail.cfgvalue()
	if log_tail_text == "" then
		return "暂无日志"
	end

	return "<pre style=\"white-space:pre-wrap;max-height:320px;overflow:auto;\">" ..
		util.pcdata(log_tail_text) ..
		"</pre>"
end

return m
