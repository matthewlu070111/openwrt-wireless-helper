local fs = require "nixio.fs"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()

local script = "/usr/libexec/wireless-helper"
local last_log = "/tmp/wireless-helper.last"

if not uci:get("wireless_helper", "settings") then
	uci:section("wireless_helper", "settings", "settings", {
		enabled = "0",
		path_prefix = "platform/ff5c0000.usb",
		preferred_radio = "",
		reload_wifi = "0"
	})
	uci:commit("wireless_helper")
end

local m = Map("wireless_helper", translate("无线助手"),
	translate("检测并清理因 USB sysfs 路径漂移导致的重复 Wi-Fi radio 配置。"))

local s = m:section(NamedSection, "settings", "settings", translate("设置"))
s.anonymous = true
s.addremove = false

local enabled = s:option(Flag, "enabled", translate("自动清理"))
enabled.default = "0"
enabled.rmempty = false
enabled.description = translate("在系统启动和 USB 热插拔事件发生后自动执行清理。")

local prefix = s:option(Value, "path_prefix", translate("USB 路径前缀"))
prefix.default = "platform/ff5c0000.usb"
prefix.placeholder = "platform/ff5c0000.usb"
prefix.description = translate("只处理此 sysfs 前缀下的 wifi-device 路径。")

local reload = s:option(Flag, "reload_wifi", translate("清理后重载 Wi-Fi"))
reload.default = "0"
reload.rmempty = false
reload.description = translate("删除重复 radio 配置后立即应用无线配置。")

local preferred = s:option(ListValue, "preferred_radio", translate("默认保留的 radio"))
preferred:value("", translate("自动检测正在工作的 radio"))
preferred.rmempty = true
preferred.description = translate("发现重复项时优先保留此 radio，并把无线接口迁移到它。自动模式会优先保留正在工作的 radio。")

if fs.access(script) then
	for line in sys.exec(script .. " list-radios 2>/dev/null"):gmatch("[^\r\n]+") do
		local value, label = line:match("^([^|]+)|(.+)$")
		if value and label then
			preferred:value(value, label)
		end
	end
end

local scan = s:option(Button, "_scan", translate("扫描"))
scan.inputstyle = "find"
function scan.write()
	sys.call(script .. " status > " .. last_log .. " 2>&1")
end

local dryrun = s:option(Button, "_dryrun", translate("预览清理"))
dryrun.inputstyle = "reload"
function dryrun.write()
	sys.call(script .. " dry-run > " .. last_log .. " 2>&1")
end

local clean = s:option(Button, "_clean", translate("清理重复项"))
clean.inputstyle = "apply"
function clean.write()
	sys.call(script .. " clean > " .. last_log .. " 2>&1")
end

local remember = s:option(Button, "_remember", translate("记住当前 radio"))
remember.inputstyle = "save"
function remember.write()
	sys.call(script .. " remember > " .. last_log .. " 2>&1")
end

local output = s:option(TextValue, "_output", translate("状态"))
output.rows = 18
output.readonly = true
output.wrap = "off"
function output.cfgvalue()
	if fs.access(last_log) then
		return fs.readfile(last_log) or ""
	end

	if fs.access(script) then
		return sys.exec(script .. " status 2>&1")
	end

	return translate("后台脚本未安装。")
end

function output.write() end

return m
