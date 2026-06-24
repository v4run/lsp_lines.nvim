# lsp_lines.nvim — Render Refactor & Bug Fixes (Phase 1+2)

Date: 2026-06-24
Status: Approved

## Context

This repository is a personal fork of `lsp_lines.nvim` (originally by whynothugo)
that renders LSP diagnostics as virtual lines beneath the offending code. The fork
has layered several custom options on top of upstream:

- **`prefix`** — string or a resolver function returning prefix chunks per
  diagnostic (used by both the virt_lines and virt_text paths).
- **`only_current_line`** — accepts a table; can fall back to compact `virtual_text`
  for non-current lines while showing full virtual lines on the cursor line.
- **`only_count`** — collapses repeated per-line diagnostics into `[+N]` counts in
  the virt_text path.
- **`highlight_whole_line`** — extends the severity highlight across the whole line.

The implementation lives in two files: `lua/lsp_lines/init.lua` (handler
registration + current-line filtering) and `lua/lsp_lines/render.lua` (~370 lines
doing *two* unrelated jobs: virtual-lines rendering and virtual-text rendering).

The owner has authorized free refactoring of the internal API (this is a personal
fork; staying diffable against upstream is not a goal).

This spec covers **Phase 1 (foundation refactor)** and **Phase 2 (correctness
bug fixes)**. Phase 3 (tests + docs) and Phase 4 (new features) are deferred to
later cycles.

## Goals

1. Split the overloaded `render.lua` into focused, independently understandable
   modules.
2. Collapse the 7-positional `M.show` signature into a clear, documented shape.
3. Fix five known correctness bugs without changing any user-facing option names
   or behavior.

## Non-Goals

- No new user-facing features (configurable highlight groups, severity filtering,
  insert-mode behavior) — that is Phase 4.
- No test harness or option documentation yet — that is Phase 3.
- No effort to remain diffable against upstream.

## Phase 1 — Foundation Refactor

### Module layout

```
lua/lsp_lines/
  init.lua         -- handler registration + current-line filtering (unchanged role)
  render.lua       -- thin dispatcher: M.show / M.hide only
  virt_lines.lua   -- the virtual-lines renderer (moved from render.lua)
  virt_text.lua    -- the virtual-text renderer (moved from render.lua)
  highlights.lua   -- HIGHLIGHTS map + severities list (shared)
```

- `highlights.lua` exports the `HIGHLIGHTS` table (`native` / `coc` severity →
  highlight-group maps) and the ordered `severities` list. Both `virt_lines.lua`
  and `virt_text.lua` require it.
- `virt_lines.lua` exports a single function (the current `render_as_virt_lines`)
  including its `distance_between_cols` helper.
- `virt_text.lua` exports a single function (the current `render_as_virt_text`).
- `render.lua` keeps only `M.show` (dispatch + validation + sort + clear) and
  `M.hide`, delegating to the two renderer modules.

### API change

Collapse the trailing control flags into one optional `ctx` table:

```lua
-- before:
M.show(namespace, bufnr, diagnostics, opts, source, render_area, clear)

-- after:
M.show(namespace, bufnr, diagnostics, opts, ctx)
--   opts : the vim.diagnostic opts table (unchanged public contract)
--   ctx  : optional, with defaults:
--          { source = "native", area = "virt_lines", clear = true }
```

- `opts` is left untouched because `vim.diagnostic` passes it to the handler;
  breaking it would break the diagnostic-handler contract.
- The internal caller in `init.lua` (`render_current_line`) is updated to pass the
  new `ctx` table instead of the trailing positional args. Its non-current-line
  virt_text call becomes `ctx = { area = "virt_text", clear = false }`.
- `area` replaces the previous `render_area`; values are `"virt_lines"`
  (default) and `"virt_text"`.

### Cleanup

- Remove commented-out / dead code: the `msg = string.format(...)` dead branch in
  the virt_lines path (the `if diagnostic.code` block that assigns the same value
  in both branches), the commented `severity_counts` lines, the commented
  `opts = opts.virtual_lines.virtual_text` block, and stale rename `TODO:`s that
  no longer apply after the split.
- Keep the explanatory comments that document the rendering algorithm (the
  stack-walking logic, the magic-number clarifications).

### User-facing options preserved exactly

`prefix`, `only_current_line` (boolean or table), `only_count`,
`highlight_whole_line` keep their names, accepted types, and behavior. The refactor
is internal only.

## Phase 2 — Correctness Bug Fixes

### Bug 1 — virt_text aborts on the first blank-message line (highest impact)

`render.lua:278-281`: inside `for _, diags in pairs(line_diagnostics)`, when a
line's diagnostics are all whitespace, `best` stays `nil` and the code executes
`return`, exiting the *entire* `render_as_virt_text` function. Every line iterated
after that one silently loses its virtual text.

**Fix:** restructure the per-line loop body so a `nil` `best` skips only the current
line (`goto continue` with a `::continue::` label, or extract the body into a local
function and `return` from that). No diagnostics for other lines are affected.

### Bug 2 — `col=0, row=0` whole-file diagnostics render nonsensically

Recorded in `TODO.md`. Diagnostics at `(lnum=0, col=0)` typically refer to the
whole file; the tree/alignment glyphs (`╰───`, left padding) are meaningless there.

**Fix:** in the virt_lines path, detect diagnostics anchored at `col == 0` on
`lnum == 0` (whole-file diagnostics) and render them as a plain prefixed line at the
top of the buffer, without the leading alignment spaces and connector glyphs. The
prefix + message + severity highlight are still shown.

### Bug 3 — stale diagnostics after LSP restart

`init.lua:46` TODO. In `only_current_line` mode the `CursorMoved` autocmd callback
closes over the `diagnostics` list captured when the handler last ran. After an LSP
restart clears diagnostics, the stale closed-over list keeps re-rendering removed
diagnostics.

**Fix:** the `CursorMoved` callback re-fetches the live diagnostics via
`vim.diagnostic.get(bufnr)` (filtered to the relevant namespace) instead of using
the captured list, so cleared diagnostics disappear on the next cursor move. The
initial pre-`CursorMoved` render keeps using the handler-provided list.

### Bug 4 — multiline diagnostics in the virt_text path

The `FIX:` block at `render.lua:209-213` flags diagnostics spanning multiple lines
and embedded newlines as inconsistently handled in virt_text.

**Fix:** normalize the message to a single line before measuring/inserting — collapse
`\r` and `\n` (and runs thereof) into single spaces consistently in one place, so
multiline messages render as one flattened virt_text chunk.

### Bug 5 — `only_count` severity-count logic

`render.lua:287-305`: contains empty `else` branches and counts the "best" severity
by subtracting 1 only for that severity, which is fragile.

**Fix:** remove the dead `else` branches and compute each severity's overflow count
uniformly: for the severity that contributed `best`, show `count - 1` (the best one
is already displayed); for all other severities, show `count`. Suppress the `[+0]`
case. Behavior for the common cases is unchanged; the logic is just made correct and
readable.

## Testing strategy (manual, this phase)

Phase 3 introduces an automated harness. For Phase 1+2, verification is manual in a
running Neovim:

- Open a buffer with diagnostics on multiple lines where one line's only diagnostic
  is whitespace; confirm later lines still get virt_text (Bug 1).
- Trigger a whole-file `(0,0)` diagnostic; confirm a clean top-of-file line (Bug 2).
- Restart the LSP / clear diagnostics in `only_current_line` mode; confirm stale
  lines disappear on cursor move (Bug 3).
- Show a multiline diagnostic in virt_text mode; confirm single flattened line
  (Bug 4).
- Show multiple diagnostics of several severities on one line with `only_count`;
  confirm correct `[+N]` counts (Bug 5).

## Risks

- Splitting modules could shift `require` ordering; mitigated by keeping
  `highlights.lua` dependency-free.
- Re-fetching diagnostics in the `CursorMoved` callback changes timing; mitigated by
  filtering to the same namespace the handler used.
