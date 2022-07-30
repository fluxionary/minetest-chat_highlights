local register_on_receive = minetest.register_on_receiving_chat_message or minetest.register_on_receiving_chat_messages

if not register_on_receive then
    return
end

local colorize = minetest.colorize

local mod_name = minetest.get_current_modname()

local function log(level, messagefmt, ...)
    minetest.log(level, ("[%s] %s"):format(mod_name, messagefmt:format(...)))
end

log("action", "CSM loading...")

-- configurable values --

local ignore_messages = {
    "Not chiselable",
    "You are now a human",
    "You are now a werewolf",
    --"Werewolves only can eat raw meat!",
    "You missed the snake",
    "Nothing to replace.",
    "Node replacement tool set to:",
    "Your hit glanced off of the protection and turned you around. The protection deals you 1 damage.",
    "Error: \"nothing\" is not a node.",
    ">>> You missed <<<",
}

local function escape_regex(x)
   return (x:gsub("%%", "%%%%")
            :gsub("^%^", "%%^")
            :gsub("%$$", "%%$")
            :gsub("%(", "%%(")
            :gsub("%)", "%%)")
            :gsub("%.", "%%.")
            :gsub("%[", "%%[")
            :gsub("%]", "%%]")
            :gsub("%*", "%%*")
            :gsub("%+", "%%+")
            :gsub("%-", "%%-")
            :gsub("%?", "%%?"))
end

local function should_ignore(text)
    for _, ignore_message in ipairs(ignore_messages) do
        local match, _ = text:match("(" .. escape_regex(ignore_message) .. ")")
        if match and match ~= "" then
            return true
        end
    end
    return false
end

local PER_SERVER = true  -- set to false if you want to use the same player statuses on all servers
local AUTO_ALERT_ON_NAME = true  -- set to false if you don't want messages that mention you to highlight automatically
local COLOR_BY_STATUS = {
    default="#888888",  -- don't remove or change the name of this status!
    server="#FF9900",  -- don't remove or change the name of this status!
    self="#FF8888",  -- don't remove or change the name of this status!

    -- these can be changed to your liking.
    -- TODO: make these configurable in game?
    secretz="#000000",

    admin="#88FFFF",
    privileged="#00FFFF",
    poweruser="#55FFAA",
    ally="#00FF55",
    friend="#00FF00",
    acquaintance="#55FF00",
    contact="#AAFF00",
    noob="#FFFF00",
    trouble="#FF0000",
    rival="#FF0088",
    other="#FF00FF",
}
local LIGHTEN_TEXT_BY = .8 -- 0 == same color as status; 1 == pure white.

local DATE_FORMAT = "%Y%m%dT%H%M%S"

-- END configurable values --
-- general functions --

local function safe(func)
    -- wrap a function w/ logic to avoid crashing the game
    local f = function(...)
        local status, out = pcall(func, ...)
        if status then
            return out
        else
            log("warning", "Error (func):  " .. out)
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

    return ("#%02x%02x%02x"):format(r, g, b)
end

local function get_date_string()
    return os.date(DATE_FORMAT, os.time())
end

-- END general functions --
-- mod_storage access --

local mod_storage = minetest.get_mod_storage()

local server_id
if PER_SERVER then
    local server_info = minetest.get_server_info()
    server_id = server_info.address .. ":" .. server_info.port
else
    server_id = ""
end

-- -- mod_storage: status_by_name -- --

local status_by_name


local function load_status_by_name()
    local serialized_storage = mod_storage:get_string(server_id)
    if string.find(serialized_storage, "return") then
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
    return status_by_name[name] or "default"
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
    local serialized_storage = mod_storage:get_string(("%s:alert_patterns"):format(server_id))
    if string.find(serialized_storage, "return") then
        return minetest.deserialize(serialized_storage)
    else
        mod_storage:set_string(("%s:alert_patterns"):format(server_id), minetest.serialize({}))
        return {}
    end
end


local function save_alert_patterns()
    mod_storage:set_string(("%s:alert_patterns"):format(server_id), minetest.serialize(alert_patterns))
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
    local serialized_storage = mod_storage:get_string("disabled_servers")
    if string.find(serialized_storage, "return") then
        return minetest.deserialize(serialized_storage)
    else
        local ds = {["94.16.121.151:2500"] = true }  -- disable on IFS by default
        mod_storage:set_string("disabled_servers", minetest.serialize(ds))
        return ds
    end
end


local function save_disabled_servers()
    mod_storage:set_string("disabled_servers", minetest.serialize(disabled_servers))
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

local set_my_name_tries = 0
local function set_my_name()
    local name
    if minetest.localplayer then
        name = minetest.localplayer:get_name()
        log("action", ("you are %s"):format(name))
        set_name_status(name, "self")
        if AUTO_ALERT_ON_NAME then
            add_alert_pattern(name)
        end
    elseif set_my_name_tries < 20 then
        set_my_name_tries = set_my_name_tries + 1
        minetest.after(1, set_my_name)
    else
        log("warning", "could not determine name!")
    end
end

if minetest.register_on_connect then
    minetest.register_on_connect(set_my_name)
elseif minetest.register_on_mods_loaded then
    minetest.register_on_mods_loaded(set_my_name)
else
    minetest.after(1, set_my_name)
end

-- END initalization --
-- chat commands --

minetest.register_chatcommand("ch_toggle", {
    description = ("turn %s on/off for this server"):format(mod_name),
    func = safe(function()
        local current_status = toggle_disable_this_server()
        if current_status then
            current_status = "off"
        else
            current_status = "on"
        end
        minetest.display_chat_message(("%s is now %s for server "%s""):format(mod_name, current_status, server_id))
    end),
})


minetest.register_chatcommand("ch_statuses", {
    description = "list statuses",
    func = safe(function()
        for name, color in pairsByKeys(COLOR_BY_STATUS) do
            if name and color then
                minetest.display_chat_message(colorize(color, ("%s: %s"):format(name, color)))
            end
        end
    end),
})


minetest.register_chatcommand("ch_set", {
    params = "<name> <status>",
    description = "associate a name w/ a status",
    func = safe(function(param)
        local name, status = param:match("^(%S+)%s+(%S+)$")
        if name ~= nil then
            if not COLOR_BY_STATUS[status] then
                minetest.display_chat_message(colorize("#FF0000", ("unknown status \"%s\""):format(status)))
                return false
            end
            set_name_status(name, status)
            minetest.display_chat_message(colorize(COLOR_BY_STATUS[status], ("%s is now %s"):format(name, status)))
            return true
        else
            minetest.display_chat_message(colorize("#FF0000", "invalid syntax"))
            return false
        end
    end),
})


minetest.register_chatcommand("ch_unset", {
    params = "<name>",
    description = "unregister a name",
    func = safe(function(name)
        set_name_status(name, nil)
        minetest.display_chat_message(colorize(COLOR_BY_STATUS.server, ("unregistered %s"):format(name)))
    end),
})


minetest.register_chatcommand("ch_list", {
    description = "list all statuses",
    func = safe(function()
        for name, status in pairsByKeys(status_by_name, lc_cmp) do
            local color = COLOR_BY_STATUS[status] or COLOR_BY_STATUS.default
            minetest.display_chat_message(colorize(color, ("%s: %s"):format(name, status)))
        end
    end),
})


minetest.register_chatcommand("ch_alert_list", {
    description = "list all alert patterns",
    func = safe(function()
        for pattern, _ in pairsByKeys(alert_patterns, lc_cmp) do
            minetest.display_chat_message(colorize(COLOR_BY_STATUS.server, pattern))
        end
    end),
})


minetest.register_chatcommand("ch_alert_set", {
    params = "<pattern>",
    description = "alert on a given pattern",
    func = safe(function(pattern)
        add_alert_pattern(pattern)
    end),
})


minetest.register_chatcommand("ch_alert_unset", {
    params = "<pattern>",
    description = "no longer alert on a given pattern",
    func = safe(function(pattern)
        remove_alert_pattern(pattern)
    end),
})


-- END chat commands --

local function clean_android(msg)
    -- supposedly, android surrounds messages with (c@#ffffff)
    if msg:sub(1, 4) == "(c@#" then -- strip preceeding
        msg = msg:sub(msg:find(")") + 1, -1)
        if msg:sub(-11, -8) == "(c@#" then -- strip trailing
            msg = msg:sub(-11)
        end
    end
    return msg
end

local function clean_weird_crap(msg)
    -- client side translation stuff in 5.5?
    msg = msg:gsub("\27%(T@[^%)]+%)", "")
    msg = msg:gsub("\27.", "")

    return msg
end

local function get_color_by_name(name)
    local _
    name, _ = name:match("^([^@]+).*$")  -- strip @... from IRC users
    name, _ = name:match("^([^[]+).*$")  -- strip [m] from matrix users

    local status = get_name_status(name)
    return COLOR_BY_STATUS[status] or COLOR_BY_STATUS.default
end


local function color_name(name)
    local color = get_color_by_name(name)
    return colorize(color, name)
end


local function color_names(names, delim)
    local sorted_names = {}

    for name in names:gmatch("[%w_%-]+") do
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
            minetest.sound_play("default_dug_metal")
            return colorize(COLOR_BY_STATUS.self, text)
        end
    end

    local color = get_color_by_name(name)

    if color == COLOR_BY_STATUS.default then
        return colorize(COLOR_BY_STATUS.default, text)
    else
        color = lighten(color, LIGHTEN_TEXT_BY)
        return colorize(color, text)
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
        return ("%d days %02d:%02d:%02d"):format(time, h, m, s)
    elseif h ~= 0 then
        return ("%02d:%02d:%02d"):format(h, m, s)
    elseif m ~= 0 then
        return ("%02d:%02d"):format(m, s)
    else
        return ("%d seconds"):format(s)
    end
end

local function sort_privs(text)
    local sorted_privs = {}

    for priv in text:gmatch("[%w_%-]+") do
        table.insert(sorted_privs, priv)
    end

    table.sort(sorted_privs, lc_cmp)

    return table.concat(sorted_privs, ", ")
end

local t = {
    -- SORT PRIVILEGES
    {"^Privileges of ([^:]+): (.*)$", function(name, text)
        return ("%s%s%s%s"):format(
            color_text(name, "Privileges of "),
            color_name(name),
            color_text(name, ": "),
            color_text(name, sort_privs(text))
        )
    end},

    -- join/part messages
    {"^%*%*%* (%S+) (.*)$", function(name, text)
        return ("%s %s %s"):format(
            color_text(name, "***"),
            color_name(name),
            color_text(name, text)
        )
    end},

    -- yl discord messages
    {"^<([^|%s]+)|([^>%s]+)>%s+(.*)$", function(source, name, text)
        return ("%s%s%s%s%s %s"):format(
            color_text(name, "<"),
            color_text(name, source),
            color_text(name, "|"),
            color_name(name),
            color_text(name, ">"),
            color_text(name, text)
        )
    end},

    -- normal messages
    {"^<([^>%s]+)>%s+(.*)$", function(name, text)
        return ("%s%s%s %s"):format(
            color_text(name, "<"),
            color_name(name),
            color_text(name, ">"),
            color_text(name, text)
        )
    end},

    -- YL chatroom stuff
    -- {"^\[([^@]+}@([^\]]+)\] (.*)$", function(name, channel, text)
    --     return ("%s%s%s %s"):format(
    --         color_text(name, "["),
    --         color_name(name),
    --         color_text(name, "@"),
    --         color_name(channel),
    --         color_text(name, "]"),
    --         color_text(name, text)
    --     )
    -- end},

    -- YL announce
    {"^(%[[^%]]+%])%s(.*)$", function(t1, t2)
        return ("%s %s"):format(
            colorize(COLOR_BY_STATUS.server, t1),
            colorize(COLOR_BY_STATUS.server, t2)
        )
    end},

    -- prefixed messages
    {"^(%S+)%s+<([^>]+)>%s+(.*)$", function(prefix, name, text)
        return ("%s %s%s%s %s"):format(
            color_text(name, prefix),
            color_text(name, "<"),
            color_name(name),
            color_text(name, ">"),
            color_text(name, text)
        )
    end},

    -- Empire of Legends messages
    {"^<(%S+)%s+([^>]+)>%s+(.*)$", function(prefix, name, text)
        return ("%s%s %s%s %s"):format(
            color_text(name, "<"),
            color_text(name, prefix),
            color_name(name),
            color_text(name, ">"),
            color_text(name, text)
        )
    end},

    -- /me messages
    {"^%* (%S+) (.*)$", function(name, text)
        return ("%s %s %s"):format(
            color_text(name, "*"),
            color_name(name),
            color_text(name, text)
        )
    end},

    -- /msg messages
    {"^[DP]M from (%S+): (.*)$", function(name, text)
        minetest.sound_play("default_place_node_metal")
        return ("%s%s%s%s"):format(
            colorize(COLOR_BY_STATUS.server, "DM from "),
            color_name(name),
            colorize(COLOR_BY_STATUS.server, ": "),
            colorize(COLOR_BY_STATUS.self, text)
        )
    end},

    -- /tell messages
    {"^(%S+) whispers: (.*)$", function(name, text)
        minetest.sound_play("default_place_node_metal")
        return ("%s%s%s%s"):format(
            color_name(name),
            colorize(COLOR_BY_STATUS.server, " whispers: "),
            colorize(COLOR_BY_STATUS.self, text)
        )
    end},

    -- /who
    {"^Players in channel: (.*)$", function(names)
        return ("%s%s"):format(
            colorize(COLOR_BY_STATUS.server, "Players in channel: "),
            color_names(names, ", ")
        )
    end},

    -- /status
    {"^# Server: (.*) clients={([^}]*)}(.*)", function(text, names, lastbit)
        return ("%s%s%s%s%s%s"):format(
            colorize(COLOR_BY_STATUS.server, "# Server: "),
            colorize(COLOR_BY_STATUS.server, text),
            colorize(COLOR_BY_STATUS.server, " clients={"),
            color_names(names, ", "),
            colorize(COLOR_BY_STATUS.server, "}"),
            colorize(COLOR_BY_STATUS.server, lastbit)
        )
    end},

    -- /status on YL
    {"^# Server: (.*) clients: (.*)", function(text, names)
        return ("%s%s%s%s"):format(
            colorize(COLOR_BY_STATUS.server, "# Server: "),
            colorize(COLOR_BY_STATUS.server, text),
            colorize(COLOR_BY_STATUS.server, " clients: "),
            color_names(names, ", ")
        )
    end},

    -- IRC join messages
    {"^%-!%- ([%w_%-]+) joined (.*)$", function(name, rest)
        return ("%s%s%s%s"):format(
            color_text(name, "-!- "),
            color_name(name),
            color_text(name, " joined "),
            color_text(name, rest)
        )
    end},

    -- IRC part messages
    {"^%-!%- ([%w_%-]+) has quit (.*)$", function(name, rest)
        return ("%s%s%s%s"):format(
            color_text(name, "-!- "),
            color_name(name),
            color_text(name, " has quit "),
            color_text(name, rest)
        )
    end},

    -- IRC part messages
    {"^%-!%- ([%w_%-]+) has left (.*)$", function(name, rest)
        return ("%s%s%s%s"):format(
            color_text(name, "-!- "),
            color_name(name),
            color_text(name, " has left "),
            color_text(name, rest)
        )
    end},

    -- IRC mode messages
    {"^%-!%- mode/(.*)$", function(rest)
        return colorize(COLOR_BY_STATUS.default, ("^%-!%- mode/%s$"):format(rest))
    end},

    -- IRC /nick messages
    {"^%-!%- (.*) is now known as (.*)$", function(name1, name2)
        return ("%s%s%s%s"):format(
            color_text(name1, "-!- "),
            color_name(name1),
            color_text(name2, " is now know as "),
            color_name(name2)
        )
    end},

    -- DM sent
    {"^[DP]M to (%S+): (.*)$", function(name, text)
        return ("%s%s%s%s"):format(
            colorize(COLOR_BY_STATUS.server, "DM to "),
            color_name(name),
            colorize(COLOR_BY_STATUS.server, ": "),
            colorize(COLOR_BY_STATUS.server, text)
        )
    end},

    -- BlS moderator PM snooping
    {"^([%w_%-]+) to ([%w_%-]+): (.*)$", function(name1, name2, text)
        return ("%s%s%s%s%s"):format(
            color_name(name1),
            colorize(COLOR_BY_STATUS.server, " to "),
            color_name(name2),
            colorize(COLOR_BY_STATUS.server, ": "),
            colorize(COLOR_BY_STATUS.server, text)
        )
    end},

    -- BlS unverified player notice
    {"^Player ([%w_%-]+) is unverified%.$", function(name)
        minetest.sound_play("default_dug_metal")
        return colorize("#FF0000", ("Player %s is unverified."):format(name))
    end},

    -- BlS unverified player chat
    {"^%[unverified] <([^>]+)>%s+(.*)$", function(name, text)
        minetest.sound_play("default_dug_metal")
        return colorize("#FF0000", ("[unverified] <%s> (%s)$"):format(name, text))
    end},

    -- BlS cloaked chat
    {"^%-Cloaked%-%s+<([^>]+)>%s+(.*)$", function(name, text)
        return ("%s%s%s%s %s"):format(
            colorize(COLOR_BY_STATUS.server, "-Cloaked- "),
            color_text(name, "<"),
            color_name(name),
            color_text(name, ">"),
            color_text(name, text)
        )
    end},

    -- death messages
    {"^(%S+) was killed by (%S+), using (.+), near (.+)$", function(victim, killer, weapon, location)
        return ("%s%s%s%s%s%s%s"):format(
            color_name(victim),
            color_text(victim, " was killed by "),
            color_name(killer),
            color_text(killer, ", using "),
            color_text(killer, weapon),
            color_text(victim, ", near "),
            color_text(victim, location)
        )
    end},
    {"^(%S+) was killed by (.*)$", function(name, text)
        return ("%s%s%s"):format(
            color_name(name),
            color_text(name, " was killed by "),
            color_text(name, text)
        )
    end},
    {"^(%S+) should not play with ([^,]+), near ([^%.]+)%.", function(name, what, where)
        return ("%s%s%s%s%s%s"):format(
            color_name(name),
            color_text(name, " should not play with "),
            color_text(name, what),
            color_text(name, ", near "),
            color_text(name, where),
            color_text(name, ".")
        )
    end},
    {"^(%S+) shouldn't play with (.*)$", function(name, text)
        return ("%s%s%s"):format(
            color_name(name),
            color_text(name, " shouldn't play with "),
            color_text(name, text)
        )
    end},
    {"^(%S+) was killed near (.*)$", function(name, text)
        return ("%s%s%s"):format(
            color_name(name),
            color_text(name, " was killed near "),
            color_text(name, text)
        )
    end},
    {"^(%S+) has fallen near (.*)$", function(name, text)
        return ("%s%s%s"):format(
            color_name(name),
            color_text(name, " has fallen near "),
            color_text(name, text)
        )
    end},
    {"^(%S+) has drown in ([^,]+), near ([^%.]+)%.", function(name, what, where)
        return ("%s%s%s%s%s%s"):format(
            color_name(name),
            color_text(name, " has drown in "),
            color_text(name, what),
            color_text(name, ", near "),
            color_text(name, where),
            color_text(name, ".")
        )
    end},
    {"^(%S+) has drown in (.*)", function(name, what)
        return ("%s%s%s%s%s%s"):format(
            color_name(name),
            color_text(name, " has drown in "),
            color_text(name, what),
            color_text(name, ", near "),
            color_text(name, where),
            color_text(name, ".")
        )
    end},

    -- rollback_check messages
    {"%((%-?%d+,%-?%d+,%-?%d+)%) player:(%S+) (%S*) %-> (%S*) (%d+) seconds ago%.", function(pos, name, item1, item2, time)
        if item1 == "air" then
            item1 = colorize("#FF0000", item1)
        else
            item1 = colorize(COLOR_BY_STATUS.server, item1)
        end
        if item2 == "air" then
            item2 = colorize("#FF0000", item2)
        else
            item2 = colorize(COLOR_BY_STATUS.server, item2)
        end

        return ("(%s) player:%s %s -> %s %s ago."):format(
            colorize(COLOR_BY_STATUS.server, pos),
            color_name(name),
            item1,
            item2,
            seconds_to_interval(tonumber(time))
        )
    end},

    -- YL thankyous
    {"^Adventurer (%S+) received a 'Thank you' from (%S+)$", function(name1, name2)
        return ("%s%s%s%s"):format(
            colorize(COLOR_BY_STATUS.server, "Adventurer "),
            color_name(name1),
            colorize(COLOR_BY_STATUS.server, " received a 'Thank you' from "),
            color_name(name2)
        )
    end},

    -- YL levels
    {"^Congratulations, (%S+) reached L(%d+)$", function(name, level)
        return ("%s%s%s%s"):format(
            colorize(COLOR_BY_STATUS.server, "Congratulations "),
            color_name(name),
            colorize(COLOR_BY_STATUS.server, " reached L"),
            color_text(name, level)
        )
    end},
}

local last_message = ""

register_on_receive(safe(function(message)
    if disabled_servers[server_id] then
        return false
    end

    if message == last_message then
        return true
    else
        last_message = message
    end

    local msg = minetest.gettext(message)
    msg = minetest.strip_colors(msg)
    msg = clean_android(msg)
    msg = clean_weird_crap(msg)

    --log("action", "%q", msg)

    if should_ignore(msg) then
        return true
    end

    local date = get_date_string()

    for _, stuff in ipairs(t) do
        local key, fun = unpack(stuff)
        local parts = {msg:match(key)}
        if #parts > 0 then
            local fmsg = fun(unpack(parts))
            if fmsg then
                minetest.display_chat_message(("%s %s"):format(date, fmsg))
                return true
            end
        end
    end
end))
