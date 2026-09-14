---
title: "MySQL索引"
date: "2025-04-18T12:00:00+08:00"
tags: ["mysql"]
title-images: []
ending-images: []
author: "烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
关于SQL索引
<!--more-->
## 主键 Primary Key
主键是对某一条记录的唯一标识
主键唯一，且一张表只能有一个主键
主键不能为空，可以是联合主键

## 唯一键Unique Key
保证某个键的值不能重复(不是主键)
主键主要用于唯一标识记录；唯一键用于保证业务字段唯一。
唯一建可以为NULL

## 普通索引
索引主要是为了提高查询速度，不唯一

## 外键
表示表和表之间的关联关系
一个表中的字段引用另一个表的主键或唯一键，用来保证两个表之间的数据关系合法。

## 全文索引
主要用于文本搜索

## 查询优化器
查询优化器： MySQL 一条 SQL，查询优化器负责分析这条 SQL，然后选择一个它认为执行成本更低的执行方案。