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
  - Order (when the sections exist): Home, Search, Live TV, TV Guide,
    Movies, Series, Downloads, … Settings at the bottom. The app opens on
    Home.
- **Main area**: page title row (title left, search field right, then
  page actions such as reload), then sections stacked vertically. On
  pages with a category list the title row spans the full width above the
  list and the content. The TV Guide keeps its own toolbar.

## Components

- **Focus / selection ring**: 2–3 px accent ring (outside for posters and
  cards, inside for list rows and guide cells). Must be visible for keyboard
  focus everywhere — the app must be usable with keyboard alone.
- **Primary button**: accent background, `onAccent` text, 600, radius 10.
- **Secondary button**: `hover` background, `textPrimary` text, 500.
- **Chip** (category filter): height 40, pill. Selected: accent bg,
  `onAccent` text, 600. Unselected: `surface` bg, `textSecondary` text.
- **Toolbar chip** (sort, filters, search scope): a chip with a leading
  icon and, when it opens a menu, a dropdown arrow. Accent while a filter
  is active. Above the grid: sort, year, genre (Series), "Only in …"
  while searching, the result count (13, textMuted) and "Reset filters"
  while a filter is active.
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
- **Player controls bar**, left to right: the primary action (play/pause for
  movies and episodes; on live TV, which can't pause, the slot is kept for
  Record), the seek bar with position and end time (or nothing on live TV),
  mute button + volume slider (0–100 %, about 120 wide), the Channels and
  favourite pills (live TV), the Subtitles pill, fullscreen, stop, and the
  clock (HH:MM, `textSecondary`). The end time switches between the
  duration and the time left ("-12:34") on double click or Enter.
- **Player layout**: windowed, the video keeps its area; the controls bar
  and now/next (live TV: titles plus the short descriptions, two lines for
  now, one for next where it fits) sit below it and panels beside it. The
  video area is never resized for transient UI. In fullscreen the video
  fills the screen and the controls, panels and the next-episode card are
  drawn over it by mpv (the same widgets, mirrored as images): the bar is
  `scrim` at 85 % across the bottom, a panel takes the right edge. They
  show on mouse movement or a key and hide after 3 s (with the cursor),
  but stay while a panel is open, a control has keyboard focus or a slider
  is dragged.
- **Mouse on the video**: click = play/pause (live TV: show the controls),
  double click = fullscreen (the click doesn't also fire), wheel = volume.
- **Channels panel** (zap, `c`): side panel 360 wide, my Live TV
  categories as toolbar chips, then compact channel rows (logo, name, the
  programme on now with progress); the current channel is the selected row
  and has focus. A click or Enter switches channel in the player and closes
  the panel. Without my Live TV categories it shows a hint about the star.
- **Next episode card**: `surface` panel 360 wide, "Next episode in N s"
  (card title), the episode code and title (`textSecondary`), primary
  button "Play now" (focused) and secondary "Cancel" (also Esc). Windowed it
  sits beside the video, in fullscreen at the bottom right over it.
- **Favourite star**: filled accent star when the item is in at least one of
  my categories; otherwise an outline star that shows only on hover or
  focus. At the right end of channel rows; at the top left of posters, on a
  translucent `scrim` tile.
- **Context menu**: channels, movies and series open one on right click,
  long press (touch) and Menu key / Shift+F10. Menus and dialogs can't be
  drawn over the embedded mpv video: next to it, use a side panel (like the
  track panel) instead.
- **Start page (Home)**: header with the greeting ("Good morning /
  afternoon / evening") left and a search field right that opens the
  Search page with what was typed. Then rows, each with a section title
  (20/600) and a horizontally scrolling list (vertical wheel scrolls the
  page; Shift+wheel, touchpad, hover arrows and the keyboard scroll the
  row): the Featured banner (backdrop with the bottom fade, or the poster
  at the left on `card`; hero title, meta line, two lines of plot, Play
  and More info, page dots; rotates every 8 s unless hovered or focused,
  Left/Right page), recently viewed channel cards, my-category tiles
  (icon, type overline, name, count), Continue watching thumbnails and
  Recently added posters, the last two with "See all". Rows still loading show `card`
  placeholders; empty rows are left out.
- **My categories**: in category lists above the provider categories, with
  their icon (outline, 18), name and count; an edit mode reorders them and
  hides provider categories (eye toggle, hidden ones dimmed).

## Naming

Use these terms in the UI, tooltips and Settings. The UI language is
English for now.

| Term | Meaning |
|------|---------|
| My categories | The user's own favourite categories |
| Categories | The provider's categories |
| All channels / All movies / All series | Everything except hidden categories |
| Favourite (star) | The item is in at least one of my categories |
| Continue watching | Started movies and episodes |
| Remove from Continue watching | Takes a started item out of Continue watching |
| Hidden | Hidden provider categories |
| Featured | The banner at the top of Home |
| Recently viewed channels | The last live channels played (up to 20) |
| Recently added series / movies | Newest series (by last update) / movies (by date added) |
| Edit home | The mode that moves and hides Home rows |
| Channels | The player's zap panel of my Live TV categories |
| Play next episode | The setting and countdown that start the next episode |

- The heading above a list or grid names the selected category ("All
  movies", one of my categories or a category).
- "Continue watching" lists started items, most recently watched first.
  Under "All movies"/"All series" it shows all of them except those in
  hidden categories; under a provider category only those in that
  category. Under one of my categories it shows all of them except those
  in hidden categories, with the ones in the selected category first. With
  none, the row and its heading are left out.
- "Remove from Continue watching" (context menu of its cards on Home, the
  Continue watching page and in Movies/Series) clears a movie's resume
  position; a series leaves the list but its episodes keep their watched
  marks, and it comes back when an episode is played or marked again.
  No confirmation: a snack bar "Removed “<name>” from Continue watching"
  offers "Undo" for 5 s.
- The favourites menu saves each checkbox at once; "Done", Esc or a click
  outside closes it. The genre menu works the same way.
- The search field of Live TV, Movies and Series searches the whole
  section (except hidden categories); "Only in <category>" limits it to
  the selected category.
- Sort: "Recently added" (Series: "Recently updated"), "A–Z", "Top rated".
  Year filter: "This year", "Last 2 years", "Last 5 years", "Custom
  range…". "Reset filters" clears year and genre.
- Home: "Continue watching" mixes movies and episodes, most recently
  watched first, without hidden categories; Enter or a click resumes
  playback, the context menu has "Open details", "Remove from Continue
  watching" and "Add to favourites…". Its card says what is left: "S2 ·
  E4 · 18 min left", "1 h 02 min left". Its "See all" opens the Continue
  watching page (not in the sidebar; back arrow): the same 16:9 cards in a
  grid, most recently watched first, with chips "All", "Movies",
  "Series". Recently viewed
  channels say "Watched 1 h ago" and the programme on now; their context
  menu has "Remove from recently viewed". "See all" of Recently added
  opens Movies/Series with "All" and "Recently added". With no categories of mine, the row
  shows a hint about the star.
- Search page groups: "Live TV", "Movies", "Series", each with its count
  and "Show all".
- Player tooltips name their keys: "Channels (c)", "Mute (m)",
  "Subtitles and audio (s: next subtitles)", "Fullscreen (f or
  double-click, Esc to leave)". Keys: Space pause, ←/→ seek 10 s, ↑/↓
  volume, f fullscreen, Esc (cancel the countdown, close a panel, leave
  fullscreen), s subtitles, m mute, c channels.
- "Play next episode" (Settings › Player): Off, 15, 20, 30 (default), 45,
  60, 90 or 120 s before the end. The card reads "Next episode in 12 s";
  after a season finale it is the next season's first episode, after the
  last episode there is none. "Cancel" plays to the end, which shows
  "Episode finished" with "Play next episode".

## Icons

Material outlined (stroke) icons, size 20 in navigation, 18 in fields.
No emoji in the UI.

## Accessibility

- Text contrast at least 4.5:1 (the tokens above are chosen for this on
  `background`/`surface`; don't put `textMuted` on `hover` for small text).
- Never rely on colour alone (LIVE also says "LIVE", downloaded also has ✓).
- Everything reachable and operable by keyboard; visible focus ring.
