---
title: "Net"
date: "2025-09-7T12:00:00+08:00"
tags: ["mysql"]
title-images: []
ending-images: []
author: "烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
关于网络的一些基础知识
<!--more-->
##
socket通过`write()`,`send()`等函数，把数据从用户态拷贝到内核态缓冲区，再通过TCP/IP协议经由网卡发送

## DNS
DNS全称域名系统 是将域名转换为IP的分布式数据库系统
DNS底层同时使用TCP和UDP，端口都是53

## token，session，cookie的区别
session存储在服务器，一般会给用户一个唯一的sessionid
cookie存储在客户端，浏览器向客户端发送请求的时候自动携带token的数据
token需要开发者手动添加，加密存储用户信息，