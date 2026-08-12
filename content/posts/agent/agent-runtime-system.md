---
title: "Agent Runtime — 运行时系统深度解析"
date: "2026-08-12T16:00:00+08:00"
tags: ["Agent", "运行时"]
title-images: []
ending-images: []
author: "烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
Agent 与聊天机器人的本质区别：事件驱动、状态管理、持续执行。深入 Agent Runtime 的四要素——Event/State/LLM/Execute——以及记忆系统的分层设计。
<!--more-->

## Agent 与 AI 的本质区别

电商聊天机器人：输入"我要退款" → 匹配规则 → 返回预设回复。它只是在 **回应问题**。

Coding Agent：给一个仓库，说"修改代码里的 bug，确保测试通过"。Agent 会分析问题 → 制定计划 → 执行动作 → 观察反馈 → 继续循环，直至完成任务。

**前者是一次性响应系统，后者是持续执行系统。**

## Agent 的定义

Agent 的三个本质特征：**感受（Sensors）、自主（Decision）、执行（Actuators）**。

以 Coding Agent 为例：
- 感知：读代码，看日志
- 状态：当前修复位置，发生错误的位置
- 决策：使用什么工具，如何修复
- 行动：修复代码，跑测试

## Agent 怎么处理请求 — Runtime

一段简单的 Agent 处理过程：

```
while (true):
    event = receive()
    state = update(state, event)
    action = decide(state)
    execute(action)
```

### Event 事件

在 Agent 中，系统面对的是不断发生的变化，而不是简单的输入。系统中发生的一次可观测变化称为 **事件**：

- 用户提出请求
- 工具返回结果
- 定时器触发
- 外部 API 返回

**为什么必须引入事件模型？** Agent 的执行过程是"多步的"：查代码 → 修改 → 跑测试 → 再修改。每一步都产生新的反馈，而反馈本身就是 "事件"。没有事件模型，中间过程会被压扁成一次输出。

### State 状态

状态是对事件历史的压缩表示：

```
State = f(event1, event2, ... eventN)
```

状态只解决一件事：**当前任务进行到哪里了？**

Coding Agent 的状态可能包含：bug 是否定位、哪个文件已检查、哪些假设被否定、下一步应该做什么。

没有状态，每一轮 Agent 都会变成"失忆系统"，不断重复相同操作。

### LLM 决策模块

LLM 不是"生成答案的终点"，而是**决策模块**（Decision Maker）。它基于当前 state 做三件事：

1. 判断问题在哪
2. 决定下一步行动
3. 选择使用哪个工具

例如，当 state 是 `panic 在 server.go:42，疑似 nil pointer` 时，LLM 生成：`ToolCall: read_file(server.go)`。

**LLM 在 Agent 中不直接"执行"，只负责"决定"。**

### Execute 执行层

执行层负责把 LLM 的决策落地为现实动作。LLM 是"大脑"，执行层是"手和脚"。

执行不光改变事件，还会产生新事件。例如 `apply_patch(server.go)` → `ToolResultEvent: patch applied`。

**Execute 不是终点，而是下一轮决策的开始。** "行动 → 反馈 → 再行动"的闭环是 Agent 持续完成复杂任务的核心。

## Agent Loop 实现

```typescript
const messages: MessageParam[] = [{ role: "user", content: userInput }];

while (true) {
  const response = await client.messages.create({
    model: "claude-opus-4-6",
    max_tokens: 8096,
    tools: toolDefinitions,
    messages,
  });

  if (response.stop_reason === "tool_use") {
    const toolResults = await Promise.all(
      response.content.filter(b => b.type === "tool_use")
        .map(async b => ({
          type: "tool_result",
          tool_use_id: b.id,
          content: await executeTool(b.name, b.input),
        }))
    );
    messages.push({ role: "assistant", content: response.content });
    messages.push({ role: "user", content: toolResults });
  } else {
    return response.content.find(b => b.type === "text")?.text ?? "";
  }
}
```

## Runtime 解决的三个关键问题

1. **持续执行能力**：任务跨多个步骤执行，不是一次完成
2. **状态管理能力**：系统随时知道进度、哪些已完成、下一步做什么
3. **失败恢复能力**：支持从中间状态恢复执行（工具失败、网络中断等）

## 上下文、状态与记忆的区别

| 概念 | 比喻 | 说明 |
|------|------|------|
| 上下文 | 草稿纸 | 当前轮决策能看到的信息，会变化、裁剪、覆盖 |
| State | 快照 | 记录当前运行到哪个环节，Runtime 必须知道 |
| 记忆 | 笔记本 | 长期保存、未来可检索，不会因 prompt 结束而消失 |

## Agent 的记忆类型

| 类型 | 存储方式 | 职责 | 生命周期 |
|------|----------|------|----------|
| 工作记忆 | Runtime 内存 / Context window | 当前目标、步骤、最近错误 | 短，token 成本高 |
| 程序性记忆 | Skill 文件 | 调试流程、Tool 规范、Coding Style | 按需加载 |
| 情景记忆 | Append-only Event Log | 发生过什么（jsonl） | 跨会话检索 |
| 语义记忆 | MEMORY.md / SQL / KV / VectorDB | 用户偏好、项目配置等长期知识 | 启动时注入 |

## Skill 与 Tool

- **Skill**：决定"怎么做"（如何 Debug、如何定位问题）。本身不执行动作，而是指导 Agent 什么时候该用什么工具
- **Tool**：决定"能做什么"（read_file、run_test）。真正执行动作

### ACI 工具设计原则

工具应对应 Agent 的目标，而非底层 API 操作。不要暴露 `create_file`、`write_content`、`set_permissions`，而是给一个高层次的 `create_script(path, content, executable)`。

核心标准：
1. 参数语义明确（date 是入住还是离店？必须描述清楚）
2. 职责清晰（预订酒店的前提是搜索酒店，description 必须说明）
3. 错误可恢复（返回结构化错误码 + 修正建议，避免 Agent 无限重试卡死）
