---
title: "Agent的框架"
date: "2026-09-20T14:00:00+08:00"
tags: ["Agent"]
title-images: []
ending-images: []
author: "幸福烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
Agent 的框架
<!--more-->
接入工具，定义工具协议，实现Agent循环，把结果重新交给模型。使用Agent框架可以减少写这些重复的步骤，开发者只需要聚焦自己需要实现的Agent功能。
常见的框架：LangChain，LangGraph。LlamaIndex。本篇文章将主要介绍这些主流Agent模型。

# LangChain
LangChain框架结合了Prompt，模型，消息，工具，结构化输出，中间件。LangChain的最大优点是开发速度快，集成范围广。
不过LangChain不适合复杂的Agent模型，当出现业务分支，精细分支的时候，就需要考虑其他的框架

# LangGraph
LangGraph用`state+edge+node`表示工作流，state表示状态，node负责执行或者工具，edge表示下一步运行哪个节点。
LangGraph让Agent可以处理更复杂的问题。
在实际的框架中，往往分为父图和多个子图。父图负责Agent的多个流程，子图分别负责Agent的一个步骤。父图和子图通过state通信，下面是项目中一个实际的LangGraph工作流程
```bash
                          用户请求
                            │
                            ▼
                    ┌─────────────────┐
                    │   Supervisor    │
                    │  决定下一步去哪   │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
          Memory          Planner         ToolsAgent
              │              │              │
              ▼              ▼              ▼
          用户画像        N天行程JSON       即时问答
                             │
                             ▼
                          Content
                             │
                             ▼
                           Image
                             │
                             ▼
                          Summary
                             │
                             ▼
                         最终攻略
```


# LlamaIndex
LlamaIndex强调在私有数据之上构建AI应用，可以保证不同用户只能看到自己有权限访问的数据，各个平台的资料进入库的时候按照同一接口解析。适合企业知识库，知识Agent

# AutoGen
多智能体协作，核心思想是让多个Agent之间进行对话，协作。Agent之间可以互相对话，比如Plan Agent对计划做出调整之后，下面的search agent马上收到消息开始修正自己的计划。可以让不同agent担任搜索，执行，审查等角色。
这种方法主要通过message在Agent之间传递信息来实现

# CrewAI
把多个有明确角色和任务的 Agent 组织成一个“团队（Crew）”，让它们协作完成任务。在这种框架下，每个Agent有自己的角色，每个agent领取自己的Task执行。强调角色和任务编排