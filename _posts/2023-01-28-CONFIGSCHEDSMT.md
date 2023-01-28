---
title: 无聊 001
articles:
   excerpt_type: html
---
`CONFIG_SCHED_SMT` 到底要不要打开？
<!--more-->
**`CONFIG_SCHED_SMT`**

SMT 是叫同步多线程。是一种在一个CPU
的时钟周期内能够执行来自多个线程的指令的硬件多线程技术

内核有关`CONFIG_SCHED_SMT` 的说明：

> Improves the CPU scheduler's decision making when dealing with MultiThreading
> at a cost of slightly increased overhead in some places. If unsure say N here
>

但是在那些地方变慢文档里没写，如果你翻看`CONFIG_SCHED_SMT` 为中心的
patches，你会发现启用`CONFIG_SCHED_SMT`
只会让内核变大一点，但完全可以接受。`CONFIG_SCHED_SMT` 相关的代码
`sched_smt_present` 静态 key 所控制，`sched_domains` 只在平台 CPU 支持 SMT
时才启用 SMT ，`CONFIG_SCHED_SMT`  不会改变内核的原来行为。

打开之前和之后的`sched_domain` 都一样：

``bash
$ cat /proc/sys/kernel/sched_domain/cpu*/domain*/name | sort | uniq
DIE
MC
``

理论上不会让内核性能变慢其实。

如果你你使用的时 CFS 调度，CFS代码内由额外的逻辑去迎合 SMT，如果你不启用
`CONFIG_SCHED_SMT` 那么CFS对 SMT 优化的特性就不会被编译。

看到这里我觉得你也许会觉得还是打开这个配置比较好。

