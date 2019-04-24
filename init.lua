local mod_name = minetest.get_current_modname()

local function log(level, message)
    minetest.log(level, ('[%s] %s'):format(mod_name, message))
end

log('action', 'CSM loading...')

local mod_storage = minetest.get_mod_storage()

-- configurable values --

local PER_SERVER = true  -- set to false if you want to use the same player statuses on all servers
local AUTO_ALERT_ON_NAME = true  -- set to false if you don't want messages that mention you to highlight automatically
local COLORS = {
    server='#FF9900',  -- don't remove
    self='#FF8888',  -- don't remove
    admin='#00FFFF',
    privileged='#FFFF00',
    friend='#00FF00',
    other='#FF00FF',
    trouble='#FF0000',
    default='#888888',  -- don't remove
}

-- END configurable values --
-- general functions --

local function safe(func)
    -- wrap a function w/ logic to avoid crashing the game
    local f = function(...)
        local status, out = pcall(func, ...)
        if status then
            return out
        else
            log('warning', 'Error (func):  ' .. out)
            return nil
        end
    end
    return f
end


local function lc_cmp(a, b)
    return a:lower() < b:lower()
end


local function pairsByKeys(t, f)
    local a = {}
    for n in pairs(t) do
        table.insert(a, n)
    end
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

-- END general functions --
-- mod_storage access --

local server_id
if PER_SERVER then
    local server_info = minetest.get_server_info()
    server_id = server_info.address .. ':' .. server_info.port
else
    server_id = ''
end


local status_by_name


local function load_status_by_name()
    local serialized_storage = mod_storage:get_string(server_id)
    if string.find(serialized_storage, 'return') then
        return minetest.deserialize(serialized_storage)
    else
        mod_storage:set_string(server_id, minetest.serialize({}))
        return {}
    end
end


local function save_status_by_name()
    mod_storage:set_string(server_id, minetest.serialize(status_by_name))
end


status_by_name = load_status_by_name()


local function get_name_status(name)
    return status_by_name[name] or 'default'
end


local function set_name_status(name, status)
    status_by_name = load_status_by_name()
    status_by_name[name] = status
    save_status_by_name()
end


local alert_patterns


local function load_alert_patterns()
    local serialized_storage = mod_storage:get_string(('%s:alert_patterns'):format(server_id))
    if string.find(serialized_storage, 'return') then
        return minetest.deserialize(serialized_storage)
    else
        mod_storage:set_string(server_id .. ':alert_patterns', minetest.serialize({}))
        return {}
    end
end


local function save_alert_patterns()
    mod_storage:set_string(('%s:alert_patterns'):format(server_id), minetest.serialize(alert_patterns))
end


alert_patterns = load_alert_patterns()


local function add_alert_pattern(pattern)
    alert_patterns = load_alert_patterns()
    alert_patterns[pattern] = true
    save_alert_patterns()
end


local function remove_alert_pattern(pattern)
    alert_patterns = load_alert_patterns()
    alert_patterns[pattern] = nil
    save_alert_patterns()
end


-- END mod_storage access --
-- initalization --

local function set_my_name()
    local name = minetest.localplayer:get_name()
    if name then
        log('action', ('you are %s'):format(name))
        set_name_status(name, 'self')
        if AUTO_ALERT_ON_NAME then
            add_alert_pattern(name)
        end
    else
        minetest.after(1, set_my_name)
    end
end


if minetest.register_on_connect then
    minetest.register_on_connect(set_my_name)
elseif minetest.register_on_mods_loaded then
    minetest.register_on_mods_loaded(set_my_name)
else
    set_my_name()
end

-- END initalization --
-- chat commands --

minetest.register_chatcommand('fc_ss', {
    description = 'list statuses',
    func = safe(function()
        for name, color in pairsByKeys(COLORS) do
            if name and color then
                minetest.display_chat_message(minetest.colorize(color, ('%s: %s'):format(name, color)))
            end
        end
    end),
})


minetest.register_chatcommand('fc_s', {
    params = '<name> <status>',
    description = 'associate a name w/ a status',
    func = safe(function(param)
        local name, status = param:match('^(%S+)%s+(%S+)$')
        if name ~= nil then
            if not COLORS[status] then
                minetest.display_chat_message(minetest.colorize('#FF0000', ('unknown status "%s"'):format(status)))
                return false
            end
            set_name_status(name, status)
            minetest.display_chat_message(minetest.colorize(COLORS[status], ('%s is now %s'):format(name, status)))
            return true
        else
            minetest.display_chat_message(minetest.colorize('#FF0000', 'invalid syntax'))
            return false
        end
    end),
})


minetest.register_chatcommand('fc_rm', {
    params = '<name>',
    description = 'unregister a name',
    func = safe(function(name)
        set_name_status(name, nil)
        minetest.display_chat_message(minetest.colorize(COLORS.server, ('unregistered %s'):format(name)))
    end),
})


minetest.register_chatcommand('fc_ls', {
    description = 'list all statuses',
    func = safe(function()
        for name, status in pairsByKeys(status_by_name, lc_cmp) do
            local color = COLORS[status] or COLORS.default
            minetest.display_chat_message(minetest.colorize(color, ('%s: %s'):format(name, status)))
        end
    end),
})


minetest.register_chatcommand('fc_a_ls', {
    description = 'list all alert patterns',
    func = safe(function()
        for pattern, _ in pairsByKeys(alert_patterns, lc_cmp) do
            minetest.display_chat_message(minetest.colorize(COLORS.server, pattern))
        end
    end),
})


minetest.register_chatcommand('fc_a_s', {
    params = '<pattern>',
    description = 'alert on a given pattern',
    func = safe(function(pattern)
        add_alert_pattern(pattern)
    end),
})


minetest.register_chatcommand('fc_a_rm', {
    params = '<pattern>',
    description = 'no longer alert on a given pattern',
    func = safe(function(pattern)
        remove_alert_pattern(pattern)
    end),
})


-- END chat commands --

local function clean_android(msg)
    -- supposedly, android surrounds messages with (c@#ffffff)
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
    name, _ = name:match('^([^@]+).*$')  -- strip @... from IRC users
    name, _ = name:match('^([^[]+).*$')  -- strip [m] from matrix users

    local status = get_name_status(name)
    return COLORS[status] or COLORS.default
end


local function color_name(name)
    local color = get_color_by_name(name)
    return minetest.colorize(color, name)
end


local function color_names(names, delim)
    local text = ''
    local sorted_names = {}

    for name in names:gmatch('[%w_-]+') do
        table.insert(sorted_names, name)
    end

    table.sort(sorted_names, lc_cmp)

    for i, name in ipairs(sorted_names) do
        sorted_names[i] = color_name(name)
    end

    return table.concat(sorted_names, delim)
end


local function color_name_and_text(name, text)
    local color = get_color_by_name(name)
    name = color_name(name)

    for pattern, _ in pairs(alert_patterns) do
        if text:lower():match(pattern:lower()) then
            return name, minetest.colorize(COLORS.self, text)
        end
    end

    if color == COLORS.default then
        text = minetest.colorize(color, text)
    end

    return name, text
end


local register_on_receive = minetest.register_on_receiving_chat_message or minetest.register_on_receiving_chat_messages


if register_on_receive then
register_on_receive(safe(function(message)
    local msg = clean_android(minetest.strip_colors(message))

    -- join/part messages
    local name, text = msg:match('^%*%*%* (%S+) (.*)$')
    if name and text then
        name, text = color_name_and_text(name, text)
        minetest.display_chat_message(('*** %s %s'):format(name, text))
        return true
    end

    -- normal messages
    local name, text = msg:match('^<([^%s>]+)>%s+(.*)$')
    if name and text then
        name, text = color_name_and_text(name, text)
        minetest.display_chat_message(('<%s> %s'):format(name, text))
        return true
    end

    -- /me messages
    local name, text = msg:match('^%* (%S+) (.*)$')
    if name and text then
        name, text = color_name_and_text(name, text)
        minetest.display_chat_message(('* %s %s'):format(name, text))
        return true
    end

    -- /msg messages
    local name, text = msg:match('^PM from (%S+): (.*)$')
    if name and text then
        minetest.display_chat_message(('%s%s%s%s'):format(
            minetest.colorize(COLORS.server, 'PM from '),
            color_name(name),
            minetest.colorize(COLORS.server, ': '),
            minetest.colorize(COLORS.self, text)
        ))
        return true
    end

    -- /tell messages
    local name, text = msg:match('^(%S+) whispers: (.*)$')
    if name and text then
        minetest.display_chat_message(('%s%s%s%s'):format(
            color_name(name),
            minetest.colorize(COLORS.server, ' whispers: '),
            minetest.colorize(COLORS.self, text)
        ))
        return true
    end

    -- /who
    local names = msg:match('^Players in channel: (.*)$')
    if names then
        minetest.display_chat_message(('%s%s'):format(
            minetest.colorize(COLORS.server, 'Players in channel: '),
            color_names(names, ', ')
        ))
        return true
    end

    -- /status
    local text, names, lastbit = msg:match('^# Server: (.*) clients={([^}]*)}(.*)')
    if text and names then
        minetest.display_chat_message(('%s%s%s%s%s%s'):format(
            minetest.colorize(COLORS.server, '# Server: '),
            minetest.colorize(COLORS.server, text),
            minetest.colorize(COLORS.server, ' clients={'),
            color_names(names, ', '),
            minetest.colorize(COLORS.server, '}'),
            minetest.colorize(COLORS.server, lastbit)
        ))
        return true
    end

    -- BlS moderator PM snooping
    local name1, name2, text = msg:match('^([%w_-]+) to ([%w_-]+): (.*)$')
    if name1 and name2 and text then
        minetest.display_chat_message(('%s%s%s%s%s'):format(
            color_name(name1),
            minetest.colorize(COLORS.server, ' to '),
            color_name(name2),
            minetest.colorize(COLORS.server, ': '),
            minetest.colorize(COLORS.server, text)
        ))
        return true
    end

    -- other server messages
    minetest.display_chat_message(minetest.colorize(COLORS.server, msg))
    return true
end))
end
