---
title: "关于HMETCD——类etcd的kv存储项目"
date: "2026-08-13T12:00:00+08:00"
tags: ["Raft", "ETCD"]
title-images: []
ending-images: []
author: "喷了很多发胶的烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
一些比较ran的项目流程问题
<!--more-->
1. commitIndex 和 lastApplied 到底是什么？
标准答案

commitIndex 表示 Raft 层已经确认提交到哪条日志；lastApplied 表示当前节点的状态机已经实际执行到哪条日志。Leader 和 Follower 都会 Apply 已提交日志，两者不是只有 Leader 执行。

例如：

Raft Log:
1 2 3 4 5 6 7 8 9 10

commitIndex = 10
lastApplied = 7

说明：

1~10：Raft 已经提交
1~7 ：状态机已经执行
8~10：等待 Apply

ApplyLoop：

8 → 9 → 10

最后：

lastApplied = 10
你今天的问题

你一开始说：

只有 Leader 可以 Apply。

这是错的。

正确的是：

只有 Leader 接收客户端写请求并发起日志复制；所有节点都会将 committed log Apply 到自己的状态机。

2. Follower 到底能不能“写日志”？
标准答案

Follower 不能直接处理客户端写请求、不能自己生成业务日志，但可以把 Leader 通过 AppendEntries 发送过来的日志追加到自己的 Raft Log，并持久化。

所以：

Client
 ↓
Leader
 ↓
生成log
 ↓
AppendEntries
 ↓
Follower
 ↓
追加自己的Raft Log

你今天说：

follower不能写日志

这个容易被面试官抓。

以后统一说：

Follower 不接受客户端写请求，但会复制并持久化 Leader 的日志。

3. Raft Log 和 WAL 到底什么关系？

这是你今天答得还不错，但需要进一步规范的问题。

标准答案

Raft Log 是 Raft 协议中的逻辑日志，记录 Term、Index、Command 等信息；WAL 是持久化 Raft 状态和日志的一种实现机制。我的 HMETCD 使用 WAL 保证节点宕机后能够恢复 Raft 状态和日志。

例如：

Raft Log：

index=10
term=5
command=Put(foo,A)

WAL：

把这些状态持久化到磁盘

所以不要简单说：

WAL 和日志不是一类东西。

更准确：

Raft Log 是逻辑概念，WAL 是持久化机制。

4. Leader 收到 Put，什么时候返回成功？

这是非常重要的一题。

标准回答

对于你的 HMETCD，可以描述成：

Client
 ↓
Leader
 ↓
rf.Start()
 ↓
生成Raft Log
 ↓
WAL持久化
 ↓
复制给多数节点
 ↓
commitIndex推进
 ↓
ApplyLoop
 ↓
MVCC
 ↓
Badger
 ↓
返回结果
 ↓
Client

你项目如果是通过 Apply 结果 channel 返回，那么：

不能仅仅因为 Leader 自己写 WAL 成功就返回成功，而是要等这条日志真正 Commit 并 Apply 成功后，再返回业务结果。

这和“Raft 已经复制多数派”是两个概念。

5. 为什么新 Leader 不能直接提交旧 Term 的日志？

这是你今天答得比较好的一题。

标准答案

Raft 规定：

Leader 只能直接通过多数派复制来提交当前 Term 的日志。

原因是：

旧 Term 的日志即使已经复制到了多数节点，也不能仅凭这个事实判断它之前是否已经被提交。

例如：

旧Leader Term 4

index=10
复制：
A √
B √
C √

旧 Leader 还没来得及推进 commit 就挂了。

新 Leader Term 5：

不能仅因为 index=10 在多数节点存在
就直接认为它已经 committed

新 Leader 可以提交自己的 Term 5 日志：

index=11 term=5

一旦 index=11 被多数节点复制并提交：

commitIndex = 11

那么：

index=10
index=11

就会一起 Apply。

6. 不同节点的 Badger 不一样，为什么最终还能一致？

这个其实是你今天主动问出来的一个很好的问题。

标准答案

Raft 并不是让多个 BadgerDB 直接保持一致，而是让所有节点获得相同顺序的 committed log。然后每个节点的状态机按照相同顺序执行这些日志，最终得到相同的逻辑状态。

结构：

          Raft Log
         /   |   \
        /    |    \
      A      B      C
   Badger  Badger  Badger

真正复制的是：

Raft Log

不是：

BadgerDB

所以即使：

A磁盘慢
B磁盘快
C网络延迟高

只要最终执行：

Log 1
Log 2
Log 3
Log 4

而且状态机是确定性的，最终逻辑结果就应该一致。

7. 为什么状态机必须确定性？

这是上面那道题的延伸，非常容易被问。

假设 Raft 日志是：

Put(foo,A)

如果你的 Apply 过程中：

revision := time.Now().UnixNano()

那么：

A:
revision = 100

B:
revision = 200

日志一样，但是状态不同。

所以：

复制状态机要求相同日志序列经过确定性的状态机执行后得到相同结果。

尤其你 HMETCD 有：

revision
MVCC
lease
watch

这些地方要特别注意不能随便依赖：

time.Now()
rand
goroutine执行顺序
8. Apply 和 applyIndex 的持久化一致性

这是我认为你今天最薄弱、也最值得补的一题。

你已经意识到问题了，但还没有完全形成答案。

假设：

Apply log 100

① Badger写成功
② applyIndex=100写成功

如果中间宕机：

情况 A
Badger成功
applyIndex失败

重启：

applyIndex=99
Badger已经有log100的数据

于是 log100 可能再次 Apply。

情况 B
applyIndex成功
Badger失败

重启：

applyIndex=100

但是Badger没有log100的数据

系统反而会认为：

我已经执行过了。

这更加危险。

更好的设计

把状态机数据更新和 appliedIndex 放到同一个底层事务中提交。

例如：

Badger Transaction
 ├── 写 MVCC 数据
 └── 写 appliedIndex
        ↓
     Commit

要么：

两个都成功

要么：

两个都失败

这样恢复时：

appliedIndex = 99

就从：

log 100

继续执行。

9. Watch 为什么不能在 Raft Commit 后马上通知？

你今天这题回答方向是对的。

标准答案

因为：

Raft Commit

只代表：

这条日志已经被共识层确认。

不代表：

MVCC修改成功
Badger持久化成功

所以应该：

Raft Commit
 ↓
Apply
 ↓
MVCC修改
 ↓
底层存储成功
 ↓
Watch通知

否则可能：

Watch收到：
foo = B

但是：
Badger写失败

客户端就会看到一个不存在的状态。

10. Watch 最容易漏事件的竞态

这个是你今天完全没真正答出来的。

例如：

当前 revision = 100

客户端创建：

Watch(foo, 100)

同时另一个线程：

Put(foo,B)
revision = 101

如果执行：

① 读取revision
② 发生Put
③ 注册Watcher

那么：

revision=101

可能已经发生，但 Watcher 还没注册。

结果：

事件丢失

所以 Watch 的核心是：

Watcher 注册和历史检查/实时事件切换之间必须有正确的并发控制，保证从历史追赶切换到实时监听时不会出现空窗期。

你项目里的：

未对齐 watcher
        ↓
历史事件追赶
        ↓
对齐
        ↓
实时事件

就是你应该重点搞懂的地方。

最后给你一个“今晚必背版”

如果明天面试官把你拷懵了，就至少牢牢记住这张图：

                 Client
                    ↓
                  Leader
                    ↓
                 rf.Start
                    ↓
              Raft Log / WAL
                    ↓
              多数节点复制
                    ↓
               commitIndex
                    ↓
              所有节点 Apply
                    ↓
                MVCC
                    ↓
                Badger
                    ↓
              Watch Notify

以及这五句话：

1. Leader 接收客户端写请求，Follower 不接收客户端写请求，但会复制并持久化 Leader 日志。

2. commitIndex 是 Raft 已提交位置，lastApplied 是状态机已经执行的位置。

3. Raft 复制的是日志，不是 BadgerDB；相同日志经过确定性状态机得到相同逻辑状态。

4. Apply 数据和 applyIndex 的持久化必须考虑原子性，否则恢复时可能出现重复执行或数据丢失。

5. Watch 应该建立在状态机修改成功之后，并且历史追赶和实时监听之间必须避免事件漏掉。5