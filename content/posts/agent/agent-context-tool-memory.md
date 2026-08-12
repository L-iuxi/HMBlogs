---
title: "Agent 学习笔记 — 上下文工程、工具与记忆"
date: "2026-08-12T14:00:00+08:00"
tags: ["Agent", "上下文工程"]
title-images: []
ending-images: []
author: "烩面"
draft: false
table-of-contents: true
toc-auto-numbering: false
---
<!-- introduction -->
Agent 智能体核心概念：从反射智能体到 LLM 智能体的演进、上下文工程分层设计、ACI 工具设计原则，以及四种记忆类型的存储策略。
<!--more-->

## 什么是 Agent

**智能体被定义为任何能够通过传感器（Sensors）感知其所处环境（Environment），并自主地通过执行器（Actuators）采取行动（Action）以达成特定目标的实体。**

## Agent 的演进历程

- **反射智能体**：例如传感器，恒温系统
- **基于模型的反射智能体**：例如自动驾驶汽车，基于内部模型做出决策
- **基于目标的智能体**：例如 GPS 导航系统，用搜索算法找最优路径
- **基于效用的智能体**：最大化效益期望，如省油省时的路径规划
- **学习型智能体**：强化学习，例如 AlphaGo
- **LLM 智能体**：基于大模型实现信息整合与决策，如旅游助手

## 智能体的运行模式

1. **感知**：接受来自环境的初始信息，比如用户的指令
2. **思考**：规划分解子任务 + 选择工具
3. **行动**：根据决策和工具做出具体行动

## 常见的智能体控制模式

| 模式 | 说明 |
|------|------|
| 提示链 | 按步骤执行，每步 LLM 处理上一步输出 |
| 路由 | 对输入分类定向到专门处理流程 |
| 并行 | 多步骤并行处理，适合高风险决策或多视角 |
| 编排器 | 中央 LLM 动态分解任务，委派给工作者 LLM |
| 评估优化 | 生成器产出 → 评估器反馈 → 循环直到达标 |

## Agent Loop 简单实现

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
      response.content
        .filter((b) => b.type === "tool_use")
        .map(async (b) => ({
          type: "tool_result" as const,
          tool_use_id: b.id,
          content: await executeTool(b.name, b.input),
        }))
    );
    messages.push({ role: "assistant", content: response.content });
    messages.push({ role: "user", content: toolResults });
  } else {
    return response.content.find((b) => b.type === "text")?.text ?? "";
  }
}
```

## 上下文工程

### 为什么要分层压缩

Transformer 的注意力复杂度是 O(n²)。上下文越长，无关内容占比越大，直接影响 Agent 决策质量。

### 五层架构

| 层级 | 内容 | 策略 |
|------|------|------|
| 常驻层 | 身份定义、项目约定、绝对禁止项 | 每次会话必加载，短、硬、可执行 |
| 按需加载 | Skills 和领域知识 | 描述符常驻，完整内容触发时注入 |
| 运行时注入 | 当前时间、用户偏好等动态信息 | 每轮按需拼入 |
| 记忆层 | 跨会话经验 | 写入 MEMORY.md，需要时才读 |
| 系统层 | Hooks 或代码规则 | 完全不进上下文 |

### 常见压缩策略

- **滑动窗口**：丢弃旧消息，适合短期任务
- **LLM 摘要**：总结模型输出，适合长任务
- **工具结果替换**：适合工具调用密集型场景

## Skill 设计

Skill 的核心思路：系统提示只保留索引，完整知识按需加载。

描述符要简洁精准：

- 低效（约 45 tokens）：`This skill handles the complete deployment process to production. It covers environment checks, rollback procedures...`
- 高效（约 9 tokens）：`Use when deploying to production or rolling back.`

数量控制：常驻只放高频 Skill，低频按需引入，极低频用文档替代。

## 工具设计的演变

**第一代 API 封装**：每个 API Endpoint 一个工具，粒度过细。

**第二代 ACI（Agent-Computer Interface）**：工具对应 Agent 目标，而非底层 API。不暴露 `create_file`、`write_content`、`set_permissions`，而是给一个 `create_script(path, content, executable)`。

**第三代 Advanced Tool Use**：
- Tool Search：按需发现工具，上下文保留率达 95%
- Programmatic Tool Calling：模型用代码编排多个工具调用，中间结果不进 LLM 上下文
- Tool Use Examples：每个工具附带 1-5 个调用示例，准确率从 72% 提升到 90%

## ACI 工具设计原则

**差的工具**：参数模糊、错误不可修正、定义实现分离

**好的工具**（betaZodTool）：定义和实现绑在一起，参数描述直接约束格式，错误结构化给出修正建议：

```typescript
const updateTool = betaZodTool({
  name: "update_yuque_post",
  description: "更新语雀文章内容，不适合创建新文章",
  inputSchema: z.object({
    post_id: z.string().describe("语雀文章 ID，纯数字字符串"),
    content_markdown: z.string().describe("Markdown 格式正文"),
  }),
  run: async (input) => {
    const post = await getPost(input.post_id);
    if (!post) throw new ToolError("文章 ID 不存在", {
      error_code: "POST_NOT_FOUND",
      suggestion: "请先调用 list_yuque_posts 获取有效的 post_id",
    });
    return await updatePost(input.post_id, undefined, input.content_markdown);
  },
});
```

## 记忆系统

Agent 不具备原生的时间连续性。会话结束后上下文清空，记忆层必须单独设计。

| 类型 | 存储 | 职责 |
|------|------|------|
| 工作记忆 | Context window | 当前任务最小必要信息 |
| 程序性记忆 | Skills 文件 | 怎么做某件事，按需加载 |
| 情景记忆 | JSONL 会话历史 | 发生过什么，跨会话检索 |
| 语义记忆 | MEMORY.md | Agent 主动写入的重要事实，启动时注入 |
