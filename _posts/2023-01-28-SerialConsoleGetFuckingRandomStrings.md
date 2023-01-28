---
title: 无聊 002
articles:
   excerpt_type: html
---
## 串口异常

minicom 串口乱码，但也不是全乱码，随缘乱码，每次按回车的时候输出这玩意儿：

![Untitled](/images/%E6%97%A0%E8%81%8A%20002%209892eae4e8784e849c69c6e008f0504b/Untitled.png)

![Untitled](/images/%E6%97%A0%E8%81%8A%20002%209892eae4e8784e849c69c6e008f0504b/Untitled%201.png)

<!--more-->
检查内核 cmdline 的 console 设置：

```bash
$ cat /proc/cmdline
console=ttyAML0,115200n8 console=tty0
```

检查 minicom 的用户配置：

```bash
$ cat .minirc.amlogic
	 pu port             /dev/ttyUSB0
   pu baudrate         115200
   pu bits             8
   pu parity           N
   pu stopbits         1
   pu rtscts           No
```

波特率 为 115200 8N1 , 对应上了内核 console 的参数，说明 minicom 串口设置没问题。

尝试设置 minicom 为 UTF 8  终端类型为 Xterm

```bash
$ alias minicom='minicom -w -t xterm -l -R UTF-8'
```

依旧随缘乱码。

尝试 chroot 进 rootfs ，安装 locales-all，手动设置 UTF8 环境变量：

```bash
root@localhost# chroot /tmp/rootfs
ubuntu@amlogic# apt update;apt install locales-all
ubuntu@amlogic# echo TERM=xterm-256color >> /etc/environment
ubuntu@amlogic# echo LC_ALL=en_US.UTF8 >> /etc/environment
```

启动 rootfs 后，执行 `echo $TERM; echo $LC_ALL` 后验证 UTF8 环境，但 minicom 依旧随缘乱码。

我他妈？？？

![Untitled](/images/%E6%97%A0%E8%81%8A%20002%209892eae4e8784e849c69c6e008f0504b/Untitled%202.png)

什么情况？？？

似乎和USB供电电源有关，我的板子是通过显示器USB接口进行 5v 供电，我换成5v usb 充电器这个问题会有几率消失。但也有几次换成5V USB充电器供电仍旧出现乱码的情况。难不成电压不稳或者空气介质中有其他干扰造成 TTL 信号不稳定 ？

鬼魂作祟是吧：）

似乎和USB2TTL板有关，我有两个 USB2TTL 板，换另外一个就不会出现随缘乱码的情况。难道和硬件有关？？？

最后换了 从 Bash shell 换成了使用 fish 能缓解该问题。

```bash
$ chshell <USERNAME>
```

fish shell 的设计上似乎对命令行乱码有过滤的作用，能吞掉这些随机的乱码字符。但仅仅是缓解，因为乱码还是存在。

**更新：Sat 28 Jan 2023 10:38:42 AM UTC**

内核配置 CONFIG_NLS 下，瞎JB全选就像这样：

![Untitled](/images/%E6%97%A0%E8%81%8A%20002%209892eae4e8784e849c69c6e008f0504b/Untitled%203.png)

问题就消失了我去…..

可这是文件系统命名支持，和SerialConsole控制台乱码有什么关系…..

并且这样一来内核就大了6kb左右的样子，整整 6kb 啊，你知道 6kb 能在Boot 分区干嘛么？你知道Boot 莫名其妙被插入 6kb 左右的代码有多奇怪，多诡异吗？

好刺激，好兴奋，好涩涩，真是心疼 emmc 哥哥的空间间啦….
