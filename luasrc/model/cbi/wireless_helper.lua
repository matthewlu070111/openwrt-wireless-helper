local fs = require "nixio.fs"
local sys = require "luci.sys"
local uci = require "luci.model.uci".cursor()

local script = "/usr/libexec/wireless-helper"
local last_log = "/tmp/wireless-helper.last"
local watchdog_log = "/tmp/wireless-helper.watchdog.log"

if not uci:get("wireless_helper", "settings") then
	uci:section("wireless_helper", "settings", "settings", {
		enabled = "0",
		path_prefix = "platform/ff5c0000.usb",
		preferred_radio = "",
		reload_wifi = "0",
		auto_recover = "0",
		check_interval = "60",
		failure_threshold = "3",
		recovery_action = "wifi_reload",
		recovery_delay = "3",
		dns_takeover = "0",
		dns_upstream = "auto",
		dns_keep_domain_forwards = "1"
	})
	uci:commit("wireless_helper")
end

local m = Map("wireless_helper", translate("无线助手"),
	translate("检测 USB 无线网卡的路径漂移和 netifd 运行状态，并在网卡变为 unknown 时尝试恢复。"))

local s = m:section(NamedSection, "settings", "settings", translate("设置"))
s.anonymous = true
s.addremove = false
s:tab("general", translate("基础设置"))
s:tab("health", translate("健康监控"))
s:tab("dns", translate("DNS 接管"))
s:tab("actions", translate("诊断与恢复"))

local enabled = s:taboption("general", Flag, "enabled", translate("启用无线助手"))
enabled.default = "0"
enabled.rmempty = false
enabled.description = translate("在系统启动和 USB 热插拔后自动清理重复 radio；也是启用健康监控的前置开关。")

local prefix = s:taboption("general", Value, "path_prefix", translate("USB 路径前缀"))
prefix.default = "platform/ff5c0000.usb"
prefix.placeholder = "platform/ff5c0000.usb"
prefix.description = translate("只处理此 sysfs 前缀下的 wifi-device 路径。")

local reload = s:taboption("general", Flag, "reload_wifi", translate("清理后重载 Wi-Fi"))
reload.default = "0"
reload.rmempty = false
reload.description = translate("删除重复 radio 配置后立即应用无线配置。")

local preferred = s:taboption("general", ListValue, "preferred_radio", translate("默认保留的 radio"))
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

local auto_recover = s:taboption("health", Flag, "auto_recover", translate("自动恢复 unknown/down"))
auto_recover.default = "0"
auto_recover.rmempty = false
auto_recover:depends("enabled", "1")
auto_recover.description = translate("连续多次检测到异常才执行恢复，避免在无线初始化期间误触发。")

local interval = s:taboption("health", Value, "check_interval", translate("检查间隔（秒）"))
interval.datatype = "uinteger"
interval.default = "60"
interval:depends("auto_recover", "1")
interval.description = translate("最小 15 秒。")

local threshold = s:taboption("health", Value, "failure_threshold", translate("连续失败阈值"))
threshold.datatype = "uinteger"
threshold.default = "3"
threshold:depends("auto_recover", "1")

local action = s:taboption("health", ListValue, "recovery_action", translate("恢复策略"))
action:value("wifi_reload", translate("仅重置异常 radio（推荐）"))
action:value("network_restart", translate("重启 network 服务（强力）"))
action.default = "wifi_reload"
action.description = translate("重启 network 服务会短暂中断 LAN/WAN 和当前 LuCI 连接。")

local delay = s:taboption("health", Value, "recovery_delay", translate("radio 重置等待（秒）"))
delay.datatype = "uinteger"
delay.default = "3"
delay:depends("recovery_action", "wifi_reload")

local monitor = s:taboption("health", TextValue, "_monitor", translate("最近监控记录"))
monitor.rows = 4
monitor.readonly = true
monitor.wrap = "off"
function monitor.cfgvalue()
	if fs.access(watchdog_log) then
		return fs.readfile(watchdog_log) or ""
	end
	return translate("监控尚未启动。")
end
function monitor.write() end

local dns_takeover = s:taboption("dns", Flag, "dns_takeover", translate("同步接管 DNS"))
dns_takeover.default = "0"
dns_takeover.rmempty = false
dns_takeover:depends("enabled", "1")
dns_takeover.description = translate("将 dnsmasq 的默认上游固定为 Clash/Mihomo DNS，并持续修正被魔改系统或其他插件改回的配置。开启前会备份原配置。")

local dns_upstream = s:taboption("dns", Value, "dns_upstream", translate("Clash/Mihomo DNS 上游"))
dns_upstream.default = "auto"
dns_upstream.placeholder = "127.0.0.1#7874"
dns_upstream.description = translate("填 auto 时自动读取 OpenClash DNS 端口，读取失败则使用 127.0.0.1#7874。自定义格式为 IP#端口。")

local keep_forwards = s:taboption("dns", Flag, "dns_keep_domain_forwards", translate("保留域名专用转发"))
keep_forwards.default = "1"
keep_forwards.rmempty = false
keep_forwards.description = translate("保留 /internal.example/192.168.1.1 这类内网域名规则，其他默认上游会被替换，避免 DNS 绕过 Clash。")

local dns_status = s:taboption("dns", TextValue, "_dns_status", translate("DNS 状态"))
dns_status.rows = 5
dns_status.readonly = true
dns_status.wrap = "off"
function dns_status.cfgvalue()
	if fs.access(script) then
		return sys.exec(script .. " dns-status 2>&1")
	end
	return translate("后台脚本未安装。")
end
function dns_status.write() end

local dns_apply = s:taboption("dns", Button, "_dns_apply", translate("立即接管 DNS"))
dns_apply.inputstyle = "apply"
dns_apply.description = translate("只有检测到 Clash/Mihomo DNS 端口正在监听时才会修改 dnsmasq。")
function dns_apply.write()
	sys.call(script .. " dns-apply > " .. last_log .. " 2>&1")
end

local dns_restore = s:taboption("dns", Button, "_dns_restore", translate("恢复原 DNS 配置"))
dns_restore.inputstyle = "reset"
function dns_restore.write()
	sys.call(script .. " dns-restore > " .. last_log .. " 2>&1")
end

local scan = s:taboption("actions", Button, "_scan", translate("扫描状态"))
scan.inputstyle = "find"
function scan.write()
	sys.call(script .. " status > " .. last_log .. " 2>&1")
end

local health = s:taboption("actions", Button, "_health", translate("健康检查"))
health.inputstyle = "find"
function health.write()
	sys.call(script .. " health > " .. last_log .. " 2>&1")
end

local recover = s:taboption("actions", Button, "_recover", translate("立即恢复"))
recover.inputstyle = "apply"
recover.description = translate("对选定的 radio，或自动检测到的异常 radio，执行当前恢复策略。")
function recover.write()
	sys.call(script .. " recover > " .. last_log .. " 2>&1")
end

local restart = s:taboption("actions", Button, "_restart", translate("重启监控服务"))
restart.inputstyle = "reload"
function restart.write()
	sys.call("(/etc/init.d/wireless_helper restart && echo '监控服务已重启。') > " .. last_log .. " 2>&1")
end

local dryrun = s:taboption("actions", Button, "_dryrun", translate("预览清理"))
dryrun.inputstyle = "reload"
function dryrun.write()
	sys.call(script .. " dry-run > " .. last_log .. " 2>&1")
end

local clean = s:taboption("actions", Button, "_clean", translate("清理重复项"))
clean.inputstyle = "apply"
function clean.write()
	sys.call(script .. " clean > " .. last_log .. " 2>&1")
end

local remember = s:taboption("actions", Button, "_remember", translate("记住当前 radio"))
remember.inputstyle = "save"
function remember.write()
	sys.call(script .. " remember > " .. last_log .. " 2>&1")
end

local output = s:taboption("actions", TextValue, "_output", translate("运行结果"))
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
