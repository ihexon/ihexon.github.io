---
title: 给你的 Java 开发环境上代理
articles:
   excerpt_type: html
---

嘛的真是烦死了，每次看 Maven 的 Java 项目都要经历 jar 包下载失败，手动执行`mvn dependency:sources` ，又依赖下载失败 ，浪费巨多时间。
<!--more-->
# IDEA 上代理

IDEA 支持 HTTP 代理，=位置`File | Settings | Appearance & Behavior | System Settings | HTTP Proxy`：

![Untitled](/images/%E7%BB%99%E4%BD%A0%E7%9A%84%20Java%20%E5%BC%80%E5%8F%91%E7%8E%AF%E5%A2%83%E4%B8%8A%E4%BB%A3%E7%90%86%2071d22edbcf814433a5c58d048d8397ab/Untitled.png)

不得不说 Intellij idea 的 UI 逻辑做的真舒服，就好用。很难想象这种程度的 UI 竟然是使用老掉牙的 Java Swing 图形框架实现的。

# IDEA 自带的 Maven 走代理

Maven 需要额外设置，因为 IDEA 和 Maven 启动的 JVM 虚拟机是两个独立的 JVM 进程。

![Untitled](/images/%E7%BB%99%E4%BD%A0%E7%9A%84%20Java%20%E5%BC%80%E5%8F%91%E7%8E%AF%E5%A2%83%E4%B8%8A%E4%BB%A3%E7%90%86%2071d22edbcf814433a5c58d048d8397ab/Untitled%201.png)

在 `File | Settings | Build, Execution, Deployment | Build Tools | Maven | Importing` 的 `VM options for importer` 内填写 JVM 的启动参数，让 Maven所在的 JVM 全局走代理就行：

```bash
-DproxySet=true -DproxyHost=localhost -DproxyPort=2020
```

最后：IDE 我只选 Intellij IDEA，虽然当然我最常用的是 VSCode。

祝大家新年快乐呀~
