---
name: claude-memory-api
description: Store and recall persistent memories using the memory-tool CLI. Use when the user asks to remember something, recall a previous memory, or when you want to persist knowledge across sessions.
---

# Claude Memory API

You have access to a persistent memory system via the `memory-tool` CLI command.

## When to Use

- User says "remember this", "save this", "note that..."
- User asks "do you remember...", "what do you know about...", "recall..."
- You discover important facts worth persisting (user preferences, project patterns, debugging insights)
- You need to check if you already know something before asking the user

## Commands

### Store a memory
```bash
memory-tool store "content to remember" --category <category> --tags "tag1,tag2"
```
Categories: `facts`, `preferences`, `patterns`, `debugging`, `architecture`

### Recall memories (semantic search)
```bash
memory-tool recall "search query"
```

### List all memories
```bash
memory-tool list
memory-tool list --category facts
```

### Delete a memory
```bash
memory-tool delete <memory-id>
```

## Guidelines

- Always `recall` before storing to avoid duplicates
- Use specific, descriptive content — memories should be self-contained
- Choose the most relevant category
- Add tags for better recall later
- When the user says "remember X", store it immediately and confirm
