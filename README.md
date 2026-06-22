# openwrt-wireless-helper

`openwrt-wireless-helper` 是一个用于 OpenWrt 的无线设备辅助管理 LuCI 插件，主要解决 USB 无线网卡路径漂移后反复新增 `wifi-device` 的问题。

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
网络 -> 无线助手
```

页面功能：

- `默认保留的 radio`：选择重复项清理后应关联到哪个 `radioX`
- `扫描`：显示当前匹配的 USB Wi-Fi radio、是否新增、是否正在工作
- `预览清理`：只显示将要执行的清理计划，不修改配置
- `清理重复项`：执行迁移和清理
- `记住当前 radio`：把当前 radio 记录为基线，之后新冒出来的 radio 会显示为新增
- `自动清理`：在系统启动和 USB 热插拔后自动执行清理

第一次使用建议先点击 `扫描`，确认信息正常后点击 `记住当前 radio`。之后再选择默认保留的 radio，并使用 `预览清理` 检查计划。

## 命令行使用

```sh
/usr/libexec/wireless-helper status
/usr/libexec/wireless-helper list-radios
/usr/libexec/wireless-helper dry-run
/usr/libexec/wireless-helper clean
/usr/libexec/wireless-helper remember
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
uci commit wireless_helper
/etc/init.d/wireless_helper enable
```

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
