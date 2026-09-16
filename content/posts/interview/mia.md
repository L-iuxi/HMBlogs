---
title: "interview"
date: "2025-03-16T12:00:00+08:00"
tags: ["interview"]
title-images: []
ending-images: []
author: "开心的面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->

<!--more-->
1. Go 抢占式调度

Go 的 goroutine 是怎么实现抢占的？
Go 现在支持异步抢占。对于长时间运行、不主动让出 CPU 的 goroutine，Go runtime 可以通过抢占机制让它暂停，把 CPU 让给其他 goroutine。Go 1.14 开始引入了基于信号的异步抢占，避免一个 CPU 密集型 goroutine 长时间占用 P。导致同一个 P 上其他 goroutine 长时间得不到调度。

2. Linux CFS / vruntime

CFS 怎么决定下一个运行哪个进程？
CFS 会给 runnable 进程维护一个 vruntime，可以理解成进程根据实际运行时间和优先级折算出来的虚拟运行时间。调度时倾向于选择 vruntime 最小的进程运行，让不同进程获得相对公平的 CPU 时间。CFS 不是简单的时间片轮转，而是根据 vruntime 选择相对“欠 CPU”最多的任务。
较新的 Linux 内核已经逐步从传统 CFS 调度思想演进到 EEVDF，但很多面试仍然会以 CFS/vruntime 考察公平调度的基本思想。

3. SELECT FOR UPDATE

SELECT ... FOR UPDATE 是什么？

FOR UPDATE 是一种当前读，会读取当前最新版本的数据，并对符合条件的记录加排他锁，其他事务如果要修改这些记录，需要等待当前事务提交或者回滚。普通 SELECT 是一致性读，主要通过 MVCC 和 Read View；FOR UPDATE 是当前读，不使用普通一致性读的 Read View。
例如：

SELECT * FROM user
WHERE id = 1
FOR UPDATE;

可以理解：

查当前数据
+
把它锁住
+
我后面准备修改

4. Redis Cluster：Hash Slot

Redis Cluster 怎么决定一个 key 存在哪个节点？
Redis Cluster 把整个 key 空间划分成 16384 个 hash slot。Redis 会对 key 计算 CRC16，然后对 16384 取模得到对应的 slot，再根据 slot 到节点的映射关系找到具体节点。

5. Redis Cluster：为什么跨 Slot 不能保证原子性？

key1 和 key2 在不同节点，能不能直接通过 Redis Cluster 保证两个操作原子完成？
因为两个 key 在不同节点，需要分别在不同 Redis 节点执行。Redis Cluster 的事务和 Lua 脚本要求涉及的 key 通常位于同一个 hash slot，Cluster 本身不会提供跨节点的分布式事务来保证两个节点上的操作要么全部成功、要么全部失败。

6. SkipList + ZRANGE

Redis 为什么使用跳表？

跳表本质上是多层链表，通过增加索引层来减少查找需要遍历的节点数量。它的平均查找、插入、删除复杂度是 O(logN)，实现相对简单，而且非常适合有序数据的范围查询。
红黑树也是：O(logN)Redis 选择跳表很重要的一个原因是：实现简单，而且范围查询比较方便。
ZRANGE key 0 99 为什么是 O(logN + M)？
先通过跳表找到起始位置，大约 O(logN)，然后连续遍历 M 个元素，所以总复杂度是 O(logN + M)。

7. TCP 重复 SYN

Server 已经 SYN-RECEIVED，又收到 Client 的 SYN，怎么办？
这种情况通常是之前的 SYN-ACK 丢失，导致客户端重传 SYN。服务器不会因为这个就创建一个新的连接并关闭原来的连接，而是按照 TCP 状态处理这个重复 SYN，通常重新发送 SYN-ACK，继续完成原来的三次握手。
