---
title: 你家的光猫，你能怎么办？（二）
articles:
   excerpt_type: html
---

拿到光猫的最终控制台后，接下来怎么办？是不是可以放一点私货进去？
<!--more-->

首先，光猫的 cpu 架构是mips32架构，这一点可以从 `cat /proc/cpuinfo` 这条命令验证。

```bash
#cat /proc/cpuinfo
system type             : EcoNet EN751221 SOC
machine                 : Unknown
processor               : 0
cpu model               : MIPS 34Kc V5.8
```

这里的 MIPS 34K 是 MIPS 的 MIPS32 处理器系列的成，似乎三大运营商配送的光猫都是 MIPS32 架构。

可以使用MIPS的编译器工具链，自己构建一些库和二进制上传到这台光猫中运行，二进制的源码结构越复杂，调用的外部依赖库越多，构建起来约复杂。你可以去网上寻找一些 MIPS 的交叉编译器工具链，分析代码层级，解决 `configure` 阶段所需的依赖库 , 解决代码内对平台架构所定义的 `# d`

`efind` 适配问题，当然一般人肯定不会这样做，这又不是刀耕火种的时代，没人会从0开始做这种吃力不讨好的事情。

所以当然是用 [buildroot](https://buildroot.org/)。

Buildroot 是一些列 Makefile，patch和 Scripts 的组合的框架，你可以使用这些 Makefile和 Patch构建你自己的嵌入式 Linux 文件系统，Buildroot 支持许多架构，自动化构建交叉编译工具链，再使用构建好的交叉编译器工具链构建你需要的库和二进制程序，将这些库和二进制程序打包生成一个最基础的嵌入式文件系统，Buildroot 还可以构建内核和 uboot 并生成可启动的镜像，比如我的 [RockPiN10](https://wiki.radxa.com/RockpiN10) 就被 Buildroot 支持…..

说一句闲话：我在邮件列表里看到 buildroot 支持 rockpin10 的时候就第一时间去尝试了一下使用 buildroot 构建一个 musl  为C库的最小 Linux 可启动镜像，使用的主线内核和 uboot，但在实测启动的时候内核会崩溃，原因是未知，所以也只是支持，至少主线 uboot 可以从 sdcard 引导内核了。开源社区就是这样，它能工作，但有时候它也不能。因为这不是产品，所有的东西都可以祝你一臂之力，但不能让你一键摩托变跑车。

# 使用 Buildroot 构建二进制和库文件

下载 buildroot 源码，这里我使用 github 上最新的代码库试水，祝我好运~

buildroot 配置和 Linux kernel 的配置界面不能说是相似，只能说是一模一样。但是要比 Linux kernel 的 menuconfig 要简单许多。

```bash
$ git clone git://git.busybox.net/buildroot --depth 1
$ cd buildroot
$ make menuconfig
```

TIPS：你可以使用键盘`/` 来查找单一配置路径，就像是在分页器里搜索字符串一样。

## 配置 Target options

首先判断当前内核为大端还是小段，这个很重要，不要瞎猜，否则电费白给。使用固件内的 ELF 文件头判断。

提取前 5 bytes 的数据：

```bash
#hexdump  -n 6 -C /bin/busybox
00000000  7f 45 4c 46 01 02                                 |.ELF..|
```

 前 4 bytes `7f 45 4c 46` 是固定的表示这是一个 ELF 文件，第 5 bytes 为 **01** 说明这个ELF 为 32 位，第 6 bytes ，为 **02** 表示这个ELF文件 为大端二进制。

使用 `make menuconfig` 进行对需要生成的目标系统和需要生成的交叉编译工具链进行基础配置。

架构选择 `MIPS (big endian)`，位置：

```bash
Prompt: MIPS (big endian)
Location:
-> Target options
-> Target Architecture (<choice> [=y])
```

根据光猫内的 `/proc/cpuinfo` ，我知道这台光猫处理器型号为 EcoNet EN751221 SOC，指令集架构(ISA)为： `mips1 mips2 mips32r1 mips32r2`

```bash
system type             : EcoNet EN751221 SOC
machine                 : Unknown
processor               : 0
cpu model               : MIPS 34Kc V5.8
MIPS            : 1195.21
wait instruction        : yes
microsecond timers      : yes
tlb_entries             : 32
extra interrupt vector  : yes
hardware watchpoint     : yes, count: 4, address/irw mask: [0x0ffc, 0x0ffc, 0x0ffb, 0x0ffb]
isa                     : mips1 mips2 mips32r1 mips32r2
ASEs implemented        : mips16 dsp mt
```

为了 GCC 编译器对二进制代码的优化，在配置buildroot 时，在 Target Architecture Variant 选择 `Generic MIPS32R2`。位置：

```bash
Prompt: Generic MIPS32R2
Location:
-> Target options
-> Target Architecture Variant (<choice> [=y])
```

**更新1/21/2023** **注意：在这之后我发现 `MIPS32R2` 指令集在某些老板子上不受支持，这些板子主要是跑裸机汇编，所以我还是选择了 `Generic MIPS32` 这样构建出来的二进制更加具有通用性。**

这里还要注意的一点是，为了保证二进制文件的通用性，我这里选择 **Use soft-float (NEW)**

因为如果 CPU上没有 FPU 单元的话，许多低端 CPU都把FPU单元给砍了，造成使用 `hardfloat`的二进制运行会出错。

## 配置 Toolchain

接下来是 交叉编译工具链的配置（Toolchain目录），底层 C 库比较重要，我个人推荐使用 musl 作为底层 C 库，musl 比 gnu c 库小太多，且提供一套标准的 POSIX 兼容的 C API。虽然 musl 在某些 API 上与 gun c库不兼容就是。好在但我提前知道我需要构建的二进制在 musl 之上是可以运行的。

话说实现一套C库是一个大工程~

Toolchain type 选择 `Buildroot toolchain`

选择 C 库为 **musl**（`Symbol: BR2_TOOLCHAIN_BUILDROOT_MUSL [=y]`）位置：

```bash
Prompt: musl
-> Toolchain
-> C library (<choice> [=y])
```

Kernel Headers 不太重要，我参考了 小米 ac2100 opwnwrt的内核版本，选择了 Linux 5.10.x

```bash
Prompt: Linux 5.10.x kernel headers
Location:
-> Toolchain
-> Kernel Headers (<choice> [=y])
```

交叉编译器 GCC 版本我选择了 gcc 11.x，会不会出错全看运气。我同时启用了 C++的支持。

我也选择了 `Build cross gdb for the host`，因为我需要在光猫上使用 gdb 远程调试里面的某些不可告人的 ELF 文件。

**更新1/8/2023** **注意：到最后交叉编译器的选择上，我回退了 gcc 10.x，我的代码引入了许多 gnu gcc9 的扩展，要过 gcc11 的语法检查许多地方就需要修改，算了算了…..**

## 配置 Build options

使用 `ccache` 把编译的中间产物缓存下来（Symbol: BR2_CCACHE [=y]），这样可以加速第二次编译。

位置：

```bash
Symbol: BR2_CCACHE [=y]
Prompt: Enable compiler cache
Location:
-> Build options
```

使用全静态编译使得二进制具有可移动性（`Symbol: BR2_SHARED_LIBS [=y]`），这样的好处是二进制程序丢到光猫里就可以运行，非常简洁。但如果选择静态编译，但很多复杂软件包不支持静态编译，比如 python 解释器就无法加载一些动态库，nmap 没有 lua 脚本支持等。

选择动态编译的好处是支持的软件包更多，复杂特性也被支持，但需要手动分析依赖，手动使用 musl 的 LD 加载器去链接动态库。

我选择的是静态编译，在光猫运行复杂程序也不太现实，能跑个 PHP 环境就谢天谢地了。

```bash
Symbol: BR2_SHARED_LIBS [=y]
Prompt: shared only
Location:
-> Build options
-> libraries (<choice> [=y])
```

我选择了`strip target binaries` 在二进制的安装阶段去除调试符号和无用信息，让生成的二进制文件更小。

```bash
Symbol: BR2_STRIP_strip [=y]
```

## 配置 busybox

### 扩展 Busybox 命令

我觉得配置好了 busybox 后面会给你**节省大量时间**，因为后期我们所有的命令都由这个 busybox 提供支持，光猫内自带的 busybox 阉割太多了，要啥没啥属于是。

在 buildroot 源码目录下，运行 `make busybox-menuconfig`

这里推荐几个配置：

```bash
# bbconfig 可以打印编译时的配置
CONFIG_BBCONFIG=y
# 给 busybox 添加 ftpd 支持
CONFIG_FTPD=y
CONFIG_FTPGET=y
CONFIG_FTPPUT=y
CONFIG_FEATURE_FTPD_WRITE=y
CONFIG_FEATURE_FTPD_AUTHENTICATION=y
# 给 wget 添加 ssl 支持，默认wget不支持ssl 链接
CONFIG_FEATURE_WGET_STATUSBAR=y
CONFIG_FEATURE_WGET_FTP=y
CONFIG_FEATURE_WGET_HTTPS=y
CONFIG_FEATURE_WGET_OPENSSL=y
# 添加 ubifs 支持，因为我的光猫的 Raw flash 使用 ubifs 进行读写
CONFIG_FEATURE_VOLUMEID_UBIFS=y
CONFIG_UBIATTACH=y                                                                                                                                                                                                                                                          CONFIG_UBIDETACH=y
CONFIG_UBIMKVOL=y                                                                                                                                                                                                                                                           CONFIG_UBIRMVOL=y                                                                                                                                                                                                                                                           CONFIG_UBIRSVOL=y                                                                                                                                                                                                                                                           CONFIG_UBIUPDATEVOL=y                                                                                                                                                                                                                                                       CONFIG_UBIRENAME=y
# bc 计算器支持，在编写shell脚本的时候进行浮点运算
CONFIG_BC=y
# 你可能也需要 nc 来调试端口
CONFIG_NC=y
# 你可能需要 traceroute 和 traceroute6 来进行路由跟踪
CONFIG_TRACEROUTE=y
CONFIG_TRACEROUTE6=y
CONFIG_FEATURE_TRACEROUTE_VERBOSE=y
# 添加 whois 命令
CONFIG_WHOIS=y
```

### 解决 busybox 处理 Unicode 的问题

busybox 有个问题就是 ls 中文目录会出现？代替中文字符的问题。但这不是一个 BUG，这只能说是一个 `Feature`。

在这段代码里可以看到 busybox 处理 Unicode 的逻辑，在 `unicode.c` 中：

```bash
12 #endif
  11     if (CONFIG_LAST_SUPPORTED_WCHAR && wc > CONFIG_LAST_SUPPORTED_WCHAR)
  10       goto subst;
   9     w = wcwidth(wc);
   8     if ((ENABLE_UNICODE_COMBINING_WCHARS && w < 0) /* non-printable wchar */
   7      || (!ENABLE_UNICODE_COMBINING_WCHARS && w <= 0)
   6      || (!ENABLE_UNICODE_WIDE_WCHARS && w > 1)
   5     ) {
   4  subst:
   3       wc = CONFIG_SUBST_WCHAR;
   2       w = 1;
   1     }
```

这段代码就是用 `CONFIG_SUBST_WCHAR`  来替换超出 `CONFIG_LAST_SUPPORTED_WCHAR`  的字符，默认情况下，`CONFIG_LAST_SUPPORTED_WCHAR` 的值为 767，远小于整个 Unicode字符集，`CONFIG_SUBST_WCHAR`  默认为 63 ，也就是 `？` 的值。这就能解释为什么 打印中文，目录名字被 ？ 替换的问题。

```bash
(63)  Character code to substitute unprintable characters with (NEW)
(767) Range of supported Unicode characters
```

 `CONFIG_LAST_SUPPORTED_WCHAR`   符号位置：

![Untitled](/images/%E4%BD%A0%E5%AE%B6%E7%9A%84%E5%85%89%E7%8C%AB%EF%BC%8C%E4%BD%A0%E8%83%BD%E6%80%8E%E4%B9%88%E5%8A%9E%EF%BC%9F%EF%BC%88%E4%BA%8C%EF%BC%89%20832ba99f0b8e441c908889060ae1c6a5/Untitled.png)

我猜busybox 的作者应该是觉得有些终端无法处理超出 767 之外的字符，导致终端行为异常，为了终端的安全性索性就把 值给缩小成了 0-767 。但现代终端模拟器都一般都能处理 Unicode 字符集了，所以可以把 `CONFIG_LAST_SUPPORTED_WCHAR`   这个配置直接调整成 0，打印几乎所有字符集，并且后果自负。

```bash
(0) Range of supported Unicode characters
```

**注意：打印多国语言的前提是你的系统上配置了完整的 locales 环境。**

单独编译 busybox 使用 `make busybox` 命令。

## 配置 Target packages

这里是需要构建的目标系统（需要运行在光猫上的）的二进制库和程序。Buildroot 提供了许多常见的二进制库和工具，如 wget，libssl，protobuf，甚至是运行环境如 php，python 等。这些软件将被构建打包成一个最小的 rootfs。 这里按需要选择就可以。

我需要 tcpdump 和 ttyd ，以及一个 php 运行环境。

依次如下：

![Untitled](/images/%E4%BD%A0%E5%AE%B6%E7%9A%84%E5%85%89%E7%8C%AB%EF%BC%8C%E4%BD%A0%E8%83%BD%E6%80%8E%E4%B9%88%E5%8A%9E%EF%BC%9F%EF%BC%88%E4%BA%8C%EF%BC%89%20832ba99f0b8e441c908889060ae1c6a5/Untitled%201.png)

![Untitled](/images/%E4%BD%A0%E5%AE%B6%E7%9A%84%E5%85%89%E7%8C%AB%EF%BC%8C%E4%BD%A0%E8%83%BD%E6%80%8E%E4%B9%88%E5%8A%9E%EF%BC%9F%EF%BC%88%E4%BA%8C%EF%BC%89%20832ba99f0b8e441c908889060ae1c6a5/Untitled%202.png)

![Untitled](/images/%E4%BD%A0%E5%AE%B6%E7%9A%84%E5%85%89%E7%8C%AB%EF%BC%8C%E4%BD%A0%E8%83%BD%E6%80%8E%E4%B9%88%E5%8A%9E%EF%BC%9F%EF%BC%88%E4%BA%8C%EF%BC%89%20832ba99f0b8e441c908889060ae1c6a5/Untitled%203.png)

## 开始构建 Toolchain 和 Rootfs

执行 `make  menuconfig` 然后编译，等到世界毁灭外星人入侵地球三次后再去看就编译好了。

## 在构建时期遇到的错误

## Grep，Findutil 使用Gnu扩展导致构建 busybox 失败

具体报错：

```bash
findutils/grep.c:180:2: error: unknown type name ‘RE_TRANSLATE_TYPE’
  180 |  RE_TRANSLATE_TYPE case_fold; /* RE_TRANSLATE_TYPE is [[un]signed] char* */
      |  ^~~~~~~~~~~~~~~~~
findutils/grep.c:238:22: error: field ‘matched_range’ has incomplete type
  238 |  struct re_registers matched_range;
      |                      ^~~~~~~~~~~~~
findutils/grep.c: In function ‘grep_file’:
findutils/grep.c:381:24: error: ‘struct re_pattern_buffer’ has no member named ‘translate’
  381 |      gl->compiled_regex.translate = case_fold; /* for -i */
      |                        ^
```

定位到 源文件，发现这里有个定义了 `ENABLE_EXTRA_COMPAT`，在编译时根据判断条件，使用了 GNU 标准C库扩展 `RE_TRANSLATE_TYPE`

![Untitled](/images/%E4%BD%A0%E5%AE%B6%E7%9A%84%E5%85%89%E7%8C%AB%EF%BC%8C%E4%BD%A0%E8%83%BD%E6%80%8E%E4%B9%88%E5%8A%9E%EF%BC%9F%EF%BC%88%E4%BA%8C%EF%BC%89%20832ba99f0b8e441c908889060ae1c6a5/Untitled%204.png)

咋会出现这种情况？使用 GNU C库的扩展在 musl c库上肯定根本编译不过啊。

在 busybox 代码库中搜索 `EXTRA_COMPAT`，发现是`CONFIG_EXTRA_COMPAT` 这个 CONFIG 符号导致busybox使用 GNU C库扩展，取消这个 CONFIG 就可以解决问题。

`CONFIG_EXTRA_COMPAT` 符号位置：

![Untitled](/images/%E4%BD%A0%E5%AE%B6%E7%9A%84%E5%85%89%E7%8C%AB%EF%BC%8C%E4%BD%A0%E8%83%BD%E6%80%8E%E4%B9%88%E5%8A%9E%EF%BC%9F%EF%BC%88%E4%BA%8C%EF%BC%89%20832ba99f0b8e441c908889060ae1c6a5/Untitled%205.png)

### 不是那么智能的依赖问题

在构建 e2fsprogs 的时候提示 `error: external blkid library not found`

啥玩意儿？

在 `buildroot/output/host/mips-buildroot-linux-musl/sysroot/*` 下没找到 libblkid.a 静态库。说明 buildroot 没有构建这个依赖库。

如果你熟悉 buildroot 的源码，你会发现在 buildroot 源码内，`buildroot/package/util-linux/Config.in` 构建 libblkid 的符号是 `BR2_PACKAGE_UTIL_LINUX_LIBBLKID`

![Untitled](/images/%E4%BD%A0%E5%AE%B6%E7%9A%84%E5%85%89%E7%8C%AB%EF%BC%8C%E4%BD%A0%E8%83%BD%E6%80%8E%E4%B9%88%E5%8A%9E%EF%BC%9F%EF%BC%88%E4%BA%8C%EF%BC%89%20832ba99f0b8e441c908889060ae1c6a5/Untitled%206.png)

`blkid library` 是 utils-linux 项目里的一个库，是 一个很常用的库，一部分 mount 的函数 和 blkid 的底层函数在 libblkid 中实现。可以参考 [Debian -- Details of package libblkid-dev in sid](https://packages.debian.org/sid/libblkid-dev)

而 `BR2_PACKAGE_UTIL_LINUX_LIBBLKID` 这个符号在 buildroot 生成的 `.config` 中被标记为了 `n`

笑死…

util-linux 这个包是被 buildroot 自动选上的，但 buildroot 只构建了部分 utils-linux 包中的静态二进制文件，而没有构建静态 libblkid 这个库，而静态链接 e2fsprogs 的时候又需要 libblkid 这个库。

去这里把 libblkid 选上，然后执行 `make utils-linux-dirclean & make utils-linux-rebuild。`

![Untitled](/images/%E4%BD%A0%E5%AE%B6%E7%9A%84%E5%85%89%E7%8C%AB%EF%BC%8C%E4%BD%A0%E8%83%BD%E6%80%8E%E4%B9%88%E5%8A%9E%EF%BC%9F%EF%BC%88%E4%BA%8C%EF%BC%89%20832ba99f0b8e441c908889060ae1c6a5/Untitled%207.png)

### 网络问题

如果你人在国内，你可能需要在编译之前设置代理环境变量：

```bash
export http_proxy=http://proxy_ip:port
export https_proxy=http://proxy_ip:port
export ftp_proxy=http://proxy_ip:port
```

你也可以在配置buildroot 的时候使用 [http://sources.buildroot.net](http://sources.buildroot.net/) 当作下载源。配置位置：

```bash
Symbol: BR2_PRIMARY_SITE [=http://sources.buildroot.net]
Prompt: Primary download site
Location:
-> Mirrors and Download locations
-> Build options
```

### libwebsocket 编译错误的情况

libwebsocket 编译失败，符号 `BR2_PACKAGE_LIBWEBSOCKETS`

```bash
In file included from ../include/libwebsockets.h:668,
                 from core/private-lib-core.h:140,
                 from plat/unix/unix-init.c:28:
../include/libwebsockets/lws-genhash.h:85:18: error: field ‘ctx’ has incomplete type
   85 |         HMAC_CTX ctx;
      |                  ^~~
make[3]: *** [lib/CMakeFiles/websockets_shared.dir/build.make:104: lib/CMakeFiles/websockets_shared.dir/plat/unix/unix-init.c.o] Error 1
make[3]: *** Waiting for unfinished jobs....
In file included from ../include/libwebsockets.h:668,
                 from core/private-lib-core.h:140,
                 from plat/unix/unix-misc.c:28:
../include/libwebsockets/lws-genhash.h:85:18: error: field ‘ctx’ has incomplete type
   85 |         HMAC_CTX ctx;
      |                  ^~~
```

我没选 libwebsocket 这个库，但我选择了 ttyd ，ttyd这个包依赖 libwebsocket ，buildroot给自动选上了 libwebsocket 。

![Untitled](/images/%E4%BD%A0%E5%AE%B6%E7%9A%84%E5%85%89%E7%8C%AB%EF%BC%8C%E4%BD%A0%E8%83%BD%E6%80%8E%E4%B9%88%E5%8A%9E%EF%BC%9F%EF%BC%88%E4%BA%8C%EF%BC%89%20832ba99f0b8e441c908889060ae1c6a5/Untitled%208.png)

ttyd 不要也罢 busybox 里自带只是行为不一样而已。

要解决这个问题，顺着路径依赖取消 ttyd ，然后取消 libwebsocket 。

话说我就选了 tcpdump 和 ttyd 这俩软件包，保持系统最小原则，竟然这么不走运遇到编译失败的错误。

# 是时候跑起来你的二进制文件了

1. 理论上是可以 构建 zerotier-one 的，试试看。**（不用试了，出错，调不好，弃坑）**
2. 理论上是可以构建一个 nmap 把光猫变成一个扫描器 **（可以，但缺少 nmap script 支持，只能扫描端，速度挺快）**
3. 理论上 光猫有ipv6地址是可以用作BT 下载，理论上emmc空间不够可以移植sshfs 来挂载远端硬盘**（不用试了，光猫内核没有 fuse 支持）**
4. 理论上，是可以修改 rcS 文件来实现自启动的 **（不用试了，rcS所在的分区是只读的，只能 dump出来重新写，算了我怕搞坏光猫）**
5. 理论上是可以运行 ssh 实例的，比如 dropbear和openssh **（可以）**
6. 理论是理论实际上是怎么样的做了才知道啊：）
7. 理论上我到这里就弃坑了

# 最后自言自语

编译一次 buildroot 花了8小时，我本以为最多2小时搞定。可能是我编译的机器实在是太老了，但也不该这么慢啊 Orz，这 TM一定有问题。

这台机器是我滑板的时候摔坏的 Dell 笔记本，最后被我改造成了无头骑士挂墙上。到目前为止，它已经陪了我 6 年了。

配置如下：

内核：

`Linux ihexon-inspiron157579 5.15.85-1-MANJARO #1 SMP PREEMPT Wed Dec 21 21:15:06 UTC 2022 x86_64 GNU/Linux`

处理器：

```bash
Architecture:            x86_64
  CPU op-mode(s):        32-bit, 64-bit
  Address sizes:         39 bits physical, 48 bits virtual
  Byte Order:            Little Endian
CPU(s):                  4
  On-line CPU(s) list:   0-3
Vendor ID:               GenuineIntel
  Model name:            Intel(R) Core(TM) i5-7200U CPU @ 2.50GHz
    CPU family:          6
```

硬盘：

```bash
=== START OF INFORMATION SECTION ===
Device Model:     SanDisk Z400s M.2 2280 256GB
Serial Number:    163137420247
LU WWN Device Id: 5 001b44 4a429c9ee
Firmware Version: Z2329012
User Capacity:    256,060,514,304 bytes [256 GB]
Sector Sizes:     512 bytes logical, 4096 bytes physical
Rotation Rate:    Solid State Device
Form Factor:      M.2
TRIM Command:     Available, deterministic, zeroed
Device is:        Not in smartctl database 7.3/5319
ATA Version is:   ACS-2 T13/2015-D revision 3
SATA Version is:  SATA 3.2, 6.0 Gb/s (current: 6.0 Gb/s)
Local Time is:    Thu Jan 19 16:45:31 2023 CST
SMART support is: Available - device has SMART capability.
SMART support is: Enabled
```

我使用的CPU调度驱动为 `intel_pstate`，前年的某天我把默认的调度模式改为了`powersave` 这可能是造成编译过慢的原因，后期我手动改成了 `performance`

构建的时间主要耗费在 IO 上，使用 `iostat -m -x 1` 观察SSD状态，发现这段时间 ssd 的读写使用率达到 `98 %`

`ccache`也是拖慢编译速度的一个很大因素。ccache 我放在了另外一块机械硬盘上，作为云缓存，使用 sshfs 挂载，多台机器共享这个 cache 目录，这样的有点就是在另外一台机器上可以复用这些编译缓存（使用 distcc 分布式编译），但单台机器的系统的瓶颈在 IO 读写上，这时候云缓存反而会拖慢整个编译速度。

但具体原因自己也懒得分析了，**系统优化是一个深不见底的大坑**，建议从入门到弃坑：）

[你家的光猫，你能怎么办？（一）](https://www.notion.so/b0350affc43642639ec1d54e5a805587)
