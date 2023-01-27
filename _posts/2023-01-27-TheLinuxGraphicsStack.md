---
title: 关于 Linux 显示软件与技术栈，乱谈一下
articles:
   excerpt_type: html
---

Linux 显示软件栈贼复杂，是我见过最复杂的系统，然后我本来就挺笨的。关于Linux 显示软件与技术栈说错我不负责，你看看就好
<!--more-->

# 说一下 2D 渲染

## 科普一下 X Server 相关的库

**Xlib，XCB，GTK，Qt，X ToolKit  的关系：**

Xlib 是一个用于 2D 绘图 C 函数库，用来与 X Server讲话，有了 Xlib，开发者就可以不需要知道 X proto就编写图形化界面，Xlib 现在被 XCB 取代了，Xlib 是 1985 的项目，XCB 是 2007 年的项目，XCB 重新实现了 Xlib。

Xlib 还是属于底层库，不提供 Button，Widgets，Dialog 这样的组件，那不得搞死人。所以程序员一般都不直接使用 Xlib，而是使用更高层次的图形库，这些图形库直接调用 Xlib进行绘图，比如，X-Toolkit，常见的 Gtk，Qt，SDL 等。但注意，调用 Xlib 不是这些图形库唯一绘图的办法，许多图形库也可以直接和图形硬件讲话。

这里放一张图：

![Untitled](/images/%E5%85%B3%E4%BA%8E%20Linux%20%E6%98%BE%E7%A4%BA%E8%BD%AF%E4%BB%B6%E4%B8%8E%E6%8A%80%E6%9C%AF%E6%A0%88%EF%BC%8C%E6%88%91%E6%83%B3%E5%88%B0%E8%AF%B4%E8%AF%B4%E4%BB%80%E4%B9%88%20eeecf33ea2f44e1b9ef29041dcf2dfff/Untitled.png)

如果你有编写 X-Tookit（Xt）及上层库如 Motif 的开发经验，那么叔叔你好，你的孩子可能都比我大了。

## X Server 的角色和内部的 DDX 驱动

简单说一下： Xlib 是通过 `X Server` **间接**完成所有绘图。 Xlib 通过 X11 Proto 发送渲指令，X Server 将接收处理这些指令，**并将其转换为硬件绘图的实际指令**。 这里 X Server 能将 X Proto 这种**与硬件无关的指令** 转换为与**图形设备相关的硬件指令。**

> X Server：虽然我不是显示驱动，但我也干显示驱动的活，蛤蛤蛤。
>

可是显示硬件很多，ARM Mali GPU 就有一堆不同的型号，加上 Intel 和AMD，Nvidia，X Server 需要把统一的 X Proto 转化为每个厂商每种硬件专有的绘图语言，就涉及到巨量的 GPU 寄存器和显示内存的读写操作，X Server 的代码岂不是日渐肥胖到最后无法维护。

所以 X Server 内与特定显示硬件相关的代码就需要独立出来，成为单独的用户空间二进制库，这就是 X Server 内的 **DDX 用户空间驱动，DDX 用户空间驱动才是真正的显示驱动，**但 DDX 驱动也仅是整个显示驱动的一部分。

![Screenshot 2023-01-27 053937.png](/images/%E5%85%B3%E4%BA%8E%20Linux%20%E6%98%BE%E7%A4%BA%E8%BD%AF%E4%BB%B6%E4%B8%8E%E6%8A%80%E6%9C%AF%E6%A0%88%EF%BC%8C%E6%88%91%E6%83%B3%E5%88%B0%E8%AF%B4%E8%AF%B4%E4%BB%80%E4%B9%88%20eeecf33ea2f44e1b9ef29041dcf2dfff/Screenshot_2023-01-27_053937.png)

如果你用的 Ubuntu，Intel 集成显卡，那么你会发现系统中有这个软件包： `xserver-xorg-video-intel` ，这就是 Xserver 内的 DDX 驱动。

# 3D绘图的情况

## OpenGL 不是库函数，是一个3D绘图标准

虽然 OpenGL 的全称是 `Open Graphics Library，`但它不是某个具体的二进制库，而是一个标准。OpenGL 定义了差不多 350 多个标准 2D和3D绘图指令，其指令就像这样：

![Untitled](/images/%E5%85%B3%E4%BA%8E%20Linux%20%E6%98%BE%E7%A4%BA%E8%BD%AF%E4%BB%B6%E4%B8%8E%E6%8A%80%E6%9C%AF%E6%A0%88%EF%BC%8C%E6%88%91%E6%83%B3%E5%88%B0%E8%AF%B4%E8%AF%B4%E4%BB%80%E4%B9%88%20eeecf33ea2f44e1b9ef29041dcf2dfff/Untitled%201.png)

这里是OpenGL 3.1 规范里 Shader 相关的函数：

![Untitled](/images/%E5%85%B3%E4%BA%8E%20Linux%20%E6%98%BE%E7%A4%BA%E8%BD%AF%E4%BB%B6%E4%B8%8E%E6%8A%80%E6%9C%AF%E6%A0%88%EF%BC%8C%E6%88%91%E6%83%B3%E5%88%B0%E8%AF%B4%E8%AF%B4%E4%BB%80%E4%B9%88%20eeecf33ea2f44e1b9ef29041dcf2dfff/Untitled%202.png)

OpenGL 因为它是无形的，所以不仅跨语言，还跨平台，显示硬件的厂商大部分会根据 OpenGL 的规范去实现出一套 闭源的 GL 函数库叫 `*libGL.so*`，并且厂商给出的 *`libGL.so`* 一般都带有硬件加速功能。

逼逼赖赖几句：显示硬件属于是计算机硬件中**黑盒子中的黑盒子**，所以 OpenGL 的具体实现大多由厂商编写，部分能有机会开源，某些 ARM 提供的的 *[libGL.so](http://libGL.so)* 驱动不仅闭源还非常不友好。且理想的情况是厂商根据 OpenGL 标准去实现 *libGL.so* 图形库，但很多厂商还是个大爷，我可以不按OpenGL 的标准去实现 *libGL.so*，我也可以魔改扩展 OpenGL ，导致 OpenGL 从规范变成了参考，干脆叫 `libFuckYourselfGL.so`算了，蛤蛤蛤。

## X Server 通过 GLX 转发GL指令实，现对3D绘图的间接渲染

厂商给出 *[libGL.so](http://libGL.so)* 能直接和操作显示硬件的寄存器和显存，一些独占屏幕的3D应用可以直接调用厂商给的 libGL.so 进行带硬件加速的3D与2D绘图，我初中的电子词典的 UI 就是 QT 桌面，独占显示的，使用的是闭源的Mips处理器，北京君正生产的 Jz4740 Soc，使用不知道从哪里来的闭源 libGL.so进行绘图，打 NES 游戏能到 30fps效率还可以 。

但这明显不兼容 Linux 已有的显示栈 ，因为早期的 Linux 上只有 X Server，开发者也不想改动 Linux 的显示软件栈。所以开发者搞了一组扩展叫 GLX（Open**GL** Extension to the **X** Window System）

GLX 是一组对 **X** Window System 的扩展主要由三个扩展组成：

1. OpenGL 函数的编程接口，好让 X ****Window System 之上的程序可以使用 OpenGL 指令
2. 扩展 Window proto，让运行在 X Server 之上的程序可以发送 OpenGL 指令给X Server
3. 扩展 X Server，使X Server 能处理和接收的 GL 渲染指令，并将它们传递给厂商提供的 libGL.so 库，当然也可以是其它的 libGL.so，比如完全开源的 [Utah GLX driver](https://utah-glx.sourceforge.net/)。

然后整个架构得就像这张图：

![Untitled](/images/%E5%85%B3%E4%BA%8E%20Linux%20%E6%98%BE%E7%A4%BA%E8%BD%AF%E4%BB%B6%E4%B8%8E%E6%8A%80%E6%9C%AF%E6%A0%88%EF%BC%8C%E6%88%91%E6%83%B3%E5%88%B0%E8%AF%B4%E8%AF%B4%E4%BB%80%E4%B9%88%20eeecf33ea2f44e1b9ef29041dcf2dfff/Untitled%203.png)

这种渲染方式叫 **间接渲染（indirect redering），使用OpenGL指令每次都需要经过 X Server**。显然渲染方式效率比较低，因为中间多了一层 X Server 对 GL 指令的转发，在密集绘图和渲染时，每次这么一来一回显然是资源浪费。

## 直接渲染

再写就猝死了…..我先去睡一下。
