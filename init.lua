local mod_name = minetest.get_current_modname()

local function log(level, message)
    minetest.log(level, ('[%s] %s'):format(mod_name, message))
end

log('action', 'CSM loading...')

-- configurable values --

local PER_SERVER = true  -- set to false if you want to use the same player statuses on all servers
local AUTO_ALERT_ON_NAME = true  -- set to false if you don't want messages that mention you to highlight automatically
local COLOR_BY_STATUS = {
    default='#888888',  -- don't remove or change the name of this status!
    server='#FF9900',  -- don't remove or change the name of this status!
    self='#FF8888',  -- don't remove or change the name of this status!

    -- these can be changed to your liking.
    -- TODO: make these configurable in game?
    admin='#00FFFF',
    privileged='#FFFF00',
    friend='#00FF00',
    contact='#4444FF',
    other='#FF00FF',
    trouble='#FF0000',
}
local LIGHTEN_TEXT_BY = .8 -- 0 == same color as status; 1 == pure white.

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


local function round(x)
    -- approved by kahan
    if x % 2 ~= 0.5 then
        return math.floor(x+0.5)
    else
        return x - 0.5
    end
end


local function bound(min, val, max)
    return math.min(max, math.max(min, val))
end


local function lighten(hex_color, percent)
    -- lighten a hexcolor (#XXXXXX) by a percent (0.0=none, 1.0=full white)
    local r = tonumber(hex_color:sub(2,3), 16)
    local g = tonumber(hex_color:sub(4,5), 16)
    local b = tonumber(hex_color:sub(6,7), 16)

    r = bound(0, round(((1 - percent) * r) + (percent * 255)), 255)
    g = bound(0, round(((1 - percent) * g) + (percent * 255)), 255)
    b = bound(0, round(((1 - percent) * b) + (percent * 255)), 255)

    return ('#%02x%02x%02x'):format(r, g, b)
end

-- END general functions --
-- mod_storage access --

local mod_storage = minetest.get_mod_storage()

local server_id
if PER_SERVER then
    local server_info = minetest.get_server_info()
    server_id = server_info.address .. ':' .. server_info.port
else
    server_id = ''
end

-- -- mod_storage: status_by_name -- --

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

-- -- END mod_storage: status_by_name -- --
-- -- mod_storage: alert_patterns -- --

local alert_patterns


local function load_alert_patterns()
    local serialized_storage = mod_storage:get_string(('%s:alert_patterns'):format(server_id))
    if string.find(serialized_storage, 'return') then
        return minetest.deserialize(serialized_storage)
    else
        mod_storage:set_string(('%s:alert_patterns'):format(server_id), minetest.serialize({}))
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

-- -- END mod_storage: alert_patterns -- --
-- -- mod_storage: disabled_servers -- --

local disabled_servers


local function load_disabled_servers()
    local serialized_storage = mod_storage:get_string('disabled_servers')
    if string.find(serialized_storage, 'return') then
        return minetest.deserialize(serialized_storage)
    else
        local ds = {['94.16.121.151:2500'] = true }  -- disable on IFS by default
        mod_storage:set_string('disabled_servers', minetest.serialize(ds))
        return ds
    end
end


local function save_disabled_servers()
    mod_storage:set_string('disabled_servers', minetest.serialize(disabled_servers))
end


disabled_servers = load_disabled_servers()


local function toggle_disable_this_server()
    local current_status
    disabled_servers = load_disabled_servers()
    if disabled_servers[server_id] then
        disabled_servers[server_id] = nil
        current_status = false
    else
        disabled_servers[server_id] = true
        current_status = true
    end
    save_disabled_servers()
    return current_status
end

-- -- END mod_storage: disabled_servers -- --
-- END mod_storage access --
-- initalization --

local set_my_name = safe(function()
    local name
    if minetest.localplayer then
        name = minetest.localplayer:get_name()
    end
    if name then
        log('action', ('you are %s'):format(name))
        set_name_status(name, 'self')
        if AUTO_ALERT_ON_NAME then
            add_alert_pattern(name)
        end
    else
        log('warning', 'could not determine name!')
    end
end)


if minetest.register_on_connect then
    minetest.register_on_connect(set_my_name)
elseif minetest.register_on_mods_loaded then
    minetest.register_on_mods_loaded(set_my_name)
else
    minetest.after(1, set_my_name)
end

-- END initalization --
-- chat commands --

minetest.register_chatcommand('ch_toggle', {
    description = ('turn %s on/off for this server'):format(mod_name),
    func = safe(function()
        local current_status = toggle_disable_this_server()
        if current_status then
            current_status = 'off'
        else
            current_status = 'on'
        end
        minetest.display_chat_message(('%s is now %s for server "%s"'):format(mod_name, current_status, server_id))
    end),
})


minetest.register_chatcommand('ch_statuses', {
    description = 'list statuses',
    func = safe(function()
        for name, color in pairsByKeys(COLOR_BY_STATUS) do
            if name and color then
                minetest.display_chat_message(minetest.colorize(color, ('%s: %s'):format(name, color)))
            end
        end
    end),
})


minetest.register_chatcommand('ch_set', {
    params = '<name> <status>',
    description = 'associate a name w/ a status',
    func = safe(function(param)
        local name, status = param:match('^(%S+)%s+(%S+)$')
        if name ~= nil then
            if not COLOR_BY_STATUS[status] then
                minetest.display_chat_message(minetest.colorize('#FF0000', ('unknown status "%s"'):format(status)))
                return false
            end
            set_name_status(name, status)
            minetest.display_chat_message(minetest.colorize(COLOR_BY_STATUS[status], ('%s is now %s'):format(name, status)))
            return true
        else
            minetest.display_chat_message(minetest.colorize('#FF0000', 'invalid syntax'))
            return false
        end
    end),
})


minetest.register_chatcommand('ch_unset', {
    params = '<name>',
    description = 'unregister a name',
    func = safe(function(name)
        set_name_status(name, nil)
        minetest.display_chat_message(minetest.colorize(COLOR_BY_STATUS.server, ('unregistered %s'):format(name)))
    end),
})


minetest.register_chatcommand('ch_list', {
    description = 'list all statuses',
    func = safe(function()
        for name, status in pairsByKeys(status_by_name, lc_cmp) do
            local color = COLOR_BY_STATUS[status] or COLOR_BY_STATUS.default
            minetest.display_chat_message(minetest.colorize(color, ('%s: %s'):format(name, status)))
        end
    end),
})


minetest.register_chatcommand('ch_alert_list', {
    description = 'list all alert patterns',
    func = safe(function()
        for pattern, _ in pairsByKeys(alert_patterns, lc_cmp) do
            minetest.display_chat_message(minetest.colorize(COLOR_BY_STATUS.server, pattern))
        end
    end),
})


minetest.register_chatcommand('ch_alert_set', {
    params = '<pattern>',
    description = 'alert on a given pattern',
    func = safe(function(pattern)
        add_alert_pattern(pattern)
    end),
})


minetest.register_chatcommand('ch_alert_unset', {
    params = '<pattern>',
    description = 'no longer alert on a given pattern',
    func = safe(function(pattern)
        remove_alert_pattern(pattern)
    end),
})


-- END chat commands --

local function clean_android(msg)
    -- supposedly, android surrounds messages with (c@#ffffff)
    if msg:sub(1, 4) == '(c@#' then -- strip preceeding
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
    return COLOR_BY_STATUS[status] or COLOR_BY_STATUS.default
end


local function color_name(name)
    local color = get_color_by_name(name)
    return minetest.colorize(color, name)
end


local function color_names(names, delim)
    local text = ''
    local sorted_names = {}

    for name in names:gmatch('[%w_%-]+') do
        table.insert(sorted_names, name)
    end

    table.sort(sorted_names, lc_cmp)

    for i, name in ipairs(sorted_names) do
        sorted_names[i] = color_name(name)
    end

    return table.concat(sorted_names, delim)
end


local function color_text(name, text)
    for pattern, _ in pairs(alert_patterns) do
        if text:lower():match(pattern:lower()) then
            minetest.sound_play('default_dug_metal')
            return minetest.colorize(COLOR_BY_STATUS.self, text)
        end
    end

    local color = get_color_by_name(name)

    if color == COLOR_BY_STATUS.default then
        return minetest.colorize(COLOR_BY_STATUS.default, text)
    else
        color = lighten(color, LIGHTEN_TEXT_BY)
        return minetest.colorize(color, text)
    end
end


local function idiv(a, b)
    return (a - (a % b)) / b
end


local function seconds_to_interval(time)
    local s = time % 60; time = idiv(time, 60)
    local m = time % 60; time = idiv(time, 60)
    local h = time % 24; time = idiv(time, 24)
    if time ~= 0 then
        return ('%d days %02d:%02d:%02d'):format(time, h, m, s)
    elseif h ~= 0 then
        return ('%02d:%02d:%02d'):format(h, m, s)
    elseif m ~= 0 then
        return ('%02d:%02d'):format(m, s)
    else
        return ('%d seconds'):format(s)
    end
end


local register_on_receive = minetest.register_on_receiving_chat_message or minetest.register_on_receiving_chat_messages


if register_on_receive then
register_on_receive(safe(function(message)
    if disabled_servers[server_id] then
        return false
    end

    local msg = clean_android(minetest.strip_colors(message))

    -- join/part messages
    local name, text = msg:match('^%*%*%* (%S+) (.*)$')
    if name and text then
        minetest.display_chat_message(('%s %s %s'):format(
            color_text(name, '***'),
            color_name(name),
            color_text(name, text)
        ))
        return true
    end

    -- normal messages
    local name, text = msg:match('^<([^>]+)>%s+(.*)$')
    if name and text then
        minetest.display_chat_message(('%s%s%s %s'):format(
            color_text(name, '<'),
            color_name(name),
            color_text(name, '>'),
            color_text(name, text)
        ))
        return true
    end

    -- /me messages
    local name, text = msg:match('^%* (%S+) (.*)$')
    if name and text then
        minetest.display_chat_message(('%s %s %s'):format(
            color_text(name, '*'),
            color_name(name),
            color_text(name, text)
        ))
        return true
    end

    -- /msg messages
    local name, text = msg:match('^PM from (%S+): (.*)$')
    if name and text then
        minetest.display_chat_message(('%s%s%s%s'):format(
            minetest.colorize(COLOR_BY_STATUS.server, 'PM from '),
            color_name(name),
            minetest.colorize(COLOR_BY_STATUS.server, ': '),
            minetest.colorize(COLOR_BY_STATUS.self, text)
        ))
        minetest.sound_play('default_place_node_metal')
        return true
    end

    -- /tell messages
    local name, text = msg:match('^(%S+) whispers: (.*)$')
    if name and text then
        minetest.display_chat_message(('%s%s%s%s'):format(
            color_name(name),
            minetest.colorize(COLOR_BY_STATUS.server, ' whispers: '),
            minetest.colorize(COLOR_BY_STATUS.self, text)
        ))
        minetest.sound_play('default_place_node_metal')
        return true
    end

    -- /who
    local names = msg:match('^Players in channel: (.*)$')
    if names then
        minetest.display_chat_message(('%s%s'):format(
            minetest.colorize(COLOR_BY_STATUS.server, 'Players in channel: '),
            color_names(names, ', ')
        ))
        return true
    end

    -- /status
    local text, names, lastbit = msg:match('^# Server: (.*) clients={([^}]*)}(.*)')
    if text and names then
        minetest.display_chat_message(('%s%s%s%s%s%s'):format(
            minetest.colorize(COLOR_BY_STATUS.server, '# Server: '),
            minetest.colorize(COLOR_BY_STATUS.server, text),
            minetest.colorize(COLOR_BY_STATUS.server, ' clients={'),
            color_names(names, ', '),
            minetest.colorize(COLOR_BY_STATUS.server, '}'),
            minetest.colorize(COLOR_BY_STATUS.server, lastbit)
        ))
        return true
    end

    -- IRC join messages
    local name, rest = msg:match('^%-!%- ([%w_%-]+) joined (.*)$')
    if name and rest then
        minetest.display_chat_message(('%s%s%s%s'):format(
            color_text(name, '-!- '),
            color_name(name),
            color_text(name, ' joined '),
            color_text(name, rest)
        ))
        return true
    end

    -- IRC part messages
    local name, rest = msg:match('^%-!%- ([%w_%-]+) has quit (.*)$')
    if name and rest then
        minetest.display_chat_message(('%s%s%s%s'):format(
            color_text(name, '-!- '),
            color_name(name),
            color_text(name, ' has quit '),
            color_text(name, rest)
        ))
        return true
    end

    -- IRC part messages
    local name, rest = msg:match('^%-!%- ([%w_%-]+) has left (.*)$')
    if name and rest then
        minetest.display_chat_message(('%s%s%s%s'):format(
            color_text(name, '-!- '),
            color_name(name),
            color_text(name, ' has left '),
            color_text(name, rest)
        ))
        return true
    end

    -- IRC mode messages
    local rest = msg:match('^%-!%- mode/(.*)$')
    if rest then
        minetest.display_chat_message(minetest.colorize(COLOR_BY_STATUS.default, msg))
        return true
    end

    -- IRC /nick messages
    local name1, name2 = msg:match('^%-!%- (.*) is now known as (.*)$')
    if name1 and name2 then
        minetest.display_chat_message(('%s%s%s%s'):format(
            color_text(name1, '-!- '),
            color_name(name1),
            color_text(name2, ' is now know as '),
            color_name(name2)
        ))
        return true
    end

    -- BlS moderator PM snooping
    local name1, name2, text = msg:match('^([%w_%-]+) to ([%w_%-]+): (.*)$')
    if name1 and name2 and text then
        minetest.display_chat_message(('%s%s%s%s%s'):format(
            color_name(name1),
            minetest.colorize(COLOR_BY_STATUS.server, ' to '),
            color_name(name2),
            minetest.colorize(COLOR_BY_STATUS.server, ': '),
            minetest.colorize(COLOR_BY_STATUS.server, text)
        ))
        return true
    end

    -- BlS unverified player notice
    local name = msg:match('^Player ([%w_%-]+) is unverified%.$')
    if name then
        minetest.display_chat_message(minetest.colorize('#FF0000', msg))
        minetest.sound_play('default_dug_metal')
        return true
    end

    -- BlS unverified player chat
    local name, text = msg:match('^%[unverified] <([^>]+)>%s+(.*)$')
    if name and text then
        minetest.display_chat_message(minetest.colorize('#FF0000', msg))
        minetest.sound_play('default_dug_metal')
        return true
    end

    -- BlS cloaked chat
    local name, text = msg:match('^%-Cloaked%-%s+<([^>]+)>%s+(.*)$')
    if name and text then
        minetest.display_chat_message(('%s%s%s%s %s'):format(
            minetest.colorize(COLOR_BY_STATUS.server, '-Cloaked- '),
            color_text(name, '<'),
            color_name(name),
            color_text(name, '>'),
            color_text(name, text)
        ))
        return true
    end

    -- rollback_check messages
    local pos, name, item1, item2, time = msg:match('%((%-?%d+,%-?%d+,%-?%d+)%) player:(%S+) (%S*) %-> (%S*) (%d+) seconds ago%.')
    if pos and name and item1 and item2 and time then
        if item1 == 'air' then item1 = minetest.colorize('#FF0000', item1) else item1 = minetest.colorize(COLOR_BY_STATUS.server, item1) end
        if item2 == 'air' then item2 = minetest.colorize('#FF0000', item2) else item2 = minetest.colorize(COLOR_BY_STATUS.server, item2) end

        minetest.display_chat_message(('(%s) player:%s %s -> %s %s ago.'):format(
            minetest.colorize(COLOR_BY_STATUS.server, pos),
            color_name(name),
            item1,
            item2,
            seconds_to_interval(tonumber(time))
        ))
        return true
    end

end))
end
