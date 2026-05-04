---
title: "Hugo Blowfish 博客迁移与配置记录"
summary: "记录把个人博客从 Jekyll 迁移到 Hugo + Blowfish 的过程，包括主题配置、文章迁移、图片资源、GitHub Pages 部署、首页展示、TOC、favicon 和 SEO。"
description: "记录把个人博客从 Jekyll 迁移到 Hugo + Blowfish 的过程，包括主题配置、文章迁移、图片资源、GitHub Pages 部署、首页展示、TOC、favicon 和 SEO。"
date: 2026-05-04
draft: false
categories:
  - "blog"
tags:
  - "hugo"
  - "blowfish"
  - "github-pages"
  - "static-site"
---
最近把这个博客从 Jekyll 迁移到了 Hugo，并使用 Blowfish 作为主题。整个过程并不复杂，但有不少细节容易混在一起：Hugo 的资源目录、Blowfish 的配置入口、GitHub Pages 的部署方式、文章迁移后的图片路径、首页摘要、favicon、SEO，以及哪些内容应该交给主题配置，哪些内容应该用站点级覆盖。

这篇记录把这次迁移和配置经验整理下来，方便以后复盘。

<!--more-->

## 目录结构

这个站点使用 Hugo 常见的拆分配置方式：

```text
config/_default/hugo.toml
config/_default/languages.en.toml
config/_default/params.toml
config/_default/menus.en.toml
content/posts/
assets/
static/
themes/blowfish/
```

其中 `themes/blowfish/` 是主题本体，尽量不要直接修改。Blowfish 的示例配置和文档可以直接参考：

```text
themes/blowfish/exampleSite/content/docs
themes/blowfish/config/_default
```

真正属于自己站点的改动，应该放在 `config/`、`content/`、`assets/`、`static/` 或 `layouts/` 这些站点级目录下。这样后续更新主题时，冲突会少很多。

## 基础配置

`config/_default/hugo.toml` 主要放 Hugo 自己的配置，例如：

```toml
theme = "blowfish"
baseURL = "https://ihexon.github.io/"
enableRobotsTXT = true

[taxonomies]
  tag = "tags"
  category = "categories"
  author = "authors"
  series = "series"

[outputs]
  home = ["HTML", "RSS", "JSON"]
```

`baseURL` 在本地开发和线上部署时要注意。GitHub Pages 上线后应该使用最终域名；CI 构建时也可以显式传入：

```sh
hugo --gc --minify --baseURL https://ihexon.github.io/
```

`config/_default/languages.en.toml` 用来放站点标题、描述、作者和 logo：

```toml
title = "IHEXON BLOG"

[params]
  logo = "img/logo.png"
  description = "A BLACK CAT"

[params.author]
  name = "IHEXON"
  image = "https://avatars.githubusercontent.com/u/14349453"
```

Blowfish 的 header logo 通过 `resources.Get` 加载，所以 `logo = "img/logo.png"` 对应的是：

```text
assets/img/logo.png
```

这和 favicon 不一样。浏览器标签页里的 icon 不是通过 `logo` 配置控制的。

## assets 和 static 的区别

Hugo 里 `assets/` 和 `static/` 的语义不同。

`assets/` 里的文件会被 Hugo Pipes 和主题的资源处理逻辑读取，适合放：

```text
assets/img/logo.png
assets/img/default-social.png
assets/css/custom.css
```

Blowfish 的 header logo、默认社交分享图、部分背景图和需要图片处理的资源，更适合放在 `assets/`。

`static/` 则是原样复制到站点根目录，适合放固定路径资源，例如：

```text
static/favicon.ico
static/favicon-16x16.png
static/favicon-32x32.png
static/apple-touch-icon.png
static/android-chrome-192x192.png
static/android-chrome-512x512.png
static/site.webmanifest
```

Blowfish 的 favicon 文档也是这个思路：把同名文件放进站点自己的 `static/`，覆盖主题默认 favicon。

## Logo 和 favicon

顶部 logo 和浏览器标签页 icon 是两套东西。

顶部 logo：

```toml
[params]
  logo = "img/logo.png"
```

对应：

```text
assets/img/logo.png
```

如果想要圆形 logo，最干净的做法是直接把图片裁成透明圆形 PNG，而不是为了 logo 单独写 CSS 覆盖。JPG 没有透明通道，所以头像这类圆形图更适合生成 PNG。

favicon 则直接放在 `static/`：

```text
static/favicon.ico
static/favicon-16x16.png
static/favicon-32x32.png
static/apple-touch-icon.png
static/site.webmanifest
```

浏览器 favicon 缓存很顽固，改完后如果没有立即生效，可以用隐身窗口或强制刷新验证。

## 文章迁移

这次迁移的核心是把旧 Jekyll 文章整理成 Hugo 的 leaf bundle：

```text
content/posts/<slug>/index.md
content/posts/<slug>/images/
```

相比把所有图片都放到 `static/`，leaf bundle 更适合长期维护。每篇文章的 Markdown 和图片放在同一个目录里，迁移、重命名和删除文章时都更清晰。

文章中的图片链接也改成相对路径：

```md
![example](images/example.png)
```

每篇文章都补上了比较完整的 front matter：

```yaml
---
title: "文章标题"
summary: "用于首页和列表页展示的摘要。"
description: "用于 meta description 和 SEO 的描述。"
date: 2024-04-13
draft: false
categories:
  - "linux"
tags:
  - "glibc"
  - "gdb"
---
```

`summary` 很重要。Blowfish 的 `showSummary` 默认展示的是页面摘要，如果不主动写 summary，可能会从正文里截取内容，代码块、标题符号、Markdown 原文都有机会混进去。对于技术博客，手写一两句 summary 更稳定。

## 首页 Recent Articles

Blowfish 首页 Recent Articles 可以通过配置控制：

```toml
[homepage]
  showRecent = true
  showRecentItems = 40
  showMoreLink = true
  showMoreLinkDest = "/posts/"
```

列表摘要由 list 配置控制：

```toml
[list]
  showSummary = true
```

Recent 里的 tag 展示不是单独的 Recent 配置，而是走文章 meta partial。打开文章 taxonomy 后，Recent 列表也会显示 tags：

```toml
[article]
  showTaxonomies = true
  showCategories = false
  showTags = true
```

这里关掉 categories，只显示 tags，首页会更干净。

## 文章页 TOC

右侧 TOC 可以直接使用 Blowfish 配置：

```toml
[article]
  showTableOfContents = true
```

只要文章里有足够的 heading，Blowfish 的 single layout 就会渲染 TOC。这个不需要改主题模板。

## 固定顶部栏

Blowfish 的 header layout 有几个选项：

```toml
[header]
  layout = "basic"
```

可选值包括：

```text
basic
fixed
fixed-fill
fixed-gradient
fixed-fill-blur
```

如果想要类似 Blowfish 官方站那种固定、透明、带模糊的顶部栏，应该使用：

```toml
[header]
  layout = "fixed"
```

不要被 `fixed-fill-blur` 的名字误导。`fixed-fill-blur` 会叠加 `primary` 色背景，在某些配色下会明显发蓝；`fixed` 使用的是中性色透明背景，更接近真正的毛玻璃效果。

## GitHub Pages 部署

GitHub Pages 推荐使用官方 Actions + Pages 的方式部署静态站点。整体流程是：

1. checkout 仓库和主题 submodule。
2. 安装 Hugo extended。
3. 执行 Hugo 构建。
4. 上传 `public/` 作为 Pages artifact。
5. 使用 `actions/deploy-pages` 发布。

典型 workflow 大致如下：

```yaml
name: Deploy Hugo site to Pages

on:
  push:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - uses: actions/configure-pages@v5
        id: pages

      - uses: peaceiris/actions-hugo@v3
        with:
          hugo-version: latest
          extended: true

      - name: Build
        run: hugo --gc --minify --baseURL "${{ steps.pages.outputs.base_url }}/"

      - uses: actions/upload-pages-artifact@v3
        with:
          path: ./public

  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    needs: build
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

这里不需要 Jekyll，也不需要手动维护 `gh-pages` 分支。GitHub 仓库的 Pages 设置里，Source 选择 GitHub Actions 即可。

## 不要提交 Hugo 生成缓存

Hugo 处理图片后会生成：

```text
resources/_gen/
```

这些是构建产物，不是源码。对于这个站点，图片处理缓存经常出现在：

```text
resources/_gen/images/
```

本地构建后如果出现未跟踪的 `resources/_gen/images/posts/`，一般不需要提交。真正要提交的是 `content/`、`assets/`、`static/` 和 `config/` 里的源文件。

## SEO

Blowfish 已经自动处理了不少基础 SEO：

```text
title
meta description
canonical
OpenGraph
Twitter card
RSS
JSON feed
schema.org Article / WebSite
sitemap.xml
robots.txt
```

更值得自己补的是内容信号：

```toml
enableRobotsTXT = true
```

每篇文章写清楚：

```yaml
summary: "..."
description: "..."
tags:
  - "..."
```

站点级可以补默认社交图：

```toml
defaultSocialImage = "img/logo.png"
```

如果文章主体是中文，也应该把站点语言改成更准确的 locale，而不是一直使用 `en`。

## 最后的原则

Blowfish 本身功能很完整，绝大多数需求都可以通过配置完成：

```text
首页布局
Recent 文章数量
文章摘要
tags 展示
TOC
header 固定
favicon 覆盖
作者信息
社交链接
SEO 基础输出
```

真正需要改 `themes/blowfish/` 的情况并不多。优先使用配置；配置不够时，使用站点级 `layouts/partials/` 覆盖；最后才考虑改主题源码。

这次迁移之后，文章、图片和配置的边界都清楚了。后续维护主要就是继续写文章、补 summary、整理 tags，以及在必要时更新 Blowfish 主题。
