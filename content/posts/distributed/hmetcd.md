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

HMETCD 是一个用 Go 语言实现的基于 Raft 的多节点分布式KV存储，整体实现参考ETCD。客户端通过grpc 请求节点，写请求进入 Leader 后通过 Raft 复制和提交，再由 ApplyLoop 进入状态机，最后由 MVCC 管理版本落实到 BadgerDB。Raft 解决多节点下数据一致性，MVCC 做多版本管理，BadgerDB 负责存储层持久化。在这个基础上我实现了 Watch，lease，Txn，Compact，分布式锁以及客户端和各节点的grpc通信

## Put请求全链路

首先客户端会向自己已知的 Leader 发送 Put 请求。节点收到 RPC 后先判断自己是不是 Leader，如果不是，就返回自己认为的 Leader 信息，让客户端重新请求；如果是 Leader，就继续处理。

对于 Put 请求，服务端会把 clientID、requestID、key、value 等信息封装成一个 Op，序列化之后调用 Raft 的 Start，把这个操作追加到 Leader 自己的 Raft 日志中。同时 KV 层会根据这个请求建立一个对应的等待 channel，后面等这条日志真正 Apply 完成之后返回执行结果。

Leader 将日志写入自己的日志之后，通过 AppendEntries RPC 将日志复制给 Followers。Follower 收到日志后，会根据 PrevLogIndex、PrevLogTerm 等信息检查自己的日志是否匹配；匹配之后才会把新的日志追加到自己的日志中，并向 Leader 返回复制成功的信息。

当 Leader 确认这条日志已经复制到了多数节点之后，就可以推进自己的 commitIndex。这里的 commit 和 Apply 是两个阶段：commitIndex 表示 Raft 已经确认提交到哪里，而 lastApplied 表示状态机实际执行到哪里。

Leader 会把自己的提交位置通过后续的 AppendEntries，也就是 leaderCommit，同步给 Followers。Follower 收到之后，如果发现 Leader 告诉自己的提交位置比自己的 commitIndex 更大，就更新自己的 commitIndex。

然后各个节点的 ApplyLoop 会依次把 lastApplied 到 commitIndex 之间已经提交、但还没有执行的日志取出来，反序列化成 Op，交给 KV 状态机执行。所以不是只有 Leader 执行日志，Follower 对自己已经提交的日志同样需要 Apply。

对于这条 Put 日志，KV 层首先根据 clientID + requestID 查询 history，判断这个请求之前是否已经执行过。如果已经执行过，就直接返回之前保存的结果，避免客户端重试导致重复写入；如果没有执行过，就执行真正的 MVCC Put，更新对应版本的数据并写入 BadgerDB，同时记录这次请求的执行结果。

MVCC 和 history 更新完成之后，KV 层再通过之前建立的 requestID 对应的 channel，把这次请求的执行结果返回给等待中的 Leader RPC，最后由 RPC 返回给客户端。

如果 Leader 在日志已经复制给部分节点、但还没有形成多数派提交之前宕机，那么这条日志是否最终保留，要看新的 Leader 的日志情况。客户端这一次 RPC 可能收不到成功结果，因此客户端可以重试；如果这条日志最终没有提交，新的 Leader 可能会通过 Raft 的日志冲突处理覆盖掉这条未提交日志。如果它已经形成多数派并提交，那么新的 Leader 必须保证这条已经提交的日志不会被丢失，并最终 Apply 到状态机。

...