# 关于我的KV存储项目的持久化
# 总览

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
  