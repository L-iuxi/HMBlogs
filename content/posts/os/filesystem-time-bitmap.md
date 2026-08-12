---
title: "内存管理系统 — 文件时间、断言与位图"
date: "2026-01-18T10:00:00+08:00"
tags: ["操作系统", "内存管理"]
title-images: []
ending-images: []
author: "烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
《操作系统真相还原》学习笔记：文件的三种时间属性（atime/ctime/mtime）、assert 断言机制，以及位图 bitmap 的资源管理原理。
<!--more-->

## 文件的三种时间

| 时间 | 全称 | 含义 | 触发条件 |
|------|------|------|----------|
| atime | access time | 访问时间 | 读取文件数据部分时更新，如 `cat`、`less` |
| ctime | change time | 属性变更时间 | 文件属性或数据被修改时更新 |
| mtime | modify time | 数据修改时间 | 文件数据被修改时更新（同时更新 ctime） |

**注意**：`ls` 命令不会更新 atime，只有实际读取文件内容才会。

## assert 断言

assert 用于调试阶段检测程序中的逻辑错误。它是一种防御性编程手段，当条件为假时终止程序并报告错误位置。

## 位图 bitmap

位图广泛用于资源管理，是一种管理资源的方式和手段。核心思想是用一个 bit 表示一个资源单元的状态（空闲/占用），从而实现高效的空间管理。

典型应用场景：
- 内存页框分配
- 磁盘块管理
- 文件系统 inode 分配
