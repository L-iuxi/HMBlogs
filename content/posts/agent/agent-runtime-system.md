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

例如，当 state 是：

```
"panic 在 server.go:42，疑似 nil pointer"
```

LLM 会做出判断：需要读取 struct 定义、需要检查初始化逻辑、需要修改防御性判断，于是生成下一步 action：

```
ToolCall: read_file(server.go)
```

**LLM 在 Agent 中不直接"执行"，只负责"决定"。**

### Execute 执行层

执行层负责把 LLM 的决策真正落地为现实动作，它是 Agent 与外部世界交互的接口。如果说 LLM 是"大脑"，那么执行层就是"手和脚"。

执行不光改变事件，有时还会产生新事件。例如在 coding agent 中，执行层可能会：修改代码文件、执行测试命令、调用 API、查询数据库。当 LLM 判断"问题可能出现在 server.go 的空指针判断逻辑"时，生成了一个 action：

```
apply_patch(server.go)
```

执行层真正完成修改后，会返回新的结果：

```
ToolResultEvent: patch applied
```

随后 Agent 会继续执行测试，如果测试失败，那么将失败事件作为状态，在这个基础上进行下一步的决策。

**Execute 不是终点，而是下一轮决策的开始。** 这种不断"行动 → 反馈 → 再行动"的闭环，才是 Agent 能够持续完成复杂任务的核心原因。

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

Agent 的记忆系统，本质上是一个分层存储系统。不同类型的 Memory，通常会采用不同的存储结构。按照 Agent 实际要解决的问题，大致分以下几种：

1. **Working Memory（工作记忆）**：负责存储当前任务最小必要信息——当前目标、当前步骤、最近错误、Tool 输出。这类记忆生命周期短，访问频率高，token 成本高，通常不会长期持久化，直接存在 Runtime 内存 / Context window。

2. **Procedural Memory（程序性记忆）**：负责记录"如何做事情"，比如调试流程、Tool 使用规范、Coding Style、工作流模板。例如：

   ```
   实现功能前先设计接口
   修改代码后必须执行测试
   ```

   程序性记忆比较长、低频，只在某些特定场景下使用，通常采用按需加载，以 skill 文件的方式出现。

3. **Episodic Memory（情景记忆）**：记录"发生过什么"，比如：

   ```json
   {
     "time": "2026-05-18",
     "event": "watch panic",
     "cause": "backend nil"
   }
   ```

   这类记忆支持跨会话检索，通常采用 Append-only Event Log。

4. **Semantic Memory（语义记忆）**：Agent 主动写入认为重要的事实，每次启动时注入系统提示。语义记忆主要存储长期稳定知识，比如：

   ```
   用户喜欢详细解释
   项目使用 Mysql
   ```

   常用的存储方式有：MEMORY.md（可读、可编辑、LLM 友好），或者 SQL、KV、GraphDB、VectorDB。

## Skill 与 Tool

上下文、记忆决定模型"能看到什么"，而工具决定模型"能做什么"。如果没有工具，LLM 无论推理能力多强，本质上仍然只能停留在"文本生成"层面。它可以分析问题、给出建议，但无法真正对外部世界产生影响。

- **Skill**：决定"怎么做"（如何 Debug、如何定位问题）。本身不执行动作，而是指导 Agent "什么时候该用什么工具"。例如，一个 Debug Skill 可能描述：

  ```
  1. 先读取错误日志
  2. 根据 stack trace 定位文件
  3. 检查 nil pointer
  4. 运行测试验证
  ```

- **Tool**：决定"能做什么"，真正执行动作的是：

  ```
  read_file()
  run_test()
  ```

  Skill 决定"怎么做"，Tool 决定"能做什么"。

### ACI 工具设计原则

ACI，即 Agent-Computer Interface：工具应对应 Agent 的目标，而不是底层 API 操作。现代 Agent Runtime 强调 Tool 不再只是给人调用的函数，而是"给模型调用的接口"，所以 Tool 的设计至关重要。

下面以一个旅游助手为例。先看一段有问题的 Tool：

```typescript
const tool = {
  name: "book_hotel",
  input_schema: {
    properties: {
      city: { type: "string" },
      hotel: { type: "string" },
      date: { type: "string" },
    },
  },
};
```

上面这段 Tool 的问题在于：

1. **参数语义模糊**：`date` 的具体语义并没有加以说明，模型并不知道是出发日期还是离开日期、时间范围，可能出现输入之后 Tool 无法解析的情况。
2. **Tool 职责不清晰**：没有定义清楚 Tool 的职责，LLM 可能会传不合适的 token，导致系统行为无法预测。
3. **错误不可恢复**：返回失败之后，模型不知道到底为什么失败，Agent 可能会无限重试，导致卡死。

而一个更适合 Agent 的 Tool：

```typescript
const bookHotelTool = betaZodTool({
  name: "book_hotel",
  description: "预订已存在的酒店，不负责搜索酒店。调用前必须先使用 search_hotels 获取 hotel_id",
  inputSchema: z.object({
    hotel_id: z.string().describe("酒店唯一ID，例如 'HOTEL_93821'"),
    check_in_date: z.string().describe("入住日期，格式 YYYY-MM-DD"),
    check_out_date: z.string().describe("离店日期，格式 YYYY-MM-DD"),
    guest_count: z.number().describe("入住人数，例如 1 或 2"),
  }),
  run: async (input) => {
    const hotel = await getHotel(input.hotel_id);
    if (!hotel) {
      throw new ToolError("酒店不存在", {
        error_code: "HOTEL_NOT_FOUND",
        suggestion: "请先调用 search_hotels 获取有效 hotel_id",
      });
    }
    if (hotel.rooms <= 0) {
      throw new ToolError("酒店满房", {
        error_code: "NO_AVAILABLE_ROOM",
        suggestion: "请重新调用 search_hotels 查找其他酒店",
      });
    }
    return await bookHotel(input);
  },
});
```

核心标准：

1. 参数语义明确（`check_in_date` 是入住日期，`check_out_date` 是离店日期，格式 YYYY-MM-DD，必须描述清楚）
2. 职责清晰（预订酒店的前提是搜索酒店，description 必须说明"调用前必须先使用 search_hotels"）
3. 错误可恢复（返回结构化错误码 + 修正建议，避免 Agent 无限重试卡死）
