---
title: RockChip 安全启动的一点猜想
articles:
   excerpt_type: html
---

## **bootROM**

所有支持 Secure Boot 的 CPU 都会有一个写死在 CPU 中的 bootROM 程序。CPU 在通电之后执行的第一条指令就在 bootROM 的入口。bootROM 拥有最高的执行权限，也就是 EL3。它将初始化 Secure Boot 安全机制，加载 Secure Boot Key 等密钥、从 eMMC 加载并验证 First Stage Bootloader（FSBL），最后跳转进 FSBL 中。

bootROM 是完全只读的，这个在 CPU 出厂时就被写死了，连 OEM 都无法更改。bootROM 通常会被映射到它专属的一块内存地址中，但是如果你尝试向这块地址写入内容，一般都会出错或者没有任何效果。

有些芯片还会有一个专门的寄存器控制 bootROM 的可见性，bootROM 可以通过这个寄存器禁止别的程序读取它的代码，以阻止攻击者通过逆向 bootROM 寻找漏洞。

<!--more-->
## **eFUSE**

一块很小的一次性编程储存模块，我们称之为 FUSE 或者 eFUSE，因为它的工作原理跟现实中的保险丝类似：CPU 在出厂后，这块 eFUSE 空间内所有的比特都是 1，如果向一个比特烧写 0，就会彻底烧死这个比特，再也无法改变它的值，也就是再也回不去 1 了。rk3399 使用的在efuse 里存储了Public Key 的 Hash 值。

## **First Stage Bootloader（FSBL）**

FSBL 的作用是初始化 PCB 板上的其他硬件设备，给外部 RAM 映射内存空间，从 eMMC 的 GPT 分区上加载验证并执行接下来的启动程序。

## **根信任的建立**

CPU 通电后执行的第一行指令就是 bootROM 的入口，bootROM 将初始化各种 CPU 内部的模块，但最主要的是，它会读取 eFUSE 上的内容，首先它会判断当前的运行模式是不是生产模式，是的话会开启 Secure Boot 功能，然后把 Secure Boot Key 加载到一个 Security Engine 的 Keyslot 当中，有时候它还会通过 Key Derivation 从 Secure Boot Key 或别的 eFUSE 内容生成多几个不同用途的密钥，分别加载到不同的 Keyslots 中。然后它会从 eMMC 上加载 FSBL，FSBL 里面会有一个数字签名和公钥证书，bootROM 会验证这个签名的合法性，以及根证书的 Hash 是否和 eFUSE 中的 Signing Key 的 Hash 相同。如果验证通过，说明 FSBL 的的确确是 OEM 正式发布的，没有受到过篡改。于是 bootROM 就会跳转到 FSBL 执行接下来的启动程序。有些 CPU 在跳转之前会把 bootROM 的内存区间设为不可见，防止 FSBL 去读取 bootROM。有些 CPU 还会禁止 eFUSE 的读写，或者至少 Secure Boot Key 区域的读取权限，来防止 FSBL 泄漏根信任的解密密钥。还有要注意的是，FSBL 是被加载到了 iRAM 上执行的，而且 FSBL 仍然拥有 EL3 级别的权限。

FSBL 会进一步初始化 PCB 板上的别的硬件，比如外部的 RAM 芯片等等，使其不再受限于 iRAM 的内存空间。然后它会进一步加载 eMMC 上的内容到 RAM。我们接下来会着重讲讲跟 Secure Boot 密切相关的启动内容。

# 猜想 RK 3399 的 Security Boot机制

长话短说，要做到安全启动，那么就必须做到两点

- 固件安全性验证
- 固件完整性验证
1. 安全性校验是加密公钥的校验，流程为CPU上电后从安全存储（OTP&efuse）中读取公钥 hash，与计算的公钥 hash对比，是否一致，然后解密固件 hash。
2. 完整性校验为校验固件的完整性，流程为从存储里加载固件，计算固件的 hash 是否与解密出来的 hash 一致。

Android上的 AVB 和 DM-V 不在讨论范围内，这里只讨论CPU上电后到 Uboot 的验证流程。

## 启动流程

首先搞清楚 RK 的启动流程

`BootRom ->  Maskrom ‐> Loader ‐> Trust ‐> U‐Boot ‐> kernel ‐> Android`

个人理解 对应的 BL X 阶段

BootRom ，Maskrom（BL1）
Loader（BL2）：

Trust（BL31：ARM Trusted Firmware和 OP-TEE）

U-Boot（BL33）

## 首先 OEM 做了什么

1. OEM生成私钥→私钥生成公钥→ 计算公钥 hash 值 →将公钥 hash 写入 efuse
2. OEM 使用 私钥签名自己的固件包，如 **loader/trust/uboot 等**

## Maskroot 刷机模式下

1. Public Key Hash 储存在在芯片的 OTP(eFuse)上，CPU 上电后 RootRom 读取的 eFUSE 内部的公钥 hash，
2. 当使用组合键尝试进入Maskroom，引发中断，BootRom 进入 Maskroom 下
3. Maskroom 先使用 OTP(eFuse) 中的 Hash 校验固件的 Public Key，如果校验失败那么抱歉禁止刷机。
4. Public Key 解密固件内的数字签名，得到固件各个分区的的 hash，然后 Maskroom 计算  loader/trust/uboot  的 hash，与数字签名的 hash 对比看是否一致，如果一致那就说明 loader/trust/uboot 都是 OEM 的，如果校验不过，那么抱歉禁止刷机。

也就是说 Rk 的security boot 能保证固件的安全性到 uboot 为止，至于uboot 如何安全引导 Kernel 那就是另外一回事了，比如内核与文件系统的 AVB，DM-V 安全机制。

根据公开资料显示，rk3399 用的是 eFUSE 存储区域，而 RK3308 / RK3326 / PX30 / RK3328 这些用的是 OPT 存储区域。所以 eFUSE 是在Soc 内部吗？如果是外部的话那么直接拆掉eFUSE 不久行了，所以eFUSE 应该是在 SoC 内部，这就是为啥B站上的垃圾佬捡到某些开启 Security Boot 的板子直接把 RK3399 SoC 拿下来换新的 Soc 上去，因为eFUSE 在 SoC 内部。

