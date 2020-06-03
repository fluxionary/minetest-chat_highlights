minetest CSM which makes busy public chat easier to parse by coloring certain things.

requirements
------------

tested with minetest 0.4.17 and 5.0 through through 5.3-dev-ee831ed6e.

only basic CSM need be enabled on the 5.0+ server, which is the default.

installation
------------

make sure the mod is installed at `~/.minetest/clientmods/chat_highlights`

make sure `~/.minetest/clientmods/mods.conf` exists and contains:

```config
load_mod_chat_highlights = true
```

usage
-----

* .ch_toggle: turns chat highlighting on/off for the current server (defaults to on)
* .ch_statuses: lists the available statuses
* .ch_set PLAYERNAME STATUS: set the status of `PLAYER`
* .ch_list: lists the status of all players
* .ch_unset PLAYER: unset the status of `PLAYER`
* .ch_alert_list: list all alert patterns
* .ch_alert_set PATTERN: set an pattern to alert on
* .ch_alert_unset PATTERN: unset a pattern to alert on
