---
title: 解决 UFI003 板上外置 SIM 卡无法启用的问题
articles:
   excerpt_type: html
---

# 解决 UFI003 板上外置 SIM 卡无法启用的问题

OpenStick 项目的给410 WIFI 板子适配的 Linux 内核可以在 UFI003_MB_V02 的主板上启动，但Modem 工作不正常，，插入自己的SIM卡，使用 `mmcli -m 0` 查看 Modem 状态时，会发现 `sim-missing` 的异常：

```
Status   |             state: failed
         |     failed reason: sim-missing
         |    signal quality: 0% (cached)
```
<!--more-->

这个问题不是只有我一个人遇到，在 Openstick项目的 Issue 中也被提到：

[https://github.com/OpenStick/OpenStick/issues/33#issuecomment-1430420841](https://github.com/OpenStick/OpenStick/issues/33#issuecomment-1430420841)

[https://github.com/OpenStick/OpenStick/issues/20#issuecomment-1235861433](https://github.com/OpenStick/OpenStick/issues/20#issuecomment-1235861433)

这个问题是 dtb 设备树错误配置引入的，这个 patch 修复了这个问题：

[[PATCH] arm64: dts: qcom: msm8916-ufi: Fix sim card selection pinctrl - Yang Xiwen (kernel.org)](https://lore.kernel.org/all/tencent_7036BCA256055D05F8C49D86DF7F0E2D1A05@qq.com/)

这个patch 默认将 sim-sel-pins 设置为 high，于是内核会默认启动外置 SIM 卡

![Untitled](/images/%E8%A7%A3%E5%86%B3%20UFI003%20%E6%9D%BF%E4%B8%8A%E5%A4%96%E7%BD%AE%20SIM%20%E5%8D%A1%E6%97%A0%E6%B3%95%E5%90%AF%E7%94%A8%E7%9A%84%E9%97%AE%E9%A2%98%20cf7443bd5c0c49edbd45113b8116146e/Untitled.png)

这个patch 已经合并进主线内核，可以选择社区维护的高通 410 内核分叉（也叫 MSM8916），源码地址：

[https://github.com/msm8916-mainline/linux](https://github.com/msm8916-mainline/linux)

这个内核树同样也支持 Qualcomm MSM8909/MSM8939 相关平台。

所以你要做的就是重新编译一份主线内核就行。
