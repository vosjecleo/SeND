# JSON themes (schema 1)

In Appearance, choose **Try Aero Glass** or **Import JSON theme**. Choosing a
built-in appearance clears the custom theme. Theme documents and their chosen
settings follow the existing appearance-sync preference; disabling sync keeps
them device-local. Copy JSON exports the current settings as theme defaults.

See [the bundled Aero example](../assets/themes/aero.json) for a complete theme.

```json
{
  "schema": 1,
  "id": "example.ocean",
  "name": "Ocean",
  "extends": "dark",
  "settings": [
    {"id": "accent", "label": "Accent", "type": "color", "default": "#8ACFFF"}
  ],
  "tokens": {"accent.primary": {"setting": "accent"}}
}
```

## Inheritance and values

`extends` accepts a built-in parent: `light`, `gray` (`regular` is an alias),
`dark`, or `night`. Missing/new tokens inherit that parent's defaults. Imported
themes do not depend on other imported files. Unknown tokens are ignored.
`variants` may contain named objects with `extends` and `tokens`; the choice
setting named `variant` selects one. Variant tokens override root tokens.

Colours use `#RRGGBB` or `#AARRGGBB`. Values may reference a setting with
`{"setting":"accent"}`, another token with `{"ref":"accent.primary"}`,
or mix colours using `{"mix":["#000000","#FFFFFF"],"amount":0.2}`.
Invalid values and cyclic references fall back safely. Core text and surface
colours remain opaque; glass opacity applies only to decorative panel surfaces.

Settings support `color`, `number` (with finite `min`/`max`), `boolean`, and
`choice` (with `choices`). Controls are generated from their labels and types.

## Semantic tokens

- Surfaces: `surface.background`, `surface.rail`, `surface.panel`,
  `surface.content`, `surface.raised`, `surface.input`, `surface.island`,
  `surface.hover`.
- Content/boundaries: `text.primary`, `text.secondary`, `border.subtle`,
  `accent.primary`, `accent.secondary`, `selection.fill`, `selection.border`.
- Decoration: `glass.opacity` (0.65–1), `glass.blur` (0–8),
  `glass.gloss` (0–0.3), `glass.glow` (0–0.15), `shape.cardRadius` (4–18).

## Component surface styles

Optional `surfaces` entries `header`, `island`, `button` and `popup` style panel
headers, composer/user islands, the profile footer button and expression picker
respectively. Variant surface entries replace the corresponding root entry.
Other controls retain standard Material interaction/disabled/focus behaviour.

Each entry accepts `gradient` (up to eight colours), `direction` (`vertical` or
`horizontal`), `border`, `highlight`, `hover`, `radius` (4–18), `opacity`
(0.55–1), `blur` (0–8), `shadow` (0–0.35), `texture` (0–0.08), `gloss` (0–0.3)
and `transitionMs` (0–180). Colour/number values accept the same setting/ref/mix
references as tokens. Texture uses bounded, static diagonal strokes; gloss is
a static upper-surface reflection. There are no continuously animated effects.

`avatar.shape` accepts `circle` (default) or `glass-square`. The latter uses
rounded-square main timeline/navigation/profile avatars with a static reflection.
High contrast restores the stock treatment.

`icons.pack` selects `Material` (default) or the bundled public-domain `Tango`.
Themes can add a root `icons` object mapping semantic roles to
`data:image/png;base64,...` strings. Supported roles: `home`, `search`, `inbox`,
`add`, `settings`, `microphone`, `emoji`, `gifs`, `stickers`, `camera`, `files`,
`send`, `mute`, `audio`, `servers`, `pause`, `stop`. These cover the main
navigation, composer, expression picker and pack-management controls; unrelated
icons retain their stock glyphs. Each PNG must be static, at most 8 KiB and
128×128 pixels. The complete document still has the 64 KiB limit. No remote URLs,
filesystem paths, SVGs or executable fonts are accepted. Invalid/missing icons
fall back safely. Embedded data travels with the existing appearance sync.

`icons.style` selects `Outline` or `Classic`. Classic uses filled expression-tab
icons and embossed inherited icon shadows, not a downloaded icon pack. Existing
functional icons remain recognisable; arbitrary SVG/icon imports are not enabled.

Glass is scoped to these surfaces, not message rows or the scrolling timeline.
High contrast disables transparency, blur, gloss and glow. Reduced motion also
disables blur. Existing user profile colours are independent of theme accents.

## Safety and future compatibility

Documents are limited to 64 KiB, nesting to 16 levels, settings to 20 and choice
options to 12. Expression resolution has a bounded budget. Files contain only
data: no executable expressions, Lua, URLs, fonts or external asset loading.
Malformed imports preserve the current appearance; invalid saved themes fall
back to built-in appearance. The schema version and ignored extension metadata
leave room for a separately permissioned extension system later; no such runtime
is enabled by this format.
