---
title: "零拷贝"
date: "2026-09-13T10:00:00+08:00"
tags: ["操作系统"]
title-images: []
ending-images: []
author: "烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!--more-->
# 零拷贝
传统的IO模型 read(),write(),文件发送到网络，需要经过四次拷贝，四次上下文切换：
```bash
磁盘---->内核缓冲区---->用户缓冲区---->socket内核缓冲区---->网卡
```
其中第一次和最后一次是DMA拷贝，中间两次是CPU拷贝
> DMA——Direct Memory Access直接内存访问。让硬件设备直接把数据搬到内存，而不是CPU一个字节一个字节的搬运
为了提高这个过程的效率，零拷贝技术诞生了。零拷贝旨在通过一次系统调用，将磁盘读取和网络传输合并为一个操作。减少上下文的切换，减少了内存拷贝的次数

Linux下，常见的零拷贝方式有两种：
sendfile，mmap
## mmap
mmap实际上减少了一次内核到用户空间拷贝
```bash
磁盘---->内核缓冲区---->用户缓冲区---->socket内核缓冲区---->网卡
```

还是这个过程，mmap通过让用户空间和内核页映射同一块物理地址，从而访问到磁盘内数据，减少了一次数据从内核到用户态的拷贝。
所以mmap实际上是3次拷贝
```bash
磁盘---->用户缓冲区---->socket内核缓冲区---->网卡
```
## sendfile
sendfile实际上也是只减少了一次拷贝，相比较于mmap，sendfile直接将数据从内核缓冲区拷贝到socket缓冲区
```bash
磁盘---->内核缓冲区---->socket内核缓冲区---->网卡
```
这个过程实际上也是三次拷贝，但是在现代Linux中，sendfile可以优化，实现类似于
```bash
磁盘---->socket内核缓冲区---->网卡
```
两次拷贝都是DMA拷贝而没有CPU拷贝，实现真正的零CPU拷贝，所以一般说sendfile可以实现真正的零拷贝

而sendfile一般通过**Scatter-Gather**的方式实现这种功能。sendfile认为既然用户程序不修改文件内容，只是复制文件，那为什么非要把文件拷贝到用户缓冲区？所以直接将数据从内核缓冲区拷贝到socket缓冲区。Scatter-Gather则认为这一步也可以省略，可以从内核缓冲区到socket而不需要CPU拷贝。
Scatter-Gather的思想是不要求数据必须连续存放，允许一次IO操作操作多个不连续的区域，Scatter-Gather中前者是分散的意思，后者是聚集的意思。所以一个IO操作可以引用多个不连续的内存区域，而不需要先把他们复制成一块连续内存。
```bash
磁盘
 │
 │ DMA
 ↓
内核页缓存
 │
 │ 直接引用这些页面
 ↓
Socket
 │
 │ DMA
 ↓
网卡
```