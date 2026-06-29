local highlights = require("lsp_lines.highlights")
local HIGHLIGHTS = highlights.HIGHLIGHTS
local SEVERITIES = highlights.severities

local M = {}

-- These don't get copied, do they? We only pass around and compare pointers, right?
local SPACE = "space"
local DIAGNOSTIC = "diagnostic"
local OVERLAP = "overlap"
local BLANK = "blank"

-- Single-letter labels used by the `only_count` overflow counts (e.g. "[+2 W]").
local SEVERITY_LABELS = {
  [vim.diagnostic.severity.ERROR] = "E",
  [vim.diagnostic.severity.WARN] = "W",
  [vim.diagnostic.severity.INFO] = "I",
  [vim.diagnostic.severity.HINT] = "H",
}

-- Returns the exclusive upper column bound that a diagnostic covers on its
-- starting line (math.huge when it spans onto later lines).
local function upper_col(d)
  if d.end_lnum and d.end_lnum > d.lnum then
    return math.huge
  end
  return d.end_col or (d.col + 1)
end

-- When `only_count` is enabled, collapse each line's diagnostics to a single one
-- and return per-severity overflow count chunks keyed by the kept diagnostic.
-- The kept diagnostic is the highest severity (ties: earliest column), except on
-- the line the cursor is on: if the cursor sits within a diagnostic's column
-- range, that diagnostic is shown instead. Returns reduced list and count map.
local function collapse_to_counts(diagnostics, highlight_groups, cursor)
  local by_line = {}
  for _, d in ipairs(diagnostics) do
    by_line[d.lnum] = by_line[d.lnum] or {}
    table.insert(by_line[d.lnum], d)
  end

  local reduced = {}
  local counts_by_diag = {}
  for lnum, line_diags in pairs(by_line) do
    -- Highest severity wins (lower severity number == more severe); ties broken
    -- by the earliest column so the kept diagnostic aligns under the same spot.
    local best = line_diags[1]
    local per_severity = {}
    for _, d in ipairs(line_diags) do
      per_severity[d.severity] = (per_severity[d.severity] or 0) + 1
      if d.severity < best.severity or (d.severity == best.severity and d.col < best.col) then
        best = d
      end
    end

    -- On the cursor's line, prefer the diagnostic under the cursor column
    -- (highest severity among matches, then the narrowest/most specific range).
    if cursor and cursor.lnum == lnum then
      local match, match_span
      for _, d in ipairs(line_diags) do
        local upper = upper_col(d)
        if cursor.col >= d.col and cursor.col < upper then
          local span = upper - d.col
          if match == nil or d.severity < match.severity or (d.severity == match.severity and span < match_span) then
            match, match_span = d, span
          end
        end
      end
      if match then
        best = match
      end
    end

    local chunks = {}
    for _, severity in ipairs(SEVERITIES) do
      local count = per_severity[severity]
      if count then
        -- The kept diagnostic is already shown, so its severity has one fewer.
        if severity == best.severity then
          count = count - 1
        end
        if count > 0 then
          table.insert(
            chunks,
            { string.format(" [+%d %s]", count, SEVERITY_LABELS[severity]), highlight_groups[severity] }
          )
        end
      end
    end

    counts_by_diag[best] = chunks
    table.insert(reduced, best)
  end

  return reduced, counts_by_diag
end

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
  -- This loop reads line by line, and puts them into stacks with some
  -- extra data, since rendering each line will require understanding what
  -- is beneath it.
  local line_stacks = {}
  local prev_lnum = -1
  local prev_col = 0
  local highlight_groups = HIGHLIGHTS[source or "native"]
  local prefix = opts.virtual_lines.prefix or "■"
  local prefix_resolver = function(diagnostic)
    return { { prefix, highlight_groups[diagnostic.severity] } }
  end
  if type(prefix) == "function" then
    prefix_resolver = prefix
  end

  -- Whole-file diagnostics (anchored at the very start of the buffer with no
  -- extent) have no meaningful column to align under, so render them as plain
  -- prefixed lines at the top instead of drawing nonsensical tree glyphs.
  -- A diagnostic on the first *token* of the file ((0,0) with end_col > 0) has a
  -- real column to point at and must render normally.
  local function is_whole_file(d)
    return d.lnum == 0
      and d.col == 0
      and (d.end_lnum == nil or d.end_lnum == 0)
      and (d.end_col == nil or d.end_col == 0)
  end

  local whole_file = {}
  local positioned = {}
  for _, diagnostic in ipairs(diagnostics) do
    if is_whole_file(diagnostic) then
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

  -- When enabled, keep only the highest-severity diagnostic per line and append
  -- per-severity overflow counts to its message (counts_by_diag is empty/no-op
  -- otherwise).
  local counts_by_diag = {}
  if opts.virtual_lines and opts.virtual_lines.only_count then
    -- If this buffer is the one in the current window, let the cursor's column
    -- pick which diagnostic the collapsed line shows (updates live in
    -- only_current_line mode, which re-renders on CursorMoved).
    local cursor
    local win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      local pos = vim.api.nvim_win_get_cursor(win)
      cursor = { lnum = pos[1] - 1, col = pos[2] }
    end
    diagnostics, counts_by_diag = collapse_to_counts(diagnostics, highlight_groups, cursor)
  end

  for _, diagnostic in ipairs(diagnostics) do
    if line_stacks[diagnostic.lnum] == nil then
      line_stacks[diagnostic.lnum] = {}
    end

    local stack = line_stacks[diagnostic.lnum]

    if diagnostic.lnum ~= prev_lnum then
      table.insert(stack, { SPACE, string.rep(" ", distance_between_cols(bufnr, diagnostic.lnum, 0, diagnostic.col)) })
    elseif diagnostic.col ~= prev_col then
      -- Clarification on the magic numbers below:
      -- +1: indexing starting at 0 in one API but at 1 on the other.
      -- -1: for non-first lines, the previous col is already drawn.
      table.insert(
        stack,
        { SPACE, string.rep(" ", distance_between_cols(bufnr, diagnostic.lnum, prev_col + 1, diagnostic.col) - 1) }
      )
    else
      table.insert(stack, { OVERLAP, diagnostic.severity })
    end

    if diagnostic.message:find("^%s*$") then
      table.insert(stack, { BLANK, diagnostic })
    else
      table.insert(stack, { DIAGNOSTIC, diagnostic })
    end

    prev_lnum = diagnostic.lnum
    prev_col = diagnostic.col
  end

  for lnum, lelements in pairs(line_stacks) do
    local virt_lines = {}

    -- We read in the order opposite to insertion because the last
    -- diagnostic for a real line, is rendered upstairs from the
    -- second-to-last, and so forth from the rest.
    for i = #lelements, 1, -1 do -- last element goes on top
      if lelements[i][1] == DIAGNOSTIC then
        local diagnostic = lelements[i][2]
        local empty_space_hi
        if opts.virtual_lines and opts.virtual_lines.highlight_whole_line == false then
          empty_space_hi = ""
        else
          empty_space_hi = highlight_groups[diagnostic.severity]
        end

        local left = {}
        local overlap = false
        local multi = 0

        -- Iterate the stack for this line to find elements on the left.
        for j = 1, i - 1 do
          local type = lelements[j][1]
          local data = lelements[j][2]
          if type == SPACE then
            if multi == 0 then
              table.insert(left, { data, empty_space_hi })
            else
              table.insert(left, { string.rep("─", data:len()), highlight_groups[diagnostic.severity] })
            end
          elseif type == DIAGNOSTIC then
            -- If an overlap follows this, don't add an extra column.
            if lelements[j + 1][1] ~= OVERLAP then
              table.insert(left, { "│", highlight_groups[data.severity] })
            end
            overlap = false
          elseif type == BLANK then
            if multi == 0 then
              table.insert(left, { "╰", highlight_groups[data.severity] })
            else
              table.insert(left, { "┴", highlight_groups[data.severity] })
            end
            multi = multi + 1
          elseif type == OVERLAP then
            overlap = true
          end
        end

        local center_symbol
        if overlap and multi > 0 then
          center_symbol = "┼"
        elseif overlap then
          center_symbol = "├"
        elseif multi > 0 then
          center_symbol = "┴"
        else
          center_symbol = "╰"
        end
        local center = {
          { string.format("%s%s", center_symbol, "───"), highlight_groups[diagnostic.severity] },
        }
        local resolved_prefix = prefix_resolver(diagnostic)
        local prefix_len = 0
        for _, part in pairs(resolved_prefix) do
          prefix_len = prefix_len + vim.fn.strdisplaywidth(part[1])
        end
        vim.list_extend(center, resolved_prefix)

        -- TODO: We can draw on the left side if and only if:
        -- a. Is the last one stacked this line.
        -- b. Has enough space on the left.
        -- c. Is just one line.
        -- d. Is not an overlap.

        local msg = diagnostic.message
        local count_chunks = counts_by_diag[diagnostic]
        local msg_lines = {}
        for msg_line in msg:gmatch("([^\n]+)") do
          table.insert(msg_lines, msg_line)
        end
        for idx, msg_line in ipairs(msg_lines) do
          local vline = {}
          vim.list_extend(vline, left)
          vim.list_extend(vline, center)
          vim.list_extend(vline, { { msg_line, highlight_groups[diagnostic.severity] } })
          -- Overflow counts go after the message on its final line.
          if count_chunks and idx == #msg_lines then
            vim.list_extend(vline, count_chunks)
          end
          vim.list_extend(
            vline,
            { { string.rep(" ", vim.api.nvim_win_get_width(0)), highlight_groups[diagnostic.severity] } }
          )

          table.insert(virt_lines, vline)

          -- Special-case for continuation lines:
          if overlap then
            center = {
              { "│", highlight_groups[diagnostic.severity] },
              { "     " .. string.rep(" ", prefix_len), empty_space_hi },
            }
          else
            center = { { "      " .. string.rep(" ", prefix_len), empty_space_hi } }
          end
        end
      end
    end

    vim.api.nvim_buf_set_extmark(bufnr, namespace, lnum, 0, { virt_lines = virt_lines })
  end
end

return M
