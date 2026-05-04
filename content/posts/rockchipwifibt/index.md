---
title: "Rockchip Wi-Fi/BT 调试笔记"
summary: "记录 Rockchip 平台 Wi-Fi/BT 模组、设备树、内核配置、wpa_supplicant 和蓝牙测试的调试要点。"
description: "记录 Rockchip 平台 Wi-Fi/BT 模组、设备树、内核配置、wpa_supplicant 和蓝牙测试的调试要点。"
date: 2023-06-15
draft: false
categories:
  - "embedded"
tags:
  - "rockchip"
  - "wifi"
  - "bluetooth"
---
`WL_ROCKCHIP` 下的 Realtek 模组和 AP6xxx 模组不能同时选择为 `y`，AP6xxx 和 Cypress 也是互斥的。至于 out-of-tree 模块则没有这个限制，可以在 Buildroot 中直接修改 Makefile。

<!--more-->

## DTSI

```dts
sdio_pwrseq: sdio-pwrseq {
compatible = "mmc-pwrseq-simple";
pinctrl-names = "default";
pinctrl-0 = <&wifi_enable_h>;
reset-gpios = <&gpio0 RK_PA2 GPIO_ACTIVE_LOW>; //有个注意要点是：这里的电平状态恰好跟使能状态相反，比如 REG_ON高有效，则这里为 LOW；如果 REG_ON低有效，则填 HIGH
};
&pinctrl {
sdio-pwrseq {
wifi_enable_h: wifi-enable-h {
rockchip,pins =
<0 RK_PA2 RK_FUNC_GPIO &pcfg_pull_none>; //对应上面的 WIFI_REG_ON
};
};
};
&sdio {
bus-width = <4>;
… …
status = "okay";
};
WIFI_WAKE_HOST: WIFI 唤醒主控的 PIN 脚
wireless-wlan {
compatible = "wlan-platdata";
rockchip,grf = <&grf>;
wifi_chip_type = "ap6255"; //海华/正基模组可以不用修改此名称，realtek需要按实际填写
WIFI,host_wake_irq = <&gpio0 RK_PA0 GPIO_ACTIVE_HIGH>; // WIFI_WAKE_HOST GPIO_ACTIVE_HIGH 特别注意：确认下这个 wifi pin脚跟主控的连接关系，直连的话就是 HIGH,如果中间加了一个反向管就要改成低电平 LOW触发
status = "okay";
};
```
## 内核配置

- `WL_ROCKCHIP`

RK 平台适配的 Wi-Fi/BT 相关目录大致是：

- Wi-Fi 驱动目录：`kernel/drivers/net/wireless/rockchip_w`
- BT 驱动和蓝牙 firmware 目录：`external/rkwifibt/`
- AP 模组 firmware：`external/rkwifibt/firmware/broadco`
- Realtek 模组目录：`external/rkwifibt/realte`
- 编译规则：`buildroot/package/rockchip/rkwifibt/rkwifi`
- 关键文件：`rkwifibt.mk`、`Config.in`

这两个文件主要完成 Wi-Fi 模组 firmware 的拷贝、对应模组蓝牙驱动和可执行文件的编译拷贝。

## 测试
```sh
wpa_cli -i wlan0 -p /var/run/wpa_supplicant scan
wpa_cli -i wlan0 -p /var/run/wpa_supplicant scan_result
// 正常情况下：-30 到-55，偏弱：-55 到-70，非常差-70 到-90
```

简略的 Wi-Fi 连接配置：

```conf
network={
ssid="WiFi-AP" // WiFi 名字
psk="12345678" // WiFi 密码
key_mgmt=WPA-PSK // 填加密方式
# key_mgmt=NONE // 如果 wifi 不加密
}

$ wpa_cli -i wlan0 -p /var/run/wpa_supplicant reconfigure
$ wpa_cli -i wlan0 -p /var/run/wpa_supplicant reconnect 
```

BT 测试：

```sh
echo 0 > /sys/class/rfkill/rfkill0/state //下电
sleep 2
echo 1 > /sys/class/rfkill/rfkill0/state //上电
sleep 2

insmod /usr/lib/modules/hci_uart.ko //realtek 模组需要加载特定驱动
rtk_hciattach -n -s 115200 /dev/ttyS4 rtk_h5
hciconfig hci0 up
```

wifibt 的 MAC 地址都是芯片内置的，如果需要自定义 MAC 地址，需要使用 RK 专用工具写到 flash 自定义的 vendor 分区：

```sh
读：vendor_storage -r "VENDOR_WIFI_MAC_ID"
vendor_storage -r "VENDOR_BT_MAC_ID"
写：vendor_storage -w "VENDOR_WIFI_MAC_ID B4021192D25C"
vendor_storage -w "VENDOR_BT_MAC_ID B4021192D25D"
```
