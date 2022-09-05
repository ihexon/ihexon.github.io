---
title: 从源码构建 IntelliJ IDEA Community Edition
articles:
   excerpt_type: html
---

## Intellij 平台简介

你可能不知道的是 IntelliJ IDEA 社区版是开源的，其源代码托管在
[https://git.jetbrains.org](https://git.jetbrains.org/?p=idea/community.git;a=summary)
中。

仓库
[https://github.com/JetBrains/intellij-community/](https://github.com/JetBrains/intellij-community/) 与
[https://git.jetbrains.org](https://git.jetbrains.org/)
保持同步，但可能会有延迟。

准确来说 IntelliJ 是一个开源的 IDE 平台，IntelliJ IDEA 等 JetBrains
产品基于IntelliJ 平台开发。Google 的 Android Studio也是基于IntelliJ
平台开发的，从Android Studio的界面看就知道。

IntelliJ 平台提一个 现代 IDE所需要的基础架构组件
。比如创建工具窗口、树视图和列表，快速搜索，全文编辑器，语法突出显示、代码折叠、代码补全等抽象实现。

文档地址：[https://plugins.jetbrains.com/docs/intellij/intellij-platform.html](https://plugins.jetbrains.com/docs/intellij/intellij-platform.html)
<!--more-->

## 从源码构建 IntelliJ IDEA Community Edition

首先克隆源码：

```bash
$ git clone git://git.jetbrains.org/idea/community.git --depth 1
```

💡 如果不添加 `--depth 1`
将会克隆全部提交记录，体积会非常大。这里需要说明的一点是`git.jetbrains.org`在国内非常慢，直连大概
10kb/s ，而`git://` 协议不支持从 `http_proxy` 读取代理配置，需要使用 `proxychains` 强制 git 走代理。

💡 Master 分支可能无法成功构建。

Jetbrains 内部 CI
应该会不定时进行构建测试，但哪次提交构建成功或者失败我就不太清楚了。所以Master
分支能不能成功构建全看运气。我写了一个脚本，会自动构建 IntelliJ IDEA Community
Edition 并记录构建成功的 `commit tree`供大家参考。

我感觉 Intellij
平台虽然是开源的，但类似于一种大家都知道大家都在用，但一般不会给它贡献代码的情况。
Intellij 平台的代码提交者基本是在 Jetbrains 内部工作的大佬。

在 windows 平台上需要对 git 客户端配置两个参数

`git config --global core.longpaths true`

`git config --global core.autocrlf input`

IntelliJ IDEA 社区版需要独立的 Android 模块，在源码根目录克隆Android 模块目录：

`git clone git://git.jetbrains.org/idea/android.git android --depth 1`

<aside>
💡 Android 模块的 Master 分支同样可能无法成功构建，全靠运气。

</aside>

运行 `installers.cmd` 进行源码构建：

```bash
$ ./installers.cmd -Dintellij.build.dev.mode=false
-Dintellij.build.target.os=current
```

增量构建需要添加 `-Dintellij.build.incremental.compilation=true`
参数，增量构建可以减少构建时间。

## 遇到的问题

 `/tmp` 不能为软链接，否则在 `jps-bootstrap` 时会失败。
 如果你的Linux 发行版的 /tmp 目录为软链接，需要为JVM添加参数：
 ```sh
 $ export _JAVA_OPTIONS="-Djava.io.tmpdir=/var/tmp"
 ```

## 后话

 构建 Intellij 平台需要的内存非常大，8G内存可能会不够，在构建的时候会直接爆炸。

 如果是调试 Intellij 平台。最低要 16G 内存，不然会卡成 PPT。

 **如果我就是穷怎么办？**

 如果是单纯构建 Intellij 平台，可以通过 SWAP
 （ZSWAP或者ZRAM）来弥补内存不足的情况。

 我这里的情况是用一台机顶盒作为 AutoBuild 服务器，内存只有 4G ，但通过 ZRAM
 可以扩展出
 11G的SWAP内存，我一开始觉得这样操作算作弊。但实测确实可以成功构建IDEA
 社区版，但就是非常非常慢，因为EMMC的 IO 读写慢，DDR 内存 IO
 慢，造成了虽然能构建，但构建一次需要4个小时。

 但作为 AutoBuild 服务器，4小时构建时长就不是问题，因为我本打算就一天构建2次。多次重复构建没有实际意义还不环保：）
