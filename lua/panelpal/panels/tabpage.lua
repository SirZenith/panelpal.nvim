local api = vim.api

local M = {}

---@class TabPage
---@field tabpage integer
--
---@field winnr_sidebar integer
---@field winnr_bottom_panel integer
---@field winnr_top_panel integer
---@field winnr_vsplit integer[]
--
---@field bufnr_sidebar integer
---@field bufnr_bottom_panel integer
---@field bufnr_top_panel integer
---@field bufnr_vsplit integer
--
---@field sidebar_width integer
---@field bottom_panel_height integer
---@field top_panel_height integer
local TabPage = {
    sidebar_width = 25,
    bottom_panel_height = 10,
    top_panel_height = 10,
}
M.TabPage = TabPage

---@param config? table
function TabPage:new(config)
    self.__index = self

    local obj = {}
    for k, v in ipairs(config or {}) do
        obj[k] = v
    end

    obj.win_vsplit = {}

    return setmetatable(obj, self)
end

-- -----------------------------------------------------------------------------
-- Tab

---@return integer? tabpagenr
function TabPage:get_tabpagenr()
    local tabpage = self.tabpagenr
    if tabpage and api.nvim_tabpage_is_valid(tabpage) then
        return tabpage
    else
        return nil
    end
end

---@return integer tabpagenr
function TabPage:show()
    local tabpage = self:get_tabpagenr()
    if not tabpage then
        vim.cmd "tabnew"
        tabpage = api.nvim_get_current_tabpage()
        self.tabpagenr = tabpage
        self.winnr_vsplit = api.nvim_tabpage_list_wins(tabpage)
    end

    api.nvim_set_current_tabpage(tabpage)

    return tabpage
end

function TabPage:hide()
    local tabpage = self:get_tabpagenr()
    if not tabpage then return end

    local cur_tabpage = api.nvim_get_current_tabpage()
    api.set_current_tabpage(tabpage)
    vim.cmd "tabclose"
    api.set_current_tabpage(cur_tabpage)

    self.tabpagenr = nil
end

-- -----------------------------------------------------------------------------
-- Split

---@param cnt integer
function TabPage:vsplit_into(cnt)
    if not self:get_tabpagenr() then return end

    local win_vsplit_old = self.winnr_vsplit
    local win_vsplit = {}
    for i = 1, #win_vsplit_old do
        local win = win_vsplit_old[i]
        if api.nvim_win_is_valid(win) then
            win_vsplit[#win_vsplit + 1] = win
        end
    end

    local split_cnt = #win_vsplit

    for i = split_cnt, cnt + 1, -1 do
        api.nvim_win_hide(win_vsplit[i])
        win_vsplit[i] = nil
    end

    local cur_win = api.nvim_get_current_win()
    for _ = split_cnt + 1, cnt do
        vim.cmd "botright vsplit"
        win_vsplit[#win_vsplit + 1] = api.nvim_get_current_win()
    end
    api.nvim_set_current_win(cur_win)

    self.winnr_vsplit = win_vsplit
end

---@param index integer
---@return integer? winnr
function TabPage:get_win_vsplit(index)
    if not index then return end

    local win = self.winnr_vsplit[index]
    if win and api.nvim_win_is_valid(win) then
        return win
    else
        return
    end
end

---@param index integer
---@param bufnr integer
function TabPage:set_vsplit_buf(index, bufnr)
    local win = self:get_win_vsplit(index)
    if not win then return end

    api.nvim_win_set_buf(win, bufnr)
end

-- -----------------------------------------------------------------------------
-- Common

-- return win number of sidebar win if there is a valid one, else return nil.
---@param key string # field name
---@return integer? winnr
function TabPage:_get_winnr_common(key)
    local win = self[key]
    if win and api.nvim_win_is_valid(win) then
        return win
    else
        self[key] = nil
        return nil
    end
end

---@param key string # field name
---@param key_size string # field name for split size
---@param sp_mod string # modifiyer of split command
---@param sp_cmd string # split command to create this window if not exists.
---@param key_bufnr string # field name for bufnr
---@param bufnr? integer
function TabPage:_toggle_common(key, key_size, sp_mod, sp_cmd, key_bufnr, bufnr)
    if not self:get_tabpagenr() then return end

    if self:_get_winnr_common(key) then
        self:_hide_common(key)
    else
        self:_show_common(key, key_size, sp_mod, sp_cmd, key_bufnr, bufnr)
    end
end

---@param key string # field name
---@param key_size string # field name for split size
---@param sp_mod string # modifiyer of split command
---@param sp_cmd string # split command to create this window if not exists.
---@param key_bufnr string # field name for bufnr
---@param bufnr? integer
---@return integer? winnr
function TabPage:_show_common(key, key_size, sp_mod, sp_cmd, key_bufnr, bufnr)
    if not self:get_tabpagenr() then return nil end

    local win = self:_get_winnr_common(key)
    if not win then
        local cur_win = api.nvim_get_current_win()

        vim.cmd(sp_mod .. " " .. self[key_size] .. sp_cmd)
        win = api.nvim_get_current_win()

        api.nvim_set_current_win(cur_win)
        self[key] = win
    end

    bufnr = bufnr or self[key_bufnr]
    if bufnr then
        self[key_bufnr] = bufnr
        api.nvim_win_set_buf(win, bufnr)
    end

    return win
end

---@param key string # field name
function TabPage:_hide_common(key)
    local win = self:_get_winnr_common(key)
    if not win then return end

    api.nvim_win_hide(win)
    self[key] = nil
end

-- -----------------------------------------------------------------------------
-- Sidebar

-- return win number of sidebar win if there is a valid one, else return nil.
---@return integer? winnr
function TabPage:get_winnr_sidebar()
    return self:_get_winnr_common("winnr_sidebar")
end

---@param bufnr? integer
function TabPage:toggle_sidebar(bufnr)
    self:_toggle_common(
        "winnr_sidebar", "sidebar_width", "topleft", "vsplit", "bufnr_sidebar", bufnr
    )
end

---@param bufnr? integer
---@return integer? winnr
function TabPage:show_sidebar(bufnr)
    return self:_show_common(
        "winnr_sidebar", "sidebar_width", "topleft", "vsplit", "bufnr_sidebar", bufnr
    )
end

function TabPage:hide_sidebar()
    self:_hide_common("winnr_sidebar")
end

-- -----------------------------------------------------------------------------
-- Bottom Panel

---@return integer? winnr
function TabPage:get_winnr_bottom_panel()
    return self:_get_winnr_common("winnr_bottom_panel")
end

---@param bufnr? integer
function TabPage:toggle_bottom_panel(bufnr)
    self:_toggle_common(
        "winnr_bottom_panel", "bottom_panel_height", "botright", "split", "bufnr_bottom_panel", bufnr
    )
end

---@param bufnr? integer
---@return integer? winnr
function TabPage:show_bottom_panel(bufnr)
    return self:_show_common(
        "winnr_bottom_panel", "bottom_panel_height", "botright", "split", "bufnr_bottom_panel", bufnr
    )
end

function TabPage:hide_bottom_panel()
    self:_hide_common("winnr_bottom_panel")
end

-- -----------------------------------------------------------------------------
-- Top Panel

---@return integer? winnr
function TabPage:get_winnr_top_panel()
    self:_get_winnr_common("winnr_top_panel")
end

---@param bufnr? integer
function TabPage:toggle_top_panel(bufnr)
    self:_toggle_common(
        "winnr_top_panel", "top_panel_height", "topleft", "split", "bufnr_top_panel", bufnr
    )
end

---@param bufnr? integer
---@return integer? winnr
function TabPage:show_top_panel(bufnr)
    return self:_show_common(
        "winnr_top_panel", "top_panel_height", "topleft", "split", "bufnr_top_panel", bufnr
    )
end

function TabPage:hide_top_panel()
    self:_hide_common("winnr_top_panel")
end

-- -----------------------------------------------------------------------------

return M
