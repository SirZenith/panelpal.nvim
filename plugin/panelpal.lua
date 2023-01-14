if vim.g.loaded_panelpal then
    return
end

vim.g.loaded_panelpal = true

require "panelpal".setup()
