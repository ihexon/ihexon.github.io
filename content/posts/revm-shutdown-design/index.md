---
title: "如何设计虚拟机的关机流程"
summary: "从 revm 的一次关机流程重构出发，讨论虚拟机运行时里 graceful shutdown、force shutdown、等待语义和宿主侧服务生命周期应该如何拆分。"
description: "从 revm 的一次关机流程重构出发，讨论虚拟机运行时里 graceful shutdown、force shutdown、等待语义和宿主侧服务生命周期应该如何拆分。"
date: 2026-05-16
lastmod: 2026-05-19
draft: false
categories:
  - "virtualization"
tags:
  - "design"
  - "virtualization"
  - "revm"
---

虚拟机的关机流程很容易被写成一团：收到用户中断，发一个信号，关几个服务，杀掉虚拟机，然后退出。

这看起来能工作，但一旦运行时变复杂，就会暴露出许多问题：日志丢失、磁盘没来得及 sync、guest-agent 没跑完整、宿主侧代理提前退出、第二次 Ctrl-C 也不能立刻结束。

这次 revm 的关机流程重构，本质上不是修一个 Go 代码问题，而是重新思考一个虚拟机运行时应该如何表达“关机”。

<!--more-->

## 关机不是一个动作

很多 bug 都来自一个错误抽象：把“关机”当成一个动作。

实际上，对于一个虚拟机运行时来说，关机至少包含三种完全不同的语义。

第一种是 **请求 guest 自己关机**。

这是一种 polite request。host 告诉 guest：“请你开始收尾。” guest-agent 可能会 flush 日志、停止服务、sync filesystem，最后 reboot 或 poweroff。

第二种是 **等待 guest 退出**。

这是 host 侧的等待行为。host 不一定在做什么，只是在等 VMM、hypervisor、子进程或者某个阻塞调用返回。

第三种是 **放弃等待并强制收尾**。

这意味着 host 已经不再相信 guest 能及时退出，或者用户已经不想等了。此时运行时要中断等待、停止宿主侧代理、释放 socket、关闭转发器，必要时 kill 子进程。

这三件事如果混成一个 cancel 或一个 signal，流程就会变得很脆。

## revm 的设计落点

revm 当前的实现不是把“关机”做成一个万能按钮，而是把它拆成一组行为契约。

backend 暴露的接口大致是这样：

```go
Start(vmWaitAbortCtx context.Context) error
RequestShutdown(ctx context.Context) error
ForceStop(ctx context.Context) error
```

这组接口的重点不是代码形式，而是它强迫调用方回答三个不同的问题。

`Start` 表达的是：

```text
host 是否还要继续等 VM 自己退出？
```

`RequestShutdown` 表达的是：

```text
是否要礼貌地通知 guest 进入关机路径？
```

`ForceStop` 表达的是：

```text
host 是否决定放弃 graceful wait，进入有界收尾？
```

这三个问题不能合并。合并之后，第一次 Ctrl-C 就很容易同时变成“通知 guest 关机”和“host 不等了”，结果是 guest 还没来得及 sync，host 侧代理已经开始退出。

revm 因此把运行期分成两条生命周期。

第一条是 VM wait lifecycle。它只关心 host 是否还要等待 VM 退出。

第二条是 host services lifecycle。它控制管理 API、网络栈、代理、metadata server 这些宿主侧服务何时停止。

第一次 Ctrl-C 或管理 API stop request 只进入 graceful request：

```text
request guest shutdown
```

这时 host services 仍然活着，VM wait 也仍然继续。这个选择很重要：guest 的关机路径可能还需要日志通道、网络代理、管理通道或其他 host-side plumbing。如果 host 过早 teardown，所谓 graceful shutdown 本身就被破坏了。

只有当 guest 自己完成收尾并退出后，host 才停止附属服务并返回。

第二次 Ctrl-C、parent process 消失、host service 失败这类事件才进入 force path。force path 的本质是：

```text
abort VM wait
stop host services
return control to caller
```

在当前 libkrun backend 里，graceful request 最终会通过一个 guest signal 交给 guest-agent。guest-agent 在 guest 内部完成 signal propagation、disk sync 和 reboot。这里的实现细节可以替换，但行为契约不应该变：host 发出的是请求，guest 执行自己的关机协议。

这里用时序图表达会更清楚，但它应该画行为边界，而不是画代码调用栈：

{{< mermaid >}}
sequenceDiagram
    participant User as User/API
    participant Host as revm host runtime
    participant Guest as guest shutdown path
    participant Services as host services

    User->>Host: first Ctrl-C or stop request
    Host->>Guest: request graceful shutdown
    Note over Host,Services: keep VM wait and host services alive
    Guest-->>Host: guest syncs, reboots, and VM exits
    Host->>Services: stop after VM exit
    Host-->>User: return

    User->>Host: second Ctrl-C / owner gone / fatal host error
    Host->>Host: abort VM wait
    Host->>Services: stop immediately
    Host-->>User: return quickly
{{< /mermaid >}}

这里最容易误解的是 force path。force 不一定意味着底层 backend 必须有一个完全不同的“硬关机信号”。它首先是一种 host 侧承诺：不再无限等待 graceful path，开始停止依附于这次 VM run 的宿主侧资源，并把控制权还给调用方。

## 第一次 Ctrl-C 应该是什么

对于交互式命令，Ctrl-C 往往有两种语义。

第一次 Ctrl-C 通常应该是：

> 我想结束它，请正常退出。

第二次 Ctrl-C 才是：

> 我不想等了，立刻停。

这个习惯很重要。它给运行时提供了一个自然的两阶段退出协议。

对于虚拟机来说，第一次 Ctrl-C 不应该直接解释成“host 不再等待 VM”。它更适合解释成：

```text
request guest shutdown
```

也就是通知 guest-agent 进入关机路径。guest 内部应该有机会执行：

```text
stop services
flush logs
sync filesystem
reboot / poweroff
```

host 此时仍然应该继续等待 VM 自己退出。

如果第一次 Ctrl-C 直接打断 host 的等待路径，那么 guest-agent 可能还没来得及跑完整，宿主侧就已经开始 teardown。用户看到的现象通常是日志顺序混乱、shutdown 日志缺失，或者某些资源像是被硬切掉。

## 第二次 Ctrl-C 应该是什么

第二次 Ctrl-C 的语义应该非常明确：

```text
force shutdown
```

它不再是一个 polite request，而是 host 侧的决策：

```text
stop waiting for guest
tear down host services
return to user as soon as possible
```

这里的重点是“stop waiting”，而不是“再请求一次 guest 关机”。

如果 guest 能正常关，第一次 Ctrl-C 已经足够。如果第二次 Ctrl-C 发生了，说明用户已经表达了不愿意继续等待。此时运行时应该把控制权还给用户。

## 等待本身也需要被设计

虚拟机运行时里经常有一个阻塞点：

```text
start VM and wait until it exits
```

这个阻塞点可能来自不同实现：

- 当前进程内的 VMM 调用
- libkrun / qemu / firecracker 之类的 backend
- 一个子进程
- 一个 RPC session
- 一个管理 socket

不管实现细节是什么，host 都需要表达一个问题：

> 我还要不要继续等这个 VM 自己退出？

这和“请求 guest 关机”不是同一个问题。

请求 guest 关机是发给 guest 的消息；停止等待是 host 自己的控制流。

所以设计上最好给“等待 VM 退出”一个独立的 abort signal。它可以是 context，可以是 channel，可以是 eventfd，也可以是 supervisor 内部的状态转换。具体机制不重要，重要的是语义：

```text
abort VM wait != request guest shutdown
```

这个区分能避免许多隐性 bug。

## 宿主侧服务也有自己的生命周期

一个现代虚拟机运行时通常不只是启动 VM。它还会启动一堆 host-side services：

- 网络栈
- 端口转发
- 管理 API
- ignition / metadata server
- SSH proxy
- container API proxy
- 日志转发
- 文件系统共享

这些服务依附于 VM，但不等同于 VM。

它们的生命周期应该是：

```text
VM 还在运行 -> host services 应该活着
VM 已经退出 -> host services 应该收掉
强制退出 -> host services 应该尽快收掉
host service 自己失败 -> VM run 应该进入失败/强制收尾路径
```

这意味着 host services 也需要一个独立的生命周期控制。

如果把 host services 的生命周期和 VM wait 混成一个信号，第一次 Ctrl-C 时就很容易出现错误：guest 还没关完，metadata server 或网络代理先被停掉了。

对于某些 guest 关机路径来说，这些服务甚至可能仍然是必要的。例如 guest-agent 需要通过 virtio port、vsock、网络或管理通道完成最后一次通信。host 提前 teardown 会破坏 graceful shutdown 本身。

## 一个更稳的状态机

revm 当前的退出流程可以抽象成下面这个状态机：

{{< mermaid >}}
stateDiagram-v2
    [*] --> Running

    Running --> ShutdownRequested: first SIGINT/SIGTERM
    Running --> ShutdownRequested: management /v2/stop
    Running --> Forcing: parent process disappeared
    Running --> Forcing: host service failed

    ShutdownRequested --> Finished: guest syncs and exits
    ShutdownRequested --> Forcing: second SIGINT/SIGTERM
    ShutdownRequested --> Forcing: host service failed

    Forcing --> Finished: abort VM wait and stop host services

    state Running {
        [*] --> HostServicesAlive
        HostServicesAlive --> VMStartWaiting
    }
{{< /mermaid >}}

这里有几个关键点。

`running -> shutdown requested` 是 graceful path。它应该通知 guest，而不是中断 host 的等待。

`shutdown requested -> finished` 是 guest 自己退出。此时 host 停止附属服务并返回。

`shutdown requested -> forcing` 是放弃等待。它可以由第二次 Ctrl-C 触发，也可以由 host service 失败这类 fatal condition 触发。

`running -> forcing` 是当前实现里另一个重要分支：如果 launcher 或 parent process 消失，revm 不再假装还处在一个有人负责收尾的交互式 session 里，而是直接进入 force cleanup。

`forcing -> finished` 是 host 侧强制收尾。它的目标不是优雅，而是 bounded cleanup。

## 超时是否必要

两次 Ctrl-C 之外，很多运行时还会加一个 timeout。

例如：

```text
first Ctrl-C
  -> request guest shutdown
  -> wait up to 30 seconds
  -> force shutdown
```

这是否应该做，取决于产品语义。

对于交互式 CLI，我更喜欢不默认加很短的超时，而是提示用户：

```text
waiting for guest shutdown; press Ctrl-C again to force
```

原因是用户就在终端前，可以自己决定要不要等。

对于 daemon、CI、系统服务，timeout 更有必要。因为没有人在旁边按第二次 Ctrl-C，运行时必须保证最终能回收资源。

当前 revm 没有给第一次 Ctrl-C 后的 graceful wait 加固定超时。它选择提示用户再次 Ctrl-C 来 force shutdown。只有 force path 里的 `ForceStop` 调用有一个 3 秒 timeout，用来约束 host 侧的 force request。

所以 timeout 不是关机设计的核心，而是策略层。核心仍然是区分：

```text
request graceful shutdown
abort waiting
cleanup host resources
```

## 父进程消失时不必装作 graceful

还有一种特殊情况：launcher 或 parent process 消失了。

这和用户第一次 Ctrl-C 不一样。

第一次 Ctrl-C 时，用户还在，运行时还被某个前台交互流程拥有。此时等待 guest 优雅退出是合理的。

但如果 parent process 已经消失，运行时通常应该尽快 force shutdown。因为 owning process 已经没了，继续长时间等待会让后台资源悬挂。

所以 parent exit 更像：

```text
force shutdown
```

而不是：

```text
request guest graceful shutdown and wait forever
```

这是一个 ownership 问题，不是 guest 是否支持 graceful shutdown 的问题。

## 不要让机制吞掉语义

这次重构里最容易误导人的地方是 `context`。

在 Go 里，`context.Context` 是一个很方便的取消机制。但机制本身不携带业务语义。你把它叫 `ctx`，它就什么都能表示：

- 用户取消
- VM wait abort
- host services teardown
- request guest shutdown
- parent process exit
- backend failure

一旦这些语义都塞进同一个 `ctx`，代码就很难回答一个问题：

> cancel 这个 ctx 到底是在请求 guest 关机，还是在放弃等待 guest？

这个问题不只存在于 Go。

换成其他语言也是一样。一个 channel、一个 promise cancellation、一个 cancellation token、一个 eventfd、一个 unix signal，如果名字和状态机不清楚，都可能变成“万能退出按钮”。

万能退出按钮的坏处是：它太容易工作了，直到你需要 graceful shutdown。

## 可迁移的设计原则

我从这次重构里总结出的原则是：

### 1. 把 request 和 abort 分开

请求 guest 关机是 request。

停止 host 等待是 abort。

它们可以先后发生，但不应该是同一个动作。

### 2. 把 VM 生命周期和 host services 生命周期分开

VM 退出后，host services 应该停止。

但请求 VM 退出时，host services 不一定应该马上停止。

### 3. 第二次中断必须有明确语义

第一次中断 request graceful shutdown。

第二次中断 force shutdown。

不要让第二次中断只是重复发送同一个 shutdown signal。

### 4. force path 必须能尽快返回

force shutdown 的价值在于 bounded behavior。

如果 force path 仍然可能无限等待，那它就不是 force。

### 5. parent exit 是 ownership 结束

父进程消失通常应该触发 force cleanup。

这条路径不应该和用户第一次 Ctrl-C 使用同一套 graceful wait 语义。

### 6. 命名要暴露状态机

好的名字应该让读者看到控制流：

```text
requestGuestShutdown
abortVMWait
stopHostServices
forceVMRun
finishVMRun
```

坏的名字会隐藏设计：

```text
ctx
stop
shutdown
cancel
done
```

这些词不是不能用，而是不能在复杂生命周期里单独使用。

## 小结

虚拟机的关机流程不是“收到信号然后退出”这么简单。

更稳的设计是把它拆成三层：

```text
guest graceful shutdown request
host-side VM wait control
host services lifecycle
```

第一次 Ctrl-C 只进入第一层。第二次 Ctrl-C 才进入后两层。

这样设计后，guest 有机会完整执行自己的 shutdown path，host 又保留了强制退出的能力。无论底层是 libkrun、qemu、firecracker，还是一个自研 VMM 子进程，这个设计都可以迁移。

真正重要的不是用了哪种语言、哪个 context、哪个 channel，而是状态机本身足够诚实：它清楚地区分了“请你关机”和“我不等了”。
