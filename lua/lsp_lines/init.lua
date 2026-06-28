local M = {}

local render = require("lsp_lines.render")

-- Tracks which diagnostic namespaces have current-line rendering active, per
-- buffer, so a single shared CursorMoved autocmd can re-render every namespace.
-- Without this, each namespace's handler would clobber the others' cursor
-- tracking (only the last source to publish would follow the cursor).
-- active[bufnr] = { [namespace] = { vns = <virt_lines_ns>, opts = <opts> } }
local active = {}

local function render_current_line(diagnostics, ns, bufnr, opts)
  local current_line_diag = {}
  local not_current_line_diag = {}
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1

  for _, diagnostic in pairs(diagnostics) do
    -- A diagnostic is "on the current line" if the cursor falls within its
    -- (possibly multi-line) range. The two buckets must be mutually exclusive,
    -- otherwise a multi-line diagnostic spanning the cursor would render both as
    -- a virtual line AND as a virtual-text fallback copy.
    local on_current = diagnostic.end_lnum and (lnum >= diagnostic.lnum and lnum <= diagnostic.end_lnum)
      or (lnum == diagnostic.lnum)
    if on_current then
      table.insert(current_line_diag, diagnostic)
    else
      table.insert(not_current_line_diag, diagnostic)
    end
  end

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
end

-- Re-render every namespace that has current-line rendering active for a buffer.
local function render_active_buffer(bufnr)
  local buf_active = active[bufnr]
  if not buf_active then
    return
  end
  for namespace, entry in pairs(buf_active) do
    -- Re-fetch live diagnostics so entries cleared by an LSP restart actually
    -- disappear instead of replaying a stale closed-over list.
    local live = vim.diagnostic.get(bufnr, { namespace = namespace })
    render_current_line(live, entry.vns, bufnr, entry.opts)
  end
end

-- Ensure exactly one CursorMoved autocmd exists for this buffer. We clear only
-- THIS buffer's autocmds (not the whole group) so other buffers keep tracking
-- their own cursor.
local function ensure_cursor_autocmd(bufnr)
  vim.api.nvim_clear_autocmds({ group = "LspLines", buffer = bufnr })
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = bufnr,
    callback = function()
      render_active_buffer(bufnr)
    end,
    group = "LspLines",
  })
end

-- Stop tracking a namespace for a buffer; drop the buffer's autocmd once no
-- namespaces remain active there.
local function deactivate(namespace, bufnr)
  local buf_active = active[bufnr]
  if not buf_active then
    return
  end
  buf_active[namespace] = nil
  if next(buf_active) == nil then
    active[bufnr] = nil
    vim.api.nvim_clear_autocmds({ group = "LspLines", buffer = bufnr })
  end
end

---@class Opts
---@field virtual_lines OptsVirtualLines Options for lsp_lines plugin

---@class OptsVirtualLines
---@field only_current_line boolean|table Options for rendering only on current line
---@field highlight_whole_line boolean Highlight empty space to the left of a diagnostic

-- Registers a wrapper-handler to render lsp lines.
-- This should usually only be called once, during initialisation.
M.setup = function()
  vim.api.nvim_create_augroup("LspLines", { clear = true })
  vim.diagnostic.handlers.virtual_lines = {
    ---@param namespace number
    ---@param bufnr number
    ---@param diagnostics table
    ---@param opts boolean|Opts
    show = function(namespace, bufnr, diagnostics, opts)
      local ns = vim.diagnostic.get_namespace(namespace)
      if not ns.user_data.virt_lines_ns then
        -- One extmark namespace PER diagnostic source. A shared name would
        -- resolve to a single id, so sources would clear each other's marks.
        ns.user_data.virt_lines_ns = vim.api.nvim_create_namespace("lsp_lines." .. namespace)
      end
      local vns = ns.user_data.virt_lines_ns

      if opts.virtual_lines.only_current_line == nil then
        opts.virtual_lines.only_current_line = {
          enable = false,
        }
      elseif type(opts.virtual_lines.only_current_line) == "boolean" then
        opts.virtual_lines.only_current_line = {
          enable = opts.virtual_lines.only_current_line,
        }
      else
        opts.virtual_lines.only_current_line.enable = true
      end

      if opts.virtual_lines.only_current_line.enable then
        active[bufnr] = active[bufnr] or {}
        active[bufnr][namespace] = { vns = vns, opts = opts }
        ensure_cursor_autocmd(bufnr)
        -- Render immediately, before the first CursorMoved event.
        render_current_line(diagnostics, vns, bufnr, opts)
      else
        deactivate(namespace, bufnr)
        render.show(vns, bufnr, diagnostics, opts)
      end
    end,
    ---@param namespace number
    ---@param bufnr number
    hide = function(namespace, bufnr)
      local ns = vim.diagnostic.get_namespace(namespace)
      if ns.user_data.virt_lines_ns then
        render.hide(ns.user_data.virt_lines_ns, bufnr)
        deactivate(namespace, bufnr)
      end
    end,
  }
end

---@return boolean
M.toggle = function()
  local new_value = not vim.diagnostic.config().virtual_lines
  vim.diagnostic.config({ virtual_lines = new_value })
  return new_value
end

return M
