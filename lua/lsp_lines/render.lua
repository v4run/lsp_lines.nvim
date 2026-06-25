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
