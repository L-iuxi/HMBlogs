---
title: "Map和Channel"
date: "2026-08-25T12:00:00+08:00"
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
```

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

## map的安全性
*map并非线程安全，map的底层不是不可分割的原子操作*
Go的普通 map 没有提供并发访问时的同步机制，因此多个 goroutine 同时读写可能产生数据竞争，甚至直接触发运行时的 concurrent map read and map write。

可以通过加sync.RWMutex来保证读写安全

因为同步会带来额外开销，而很多场景下 map 根本不需要并发保护；把同步责任交给使用者，可以让普通 map 在单线程/自行同步的场景下保持更高性能和更简单的语义。

# Channel
