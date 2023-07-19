---
title: ARMv8-A 可信固件乱谈
articles:
   excerpt_type: html
---


> 全部都是个人理解，非常个人的理解，非常不建议阅读，建议立即关闭此页面
>

# ARM TrustZone 是什么

TrustZone 技术与 Cortex-A 处理器紧密集成，并通过 AMBA-AXI 总线和特定的 TrustZone 系统 IP
块在系统中进行扩展。此系统方法意味着可以保护安全内存、加密块、键盘和屏幕等外设，从而可确保它们免遭软件攻击。

<!--more-->
# 了解 Exception Levels 0-3 和 Security state

ARMv8 的异常级别分为 EL0-EL3，EL0 权限最低，EL3 权限最高。通常情况下的 EL0-EL3 模型：

**EL3：**用户态APP

**EL2：**特权级内核及相关函数。

**EL1：**提供对处理器虚拟化的支持。

**EL0：**Secure monitor. CPU内的 BootRom代码

在 Cortex-A53 者更高版本的的处理器上，EL0-3 还支持各自的 Secure state。

那什么是 **Security state ？**

两种状态Secure 和Non-secure 对应的是 Trusted world 和 **Non-trusted world，**从高层次看，Trusted world和 Non-trusted world 把一个物理处理器分成了两个虚拟处理器核心，两个 world 之间代码行和数据是隔离的，并通过NS位来控制 Non-trusted world 和Trusted world 的地址空间访问，NS 为 0，表示进入Secure status，NS 为 1 表示 Non-secure

在Secure 和Non-secure视角下的物理内存分布：

![Untitled](/images/ARMv8-A%20%E5%8F%AF%E4%BF%A1%E5%9B%BA%E4%BB%B6%E4%B9%B1%E8%B0%88%2022e5ca90650944cd83fac3b294bee11a/Untitled.png)

跑在 Secure state 下的代码可以访问其所在异常级别和更高级别的所以资源，跑在 Non-secure 下的代码就受限了，可以访问其所在异常级别和更高级别的 Non-secure 资源，但不能访问 Secure state 下控制的资源。比如跑在  Secure state EL 3 下的代码可以访问整个系统的资源，这类的代码一般是芯片厂商固化在CPU内的 Boot Rom 第一段引导程序，当 CPU 上电时，Boot Rom 用于初始化主板板CPU和内存。

**在 AARCH64 中，EL3 只存在在 Secure state 之下，AARCH32 模式下，EL3 存在在 Secure state和Non-Secure state。**

![Untitled](/images/ARMv8-A%20%E5%8F%AF%E4%BF%A1%E5%9B%BA%E4%BB%B6%E4%B9%B1%E8%B0%88%2022e5ca90650944cd83fac3b294bee11a/Untitled%201.png)

好了点到为止。

# BL 1

AARCH64 的启动基本分为 `Bootrom -> BL1 -> BL2 -> (BL31/BL32/BL33)` 这几个阶段。

通常情况下，CPU上电后运行的 Boot Rom 代码我们说他们是可信的，运行在 EL3 ，上电运行Boot Rom 的阶段在 BL1，这里有个例子就是我的 S905X3 的 EMMC 被我吹风机吹坏，不插 SDCARD和 U盘的情况，板子上电后在串口反复打印：

```bash
SM1:BL:511f6b:81ca2f;FEAT:A0F83180:20282000;POC:F;RCY:0;EMMC:0;READ:E;READ:800;READ:800;SD?:0;SD:0;READ:0;0.0;C;
```

因为 EMMC 和 SRCARD 都插盒子，CPU 上电后芯片内部的 Boot Rom 内的代码找不到任何引导，就反复尝试且反复报错。

在 arm-trusted-firmware 的  [arm-trusted-firmware/bl1_main.c at master · ARM-software/arm-trusted-firmware (github.com)](https://github.com/ARM-software/arm-trusted-firmware/blob/master/bl1/bl1_main.c) 内的 bl1_main 函数内定义了 CPU BootRom 上电后的 BL1 逻辑。

```bash
# Sourcegraph 语法，直接粘贴到 Sourcegraph 定位代码
repo:^github\.com/ARM-software/arm-trusted-firmware$@6264643 file:^bl1/bl1_main\.c
```

主要干了三件事：

1. 架构初始化
    1. 判断cold reset还是warm reset
    2. 建立简单的 exception vectors
    3. 1. CPU初始化，参考函数`reset_hardler`
    4. 1. 配置控制寄存器，`SCTLR_EL3`、`SCR_EL3`、`CPTR_EL3`、`DAIF`、`MDCR_EL3`等等
2. 平台初始化
3. 通过 `bl1_load_bl2()` 加载 BL2

所以 BL1 是开源的咯，**其实基本上 Soc 芯片厂商的 BL1 都是闭源的**，可以理解为 [arm-trusted-firmware/bl1_main.c](https://github.com/ARM-software/arm-trusted-firmware/blob/master/bl1/bl1_main.c) 只是一个参考，真正的 BL1 实现是 Soc 厂商内部的机密。然后你再去意会下  [arm-trusted-firmware](https://github.com/ARM-software/arm-trusted-firmware/blob/master/bl1/bl1_main.c) 的 README 中的 reference implementation

![Untitled](/images/ARMv8-A%20%E5%8F%AF%E4%BF%A1%E5%9B%BA%E4%BB%B6%E4%B9%B1%E8%B0%88%2022e5ca90650944cd83fac3b294bee11a/Untitled%202.png)

你 get 到了我的意思了吗，**第一阶段的引导代码 BL1 是专有的**，BL1 的控制权在厂商而不是在用户，放眼今朝，如果你真的想要对硬件做到完全的控制，每一处细节每一处代码，完全的 OpenSource，那么对不起，基本做不到，也基本不可能。

举个例子，虽然 uboot 对 Amlogic s905x3 Soc 的支持程序相当好了，但 uboot 仍然需要一堆专有的 binaries 来初始化硬件，如这些：

![Untitled](/images/ARMv8-A%20%E5%8F%AF%E4%BF%A1%E5%9B%BA%E4%BB%B6%E4%B9%B1%E8%B0%88%2022e5ca90650944cd83fac3b294bee11a/Untitled%203.png)

Amlogic 提供二进制文件的许可证在历史上并不明确，但现在已经澄清。 当前的 Amlogic 分发许可证如下：

```bash
// Copyright (C) 2018 Amlogic, Inc. All rights reserved.
//
// All information contained herein is Amlogic confidential.
//
// This software is provided to you pursuant to Software License
// Agreement (SLA) with Amlogic Inc ("Amlogic"). This software may be
// used only in accordance with the terms of this agreement.
//
// Redistribution and use in source and binary forms, with or without
// modification is strictly prohibited without prior written permission
// from Amlogic.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

这些专有的 binaries 可在在 `[https://github.com/LibreELEC/amlogic-boot-fip](https://github.com/LibreELEC/amlogic-boot-fip)` 被找到。然后使用  `./build-fip.sh` 来构建实际可用的 u-boot.bin 。

我手上有块 rk3399 eaidk 610 的板子，假设固件没有被人为修改，那么

- BL1 对应 RK 的 Maskrom，周所周知 Maskrom 是闭源的
- BL2 对应 RK 的 Miniloader，Miniloader 也是闭源的
- BL3-1 对应 PSCI、Secure Monitor 功能支持的固件
- BL3-2 和 BL3-3 对应 RK的 Uboot

Rockchip 的 BL1/BL2 都是闭源的，其实也可以理解。RK 只使用了 ARM-Trust-Firmware 的 BL31 代码。这就是为什么构建 U-boot的时候需要 bl31.elf 的原因。

# BL3 干了什么

BL3 由 BL2 加载，BL1 将控制权传递给 EL3 处的 BL3-1。 BL3-1 仅在受信任的 SRAM 中执行。

BL3-1 链接并加载到特定于平台的基地址。 BL3-1 实现的功能：

## 架构初始化

BL3-1 执行与 BL1 类似的架构初始化。 由于 BL1 代码驻留在 ROM 中，因此 BL3-1 中的体系结构初始化允许覆盖 BL1 之前完成的任何初始化。 BL3-1 创建页表来寻址前 4GB 的物理地址空间，并相应地初始化 MMU。 它用自己的替换了 BL1 填充的异常向量。 如果引发意外异常，BL3-1 异常向量会以与 BL1 相同的方式指示错误条件。 他们为处理 SMC 实现了更精细的支持，因为这是访问 BL3-1（例如 PSCI）实现的运行时服务的唯一机制。 在将控制传递给所需的 SMC 处理程序之前，BL3-1 检查每个 SMC 的有效性，如 SMC 调用约定 PDD 所指定的那样。 BL3-1 使用平台提供的系统计数器的时钟频率对 CNTFRQ_EL0 寄存器进行编程。

## 平台初始化

BL3-1 执行详细的平台初始化，使正常世界的软件能够正常运行。 它还从 BL2 填充的平台定义内存地址检索 BL2 加载的 BL3-3 图像的入口点信息。 BL3-1 还初始化 UART0（PL011 控制台），它可以访问 BL3-1 中的 printf 函数系列。 它通过内存映射接口启用通用定时器的系统级实现。

## GICv2初始化：

建议 Google

## 电源管理初始化：

BL3-1 实现了一个状态机来跟踪 CPU 和集群状态。 状态可以是 OFF、ON_PENDING、SUSPEND 或 ON 之一。 所有辅助 CPU 最初都处于关闭状态。 主CPU所属集群ON； 任何其他集群都关闭。 BL3-1 初始化实现状态机的数据结构，包括保护它们的锁。 BL3-1 在复位后和在热启动路径中启用 MMU 之前立即访问 CPU 或集群的状态。 目前不可能使用基于“独占”的自旋锁，因此 BL3-1 使用基于 Lamport 的 Bakery 算法的锁。 BL3-1 在设备内存中分配这些锁。 无论 MMU 状态如何，它们都是可访问的。

## 运行时服务初始化：

建议  Google

# 怎么触发 BL31-Kernel 层的交互

No Secure OS（Linux）和 Secure OS,如果需要同 BL31 进行交互，可以通过两种
方法：
方法 1：通过显示的调用 SMC 指令，主动申请陷入 BL31.
方法 2：将中断配置为需要在 EL3 中处理，这个功能主要针对安全的中断，系统
运行在 Linux Kernel 时，系统会先进入 BL31，然后在 BL31 中切换到
Secure OS 中进行处理。

~~BL3，BL3 又分为 BL31，BL32，BL33。我第一次看见BL33的时候以为ARM处理器的BL阶段有33个阶段，可以说这个命名是非常随意了。~~

BL1-3的所有代码统称叫 `Application processor firmware。`
