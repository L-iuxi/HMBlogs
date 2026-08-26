---
title: "Map和Channel"
date: "2026-03-25T12:00:00+08:00"
tags: ["go"]
title-images: []
ending-images: []
author: "烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
关于GO的Map和channel
<!--more-->
# MAP

## map底层结构
```bash
type hmap struct {
    count     int   //map中元素的个数
    flags     uint8 //标志位，记录map状态
    B         uint8 //bucket数量
    noverflow uint16    //溢出桶数量近似值
    hash0     uint32    //hash种子

    buckets    unsafe.Pointer   //指向bucket的指针
    oldbuckets unsafe.Pointer   //旧bucket
    nevacuate  uintptr  //表示扩容进度，小于该值的桶已完成迁移

    extra *mapextra //指向mapextra的指针，存放溢出桶
}

type mapextra struct {
    overflow    *[]*bmap
    oldoverflow *[]*bmap
    nextOverflow *bmap
}
```
## 在map中查找对应的keyValue
Go的map通过hash(key)计算出一个hash值，hash值的低位对应bucket下标，在对应bucket的8个槽中先比较hash值的高位和tophash，tophash可以排除大量不匹配的key，减少时间。找到tophash之后检查key是否相同，避免hash冲突找错key，如果符合返回对应值，如果不符合，检查overflow，直到找到key或者整个链条检查完。


## map扩容机制

向map中插入新key的时候，符合以下两个条件就会触发扩容

1. 装载因子超过阈值6.5触发双倍扩容，B+1，bucket数量翻倍
装载因子是哈希表中已经存储的元素数量 ÷ 哈希桶的数量，用来衡量哈希表有多“满”。

2. overflow bucket数量过多，触发等量扩容，B不会变，让排列更紧凑
overflow bucket（溢出桶）就是当一个 bucket 已经放满 8 个键值对，但又有新的 key 哈希到了这个 bucket 时，额外拿来存放这些数据的 bucket。
```bash
bucket 0
┌──────────────────────┐
│ key1 │ key2 │ ... │key8│
└──────────┬───────────┘
           │
           ↓
      overflow bucket
      ┌──────────────────┐
      │ key9 │ key10 │...│
      └──────────────────┘
```
map的扩容是**渐进式**，再触发扩容时不会一次性迁移数据，而是下一次操作的时候顺便迁移一两个桶的数据，将庞大的扩容成本迁移到多次操作之中，减少了服务的瞬间延迟
5
## map的安全性
*map并非线程安全，map的底层不是不可分割的原子操作*
Go的普通 map 没有提供并发访问时的同步机制，因此多个 goroutine 同时读写可能产生数据竞争，甚至直接触发运行时的 concurrent map read and map write。

可以通过加sync.RWMutex来保证读写安全

因为同步会带来额外开销，而很多场景下 map 根本不需要并发保护；把同步责任交给使用者，可以让普通 map 在单线程/自行同步的场景下保持更高性能和更简单的语义。

# Channel

## CSP
csp为并发编程模型，通过通信共享内存而不是通过共享内存来通信

## 底层模型
channel的底层是一个 hchan 结构体
```bash
type hchan struct {
    qcount   uint           // 当前队列中元素数量
    dataqsiz uint           // 环形队列容量
    buf      unsafe.Pointer // 环形队列缓冲区

    elemsize uint16         // 每个元素大小
    closed   uint32         // channel 是否关闭

    elemtype *_type         // 元素类型

    sendx    uint           // 下一次发送的位置
    recvx    uint           // 下一次接收的位置

    recvq    waitq          // 等待接收的 goroutine
    sendq    waitq          // 等待发送的 goroutine

    lock     mutex          // 保护 channel
}
```
**环形缓冲区**：buf指针指向环形缓冲区，sendx和recvx记录下一次发送和接受的位置

**互斥锁**：所有读写操作都需要先获取锁，go内部通过调度减少性能开销

**等待队列**：sendq和recvq分别用来存储发送阻塞的channel和接受阻塞的channel，这些队列用双向链表实现，条件满足时唤起对应的gourtine

**sudog是什么**：记录哪个 goroutine 因为什么原因正在这个 channel 上等待？的结构体

channel怎么唤醒阻塞的gourtine：

阻塞的 goroutine 会通过 sudog 加入 channel 的 sendq 或 recvq。当另一方进行发送或接收时，runtime 会从对应等待队列中取出 sudog，通过 goready 将对应 goroutine 从等待状态转为 runnable，之后由 Go 调度器重新调度执行。

## 发送数据过程
向某个channel发送数据之后

- 首先检查channel的recvq是否为空，如果不为空，证明有等待接受的groutine，那么优先向这个groutine传递数据，跳过缓冲区
  
- 没有接受者则写入缓冲区，检查缓冲区是否还有位置，当前队列中元素数量小于队列容量的时候，继续写入sendx下标位置，调用gopark让当前goutine阻塞，让出cpu
  
- 如果缓冲区满了，创建一个sudog，加入sendq阻塞等待调用gopark让当前goutine阻塞，让出cpu
  
  读取数据的过程与发送数据流程大致相同

- 向已经关闭的channel写入数据会触发panic，向已经关闭的channel读数据，如果缓冲区有数据仍然能读到，只有返回的ok为false的时候，读出的数据无效

## select的执行机制
select会检查哪个case满足条件可以执行，如果有多个case满足条件，select会随机选择一个执行，如果没有case可以执行，要么default，没有default的时候阻塞等待

注册select的时候

创建select -> 注册case -> 执行select -> 释放select

case随机化➕双重循环检测：

定义select的时候会定义scase，存放所有case数据包括default，在runtime层面实现

case会随机排序，第一次轮询检测的时候检查是否有case符合要求，如果没有进行第二次检测，第二次检测把当前groutine加入等待接收队列或者等待发送队列，调用gopark让出cpu
