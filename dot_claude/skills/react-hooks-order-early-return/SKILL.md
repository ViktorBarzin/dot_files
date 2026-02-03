---
name: react-hooks-order-early-return
description: |
  Fix for "Rendered more hooks than during the previous render" or "React has detected
  a change in the order of Hooks called by Component" errors. Use when: (1) useEffect
  is placed after an early return statement, (2) conditional rendering causes different
  hook counts between renders, (3) hooks are called inside conditions or loops.
  Covers React Rules of Hooks violations and proper hook ordering.
author: Claude Code
version: 1.0.0
date: 2026-02-01
---

# React Hooks Order Violation with Early Returns

## Problem
React throws "Rendered more hooks than during the previous render" or similar hook
ordering errors when hooks are called conditionally or after early return statements.

## Context / Trigger Conditions
- Error: "React has detected a change in the order of Hooks called by [Component]"
- Error: "Rendered more hooks than during the previous render"
- Component has an early return (e.g., `if (!user) return <LoginModal />`)
- Hooks (useState, useEffect, useCallback, etc.) are defined after the early return
- Error appears when state changes cause the early return to be skipped

## Solution

### Rule: All hooks must be called before any early returns

**Wrong** (hooks after early return):
```tsx
function App() {
  const [user, setUser] = useState(null);

  // Early return
  if (!user) {
    return <LoginModal />;
  }

  // BUG: This useEffect only runs when user exists
  // causing different hook count between renders
  useEffect(() => {
    loadUserData();
  }, []);

  return <Dashboard user={user} />;
}
```

**Correct** (all hooks before early return):
```tsx
function App() {
  const [user, setUser] = useState(null);

  // All hooks must be called unconditionally
  useEffect(() => {
    if (user) {
      loadUserData();
    }
  }, [user]);

  // Early return after all hooks
  if (!user) {
    return <LoginModal />;
  }

  return <Dashboard user={user} />;
}
```

### For Complex Logic: Use useCallback

When you need to call a function from multiple places (including effects):

```tsx
function App() {
  const [user, setUser] = useState(null);
  const [data, setData] = useState(null);

  // Define callback BEFORE early return
  const loadData = useCallback(async () => {
    if (!user) return;
    const result = await fetchData(user);
    setData(result);
  }, [user]);

  // Effect uses the callback
  useEffect(() => {
    loadData();
  }, [user, loadData]);

  // Early return AFTER all hooks
  if (!user) {
    return <LoginModal />;
  }

  return <Dashboard data={data} />;
}
```

## Verification
1. Component renders without hook errors
2. State changes that affect early return don't cause crashes
3. React DevTools shows consistent hook order

## Example

**Scenario**: Auto-loading data when user authenticates

**Before** (broken):
```tsx
if (!user) {
  return <LoginModal />;
}

// useEffect after early return - BREAKS
useEffect(() => {
  onSubmit('visualize', defaultParams);
}, []);
```

**After** (fixed):
```tsx
// useCallback defined before early return
const loadListings = useCallback(async (params) => {
  if (!user) return;
  // ... loading logic
}, [user]);

// useEffect before early return, with user check inside
useEffect(() => {
  if (!user) return;
  loadListings(defaultParams);
}, [user, loadListings]);

// Early return AFTER all hooks
if (!user) {
  return <LoginModal />;
}
```

## Notes

- **Rules of Hooks**: Hooks must be called in the same order on every render
- **No conditional hooks**: Never put hooks inside if statements, loops, or after returns
- **Linting**: ESLint plugin `eslint-plugin-react-hooks` catches most violations
- **The fix pattern**: Move hook definitions before early returns, add conditions inside hooks

## References
- [React: Rules of Hooks](https://react.dev/reference/rules/rules-of-hooks)
- [React: Hooks FAQ](https://react.dev/learn/reusing-logic-with-custom-hooks)
