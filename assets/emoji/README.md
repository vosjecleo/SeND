# SeND emoji names and aliases

Applies to 0.9.34+106. This is the bundled Unicode catalogue; imported custom
emoji names belong to their packs and can be edited through pack management.
See [current documentation](../../docs/README.md).

Edit `aliases.json` to change the canonical `:name:` or add aliases without
modifying the upstream emoji catalogue in `emojis.json`.

Each top-level key is the emoji itself. `name` replaces its displayed/searchable
description; `primary_alias` sets the displayed colon shortcode, and every item
in `aliases` becomes an accepted colon completion. An
optional `category` can be one of:

`smileysAndPeople`, `animalsAndNature`, `foodAndDrink`, `travelAndPlaces`,
`activities`, `objects`, `symbols`, or `flags`.

New emoji can also be added in this file by supplying all three fields. JSON
requires double quotes and does not support comments. Rebuild/restart the app
after editing because the file is bundled into the application.

`shortcodes.json` provides default, familiar Discord-style colon names from
iamcal/emoji-data revision `13ee711e222ea17fe537bfea953c687866f16411` (MIT;
`SHORTCODES-LICENSE.txt`). These are not an official Discord registry. Primary
shortcodes take precedence over broad search keywords; older catalogue keywords
and aliases are retained. SeND additionally accepts `sobbing` for `sob`.
