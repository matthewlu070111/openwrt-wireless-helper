# luci-app-wireless-helper

LuCI helper for OpenWrt systems where a USB wireless adapter is repeatedly
rediscovered as new `wifi-device` sections such as `radio3`, `radio4`, and
`radio5`.

The specific failure this targets looks like this:

```uci
config wifi-device 'radioX'
	option path 'platform/ff5c0000.usb/usbX/X-1/X-1:1.0'
```

where `X` drifts between values like `3`, `4`, and `5`.

## How it works

OpenWrt/netifd expects `option path` to point at a real sysfs device, so writing
a wildcard path is not a reliable fix. This package instead groups matching USB
paths by a normalized key:

```text
platform/ff5c0000.usb/usbX/X-1/X-1:1.0
```

When duplicates are found, it chooses the radio to keep in this order:

- the user-selected default radio in LuCI
- the detected active radio
- the currently present sysfs path
- the first matching radio section

Then it migrates any `wifi-iface` sections that still reference the old radio
and deletes the stale duplicate `wifi-device` section.

The active-radio check is intentionally conservative: a radio is marked active
when its sysfs path exists, the radio is not disabled, and at least one enabled
`wifi-iface` references it. The status output also shows detected `phy*` names
from `/sys/devices/.../ieee80211`.

## LuCI

After installing, open:

```text
Network -> Wireless Helper
```

Available actions:

- `Scan`: show matching USB Wi-Fi radios and duplicate groups.
- `Preview cleanup`: show what would be removed.
- `Clean duplicates`: apply the cleanup.
- `Remember current radios`: store the current radios as the known baseline.

The `Default radio to keep` setting lets the user choose which `radioX` should
be kept when duplicates are cleaned. Leave it on auto to prefer the detected
active radio.

Automatic cleanup can also be enabled from the LuCI page. When enabled, the
helper runs during boot and USB hotplug events.

## Command line

```sh
/usr/libexec/wireless-helper status
/usr/libexec/wireless-helper list-radios
/usr/libexec/wireless-helper dry-run
/usr/libexec/wireless-helper clean
/usr/libexec/wireless-helper remember
```

The default path prefix is:

```text
platform/ff5c0000.usb
```

You can change it in LuCI or with UCI:

```sh
uci set wireless_helper.settings.path_prefix='platform/ff5c0000.usb'
uci set wireless_helper.settings.preferred_radio='radio3'
uci set wireless_helper.settings.enabled='1'
uci commit wireless_helper
/etc/init.d/wireless_helper enable
```

If you want the helper to reload Wi-Fi after cleanup:

```sh
uci set wireless_helper.settings.reload_wifi='1'
uci commit wireless_helper
```
