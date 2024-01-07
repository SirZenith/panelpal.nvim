local api = vim.api
local panelpal = require "panelpal"

local M = {}

M.selected_symbol     = "  [■] "
M.unselected_symbol   = "   □  "
M.unselectable_symbol = "      "

local Highlight = {
    select = "PanelpalSelect",
    unselect = "PanelpalUnselect",
    unselectable = "PanelpalUnselectable",
}

---@class SelectionPanel
---@field name string
---@field buf integer
---@field win integer
---@field height integer
--
---@field multi_selection boolean
---@field options string[]
---@field selected {[integer]: boolean}
--
---@field _on_select_callback? fun(self: SelectionPanel, index: integer)
---@field _on_unselect_callback? fun(self: SelectionPanel, index: integer)
---@field _selection_checker? fun(self: SelectionPanel, index: integer): boolean
local SelectionPanel = {
    name = "select-panel",
    height = 15,
    multi_selection = false,
}
M.SelectionPanel = SelectionPanel

---@param config? table
---@return SelectionPanel
function SelectionPanel:new(config)
    self.__index = self

    config = config or {}
    local obj = {}
    for k, v in pairs(config) do
        obj[k] = v
    end

    local name = obj.name or self.name
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(buf, name)
    vim.bo[buf].buftype = "nofile"

    obj.buf = buf
    obj.options = {}
    obj.selected = {}

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
        local pos = api.nvim_win_get_cursor(0)
        local index = pos[1]
        self:toggle_selection(index)
    end)
end

---@return integer? bufnr
function SelectionPanel:get_buffer()
    local buf = self.buf
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(self.name)
        self.buf = buf
    end

    return buf ~= 0 and buf or nil
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
        selected[i] = nil
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
    elseif not win or not api.nvim_win_is_valid(win) then
        vim.cmd "belowright split"
        win = api.nvim_get_current_win()
        api.nvim_win_set_buf(win, self.buf)

        self.win = win
    end

    api.nvim_win_set_height(win, self.height)
    self:update_options()
end

function SelectionPanel:hide()
    local win = self.win
    if not win or api.nvim_win_is_valid(win) == 0 then
        return
    end

    api.nvim_win_hide(win)
end

function SelectionPanel:update_options()
    local buf = self:get_buffer()
    if not buf then return end

    panelpal.clear_buffer_contnet(buf)

    for i = 1, #self.options do
        self:update_option(i)
    end
end

---@param index integer
function SelectionPanel:update_option(index)
    local option = self.options[index]
    if not option then return end

    local is_selected = self.selected[index]
    local is_selectable = true
    local checker = self._selection_checker
    if checker then
        is_selectable = checker(self, index)
    end

    local symbol, hl_name
    if not is_selectable then
        symbol = M.unselectable_symbol
        hl_name = Highlight.unselectable
    elseif is_selected then
        symbol = M.selected_symbol
        hl_name = Highlight.select
    else
        symbol = M.unselected_symbol
        hl_name = Highlight.unselect
    end

    local buf = self.buf
    local line_index = index - 1
    local lines = is_selectable and {
        symbol .. option
    } or {
        option ~= "" and (symbol .. option) or ""
    }

    api.nvim_buf_set_lines(buf, line_index, line_index + 1, false, lines)
    api.nvim_buf_add_highlight(buf, 0, hl_name, line_index, 0, #symbol)
end

-- -----------------------------------------------------------------------------

return M
