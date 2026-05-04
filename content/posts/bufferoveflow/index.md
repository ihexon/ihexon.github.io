---
title: "Buffer Overflow 入门笔记"
summary: "通过一个 scanf 未限制输入长度的例子，记录 AArch64 栈帧、LR 寄存器和返回地址覆盖的基本思路。"
description: "通过一个 scanf 未限制输入长度的例子，记录 AArch64 栈帧、LR 寄存器和返回地址覆盖的基本思路。"
date: 2023-01-05
draft: false
categories:
  - "security"
tags:
  - "exploit"
  - "buffer-overflow"
  - "aarch64"
---
functions echo 的 scanf 没有对输入的buffer 大小做限制而用户可以输入超长字符串覆盖函数的 return 地址，进而跳转执行 secretFunction 函数。

<!--more-->

考虑下面的代码：

![](images/1fcbeb48-e333-4fa3-8a13-7227c7680c74.png)

functions echo 的 scanf 没有对输入的buffer 大小做限制而用户可以输入超长字符串覆盖函数的 return 地址，进而跳转执行 secretFunction 函数。

尝试输入：`1234AAAABBBB`

执行到地 11 行时，栈的内容：

![](images/168bc00d-1e31-4b1b-8ce8-93fb1ee4cd8d.png)

因为 `char buffer[4]` 所以溢出的部分为 `AAAABBBB`，者很好理解。


## Buffer Overflow 的本质

从 echo 返回到 main 函数会执行 ldp 指令：

![](images/ba6d3e95-56a7-4ff3-ab21-efcfbe66f8bd.png)


x29
When a function is called, its stack frame is typically set up to store information such as the return address, function arguments, and local variables. The frame pointer points to the base of this stack frame, allowing easy access to these values through fixed offsets from the frame pointer.

x29 通常会被设置为当前函数的栈帧底部的地址，这样可以通过偏移量相对于x29来访问局部变量和函数参数。


x30(LR):
The LR register allows the processor to return control to the correct location in the code after a function call. **When a function is called, the address of the instruction immediately following the function call is stored in the LR register.** This allows the processor to resume execution from that point once the function execution is complete.

执行之前的 x29 和 x30 寄存器
![](images/ed9ae8d6-2c12-471d-8f04-e74a3f3b2fa3.png)


执行之前的栈如下，`$ stack -i 20` 显示：
![](images/d4250088-97a9-4651-8705-21839deff458.png)


After：
![](images/a7fde40b-3c89-450b-b667-063b3ca26eae.png)


可见栈空间向下扩展 `0x10`（ 0x7fffffec20 = 0x7fffffec10 + 0x10）
```sh
pwndbg> x/i 0x7ff7dec8f0  
0x7ff7dec8f0 <__GI_exit>:    stp     x29, x30, [sp, #-16]!                                                                
```
![](images/3c247f21-bb2b-4bca-b53c-86ceb04a5df4.png)

原来的 sp 变成了 x29, x30 = 原sp - 0x8

X30 也就是 LR 指向了 `<__GI_exit>`

```sh
pwndbg> x/i 0x7ff7dec8f0  
0x7ff7dec8f0 <__GI_exit>:    stp     x29, x30, [sp, #-16]!
```
看到 ` stp     x29, x30,` 表示这又是某个函数的开头。

这非常好理解，因为 echo 的返回值为 return 0, GCC 把它认为是 exit(0)，基 exit 是 glibc 提供的退出函数，It performs various cleanup tasks, such as flushing streams, closing files, and calling functions registered with the atexit or on_exit functions. After cleanup, exit terminates the program execution and returns control to the operating system.

如果 stepi 的，会发现转入了 `glibc-2.38/sysdeps/nptl/libc_start_call_main.h` 中的 `__libc_start_call_main` 运行：

![](images/0a5739fa-8197-4df9-b6d6-a68e66325dc8.png)


main 函数 return 时：
![](images/74c09fd7-675f-4b29-a5be-3ae56e629cb8.png)

```
  ldp    x29, x30, [sp], #0x10  
```
执行完成后:
1. x29 = sp
2. x30 = sp + 0x8 
3. sp = sp + 0x10

这里关键是 x30 的值如何，决定了main 函数 return 到哪里去，我们可以计算一下  x30 的值，显然为 0x7ff7dd73ec（sp=0x7fffffec10,sp-0x8 ）而 0x7ff7dd73ec 为 libc.so.6 中的 .text 
对应的函数为：

```sh
0x7ff7dd73ec <__libc_start_call_main+92>:       0x94005541
```

最后程序正常退出：

![](images/ac6e60e3-bc6b-4c66-a9da-24eb58c9ae4e.png)

这没什么问题，1234AAAABBBB 最终并不会造成程序异常退出，因为 payload 的长度并不足以覆盖到 main函数的 return 地址，本质上是执行到 `ldp    x29, x30, [sp], #0x10 ` 的时候，payload 并不会影响到 x30 计算后的值。

本质上，buffer overflow 可以看作是对 LR 寄存器的覆盖，你覆盖了LR寄存器，就可以控制程序跳转到你想要的地方去执行。

### 动手覆盖 main 函数的返回地址

关键在这个地方：
![](images/62167eb3-a1aa-41be-9613-a710c5f0382c.png)

我们知道 一切源于这条指令：`  ldp    x29, x30, [sp], #0x10 `：
1. x29 = sp
2. x30 = sp + 0x8 
3. sp = sp + 0x10

1234AAABBBB 还不足以覆盖到栈地址 0x7fffffec18（sp + 0x8 ），在 aarch64 中，指针长度为 `long *`，也就是 8 字节，所以payload 需要适当增加，接下来组装 payload，8字节一组：
```
[1234AAAA] [BBBBCCCC] [DDDDEEEE] 
```

理论上DDDDEEEE能填充到 0x7fffffec18 + 0x8 的区域，传入`1234AAAABBBBCCCCDDDDEEE`，在 main 函数的 return 处停止，此时栈：

![](images/35268002-3767-406c-b0f3-26814d3fa140.png)

理论上执行 `ldp    x29, x30, [sp], #0x10` 后，X30（LR）寄存器的值就成了 DDDDEEEE：

![](images/4abfded9-9c70-4e29-a10e-e1baf790923d.png)

使用任何一个 Hex 编辑器将 DDDDEEEE 改为 secrtFunction 的函数开始地址：
