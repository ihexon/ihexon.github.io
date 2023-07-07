---
title: libc.so 的 _start
articles:
   excerpt_type: html
---


# GDB非预期的在 [libc.so](http://libc.so) 中的 _dl_start 下断点

gdb 在`BinaryHacking 的 _start` 处下断点，发现执行的汇编代码咋和想象中的不太一样?

![Untitled](/images//libc%20so%20%E7%9A%84%20_start%20524805650dad49d9baabd0732a4264a3/Untitled.png)

gdb 在 0x0000000000400480 处中断程序运行，但是run 之后发现咋跳到一个 奇怪的位置执行`_dl_start`，并且汇编代码完全不同：

<!--more-->
![Untitled](/images//libc%20so%20%E7%9A%84%20_start%20524805650dad49d9baabd0732a4264a3/Untitled%201.png)

`objdump -d BinaryHacking -j.text --disassemble="_start"` 输出：

![Untitled](/images//libc%20so%20%E7%9A%84%20_start%20524805650dad49d9baabd0732a4264a3/Untitled%202.png)

这完全是两个不同的函数，并且地址也不一样，一个是`0x0000000000400480` ，一个是`0x0000007fb7fdac28`。`0x0000007fb7fdac28` 处的 _dl_start 实际上是 GNU LIBC 的 `_dl_start` 函数，gdb 是先跳转到 libc.so 中的 `_dl_tart` 函数去执行了，然后再跳转到 BinaryHacking 的 `_start` 执行。

但如果我要调试的是被调试 ELF 文件中的 _start 而不是 [libc.so](http://libc.so) 中的`_dl_start` 怎么办？

使用 `info functions` 指令查看 _start 在 ELF 中的地址，然后 使用 `b *address` 在 ELF 处的 _start 下断点。

比如说 _start 的地址为：

![Untitled](/images//libc%20so%20%E7%9A%84%20_start%20524805650dad49d9baabd0732a4264a3/Untitled%203.png)

使用 `b *0x0000000000400480` 打断点。使用 run 运行到 `0x0000000000400480` 处查看汇编代码：

![Untitled](/images//libc%20so%20%E7%9A%84%20_start%20524805650dad49d9baabd0732a4264a3/Untitled%204.png)

这回确实是被调试 ELF 中的 `_start`入口函数了。

# [libc.so](http://libc.so) 中的 `_dl_start` 函数

感兴趣的同学可以自己去stepin GNU LIBC 的`_dl_start`，但前提是你有足够的时间不至于气的掀桌子。

然后源码分析可以看这里 [_dl_start源码分析___dl_start入参_二侠的博客-CSDN博客](https://blog.csdn.net/conansonic/article/details/54236335)

但基本上都符合下面的给出的流程。

**Statically-linked 文件**

- The ELF headers points program start at `_start`.
- `_start` (sysdeps/mach/hurd/i386/static-start.S) calls `_hurd_stack_setup`
- `_hurd_stack_setup` (sysdeps/mach/hurd/i386/init-first.c) calls `first_init` which calls `__mach_init` to initialize enough to run RPCs, then runs the `_hurd_preinit_hook` hooks, which initialize global variables of libc.
- `_hurd_stack_setup` (sysdeps/mach/hurd/i386/init-first.c) calls `_hurd_startup`.
- `_hurd_startup` (hurd/hurdstartup.c) gets hurdish information from servers and calls its `main` parameter.
- the `main` parameter was actually `doinit` (in sysdeps/mach/hurd/i386/init-first.c), which mangles the stack and calls `doinit1` which calls `init`.
- `init` sets threadvars, tries to initialize threads (and perhaps switches to the new stack) and gets to call `init1`.
- `init1` gets the Hurd block, calls `_hurd_init` on it
- `_hurd_init` (hurd/hurdinit.c) initializes initial ports, starts the signal thread, runs the `_hurd_subinit` hooks (`init_dtable` hurd/dtable.c notably initializes the FD table and the `_hurd_fd_subinit` hooks, which notably checks `std*`).
- We are back to `_start`, which jumps to `_start1` which is the normal libc startup which calls `__libc_start_main`
- `__libc_start_main` (actually called `LIBC_START_MAIN` in csu/libc-start.c) initializes libc, tls, libpthread, atexit
- `__libc_start_main` calls initialization function given as parameter `__libc_csu_init`,
- `__libc_csu_init` (csu/elf-init.c) calls `preinit_array_start` functions
- `__libc_csu_init` calls `_init`
- `_init` (sysdeps/i386/crti.S) calls `PREINIT_FUNCTION`, (actually libpthread on Linux, `__gmon_start__` on hurd)
- back to `__libc_csu_init` calls `init_array_start` functions
- back to `__libc_start_main`, it calls calls application's `main`, then `exit`.

**dynamically-linked ELF文件**

- dl.so ELF headers point its start at `_start`.
- `_start` (sysdeps/i386/dl-machine.h) calls `_dl_start`.
- `_dl_start` (elf/rtld.c) initializes `bootstrap_map`, calls `_dl_start_final`
- `_dl_start_final` calls `_dl_sysdep_start`.
- `_dl_sysdep_start` (sysdeps/mach/hurd/dl-sysdep.c) calls `__mach_init` to initialize enough to run RPCs, then calls `_hurd_startup`.
- `_hurd_startup` (hurd/hurdstartup.c) gets hurdish information from servers and calls its `main` parameter.
- the `main` parameter was actually `go` inside `_dl_sysdep_start`, which calls `dl_main`.
- `dl_main` (elf/rtld.c) interprets ld.so parameters, loads the binary and libraries, calls `_dl_allocate_tls_init`.
- we are back to `go`, which branches to `_dl_start_user`.
- `_dl_start_user` (./sysdeps/i386/dl-machine.h) runs `RTLD_START_SPECIAL_INIT` (sysdeps/mach/hurd/i386/dl-machine.h) which calls `_dl_init_first`.
- `_dl_init_first` (sysdeps/mach/hurd/i386/init-first.c) calls `first_init` which calls `__mach_init` to initialize enough to run RPCs, then runs the `_hurd_preinit_hook` hooks, which initialize global variables of libc.
- `_dl_init_first` calls `init`.
- `init` sets threadvars, tries to initialize threads (and perhaps switches to the new stack) and gets to call `init1`.
- `init1` gets the Hurd block, calls `_hurd_init` on it
- `_hurd_init` (hurd/hurdinit.c) initializes initial ports, starts the signal thread, runs the `_hurd_subinit` hooks (`init_dtable` hurd/dtable.c notably initializes the FD table and the `_hurd_fd_subinit` hooks, which notably checks `std*`).
- we are back to `_dl_start_user`, which calls `_dl_init` (elf/dl-init.c) which calls application initializers.
- `_dl_start_user` jumps to the application's entry point, `_start`
- `_start` (sysdeps/i386/start.S) calls `__libc_start_main`
- `__libc_start_main` (actually called `LIBC_START_MAIN` in csu/libc-start.c) initializes libc, atexit,
- `__libc_start_main` calls initialization function given as parameter `__libc_csu_init`,
- `__libc_csu_init` (csu/elf-init.c) calls `_init`
- `_init` (sysdeps/i386/crti.S) calls `PREINIT_FUNCTION`, (actually libpthread on Linux, `__gmon_start__` on hurd)
- back to `__libc_csu_init` calls `init_array_start` functions
- back to `__libc_start_main`, it calls application's `main`, then `exit`.
