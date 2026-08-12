---
title: "文件系统 — inode 与文件查找流程"
date: "2026-01-21T14:00:00+08:00"
tags: ["操作系统", "文件系统"]
title-images: []
ending-images: []
author: "烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
《操作系统真相还原》学习笔记：inode 索引结构、超级块、目录项，以及从路径名定位磁盘文件的完整流程。
<!--more-->

## 文件存储方式

块是文件系统的读写单位。文件至少要占据一个块。当文件体积大于 1 个块时，文件被拆分成多个块来存储。

### FAT vs UNIX

- **FAT 文件系统**：在每个块的最后存储下一个块的地址，块与块串联
- **UNIX 文件系统**：将文件以索引结构组织，包含此索引表的索引结构称为 **inode**

Linux 借鉴了 inode 结构：一个文件一个 inode，有多少文件就有多少 inode。

## 文件查找流程

以查找 `/home/test.c` 为例：

1. 超级块位置固定，可直接访问
2. 从超级块获取根目录的 inode 标号和 inode 数组位置
3. 用根目录 inode 找到根目录文件
4. 在根目录文件中查找名为 `home` 的目录项，取出其 inode 标号
5. 访问 inode 数组，找到 home 目录文件在磁盘上的位置
6. 在 home 目录文件中查找 `test.c` 的目录项，取出 inode 标号
7. 最终定位到 `test.c` 在磁盘上的位置

## 关键数据结构

| 结构 | 作用 |
|------|------|
| 超级块 | 存储文件系统元信息（inode 数量、块大小等） |
| inode | 文件的元数据和数据块索引 |
| 目录项 | 文件名到 inode 的映射 |
| 间接块索引表 | 当文件超过 inode 直接索引范围时使用 |
