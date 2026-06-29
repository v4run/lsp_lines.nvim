-- Unit test for `virtual_lines.only_count`: when a line has multiple
-- diagnostics, the virtual-lines view shows only the highest-severity one and
-- appends per-severity overflow counts (e.g. "[+2 W] [+1 H]").
--
-- Calls the renderer directly (rather than going through the async
-- vim.diagnostic layer) so the assertions are deterministic.
--
-- Run with: nvim --headless --cmd "set rtp+=$(pwd)" -l tests/only_count_virt_lines.lua

local virt_lines = require("lsp_lines.virt_lines")

local failures = 0
local function check(label, ok, extra)
  if ok then
    print("ok   - " .. label)
  else
    failures = failures + 1
    print("FAIL - " .. label .. (extra and ("  (" .. tostring(extra) .. ")") or ""))
  end
end

local function render(only_count)
  local nsname = "occount" .. tostring(only_count)
  local ns = vim.api.nvim_create_namespace(nsname)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line zero", "line one here", "line two" })
  vim.api.nvim_set_current_buf(buf)
  local diagnostics = {
    {
      lnum = 1,
      col = 2,
      end_lnum = 1,
      end_col = 3,
      severity = vim.diagnostic.severity.HINT,
      message = "hintA",
      bufnr = buf,
    },
    {
      lnum = 1,
      col = 4,
      end_lnum = 1,
      end_col = 5,
      severity = vim.diagnostic.severity.ERROR,
      message = "boom",
      bufnr = buf,
    },
    {
      lnum = 1,
      col = 6,
      end_lnum = 1,
      end_col = 7,
      severity = vim.diagnostic.severity.WARN,
      message = "warnA",
      bufnr = buf,
    },
    {
      lnum = 1,
      col = 8,
      end_lnum = 1,
      end_col = 9,
      severity = vim.diagnostic.severity.WARN,
      message = "warnB",
      bufnr = buf,
    },
  }
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  virt_lines.render(ns, buf, diagnostics, { virtual_lines = { only_count = only_count } }, "native")

  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  local text, vline_count = "", 0
  for _, m in ipairs(marks) do
    if m[4].virt_lines then
      for _, vline in ipairs(m[4].virt_lines) do
        vline_count = vline_count + 1
        for _, chunk in ipairs(vline) do
          if type(chunk[1]) == "string" then
            text = text .. chunk[1]
          end
        end
      end
    end
  end
  return text, vline_count
end

-- only_count = true: one diagnostic shown (the ERROR) with per-severity counts.
local text, vlines = render(true)
check("only_count: shows the highest-severity message", text:find("boom") ~= nil, text)
check(
  "only_count: hides the other diagnostics' messages",
  text:find("warnA") == nil and text:find("hintA") == nil,
  text
)
check("only_count: shows 2 remaining warnings as [+2 W]", text:find("%[%+2 W%]") ~= nil, text)
check("only_count: shows 1 hint as [+1 H]", text:find("%[%+1 H%]") ~= nil, text)
check("only_count: suppresses the best severity's own [+0 E]", text:find("%[%+0") == nil, text)
check("only_count: collapses the line to a single virtual line", vlines == 1, "vlines=" .. vlines)

-- only_count = false (control): all four diagnostics still stack.
local _, vlines_full = render(false)
check("control: without only_count, all diagnostics still stack", vlines_full == 4, "vlines=" .. vlines_full)

-- A normal diagnostic on the first token (0,0)-(0,N) must NOT be mistaken for a
-- whole-file diagnostic; it should collapse with the rest of its line.
do
  local ns = vim.api.nvim_create_namespace("occol0")
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "part appnd pars" })
  vim.api.nvim_set_current_buf(buf)
  virt_lines.render(ns, buf, {
    {
      lnum = 0,
      col = 0,
      end_lnum = 0,
      end_col = 4,
      severity = vim.diagnostic.severity.ERROR,
      message = "undefined: part",
      bufnr = buf,
    },
    {
      lnum = 0,
      col = 5,
      end_lnum = 0,
      end_col = 10,
      severity = vim.diagnostic.severity.ERROR,
      message = "undefined: appnd",
      bufnr = buf,
    },
    {
      lnum = 0,
      col = 11,
      end_lnum = 0,
      end_col = 15,
      severity = vim.diagnostic.severity.ERROR,
      message = "undefined: pars",
      bufnr = buf,
    },
  }, { virtual_lines = { only_count = true } }, "native")
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  local n, text = 0, ""
  for _, m in ipairs(marks) do
    if m[4].virt_lines then
      for _, vline in ipairs(m[4].virt_lines) do
        n = n + 1
        for _, c in ipairs(vline) do
          if type(c[1]) == "string" then
            text = text .. c[1]
          end
        end
      end
    end
  end
  check("first-token (0,0) diagnostic collapses to one line", n == 1, "vlines=" .. n)
  check("first-token (0,0) line shows the [+2 E] count", text:find("%[%+2 E%]") ~= nil, text)
end

-- Cursor-aware selection: when the cursor sits within a diagnostic's column
-- range on the line, that diagnostic's message is the one shown.
do
  local ns = vim.api.nvim_create_namespace("occursor")
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "aaaaa bbbbb ccccc" })
  vim.api.nvim_set_current_buf(buf)
  local diags = {
    {
      lnum = 0,
      col = 0,
      end_lnum = 0,
      end_col = 5,
      severity = vim.diagnostic.severity.ERROR,
      message = "first",
      bufnr = buf,
    },
    {
      lnum = 0,
      col = 6,
      end_lnum = 0,
      end_col = 11,
      severity = vim.diagnostic.severity.ERROR,
      message = "second",
      bufnr = buf,
    },
    {
      lnum = 0,
      col = 12,
      end_lnum = 0,
      end_col = 17,
      severity = vim.diagnostic.severity.ERROR,
      message = "third",
      bufnr = buf,
    },
  }
  local function render_at(col)
    vim.api.nvim_win_set_cursor(0, { 1, col })
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    virt_lines.render(ns, buf, diags, { virtual_lines = { only_count = true } }, "native")
    local text = ""
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
      if m[4].virt_lines then
        for _, line in ipairs(m[4].virt_lines) do
          for _, c in ipairs(line) do
            if type(c[1]) == "string" then
              text = text .. c[1]
            end
          end
        end
      end
    end
    return text
  end

  local t = render_at(7) -- inside "bbbbb" (cols 6..11)
  check("cursor on 2nd diagnostic shows its message", t:find("second") ~= nil and t:find("first") == nil, t)
  check("cursor-matched line still counts the rest", t:find("%[%+2 E%]") ~= nil, t)

  t = render_at(13) -- inside "ccccc" (cols 12..17)
  check("cursor on 3rd diagnostic shows its message", t:find("third") ~= nil, t)

  t = render_at(5) -- the space between "aaaaa" and "bbbbb" -> no match -> fallback
  check(
    "cursor in a gap falls back to highest-severity (leftmost)",
    t:find("first") ~= nil and t:find("second") == nil,
    t
  )
end

-- A true whole-file diagnostic (0,0 with no extent) still renders at the top.
do
  local ns = vim.api.nvim_create_namespace("ocwf")
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "code here", "more code" })
  vim.api.nvim_set_current_buf(buf)
  virt_lines.render(ns, buf, {
    { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = "whole file broken", bufnr = buf },
  }, { virtual_lines = {} }, "native")
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  local has_above = false
  for _, m in ipairs(marks) do
    if m[4].virt_lines and m[4].virt_lines_above then
      has_above = true
    end
  end
  check("whole-file (0,0 no extent) still renders above", has_above)
end

print(string.format("\n%d failure(s)", failures))
os.exit(failures == 0 and 0 or 1)
