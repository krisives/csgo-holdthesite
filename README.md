
# Hold the Site!

Hold the Site (HTS) is a sourcemod plugin for CSGO servers where players take
turn holding bomb sites. Intended for casual play the plugin keeps track of
who can hold the site the longest, kills, etc.

## Install

* Copy `holdthesite.smx` into your `plugins/` directory

* Copy the `maps/*.hts.cfg` files into your `maps/` directory

## Commands

* `hts_help` will show you a plugin-specific help (but basically what you are reading right now)

* `hts_site` adds or updates a site. It's used like `hts_site a 3000` where "a" is the name of the
   site and 3000 is the distance that players not allowed to enter the site yet must stay away.

* `hts_addspawn` adds a spawn point to a bomb site. It's used like `hts_addspawn a` where "a" is
   the name of the bomb site. This is where players who are not holding the site will spawn.

* `hts_clear` removes a bomb site or all bomb sites. Use `hts_clear *` to remove all. Use `hts_clear a` to
   remove the bombsite "a".

* `hts_save` and `hts_load` simply save and reload the `.hts.cfg` file for the current map. This
   automatically happens when the map is changed, but can be useful while testing or if you make
   a mistake.

* `hts_next` selects a new player to hold the site and starts a new round.

