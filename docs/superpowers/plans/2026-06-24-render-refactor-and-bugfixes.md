# Render Refactor & Bug Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the overloaded `render.lua` into focused modules, collapse the 7-positional `M.show` signature into a `ctx` table, and fix five known correctness bugs — all without changing user-facing option names or behavior.

**Architecture:** Move the two renderers (`render_as_virt_lines`, `render_as_virt_text`) and the shared highlight maps out of `render.lua` into dedicated modules. `render.lua` becomes a thin dispatcher (`M.show`/`M.hide`). `init.lua` is updated to the new call shape. Then apply five surgical bug fixes in the new module homes.

**Tech Stack:** Lua, Neovim diagnostic API (`vim.diagnostic`, `vim.api.nvim_buf_set_extmark`), stylua for formatting.

---

## Conventions for every task

- Formatting: run `stylua --check lua/` after edits; if it reports diffs, run `stylua lua/` then re-check.
- Load smoke test: `nvim --headless -c "lua require('lsp_lines').setup()" -c "qa" 2>&1` must print nothing and exit 0 (a Lua error prints a traceback).
- This phase has no automated test harness (that is Phase 3). Verification is `stylua --check`, the headless load test, and the manual checks noted per bug task.
- Commit after each task with the message shown.

---

## File Structure

```
lua/lsp_lines/
  init.lua         -- handler registration + current-line filtering
  render.lua       -- thin dispatcher: M.show / M.hide
  virt_lines.lua   -- virtual-lines renderer (new)
  virt_text.lua    -- virtual-text renderer (new)
  highlights.lua   -- HIGHLIGHTS map + severities list (new)
```

---

## Task 1: Extract `highlights.lua`

**Files:**
- Create: `lua/lsp_lines/highlights.lua`
- Modify: `lua/lsp_lines/render.lua` (remove the moved `HIGHLIGHTS` and `severities` definitions later, in Task 4)

- [ ] **Step 1: Create the shared highlights module**

Create `lua/lsp_lines/highlights.lua`:

```lua
local M = {}

M.HIGHLIGHTS = {
  native = {
    [vim.diagnostic.severity.ERROR] = "DiagnosticVirtualTextError",
    [vim.diagnostic.severity.WARN] = "DiagnosticVirtualTextWarn",
    [vim.diagnostic.severity.INFO] = "DiagnosticVirtualTextInfo",
    [vim.diagnostic.severity.HINT] = "DiagnosticVirtualTextHint",
  },
  coc = {
    [vim.diagnostic.severity.ERROR] = "CocErrorVirtualText",
    [vim.diagnostic.severity.WARN] = "CocWarningVirtualText",
    [vim.diagnostic.severity.INFO] = "CocInfoVirtualText",
    [vim.diagnostic.severity.HINT] = "CocHintVirtualText",
  },
}

M.severities = {
  vim.diagnostic.severity.ERROR,
  vim.diagnostic.severity.WARN,
  vim.diagnostic.severity.INFO,
  vim.diagnostic.severity.HINT,
}

return M
```

- [ ] **Step 2: Verify the module loads**

Run: `nvim --headless -c "lua assert(require('lsp_lines.highlights').HIGHLIGHTS.native[vim.diagnostic.severity.ERROR] == 'DiagnosticVirtualTextError')" -c "qa" 2>&1`
Expected: no output, exit 0.

- [ ] **Step 3: Format check**

Run: `stylua --check lua/lsp_lines/highlights.lua`
Expected: no output (clean). If it reports a diff, run `stylua lua/lsp_lines/highlights.lua`.

- [ ] **Step 4: Commit**

```bash
git add lua/lsp_lines/highlights.lua
git commit -m "refactor: extract shared highlights module"
```

---

## Task 2: Extract `virt_lines.lua`

**Files:**
- Create: `lua/lsp_lines/virt_lines.lua`
- Source of moved code: `lua/lsp_lines/render.lua:33-197` (`distance_between_cols` + `render_as_virt_lines`)

- [ ] **Step 1: Create the virt_lines module scaffold and move the renderer**

Create `lua/lsp_lines/virt_lines.lua`. Move the `distance_between_cols` helper (currently `render.lua:33-39`) and the `render_as_virt_lines` function body (currently `render.lua:42-197`) **verbatim** into this module, with these adjustments:

1. Pull `HIGHLIGHTS` from the new module via `require`.
2. Reference the constant locals (`SPACE`, `DIAGNOSTIC`, `OVERLAP`, `BLANK`) here (move them too).
3. Apply the dead-code cleanup noted in the spec: replace the `if diagnostic.code then ... else ... end` block (currently `render.lua:164-169`) — which assigns `msg = diagnostic.message` in both branches — with a single `local msg = diagnostic.message`. Remove the commented `-- msg = string.format(...)` line and the `-- local center_text =` line.
4. Expose the renderer as `M.render`.

The module structure:

```lua
local highlights = require("lsp_lines.highlights")
local HIGHLIGHTS = highlights.HIGHLIGHTS

local M = {}

-- These don't get copied, do they? We only pass around and compare pointers, right?
local SPACE = "space"
local DIAGNOSTIC = "diagnostic"
local OVERLAP = "overlap"
local BLANK = "blank"

---Returns the distance between two columns in cells.
---
---Some characters (like tabs) take up more than one cell.
---Additionally, inline virtual text can make the distance between two columns larger.
---A diagnostic aligned
---under such characters needs to account for that and add that many spaces to
---its left.
---
---@return integer
local function distance_between_cols(bufnr, lnum, start_col, end_col)
  return vim.api.nvim_buf_call(bufnr, function()
    local s = vim.fn.virtcol({ lnum + 1, start_col })
    local e = vim.fn.virtcol({ lnum + 1, end_col + 1 })
    return e - 1 - s
  end)
end

---@param namespace number
---@param bufnr number
---@param diagnostics table
---@param opts table
---@param source 'native'|'coc'|nil
function M.render(namespace, bufnr, diagnostics, opts, source)
  -- <<< MOVE the body of render_as_virt_lines here verbatim, applying
  --     the cleanup in adjustment #3 above. >>>
end

return M
```

> Implementation note for the mover: the moved body uses `HIGHLIGHTS[source or "native"]` (now resolved via the `require`d `highlights` module) and the `SPACE/DIAGNOSTIC/OVERLAP/BLANK` locals defined above. Do not change any rendering logic — this is a move plus the dead-code deletion only.

- [ ] **Step 2: Format check**

Run: `stylua --check lua/lsp_lines/virt_lines.lua`
Expected: clean (or run `stylua lua/lsp_lines/virt_lines.lua`).

- [ ] **Step 3: Verify the module loads and exposes `render`**

Run: `nvim --headless -c "lua assert(type(require('lsp_lines.virt_lines').render) == 'function')" -c "qa" 2>&1`
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add lua/lsp_lines/virt_lines.lua
git commit -m "refactor: extract virt_lines renderer into its own module"
```

---

## Task 3: Extract `virt_text.lua`

**Files:**
- Create: `lua/lsp_lines/virt_text.lua`
- Source of moved code: `lua/lsp_lines/render.lua:207-316` (`render_as_virt_text`)

- [ ] **Step 1: Create the virt_text module and move the renderer**

Create `lua/lsp_lines/virt_text.lua`. Move `render_as_virt_text` (currently `render.lua:207-316`) **verbatim** into `M.render`, with these cleanups:

1. `require` `severities` and `HIGHLIGHTS` from the highlights module (do not redefine them locally).
2. Delete the commented `FIX:`/`SUGGEST:` comment block and the commented `opts = opts.virtual_lines.virtual_text` block (currently `render.lua:209-220`) — these are addressed by the bug-fix tasks below; keep no stale comments.
3. Delete the commented `-- local severity_counts = {}` and `-- severity_counts[severity] = ...` lines.

Scaffold:

```lua
local highlights = require("lsp_lines.highlights")
local HIGHLIGHTS = highlights.HIGHLIGHTS
local severities = highlights.severities

local M = {}

---@param namespace number
---@param bufnr number
---@param diagnostics table
---@param opts table
---@param source 'native'|'coc'|nil
function M.render(namespace, bufnr, diagnostics, opts, source)
  -- <<< MOVE the body of render_as_virt_text here verbatim, applying
  --     cleanups #2 and #3 above. Leave the actual rendering logic
  --     unchanged; bug fixes come in Tasks 6-10. >>>
end

return M
```

- [ ] **Step 2: Format check**

Run: `stylua --check lua/lsp_lines/virt_text.lua`
Expected: clean (or run `stylua lua/lsp_lines/virt_text.lua`).

- [ ] **Step 3: Verify the module loads and exposes `render`**

Run: `nvim --headless -c "lua assert(type(require('lsp_lines.virt_text').render) == 'function')" -c "qa" 2>&1`
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add lua/lsp_lines/virt_text.lua
git commit -m "refactor: extract virt_text renderer into its own module"
```

---

## Task 4: Slim `render.lua` to a dispatcher with the `ctx` API

**Files:**
- Modify (replace contents): `lua/lsp_lines/render.lua`

- [ ] **Step 1: Replace `render.lua` with the thin dispatcher**

Overwrite `lua/lsp_lines/render.lua` with:

```lua
local M = {}

local virt_lines = require("lsp_lines.virt_lines")
local virt_text = require("lsp_lines.virt_text")

---@param namespace number
---@param bufnr number
---@param diagnostics table
---@param opts table The vim.diagnostic opts table.
---@param ctx table|nil { source = 'native'|'coc', area = 'virt_lines'|'virt_text', clear = boolean }
function M.show(namespace, bufnr, diagnostics, opts, ctx)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  ctx = ctx or {}
  local source = ctx.source or "native"
  local area = ctx.area or "virt_lines"
  local clear = ctx.clear
  if clear == nil then
    clear = true
  end

  vim.validate({
    namespace = { namespace, "n" },
    bufnr = { bufnr, "n" },
    diagnostics = {
      diagnostics,
      vim.islist or vim.tbl_islist,
      "a list of diagnostics",
    },
    opts = { opts, "t", true },
  })

  table.sort(diagnostics, function(a, b)
    if a.lnum ~= b.lnum then
      return a.lnum < b.lnum
    else
      return a.col < b.col
    end
  end)

  if clear then
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  end
  if #diagnostics == 0 then
    return
  end

  if area == "virt_text" then
    virt_text.render(namespace, bufnr, diagnostics, opts, source)
  else
    virt_lines.render(namespace, bufnr, diagnostics, opts, source)
  end
end

---@param namespace number
---@param bufnr number
function M.hide(namespace, bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
end

return M
```

- [ ] **Step 2: Format check**

Run: `stylua --check lua/lsp_lines/render.lua`
Expected: clean (or run `stylua lua/lsp_lines/render.lua`).

- [ ] **Step 3: Verify the full chain loads**

Run: `nvim --headless -c "lua local r = require('lsp_lines.render'); assert(type(r.show) == 'function' and type(r.hide) == 'function')" -c "qa" 2>&1`
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add lua/lsp_lines/render.lua
git commit -m "refactor: make render.lua a thin dispatcher with ctx-table API"
```

---

## Task 5: Update `init.lua` to the new call shape

**Files:**
- Modify: `lua/lsp_lines/init.lua:21-32` (the `render_current_line` calls)

- [ ] **Step 1: Update the two `render.show` calls in `render_current_line`**

In `lua/lsp_lines/init.lua`, the function `render_current_line` currently calls `render.show` twice with positional control args. Replace lines 21-32:

```lua
  render.show(ns, bufnr, current_line_diag, opts)
  if opts.virtual_lines and opts.virtual_lines.only_current_line.virtual_text then
    render.show(
      ns,
      bufnr,
      not_current_line_diag,
      opts.virtual_lines.only_current_line.virtual_text,
      nil,
      "virt_text",
      false
    )
  end
```

with:

```lua
  render.show(ns, bufnr, current_line_diag, opts)
  if opts.virtual_lines and opts.virtual_lines.only_current_line.virtual_text then
    render.show(
      ns,
      bufnr,
      not_current_line_diag,
      opts.virtual_lines.only_current_line.virtual_text,
      { area = "virt_text", clear = false }
    )
  end
```

- [ ] **Step 2: Format check**

Run: `stylua --check lua/lsp_lines/init.lua`
Expected: clean (or run `stylua lua/lsp_lines/init.lua`).

- [ ] **Step 3: Verify setup still registers the handler**

Run: `nvim --headless -c "lua require('lsp_lines').setup(); assert(type(vim.diagnostic.handlers.virtual_lines.show) == 'function')" -c "qa" 2>&1`
Expected: no output, exit 0.

- [ ] **Step 4: Manual smoke check (refactor regression)**

Open a real file with an LSP attached (or any buffer where you can set diagnostics) and confirm virtual lines still render as before. Quick scripted check:

```bash
nvim --headless -c "lua
  require('lsp_lines').setup()
  local ns = vim.api.nvim_create_namespace('test')
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {'local x = 1', 'local y = 2'})
  vim.diagnostic.config({ virtual_lines = true, virtual_text = false })
  vim.diagnostic.set(ns, buf, {
    { lnum = 0, col = 0, end_lnum = 0, end_col = 5, severity = vim.diagnostic.severity.ERROR, message = 'boom' },
    { lnum = 1, col = 6, end_lnum = 1, end_col = 7, severity = vim.diagnostic.severity.WARN, message = 'careful' },
  })
  local marks = vim.api.nvim_buf_get_extmarks(buf, vim.diagnostic.get_namespace(ns).user_data.virt_lines_ns, 0, -1, { details = true })
  assert(#marks >= 1, 'expected virt_lines extmarks')
  print('OK marks=' .. #marks)
" -c "qa" 2>&1
```

Expected: prints `OK marks=...` with no traceback.

- [ ] **Step 5: Commit**

```bash
git add lua/lsp_lines/init.lua
git commit -m "refactor: update init.lua to the ctx-table render API"
```

---

## Task 5b: Bug 6 — default virt_lines `prefix` must resolve to a list of chunks

> Added during execution after the Task 5 smoke test exposed a pre-existing crash.

**Files:**
- Modify: `lua/lsp_lines/virt_lines.lua` (`M.render` default `prefix_resolver`)

**Problem:** with the default string `prefix` (no custom resolver), virt_lines crashes
with `Invalid 'chunk': expected Array, got String`. The consuming code
(`for ... part[1] ...` and `vim.list_extend(center, resolved_prefix)`) expects a list of
chunks, but the default resolver returned a flat `{ text, hl }` pair.

- [ ] **Step 1: Wrap the default resolver's pair in a list**

Change:

```lua
  local prefix_resolver = function(diagnostic)
    return { prefix, highlight_groups[diagnostic.severity] }
  end
```

to:

```lua
  local prefix_resolver = function(diagnostic)
    return { { prefix, highlight_groups[diagnostic.severity] } }
  end
```

Leave the `if type(prefix) == "function" then prefix_resolver = prefix end` line
untouched — user functions already return a list of chunks.

- [ ] **Step 2: Verify default prefix no longer crashes**

```bash
nvim --headless --cmd "set rtp+=$(pwd)" -c "lua
  local vl = require('lsp_lines.virt_lines')
  local ns = vim.api.nvim_create_namespace('t5b')
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {'local x = 1'})
  vl.render(ns, buf, { { lnum = 0, col = 6, end_lnum = 0, end_col = 7, severity = vim.diagnostic.severity.ERROR, message = 'boom', bufnr = buf } }, { virtual_lines = {} }, 'native')
  assert(#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 1)
  print('OK default-prefix marks=1')
" -c "qa!" 2>&1
```

Expected: `OK default-prefix marks=1`, no `Invalid 'chunk'` error.

- [ ] **Step 3: Commit**

```bash
git add lua/lsp_lines/virt_lines.lua
git commit -m "fix: default virt_lines prefix must resolve to a list of chunks"
```

---

## Task 6: Bug 1 — virt_text must not abort on a blank-message line

**Files:**
- Modify: `lua/lsp_lines/virt_text.lua` (the `for _, diags in pairs(line_diagnostics) do` loop)

**Problem:** when a line's diagnostics are all whitespace, `best` stays `nil` and the code does `return`, exiting the whole function and dropping virt_text for every later line.

- [ ] **Step 1: Replace the `return` with a per-line skip**

In `M.render`, find the block (moved from `render.lua:278-281`):

```lua
    if best == nil then
      -- For some reason best is nil. This should not happen unless there is an undefined diagnostic severity
      return
    end
```

Restructure the per-line loop to use a `goto continue` so only the current line is skipped. Change the loop header/footer so the body is skippable:

```lua
  for _, diags in pairs(line_diagnostics) do
    local index = 1
    local best = nil
    local virt_texts = { { string.rep(" ", spacing) } }
    for _, severity in ipairs(severities) do
      if diags[severity] ~= nil then
        for _, diagnostic in ipairs(diags[severity]) do
          local resolved_prefix = prefix_resolver(diagnostic, index, #diags)
          if best == nil then
            if diagnostic.message:gsub("%s+$", "") ~= "" then
              best = { prefix = resolved_prefix, diagnostic = diagnostic }
            end
          else
            if not only_count then
              table.insert(virt_texts, resolved_prefix)
            end
          end
          index = index + 1
        end
      end
    end

    if best == nil then
      -- Every diagnostic on this line had a blank message; skip just this line.
      goto continue
    end

    -- ... (rest of the per-line body unchanged: insert best.prefix, message,
    --      only_count counts, and the extmark) ...

    ::continue::
  end
```

> Implementation note: keep everything between the `if best == nil` skip and `::continue::` exactly as it was (the `table.insert(virt_texts, best.prefix)`, the message insert, the `only_count` block, and the `nvim_buf_set_extmark` call). Only the control flow changes from `return` to `goto continue`.

- [ ] **Step 2: Format check**

Run: `stylua --check lua/lsp_lines/virt_text.lua`
Expected: clean.

- [ ] **Step 3: Manual verification — later lines survive a blank line**

```bash
nvim --headless -c "lua
  require('lsp_lines').setup()
  local vt = require('lsp_lines.virt_text')
  local ns = vim.api.nvim_create_namespace('t6')
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {'aaa','bbb','ccc'})
  -- line 0 has only a blank-message diagnostic; line 2 has a real one
  vt.render(ns, buf, {
    { lnum = 0, col = 0, severity = vim.diagnostic.severity.WARN, message = '   ', bufnr = buf },
    { lnum = 2, col = 0, severity = vim.diagnostic.severity.ERROR, message = 'real error', bufnr = buf },
  }, {}, 'native')
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  local lines = {}
  for _, m in ipairs(marks) do lines[m[2]] = true end
  assert(lines[2], 'line 2 must still get virt_text after a blank line 0')
  print('OK line2 rendered')
" -c "qa" 2>&1
```

Expected: prints `OK line2 rendered` (before the fix this would fail / render nothing for line 2).

- [ ] **Step 4: Commit**

```bash
git add lua/lsp_lines/virt_text.lua
git commit -m "fix: virt_text no longer aborts all lines on a blank-message line"
```

---

## Task 7: Bug 2 — render `col=0, row=0` whole-file diagnostics cleanly

**Files:**
- Modify: `lua/lsp_lines/virt_lines.lua` (`M.render`)

**Problem:** diagnostics at `(lnum=0, col=0)` usually mean "the whole file"; the tree/alignment glyphs are meaningless and look broken there.

- [ ] **Step 1: Split whole-file diagnostics out before the stacking loop**

At the top of `M.render`, before the existing `for _, diagnostic in ipairs(diagnostics) do` stacking loop, partition out whole-file diagnostics and render them as plain top-of-file lines. Insert:

```lua
  local highlight_groups = HIGHLIGHTS[source or "native"]
  local prefix = opts.virtual_lines.prefix or "■"
  local prefix_resolver = function(diagnostic)
    return { prefix, highlight_groups[diagnostic.severity] }
  end
  if type(prefix) == "function" then
    prefix_resolver = prefix
  end

  -- Whole-file diagnostics (anchored at the very start of the buffer) have no
  -- meaningful column to align under, so render them as plain prefixed lines at
  -- the top instead of drawing nonsensical tree glyphs.
  local whole_file = {}
  local positioned = {}
  for _, diagnostic in ipairs(diagnostics) do
    if diagnostic.lnum == 0 and diagnostic.col == 0 then
      table.insert(whole_file, diagnostic)
    else
      table.insert(positioned, diagnostic)
    end
  end

  if #whole_file > 0 then
    local virt_lines = {}
    for _, diagnostic in ipairs(whole_file) do
      local hi = highlight_groups[diagnostic.severity]
      for msg_line in diagnostic.message:gmatch("([^\n]+)") do
        local vline = {}
        -- Consume resolved_prefix exactly like the main stacking loop does
        -- (via list_extend), so custom prefix resolvers behave identically here.
        vim.list_extend(vline, prefix_resolver(diagnostic))
        vim.list_extend(vline, { { " " .. msg_line, hi } })
        table.insert(virt_lines, vline)
      end
    end
    vim.api.nvim_buf_set_extmark(bufnr, namespace, 0, 0, { virt_lines = virt_lines, virt_lines_above = true })
  end

  diagnostics = positioned
```

> Implementation note: the `prefix` / `prefix_resolver` setup above duplicates what the existing body computes a few lines down. After inserting this block, **remove the now-duplicate** `prefix`/`prefix_resolver`/`highlight_groups` definitions from their original spot in the moved body (originally `render.lua:49-56`) so they are defined exactly once. The rest of the stacking loop now iterates the filtered `diagnostics` (positioned only).
>
> The default `prefix_resolver` returns `{ prefix, highlight_groups[severity] }`, and the existing positioned loop appends it with `vim.list_extend`, so `vline` chunks may be either `{ text, hl }` tables or bare strings depending on the resolver. Do not assume a fixed chunk shape — mirror the existing convention only.

- [ ] **Step 2: Format check**

Run: `stylua --check lua/lsp_lines/virt_lines.lua`
Expected: clean.

- [ ] **Step 3: Manual verification — whole-file diagnostic renders without tree glyphs**

```bash
nvim --headless -c "lua
  require('lsp_lines').setup()
  local vl = require('lsp_lines.virt_lines')
  local ns = vim.api.nvim_create_namespace('t7')
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {'first line','second'})
  vl.render(ns, buf, {
    { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = 'whole file is broken', bufnr = buf },
  }, { virtual_lines = {} }, 'native')
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  assert(#marks == 1, 'expected one whole-file extmark')
  local vlines = marks[1][4].virt_lines
  assert(vlines and #vlines >= 1, 'expected virt_lines content')
  -- confirm no tree connector glyph in the rendered text (chunks may be
  -- {text,hl} tables or bare strings depending on the prefix resolver).
  for _, line in ipairs(vlines) do
    for _, chunk in ipairs(line) do
      local text = type(chunk) == 'table' and chunk[1] or chunk
      if type(text) == 'string' then
        assert(not text:find('╰') and not text:find('─'), 'whole-file line must not use tree glyphs: ' .. text)
      end
    end
  end
  print('OK whole-file clean')
" -c "qa" 2>&1
```

Expected: prints `OK whole-file clean`.

- [ ] **Step 4: Manual verification — positioned diagnostics still render normally**

Re-run the Task 5 Step 4 smoke check; the line-1 (`lnum=1, col=6`) warning must still produce an extmark. Expected: `OK marks=...` unchanged.

- [ ] **Step 5: Commit**

```bash
git add lua/lsp_lines/virt_lines.lua
git commit -m "fix: render whole-file (0,0) diagnostics as plain top lines"
```

---

## Task 8: Bug 3 — stale diagnostics after LSP restart in current-line mode

**Files:**
- Modify: `lua/lsp_lines/init.lua` (`render_current_line` signature + the `CursorMoved` autocmd callback)

**Problem:** the `CursorMoved` callback closes over the `diagnostics` list captured when the handler last ran. After an LSP restart clears diagnostics, the stale list keeps re-rendering removed entries.

- [ ] **Step 1: Make `render_current_line` fetch live diagnostics**

Change `render_current_line` (`init.lua:5`) to accept the diagnostic `namespace` id and re-fetch live diagnostics instead of trusting a captured list. Replace the function signature and the diagnostics source:

```lua
local function render_current_line(diagnostics, ns, bufnr, opts)
```

becomes:

```lua
local function render_current_line(diagnostics, ns, bufnr, opts)
  -- `diagnostics` may be a stale closed-over list (e.g. after an LSP restart
  -- cleared them). When called from CursorMoved we pass the live set instead;
  -- see the autocmd callback below.
```

(No behavior change to the body — it already iterates the `diagnostics` argument. The fix is in *what* the autocmd passes.)

- [ ] **Step 2: Re-fetch in the `CursorMoved` callback**

In `M.setup`, the `CursorMoved` autocmd (`init.lua:72-78`) currently passes the captured `diagnostics`. Replace:

```lua
        vim.api.nvim_create_autocmd("CursorMoved", {
          buffer = bufnr,
          callback = function()
            render_current_line(diagnostics, ns.user_data.virt_lines_ns, bufnr, opts)
          end,
          group = "LspLines",
        })
```

with:

```lua
        vim.api.nvim_create_autocmd("CursorMoved", {
          buffer = bufnr,
          callback = function()
            -- Re-fetch live diagnostics so entries cleared by an LSP restart
            -- actually disappear instead of replaying a stale closed-over list.
            local live = vim.diagnostic.get(bufnr, { namespace = namespace })
            render_current_line(live, ns.user_data.virt_lines_ns, bufnr, opts)
          end,
          group = "LspLines",
        })
```

> Note: `namespace` is the handler's diagnostic namespace id, already in scope inside `show = function(namespace, bufnr, diagnostics, opts)`. The initial pre-`CursorMoved` render call on the next line keeps using the handler-provided `diagnostics`.

- [ ] **Step 3: Format check**

Run: `stylua --check lua/lsp_lines/init.lua`
Expected: clean.

- [ ] **Step 4: Manual verification — cleared diagnostics vanish on cursor move**

```bash
nvim --headless -c "lua
  require('lsp_lines').setup()
  local ns = vim.api.nvim_create_namespace('t8')
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {'aaa','bbb'})
  vim.api.nvim_set_current_buf(buf)
  vim.diagnostic.config({ virtual_lines = { only_current_line = true }, virtual_text = false })
  vim.diagnostic.set(ns, buf, {
    { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = 'will be cleared' },
  })
  vim.api.nvim_win_set_cursor(0, {1, 0})
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
  -- now clear diagnostics (simulating LSP restart) and move cursor
  vim.diagnostic.set(ns, buf, {})
  vim.api.nvim_win_set_cursor(0, {1, 0})
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = buf })
  local vns = vim.diagnostic.get_namespace(ns).user_data.virt_lines_ns
  local marks = vim.api.nvim_buf_get_extmarks(buf, vns, 0, -1, {})
  assert(#marks == 0, 'stale diagnostics should be gone, found ' .. #marks)
  print('OK no stale marks')
" -c "qa" 2>&1
```

Expected: prints `OK no stale marks`.

- [ ] **Step 5: Commit**

```bash
git add lua/lsp_lines/init.lua
git commit -m "fix: re-fetch live diagnostics on CursorMoved so cleared ones vanish"
```

---

## Task 9: Bug 4 — flatten multiline messages in virt_text

**Files:**
- Modify: `lua/lsp_lines/virt_text.lua` (`M.render`)

**Problem:** multiline diagnostic messages are inconsistently flattened; only the `best` message insert applies `:gsub("\r",""):gsub("\n"," ")`.

- [ ] **Step 1: Normalize messages once, up front**

At the start of `M.render`, before grouping diagnostics by line, add a single normalization helper and apply it when reading each message. Add near the top of the function (after `opts = opts or {}`):

```lua
  -- Collapse any embedded carriage returns / newlines (and runs of them) into a
  -- single space so multiline messages render as one flattened virt_text chunk.
  local function flatten(message)
    return (message:gsub("[\r\n]+", " "):gsub("%s+$", ""))
  end
```

- [ ] **Step 2: Use `flatten` for the displayed message**

Replace the `best` message insert (moved from `render.lua:283-286`):

```lua
    table.insert(virt_texts, {
      string.format(" %s ", best.diagnostic.message:gsub("\r", ""):gsub("\n", " ")),
      highlight_groups[best.diagnostic.severity],
    })
```

with:

```lua
    table.insert(virt_texts, {
      string.format(" %s ", flatten(best.diagnostic.message)),
      highlight_groups[best.diagnostic.severity],
    })
```

Also, the blank-message detection should consider a message blank after flattening. Replace the `best == nil` assignment guard (moved from `render.lua:265`):

```lua
            if diagnostic.message:gsub("%s+$", "") ~= "" then
```

with:

```lua
            if flatten(diagnostic.message) ~= "" then
```

- [ ] **Step 3: Format check**

Run: `stylua --check lua/lsp_lines/virt_text.lua`
Expected: clean.

- [ ] **Step 4: Manual verification — multiline message becomes one line**

```bash
nvim --headless -c "lua
  require('lsp_lines').setup()
  local vt = require('lsp_lines.virt_text')
  local ns = vim.api.nvim_create_namespace('t9')
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {'aaa'})
  vt.render(ns, buf, {
    { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = 'line one\nline two\r\nline three', bufnr = buf },
  }, {}, 'native')
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  local text = ''
  for _, chunk in ipairs(marks[1][4].virt_text) do text = text .. chunk[1] end
  assert(not text:find('\n') and not text:find('\r'), 'message must be flattened: ' .. vim.inspect(text))
  assert(text:find('line one') and text:find('line three'), 'all parts present')
  print('OK flattened')
" -c "qa" 2>&1
```

Expected: prints `OK flattened`.

- [ ] **Step 5: Commit**

```bash
git add lua/lsp_lines/virt_text.lua
git commit -m "fix: flatten multiline messages consistently in virt_text"
```

---

## Task 10: Bug 5 — correct the `only_count` severity counting

**Files:**
- Modify: `lua/lsp_lines/virt_text.lua` (the `if only_count then` block)

**Problem:** the count block (moved from `render.lua:287-305`) has empty `else` branches and a fragile per-severity special case.

- [ ] **Step 1: Replace the count block with uniform logic**

Replace the entire `if only_count then ... end` block:

```lua
    if only_count then
      for i = #severities, 1, -1 do
        local severity = severities[i]
        local ds = diags[severity]
        if ds then
          local count = #ds
          if count ~= nil then
            if severity ~= best.diagnostic.severity then
              table.insert(virt_texts, { string.format("[+%d] ", count), highlight_groups[severity] })
            elseif severity == best.diagnostic.severity then
              if count > 1 then
                table.insert(virt_texts, { string.format("[+%d] ", count - 1), highlight_groups[severity] })
              end
            else
            end
          end
        end
      end
    end
```

with:

```lua
    if only_count then
      for i = #severities, 1, -1 do
        local severity = severities[i]
        local ds = diags[severity]
        if ds then
          -- The diagnostic shown as `best` is already displayed, so its own
          -- severity contributes one fewer to the overflow count.
          local count = #ds
          if severity == best.diagnostic.severity then
            count = count - 1
          end
          if count > 0 then
            table.insert(virt_texts, { string.format("[+%d] ", count), highlight_groups[severity] })
          end
        end
      end
    end
```

- [ ] **Step 2: Format check**

Run: `stylua --check lua/lsp_lines/virt_text.lua`
Expected: clean.

- [ ] **Step 3: Manual verification — counts are correct and `[+0]` is suppressed**

```bash
nvim --headless -c "lua
  require('lsp_lines').setup()
  local vt = require('lsp_lines.virt_text')
  local ns = vim.api.nvim_create_namespace('t10')
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {'aaa'})
  -- 2 errors + 1 warning on the same line; best is an ERROR
  vt.render(ns, buf, {
    { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = 'err1', bufnr = buf },
    { lnum = 0, col = 1, severity = vim.diagnostic.severity.ERROR, message = 'err2', bufnr = buf },
    { lnum = 0, col = 2, severity = vim.diagnostic.severity.WARN, message = 'warn1', bufnr = buf },
  }, { only_count = true }, 'native')
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  local text = ''
  for _, chunk in ipairs(marks[1][4].virt_text) do text = text .. chunk[1] end
  assert(text:find('%[%+1%]'), 'expected [+1] for the extra error: ' .. text)
  assert(text:find('%[%+1%] ', 1, false), 'expected a warning count too')
  assert(not text:find('%[%+0%]'), 'must not show [+0]: ' .. text)
  print('OK counts: ' .. text)
" -c "qa" 2>&1
```

Expected: prints `OK counts: ...` containing `[+1]` (extra error) and `[+1]` (warning), no `[+0]`.

- [ ] **Step 4: Commit**

```bash
git add lua/lsp_lines/virt_text.lua
git commit -m "fix: correct and simplify only_count severity counting"
```

---

## Final verification

- [ ] **Step 1: Full format check**

Run: `stylua --check lua/`
Expected: no output (entire `lua/` clean).

- [ ] **Step 2: Full load smoke test**

Run: `nvim --headless -c "lua require('lsp_lines').setup()" -c "qa" 2>&1`
Expected: no output, exit 0.

- [ ] **Step 3: Confirm no dead code remains**

Run: `grep -rn "render_area\|FIX:\|severity_counts\|TODO: rename" lua/`
Expected: no matches (the old positional param name, stale FIX comments, commented count vars, and rename TODOs are all gone).
```
