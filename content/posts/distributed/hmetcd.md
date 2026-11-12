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

## 介绍一下HMETCD项目
-项目目标
-整体架构
-选型（mvcc+badgerdb+raft）
-实现功能

HMETCD 是一个用 Go 语言实现的基于 Raft 的多节点分布式KV存储，整体实现参考ETCD。客户端通过 grpc 请求节点，写请求进入 Leader 后通过 Raft 复制和提交，再由 ApplyLoop 进入状态机，最后由 MVCC 管理版本落实到 BadgerDB。Raft 解决多节点下数据一致性，MVCC 做多版本管理，BadgerDB 负责存储层持久化。在这个基础上我实现了 Watch，lease，Txn，Compact，分布式锁以及客户端和各节点的grpc通信

## Put请求全链路

首先客户端会向自己已知的 Leader 发送 Put 请求。节点收到 RPC 后先判断自己是不是 Leader，如果不是，就返回自己认为的 Leader 信息，让客户端重新请求；如果是 Leader，就继续处理。

对于 Put 请求，服务端会把 clientID、requestID、key、value 等信息封装成一个 Op，序列化之后调用 Raft 的 Start，把这个操作追加到 Leader 自己的 Raft 日志中。同时 KV 层会根据这个请求建立一个对应的等待 channel，后面等这条日志真正 Apply 完成之后返回执行结果。

Leader 将日志写入自己的日志之后，通过 AppendEntries RPC 将日志复制给 Followers。Follower 收到日志后，会根据 PrevLogIndex、PrevLogTerm 等信息检查自己的日志是否匹配；匹配之后才会把新的日志追加到自己的日志中，并向 Leader 返回复制成功的信息。

当 Leader 确认这条日志已经复制到了多数节点之后，就可以推进自己的 commitIndex。这里的 commit 和 Apply 是两个阶段：commitIndex 表示 Raft 已经确认提交到哪里，而 lastApplied 表示状态机实际执行到哪里。

Leader 会把自己的提交位置通过后续的 AppendEntries，也就是 leaderCommit，同步给 Followers。Follower 收到之后，如果发现 Leader 告诉自己的提交位置比自己的 commitIndex 更大，就更新自己的 commitIndex。

然后各个节点的 ApplyLoop 会依次把 lastApplied 到 commitIndex 之间已经提交、但还没有执行的日志取出来，反序列化成 Op，交给 KV 状态机执行。所以不是只有 Leader 执行日志，Follower 对自己已经提交的日志同样需要 Apply。

对于这条 Put 日志，KV 层首先根据 clientID + requestID 查询 history，判断这个请求之前是否已经执行过。如果已经执行过，就直接返回之前保存的结果，避免客户端重试导致重复写入；如果没有执行过，就执行真正的 MVCC Put，更新对应版本的数据并写入 BadgerDB，同时记录这次请求的执行结果。

MVCC 和 history 更新完成之后，KV 层再通过之前建立的 requestID 对应的 channel，把这次请求的执行结果返回给等待中的 Leader RPC，最后由 RPC 返回给客户端。

## 如果日志提交了，复制给了某几个节点，leader突然宕机了怎么办
如果 Leader 在日志已经复制给部分节点、但还没有形成多数派提交之前宕机，那么这条日志是否最终保留，要看新的 Leader 的日志情况。客户端这一次 RPC 可能收不到成功结果，因此客户端可以重试；如果这条日志最终没有提交，新的 Leader 可能会通过 Raft 的日志冲突处理覆盖掉这条未提交日志。如果它已经形成多数派并提交，那么新的 Leader 必须保证这条已经提交的日志不会被丢失，并最终 Apply 到状态机。

## Raft怎么保证已经提交的日志不会丢失
raft的投票机制

## 投票的时候Follower怎么决定自己投票给谁

1. 检查candidate的最新日志任期以及最新日志位置是否比自己新
2. 检查candidate任期是否大于等与自己，否则不投票，如果大于等于，更新自己的任期和在当前任期的投票
3. 任期相同且未投票，此时可以投票
4. 任期若大则不投票，任期若小更新任期并规定身份为follwer

## 如何用Readindex实现线性一致读

当当前节点确认自己是Leader的时候，确认自己读的位置已经commit，无法回滚，Get请求可以跳过Raft日志，直接走MVCC读取需要的建。此时需要保证 Leader不过期，不然会出现新Leader当选，旧Leader仍然认为自己是Leader于是读到旧数据。Readindex方案可以解决这个问题
Get 请求不需要作为日志写入 Raft，因为读操作本身不会修改状态机。如果每个 Get 都走 Raft 日志，会产生大量不必要的日志复制和提交开销。

但是 Leader 直接读取本地 MVCC 又是不安全的，因为 Leader 可能已经失去领导权，但由于网络延迟还不知道自己已经被新 Leader 替代。这时候旧 Leader 可能读取到旧状态。

所以我使用 ReadIndex 来实现线性一致读。

一次 Get 到达 Leader 后，Leader 首先需要通过 ReadIndex 确认自己仍然拥有当前 Term 的领导权，并获取当前安全的 commit index，记为 readIndex。

然后不能马上读取 MVCC，因为 Raft 的 commitIndex 只表示日志已经提交，不代表状态机已经执行到这个位置。因此还需要等待：
```bash
lastApplied >= readIndex
```
确认状态机已经应用到这个位置之后，Leader 再读取本地 MVCC，这样读到的就是当前已经提交状态下的数据。

所以整个流程可以理解成：

```bash
Get
  ↓
Leader
  ↓
ReadIndex
  ↓
多数派确认当前 Leader 的领导权
  ↓
得到 readIndex
  ↓
等待 lastApplied >= readIndex
  ↓
读取本地 MVCC
  ↓
返回客户端
```
这样既不需要把 Get 写入 Raft 日志，又能够保证线性一致读。

原来每个 Get 都独立触发 ReadIndex，导致大量请求重复进行 Leader→Follower 的确认；把同一批等待中的读请求聚合到一个 gate 上，共享一次 ReadIndex 结果，再等待状态机 Apply 到对应位置，从而降低重复的 Raft 通信和同步等待。
...

## Txn事务

事务的实现基于锁和batch，创建一个事务的时候会将一个事务内的全部操作batch一次性批量提交，通过raft保证各个事务之间的绝对顺序，执行一个事务首先通过锁机制，保证一个事务正在执行的时候不执行其他事务。事务内部通过if 条件，else 语句，then 语句执行，确保原子操作

## WAL和BadgerDB
WAL 主要保证 Raft 日志和共识状态的持久化，BadgerDB 负责 KV 状态的持久化。WAL 解决的是崩溃后日志不能丢的问题，BadgerDB 解决的是状态数据的持久保存，两者处于不同层次。

## Watch 实现
watch主要实现对某个建的监听，支持推送事件的历史版本和当前版本两种方法。当客户端发起对某个建的监听的时候会把该客户端加入这个key的watch监听表里面，当对某个建进行修改的时候，会对这个key监听表里的所有客户端进行通知，具体形式是通过表共享的管道传输信息，客户端和服务器会建立长连接，服务器可以一直推送。如果是旧数据推送，那么访问mvcc推送未同步的数据，同步之后加入同步watch表，推送后续更新

## 前缀树
Watch 支持 prefix 监听，如果使用普通 map，只能通过遍历所有 watcher 判断哪些 prefix 能匹配当前 key；使用 Trie 可以沿着 key 的字符逐层查找，并通知符合前缀的节点下所有节点，同时找到这个 key 对应路径上的 prefix watcher，避免每次修改都扫描全部 watcher。


## Lease
lease实现绑定过期时间并且对过期建进行删除，后台启动协程，定期轮询建是否过期，如果过期就把删除键封装成一个raft请求提交，删除建

## 为什么要先持久化日志，再推进commitindex
因为 Raft 要保证节点崩溃恢复后，已经接受的日志不会因为只存在内存中而丢失，所以 Leader 会先将日志持久化到 WAL，再通过 AppendEntries 向其他节点复制。需要注意，WAL 持久化只代表本节点数据可靠，不代表日志已经 commit，只有获得多数派确认后才能推进 commitIndex。

## 怎么实现动态成员变更
支持运行时的 AddPeer 和 RemovePeer。成员变更时首先对 Raft 状态加锁，Add 时检查节点是否存在，然后建立对应的 gRPC peer 连接，将节点加入 peers，同时初始化它的 nextIndex 和 matchIndex；Remove 时关闭对应连接，并同步从 peers、clients、nextIndex、matchIndex 等结构中删除节点。成员变化后通过 peerGen 自增，让正在执行的心跳和选举 goroutine 能够检测成员配置是否发生变化，避免继续使用旧的成员列表。

## learner 解决什么问题
Follower 一旦成为正式成员，就拥有投票权，会影响 quorum；而 Learner 可以先完成数据同步，再获得投票权，避免一个严重落后的新节点影响集群的选举和提交。
可以先将新节点作为 Learner 加入，让 Leader 向它同步 Raft 日志和状态。当 Learner 的日志追平到一定程度后，再将其提升为正式 voter。这样新节点在数据未同步完成之前不会参与 quorum 和 Leader 选举，降低成员变更对集群可用性的影响。

## 为什么用BadgerDB
ETCD是使用的是基于B+树实现的BoltDB，我使用的是基于LSM实现的BadgerDB。LSM用读放大换取特别高的写入性能
如果使用BoltDB的话实现MVCC就要实现类似copy on write的方法，如果用BadgerDB的话可以通过不同的版本号天然维护MVCC，实现上更简单一点

```bash
                         浏览器
                           │
                           │ HTTP
                           ↓
                    ┌─────────────┐
                    │    Nginx    │
                    │  80 / 8090  │
                    └──────┬──────┘
                           │
            ┌──────────────┼──────────────┐
            ↓              ↓              ↓
        user-api       event-api      order-api ×3
        :8888          :8890       :8894/:8895/:8896
            │              │              │
            │              │              │
            └──────────────┼──────────────┘
                           │
                        gRPC RPC
                           │
                     ┌─────▼─────┐
                     │   etcd    │
                     │ 服务发现   │
                     └─────┬─────┘
                           │
          ┌────────────────┼────────────────┐
          ↓                ↓                ↓
     event-rpc       inventory-rpc       order-rpc
       ×2                ×2                ×2
          │                │                │
          └────────────────┼────────────────┘
                           │
                MySQL / Redis / RabbitMQ
```
## go-zero
go-zero是一个基于go的微服务开发框架，主要用于快速构建微服务，本项目主要使用了go-zero的api服务和rpc服务.go-zreo可以解决微服务开发中的一些重复问题，比如API定义，RPC通信，配置管理，限流，日志以及服务发现。通过.api生成和.proto生成，可以减删重复手写代码，封装基础设施

外部http请求先到达go-zero的API Gateway，Gateway根据API定义把请求转发给对应的RPC服务，服务之间主要通过[gRPC](https://l-iuxi.github.io/HMBlogs/posts/grpc/)通信

Gin 更偏向 HTTP Web 服务本身，主要解决路由、中间件、HTTP 请求处理这些问题。

Go-Zero 的定位更偏微服务，它除了 HTTP API 之外，还提供 RPC、服务发现、负载均衡、限流、配置管理等微服务相关能力。

## etcd
etcd是一个高可用的分布式键值存储系统，在我的项目里面主要做服务发现，使用raft算法来保证数据的强一致性，可以对数据进行监视和更新

通过把rpc项目服务和地址按照key-value写进etcd里面，可以实现调用方通过etcd获取服务实例位置，同时go-zero RPC客户端负责多RPC服务的实例的负载均衡，比如轮询。
etcd会一直向实例发起续约，如果服务实例挂掉，续约失败，etcd将服务从实例中移除，同时通过watch通知客户端让客户端感知

## Nginx
做api服务发现，反向代理和负载均衡
- 反向代理：Nginx 的反向代理，就是客户端把请求发给 Nginx，Nginx 再代替客户端把请求转发给后端服务器。
## Lua脚本
Lua是脚本性语言

redis对Lua脚本采用单线程串行执行，一个脚本执行期间不会执行其他客户断的命令，保证操作的原子性。但是redis不是事务回滚机制

## Sentinel
redis master节点崩溃之后，sentinel发送心跳长时间没回应，主观认为redis下线，半数sentinel认为节点下线，则节点真正下线。sentinel此时发起故障转移，按照slave是否正常，优先级大小和偏移量，id等决定出新master，其他slave修改为slave of新master，客户端可以通过sentinel获取master地址

Q：故障转移后，主从复制丢数据怎么办
Redis Sentinel 本身是异步主从复制，所以确实不能保证主从切换时数据零丢失。如果业务要求库存绝对不能因为故障转移而增加，不能单纯依赖 Sentinel 保证一致性。

一种方案是在故障转移期间暂停抢票，等新的 Master 选举完成后，再通过持久化数据或者 MySQL 的库存基线进行校验和修正，确认库存状态之后再恢复业务。

更严格的方案是把 MySQL 或其他强一致存储作为最终库存事实来源，Redis 只作为高并发扣库存的缓存/临时状态，并通过可靠消息和补偿机制保证最终一致。

如果 Redis 本身作为库存的最终事实来源，那么就需要接受 Sentinel 异步复制存在极端情况下的数据丢失风险，或者使用 Redis Cluster/复制增强等方案降低风险，但普通 Sentinel 本身不能提供强一致保证。

高并发和绝对一致性之间需要做权衡，不能简单地说用了 Sentinel 就能保证库存绝对安全。


## 30000qps
压测环境是本地 2 核 16G 机器，使用约 1 万个客户端进行并发请求，测试持续 30 秒。测试结果大约达到 3 万 QPS。这里的 3 万是请求吞吐量，不是每秒卖出 3 万张票。因为实际库存只有几十张，所以成功购票数量远小于请求数量。


## MQ宕机
首先我没收到 Confirm 不代表消息一定发送失败，因为消息可能已经到达 Broker，只是 Confirm 在网络中丢失了。所以这是一个不确定状态。

订单生成全局唯一的订单号，把订单号作为业务幂等键。Confirm 超时后可以使用相同订单号进行重试，即使 Broker 实际已经收到第一条消息，重试也可能产生重复消息，但消费者侧通过订单号幂等以及 MySQL 唯一约束保证不会创建重复订单。

如果消费者处理失败，则不 ACK，让消息重试；多次失败后进入死信队列，由补偿机制处理。

另外，Redis 扣库存和 MQ 发送之间仍然存在一致性问题，比如 Redis 扣库存成功后 Producer 宕机导致消息根本没发出去。这个单靠 Confirm 解决不了，如果要进一步提高可靠性，可以引入本地消息表 Outbox 或其他可靠消息方案，再配合库存补偿机制保证最终一致。”

## Redis主从切换导致数据丢失
这个问题首先应该保证业务幂等，不能单纯依赖redis的一次操作为业务事实，请求ID，订单ID都可以成为业务的可追踪状态。第二，应该根据订单流水，补偿任务等机制，保证事务的最终一致性。最后，根据业务要求选择更复杂的redis复制策略
## 关于我的KV存储项目的持久化
## 总览

| 存储 | 管什么 | 文件 | 写入时机 |
|---|---|---|---|
| **WAL** | 要执行什么命令 + raft 元信息 | `wal.log`（append-only） | 命令提交时、投票/收快照时 |
| **Snapshot** | 某时间点的状态机全量快照 | `snapshot-<index>-<term>.dat` | 日志超阈值时（leader） |
| **BadgerDB** | 状态机的数据本体（mvcc 版本 + 查重表） | badger 目录 | apply 时 write-through |


## WAL
WAL主要是存储 Raft 得相关信息。在 wal.go 封装了三种持久化类型，分别是
- RecLogEntry：主要存储一条序列化的日志相关信息封装，包括当前任期，过期时间
- RecVote：主要是投票选举相关记录，记录当前任期下谁发起了选举，该节点投票给了谁
- RecSnapshotindex：记录快照位置指针

- LogEntry：Leader节点在收到日志之后持久化进WAL然后发起日志复制，follwer节点在收到日志复制请求，写入自己日志之前同步进WAL
- Vote在每次节点投票的时候记录
- Snapshot在每次快照的时候记录下标位置

## Snapshot快照
快照主要是保存状态机信息，对KV层的相关信息进行保存，具体保存内容有
```bash
CurrentRev / CompactRev          // 全局版本号、compact 位
Latest     map[string]int64      // 每 key 最新 rev
History    map[string][]int64    // 每 key 全部历史 rev
Revisions  []RevisionEntry       // 全局版本顺序
Entries    []ScanResult          // Badger 全量扫描（真正的数据本体）
```
帮助状态机从崩溃之后重新恢复数据，快照是一个协程10秒一次保存快照

## BadgerDB
BagderDB主要存储KV数据
- 每次kv操作的时候写入BadgerDB
- kv层查重表每次成功apply处理之后写入BadgerDB
  