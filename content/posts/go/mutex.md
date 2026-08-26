---
title: "mutex"
date: "2026-03-26T12:00:00+08:00"
tags: ["go"]
title-images: []
ending-images: []
author: "烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
关于GO的mutex
<!--more-->
# mutex

## 结构
```bash
type mutex struct {
    state int32
    sema   uint32
}
```
state表示锁的状态，有锁定，被唤醒，饥饿状态

sema表示信号量，mutex阻塞队列的定位，实现groutine的阻塞和唤醒

## 模式
Mutex基本上有两种模式：饥饿模式和正常模式：

- 正常模式：新请求的锁会和头部等待的groutine竞争，在等待期间会自旋几次，如果此时锁资源恰好被释放，那么新的请求有概率抢到锁，这样头部等待的groutine可能需要等很久才能抢到锁。这种方式吞吐量极高。
- 饥饿模式：当一个groutine在队列中等待超过1ms，就会切换到这种模式。在这种模式下，解锁后锁的所有权会给头部groutine，新的请求groutine排在队尾等待
 
当等待队列为空，或者获取锁的时间小于1ms，就会切换回正常模式

## sync.once
保证函数不管在多少个groutine中被调用，都只执行一次

```bash
type once struct {
    done uint32
    m  mutex
}
```

## WaitGroup
waitgroup用来等待一组groutine全部执行完成

调用 `Add()` 来增加计数值groutine数量

调用 `Done()` 来减少计数值groutine数量

`Wait()` 方法会检查这个计数值，当他不等于0的时候，groutine会被挂起，直到`Done()` 后计数值为0，通知当前等待的所有groutine停止阻塞等待
```bash
type WaitGroup struct {
    noCopy noCopy
    state atomic.Uint64
    sema  uint32
} 
```
nocopy：用于检查waitgroup是否被复制，被复制后会导致状态不一致，可能引发程序错误
state：高32位是计数器，激励等待的groutine数量，低32位是调用`Wait()` 方法之后被阻塞的groutine数量

## sync.map
针对多个线程同时读写map的场景，有sync.map,避免普通map并发读写导致的异常或者panic

它通过内部的 read-only 和 dirty 等结构减少锁竞争，但不意味着所有场景下都比普通 map 加 mutex 更快。sync.map针对多读少写的操作

sync.map的思路是用空间换时间，通过read和dirty两个结构实现快速读写
```bash
type Map struct {
    mu     Mutex
    read   atomic.Pointer[readOnly]
    dirty  map[any]*entry
    misses int
}
```
miss记录在read中读取值的时候没有命中的次数，到一定程度之后触发同步

read是一个只读的map，提供无锁的并发读取，速度极快

写操作先通过锁操作一个dirtymap，当dirtymap的数据过多或者读到一个不存在的key的时候，会将数据迁移并覆盖旧read，完成一次数据同步

read是只读的，当用户删除一个键的时候，通过把这个建在read中entry改为nil，只要是nil就代表该建不存在，而在需要基于read重建dirty的时候，会检查所有entry为nil的建，标记为enpunged，表示该建不再复制到新的dirty中。如果后续要写一个标记为enpunged的建，必须先回退到nil，再进行写入