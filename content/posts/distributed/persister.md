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

## 总览：三种持久化各管什么

| 存储 | 管什么 | 文件 | 写入时机 |
|---|---|---|---|
| **WAL** | 要执行什么命令 + raft 元信息 | `wal.log`（append-only） | 命令提交时、投票/收快照时 |
| **Snapshot** | 某时间点的状态机全量快照 | `snapshot-<index>-<term>.dat` | 日志超阈值时（leader） |
| **BadgerDB** | 状态机的数据本体（mvcc 版本 + 查重表） | badger 目录 | apply 时 write-through |

三者关系一句话：**WAL 存「命令序列」，apply 执行命令，Badger 存「执行结果」，Snapshot 是「Badger 某个时间点的压缩备份」。**

---

## 一、WAL：写什么、什么时候写

WAL 用 3 种记录类型（`internal/wal/wal.go:23-27`）：

| 类型 | 结构 | 内容 |
|---|---|---|
| `RecTypeEntry`(1) | `LogEntry{Index,Term,Version,Command,ExpireAt}` | 一条命令，`Command` = 序列化的 `proto.Op`（Type/Key/Value/ClientId/RequestId/ExpectedVersion/LeaseId/Entries/Compares…） |
| `RecTypeState`(2) | `VoteRecord{Term,CandidateID,VoteGranted}` | 投票状态 |
| `RecTypeSnapshot`(3) | `SnapshotRecord{LastIncludedIndex,LastIncludedTerm,Path}` | 快照位置指针 |

### 写入时机（4 个代码点）

1. `persistEntry` → `raft.go:140`：**只有 leader**，`Start()` 收到客户端命令时，把新日志条目落 WAL。
2. `persistVote` → `raft_vote.go:192/207`：任意节点收到 `RequestVote` 且 term 增大、或投出票时，落投票状态。
3. `persistSnapshot` → `raft_snapshot.go:141`：leader 做快照时，落快照指针。
4. `persistSnapshot` → `raft_snapshot.go:82`：follower 收 `InstallSnapshot` 时，落快照指针。

### WAL 缺口

- ❌ **follower 收到 `AppendEntries` 不落日志**：`raft_heartbeat.go:251-263` 只 `append` 到内存 `rf.log`，没有 `persistEntry`。follower 的 WAL 里没有日志条目。
- ❌ **`commitIndex` / `lastApply` 不落 WAL**。
- ❌ **term 变化不落**：`startElection` 里 `term++`、`AppendEntries` 里 term 更新，都不 `persistVote`。

---

## 二、Snapshot：写什么、什么时候写

### 写什么

`mvcc.Serialize()`（`mvcc/snapshot.go:20`）的 JSON = `SnapshotData`：

```
CurrentRev / CompactRev          // 全局版本号、compact 位
Latest     map[string]int64      // 每 key 最新 rev
History    map[string][]int64    // 每 key 全部历史 rev
Revisions  []RevisionEntry       // 全局版本顺序
Entries    []ScanResult          // Badger 全量扫描（真正的数据本体）
```

### 什么时候写

`kv/snapshot.go snapshotWorker`——每 **5 秒** tick，**仅 leader**，当 `rf.LogSize() >= SnapshotThreshold` 时：

1. `mvcc.Serialize()` 序列化全量数据。
2. `rf.Snapshot(data)`（`raft_snapshot.go:125`）：写快照文件 `snapshot-<index>-<term>.dat` → 写 WAL 快照记录 → `wal.Truncate(snapIndex)` 删旧日志。

### Snapshot 缺口

- ❌ 快照**不含查重表**。
- ❌ 快照恢复路径坏：`handleSnapshot` 死锁（`raft_wal.go:66` 往 nil 无缓冲 channel 发）+ `raft.go:200-207` 恢复后清零 + `commitIndex` 不持久化。现在重启走快照恢复会丢快照后数据。

---

## 三、BadgerDB：写什么、什么时候写

### 1. mvcc 版本数据

- key = `<key>/<rev>`（如 `svc/user/5`），value = `types.Value{Value,Version,ExpireAt,Deleted}`。
- 每次 `Put` 写一条新版本（`Deleted=false`）；每次 `Delete` 写一条 tombstone（`Deleted=true`）。
- 写入点：apply 时 write-through——`putInternal/deleteInternal` → `mvcc.PutWithCAS/Put/Delete` → `store.Put`（`mvcc.go:34/64/141`）。

### 2. 查重表

- key = `__dedup__`，value = `{lastRequest,lastResult,lastTxnResult}` 三个 map 的 JSON。
- 写入点：apply 后 `persistDedup()`（`kv_dedup.go:31`）→ `store.RawPut`。

### 其他

- `compact.go:63` `BatchDelete` 删旧版本 key（删除动作，非新增数据）。

### Badger 缺口

基本完整，mvcc + 查重表都写穿，是三套存储里最可靠的。

---

## 四、KV 状态机怎么存

**分两层：内存索引 + Badger 数据本体。**

- **Badger（磁盘，数据本体）**：每个 key 的每次修改存一条 `<key>/<rev>`，永不移除（除非 compact）——这就是 MVCC 多版本的物理形态。
- **内存索引（`mvcc.go`，冗余加速）**：`latest`/`history`/`revisions`/`currentRev`。这些不是新数据，是 Badger 的倒排索引，重启从 Badger `Recover()` 重建（`recover.go`）。

### 读写流程

- **写**：`PutWithCAS` 先比较 `latest[key]` 和 `expectedVersion`，通过后 `currentRev++` 拿新 rev，写 Badger `key/rev`，更新 `latest/history/revisions`。
- **读**：`latest[key]` 拿最新 rev → `store.Get("key/rev")`。
- **查重**：内存 map（`lastRequest` 等）在 apply 时更新，同时写 Badger `__dedup__`，重启读回。

### 内存 vs 磁盘边界

| 数据 | 位置 | 重启后 |
|---|---|---|
| mvcc 版本数据 | Badger | ✅ 从 Badger 恢复 |
| 查重表 | Badger `__dedup__` | ✅ 从 Badger 恢复 |
| latest/history/revisions/currentRev | 内存（可从 Badger 重建） | ✅ Recover 重建 |
| lease / lock / watch | 纯内存 | ❌ 丢，靠客户端续约/重建 |
| lastApplied / commitIndex | 纯内存 | ❌ 丢（raft 恢复 bug 根源） |

---

## 五、重启恢复流程（现状）

```
MakeKVServer
├─ db.NewStore(node-N)                    打开 Badger
├─ InitMvcc → mvcc.Recover()              扫 Badger 重建 latest/history/currentRev
├─ InitKvserver
│   ├─ raft.MakeRaft
│   │   └─ LoadFromWAL()                  读 wal.log：
│   │       ├─ RecTypeEntry   → 重建 rf.log（内存）
│   │       ├─ RecTypeState   → 恢复 term/vote
│   │       └─ RecTypeSnapshot→ 恢复 lastSnapIndex + 发快照 msg（当前死锁）
│   ├─ 建空查重 map → loadDedup()          读 Badger __dedup__ 恢复查重表
│   └─ go applier()
└─ go snapshotWorker() / leaseExpireWorker()
```

**现状结论**：能正常恢复的只有 **Badger（mvcc + 查重表）**。WAL 恢复受「follower 不落日志 + commitIndex 不持久化 + 快照死锁 + raft 清零」四个问题拖累，基本没起到 durable 作用——目前是「leader 单点 durable，follower 全内存，重启靠 Badger 兜底」。

---

## 六、待办：持久化缺口清单

| # | 问题 | 位置 |
|---|---|---|
| 1 | follower 收 AppendEntries 不落 WAL 日志 | `raft_heartbeat.go:251-263` |
| 2 | commitIndex / lastApply 不持久化 | 全 raft 层 |
| 3 | term 变化不落 WAL | `raft_vote.go startElection` / `raft_heartbeat.go:198-201` |
| 4 | 快照恢复死锁 | `raft_wal.go:66`（nil 无缓冲 channel） |
| 5 | MakeRaft 恢复后清零 | `raft.go:200-207` |
| 6 | InstallSnapshot 不落到 mvcc | `raft_snapshot.go:55-111` |
| 7 | apply 不幂等（重放会有 watch/lease/CAS 副作用） | `kv_handle.go` |