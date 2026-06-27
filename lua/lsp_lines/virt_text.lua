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
  local highlight_groups = HIGHLIGHTS[source or "native"]
  opts = opts or {}
  -- Collapse any embedded carriage returns / newlines (and runs of them) into a
  -- single space so multiline messages render as one flattened virt_text chunk.
  local function flatten(message)
    return (message:gsub("[\r\n]+", " "):gsub("%s+$", ""))
  end
  local line_diagnostics = {}
  local line_count = vim.api.nvim_buf_line_count(bufnr)

  -- group diagnostics by line number and severity
  for _, d in ipairs(diagnostics) do
    if line_diagnostics[d.lnum] == nil then
      line_diagnostics[d.lnum] = {}
    end
    if line_diagnostics[d.lnum][d.severity] == nil then
      line_diagnostics[d.lnum][d.severity] = {}
    end
    local diags = line_diagnostics[d.lnum][d.severity]
    table.insert(diags, d)
  end

  local prefix = opts.prefix or "■"
  local spacing = opts.spacing or 4
  local only_count = opts.only_count or false
  local prefix_resolver = nil
  if type(prefix) == "function" then
    prefix_resolver = prefix
  elseif type(prefix) == "string" then
    prefix_resolver = function(diagnostic, _, _)
      return { prefix, highlight_groups[diagnostic.severity] }
    end
  else
    prefix_resolver = function()
      return prefix
    end
  end

  -- separate out best diagnostic and add just the prefix for remaining diagnostics for a line
  for _, diags in pairs(line_diagnostics) do
    local index = 1
    local best = nil
    local virt_texts = { { string.rep(" ", spacing) } }
    for _, severity in ipairs(severities) do
      if diags[severity] ~= nil then
        for _, diagnostic in ipairs(diags[severity]) do
          local resolved_prefix = prefix_resolver(diagnostic, index, #diags)
          if best == nil then
            if flatten(diagnostic.message) ~= "" then
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
    table.insert(virt_texts, best.prefix)
    table.insert(virt_texts, {
      string.format(" %s ", flatten(best.diagnostic.message)),
      highlight_groups[best.diagnostic.severity],
    })
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
    if best.diagnostic.lnum <= line_count then
      vim.api.nvim_buf_set_extmark(
        best.diagnostic.bufnr,
        namespace,
        best.diagnostic.lnum,
        0,
        { virt_text = virt_texts }
      )
    end
    ::continue::
  end
end

return M
