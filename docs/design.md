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
| live           | `#D8735F` | LIVE badge, recording indicator, error and warning messages |
| success        | `#9DB48A` | Downloaded, recorded, OK, success messages |

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
- No shadows, no gradients except the fades on hero/backdrop images (the
  dark bottom fade, and on detail pages the fades into `background`, see
  Detail backdrop).

## Layout

- **Left sidebar** (not on phones, see Phone layout), width ~220–240,
  background `surface`, padding 24/16.
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

## Phone layout (compact width)

Below **600** wide (a phone in portrait) the app switches layout by the
window width, never by platform, so desktop windows keep the layout above
(a desktop window made that narrow gets the phone layout too). The aim is
clean and simple over every desktop feature.

- **Bottom bar** (`NavigationBar`, `surface`, `hover` indicator,
  selected `textPrimary` 600, others `textSecondary`): Home, Live TV,
  Movies, Series, More. **More** is a page of 56-high rows: TV Guide,
  Downloads, Settings. No sidebar, no side menu. Pages without a tab
  (TV Guide, Downloads, Settings, Search) get a back arrow before the
  title; Android Back does the same, then goes to Home, then leaves.
  The TV Guide also opens from a guide button in Live TV's header.
- **Page header**: page padding 16; back arrow, title (24/700, takes the
  remaining width, one line), icon actions, then the **magnifier**
  ("Search") that opens the Search page. Inline search fields are left
  out (the Search page keeps its own, full width under the title).
  Outlined header buttons become icon buttons with a tooltip.
- **Categories**: a full-width button (48 high, `surface`, radius 10:
  category icon, the selected category's name, dropdown arrow) above the
  content, which takes the full width. It opens a bottom sheet (`surface`,
  top radius 16, drag handle, 85 % of the height): "Categories" with the
  edit button, then the same list as the column (my categories, All …,
  provider categories with counts). A choice closes it (not in edit mode).
- **Posters**: 2–3 columns (about 130 wide each), 2:3 posters; each cell
  is as tall as the poster plus two title lines and the subtitle at the
  current text scale, so labels are never cut.
- **Details** (movie, series): stacked: the backdrop edge to edge (16:9,
  no radius, no side padding) under the transparent app bar, fading into
  `background` at the bottom, with the watched progress along its bottom
  edge; or, without one, the poster centred (at most 180 wide); then
  title, meta line, buttons (wrapping), plot, Cast, Recommendations and
  Other sources.
- **Featured banner**: 16 padding, title 26/700, as tall as its content
  or ¾ of its width; without a backdrop the poster fills it with the fade.
- **TV guide**: channel column 84 wide (scaled with the text): number
  (`textMuted`, 600) over the name (13/600, one line), not resizable. The
  category dropdown gets its own row; "Now", "Tonight" and "Updated …"
  wrap beside ⟳.
- **Settings rows**: a row's dropdown or buttons go **below** its title
  and description (dropdowns as wide as the row); icons, switches and
  spinners stay at the end.
- **Touch**: tap targets at least 48 (toolbar chips get a padded target,
  category rows are 48 high). Nothing works by hover or drag only: resize
  handles aren't built, and long press opens the context menus.
- **Text scale**: every page must fit from 1.0 up to Android's largest
  font size (2.0) without clipping: no fixed heights for text.
- **Orientation**: phones (shortest side below 600) stay in portrait
  outside the player and after leaving it; tablets turn with the device.

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
- **Messages (snack bars)**: floating, `card` bg, radius 10, text
  `textPrimary` (never coloured), action (e.g. "Undo", "Details", "Show")
  in `accent`. Each has a type, shown by a 4 px pill bar at the start and
  a 20 px icon in the type's colour (icon shape differs, so colour is never
  the only cue):

  | Type    | Colour    | Icon                  | Use |
  |---------|-----------|-----------------------|-----|
  | error   | `live`    | error (circle with !) | Something failed: "Couldn't refresh …", "Could not save settings", "Downloads paused: …" |
  | warning | `live`    | warning triangle      | Something is about to go wrong: "The disk is almost full …" |
  | success | `success` | check circle          | It worked: "Channels updated", "Added “X” to Downloads" |
  | info    | —         | —                     | Plain facts and Undo offers: "Removed “X” from Continue watching" |

  Never `accent` for a type: gold stays for focus, selection, progress and
  the main action. Every message stays 6 s (also with an action), one at a
  time (a new one replaces it) and closes when another page opens; refresh
  confirmations aren't shown over the player. Code shows them only through
  `showAppMessage` (lib/ui/shell/app_messages.dart).
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
  Watched marker: small ✓ badge in success colour; downloaded marker
  below it: the same round `success` badge with the "downloaded" icon
  (`download_done`, hint "Downloaded"), so the two never look alike. A
  series poster has it while some of its episodes are downloaded.
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
- **Detail backdrop** (movie and series details, desktop): the backdrop
  (TMDB's first, else the provider's) lies behind the top of the page,
  across its width, 16:9 but at most 60 % of the window height, aligned to
  the top, under a transparent app bar (it takes `background` once the
  page scrolls under it). Three fades, all from tokens: `scrim` at 55 % →
  0 over the top 25 % (keeps ← and ⋮ readable), `background` at 85 % → 0
  from the left over 55 % of the width (behind the text), and
  `background` 0 → 100 % over the bottom 45 %, so the image melts into
  the page. The poster (260 movies, 180 series) and the details start at
  40 % of the image height. Without a backdrop the page is as before
  (poster beside the details, no fades).
- **Cast row** ("Cast", movie and series details, after the details or
  the episodes, before Recommendations): heading `titleLarge`, then a
  sideways row of 104-wide members: a round photo 88 across (TMDB `w185`,
  placeholder `card` with a person icon), the actor's name (`titleSmall`,
  one line, centred) and the character (`bodySmall`, `textMuted`, one
  line). The row's height follows the text scale. Each member has the
  tooltip "Open <name>" and opens the person page. Left out without cast.
- **Recommendations** (after Cast): the Other sources row with the
  heading "Recommendations": TMDB's recommendations that are in the
  catalogue (by TMDB id), one poster per title and variant group, none
  from hidden categories, movies and series mixed in TMDB's order. Left
  out when empty.
- **Person page**: back arrow; a round photo (160 desktop, 120 phone, TMDB
  `w342`) beside the name (`headlineMedium`) and biography (`bodyLarge`,
  `textSecondary`, 4 lines, then a "More"/"Less" text button); on a phone
  photo, name and biography are centred above each other. Below: rows
  "Movies" and "Series" (the Other sources row) with the catalogue titles
  the person acted in, newest first. Without any: "None of <name>'s movies
  or series are in your playlist." (`bodyLarge`, `textSecondary`).
  Loading shows a linear progress bar under the name; a failure says
  "Couldn't load this person's details." with "Retry".
- **Details menu** (⋮ "More options" in the details app bar, only when the
  title is linked to TMDB): "Wrong TMDB match? Remove it", confirmed in a
  dialog ("Remove the TMDB match?", Cancel / Remove).
- **TMDB images**: sizes by use, never originals: posters `w342` in
  lists and rows, `w500` on detail pages and Featured; backdrops `w1280`
  (desktop, Featured) and `w780` (phone, 16:9 cards); cast `w185`;
  episode stills `w300`; person photo `w342`. Their own disk cache, apart
  from the provider's posters. The cache follows where an image comes
  from, not its host: provider images on TMDB's server go to the
  provider's cache. Nothing is loaded from TMDB while it is off.
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
  click plays live at once. Esc closes it. A replayable past programme
  also has "Download" (secondary; "In Downloads", disabled, once queued)
  and, below the times, what it saves ("Download saves 19:58–21:15": the
  start margin before, the end margin after).
- **Player overlay**: `scrim` background, controls in `textPrimary`, accent
  progress fill, secondary pills for Subtitles / Audio.
- **Player controls bar**, left to right: the primary action (play/pause for
  movies, episodes and replays; on live TV pause on channels with an
  archive, else nothing; greyed out while recording, hint "Pause isn't
  available while recording"), Record on live TV (see Recording), the
  seek bar with position and end time (on live TV nothing, or "Paused · Behind live
  0:45" while paused; in a replay clock times, see Replay player), the
  skip button while an intro or recap plays (see Skip button), the
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
  and which hides with it (the prominent skip button, shown without the
  bar, has no hint until the bar shows). The seek bar's hover time is the
  same pill, drawn by mpv (its own small overlay, so the bar's image
  doesn't change with the pointer) centred under the pointer just above
  the bar: windowed at the bottom edge of the video, fullscreen above the
  bar, hidden with it. VOD shows the position ("1:02:15"), replays the
  clock time ("20:41:12"); the touch player has none. In the touch player (Android) there is no hint
  line: controls use ordinary tooltips, shown on long-press, without key
  names ("Pause live TV", "Seek (or double-tap left or right: 10 s)").
- **Player layout**: windowed, the video keeps its area; the controls bar
  (with its hint line) and now/next (live TV: titles plus the short descriptions, two lines for
  now, one for next where it fits) sit below it and panels beside it. The
  video area is never resized for transient UI. In fullscreen the video
  fills the screen and the controls, panels and the next-episode card are
  drawn over it by mpv (the same widgets, mirrored as images): the bar is
  `scrim` at 85 % across the bottom, a panel takes the right edge. They
  show on mouse movement or a key and hide after 3 s (with the cursor),
  but stay while a panel is open, a control has keyboard focus or a slider
  is dragged. The sliders (seek, volume) never take keyboard focus, so the
  arrow keys always seek and change the volume.
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
- **Recording** (Record now, live TV only, not while paused or in a
  replay): Record (`fiber_manual_record_outlined`, hint "Record
  <channel> until 21:15 (r)": the programme's end from the guide plus the
  end margin, at most the maximum length) turns into "Stop recording (r)"
  (`stop_circle_outlined`, `live` colour) followed by the recording
  indicator: a `live` dot and "REC 0:12:34" (label 700, tabular figures;
  it says REC, so not colour alone). In fullscreen the indicator stays at
  the top right over the video as a pill (`scrim` at 85 %, pill radius),
  also while the controls are hidden. A reason it can't start ("Can't
  record: less than 5 GB free on the disk.") shows in its place for 6 s.
  It records what mpv plays, with no second stream, and stops by itself
  at the planned end, when the stream ends ("Stopped: the stream
  ended.") or the disk fills up.
- **Stop recording?**: switching channel, Stop, Back and closing the app
  while recording ask first, in a side panel (dialogs can't be drawn over
  the video): "Stop recording?" (card title), "Switching channel stops
  the recording of <channel>. What's recorded so far is kept." (Leaving
  the player / Closing the app …), primary "Stop recording", which then
  goes on with the action, and "Keep recording" (focused, also Esc).
- **One stream at a time**: the provider allows one stream for playback,
  downloads and recordings together. Playing from the provider while a
  download runs asks "Pause the download?" ("Your provider allows one
  stream at a time. “X” is downloading (45 %). It continues when playback
  stops.") with "Don't play" and "Pause download" (primary, focused); in
  the player the same question is a side panel. Downloaded files play
  offline and never ask. A download waits while something plays.
- **Mouse on the video**: click = play/pause (live TV: pause on channels
  with an archive, else show the controls),
  double click = fullscreen (the click doesn't also fire), wheel = volume.
- **Touch player** (Android; Linux keeps the mpv player above): always
  landscape fullscreen, immersive (system bars hidden), back to portrait
  with the bars on leaving (a phone stays in portrait); the screen stays on while playing. The video
  fills the screen (`scrim` around it) and the controls are Flutter
  widgets drawn over it, fading in and out (200 ms): they show on open
  and on a tap, hide 3 s after the last touch or on a tap, and stay while
  a side panel is open or the seek bar is dragged. Top row on a `scrim`
  75 % → transparent gradient: back arrow, title (channel without the
  provider's ◉, with the replay mark; REPLAY badge and programme in a
  replay; movie/episode without the provider's tag), Subtitles and audio
  (greyed out, "No subtitles or other audio", when there's nothing to
  choose) and, only with Settings › Player › "Player debug info", Debug
  info (`bug_report_outlined`). Middle: one large play/pause (56, on
  `scrim` 60 %) where pausing is allowed (as in the controls bar), a
  spinner instead while loading. Bottom row on the mirrored gradient:
  the seek bar (replay: clock times + LIVE), on live TV the now line with
  progress, or "Paused · Behind live 0:45" + LIVE. Everything inside the
  safe area (camera cutout). Side panels (Subtitles and audio, Debug
  info) slide in from the right edge, 360 wide (at most 70 % of the
  screen), `surface`, over a `scrim` 40 % barrier that closes them on a
  tap; Back closes them too. Episodes: the skip button and the
  next-episode card at the bottom right over the video, above the seek
  bar; at the end of an episode the next one plays in the player (unless
  cancelled, Play next Off or the last one: then it closes).
- **Player errors** (standing rule): never mpv's own text in the UI. A
  known message gets plain words ("The provider refused the stream (HTTP
  403).", "Couldn't connect to the stream.", "This video or audio format
  can't be played."), anything else "The stream couldn't be played.";
  harmless ones (a seek on a live stream that can't seek) show nothing.
  The original stays in the player log, redacted.
- **Touch gestures**: tap = show/hide the controls; double tap on the left
  or right 40 % = back/forward 10 s where seeking is possible (movies,
  episodes, recordings, replays; never live TV), each further tap on that
  side within 0.7 s another 10 s; the middle 20 % never seeks. Where a
  double tap can seek, a single tap waits 300 ms to know it isn't one;
  elsewhere it acts at once. The seek hint is a `scrim` 85 % pill
  (radius 24, `fast_rewind`/`fast_forward` + "−10 s"/"+30 s", tabular
  figures) centred in that side's third, gone 0.6 s after the last tap.
  Vertical swipe: right half = the phone's media volume (no Android
  volume panel), left half = brightness of the app window only (reset to
  the phone's when the player closes); the full height is 0–100 %, up is
  more; swipes starting within 48 of the top or bottom edge, or within
  32 (or the phone's gesture inset, if wider) of the left or right edge,
  are left to the system (notification shade, home and back gestures).
  The level hint is the same pill near the top: icon
  (`brightness_6_outlined`, `volume_up_outlined`/`volume_off_outlined` at
  0), a 120-wide progress bar and "60 %".
- **Channels panel** (zap, `c`): side panel 360 wide, my Live TV
  categories as toolbar chips, then compact channel rows (logo, name, the
  programme on now with progress); the current channel is the selected row
  and has focus. A click or Enter switches channel in the player and closes
  the panel. Without my Live TV categories it shows a hint about the star.
- **Next episode card**: `surface` panel 360 wide, "Next episode in N s"
  (card title), the episode code and title (`textSecondary`), primary
  button "Play now" (focused) and secondary "Cancel" (also Esc). Windowed it
  sits beside the video, in fullscreen at the bottom right over it; in the
  touch player at the bottom right over the video, above the seek bar,
  with ordinary tooltips. It comes "Play next episode" seconds before the
  end, or, when the episode's credits times are known, at the start of the
  credits with a 10 s countdown (playback time: pausing holds it; a seek
  into or within the credits starts it again from there). Play next Off:
  no card and no auto-start.
- **Skip button** (episodes with intro or recap times): "Skip intro" /
  "Skip recap" with the `fast_forward` icon; it jumps to the end of the
  part. It shows from the part's start to 1 s before its end. When
  playback reaches the start (or starts there) it is the filled primary
  button for 10 s of playback ("prominent"), once per part; after that,
  or after resuming or seeking into the middle, it is outlined and only
  shows with the controls. Windowed it sits in the controls bar after the
  seek bar (the bar is always shown there; the video never resizes for
  it). In fullscreen the prominent button is drawn by mpv at the bottom
  right of the bottom overlay while the controls are hidden, later it is
  in the bar. Touch player: at the bottom right over the video, above
  the seek bar, prominent on its own, then only with the controls. Hint
  "Skip intro (i)" (touch: "Skip intro" on long-press). Never skips by
  itself.
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
- **Downloads page** (sidebar, after Series): page title "Downloads"
  with "Pause all" (secondary, pause icon, hint "Pause all downloads;
  none starts until you resume"; "Resume all", play icon, hint "Downloads
  are paused. Resume the queue" while paused; shown while something is in
  the queue) and "Open folder" (secondary, hint: the folder). Sections "In
  progress" (queue order), "Recordings" (recordings and programmes from
  the archive) and "Downloaded" (movies and episodes), newest first.
  Rows: `card`, radius 12, padding 10/14: poster (44×64) or channel logo
  (64×64 on `background`), the provider label and title, a meta line
  (13, `textMuted`: "Movie · 2020 · 2.1 GB", "S01E02 · Pilot", "Recording
  · <channel> · Mon 26 Oct 20:00–21:15"), while it downloads a 4 px
  progress bar (indeterminate while the size is unknown) and a status
  line (13, `textSecondary`): "45 % · 1.0 of 2.1 GB · 4.2 MB/s · 4 min
  left", "Waiting for its turn" ("Queued · downloads paused" while the
  queue is paused), "Waiting: starts at 21:15", "Paused ·
  45 % · …", "Paused while playing", "Paused: less than 5 GB free on the
  disk.", "Failed: <reason>" (with an error icon), "Couldn't resume: the
  server started it again from the beginning.", "Recording · 0:12:34 ·
  1.2 GB" (with a `live` dot). Icon buttons at the end, each with a hint:
  Pause / Resume (Try again after a failure), Cancel download; Play,
  Remove (deletes the file). A click on a finished row plays it. Remove
  and cancelling a partial download ask first ("Remove “X”? The file
  (2.1 GB) is deleted." Cancel / Remove; "Cancel “X”?" Keep downloading /
  Cancel download). Empty: "Nothing downloaded yet" and a line on where
  Download is. Rows grow with the text (no fixed heights).
- **Download actions**: movie details have "Download" (secondary) after
  Mark as watched; once in the list it shows the state ("Downloading
  45 %", "Queued for download", "Download paused", "Download failed",
  "Downloaded" with the icon in `success`) and opens the Downloads page.
  Episodes have "Download", "Cancel download" or "Remove download" in
  their menu (⋮, right click, long press, Menu key), and a `downloading`
  icon or the downloaded mark after the title; the season menu has
  "Download season" (the episodes not in the list yet). Adding shows
  "Added “X” to Downloads" (or "Added 3 episodes of “X” to Downloads")
  with "Show" for 6 s; it also closes when another page opens.
- **Download files**: saved exactly as the provider sends them, with its
  extension, in the downloads folder: `Movies/<Title> (<Year>).<ext>`,
  `Series/<Series>/Season 01/<Series> - S01E02 - <Episode>.<ext>`,
  `Recordings/<Channel> - <Programme> - 2026-10-27 20-00.ts`; clean titles
  only, " (2)" when a name is taken. One download at a time, in order,
  while the app is open; partial files resume (also after a restart).
  Pausing the running download (or Pause all) pauses the whole queue,
  also across a restart, until Resume on a download (which then goes
  first) or Resume all; pausing a queued one only skips it. A download
  paused for playback continues by itself when playback stops.
  Movies and episodes share their position and watched marks with the
  streamed item; recordings and programmes from the archive keep no
  position and stay out of Continue watching.
- **Disk space**: below the minimum free space plus 1 GB a snack bar
  warns ("The disk is almost full: downloads pause at 5 GB free."); below
  the minimum downloads pause (until Resume) and recordings stop,
  keeping what was saved. A download whose size doesn't fit doesn't
  start ("Not enough disk space: needs 4.2 GB, 6.0 GB free, keeps 5 GB
  free.").
- **Settings › Downloads & recording** (after Player): Folder (the path,
  "Change…" opens a folder picker, "Use default" when changed), End
  margin (None, 5–60 min, default 15), Start margin (replay) (None, 1, 2,
  5, 10 min, default 2), Maximum recording length (1–12 h, default 4),
  Minimum free disk space (1–50 GB, default 5).
- **Settings › Services** (after Search, before About): "TMDB" switch,
  "TMDB key" ("Not set" / "Saved in the system keyring.", the result of
  the last test below it; text buttons "Remove key", outlined "Test
  connection" and "Enter key…", which opens a dialog with an obscured
  field), "TMDB info: 12,400 of 31,500 titles" with the state under it and
  an outlined "Pause"/"Resume" (tooltips "Stop fetching TMDB info for
  now" / "Continue fetching TMDB info"), "Prefer TMDB posters" switch
  (disabled while TMDB is off), "Image cache" ("TMDB images: 312 MB of
  1 GB", a dropdown of sizes and "Clear"), and "Removed matches: N" with
  "Allow matching again" when there are any. Then "SkipDB" and
  "TheIntroDB" (`fast_forward_outlined`, both default on): the name, a
  line on what it gives, the result of the last test, an outlined "Test
  connection" below the text (disabled while off) and the switch as
  trailing; then "TheIntroDB key (optional)" ("Not set. A key of your own
  raises the daily limit." / "Saved in the system keyring.", "Remove key"
  and "Enter key…" below the text, so phone rows keep their width). Keys
  in the system keyring like TMDB's; SkipDB needs none for reading. A
  service that is off gets no requests (not even a test).
- **Settings › About** (last): the app's name (`titleLarge`) and a short
  line, then "Data sources" with the TMDB logo 14 high (smaller than the
  app's name, as TMDB asks) and "This product uses the TMDB API but is not
  endorsed or certified by TMDB." (`textSecondary`); then "Intro, recap and
  credits times come from SkipDB and TheIntroDB, made by their
  communities." and "SkipDB data © SkipDB contributors, available under the
  Open Database License (ODbL) 1.0." (`textSecondary`), and text-button
  links (`open_in_new` 16, the address as tooltip) "SkipDB", "ODbL 1.0" and
  "TheIntroDB" that open the browser (an error message with the address
  if it can't).
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
- **Every manual reload confirms**: each reload the user starts (⟳
  "Reload channels", "Refresh TV guide", "Reload movies", "Reload series",
  "Refresh all", and "Retry" on a list that couldn't load) ends with a
  snack bar: "Channels updated", "Movies updated", "Series updated", "TV
  guide updated", "Playlist updated" (Refresh all), or on failure
  "Couldn't refresh <parts>. <describeRefreshError text>" (Refresh all
  names only the failed parts). No action, 6 s, closes when another page
  opens, a new one replaces the old one (never stacked), nothing while
  something plays. New reload actions follow the same rule; automatic
  refreshes stay silent apart from the failure notice above.
- **My categories**: in category lists above the provider categories, with
  their icon (outline, 18), name and count; an edit mode reorders them and
  hides provider categories (eye toggle, hidden ones dimmed).
- **Custom order** (kept per provider, like my categories): reorderable
  rows have a drag handle (`drag_indicator`, hint "Drag to reorder"), and
  the same moves are in a menu for the keyboard: "Move up", "Move down",
  "Move to top" (disabled where they can't move; Move up/down pass over
  entries that aren't shown, such as hidden categories or items left out
  by a search). Keyboard focus stays on the moved entry.
  - Provider categories: each of Live TV, Movies and Series has its own
    order, used wherever they are listed (category column, Settings
    categories page, TV guide category menu). Dragged in edit mode; the
    moves are in their context menu (right click, long press, Menu key,
    Shift+F10). Categories the provider adds later go at the end; removed
    ones drop out. "Reset to provider order" (edit mode and the Settings
    categories page) offers "Undo" in a snack bar for 6 s.
  - Items in my categories: a newly added item goes first. "Reorder" (a
    chip above the list or grid while one of my categories is shown)
    turns the channel list or poster grid into a list with drag handles,
    small logos/posters and the names, items the provider dropped
    included; "Done reordering" ends it. The moves are in the item's
    context menu inside my category (Movies/Series: while sorted by "My
    order"). The order is used by the channel list, the player's Channels
    panel and Movies/Series in "My order".

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
| Cast | TMDB's actors of a movie or series, with photos |
| Recommendations | TMDB's recommendations that are in the playlist |
| TMDB info | What TMDB adds to the provider's details (Settings › Services) |
| Services | Settings for online services such as TMDB |
| Recently viewed channels | The last live channels played (up to 20) |
| Recently added series / movies | Newest series (by last update) / movies (by date added) |
| Edit home | The mode that moves and hides Home rows |
| Move up / Move down / Move to top | Menu entries that move a category or an item one place or to the start |
| Reorder / Done reordering | The mode that drags the items of one of my categories into my order |
| Reset to provider order | Puts the provider categories of a section back in the provider's order |
| My order | The sort of Movies/Series in my categories that keeps my order (default there) |
| Channels | The player's zap panel of my Live TV categories |
| Play next episode | The setting and countdown that start the next episode |
| Skip intro / Skip recap | The player button that jumps to the end of an episode's intro or recap |
| Credits | The end credits of an episode; their start brings the next-episode card |
| SkipDB / TheIntroDB | The community databases of intro, recap and credits times (Settings › Services) |
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
| Downloads | The page and list of downloads and recordings |
| More | The phone layout's last tab: TV Guide, Downloads, Settings |
| Download | Saves a movie, an episode or a past programme (from the archive) to the downloads folder |
| Download season | Downloads the season's episodes that aren't in Downloads yet |
| Downloaded | A movie or episode whose file is complete; it plays offline |
| Cancel download | Stops a download that isn't finished and deletes what was saved |
| Remove / Remove download | Deletes a finished download's file |
| Pause the download? | The question before playing from the provider while a download runs |
| Record | Records the live channel playing, from what the player plays |
| Stop recording | Ends the recording, keeping the file |
| Recording / Recordings | A recording in progress / recordings and programmes saved from the archive |
| End margin | Minutes saved after a programme ends (recordings and the archive) |
| Start margin (replay) | Minutes saved before a programme starts, from the archive |
| Maximum recording length | A recording stops after this long in any case |
| Minimum free disk space | Downloads pause and recordings stop below it |

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
- Sort: "Recently added" (Series: "Recently updated"), "A–Z", "Top rated";
  in one of my categories "My order" comes first and is the default. My
  categories remember their own sort, apart from provider categories.
  Year filter: "This year", "Last 2 years", "Last 5 years", "Custom
  range…". "Reset filters" clears year and genre.
- Home: "Continue watching" mixes movies and episodes, most recently
  watched first, without hidden categories; Enter or a click resumes
  playback, the context menu has "Go to series" (on the season of the
  episode it continues with) or "Go to movie", "Remove from Continue
  watching" and "Add to favourites…" (plus "Remove from favourites" for a
  favourite). Its card says what is left: "S2 ·
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
  end (Esc)", "Record <channel> until 21:15 (r)", "Stop recording (r)",
  "Pause isn't available while recording", "Keep recording (Esc)". Stop
  and the back arrow: "Stop and go back", "Back (stops playback)". Keys:
  Space pause, ←/→ seek 10 s (Shift: 1 min), ↑/↓ volume, f fullscreen,
  Esc (cancel the countdown, close a panel or answer no, leave
  fullscreen), s subtitles, m mute, c channels, n next episode, l go
  live, r record / stop recording.
- Episodes with a next one get a "Next episode (n)" button after
  play/pause; it marks the current episode watched and plays the next.
- "Automatic refresh" (Settings › Playlist, kept per provider): Off, On
  app start, Every 6 hours, Daily (default). Daily means once per
  calendar day in the device's time zone: a part is refreshed when its
  last update was on an earlier day, so the first start of a day (or the
  first check after midnight) refreshes it. It runs only while the app is
  open (checked every 15 min, and at start when the time has passed),
  waits while something plays, and after a failure tries again an hour
  later at the earliest. Off still downloads a part that has never been
  downloaded. Channels are downloaded on every start in any mode.
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
