minetest.log('action', '[friendlier_chat] CSM loading...')

local mod_storage = minetest.get_mod_storage()
local my_name = ''
local colors = {
    server='#FF9900',
    self='#FFFF00',
    admin='#00FFFF',
    privileged='#FFFF00',
    friend='#00FF00',
    other='#FF00FF',
    trouble='#FF0000',
    default='#888888'
}

local function safe(func)
    return function(...)
        local status, out = pcall(func, ...)
        if status then
            return out
        else
            minetest.log('warning', '[friendlier_chat] Error (func):  ' .. out)
            return nil
        end
    end
end


local function lc_cmp(a, b)
    return a:lower() < b:lower()
end


local function pairsByKeys(t, f)
    local a = {}
    for n in pairs(t) do table.insert(a, n) end
    table.sort(a, f)
    local i = 0
    return function()
        i = i + 1
        if a[i] == nil then
            return nil
        else
            return a[i], t[a[i]]
        end
    end
end


local server_info = minetest.get_server_info()
local server_id = server_info.address .. ':' .. server_info.port


local function key(name)
    return server_id .. ':' .. name
end


local function unkey(name)
    local pattern = server_id .. ':(.*)'
    return name:match(pattern)
end


local function set_my_name()
    local name = minetest.localplayer:get_name()
    if name then
        minetest.log('action', '[friendlier_chat] you are ' .. name)
        my_name = name
        mod_storage:set_string(key(name), 'self')
    else
        minetest.after(1, set_my_name)
    end
end


if minetest.register_on_connect then
minetest.register_on_connect(set_my_name)
end


minetest.register_chatcommand('fcss', {
    description = 'list statuses',
    func = safe(function()
        for name, color in pairsByKeys(colors) do
            if name and color then
                minetest.display_chat_message(minetest.colorize(color, name .. ': ' .. color))
            end
        end
    end),
})


minetest.register_chatcommand('fcs', {
    params = '<name> <status>',
    description = 'register a name w/ a status',
    func = safe(function(param)
        local name, status = param:match('^(%S+)%s+(%S+)$')
        if name ~= nil then
            if not colors[status] then
                minetest.display_chat_message(minetest.colorize('#FF0000', 'unknown status "' .. status .. '"'))
                return false
            end
            mod_storage:set_string(key(name), status)
            minetest.display_chat_message(minetest.colorize(colors[status], name .. ' is now "' .. status .. '"'))
            return true
        else
            minetest.display_chat_message(minetest.colorize('#FF0000', 'invalid syntax'))
            return false
        end
    end),
})


minetest.register_chatcommand('fcrm', {
    params = '<name>',
    description = 'unregister a name',
    func = safe(function(name)
        mod_strage:set_string(key(name), 'default')
    end),
})


minetest.register_chatcommand('fcls', {
    description = 'list all statuses',
    func = safe(function()
        for name, status in pairsByKeys(mod_storage:to_table().fields, lc_cmp) do
            name = unkey(name)
            local color = colors[status] or colors.default
            minetest.display_chat_message(minetest.colorize(color, name .. ': ' .. status))
        end
    end),
})


local function clean_android(msg)
    -- Android surrounds messages with (c@#ffffff)
    if msg:sub(1, 1) == '(' then -- strip preceeding
        msg = msg:sub(msg:find(')') + 1, -1)
        if msg:sub(-11, -8) == '(c@#' then -- strip trailing
            msg = msg:sub(-11)
        end
    end
    return msg
end


local function get_color_by_name(name)
    local _
    name, _ = name:match('^([^@]+).*$')  -- IRC users
    name, _ = name:match('^([^[]+).*$')  -- matrix users

    local status = mod_storage:get_string(key(name))
    return colors[status] or colors.default
end


local function color_name(name)
    local color = get_color_by_name(name)
    return minetest.colorize(color, name)
end


local function color_names(names, delim)
    local text = ''
    local sorted_names = {}

    for name in names:gmatch('[%w_]+') do
        table.insert(sorted_names, name)
    end

    table.sort(sorted_names, lc_cmp)

    for _, name in ipairs(sorted_names) do
        text = text .. color_name(name) .. delim
    end

    if text ~= '' then
        text = text:sub(1, -(delim:len() + 1))  -- remove last delimiter
    end

    return text
end


local function color_name_and_text(name, text)
    local color = get_color_by_name(name)
    if text:match(my_name) then
        text = minetest.colorize(colors.self, text)

    elseif color == colors.default then
        text = minetest.colorize(color, text)

    end
    return color_name(name), text
end


if minetest.register_on_receiving_chat_messages then
minetest.register_on_receiving_chat_messages(safe(function(message)
    local msg = clean_android(minetest.strip_colors(message))

    -- join/part messages
    local name, text = msg:match('^%*%*%* (%S+) (.*)$')
    if name and text then
        name, text = color_name_and_text(name, text)
        minetest.display_chat_message('*** ' .. name .. ' ' .. text)
        return true
    end

    -- normal messages
    local name, text = msg:match('^<([^%s>]+)>%s+(.*)$')
    if name and text then
        name, text = color_name_and_text(name, text)
        minetest.display_chat_message('<' .. name .. '> ' .. text)
        return true
    end

    -- /me messages
    local name, text = msg:match('^%* (%S+) (.*)$')
    if name and text then
        name, text = color_name_and_text(name, text)
        minetest.display_chat_message('* ' .. name .. ' ' .. text)
        return true
    end

    -- /msg messages
    local name, text = msg:match('^PM from (%S+): (.*)$')
    if name and text then
        name = color_name(name)
        text = minetest.colorize(colors.self, text)
        minetest.display_chat_message(
            minetest.colorize(colors.server, 'PM from ')
            .. name
            .. minetest.colorize(colors.server, ': ')
            .. text
        )
        return true
    end

    -- /tell messages
    local name, text = msg:match('^(%S+) whispers: (.*)$')
    if name and text then
        name = color_name(name)
        text = minetest.colorize(colors.self, text)
        minetest.display_chat_message(
            name
            .. minetest.colorize(colors.server, ' whispers: ')
            .. text
        )
        return true
    end

    -- /who
    local names = msg:match('^Players in channel: (.*)$')
    if names then
        local text = minetest.colorize(colors.server, 'Players in channel: ')
        text = text .. color_names(names, ', ')
        minetest.display_chat_message(text)
        return true
    end

    -- /status
    local text, names, lastbit = msg:match('^# Server: (.*) clients={([^}]*)}(.*)')
    if text and names then
        local text = minetest.colorize(colors.server, '# Server: ' .. text .. ' clients={')
        text = text .. color_names(names, ', ')
        text = text .. minetest.colorize(colors.server, '}' .. lastbit)
        minetest.display_chat_message(text)
        return true
    end

    -- other server messages
    minetest.display_chat_message(minetest.colorize(colors.server, msg))
    return true

end))
end
