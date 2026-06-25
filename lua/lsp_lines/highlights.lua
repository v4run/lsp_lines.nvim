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
