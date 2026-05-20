---
title: "网络安全考古：NSE 入门"
summary: "从原理、本质、设计哲学和方法论角度理解 NSE"
description: "nmap 脚本引擎 nse 入门"
date: 2026-05-20
draft: false
categories:
  - "security"
tags:
  - "nmap"
  - "nse"
  - "lua"
---

NSE 是 Nmap Scripting Engine，是 Nmap 内置的 Lua 脚本扩展系统，用来在端口扫描和服务识别之后继续做协议探测、资产发现、漏洞验证和结构化信息采集。它常见于 HTTP 指纹识别、TLS 证书分析、数据库未授权探测、默认账号检查和轻量级漏洞检测等场景。

<!--more-->

## NSE 的本质

NSE 的本质，是 Nmap 内部嵌入的一个受限制 Lua 运行环境。它使用 Lua 语法，但不是一个普通 Lua 解释器；它运行在 Nmap 的调度、网络、超时、并发和输出体系里，并通过 NSE API 访问扫描上下文。

Nmap 负责决定什么时候运行脚本、给脚本传入什么扫描上下文、如何调度网络 IO、如何处理并发、如何把脚本结果合并到最终输出里。

用图表示会更直观：

{{< mermaid >}}
flowchart TD
    A[把 .nse 脚本交给 Nmap] --> B[Nmap 加载脚本]
    B --> C[读取脚本说明、分类、匹配规则和执行函数]
    C --> D[Nmap 扫描目标]
    D --> E[发现存活主机、开放端口和服务信息]
    E --> F{脚本是否匹配当前主机或端口?}
    F -- 否 --> G[跳过这个脚本]
    F -- 是 --> H[把 host 和 port 信息交给脚本]
    H --> I[脚本执行协议探测]
    I --> J[例如 HTTP 请求、读取 banner、检查响应特征]
    J --> K[脚本把结果返回给 Nmap]
    K --> L[Nmap 整理为普通输出和 XML 输出]
{{< /mermaid >}}

典型 NSE 脚本只需要关心几件事：

```lua
description = [[
What this script does.
]]

author = "name"
license = "Same as Nmap"
categories = {"discovery", "safe"}

portrule = ...

action = function(host, port)
  ...
end
```

一个 NSE 脚本通常最少要提供两个入口：

```text
portrule  负责判断脚本要不要在某个端口上运行
action    负责真正执行探测逻辑
```

NSE 使用 Lua 语法，但是一个受限制的系统脚本环境。普通 Lua 里你可能会习惯使用系统命令、第三方模块、文件系统和 LuaSocket。但在 NSE 里，更推荐使用 Nmap 自带的库：

```lua
local http = require "http"
local shortport = require "shortport"
local stdnse = require "stdnse"
local nmap = require "nmap"
```

NSE 的网络操作应该走 Nmap 的 socket、`comm`、`http` 等机制。这样它才能和 Nmap 的超时、并发、重试、输出、服务识别配合起来。

也就是说，NSE 的重点不是“Lua 能干什么”，而是“Nmap 允许脚本在扫描上下文里安全、稳定地干什么”。

## 设计哲学：让探测贴着端口运行

例如一个探测 HTTP 脚本不会自己去扫全端口，而是写：

```lua
local shortport = require "shortport"

portrule = shortport.portnumber(80)
```

`shortport` 不是一组端口号，而是 NSE 自带的一个“端口匹配辅助库”。它里面提供了一些函数和预设规则，用来生成 `portrule` 需要的匹配函数。

换句话说，`shortport` 不负责扫描端口，也不负责发请求。它只负责根据 Nmap 已经得到的信息做判断，然后返回 `true` 或 `false`，告诉 Nmap：这个脚本要不要在当前端口上运行。

`shortport.portnumber(80)` 会生成一个匹配函数。它大致等价于：

```text
如果当前端口是 open，并且端口号是 80，那么返回 true；
否则返回 false。
```

也就是说：

```lua
portrule = shortport.portnumber(80)
```

表示这个脚本只在 80 端口开放时运行。

## portrule 是脚本的边界

`portrule` 是 NSE 脚本最重要的设计点之一。它决定脚本运行范围，也决定扫描噪音。

刚才的 80 端口例子最容易理解：

```lua
portrule = shortport.portnumber(80)
```

但现实里的 Web 服务不一定只在 80 端口。HTTPS 常在 443，开发服务可能在 8080、8443、9000。这个时候就要决定：脚本到底应该跑得保守一点，还是激进一点。

保守写法：

```lua
portrule = shortport.http
```

只在常见 HTTP 端口或服务名被识别为 HTTP/HTTPS 的端口上运行。

激进写法：

```lua
portrule = function(host, port)
  return port.protocol == "tcp" and port.state == "open"
end
```

这会对所有 TCP open 端口都尝试运行。它可能发现非标准 HTTP 服务，但也会对 SSH、MySQL、Redis、SMTP 等端口发 HTTP 请求。扫描噪音和误报都会变多。

比较实际的折中写法是列出一组常见 Web 端口，再结合服务名：

```lua
portrule = shortport.port_or_service(
  {80, 443, 8000, 8080, 8081, 8088, 8180, 8443, 9000, 9443},
  {"http", "https", "http-alt", "https-alt", "http-proxy", "webdav"},
  "tcp",
  "open"
)
```

写 NSE 之前，先想清楚 `portrule`，比先写 `action` 更重要。

## action 是一次协议交互

`action(host, port)` 收到的是 Nmap 的 host 和 port 对象。你不需要自己解析命令行目标，也不需要自己判断端口是否 open，这些已经在 Nmap 内部完成了。

可以粗略把它们理解成：

```text
host  当前目标主机的信息，例如 IP、主机名等
port  当前端口的信息，例如端口号、协议、状态、服务名等
```

如果某个脚本的 `portrule` 匹配了 `80/tcp open http`，Nmap 就会把对应的 `host` 和 `port` 传给 `action`。

一个 HTTP 请求大概是：

```lua
local response = http.get(host, port, "/", {
  header = {
    ["User-Agent"] = "Mozilla/5.0 ..."
  }
})
```

`http.get` 会根据端口和服务情况尝试 HTTP/HTTPS。比如在 `443/tcp` 上，它通常可以自动使用 TLS 去拿 HTTPS 页面。

## nse 的输出应该服务于机器解析

写 NSE 时，不要只想着“终端里打印一行文字”。Nmap 有两套很重要的输出：

```text
普通输出：给人直接看
XML 输出：给程序解析
```

例如你运行：

```bash
nmap --script your-script.nse -oX out.xml target
```

终端里看到的是普通输出，`out.xml` 里保存的是结构化 XML。NSE 脚本返回的结果，会同时影响这两种输出。

最简单的 NSE 脚本可以返回字符串：

```lua
action = function(host, port)
  return "hello from nse"
end
```

普通输出里大概会看到：

```text
|_your-script: hello from nse
```

但是这种字符串对机器不友好。程序只能拿到一整段文本，再自己用正则去拆。更好的方式是返回 Lua table。

### Lua table 和 Nmap 输出

Lua 的 table 可以理解成一组 key/value：

```lua
local result = {
  status = 200,
  title = "Example",
  server = "nginx"
}

return result
```

Nmap 会把这个 table 转成普通输出：

```text
| your-script:
|   status: 200
|   title: Example
|_  server: nginx
```

同时也会在 XML 里变成类似这样的结构：

```xml
<script id="your-script" output="...">
  <elem key="status">200</elem>
  <elem key="title">Example</elem>
  <elem key="server">nginx</elem>
</script>
```

这就是 NSE 返回 table 的意义：人能读，程序也能稳定解析。

### 嵌套 table 会变成 XML table

如果返回值里还有一层 table：

```lua
local result = {
  status = 200,
  body = {
    length = 41836,
    hash = "ad63124ca989c156f4c527656fe9ffe9",
    truncated = false
  }
}

return result
```

普通输出会变成层级结构：

```text
| your-script:
|   status: 200
|   body:
|     length: 41836
|     hash: ad63124ca989c156f4c527656fe9ffe9
|_    truncated: false
```

XML 里会变成 `<table>` 嵌套 `<elem>`：

```xml
<script id="your-script" output="...">
  <elem key="status">200</elem>
  <table key="body">
    <elem key="length">41836</elem>
    <elem key="hash">ad63124ca989c156f4c527656fe9ffe9</elem>
    <elem key="truncated">false</elem>
  </table>
</script>
```

这就是为什么资产采集类 NSE 脚本应该尽量返回 table，而不是拼接一大段字符串。

### output_table 的作用

普通 Lua table 的 key 顺序不稳定。为了让 Nmap 输出顺序更可控，可以使用 `stdnse.output_table()`：

```lua
local out = stdnse.output_table()
out.status = response.status
out.server = headers.server
out.title = title

out.body = stdnse.output_table()
out.body.length = #body
out.body.hash = hash

return out
```

`stdnse.output_table()` 本质上还是 table，只是它记录了字段插入顺序。这样普通输出和 XML 输出的顺序更接近你写代码时的顺序。

### XML 可以直接走 stdout

如果后面要接管道，不一定要写文件。Nmap 的 XML 可以直接输出到 stdout：

```bash
nmap --script your-script.nse -oX - target
```

例如接 `yq` 转 JSON：

```bash
nmap --script your-script.nse -oX - target | yq -p xml -o json
```

这里要注意 `yq -p xml`，因为 Nmap 输出的是 XML，不是 YAML。

理解这层关系后，NSE 的定位会清楚很多：

```text
NSE 负责采集
Nmap 负责输出为普通文本或 XML
外部程序负责解析 XML，再写 SQLite、Elasticsearch 或资产系统
```

## categories 是脚本的安全标签

NSE 脚本会声明分类：

```lua
categories = {"discovery", "safe"}
```

常见分类包括：

```text
safe        通常不会破坏目标
discovery   信息发现
default     默认脚本集
version     辅助版本识别
vuln        漏洞检测
intrusive   可能有侵入性
brute       爆破
external    会访问第三方服务
```

分类不是装饰。别人可能会用：

```bash
nmap --script safe target
```

如果脚本实际会爆破、写入、上传、删除，却标成 `safe`，就是错误的。

## 方法论：先定义结果，再写请求

我现在写 NSE 的顺序通常是：

1. 明确脚本要产出什么字段
2. 明确运行在哪些端口上
3. 明确最多发几次请求
4. 明确超时、body 大小、重定向策略
5. 明确失败时输出什么
6. 最后才写协议交互代码

以 HTTP 资产发现为例，结果字段可以先定成：

```text
status
server
location
content_type
title
body.length
body.hash
body.hash_complete
body.truncated
body.preview
```

然后再决定如何请求 `/`、是否跟随重定向、body 最大读取多少、hash 是否可信。

这种顺序可以避免脚本越写越像临时 curl 包装器。

## NSE 适合什么，不适合什么

适合：

```text
端口级服务探测
协议 banner 提取
HTTP title/header/hash
TLS 证书信息
轻量漏洞验证
数据库未授权探测
默认账号检测
结构化资产采集
```

不适合：

```text
大型爬虫
浏览器渲染 JS
复杂状态机
长时间任务
海量爆破
复杂本地数据库写入
依赖大量第三方 Lua 包
```
