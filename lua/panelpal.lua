local api = vim.api

local M = {}

---@enum PanelPosition
local PanelPosition = {
    top = "top",
    right = "right",
    bottom = "bottom",
    left = "left",
}
M.PanelPosition = PanelPosition

---@enum ScrollMethod
local ScrollMethod = {
    top = "top",
    bottom = "bottom",
    compare = "compare"
}
M.ScrollMethod = ScrollMethod

---@enum PanelContentUpdateMethod
local PanelContentUpdateMethod = {
    append = "append",
    override = "override",
    prepend = "prepend",
}
M.PanelContentUpdateMethod = PanelContentUpdateMethod

-- -----------------------------------------------------------------------------

---@param method PanelContentUpdateMethod
---@param buf? integer
---@return integer line_st
---@return integer line_ed
function M.update_method_to_line_range(method, buf)
    local line_st, line_ed = -1, -1
    if method == PanelContentUpdateMethod.append then
        line_st, line_st = -1, -1
        if buf
            and api.nvim_buf_line_count(buf) == 1
            and api.nvim_buf_get_lines(buf, 0, 1, true)[1] == ""
        then
            line_st = 0
        end
    elseif method == PanelContentUpdateMethod.override then
        line_st, line_ed = 0, -1
    elseif method == PanelContentUpdateMethod.prepend then
        line_st, line_st = 0, 0
    end

    return line_st, line_ed
end

---@return number? row_st # 0-base index
---@return number? col_st # 0-base index
---@return number? row_ed # 0-base index
---@return number? col_ed # 0-base index
function M.visual_selection_range()
    local unpac = unpack or table.unpack
    local st_r, st_c, ed_r, ed_c

    local cur_mode = api.nvim_get_mode().mode
    if cur_mode == "v" then
        _, st_r, st_c, _ = unpac(vim.fn.getpos("v"))
        _, ed_r, ed_c, _ = unpac(vim.fn.getpos("."))
    else
        _, st_r, st_c, _ = unpac(vim.fn.getpos("'<"))
        _, ed_r, ed_c, _ = unpac(vim.fn.getpos("'>"))
    end

    if st_r * st_c * ed_r * ed_c == 0 then return nil end
    if st_r < ed_r or (st_r == ed_r and st_c <= ed_c) then
        return st_r - 1, st_c - 1, ed_r - 1, ed_c
    else
        return ed_r - 1, ed_c - 1, st_r - 1, st_c
    end
end

---@return string? text
function M.visual_selection_text()
    local st_r, st_c, ed_r, ed_c = M.visual_selection_range()
    if not (st_r and st_c and ed_r and ed_c) then return nil end

    local bufnr = 0

    local ed_line = api.nvim_buf_get_lines(bufnr, ed_r, ed_r + 1, true)[1]
    local delta = vim.str_utf_end(ed_line, ed_c)

    local list = api.nvim_buf_get_text(bufnr, st_r, st_c, ed_r, ed_c + delta, {})
    local selected = table.concat(list)
    return #selected ~= 0 and selected or nil
end

-- Return a list containing all visible buffer handler in given tabpage.
---@param tabpage integer # Tab number, 0 for current tab.
---@return integer[] bufs
function M.list_visible_buf(tabpage)
    local result = {}
    local wins = api.nvim_tabpage_list_wins(tabpage)
    for _, win in ipairs(wins) do
        local buf = api.nvim_win_get_buf(win)
        table.insert(result, buf)
    end
    return result
end

---@param msg string
function M.ask_for_confirmation(msg)
    local answer = vim.fn.input(msg .. " [Y/N]: ")
    if answer == "Y" or answer == "y" then
        return true
    elseif answer == "N" or answer == "n" then
        return false
    else
        vim.notify("Please answer with Y or N (case insensitive).")
        return false
    end
end

---@param msg_lines string[]
---@param on_confirm fun(ok: boolean)
function M.ask_for_confirmation_with_popup(msg_lines, on_confirm)
    if type(on_confirm) ~= "function" then
        error("on_confirm is supposed to be a function")
    end

    local buf = api.nvim_create_buf(false, true)
    if buf == 0 then
        vim.notify("failed to create popup buffer.")
        return
    end

    M.write_to_buf_with_highlight(
        buf, "Search", "-- Press 'Enter' to confirm, 'Escape' to cancel.",
        PanelContentUpdateMethod.append
    )
    M.write_to_buf(buf, "", PanelContentUpdateMethod.append)
    M.write_to_buf(buf, msg_lines, PanelContentUpdateMethod.append)

    local line_cnt = #msg_lines + 2

    local editor_w, editor_h = vim.o.columns, vim.o.lines
    local w = math.min(80, editor_w)
    local h = math.min(line_cnt, editor_h)
    local row = math.floor((editor_h - h) / 2)
    local col = math.floor((editor_w - w) / 2)

    local win = api.nvim_open_win(buf, true, {
        width = w,
        height = h,
        row = row,
        col = col,
        relative = "editor",
        border = "rounded",
    })

    local opts = { noremap = true, silent = true, buffer = buf }
    vim.keymap.set("n", "<esc>", function()
        on_confirm(false)
        api.nvim_win_close(win, true)
        api.nvim_buf_delete(buf, {})
    end, opts)
    vim.keymap.set("n", "<cr>", function()
        on_confirm(true)
        api.nvim_win_close(win, true)
        api.nvim_buf_delete(buf, {})
    end, opts)

    vim.bo[buf].modifiable = false
end

---@param msg_lines string[]
function M.show_info_popup(msg_lines)
    local buf = api.nvim_create_buf(false, true)
    if buf == 0 then
        vim.notify("failed to create popup buffer.")
        return
    end

    M.write_to_buf_with_highlight(
        buf, "Search", "-- Press 'q' or 'Escape' to quite.",
        PanelContentUpdateMethod.append
    )
    M.write_to_buf(buf, "", PanelContentUpdateMethod.append)
    M.write_to_buf(buf, msg_lines, PanelContentUpdateMethod.append)

    local line_cnt = #msg_lines + 2

    local editor_w, editor_h = vim.o.columns, vim.o.lines
    local w = math.min(80, editor_w)
    local h = math.min(line_cnt, editor_h)
    local row = math.floor((editor_h - h) / 2)
    local col = math.floor((editor_w - w) / 2)

    local win = api.nvim_open_win(buf, true, {
        width = w,
        height = h,
        row = row,
        col = col,
        relative = "editor",
        border = "rounded",
    })

    local opts = { noremap = true, silent = true, buffer = buf }
    vim.keymap.set("n", "<esc>", function()
        api.nvim_win_close(win, true)
        api.nvim_buf_delete(buf, {})
    end, opts)
    vim.keymap.set("n", "q", function()
        api.nvim_win_close(win, true)
        api.nvim_buf_delete(buf, {})
    end, opts)

    vim.bo[buf].modifiable = false
end

-- -----------------------------------------------------------------------------
-- Scroll

---@param win integer
---@param method ScrollMethod
---@param offset? integer
function M.scroll_win(win, method, offset)
    offset = offset or 0
    local cur_win = api.nvim_get_current_win()
    local cur_pos = api.nvim_win_get_cursor(cur_win)

    local buf = api.nvim_win_get_buf(win)
    local line_cnt = api.nvim_buf_line_count(buf)

    local to_line = line_cnt
    if method == ScrollMethod.top then
        to_line = 1
    elseif method == ScrollMethod.bottom then
        to_line = line_cnt
    elseif method == ScrollMethod.compare then
        to_line = cur_pos[1]
    end

    to_line = math.max(1, math.min(line_cnt, to_line + offset))
    api.nvim_win_set_cursor(win, { to_line, 0 })
end

function M.scroll_win_to_top(win)
    M.scroll_win(win, ScrollMethod.top)
end

function M.scroll_win_to_bottom(win)
    M.scroll_win(win, ScrollMethod.bottom)
end

-- -----------------------------------------------------------------------------
-- Find & Create

---@param pos PanelPosition
---@param buf integer # 需要绑定到新窗口的 buffer 编号
---@param is_switch_to boolean # 是否需要在创建窗口之后即跳转到新窗口
---@return integer win # 新创建的窗口的
function M.create_panel(buf, pos, is_switch_to)
    local cur_win = api.nvim_get_current_win()

    local cmd = "vsplit"
    if pos == PanelPosition.top then
        cmd = "topleft split"
    elseif pos == PanelPosition.right then
        cmd = "rightbelow vsplit"
    elseif pos == PanelPosition.bottom then
        cmd = "botright split"
    elseif pos == PanelPosition.left then
        cmd = "leftabove vsplit"
    end

    vim.cmd(cmd)
    local win = api.nvim_get_current_win()
    api.nvim_win_set_buf(win, buf)

    if not is_switch_to then
        api.nvim_set_current_win(cur_win)
    end

    return win
end

---@param buf integer
---@param is_in_current_tabpage boolean
---@return integer? winnr
function M.find_win_with_buf(buf, is_in_current_tabpage)
    if not buf then return nil end

    local wins = is_in_current_tabpage
        and api.nvim_tabpage_list_wins(0)
        or api.nvim_list_wins()

    local win
    for _, w in ipairs(wins) do
        if api.nvim_win_get_buf(w) == buf then
            win = w
            break
        end
    end

    return win
end

---@param name string
---@return integer? buf_num # 匹配 buffer 的编号
---@return integer? win_num # 包含此 buffer 的窗口的编号
function M.find_buf_with_name(name)
    local buf_num, win_num = nil, nil

    -- 存在性检验
    for _, buf in ipairs(api.nvim_list_bufs()) do
        -- 此接口无法获取 buffer 的显示名
        -- buf_name = api.nvim_buf_get_name(buf)
        local buf_name = vim.fn.bufname(buf)

        if buf_name == name then
            buf_num = buf
            win_num = M.find_win_with_buf(buf_num, true)
            break
        end
    end

    return buf_num, win_num
end

---@param name string
---@return integer buf_num # buffer 的编号
---@return integer? win_num # 包含此 buffer 的窗口的编号
function M.find_or_create_buf_with_name(name)
    local buf, win = M.find_buf_with_name(name)

    if not buf then
        buf = api.nvim_create_buf(true, false)
        api.nvim_buf_set_name(buf, name)
    end

    return buf, win
end

---@param name string
---@param is_visible boolean
---@return integer buf # 面板使用的 buffer 编号
---@return integer? win # 面板全用的窗口编号
function M.set_panel_visibility(name, is_visible)
    is_visible = is_visible or false

    local buf, win = M.find_or_create_buf_with_name(name)

    if not win and is_visible then
        win = M.create_panel(buf, M.default_position_for_new_window, false)
    elseif win and not is_visible then
        api.nvim_win_hide(win)
    end

    return buf, win
end

---@param name string
---@return integer buf # 面板使用的 buffer 编号
---@return integer win # 面板使用的窗口编号
function M.toggle_panel_visibility(name)
    local buf, win = M.find_or_create_buf_with_name(name)

    if not win then
        win = M.create_panel(buf, M.default_position_for_new_window, false)
    elseif win then
        api.nvim_win_hide(win)
    end

    return buf, win
end

-- -----------------------------------------------------------------------------
-- Write

---@param buf integer
function M.clear_buffer_contnet(buf)
    api.nvim_buf_set_lines(buf, 0, -1, true, {})
end

---@param buf integer
---@param content any
---@param line_st integer
---@param line_ed integer
---@return integer written_line_cnt
function M.write_lines_to_buf(buf, content, line_st, line_ed)
    local lines
    local content_type = type(content)
    if content_type == "string" then
        lines = vim.split(content, "\n")
    elseif content_type == "table" then
        lines = {}
        for i = 1, #content do
            lines[#lines + 1] = tostring(content[i])
        end
    else
        lines = { tostring(content) }
    end
    api.nvim_buf_set_lines(buf, line_st, line_ed, true, lines)

    return #lines
end

---@param name string
---@param content any
---@param line_st integer
---@param line_ed integer
---@param is_need_show boolean
---@return integer buf
---@return integer? win
---@return integer written_line_cnt
function M.write_lines_to_panel(name, content, line_st, line_ed, is_need_show)
    local buf, win = M.find_or_create_buf_with_name(name)
    if is_need_show and not win then
        win = M.create_panel(buf, M.default_position_for_new_window, false)
    end

    local written_line_cnt = M.write_lines_to_buf(buf, content, line_st, line_ed)

    return buf, win, written_line_cnt
end

---@param buf integer
---@param content string|string[]
---@param method PanelContentUpdateMethod
---@return integer written_line_cnt
function M.write_to_buf(buf, content, method)
    local line_st, line_ed = M.update_method_to_line_range(method)
    return M.write_lines_to_buf(buf, content, line_st, line_ed)
end

---@param name string
---@param content any
---@param method PanelContentUpdateMethod
---@param is_need_show boolean
---@return integer buf
---@return integer? win
---@return integer written_line_cnt
function M.write_to_panel(name, content, method, is_need_show)
    local line_st, line_ed = M.update_method_to_line_range(method)
    return M.write_lines_to_panel(name, content, line_st, line_ed, is_need_show)
end

---@param buf integer
---@param hl_name string
---@param content any
---@param method PanelContentUpdateMethod
function M.write_to_buf_with_highlight(buf, hl_name, content, method)
    local line_st, line_ed = M.update_method_to_line_range(method, buf)
    local line_cnt = M.write_lines_to_buf(buf, content, line_st, line_ed)
    local content_line_cnt = api.nvim_buf_line_count(buf)

    if line_st < 0 then
        line_st = content_line_cnt - line_cnt
    end

    for l = line_st, line_st + line_cnt do
        api.nvim_buf_add_highlight(buf, 0, hl_name, l, 0, -1)
    end
end

---@param name string
---@param hl_name string
---@param content any
---@param method PanelContentUpdateMethod
---@param is_need_show boolean
function M.write_to_panel_with_highlight(name, hl_name, content, method, is_need_show)
    local line_st, line_ed = M.update_method_to_line_range(method)
    local buf, _, line_cnt = M.write_lines_to_panel(name, content, line_st, line_ed, is_need_show)

    local content_line_cnt = api.nvim_buf_line_count(buf)
    if line_st < 0 then
        line_st = content_line_cnt - line_cnt
    end

    for l = line_st, line_st + line_cnt do
        api.nvim_buf_add_highlight(buf, 0, hl_name, l, 0, -1)
    end
end

-- -----------------------------------------------------------------------------

M.default_position_for_new_window = PanelPosition.right

function M.setup(config)
    config = config or {}

    M.default_position_for_new_window = config.default_position_for_new_window
        or PanelPosition.right
end

return M
