---
title: "IO多路复用"
date: "2026-01-21T12:00:00+08:00"
tags: ["IO多路复用"]
title-images: []
ending-images: []
author: "吃的很饱的烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
关于IO多路复用
<!--more-->
## IO多路复用
**IO多路复用解决什么问题：**
服务器为每个客户端连接创建一个进程/线程，消耗的资源很多。IO多路复用可以用一个进程/线程处理多个TCP连接，减少系统开销。

## 网络通讯中的事件
### 读事件
1. 已连接队列中有新的socket
2. 接受缓存中有数据可以读
3. tcp连接已断开
   
### 写事件
1.发送缓冲区没有满，可以写入数据

## 常见的多路复用模型

### SELECT（1024）

#### bitmap
SELECT 底层存放 socket 的结构 fd_set 是一个1024位的bitmap(int[32] 4字节 * 8位 *32个 = 1024)
FD_ZERO(fd_set *set)//位图置0
FD_CLR(fd,fd_set)//删除某socket
FD_ISSET(fd,fd_Set)//判断socket是否在bitmap中
FD_SET(fd,fd_set)//socket加入集合

#### 实例
```bash
int main() {
    fd_set readfds;

    FD_ZERO(&readfds);

    // 假设要监听标准输入
    FD_SET(STDIN_FILENO, &readfds);

    printf("等待输入...\n");

    int ret = select(STDIN_FILENO + 1, &readfds,NULL,NULL,NULL);//第二个参数为读事件，第三个参数为写事件

    if (ret < 0) {
        perror("select");
        return 1;
    }

    if (FD_ISSET(STDIN_FILENO, &readfds)) {
        printf("标准输入有数据了\n");
    }

    return 0;
}
```
#### 水平触发
被Select监视的socket上发生事件时，select会立即返回，通知程序处理事件，如果事件没有被处理，不会丢失，再次调用select的时候会再次通知。
#### 性能
1s大概12万请求
#### 问题
1. 采用轮询遍历bitmap，数据多时性能下降
2. 每次调用select的时候要拷贝bitmap，因为select会修改bitmap
3. 程序运行在用户态，在内核运行select的时候，要把bitmap从用户态拷贝到内核态
4. bitmap大小有限，增加数量效率会下降

### POLL（数千）
#### 结构
用结构体数组存放socket 
```bash
  struct pollfd {
               int   fd;         /* 为-1则忽略*/
               short events;     /* 需要监视的事件 */
               short revents;    /* 返回的事件 */
           };
```
POLL的数据：
POLLIN 有事件可以读
POLLOUT 有事件可以写
等...

#### 实例
```bash

int main() {
    struct pollfd fds[1];

    // 监听标准输入
    fds[0].fd = STDIN_FILENO;
    fds[0].events = POLLIN;

    printf("等待输入...\n");

    int ret = poll(fds, 1, -1);

    if (ret < 0) {
        perror("poll");
        return 1;
    }

    if (fds[0].revents & POLLIN) {
        printf("标准输入有数据了\n");
    }

    return 0;
}
```
#### 水平触发
#### 问题
1. Poll的结构体数组传入内核后转换为链表
2. 每调一次拷贝一次（select拷贝两次
3. 底层仍是遍历，socket越多开销越大

### EPOLL（百万）
#### 结构
```bash
 struct epoll_event {
           uint32_t      events;  /* epoll事件 */
           epoll_data_t  data;    /* 事件数据 */
       };

       union epoll_data {
           void     *ptr;
           int       fd;
           uint32_t  u32;
           uint64_t  u64;
       };

       typedef union epoll_data  epoll_data_t;//联合体

```
EPOLLIN 读事件
EPOLLOUT 写事件
#### 实例
```bash
int main() {
    // 1. 创建 epoll 实例，这里返回的是一个整数值
    //代表一个eventpoll模型描述符，也是用来存储全部事件的红黑树的根
    //参数原本指可以容纳的文件描述符的最大个数
    //更新后无实际意义，只是为了向前版本兼容
    //epollwait里的maxevents参数没有必要和这个参数进行比较

    int epfd = epoll_create1(0);

    // 2. 创建要监听的事件
    struct epoll_event event;
    event.events = EPOLLIN;//要监视的事件类型
    event.data.fd = STDIN_FILENO;//指定什么返回什么类型

    // 3. 把 需要监视的事件加入 epoll
    epoll_ctl(epfd, EPOLL_CTL_ADD, STDIN_FILENO, &event);

    // 4. 存放返回的事件
    struct epoll_event events[10];

    // 5.等待事件发生
    int n = epoll_wait(epfd, events, 10, -1);

    // 6.返回要处理的事件的数量
    for (int i = 0; i < n; i++) {
        if (events[i].events & EPOLLIN) {
            printf("stdin 有数据可以读取\n");
        }
    }

    close(epfd);

    return 0;
}
```
#### 阻塞IO和非阻塞IO
**阻塞：**在进程/线程发起调用，等待调用返回时，进程/线程会阻塞等待。等待中的进程/线程让出CPU的使用权
**非阻塞：**在进程/线程中，发起一个调用会立刻返回
connect，accept，send，recv会阻塞
传统网络模型中，每线程阻塞
IO复用中，事件循环不能被阻塞在任何环节要采用非阻塞
例如：对非阻塞IO的 connect() 进行调用，不管握手结果是成功或者失败，都会先返回失败。如果connect() 返回的 fd 可写，那么可以认为连接成功

#### 水平触发和边缘触发
```bash
//设置边缘触发，默认为水平触发
ev.event = EPOLLIN | EPOLLET 
```
##### 水平触发 LT
读：epoll_wait触发读事件，如果程序没有把数据读完。再次调用epoll_wait的时候，将立即再次触发读事件
写：发送缓冲区没有满，表示还可以写入数据。再次调用epoll_wait的时候，再次触发写事件。

#### 边缘触发 ET
读：epoll_wait触发读事件之后，不管程序有没有处理，都不会再触发读事件，只有新的数据到达的时候，才会再次触发读事件。
写：epoll_wait触发写事件之后，如果发送缓冲区未满，不会触发写事件。只有缓冲区状态由满变为不满的时候，才会再次触发写事件。

#### 原理
首先调用`epoll_create1(0)`，返回一个整数值代表event模型占用的模型描述符-也是用来存储全部事件的红黑树的根，以及创建一个存放就绪事件的双端队列
红黑树的本质就是告诉内核需要监听哪些文件描述符上面的哪些事件
epoll感知事件到来不采用轮询，调用`epoll_ctl`方法，向内核注册fd和相关事件的时候同时注册一个回调函数。
当`epollitem`对应的文件描述符上的事件已经就绪的时候，回调函数就会将该节点连接到已经就绪的双端队列中(不是拷贝一份)
调用`epoll_wait`方法，判断就绪队列中哪些文件描述符上的哪些事件就绪了

![alt text](image.png)

#### Questions
**Q：EPOLL 为什么使用红黑树 而不是Hash 或者 B+树？**
A：
1. epoll 需要频繁地对 fd 进行添加、删除、修改和查找，红黑树能在这些操作上都提供稳定的 O(log n) 性能，同时实现成熟、内核开销适中。
2. Hash 虽然平均 O(1)，但不适合 epoll 对有序性和稳定最坏情况的要求。
3. B+ 树主要适合磁盘/页式存储场景，在内存中的内核 fd 管理场景下没有必要。
**Q:EPOLL为什么比SELECT和POLL快？**
A:
1. Epoll只在调用 `epoll_ctl`方法 即监听事件的时候才会把数据从用户态拷贝到内核态，一次拷贝。而SElECT 和 POLL每执行都需要将数据从用户态拷贝到内核态
2. EPOLL在调用`epoll_wait`的时候只会拷贝已经就绪的事件，不会拷贝没有就绪的事件
3. 在判断事件是否就绪时，采用回调机制而不是轮询，`epoll_wait`不需要循环检查，只需要访问已就绪的双端队列，就可以找到已就绪的事件。这个过程的时间复杂度 `O(1)`

**Q:EPOLL 一定比 POLL 快吗？**
A:在并发数可控的时候，遍历结构体的开销较小，此时POLL更快。EPOLL适用于高并发网络场景。
