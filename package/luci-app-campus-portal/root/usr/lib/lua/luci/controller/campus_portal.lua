module("luci.controller.campus_portal", package.seeall)

local fs = require "nixio.fs"

function index()
	if not fs.access("/etc/config/campus_portal") then
		return
	end

	entry({"admin", "services", "campus_portal"}, cbi("campus_portal"), _("校园网自动登录"), 60).dependent = false
end
