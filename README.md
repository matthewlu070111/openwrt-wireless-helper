# openwrt-wireless-helper

`openwrt-wireless-helper` 是一个用于 OpenWrt 的无线设备辅助管理 LuCI 插件，用于解决 USB 无线网卡路径漂移后反复新增 `wifi-device`，以及网卡在 netifd 中变为 `unknown` / `down`、客户端已关联但信号和速率遥测丢失后无法自动恢复的问题。

常见现象类似这样：

```uci
config wifi-device 'radioX'
	option path 'platform/ff5c0000.usb/usbX/X-1/X-1:1.0'
```

其中 `X` 会在 `3`、`4`、`5` 等编号之间变化，导致 OpenWrt 不断生成新的 `radioX` 配置。

## 为什么不是 luci-app-wireless-helper

仓库名和软件包名统一为 `openwrt-wireless-helper`。

`luci-app-*` 只是 OpenWrt LuCI 插件常见的命名习惯，不是必须使用的名字。这个项目的定位不只是一个页面，而是包含 LuCI 页面、后台清理脚本、启动脚本和 USB hotplug 逻辑，所以使用与仓库一致的 `openwrt-wireless-helper` 更清楚。

## 工作方式

OpenWrt/netifd 的 `option path` 需要指向真实存在的 sysfs 设备路径，不能简单写成通配符。因此本项目会把以下路径归一为同一组：

```text
platform/ff5c0000.usb/usbX/X-1/X-1:1.0
```

发现重复项后，保留目标按以下优先级决定：

1. 用户在 LuCI 中选择的默认 radio
2. 自动检测到正在工作的 radio
3. 当前 sysfs 路径真实存在的 radio
4. 同组中的第一个 radio

如果用户固定选择保留 `radio3`，但当前实际存在的是新生成的 `radio4`，清理时会先把 `radio4` 的真实 `path` 写回 `radio3`，再把 `wifi-iface` 迁移到 `radio3`，最后删除重复的 `radio4`。

## 正在工作的 radio 如何判断

radio 会在满足以下条件时标记为正在工作：

- `option path` 对应的 `/sys/devices/...` 路径存在
- radio 没有被禁用
- 至少有一个启用的 `wifi-iface` 引用它

状态输出中还会显示从 `/sys/devices/.../ieee80211` 检测到的 `phy*` 名称。

## LuCI 使用

安装后进入：

```text
服务 -> 无线助手
```

页面功能：

- `默认保留的 radio`：选择重复项清理后应关联到哪个 `radioX`
- `扫描`：显示当前匹配的 USB Wi-Fi radio、是否新增、是否正在工作
- `预览清理`：只显示将要执行的清理计划，不修改配置
- `清理重复项`：执行迁移和清理
- `记住当前 radio`：把当前 radio 记录为基线，之后新冒出来的 radio 会显示为新增
- `自动清理`：在系统启动和 USB 热插拔后自动执行清理
- `健康监控`：同时检查 sysfs 路径、`phy`、netifd 状态，以及 Client 接口的 BSSID、信号和速率
- `自动恢复`：连续达到设定失败次数后，重置异常 radio 或重启 `network` 服务
- `立即恢复`：无需等待阈值，手动执行当前恢复策略
- `DNS 接管`：将 dnsmasq 的默认上游固定到 Clash/Mihomo DNS，并让路由器本机也通过 dnsmasq 解析
- `DNS 配置同步`：监控被系统或其他插件改回的 dnsmasq 配置，在上游端口存在时自动重新接管
- `DNS 恢复`：首次接管前会备份原来的上游、`noresolv`、`resolvfile`、`localuse` 和缓存设置，可一键恢复

第一次使用建议先点击 `扫描`，确认信息正常后点击 `记住当前 radio`。之后再选择默认保留的 radio，并使用 `预览清理` 检查计划。

## 命令行使用

```sh
/usr/libexec/wireless-helper status
/usr/libexec/wireless-helper list-radios
/usr/libexec/wireless-helper dry-run
/usr/libexec/wireless-helper clean
/usr/libexec/wireless-helper remember
/usr/libexec/wireless-helper health
/usr/libexec/wireless-helper recover
/usr/libexec/wireless-helper dns-status
/usr/libexec/wireless-helper dns-apply
/usr/libexec/wireless-helper dns-restore
```

## UCI 配置

默认配置文件：

```text
/etc/config/wireless_helper
```

示例：

```sh
uci set wireless_helper.settings.path_prefix='platform/ff5c0000.usb'
uci set wireless_helper.settings.preferred_radio='radio3'
uci set wireless_helper.settings.enabled='1'
uci set wireless_helper.settings.auto_recover='1'
uci set wireless_helper.settings.check_interval='60'
uci set wireless_helper.settings.failure_threshold='3'
uci set wireless_helper.settings.recovery_action='wifi_reload'
uci set wireless_helper.settings.recovery_settle_time='30'
uci set wireless_helper.settings.dns_takeover='1'
uci set wireless_helper.settings.dns_upstream='auto'
uci commit wireless_helper
/etc/init.d/wireless_helper enable
/etc/init.d/wireless_helper restart
```

`recovery_action` 可设为 `wifi_reload`（仅重置异常 radio）或 `network_restart`（关闭接口后直接请求 procd 重启 netifd，会短暂断开 LAN/WAN）。后一种方式不会调用部分第三方固件中可能因 `procd.sh` 兼容问题而失败的 `/etc/init.d/network restart`。恢复后会在 `recovery_settle_time` 内反复检查目标 radio，只有链路真正恢复才记录为成功。自动恢复默认关闭，建议先在 LuCI 中使用“健康检查”确认状态识别正常后再开启。

对于 Client/STA 接口，健康检查会读取与 LuCI 无线概览相同的 `iwinfo` 数据。未关联，或已经有 BSSID 但信号/速率为空（显示为 `— dBm`、`? Mbit/s`）时会判定为异常；AP 接口不做这项检查。监控仍需连续达到 `failure_threshold` 次才会执行恢复，避免把正常的短暂重连当成故障。

`dns_upstream=auto` 会优先读取 `openclash.config.dns_port`，默认回退到 `127.0.0.1#7874`。接管时会设置 dnsmasq `noresolv=1`、`localuse=1`、`cachesize=0`，并删除 `resolvfile`；默认保留 `/domain/server` 格式的内网域名专用转发。如果 Clash/Mihomo DNS 端口没有监听，脚本不会修改 dnsmasq，以免导致全网 DNS 中断。

> Fake-IP 模式下，域名解析为 `198.18.0.0/16` 是正常现象。解析正常但路由器本机 `ping` 不通时，还需要在 Clash/OpenClash 中开启“代理路由器本机流量”；DNS 接管本身不会替代 OUTPUT/TUN 流量接管。

如果希望清理后立即重载 Wi-Fi：

```sh
uci set wireless_helper.settings.reload_wifi='1'
uci commit wireless_helper
```

## 构建

把本仓库放到 OpenWrt SDK 或 buildroot 的 `package/openwrt-wireless-helper` 目录后执行：

```sh
make menuconfig
make package/openwrt-wireless-helper/compile V=s
```

GitHub Actions 也会自动使用 OpenWrt SDK 构建安装包，并把产物上传到 workflow artifact。

默认构建目标：

- `ipk`：OpenWrt 23.05.x / 24.10.x 等 opkg 系列
- `apk`：OpenWrt 25.12.x 及更新的 apk 系列
