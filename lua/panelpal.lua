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
---@return integer line_st
---@return integer line_ed
function M.update_method_to_line_range(method)
    local line_st, line_ed = -1, -1
    if method == PanelContentUpdateMethod.append then
        line_st, line_st = -1, -1
    elseif method == PanelContentUpdateMethod.override then
        line_st, line_ed = 0, -1
    elseif method == PanelContentUpdateMethod.prepend then
        line_st, line_st = 0, 0
    end

    return line_st, line_ed
end

---@return number? row_st
---@return number? col_st
---@return number? row_ed
---@return number? col_ed
function M.visual_selection_range()
    local unpac = unpack or table.unpack
    local _, st_r, st_c, _ = unpac(vim.fn.getpos("v"))
    local _, ed_r, ed_c, _ = unpac(vim.fn.getpos("."))
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
    if not (st_r or st_c or ed_r or ed_c) then return nil end

    local list = vim.api.nvim_buf_get_text(0, st_r, st_c, ed_r, ed_c, {})
    local selected = table.concat(list)
    return #selected ~= 0 and selected or nil
end

-- Return a list containing all visible buffer handler in given tabpage.
---@param tabpage integer # Tab number, 0 for current tab.
---@return integer[] bufs
function M.list_visible_buf(tabpage)
    local result = {}
    local wins = vim.api.nvim_tabpage_list_wins(tabpage)
    for _, win in ipairs(wins) do
        local buf = vim.api.nvim_win_get_buf(win)
        table.insert(result, buf)
    end
    return result
end

---@param win integer
---@param method ScrollMethod
---@param offset? integer
function M.scroll_win(win, method, offset)
    offset = offset or 0
    local cur_win = vim.api.nvim_get_current_win()
    local cur_pos = vim.api.nvim_win_get_cursor(cur_win)

    local buf = vim.api.nvim_win_get_buf(win)
    local line_cnt = vim.api.nvim_buf_line_count(buf)

    local to_line = line_cnt
    if method == ScrollMethod.top then
        to_line = 1
    elseif method == ScrollMethod.bottom then
        to_line = line_cnt
    elseif method == ScrollMethod.compare then
        to_line = cur_pos[1]
    end

    to_line = math.max(1, math.min(line_cnt, to_line + offset))
    vim.api.nvim_win_set_cursor(win, { to_line, 0 })

    vim.api.nvim_win_set_cursor(cur_win, cur_pos)
end

function M.scroll_win_to_top(win)
    M.scroll_win(win, ScrollMethod.top)
end

function M.scroll_win_to_bottom(win)
    M.scroll_win(win, ScrollMethod.bottom)
end

---@param pos PanelPosition
---@param buf integer # 需要绑定到新窗口的 buffer 编号
---@param is_switch_to boolean # 是否需要在创建窗口之后即跳转到新窗口
---@return integer win # 新创建的窗口的
function M.create_panel(buf, pos, is_switch_to)
    local cur_win = vim.api.nvim_get_current_win()

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
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)

    if not is_switch_to then
        vim.api.nvim_set_current_win(cur_win)
    end

    return win
end

---@param name string
---@return integer? buf_num # 匹配 buffer 的编号
---@return integer? win_num # 包含此 buffer 的窗口的编号
function M.find_buf_with_name(name)
    local buf_num, win_num = nil, nil

    -- 存在性检验
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        -- 此接口无法获取 buffer 的显示名
        -- buf_name = vim.api.nvim_buf_get_name(buf)
        local buf_name = vim.fn.bufname(buf)

        if buf_name == name then
            buf_num = buf

            -- 可见性检验
            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                if vim.api.nvim_win_get_buf(win) == buf_num then
                    win_num = win
                    break
                end
            end

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
        buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_name(buf, name)
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
        vim.api.nvim_win_hide(win)
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
        vim.api.nvim_win_hide(win)
    end

    return buf, win
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
    vim.api.nvim_buf_set_lines(buf, line_st, line_ed, true, lines)

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
    local line_st, line_ed = M.update_method_to_line_range(method)
    local line_cnt = M.write_lines_to_buf(buf, content, line_st, line_ed)
    local content_line_cnt = vim.api.nvim_buf_line_count(buf)

    if line_st < 0 then
        line_st = content_line_cnt - line_cnt
    end

    for l = line_st, line_st + line_cnt do
        vim.api.nvim_buf_add_highlight(buf, 0, hl_name, l, 0, -1)
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

    local content_line_cnt = vim.api.nvim_buf_line_count(buf)
    if line_st < 0 then
        line_st = content_line_cnt - line_cnt
    end

    for l = line_st, line_st + line_cnt do
        vim.api.nvim_buf_add_highlight(buf, 0, hl_name, l, 0, -1)
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
