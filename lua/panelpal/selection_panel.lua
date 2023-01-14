local panelpal = require "panelpal"

local M = {}

M.selected_symbol   = "  [■] "
M.unselected_symbol = "   □  "

local Highlight = {
    select = "PanelpalSelect",
    unselect = "PanelpalUnselect",
}

---@class SelectionPanel
---@field name string
---@field buf integer
---@field win integer
---@field height integer
---@field options string[]
---@field multi_selection boolean
---@field selected {[integer]: boolean}
---@field _on_select_callback? fun(self: SelectionPanel, index: integer)
---@field _on_unselect_callback? fun(self: SelectionPanel, index: integer)
---@field _selection_checker? fun(self: SelectionPanel, index: integer): boolean
local SelectionPanel = {}
M.SelectionPanel = SelectionPanel

---@return SelectionPanel
function SelectionPanel:new(args)
    self.__index = self

    local name = args.name or "select-panel"
    local buf = panelpal.find_or_create_buf_with_name(name)
    vim.bo[buf].buftype = "nofile"

    local obj = {
        name = name,
        buf = buf,
        win = nil,
        height = args.height or 15,
        options = args.options or {},
        multi_selection = args.multi_selection or false,
        selected = {},
        _on_select_callback = args.on_select_callback or nil,
        _on_unselect_callback = args.on_unselect_callback or nil,
        _selection_checker = args.selection_checker or nil,
    }

    setmetatable(obj, self)
    obj:setup_keymapping()

    return obj
end

function SelectionPanel:setup_keymapping()
    local buf = self.buf
    if not buf then return end

    local opts = { noremap = true, silent = true, buffer = self.buf }

    local function nmap(lhs, rhs)
        vim.keymap.set("n", lhs, rhs, opts)
    end

    nmap("<cr>", function()
        local pos = vim.api.nvim_win_get_cursor(0)
        local index = pos[1]
        self:toggle_selection(index)
    end)
end

-- -----------------------------------------------------------------------------

---@param callback? fun(self: SelectionPanel, index: integer)
function SelectionPanel:set_on_select(callback)
    self._on_select_callback = callback
end

---@param callback? fun(self: SelectionPanel, index: integer)
function SelectionPanel:set_on_unselect(callback)
    self._on_unselect_callback = callback
end

---@param callback? fun(self: SelectionPanel, index: integer): boolean
function SelectionPanel:set_selection_checker(callback)
   self._selection_checker = callback
end

---@param index integer
function SelectionPanel:on_select(index)
    self:update_option(index)

    local callback = self._on_select_callback
    if callback then callback(self, index) end
end

---@param index integer
function SelectionPanel:on_unselect(index)
    self:update_option(index)

    local callback = self._on_unselect_callback
    if callback then callback(self, index) end
end

function SelectionPanel:clear_selectioin()
    local selected = self.selected
    for i in pairs(selected) do
        selected[i] = false
        self:on_unselect(i)
        self:update_option(i)
    end
end

---@param index integer
function SelectionPanel:toggle_selection(index)
    local is_selected = not self.selected[index]
    local target = is_selected and self.select or self.unselect
    target(self, index)
end

---@param index integer
function SelectionPanel:select(index)
    local is_selected = self.selected[index]
    if is_selected then return end

    local checker = self._selection_checker
    if checker and not checker(self, index) then return end

    if not self.multi_selection then
        self:clear_selectioin()
    end

    self.selected[index] = true
    self:on_select(index)
end

---@param index integer
function SelectionPanel:unselect(index)
    local is_selected = self.selected[index]
    if not is_selected then return end

    self.selected[index] = nil
    self:on_unselect(index)
end

-- -----------------------------------------------------------------------------

function SelectionPanel:show()
    local buf, win = self.buf, self.win
    if not buf then
        return
    elseif not win or not vim.api.nvim_win_is_valid(win) then
        vim.cmd "belowright split"
        win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(win, self.buf)

        self.win = win
    end

    vim.api.nvim_win_set_height(win, self.height)
    self:update_options()
end

function SelectionPanel:hide()
    local win = self.win
    if not win or vim.api.nvim_win_is_valid() == 0 then
        return
    end

    vim.api.nvim_win_hide(win)
end

function SelectionPanel:update_options()
    for i = 1, #self.options do
        self:update_option(i)
    end
end

---@param index integer
function SelectionPanel:update_option(index)
    local option = self.options[index]
    if not option then return end

    local is_selected = self.selected[index]
    local symbol = is_selected and M.selected_symbol or M.unselected_symbol
    local buf = self.buf

    local line_index = index - 1
    local lines = { symbol .. option }
    vim.api.nvim_buf_set_lines(buf, line_index, line_index + 1, false, lines)

    local hl_name = is_selected and Highlight.select or Highlight.unselect
    vim.api.nvim_buf_add_highlight(buf, 0, hl_name, line_index, 0, #symbol)
end

-- -----------------------------------------------------------------------------

return M
