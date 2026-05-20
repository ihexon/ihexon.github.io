---
title: "网络安全考古：使用 NSE 编写一个 HTTP(S) 资产指纹脚本"
summary: "围绕一个真实 NSE 脚本讲解常用代码写法：portrule、script-args、http.get、HTTPS、title 提取、body hash、截断判断和结构化 XML 输出。"
description: "围绕一个真实 NSE 脚本讲解常用代码写法：portrule、script-args、http.get、HTTPS、title 提取、body hash、截断判断和结构化 XML 输出。"
date: 2026-05-20
draft: false
categories:
  - "security"
tags:
  - "nmap"
  - "nse"
---

NSE 是 Nmap 的 Lua 脚本引擎，适合把一次协议探测挂到 Nmap 的扫描结果上。这篇直接进入实操：编写一个 HTTP(S) 资产指纹脚本，用于 Web 资产发现，提取状态码、Server、Location、Content-Type、title、body 长度、body hash 和 preview。

<!--more-->

## 目标

脚本目标很明确：

```text
在 HTTP/HTTPS 服务上请求一个路径
提取关键 header
提取 title
计算 body hash
只输出 preview，不输出完整 body
标记 hash 是否完整
输出结构化结果，方便 XML 解析
```

从数据流上看，这个脚本做的事情并不复杂：

{{< mermaid >}}
flowchart TD
    A[Nmap 扫描目标端口] --> B{portrule 是否匹配 HTTP 服务?}
    B -- 否 --> C[跳过脚本]
    B -- 是 --> D[action 接收 host 和 port]
    D --> E[读取 script-args: path, max-body-size, useragent]
    E --> F[http.get 发起 HTTP/HTTPS 请求]
    F --> G{response.status 是否存在?}
    G -- 否 --> H[返回 request_failed]
    G -- 是 --> I[提取 header 和 body]
    I --> J[提取 title]
    I --> K[计算 body length 和 MD5 hash]
    K --> L[结合 truncated 和 Content-Length 判断 hash_complete]
    J --> M[组装 stdnse.output_table]
    L --> M
    M --> N[Nmap 输出普通文本和 XML]
{{< /mermaid >}}

脚本文件命名为：

```text
http-asset-fingerprint.nse
```

Nmap 官方脚本通常使用小写和连字符命名，比如 `http-title.nse`、`http-headers.nse`、`ssl-cert.nse`。不要用 `1.nse` 这种临时名字，后面脚本参数和 XML 里的 script id 都会变得难看。

## 设计取舍

这个脚本看起来只是请求一个页面，但里面有几个取舍需要提前定下来：

```text
运行范围：只在 HTTP/HTTPS 服务上跑，不对所有 open TCP 端口乱发请求
body 成本：默认最多读取 2MB，避免遇到大文件或流式响应拖慢扫描
hash 语义：hash 基于实际读到的 body，所以必须输出 hash_complete
输出形态：返回 table，而不是拼接字符串，方便 XML 和后续入库
可配置项：path、max-body-size、User-Agent 通过 script-args 暴露
```

后面的代码基本都围绕这些取舍展开。

## 基础骨架

一个 NSE 脚本最小结构大概是：

```lua
description = [[
Structured curl-like HTTP fetcher (optimized for asset discovery).
]]

author = "ihexon"

license = "Same as Nmap"

categories = {"discovery", "safe"}

local http = require "http"
local shortport = require "shortport"
local stdnse = require "stdnse"
local openssl = require "openssl"

portrule = shortport.http

action = function(host, port)
  ...
end
```

几个字段的含义：

```text
description  脚本说明
author       作者
license      许可证，通常跟 Nmap 保持一致
categories   脚本分类
portrule     决定在哪些端口运行
action       实际探测逻辑
```

## 选择 portrule

最简单的 HTTP 脚本可以写：

```lua
portrule = shortport.http
```

它会匹配常见 HTTP 端口和被 Nmap 识别为 HTTP/HTTPS 的服务，例如：

```text
80
443
631
7080
8000
8080
8088
8180
8443
```

也会匹配服务名：

```text
http
https
http-alt
https-alt
http-proxy
webdav
```

如果 HTTP 跑在非常规端口，比如 `9000`，建议配合 `-sV`：

```bash
nmap -sV -p9000 --script ./http-asset-fingerprint.nse target
```

如果要扫全端口上的 Web 服务：

```bash
nmap -sV -p- --script ./http-asset-fingerprint.nse target
```

不要轻易对所有 open TCP 端口都发 HTTP 请求。那样会更激进，也更吵。

## 支持脚本参数

NSE 里可以通过 `stdnse.get_script_args` 获取参数。

```lua
local path = stdnse.get_script_args(SCRIPT_NAME .. ".path") or "/"
local max_body_size = tonumber(stdnse.get_script_args(SCRIPT_NAME .. ".max-body-size")) or 2 * 1024 * 1024
local user_agent = stdnse.get_script_args(SCRIPT_NAME .. ".useragent")
  or "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
```

这里用 `SCRIPT_NAME .. ".xxx"`，好处是脚本重命名后参数前缀自动变化。

脚本叫 `http-asset-fingerprint.nse` 时，参数就是：

```bash
--script-args http-asset-fingerprint.path=/login
--script-args http-asset-fingerprint.max-body-size=52428800
--script-args 'http-asset-fingerprint.useragent=Mozilla/5.0 ...'
```

默认 body 上限设为 2MB：

```lua
2 * 1024 * 1024
```

这和 Nmap HTTP 库默认思路一致，比较稳。需要尽可能完整 hash 时，可以显式调大，或者设为 `-1` 表示不限制：

```bash
--script-args http-asset-fingerprint.max-body-size=-1
```

## 请求层：发送 HTTP 请求

请求代码：

```lua
local response = http.get(host, port, path, {
  redirect_ok = true,
  max_body_size = max_body_size,
  truncated_ok = true,
  header = {
    ["User-Agent"] = user_agent
  }
})
```

几个参数：

```text
redirect_ok     允许 http.lua 按默认规则处理重定向
max_body_size   限制读取 body 的最大字节数
truncated_ok    body 超过上限时不要直接失败，而是返回截断内容
header          自定义请求头
```

注意：`preview = body:sub(1, 200)` 只控制输出体积，不控制读取体积。真正控制读取体积的是 `max_body_size`。

### HTTPS 如何处理

不需要自己手写 TLS。Nmap 的 `http.get` 底层会使用 `comm.tryssl` 一类机制，在 HTTPS 端口上尝试 SSL/TLS。

例如：

```bash
nmap --script ./http-asset-fingerprint.nse -p80,443 oomol.com
```

测试结果里，`443/tcp open https` 可以正常返回：

```text
status: 200
server: cloudflare
content_type: text/html; charset=utf-8
title: OOMOL - Start with oo-cli. Build in Studio. Deliver through Cloud.
body:
  length: 41836
  hash: ad63124ca989c156f4c527656fe9ffe9
  hash_complete: true
  truncated: false
```

所以脚本可以获取 HTTPS 页面。对于非标准 HTTPS 端口，仍然建议加 `-sV` 帮助 Nmap 判断服务类型。

### 错误处理

不要只判断 `if not response`。Nmap 的 HTTP 库失败时可能仍然返回 table，只是 `response.status == nil`。

更稳的写法：

```lua
if not (response and response.status) then
  return {
    http = {
      success = false,
      error = "request_failed"
    }
  }
end
```

后面可以继续优化，把 `response["status-line"]` 或 incomplete 信息也输出出来。但基础版本先保持简单。

## 解析层：提取 title

HTML title 不是永远小写，也可能带属性。不要只写：

```lua
body:match("<title>(.-)</title>")
```

更稳一点：

```lua
local function extract_title(body)
  if not body then return nil end
  return body:match("<[Tt][Ii][Tt][Ll][Ee][^>]*>([^<]*)</[Tt][Ii][Tt][Ll][Ee]>")
end
```

这能匹配：

```html
<title>Example</title>
<TITLE>Example</TITLE>
<title data-rh="true">Example</title>
```

它仍然不是完整 HTML parser，但对资产发现够用。

### 计算 body hash

Nmap 的 OpenSSL 模块提供 MD5：

```lua
local body_hash = nil
if body_len > 0 then
  body_hash = stdnse.tohex(openssl.md5(body))
end
```

`openssl.md5(body)` 返回二进制 digest，`stdnse.tohex` 把它转成十六进制字符串。

这里的 hash 是对 `response.body` 计算的。也就是说，如果 body 被 `max_body_size` 截断，hash 就是截断内容的 hash，不是完整页面 hash。

所以必须输出完整性标记。

### 判断 hash 是否完整

可以结合两点判断：

1. `response.truncated`
2. `Content-Length` 和实际读取长度是否一致

```lua
local content_length = tonumber(important_headers["content-length"])

local hash_complete = not response.truncated
if content_length then
  hash_complete = hash_complete and content_length == body_len
end
```

然后输出：

```lua
out.body.hash_complete = hash_complete
out.body.truncated = response.truncated or false
```

这样下游系统就不会把截断 body 的 hash 当成完整页面 hash。

## 输出层：结构化输出

推荐使用 `stdnse.output_table()`，它可以保持输出顺序。

```lua
local out = stdnse.output_table()
out.status = response.status
out.server = important_headers.server
out.location = important_headers.location
out.content_type = important_headers["content-type"]
out.title = title

out.body = stdnse.output_table()
out.body.length = body_len
out.body.content_length = important_headers["content-length"]
out.body.hash = body_hash
out.body.hash_complete = hash_complete
out.body.truncated = response.truncated or false
out.body.preview = body:sub(1, 200)

return out
```

Nmap 会把它输出成普通文本，也会在 XML 里输出成结构化节点。

XML 大概会有：

```xml
<elem key="status">200</elem>
<elem key="server">cloudflare</elem>
<elem key="title">...</elem>
<table key="body">
  <elem key="length">41836</elem>
  <elem key="hash">...</elem>
  <elem key="hash_complete">true</elem>
  <elem key="truncated">false</elem>
</table>
```

这比只返回一段字符串好得多。

## 完整脚本

```lua
description = [[
Structured curl-like HTTP fetcher (optimized for asset discovery).
]]

author = "ihexon"

license = "Same as Nmap"

categories = {"discovery", "safe"}

local http = require "http"
local shortport = require "shortport"
local stdnse = require "stdnse"
local openssl = require "openssl"

portrule = shortport.http

local function extract_title(body)
  if not body then return nil end
  return body:match("<[Tt][Ii][Tt][Ll][Ee][^>]*>([^<]*)</[Tt][Ii][Tt][Ll][Ee]>")
end

action = function(host, port)
  local path = stdnse.get_script_args(SCRIPT_NAME .. ".path") or "/"
  local max_body_size = tonumber(stdnse.get_script_args(SCRIPT_NAME .. ".max-body-size")) or 2 * 1024 * 1024
  local user_agent = stdnse.get_script_args(SCRIPT_NAME .. ".useragent")
    or "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

  local response = http.get(host, port, path, {
    redirect_ok = true,
    max_body_size = max_body_size,
    truncated_ok = true,
    header = {
      ["User-Agent"] = user_agent
    }
  })

  if not (response and response.status) then
    return {
      http = {
        success = false,
        error = "request_failed"
      }
    }
  end

  local headers = response.header or {}

  local important_headers = {
    server = headers.server,
    location = headers.location,
    ["content-type"] = headers["content-type"],
    ["content-length"] = headers["content-length"]
  }

  local body = response.body or ""
  local title = extract_title(body)
  local body_len = #body
  local content_length = tonumber(important_headers["content-length"])

  local body_hash = nil
  if body_len > 0 then
    body_hash = stdnse.tohex(openssl.md5(body))
  end

  local hash_complete = not response.truncated
  if content_length then
    hash_complete = hash_complete and content_length == body_len
  end

  local out = stdnse.output_table()
  out.status = response.status
  out.server = important_headers.server
  out.location = important_headers.location
  out.content_type = important_headers["content-type"]
  out.title = title

  out.body = stdnse.output_table()
  out.body.length = body_len
  out.body.content_length = important_headers["content-length"]
  out.body.hash = body_hash
  out.body.hash_complete = hash_complete
  out.body.truncated = response.truncated or false
  out.body.preview = body:sub(1, 200)

  return out
end
```

## 运行脚本

直接指定脚本路径：

```bash
nmap --script ./http-asset-fingerprint.nse -p80,443 oomol.com
```

输出 XML 文件：

```bash
nmap --script ./http-asset-fingerprint.nse -p80,443 -oX out.xml oomol.com
```

输出 XML 到 stdout：

```bash
nmap --script ./http-asset-fingerprint.nse -p80,443 -oX - oomol.com
```

如果要给 `yq` 解析，记得指定 XML 输入格式：

```bash
nmap --script ./http-asset-fingerprint.nse -p80,443 -oX - oomol.com \
  | yq -p xml -o json
```

否则 `yq` 默认可能按 YAML 解析 stdin，报类似错误：

```text
mapping values are not allowed in this context
```

## 常用 script-args

请求指定路径：

```bash
nmap --script ./http-asset-fingerprint.nse \
  --script-args http-asset-fingerprint.path=/login \
  -p80,443 target
```

调大 body 上限到 50MB：

```bash
nmap --script ./http-asset-fingerprint.nse \
  --script-args http-asset-fingerprint.max-body-size=52428800 \
  -p80,443 target
```

不限制 body 大小：

```bash
nmap --script ./http-asset-fingerprint.nse \
  --script-args http-asset-fingerprint.max-body-size=-1 \
  -p80,443 target
```

指定 User-Agent：

```bash
nmap --script ./http-asset-fingerprint.nse \
  --script-args 'http-asset-fingerprint.useragent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36' \
  -p80,443 target
```

## 验证脚本是否能加载

写完后先不要急着扫目标，先看 Nmap 能不能加载脚本：

```bash
nmap --script-help ./http-asset-fingerprint.nse
```

如果正常，会看到：

```text
http-asset-fingerprint
Categories: discovery safe
```

如果 Lua 语法错、模块 require 错、metadata 写错，这一步通常就能发现。

## 调试建议

加 `-d` 可以看到更多调试信息：

```bash
nmap -d --script ./http-asset-fingerprint.nse -p80,443 target
```

脚本里可以用：

```lua
stdnse.debug1("message: %s", value)
stdnse.debug2("more detail")
```

调试阶段可以输出更多字段；稳定后再收敛输出，避免污染资产数据。

## 开发环境

用 Lua Language Server 写 NSE 会舒服很多。关键是让 LSP 知道 Nmap 的 `nselib` 在哪里，以及 NSE 的全局变量不是错误。

项目根目录可以放 `.luarc.json`：

```json
{
  "runtime": {
    "version": "Lua 5.4",
    "path": [
      "?.lua",
      "?/init.lua",
      "nmap/nselib/?.lua",
      "/usr/share/nmap/nselib/?.lua"
    ]
  },
  "workspace": {
    "library": [
      "/home/ihexon/1proxy/nmap/nselib",
      "/usr/share/nmap/nselib"
    ],
    "checkThirdParty": false
  },
  "diagnostics": {
    "globals": [
      "SCRIPT_NAME",
      "description",
      "author",
      "license",
      "categories",
      "portrule",
      "hostrule",
      "prerule",
      "postrule",
      "action"
    ],
    "disable": [
      "lowercase-global"
    ]
  }
}
```

这样 `require "http"`、`require "stdnse"`、`portrule`、`action` 这些就不会被误报。

## 常见坑

### 只扫了 80，脚本当然不会跑 443

NSE 只在 Nmap 扫描到的端口上运行。你只写：

```bash
nmap --script ./http-asset-fingerprint.nse -p80 target
```

那它就不会碰 443。

### 非标准端口需要服务识别

HTTP 在 `9000`，不加 `-sV` 可能不会被识别成 HTTP：

```bash
nmap -sV -p9000 --script ./http-asset-fingerprint.nse target
```

### preview 截断不等于 body 截断

```lua
preview = body:sub(1, 200)
```

只控制输出。真正控制读取的是：

```lua
max_body_size = ...
```

### hash 不一定完整

只要 body 被截断，hash 就不是完整页面 hash。所以一定要输出：

```text
hash_complete
truncated
```

## 小结

一个实用 NSE 脚本不需要很复杂，但要把边界想清楚：

```text
portrule 控制在哪跑
script-args 控制行为
http.get 做协议交互
max_body_size 控制成本
hash_complete 表达可信度
output_table 服务结构化解析
```

写 NSE 的目标不是写一个更复杂的 curl，而是把一次协议探测挂到 Nmap 的扫描结果上，成为资产发现流水线的一部分。
