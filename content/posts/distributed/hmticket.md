---
title: "关于EventHub"
date: "2026-08-13T12:00:00+08:00"
tags: ["Raft", "ETCD"]
title-images: []
ending-images: []
author: "伤心的面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
一些比较ran的项目流程问题
<!--more-->

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
