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
- **Provider label**: movie, series and episode titles drop the provider's
  tag, year and country (`NF-DO - Show (2025) (GB)` → "Show"); the tag
  shows as-is (never translated) in a small label before the title: pill
  radius 4, `hover` bg, `textPrimary`, 11/700 (13 on page and hero titles),
  letter spacing ~0.08em. Hover or keyboard focus shows the provider's full
  name (in the player: in the hint line). Only tags that recur in the
  catalogue count, so titles like "CSI - Vegas" stay whole. Episode rows
  show "N. <the episode's own name>", else "N. Episode N".
- **Other sources** (movie and series details, below the details or the
  episodes): the other variants of the same title from the provider (same
  TMDB id, else title and year) as a row of normal posters with their
  label. The one played last has an accent history icon ("Last played");
  sources sharing a label show the provider's date ("Added 24 Apr 2026",
  series "Updated …"), also in the details' meta line. Left out when there
  are none.
- **Replay mark**: on channels whose provider keeps an archive (Xtream
  `tv_archive`), a history icon (outline, 16, `textSecondary`) right after
  the name in Live TV, search, the guide's channel column, the Channels
  panel and Home; tooltip "Replay: 3 days back" (in the player: the row's
  hint). Such a channel's name drops the provider's own mark: a last word
  of at most 4 characters without letters or digits, and a `◉` word
  anywhere.
- **REPLAY badge**: like the LIVE badge, but `hover` bg and `textPrimary`
  (the `live` colour stays LIVE's); before the player title while it
  plays from the archive.
- **Thumbnail** (continue watching, episodes): 16:9, radius 12.
- **LIVE badge**: `live` background, `onAccent` text, 10–12 px, 700,
  uppercase, radius 4–6.
- **Panels** (now/next info, settings groups): `surface` bg, radius 14,
  padding 20, dividers in `hover`.
- **TV guide**: programme cells `card`; programme on now `hover`; selected
  cell has an inset accent ring; a vertical accent line marks the current
  time; channel column stays fixed. The time row has a label every half
  hour; midnight shows the date ("Tue 27 Oct", bold, `textPrimary`) with a
  `textSecondary` line instead of a divider. A label that would run into
  another is left out (its line stays), dates first. Its toolbar, left to
  right: the category dropdown, the toolbar chips "Now" and "Tonight"
  (never accent: they jump, they don't filter), then "Updated …" (cut
  short first when space runs out) and ⟳. The top-left corner of the grid shows the date at
  the left edge. "Now" puts the current time 30 min from the left edge, as
  when the guide opens; "Tonight" puts 20:00 there (19:30 in view), from
  23:00 on 20:00 tomorrow. "Tonight" is disabled while fewer than half of
  the guide's channels have programmes past that time ("No TV guide for
  tomorrow evening yet").
- **Replay in the TV guide**: on channels with an archive the guide
  reaches back over it (at most 7 days). Programmes that can be replayed
  (started, inside the archive) show the history icon (14) before their
  time and "· Replay available" in the tooltip; ended ones that can't are
  muted (title `textMuted`). Where the XMLTV guide stops, the visible
  rows' past programmes come from the provider's archive listing, one
  channel at a time, nearest the middle first; meanwhile the row says
  "Loading past programmes…" (or "Couldn't load past programmes",
  tried again after 5 min).
- **Programme panel**: a click, Enter, right click, long press or the Menu
  key on a programme opens a panel (`surface`, radius 14, padding 20):
  title (panel title), "Channel · Mon 26 Oct 20:00–21:00", category,
  description, then "Play" (primary, focused) and "Close" for a replayable
  past programme; "Watch live" (primary) and "Play from start" while it is
  on; otherwise a line why not ("No replay: this channel has no archive",
  "No replay: older than 3 days", "No replay: not in the provider's
  archive", "Not started yet") and "Close". On now without an archive a
  click plays live at once. Esc closes it.
- **Player overlay**: `scrim` background, controls in `textPrimary`, accent
  progress fill, secondary pills for Subtitles / Audio.
- **Player controls bar**, left to right: the primary action (play/pause for
  movies, episodes and replays; on live TV pause on channels with an
  archive, else nothing; Record (group 9) follows it), the seek bar with
  position and end time (on live TV nothing, or "Paused · Behind live
  0:45" while paused; in a replay clock times, see Replay player), the
  "LIVE" button in a replay or while live TV is paused,
  mute button + volume slider (0–100 %, about 120 wide), the Channels and
  favourite pills (live TV), the Subtitles pill, fullscreen, stop, and the
  clock (HH:MM, `textSecondary`). The end time switches between the
  duration and the time left ("-12:34") on double click or Enter. Below
  the controls, part of the bar, is the hint line (see Player hints).
- **Player hints** (standing rule): every control in the player has a
  tooltip that says what it does and names its shortcut key, if it has
  one ("Mute (m)"); generic keys (Enter/Space on a focused control) aren't
  named. Tooltips are never drawn over the embedded video, which Flutter
  can't draw over: the tooltips of the bar (and the back arrow) show in
  the hint line, a strip of the bar below the controls, as a `card` pill
  (radius 6, 13, `textPrimary`) under the control, kept inside the bar,
  on hover and on keyboard focus. Its height (scaled with the text) is
  always kept, so the video never changes size. Windowed, the tooltips of
  the side panels and the next-episode card stay inside the panel column;
  in fullscreen they use the hint line too, which mpv shows with the bar
  and which hides with it.
- **Player layout**: windowed, the video keeps its area; the controls bar
  (with its hint line) and now/next (live TV: titles plus the short descriptions, two lines for
  now, one for next where it fits) sit below it and panels beside it. The
  video area is never resized for transient UI. In fullscreen the video
  fills the screen and the controls, panels and the next-episode card are
  drawn over it by mpv (the same widgets, mirrored as images): the bar is
  `scrim` at 85 % across the bottom, a panel takes the right edge. They
  show on mouse movement or a key and hide after 3 s (with the cursor),
  but stay while a panel is open, a control has keyboard focus or a slider
  is dragged.
- **Replay player**: the seek bar's position is the clock time playing
  ("20:41:12") and its end the programme's ("21:00"); while the programme
  is still on it reaches from two hours back (or the programme's start)
  up to now, with "Behind live 12 min" (`textSecondary`) after it.
  Now/next and the title follow the playing position and run on into the
  next programme. Seeking stays in the loaded archive when it can, else
  loads it from there (a short progress bar in place of the slider);
  close to now it goes live. At the end of what was loaded it loads on
  without an error, or goes live within 10 s of live. Pausing live TV
  keeps the picture, closes the stream and resumes from the archive 15 s
  before the pause. Replays don't go into Continue watching.
- **Mouse on the video**: click = play/pause (live TV: pause on channels
  with an archive, else show the controls),
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
- **Context menu**: channels, movies, series and episodes open one on right click,
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
- **Settings › Playlist** (right after Provider): a row per part
  (Channels, Movies, Series, TV guide) with when it was last updated, in
  local time ("Updated Today 12:40 · 4,512 channels", "Yesterday 21:05",
  "Mon 20 Oct 14:05"), "Updating…" with a small spinner or "Waiting…"
  during a refresh, and after a failure the reason in plain words ("The
  provider's server had a problem (HTTP 502).", never a URL or account),
  "The previous list is kept." and the last successful update, with an
  error icon. Parts the provider lacks say "Not available for this
  provider". Then "Automatic refresh" (dropdown), "No longer listed by the
  provider" when some of my items are gone (counts; favourites open a list
  of names), and the primary button "Refresh all" ("Refreshing 2 of 4…"
  and disabled while it runs). The ⟳ buttons of Live TV, TV Guide, Movies
  and Series refresh their part the same way and update the same times.
- **Automatic refresh notice**: a failed automatic refresh only shows a
  snack bar "Couldn't refresh movies. The previous data is kept." with
  "Details" (opens Settings); like every snack bar with an action it closes
  by itself after 6 s and when another page opens. Never a dialog, and
  nothing while something plays. The parts failing in one run share one
  snack bar ("channels, movies and the TV guide"); each part is reported
  at most once while the app is open, whatever failed before it started
  or by hand.
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
| Playlist | The provider's channels, movies, series and TV guide, as downloaded |
| Refresh all | Downloads every part of the playlist again, one after another |
| Automatic refresh | The setting: Off, On app start, Every 6 hours, Daily (default) |
| Provider label | The provider's own tag of a title (`NF`, `4K-SC`), shown as-is |
| Other sources | The other variants of the same movie or series in the provider's catalogue |
| Last played | The source of a title that was played most recently |
| Now (TV guide) | Goes back to the current time |
| Replay | Playing a past (or running) programme from the provider's archive (catch-up) |
| Play / Play from start | Replays a past programme / the one on now from its start |
| Watch live | Plays the channel live from the programme panel |
| Go live (LIVE) | Leaves a replay or a pause for the live stream |
| Behind live | How far a replay or pause is behind the live stream |
| Paused (live TV) | Live TV paused on a channel with an archive; resumes from the archive |
| Tonight (TV guide) | Goes to 20:00 this evening, from 23:00 on tomorrow evening; disabled while the TV guide doesn't reach that far |

- The heading above a list or grid names the selected category ("All
  movies", one of my categories or a category).
- "Continue watching" lists started items, most recently watched first.
  Under "All movies"/"All series" it shows all of them except those in
  hidden categories; under a provider category only those in that
  category. Under one of my categories it shows all of them except those
  in hidden categories, with the ones in the selected category first. With
  none, the row and its heading are left out.
- A movie or series and its other sources count as one: watched when
  watched in any of them, resumed from the newest position ("Resume from
  12:34 (from NF)" when that was another source), marked watched or
  unwatched together (episodes matched by season and episode number), and
  shown once in "Continue watching" (the source watched last).
- "Remove from Continue watching" (context menu of its cards on Home, the
  Continue watching page and in Movies/Series) clears a movie's resume
  position; a series leaves the list but its episodes keep their watched
  marks, and it comes back when an episode is played or marked again.
  No confirmation: a snack bar "Removed “<name>” from Continue watching"
  offers "Undo" for 6 s; it also closes when another page opens.
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
- Player tooltips name their keys: "Pause (Space or click the video)",
  "Pause live TV (Space or click the video)", "Play the next episode
  (n)", "Seek (← / →: 10 s, with Shift: 1 min)", "Go live: watch
  <channel> live (l)", "Mute (m)", "Volume
  (↑ / ↓, or the mouse wheel on the video)", "Channels: switch channel
  (c)", "Subtitles and audio (s: next subtitles)", "Fullscreen (f or
  double-click, Esc to leave)", "Close (Esc)", "Cancel and play to the
  end (Esc)". Stop and the back arrow: "Stop and go back", "Back (stops
  playback)". Keys: Space pause, ←/→ seek 10 s (Shift: 1 min), ↑/↓
  volume, f fullscreen, Esc (cancel the countdown, close a panel, leave
  fullscreen), s subtitles, m mute, c channels, n next episode, l go live.
- Episodes with a next one get a "Next episode (n)" button after
  play/pause; it marks the current episode watched and plays the next.
- "Automatic refresh" (Settings › Playlist, kept per provider): Off, On
  app start, Every 6 hours, Daily (default). It runs only while the app is
  open (checked every 15 min, and at start when the time has passed),
  waits while something plays, and after a failure tries again an hour
  later at the earliest. Off still downloads a part that has never been
  downloaded.
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
