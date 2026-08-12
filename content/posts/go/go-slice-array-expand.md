---
title: "Go slice 底层数组与扩容机制"
date: "2026-08-12T10:00:00+08:00"
tags: ["Go", "slice"]
title-images: []
ending-images: []
author: ""
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
## 问题

Go slice 的底层结构是什么？扩容规则是怎样的？
<!--more-->
<!-- rest of the content -->
## slice 底层结构

```go
type slice struct {
    array unsafe.Pointer // 指向底层数组的指针
    len   int            // 当前长度
    cap   int            // 容量
}
```

## 扩容规则

- Go 1.18 之前：容量小于 1024 时翻倍，大于 1024 时增长 25%
- Go 1.18 之后：更平滑的扩容曲线，小容量时仍接近翻倍

## 关键点

1. slice 是引用语义，函数传参不会拷贝底层数组
2. append 触发扩容时会分配新数组，原 slice 不受影响
3. 多个 slice 共享同一底层数组时，修改会互相影响
