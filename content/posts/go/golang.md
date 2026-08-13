---
title: "Go!"
date: "2026-08-13T12:00:00+08:00"
tags: ["go"]
title-images: []
ending-images: []
author: "烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
关于GO
<!--more-->
# Go 语言
## GMP模型
-G 是 goroutine，表示具体的执行任务；
-M 可以理解为 Go runtime 管理的操作系统线程，真正负责执行代码；
-P 是调度器运行所需要的处理器资源，保存调度相关的状态和本地运行队列。
GOMAXPROCS 决定同时有多少个 P 可以执行 Go 代码，例如 GOMAXPROCS=2 时，最多有两个 P 同时运行 Go 代码，P 会绑定到 M 上，由 M 执行 P 当前调度的 G。大量 G 可以被少量 M 和 P 调度执行，所以 goroutine 并不是一个 goroutine 对应一个操作系统线程。