module("luci.controller.wireless_helper", package.seeall)

function index()
	local fs = require "nixio.fs"

	if not fs.access("/etc/config/wireless") then
		return
	end

	entry({"admin", "network", "wireless_helper"}, cbi("wireless_helper"), _("无线助手"), 90).dependent = false
end
