---
name: mapbox-heatmap-small-dataset-crash
description: |
  Fix for Mapbox GL JS "ExpressionEvaluationError: Input is not a number" when using
  data-driven paint properties (legacy `{ property, stops }` format or interpolate
  expressions). Use when: (1) heatmap or fill layer crashes after filtering reduces
  the dataset to fewer than ~20 features, (2) switching metrics or filter parameters
  triggers the error intermittently, (3) color stops produce NaN values from percentile
  calculations. Root causes: out-of-bounds percentile index on small arrays, non-monotonic
  stops when min === max, and stale color stops from a previous metric remaining active
  when no valid values exist for the new metric.
author: Claude Code
version: 1.0.0
date: 2026-02-08
---

# Mapbox Heatmap Crash on Small Datasets

## Problem

Mapbox GL JS throws `ExpressionEvaluationError: Input is not a number` when a data-driven
paint property (e.g., `fill-color` based on a feature property) encounters non-numeric
values in color stops or feature properties. This commonly surfaces when dynamic filtering
reduces the visible dataset to a small number of features.

## Context / Trigger Conditions

- Using legacy Mapbox property functions: `{ property: "count", stops: [[val, color], ...] }`
- Mapbox GL JS v2+ internally converts legacy format to `["interpolate", ["linear"], ["number", ["get", "count"]], ...]`
- The `["number", ...]` assertion throws if the input is not a number (including `NaN`)
- Error appears in stack as: `vi → zs → evaluate → populatePaintArray → ... → reloadTile`

Common triggers:
1. Filtering data down to 1-20 features (percentile index goes out of bounds)
2. Switching metrics where the new metric has sparse/missing data
3. Color stops from a previous metric remaining active for new data

## Solution

### 1. Clamp percentile indices to array bounds

The most common cause: `Math.round(values.length * 0.95)` exceeds `values.length - 1`
for small arrays.

```typescript
// BAD: out-of-bounds when values.length < 20
const maxIndex = Math.round(values.length * 0.95);
const max = values[maxIndex]; // undefined!

// GOOD: clamp to valid range
const maxIndex = Math.min(
  Math.round(values.length * PERCENTILE_MAX),
  values.length - 1
);
const max = values[maxIndex]; // always valid
```

Why: `Math.round(1 * 0.95) = 1` but a 1-element array's max index is 0. The returned
`undefined` cascades: `Math.max(undefined, x)` = `NaN`, then `calculateColorStops(scheme, min, NaN)`
produces `[[NaN, color], ...]`, and Mapbox's expression evaluator throws.

### 2. Ensure strictly monotonic stops (guard min === max)

```typescript
const max = Math.max(values[maxIndex], min + 1);
```

When all features have the same metric value, `min === max`. The legacy format's internal
conversion to `["interpolate", ...]` requires strictly increasing stop inputs.

### 3. Always set color stops (never leave stale stops)

```typescript
if (values.length > 0) {
  const stops = calculateColorStops(scheme, min, max);
  heatmap.setColorStops(stops);
} else {
  // Don't skip — stale stops from a previous metric cause range mismatches
  const stops = calculateColorStops(scheme, 0, 1);
  heatmap.setColorStops(stops);
}
```

### 4. Filter Infinity from metric values

```typescript
.filter(v => typeof v === 'number' && isFinite(v) && v > 0)
```

`isNaN(Infinity)` is `false`, so `Infinity` passes NaN checks but can produce
non-monotonic or degenerate stops.

### 5. Don't inject undefined into feature properties

When injecting synthetic properties for heatmap coloring, skip features without data
rather than setting the property to `undefined`:

```typescript
// BAD: Mapbox sees { poi_travel_7_WALK: undefined }
return { ...feature, properties: { ...feature.properties, [prop]: match?.value } };

// GOOD: feature unchanged, property simply absent
if (!match) return feature;
return { ...feature, properties: { ...feature.properties, [prop]: match.value } };
```

## Verification

1. Set a tight filter that reduces data to 1-5 features — no crash
2. Switch between metrics rapidly — no crash
3. Select a metric with no data (e.g., uncomputed travel mode) — graceful empty map
4. All features have identical metric value — colors still render

## Notes

- The legacy `{ property, stops }` format still works for colors in Mapbox GL JS v2+
  but is internally converted to expressions. Don't "fix" it by switching to expression
  format manually — color interpolation with `rgba()` strings works in legacy format
  but can break if the expression is constructed incorrectly.
- The `["number", value, fallback]` syntax is NOT a valid Mapbox expression. `"number"`
  is a type assertion that throws on non-numbers. For fallbacks, use
  `["coalesce", ["to-number", ["get", "prop"]], 0]` instead.
- HexgridHeatmap's reduce function handles `undefined` and `NaN` via `isNaN()` checks,
  but `isNaN(null) === false`, so null values pass through as 0.

See also: react-hooks-order-early-return (hooks after early returns cause similar
intermittent crashes during UI interactions)
