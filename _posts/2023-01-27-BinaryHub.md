---
title: 如果你不想手动构建某些二进制工具给光猫这类的设备，好的，我已经替你干了这些无聊的活
articles:
   excerpt_type: html
---
# 我提供一些预先构建好的二进制文件

你可以在我的 Github上下载到这些二进制 ELF 工具，如 curl，wget，ftp，buysbox 等。这些工具主要用于分析嵌入式设备的固件，搭建测试环境，还可以整点有趣的活，比如在运营商的光猫上跑点自己的代码，比如 PHP 和 Perl。

如果你不想手动构建某些二进制工具给光猫这类的设备，好的，我已经替你干了这些无聊的活。
<!--more-->

[mips32_big_endian](https://github.com/ihexon/BinaryHub/tree/main/mips32_big_endian) 目录下的所有二进制 ELF 文件使用 musl 的 mips32_be 交叉工具链构建并且是静态编译的丢到 设备的 /tmp/ 赋予可执行权限就可以直接运行 。mips32_be 交叉编译工具链也是从 Buildroot 构建的。

注意当前我只提供MIPS32 大端架构的静态 ELF 二进制文件。我没有MIPS_EL小端设备，暂时测试不了。

以后还会提供 ARM 架构的二进制 ELF 文件

## 关于 Debug Symbol

你会发现单个二进制文件体积有点大，因为我保留了 Debug Symbol，因为某些 ELF 文件 运行的不是很好，需要调试，保留Debug Symbol 你也自己可以帮忙调试。

还有一个是安全原因，保留 Debug Symbol 的意思是你可以在 GDB 里直接看到原始的 C 代码。而你在别的地方下载到的ELF文件可能被注入了Shellcode并且去除了这些调试符号，增加你调试这些恶意代码的难度。

这些散布恶意代码的人我不说，但总有一天会被发现。

# 有用的信息，你可能需要在下载之前看看

- [Sha1sum.txt](https://raw.githubusercontent.com/ihexon/BinaryHub/main/mips32_big_endian/sha1sum.txt)
- [Release](https://raw.githubusercontent.com/ihexon/BinaryHub/main/mips32_big_endian/Release)
- [ChangeLog](https://github.com/ihexon/BinaryHub/blame/main/mips32_big_endian/ChangeLog)
- [BinaryNote.md](https://github.com/ihexon/BinaryHub/blob/main/mips32_big_endian/BinaryNote.md)

即使静态编译的程序有时候还是需要外部文件支持运行，比如 file 就通过外部 magic 文件进行文件类型判断，还有 Vim 需要 Terminfo 和 VimRuntime，部署这些二进制就需要做一点处理，你可以在 [BinaryNote.md](https://github.com/ihexon/BinaryHub/blob/main/mips32_big_endian/BinaryNote.md) 里找正确运行这些程序有用的信息，能帮你节约大量的时间

这里提供[mips32_big_endian](https://github.com/ihexon/BinaryHub/tree/main/mips32_big_endian) 目录下二进制文件的 ELF 头和我家光猫的内核信息：

```bash
# ELF Header:
  Magic:   7f 45 4c 46 01 02 01 00 00 00 00 00 00 00 00 00
  Class:                             ELF32
  Data:                              2's complement, big endian
  Version:                           1 (current)
  OS/ABI:                            UNIX - System V
  ABI Version:                       0
  Type:                              EXEC (Executable file)
  Machine:                           MIPS R3000
  Version:                           0x1

# Kernel version
Linux (none) 3.18.21 #4 SMP Tue Nov 22 16:34:26 CST 2022 mips GNU/Linux

# CPU INFO
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

