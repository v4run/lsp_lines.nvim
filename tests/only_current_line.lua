-- Regression tests for the `only_current_line` option.
-- Run with: nvim --headless --cmd "set rtp+=$(pwd)" -l tests/only_current_line.lua
--
-- Covers:
--   Bug A: a multi-line diagnostic that spans the cursor must not render BOTH a
--          virtual line and a virtual-text fallback copy.
--   Bug B: with multiple diagnostic sources (namespaces) on one buffer, every
--          source must keep tracking the cursor (not just the last one to publish).
--   Basic: single-source current-line rendering still puts a mark only on the
--          cursor's line.

local failures = 0
local function check(label, ok)
  if ok then
    print("ok   - " .. label)
  else
    failures = failures + 1
    print("FAIL - " .. label)
  end
end

local function fresh_buf(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  return buf
end

local function vns_of(ns)
  return vim.diagnostic.get_namespace(ns).user_data.virt_lines_ns
end

local function mark_lines(vns, buf)
  local marks = vim.api.nvim_buf_get_extmarks(buf, vns, 0, -1, {})
  local out = {}
  for _, m in ipairs(marks) do
    table.insert(out, m[2])
  end
  table.sort(out)
  return out
end

local function move(buf, row1)
  vim.api.nvim_win_set_cursor(0, { row1, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
end

require("lsp_lines").setup()

-- ---------------------------------------------------------------------------
-- Basic: single source, single-line diagnostics.
-- ---------------------------------------------------------------------------
do
  local ns = vim.api.nvim_create_namespace("basic")
  local buf = fresh_buf({ "l0", "l1", "l2", "l3", "l4" })
  vim.diagnostic.config({ virtual_lines = { only_current_line = true }, virtual_text = false })
  vim.diagnostic.set(ns, buf, {
    { lnum = 0, col = 0, severity = 1, message = "e0" },
    { lnum = 2, col = 0, severity = 1, message = "e2" },
  })
  local vns = vns_of(ns)
  move(buf, 3) -- lnum 2
  check("basic: cursor on diagnostic line shows exactly that line", vim.deep_equal(mark_lines(vns, buf), { 2 }))
  move(buf, 2) -- lnum 1, no diagnostic
  check("basic: cursor on empty line shows nothing", vim.deep_equal(mark_lines(vns, buf), {}))
end

-- ---------------------------------------------------------------------------
-- Bug A: multi-line diagnostic spanning the cursor + virtual_text fallback.
-- ---------------------------------------------------------------------------
do
  local ns = vim.api.nvim_create_namespace("bugA")
  local buf = fresh_buf({ "l0", "l1", "l2", "l3", "l4" })
  vim.diagnostic.config({
    virtual_lines = { only_current_line = { virtual_text = { prefix = "●" } } },
    virtual_text = false,
  })
  vim.diagnostic.set(ns, buf, {
    { lnum = 1, col = 0, end_lnum = 3, end_col = 0, severity = 1, message = "spanning 1-3" },
  })
  local vns = vns_of(ns)
  move(buf, 3) -- lnum 2, inside the span
  local marks = vim.api.nvim_buf_get_extmarks(buf, vns, 0, -1, { details = true })
  local n_virt_lines, n_virt_text = 0, 0
  for _, m in ipairs(marks) do
    if m[4].virt_lines then
      n_virt_lines = n_virt_lines + 1
    end
    if m[4].virt_text then
      n_virt_text = n_virt_text + 1
    end
  end
  check("bugA: spanning diagnostic renders as a virtual line", n_virt_lines == 1)
  check("bugA: spanning diagnostic is NOT also duplicated as virtual text", n_virt_text == 0)
end

-- ---------------------------------------------------------------------------
-- Bug B: two sources on one buffer both keep tracking the cursor.
-- ---------------------------------------------------------------------------
do
  local buf = fresh_buf({ "l0", "l1", "l2", "l3", "l4" })
  vim.diagnostic.config({ virtual_lines = { only_current_line = true }, virtual_text = false })
  local nsA = vim.api.nvim_create_namespace("srcA")
  local nsB = vim.api.nvim_create_namespace("srcB")
  vim.diagnostic.set(nsA, buf, { { lnum = 0, col = 0, severity = 1, message = "A@0" } })
  vim.diagnostic.set(nsB, buf, { { lnum = 4, col = 0, severity = 1, message = "B@4" } })
  local vnsA, vnsB = vns_of(nsA), vns_of(nsB)

  move(buf, 1) -- lnum 0 -> A's line
  check("bugB: source A renders on its line after cursor move", vim.deep_equal(mark_lines(vnsA, buf), { 0 }))
  check("bugB: source B clears when cursor leaves its line", vim.deep_equal(mark_lines(vnsB, buf), {}))

  move(buf, 5) -- lnum 4 -> B's line
  check("bugB: source B renders on its line after cursor move", vim.deep_equal(mark_lines(vnsB, buf), { 4 }))
  check("bugB: source A clears when cursor leaves its line", vim.deep_equal(mark_lines(vnsA, buf), {}))
end

print(string.format("\n%d failure(s)", failures))
os.exit(failures == 0 and 0 or 1)
