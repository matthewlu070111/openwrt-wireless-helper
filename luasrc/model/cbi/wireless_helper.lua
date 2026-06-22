local fs = require "nixio.fs"
local sys = require "luci.sys"

local script = "/usr/libexec/wireless-helper"
local last_log = "/tmp/wireless-helper.last"

local m = Map("wireless_helper", translate("Wireless Helper"),
	translate("Find and clean duplicate USB Wi-Fi radio sections caused by unstable USB sysfs paths."))

local s = m:section(NamedSection, "settings", "settings", translate("Settings"))
s.anonymous = true
s.addremove = false

local enabled = s:option(Flag, "enabled", translate("Automatic cleanup"))
enabled.default = "0"
enabled.rmempty = false
enabled.description = translate("Run the cleaner during boot and USB hotplug events.")

local prefix = s:option(Value, "path_prefix", translate("USB path prefix"))
prefix.default = "platform/ff5c0000.usb"
prefix.placeholder = "platform/ff5c0000.usb"
prefix.description = translate("Only wifi-device paths below this sysfs prefix are grouped.")

local reload = s:option(Flag, "reload_wifi", translate("Reload Wi-Fi after cleanup"))
reload.default = "0"
reload.rmempty = false
reload.description = translate("Apply wireless config after removing duplicate radio sections.")

local preferred = s:option(ListValue, "preferred_radio", translate("Default radio to keep"))
preferred:value("", translate("Auto detect active radio"))
preferred.rmempty = true
preferred.description = translate("When duplicates are found, keep this radio and migrate wireless interfaces to it. Auto mode prefers the active radio.")

if fs.access(script) then
	for line in sys.exec(script .. " list-radios 2>/dev/null"):gmatch("[^\r\n]+") do
		local value, label = line:match("^([^|]+)|(.+)$")
		if value and label then
			preferred:value(value, label)
		end
	end
end

local actions = m:section(SimpleSection, translate("Actions"))

local scan = actions:option(Button, "_scan", translate("Scan"))
scan.inputstyle = "find"
function scan.write()
	sys.call(script .. " status > " .. last_log .. " 2>&1")
end

local dryrun = actions:option(Button, "_dryrun", translate("Preview cleanup"))
dryrun.inputstyle = "reload"
function dryrun.write()
	sys.call(script .. " dry-run > " .. last_log .. " 2>&1")
end

local clean = actions:option(Button, "_clean", translate("Clean duplicates"))
clean.inputstyle = "apply"
function clean.write()
	sys.call(script .. " clean > " .. last_log .. " 2>&1")
end

local remember = actions:option(Button, "_remember", translate("Remember current radios"))
remember.inputstyle = "save"
function remember.write()
	sys.call(script .. " remember > " .. last_log .. " 2>&1")
end

local status = m:section(SimpleSection, translate("Status"))
local output = status:option(TextValue, "_output")
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

	return translate("Backend script is not installed.")
end

function output.write() end

return m
