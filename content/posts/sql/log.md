---
title: "MySQL日志"
date: "2025-04-15T12:00:00+08:00"
tags: ["mysql"]
title-images: []
ending-images: []
author: "烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
关于SQL日志
<!--more-->
# SQL日志都有哪些？
- redolog，引擎层日志，用于SQL**掉电恢复**
- undolog，引擎层日志，用于**事务回滚**和**MVCC**
- binlog，server层日志，用于**数据备份**和**主从复制**
- relaylog，中继日志，主从复制场景下，slave拷贝master的本地binlog之后生成的日志
- 慢查询日志：需要手动开启，记录执行时间过长的SQL

# binlog
在执行完一条更新操作之后，server会生成一条binlog，等之后事务提交的时候，将本次事务中生成的所有binlog写入binlog日志。这个日志所有存储引擎都可以用。而且binlog是追加写，不会覆盖以前的日志。
binlog主要有三种格式：Statment，Row，Mixed，现在默认ROW
- Statment记录每一次修改操作，但是如果在执行的时候使用动态函数，可能导致同一条语句执行结果不同的情况。比如uuid，now这些函数。
- ROW，记录行数据最终被修改成什么样了。但是ROW的缺点是更新多少行就会产生多少条数据，binlog文件过大，如果是Statment的话只会记录一个update语句
- Mixed是以上两种的混合，根据不同情况自动选择使用模式
  
# undolog
在事务提交之前，会先将要回退的操作记录在undolog之中。以便事务失败的回滚

# redolog
redolog和undolog的区别是，redolog记录的是内存偏移量的操作。redolog记录了对哪个物理页做了什么修改，对XX表中的YY物理页ZZ偏移做了AA更新。事务提交的时候，redolog被持久化到磁盘，这个时候断电，虽然数据还没有被持久化到磁盘，但是物理页的偏移已经被记录，可以通过redolog恢复。
对redolog的操作是追加写，相比较磁盘的随机写，提高了执行性能。综上所述，redolog实际实现了：
- 将随机写改为追加写
- 实现事务的持久性