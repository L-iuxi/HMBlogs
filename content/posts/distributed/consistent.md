---
title: "分布式一致性和常见算法"
date: "2026-11-11T12:00:00+08:00"
tags: ["Raft", "Paxos","ZAB"]
title-images: []
ending-images: []
author: "有劲烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
关于分布式系统的一致性和常见的一致性算法
<!--more-->

# CAP 理论
对于一个分布式系统，不能同时满足以下三点：
1. 一致性（Consistency）：所有节点上的数据保持一致
2. 可用性（Availability）：系统在任意时刻都可用
3. 分区容错性（Partition Tolerance）：系统在任意时刻都可用

# 一致性模型
弱一致性（最终一致性）：DNS，Gossip
强一致性 Paxos，raft，ZAB
分布式系统对于容错的处理一般是通过**state machine replication**来实现的，一致性要保证多个 replication 达成共识。

# 一致性算法
## 主从同步
**主从同步**是常见的分布式系统的一致性算法，它通过主节点和从节点的同步来实现数据的一致性。主节点负责处理所有的请求，从节点负责复制主节点的数据。
主从同步复制
1. Master 节点接受写请求。
2. Master 节点将数据复制到Slave节点。
3. Master 节点等待直到所有从库返回。
一个节点失败会导致Master阻塞，导致整个集群不可用，保证了一致性，可用性降低

## 多数派
每次写都保证写入大于 N/2 个节点，比如 Redis 哨兵的主从复制。但是在并非环境下，无法保证系统的执行顺序。

## Paxos
### Basic Paxos 
**Basic Paxos**算法中的几个角色：
- Client：请求发起者
- Propser：接受 Client 的请求，向集群发起提议 propose，在冲突发生的时候协调冲突
- Accpetor：接收提议，发起投票，在形成多数派 Quorum的时候，提议最终被接受
- Learner：接收提议，备份数据，不影响集群一致性。
这几个角色执行的流程如下：
1. Client 发起请求，Propser 接受请求并发起提案，请求多数派接受。发起时携带一个请求编号 N。
2. 各个 Accpetor 接受请求，如果 N 大于任何自己接受的提案则通过，否则拒绝。
3. 达到多数派后，proposer 发起 accept 请求，请求包含提案编号和内容。
4. 如果各个 Accpetor 在此期间没有接受过任何编号大于 N 的请求，接受提案内容。
 
![Basic Paxos](paxos-basic.png)

多个 Propser 发起请求，不断提出更高编号的提案，可能会导致**活锁**。所以为了解决这个问题，可以使用单 Propser，避免多个节点竞争。或者**随机退避**，在 Proposer 被拒绝的时候，不要立刻重试，而是随机等待一段时间。

Basic Paxos存在难实现，2PC效率低，活锁的问题，引入了Multi Paxos

### Multi Paxos
相比较于 Basic Paxos，Multi Paxos 引入 Leader，唯一的 Proposer ，所有请求都需要经过此 Leader，那么 Basic Paxos 的第一个阶段就可以和第二个阶段就可以合并，不过要加一个选举 Leader 的步骤。
![Multi Paxos](paxos-multi.png)

## Raft
Raft包括 Leader，Follower，Candidate 三个角色。Raft 做三件事：选举 Leader，复制日志，保证一致性。
Raft的选举过程如下：
1. 任意节点出发选举超时 Candidate，发起选举。       
2. Candidate 发起选举，请求投票。
3. Follower 接受请求，投票规则如下：
    - 如果 term 相同则继续，若follwer < candidate，则更新任期和状态，若follwer > candidate，则拒绝。
    - 最新日志任期若大于等于则继续，否则拒绝
    - 任期相同时，若日志数目多则同意投票，否则拒绝。
4. 如果 Candidate 收到 majority 的投票，则成为 Leader。
5. Leader 发起复制日志，请求 Follower 复制日志。并定时发送心跳，维持 Leader 状态
6. Follower 接受请求，复制日志。这里要先写入 WAL 等日志，再返回，视为复制成功。


如果集群是偶数，那么可能存在有两个 candidate 获得票数一样的情况，需要通过随机心跳超时时间，避免有两个节点同时发起选举，而且要防止节点一直选举导致死锁。

## ZAB
zookeeper 使用的共识性算法，基本与 raft 相同，一个 Leader 的周期叫做 epoch。在选举的时候，会通过 epoch > counter > SID 的方式来选出leader，每次产生 leader 则 epoch + 1.