---
title: "Slice"
date: "2026-08-19T12:00:00+08:00"
tags: ["go"]
title-images: []
ending-images: []
author: "烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
关于GO的Slice
<!--more-->

## slice和数组
*Slice的底层是数组*
- 数组大小是数组类型的一部分。[3]int和[4]int是两种不同类型的数组。数组是值类型，作为参数传递的时候会传递整个数组。数组需要指定大小，不指定则自动推算初始化大小。
- Slice的底层也是数组，描述了底层数组的一个片段，包括指向数组的指针，容量和长度。切片在参数传递的时候按值传的是包含底层数组长度，容量，指针的副本，副本中的指针指向同一底层数组，所以在函数内，对底层数组的修改对调用函数方可见。切片可以通过数组或者make初始化


自动扩容
