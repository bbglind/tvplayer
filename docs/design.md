# tvplayer design guide

The visual rules for the app. Source: the "App sections" mockups (Start page,
Live TV, TV Guide, Movies, Series, Series detail, Player, Downloads).
All UI work should follow this file. If a screen needs something not covered
here, pick the closest existing token and mention it, rather than inventing
new colours.

## Look in one sentence

A warm, dark, calm living-room look: soft brown-grey surfaces, cream text,
and one gold accent used for focus, selection, progress and the main action.

## Colour tokens

| Token          | Hex       | Use |
|----------------|-----------|-----|
| background     | `#262423` | App background |
| surface        | `#393533` | Sidebar, panels, search field, inactive chips |
| card           | `#44403D` | Cards, list rows, poster placeholders |
| hover          | `#524C48` | Hover, selected row, active nav item, secondary buttons, progress track, dividers |
| scrim          | `#1A1918` | Video area / player background, overlays (use with opacity for gradients) |
| textPrimary    | `#EEE9E1` | Main text and icons |
| textSecondary  | `#C3BCB3` | Secondary text, inactive nav items, descriptions |
| textMuted      | `#ADA69D` | Labels, meta lines (year, genre, "until 21:00") |
| textDisabled   | `#85807A` | Placeholders, disabled, inactive pager dots |
| accent         | `#D4AE6A` | Focus ring, active marker, primary button, progress fill, selected chip, favourite star |
| accentHover    | `#DEBE84` | Hover / pressed state of accent elements and links |
| onAccent       | `#262423` | Text/icons on accent (and on live/success badges) |
| live           | `#D8735F` | LIVE badge, recording indicator |
| success        | `#9DB48A` | Downloaded, recorded, OK |

Accent is the only bright colour. Do not use it for large areas apart from
the primary button and selected chip.

## Typography

Font: **Figtree** (bundled with the app, not loaded from the network),
weights 400, 500, 600, 700.

| Role            | Size | Weight |
|-----------------|------|--------|
| Page title (h1) | 30   | 700    |
| Hero title      | 40   | 700    |
| Section title   | 20   | 600    |
| Panel title     | 22   | 700    |
| Body            | 15   | 400/500|
| Card title      | 14–15| 600    |
| Meta / small    | 13   | 400    |
| Overline label  | 13   | 600, uppercase, letter spacing ~0.1em, textMuted |
| Badge           | 10–12| 700, letter spacing ~0.08em |

## Shape and spacing

- Corner radius: 10 (buttons, nav items, small tiles), 12 (cards, rows,
  posters), 14–16 (large panels, hero), pill (999) for chips and search field.
- Spacing scale: 4, 6, 8, 10, 12, 16, 20, 24, 28, 40.
- Page padding: 28 top, 40 sides.
- Gap between sections: ~36–40. Gap inside a section (title → content): 16.
- Minimum touch/click target: 44 px high (buttons 44–48, nav items 44,
  chips 40).
- No shadows, no gradients except the dark bottom fade on hero/backdrop
  images.

## Layout

- **Left sidebar**, width ~220–240, background `surface`, padding 24/16.
  - Top: app mark (32×32, radius 8, accent fill) + app name (19, 700).
  - Items: icon (20, outline/stroke style) + label (15), height 44,
    radius 10, gap 12.
  - Active item: background `hover`, text `textPrimary`, weight 600, plus a
    3 px accent bar on the left edge (inside the item).
  - Inactive item: text `textSecondary`, weight 500.
  - Settings sits at the bottom, pushed down.
  - Order (when the sections exist): Home, Live TV, TV Guide, Movies,
    Series, Downloads, … Settings at the bottom.
- **Main area**: page title row (title left, search field right), then
  sections stacked vertically.

## Components

- **Focus / selection ring**: 2–3 px accent ring (outside for posters and
  cards, inside for list rows and guide cells). Must be visible for keyboard
  focus everywhere — the app must be usable with keyboard alone.
- **Primary button**: accent background, `onAccent` text, 600, radius 10.
- **Secondary button**: `hover` background, `textPrimary` text, 500.
- **Chip** (category filter): height 40, pill. Selected: accent bg,
  `onAccent` text, 600. Unselected: `surface` bg, `textSecondary` text.
- **Scrollbar**: thin pill, `accent` thumb (`accentHover` while hovered or
  dragged); where a track is shown it is `surface`, with no border.
- **Search field**: pill, `surface` bg, height 44, search icon in
  `textMuted`, placeholder in `textMuted`.
- **Channel row**: `card` bg, radius 12, padding ~10/14: channel number
  (13, 600, textMuted) · logo tile 44×44 (radius 10, `background` bg) · name
  (15, 600) + "Programme · until HH:MM" (13, textSecondary) + 3 px progress
  bar · optional favourite star (accent). Selected row: `hover` bg + accent
  ring.
- **Progress bar**: track `hover`, fill accent, height 3–6, rounded.
  On a thumbnail: 4 px at the bottom edge over a dark translucent track.
- **Poster**: 2:3, radius 12, placeholder `card`. Badges top-left
  ("New episode": accent bg; LIVE: live bg; both with `onAccent` text).
  Watched/downloaded marker: small ✓ badge in success colour.
- **Thumbnail** (continue watching, episodes): 16:9, radius 12.
- **LIVE badge**: `live` background, `onAccent` text, 10–12 px, 700,
  uppercase, radius 4–6.
- **Panels** (now/next info, settings groups): `surface` bg, radius 14,
  padding 20, dividers in `hover`.
- **TV guide**: programme cells `card`; programme on now `hover`; selected
  cell has an inset accent ring; a vertical accent line marks the current
  time; channel column stays fixed.
- **Player overlay**: `scrim` background, controls in `textPrimary`, accent
  progress fill, secondary pills for Subtitles / Audio.

## Icons

Material outlined (stroke) icons, size 20 in navigation, 18 in fields.
No emoji in the UI.

## Accessibility

- Text contrast at least 4.5:1 (the tokens above are chosen for this on
  `background`/`surface`; don't put `textMuted` on `hover` for small text).
- Never rely on colour alone (LIVE also says "LIVE", downloaded also has ✓).
- Everything reachable and operable by keyboard; visible focus ring.
