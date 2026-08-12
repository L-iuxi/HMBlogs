---
title: "磁盘驱动 — 创建磁盘与分区操作"
date: "2026-01-21T12:00:00+08:00"
tags: ["操作系统", "磁盘"]
title-images: []
ending-images: []
author: "烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
《操作系统真相还原》学习笔记：使用 bximage 创建磁盘镜像、fdisk 进行分区操作，以及主分区、扩展分区、逻辑分区的概念。
<!--more-->

## 创建磁盘镜像

使用 bochs 自带的 `bximage` 工具创建磁盘：

```bash
bin/bximage
```

按提示依次输入：`1` → `hd` → `flat` → `80` → `hd80M.img`

在 `bochsrc.disk` 中配置：

```
ata0-slave: type=disk, path="hd80M.img", mode=flat, cylinders=162, heads=16, spt=63
```

这样 bochs 虚拟机启动时就会识别并自动挂载这个磁盘。

## 分区操作

使用 fdisk 工具对磁盘进行分区：

```bash
fdisk ./hd80M.img
```

### 分区类型

| 类型 | 说明 |
|------|------|
| 主分区 | 最多 4 个，可直接存储数据 |
| 扩展分区 | 最多 1 个，作为逻辑分区的容器 |
| 逻辑分区 | 在扩展分区内创建，突破 4 个分区限制 |

### 分区表

分区表存储每个分区的信息（起始扇区、结束扇区、分区类型等），位于磁盘的固定位置。

### CHS 与扇区计算

磁盘参数 CHS = Cylinders（柱面）/ Heads（磁头）/ Sectors（每磁道扇区数）。

扇区号计算公式：`结束扇区 = (结束柱面 + 1) × 磁头数 × 每道扇区数 - 1`

现代 fdisk 工具以扇区为单位操作，起始扇区最小为 2048。

### 分区类型 ID

使用 fdisk 的 `t` 命令修改分区类型 ID，例如 `0x66` 表示自定义文件系统类型。
