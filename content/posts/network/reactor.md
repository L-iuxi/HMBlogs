---
title: "Reactor"
date: "2026-08-13T12:00:00+08:00"
tags: ["reactor"]
title-images: []
ending-images: []
author: "烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
关于Reactor
<!--more-->
# Reactor
Reactor是干什么的：
Reactor 的核心思想是把 IO 事件和业务处理解耦，通过 IO 多路复用统一监听大量连接。当大量连接处于 IO 等待状态时，并不需要为每个连接创建一个线程，而是由少量线程通过 epoll 等机制等待多个连接的事件，事件就绪后再分发给对应的处理逻辑。这样可以减少大量线程带来的栈空间、线程调度和上下文切换开销，提高高并发连接场景下的资源利用率。