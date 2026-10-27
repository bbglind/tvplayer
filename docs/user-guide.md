# tvplayer user guide

A practical guide for testers: what each part of the app does and how to
use it. Button and menu names are written exactly as they appear in the
app, in quotes ("Refresh all").

> This guide follows the app as it is today. Where something only works in
> part, or only on one platform, it says so.

## Contents

1. [What tvplayer is](#1-what-tvplayer-is)
2. [Getting started](#2-getting-started)
3. [Home](#3-home)
4. [Search](#4-search)
5. [Live TV](#5-live-tv)
6. [TV Guide](#6-tv-guide)
7. [Movies and Series](#7-movies-and-series)
8. [The player](#8-the-player)
9. [Downloads and recording](#9-downloads-and-recording)
10. [Settings](#10-settings)
11. [Keyboard shortcuts](#11-keyboard-shortcuts)
12. [One stream at a time](#12-one-stream-at-a-time)
13. [Known limitations and tips](#13-known-limitations-and-tips)

---

## 1. What tvplayer is

tvplayer is a player for an IPTV subscription you already have. You give it
your provider's connection details, it downloads the provider's channels,
movies, series and TV guide (the *playlist*), and you browse and watch them
in one app: live TV with a TV guide and replay, movies and series with
watched marks and "Continue watching", your own favourite categories,
downloads for offline viewing and recording of live TV.

The app ships no content, playlists or providers of its own. Everything you
see comes from your provider.

Today it runs on **Linux desktop**. **Android** is in early testing (see
[Android test builds](#android-test-builds)); nothing else is supported
yet.

---

## 2. Getting started

### Requirements

- **Linux desktop** (64-bit).
- **An X11 session.** The video is embedded in the app window through X11.
  On a Wayland session the app still starts, but video opens in a separate
  mpv window and most of the player described in
  [section 8](#8-the-player) (controls bar, side panels, fullscreen
  overlay, recording) isn't available. On most distributions you pick
  the session on the login screen (e.g. "GNOME on Xorg"). To check what you
  are running: `echo $XDG_SESSION_TYPE` (should print `x11`).
- **mpv**, installed from your package manager. The app starts mpv for
  playback; without it playing shows "mpv is not installed. Install it with
  your package manager (for example: sudo apt install mpv) and try again."
- **A system keyring** (Secret Service, e.g. GNOME Keyring or KWallet).
  Your provider's connection details are stored there, not in a file. If
  the keyring is missing or locked, the app shows "Keyring unavailable"
  with "Retry"; unlock the keyring (an unlock prompt may be open) and press
  "Retry".
- Hardware video decoding uses VA-API by default; it works on most Intel and
  AMD graphics. If video stutters, see
  [Known limitations and tips](#13-known-limitations-and-tips).

You can either run a ready-built copy of the app or build it yourself.

### Option A: run a prebuilt bundle

If someone gave you a built copy, it is a folder called `bundle` with a
`tvplayer` program, a `lib/` and a `data/` folder inside. Keep the folder
together.

1. Install the runtime packages. On Debian/Ubuntu, for example:

   ```sh
   sudo apt install mpv libmpv2 libgtk-3-0 libsecret-1-0 gnome-keyring
   ```

   (Package names differ by distribution and release; on older releases
   `libmpv2` is called `libmpv1`. On KDE, KWallet can take the place of
   `gnome-keyring`.)
2. Copy the `bundle` folder anywhere, e.g. `~/apps/tvplayer`.
3. Start it from a terminal:

   ```sh
   ~/apps/tvplayer/tvplayer
   ```

   If something is missing, the terminal shows which library.

### Option B: build it yourself

1. Install Flutter (stable channel, recent enough for Dart 3.13 or later),
   following the official Linux instructions at
   <https://docs.flutter.dev/get-started/install/linux>. `flutter doctor`
   should show the Linux toolchain as OK.
2. Install the build packages. On Debian/Ubuntu, for example:

   ```sh
   sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
     liblzma-dev libstdc++-12-dev libmpv-dev libsecret-1-dev \
     libjsoncpp-dev mpv gnome-keyring
   ```

3. Get the source and build:

   ```sh
   git clone https://github.com/bbglind/tvplayer.git tvplayer
   cd tvplayer
   flutter pub get
   flutter build linux --release
   ```

   The finished app is in `build/linux/x64/release/bundle/`; start
   `build/linux/x64/release/bundle/tvplayer`, or copy that folder elsewhere
   as in option A.

   While trying things out, `flutter run -d linux` builds and starts it in
   one step.

### Adding a provider

On the first start the app opens **"Add a provider"**.

1. Keep **"Xtream"** selected (the usual kind of IPTV login: a server
   address, a username and a password).
2. Fill in:
   - **Host**: the server address your provider gave you, with the port if
     there is one, e.g. `example.com:8080` or `http://example.com:8080`.
   - **Username** and **Password**: your provider login. The eye icon
     ("Show password") shows what you typed.
3. Press **"Test connection"** to check the details. The result appears
   below the buttons, with a reason in plain words if it fails.
4. Press **"Save"**. The details go into the system keyring and the app
   opens on Home.

There is also an **"M3U URL"** tab that takes a single "Playlist URL". With
an M3U playlist you get **live channels only**: no Movies, Series or TV
guide (and so no replay or recording end times). Xtream is the way to test
the whole app.

You can change or remove the provider later in
[Settings › Provider](#provider).

### The first playlist download

Right after saving, the app downloads the playlist in parts, one after
another: channels, then movies, series and the TV guide. Channels come
first and are usually quick; a large TV guide can take a while ("The first
download can take a while for large guides."). You can start browsing as
soon as channels are in.

To watch progress, open **Settings › Playlist**: each part shows
"Updating…", "Waiting…" or when it was last updated and how much it holds
("Updated Today 12:40 · 4,512 channels").

After that the playlist stays on your computer and is refreshed
automatically (once a day by default, see
[Settings › Playlist](#playlist)). Channels are downloaded again on every
start.

### Finding your way around

The **sidebar** on the left has: Home, Search, Live TV, TV Guide, Movies,
Series, Downloads, and Settings at the bottom. "Collapse sidebar" /
"Expand sidebar" makes it narrow (icons only) or wide again; you can also
drag its edge to resize it.

Most screens with categories show a category column on the left. "Hide
categories" / "Show categories" folds it away when you want more room, and
its edge can be dragged too.

Right click (or long press, or the Menu key, or Shift+F10) on a channel,
movie, series, episode or category opens its **context menu**.

---

## 3. Home

The app opens on Home. At the top: a greeting ("Good morning / afternoon /
evening") and a search field. Typing there and pressing Enter opens
[Search](#4-search) with what you typed.

Below are rows that scroll sideways. Use Shift+mouse wheel, a touchpad,
the arrows that appear on hover, or the keyboard; the normal mouse wheel
scrolls the page. Rows with nothing in them are left out.

- **Featured**: a large banner with recently added movies and recently
  updated series that are well rated (and not already in your favourites
  or hidden categories). "Play" starts it, "More info" opens its details.
  It moves on every 8 seconds unless you hover or focus it; Left/Right
  page through it by keyboard, the dots show where you are.
- **Recently viewed channels**: the last live channels you watched (up to
  20), with "Watched 1 h ago" and what is on now. Click to watch. The
  context menu has "Remove from recently viewed".
- **My categories**: a tile per category of your own (icon, type, name and
  count). Click to open it in Live TV, Movies or Series. With none yet,
  the row explains how to create one with the star.
- **Continue watching**: movies and episodes you started, most recently
  watched first, saying what is left ("S2 · E4 · 18 min left", "1 h 02 min
  left"). Click or Enter resumes playback. Its context menu has "Open
  details", "Remove from Continue watching" and "Add to favourites…".
  **"See all"** opens the Continue watching page: the same cards in a grid
  with the chips "All", "Movies" and "Series" (back arrow to return).
- **Recently added series** and **Recently added movies**: the newest
  posters. "See all" opens Series or Movies with "All" and "Recently
  added".

### Edit home

The **"Edit home"** button (top right) lets you change the rows: move a row
with "Move up" / "Move down", and "Hide row" / "Show row". Press "Done" when
finished.

---

## 4. Search

There are two kinds of search.

### The Search page (everything)

Open **Search** in the sidebar (or type in the field on Home). It searches
channels, movies and series at once and shows three groups: "Live TV",
"Movies" and "Series", each with its count. **"Show all"** opens the full
list of one group; "All results" (or Esc) goes back to the three groups.

Hidden categories (see [Live TV](#hiding-and-ordering-provider-categories))
are left out, unless you switch on "Show hidden categories in global
search" in [Settings › Search](#search-1).

### The search field in Live TV, Movies and Series

Each of these pages has its own search field. It searches the **whole
section** (except hidden categories), whatever category is selected. To
search only the category you are in, turn on the **"Only in <category>"**
chip that appears while you type.

Search ignores case and accents, so "cafe" finds "Café".

---

## 5. Live TV

**Live TV** shows the category column on the left and the channels of the
selected category on the right. Each channel row shows its number, logo,
name, the programme on now ("Programme · until 21:00") with a progress bar,
and a star if it is one of your favourites.

Click a channel (or select it and press Enter) to watch it.

At the top: the search field ([see Search](#the-search-field-in-live-tv-movies-and-series)),
and ⟳ "Reload channels", which downloads the channel list again.

### Categories

The column has, from the top:

- **My categories**: your own categories (see below), with icon, name and
  count.
- **All channels**: every channel except those in hidden categories.
- **Categories**: the provider's own categories.

The heading above the list names what is selected.

### My categories (favourites)

My categories are your own lists, for example "News" or "Kids". A channel,
movie or series can be in several of them. Live TV, Movies and Series each
have their own.

- **Add an item**: click the **star** at the end of a channel row (or on a
  poster, top left; the outline star shows on hover or focus), or use
  "Add to favourites…" in its context menu. A menu lists your categories
  as checkboxes; each tick is saved at once. "New category…" creates one
  on the spot. "Done", Esc or a click outside closes the menu.
- A **filled star** means the item is in at least one of my categories.
- **Create, rename, delete**: "New category" (in the column's edit mode,
  or in Settings › Categories) asks for a name and an icon. A category's
  context menu has "Rename or change icon…" and "Delete…" (deleting asks
  first; the items themselves aren't touched).

### Hiding and ordering provider categories

Press **"Edit categories"** at the top of the category column to enter edit
mode ("Done editing" leaves it):

- The **eye toggle** on each provider category hides or shows it. Hidden
  categories are dimmed here and left out of "All channels", search, Home
  and the TV guide. "Hide all" / "Show all" do all of them at once.
- **Drag** a category by its handle ("Drag to reorder") to change the
  order, or use "Move up", "Move down" and "Move to top" from its context
  menu (handy by keyboard; focus stays on the moved category).
- My categories can be reordered the same way.
- **"Reset to provider order"** puts the provider categories back in the
  provider's order, with "Undo" in a message for 6 seconds.

Live TV, Movies and Series each keep their own order. The order is used
wherever categories are listed: the column, the Settings categories page
and the TV guide's category menu. Categories the provider adds later go to
the end.

The same can be done in **Settings › Categories** (see
[Settings](#categories)), which also has a filter field for long lists.

### Reorder (the order inside one of my categories)

A newly added item goes **first** in its category. To arrange them yourself,
open one of my categories and press the **"Reorder"** chip above the list.
The list becomes compact rows with drag handles; drag them, then press
**"Done reordering"**. Inside my category, an item's context menu also has
"Move up", "Move down" and "Move to top".

This order is used by the channel list, the player's Channels panel and by
Movies/Series sorted by "My order".

Items the provider no longer lists stay in your category, marked "The
provider no longer lists this channel.", so you can remove them yourself.
Settings › Playlist also counts them ("No longer listed by the provider").

### Replay mark

Channels whose provider keeps an **archive** (catch-up TV) show a small
history icon right after the name. Hover it for how far back it goes:
"Replay: 3 days back". On those channels you can replay past programmes
from the [TV Guide](#6-tv-guide) and pause live TV in the
[player](#pause-live-tv).

---

## 6. TV Guide

**TV Guide** shows a grid: channels down the left, time across the top, a
vertical line marking the current time. The programme on now is a lighter
cell. The time row has a label every half hour; midnight shows the date.

### Toolbar

From left to right:

- **Category dropdown**: which channels to show ("All channels", one of
  my categories or a provider category).
- **"Now"**: jumps back to the current time (placed a little from the left
  edge, as when the guide opens).
- **"Tonight"**: jumps to 20:00 this evening; from 23:00 on, to tomorrow
  evening. It is disabled while the guide doesn't reach that far yet ("No
  TV guide for tomorrow evening yet").
- **"Updated …"**: when the guide was last downloaded, and ⟳ "Refresh TV
  guide" to download it again.

Scroll with the mouse wheel / touchpad, or move between programmes with
the arrow keys. The channel column's edge can be dragged to make it
wider.

The TV guide is only available for Xtream providers.

### Past programmes

On channels with an archive, the guide reaches back over the archive (at
most 7 days):

- Programmes you **can replay** show a small history icon before the time,
  and "· Replay available" in their tooltip.
- Past programmes you **can't** replay are muted (greyer title).
- Where the provider's normal guide stops in the past, the app fetches the
  past programmes from the provider's archive, one channel at a time,
  starting with the channels in view. Meanwhile the row says "Loading past
  programmes…"; if that fails, "Couldn't load past programmes" (tried again
  after 5 minutes).

### The programme panel

Click a programme (or select it and press Enter, right click, long press,
or press the Menu key) to open its panel: title, channel and time ("Channel
· Mon 26 Oct 20:00–21:00"), category and description, then buttons that
depend on the programme:

| Programme | Buttons |
|---|---|
| Past, can be replayed | **"Play"** (replay it), **"Download"**, "Close" |
| On now | **"Watch live"**, **"Play from start"** (only on channels with an archive) |
| Past, can't be replayed | A line saying why, and "Close" |
| Not started | "Not started yet", "Close" |

The "why not" lines are: "No replay: this channel has no archive", "No
replay: older than 3 days" (the channel's archive length), and "No replay:
not in the provider's archive".

On a channel **without** an archive, clicking the programme on now plays the
channel live straight away. Esc closes the panel.

### Replay

"Play" or "Play from start" opens the player on that programme from the
provider's archive, with a **REPLAY** badge before the title. See
[Replay seeking](#replay-seeking) for how the seek bar works there.

### Download from the archive

For a past programme that can be replayed, **"Download"** saves it to your
computer (see [Downloads](#9-downloads-and-recording)). Below the times the
panel shows exactly what it saves, e.g. "Download saves 19:58–21:15": a
couple of minutes before the start ("Start margin (replay)") and some
minutes after the end ("End margin"), in case the programme started early
or ran late. Both margins are in
[Settings › Downloads & recording](#downloads--recording). Once queued, the
button says "In Downloads".

---

## 7. Movies and Series

**Movies** and **Series** work the same way: the category column on the
left (My categories, "All movies" / "All series", then the provider's
categories), a poster grid on the right.

Click a poster to open its details page.

### Sorting and filters

The toolbar above the grid:

- **Sort**: "Recently added" (Series: "Recently updated"), "A–Z", "Top
  rated". In one of my categories **"My order"** comes first and is the
  default there (the order you set with [Reorder](#reorder-the-order-inside-one-of-my-categories)).
  My categories remember their own sort, separately from provider
  categories.
- **Year**: "This year", "Last 2 years", "Last 5 years", or "Custom
  range…" (a first and/or last year).
- **Genre** (Series): pick one or more genres; ticks apply at once.
- While searching: the "Only in <category>" chip.
- The number of results, and **"Reset filters"** (clears year and genre)
  while a filter is on.

Chips that filter turn gold while active.

### Continue watching

Above the grid, **"Continue watching"** shows the movies or series you have
started, most recently watched first:

- Under "All movies"/"All series": all of them except in hidden categories.
- Under a provider category: only those in that category.
- Under one of my categories: all of them, with those in the category first.

Its context menu has **"Remove from Continue watching"**. For a movie this
forgets where you stopped; for a series it leaves the list but episodes
keep their watched marks, and it comes back when you play or mark an
episode. A message offers "Undo" for 6 seconds.

### Provider labels

Many providers put a tag in front of titles, plus the year and a country
(e.g. `XX - Some Show (2025) (GB)`). tvplayer shows just "Some Show", with
the provider's tag in a small grey label before it. Hover the label (or
focus it) to see what the provider calls it. Only tags that recur across
the catalogue are treated this way, so a title like "CSI - Vegas" stays
whole.

### Watched marks

- A small green **✓** on a poster: watched.
- A green **downloaded** badge below it: the file is downloaded (for a
  series: some of its episodes are).
- A progress bar along a thumbnail: started, not finished.

A movie or episode counts as watched when you play it to (near) the end, or
when you mark it.

### Movie details

Backdrop, title, meta line (year, rating, length, genre), plot, director
and cast, then:

- **"Play"**, or **"Resume from 12:34"** plus **"Play from start"** if you
  started it.
- **"Mark as watched"** / **"Mark as unwatched"**.
- **"Download"**, which then shows its state ("Queued for download",
  "Downloading 45 %", "Download paused", "Download failed", "Downloaded")
  and opens the Downloads page when clicked.
- The star to add it to my categories.

### Series details

The series info, a season selector and the episodes. Each episode row shows
"N. <episode name>" (or "N. Episode N"), a thumbnail with progress, a ✓
when watched, and a download icon or mark when it is downloading or
downloaded.

- Click an episode to play it; the main button resumes the series where
  you left off ("Resume") or plays it ("Play").
- **"Episode options"** (⋮, or right click / long press / Menu key on the
  row): "Mark as watched" / "Mark as unwatched", "Download", "Cancel
  download" or "Remove download".
- **"Season options"**: "Mark season as watched", "Mark season as
  unwatched", and **"Download season"** (all episodes of the season not in
  Downloads yet).

### Other sources

Providers often carry the same movie or series more than once (different
quality, language or region). Below the details (or below the episodes) the
**"Other sources"** row shows those other versions, as posters with their
provider label. The one you played most recently has a gold history icon,
"Last played". When several share a label, the date the provider added
("Added 24 Apr 2026") or updated ("Updated …") them tells them apart.

All versions of a title count as one:

- watched in one = watched in all;
- you resume from the newest position, even if it was another version
  ("Resume from 12:34 (from XX)");
- marking watched/unwatched applies to all (episodes matched by season and
  episode number);
- it appears once in Continue watching (the version you watched last).

If no other versions exist, the row is left out.

---

## 8. The player

Playing anything opens the player. The video sits in the window with the
controls below it and side panels beside it; it never changes size when a
panel opens.

### Controls bar

From left to right (only the parts that apply are shown):

- **Play/pause**. On live TV this is "Pause live TV", only on channels
  with an archive (see [Pause live TV](#pause-live-tv)).
- **"Next episode"** (episodes that have a next one): marks this episode
  watched and plays the next.
- **"Record"** on live TV (see [Recording](#recording-live-tv)).
- **Seek bar** with the position and the end time (movies, episodes,
  replays). Double-click the end time (or focus it and press Enter) to
  switch between the length and the time left ("-12:34").
- **"LIVE"** in a replay or while live TV is paused: back to live.
- **Mute** and a **volume** slider (0–100 %). The volume is remembered.
- **"Channels"** and the **favourite star** (live TV).
- **"Subtitles and audio"**.
- **Fullscreen**, **"Stop"**, and the clock.

Below the bar is a **hint line**: hover or focus any control and it says
what it does and its key, e.g. "Mute (m)". (Tooltips can't be drawn over
the video, so they appear there.)

On live TV, the current and next programme are shown below the bar.

The back arrow ("Back (stops playback)") or Stop ("Stop and go back") ends
playback and returns to where you started.

### Mouse on the video

- **Click**: pause/resume (live TV: pause on channels with an archive,
  otherwise just shows the controls).
- **Double click**: fullscreen on/off.
- **Mouse wheel**: volume.

### Fullscreen

**f**, double click or the fullscreen button. The video fills the screen;
the controls bar, panels and the next-episode card appear over it when you
move the mouse or press a key, and hide again after 3 seconds (with the
mouse pointer). They stay while a panel is open, a control has keyboard
focus or you drag a slider. **Esc** (or f, or a double click) leaves
fullscreen.

### Channels panel (zapping)

On live TV, **"Channels"** or **c** opens a panel with your Live TV
categories as chips and their channels, with what's on now. The current
channel is selected. Click or Enter switches channel (fullscreen stays) and
closes the panel; Esc closes it. It only shows **my categories**: without
any, it explains how to add channels with the star.

### Subtitles and audio

**"Subtitles and audio"** opens a panel listing the subtitle tracks (and
"Off") and the audio tracks; pick one. **s** jumps to the next subtitle
track (or off) without opening the panel.

When playback starts, tracks are picked from your preferred languages in
[Settings › Subtitles and audio](#subtitles-and-audio). If you pick a track
by hand while watching a series, that choice is remembered for the rest of
the series.

### Next episode

When an episode is close to its end (30 seconds by default, see
[Settings › Player](#player)), a card counts down: "Next episode in 12 s",
with the episode's code and name, **"Play now"** and **"Cancel"** (also
Esc). Cancel plays this episode to the end, which then shows "Episode
finished" with "Play next episode". After a season's last episode it moves
on to the next season; after the very last episode there is no card.

**n** or the "Next episode" button skips ahead at any time.

### Pause live TV

On channels **with an archive** you can pause live TV: Space, a click on
the video, or the pause button. The picture stays, the bar shows "Paused ·
Behind live 0:45", and the stream is closed meanwhile. Resuming plays from
the archive, starting 15 seconds before you paused. "LIVE" (or **l**) jumps
back to live.

On channels without an archive there is no pause on live TV.

### Replay seeking

In a replay (from the TV guide, or after pausing live TV) the seek bar uses
**clock times**: the position is the time on air that you are watching
("20:41:12") and the end is the programme's end ("21:00"). While the
programme is still on air, the bar reaches from the programme's start (or
two hours back, if that is earlier) up to now, with "Behind live 12 min"
after it.

- ←/→ jump 10 seconds, with Shift 1 minute; or drag the bar.
- The title and now/next follow what you are watching and run on into the
  next programme.
- A jump outside what is loaded briefly shows a short progress bar while it
  loads from that point.
- Seeking close to now, or reaching the end of the archive within 10
  seconds of live, switches to live.
- "LIVE" / **l** goes live at any time.

Replays don't go into Continue watching.

### Recording live TV

While watching live TV (not paused, not in a replay), **"Record"** or **r**
records the channel. The hint says how long: "Record <channel> until 21:15
(r)", i.e. the end of the current programme from the guide plus the end
margin, but never longer than the maximum recording length (see
[Settings › Downloads & recording](#downloads--recording)).

While recording:

- The button becomes **"Stop recording (r)"**, followed by a red dot and
  "REC 0:12:34". In fullscreen this indicator stays at the top right, also
  when the controls are hidden.
- Pausing isn't possible ("Pause isn't available while recording").
- The recording is what the player is showing, so it costs no extra stream
  from your provider.

It stops by itself at the planned end, when the stream ends ("Stopped: the
stream ended."), or when the disk gets too full. If it can't start, the
reason shows in its place for 6 seconds, e.g. "Can't record: less than 5 GB
free on the disk."

**Switching channel, Stop, Back or closing the app** while recording asks
first, in a side panel: "Stop recording?" — "Switching channel stops the
recording of <channel>. What's recorded so far is kept." Choose **"Stop
recording"** (then the switch/stop/close goes ahead) or **"Keep recording"**
(also Esc).

Recordings appear in [Downloads](#9-downloads-and-recording) under
"Recordings".

### Playback statistics and debug info

Two switches in [Settings › Player](#player) add technical information
below the video: "Show playback statistics" (dropped frames) and "Player
debug info" (mpv details, a hardware-decoding selector and a log). They're
meant for troubleshooting.

### The player on Android

On a phone the player is simpler and made for touch. Opening it turns the
picture to **landscape, full screen** (the status and navigation bars hide;
swipe from the edge to see them for a moment). Leaving it with the back
arrow or Android's back button/gesture returns to portrait with the bars.
The screen stays on while something plays.

The controls are drawn over the video and hide 3 seconds after you last
touched them; **tap the video** to show them, tap again to hide them.
Long-press a button to see what it does.

- **Top**: the back arrow ("Back (stops playback)"), the title (the
  channel without the provider's ◉ mark, or the movie or episode),
  **"Subtitles and audio"** and, with "Player debug info" on, **"Debug
  info"**.
- **Middle**: a large **Pause**/**Resume**: for movies, episodes,
  recordings and replays; on live TV **"Pause live TV"** only on channels
  with an archive, as on the desktop (see [Pause live TV](#pause-live-tv)).
- **Bottom**: the seek bar (movies, episodes, recordings; replays in clock
  times with "LIVE"), on live TV what's on now with its progress, or
  "Paused · Behind live 0:45" with "LIVE" while paused. Double-tap the end
  time to switch between the length and the time left.

Gestures on the video:

- **Double-tap the right or left side**: forward or back 10 seconds, with
  a short "+10 s" / "−10 s" sign; keep tapping on that side to go further
  ("+30 s"). Only where you can seek (movies, episodes, recordings,
  replays), not on live TV.
- **Swipe up or down on the right half**: the phone's media volume (the
  same as the volume keys).
- **Swipe up or down on the left half**: brightness, for this app only
  while the player is open; leaving the player gives the phone its own
  brightness back.

A swipe that starts close to the top or bottom edge is left to Android.

**"Subtitles and audio"** opens a panel on the right with the subtitle
tracks (and "Off") and the audio tracks; tap beside it or press back to
close it. The button is greyed out ("No subtitles or other audio") when
there is nothing to choose. Tracks are picked from your preferred
languages, and a choice made in a series is remembered, as on the desktop.

Movies and episodes start where you left off and save their position as
they play, so Continue watching follows what you watched on the phone. At
the end of a movie or episode the player closes.

Not on Android yet: the Channels panel, the next-episode card, recording,
the volume slider and mute, and playback statistics.

---

## 9. Downloads and recording

You can save **movies**, **episodes** and **past programmes from the TV
guide archive** to your computer and watch them without the provider, and
**record** live TV from the player.

### Adding downloads

- **Movie**: "Download" on the details page.
- **Episode**: "Download" in the episode's menu (⋮ / right click).
- **Whole season**: "Download season" in the season menu.
- **Past programme**: "Download" in the TV guide's
  [programme panel](#the-programme-panel).

A message says "Added “X” to Downloads" (or "Added 3 episodes of “X” to
Downloads") with **"Show"** to open the Downloads page.

### The Downloads page

**Downloads** in the sidebar. At the top:

- **"Pause all"**: pauses the whole queue; nothing starts until you resume
  ("Resume all" then appears). Shown while something is in the queue.
- **"Open folder"**: opens the downloads folder in your file manager. Not
  shown on Android.

Three sections:

- **In progress**: the queue, in order.
- **Recordings**: your recordings and programmes from the archive.
- **Downloaded**: movies and episodes.

Each row shows the poster or channel logo, title, a line like "Movie · 2020
· 2.1 GB" or "S01E02 · Pilot", and while active a progress bar and a status:

| Status | Meaning |
|---|---|
| "45 % · 1.0 of 2.1 GB · 4.2 MB/s · 4 min left" | Downloading |
| "Waiting for its turn" | Queued behind another download |
| "Queued · downloads paused" | Queued, but the queue is paused |
| "Waiting: starts at 21:15" / "Waiting for the programme to end" | An archive programme that hasn't finished airing yet |
| "Paused · 45 % · …" | Paused by you |
| "Paused while playing" | Waiting because something is playing (see [One stream at a time](#12-one-stream-at-a-time)) |
| "Paused: less than 5 GB free on the disk." | Paused for disk space |
| "Failed: <reason>" | Failed; "Try again" restarts it |
| "Recording · 0:12:34 · 1.2 GB" | A recording in progress |

Buttons at the end of the row: Pause / Resume (or "Try again"), "Cancel
download"; for finished ones Play and "Remove (deletes the file)". Click a
finished row to play it. Removing, and cancelling a partly downloaded item,
ask first ("Remove “X”? The file (2.1 GB) is deleted.").

### How the queue works

- **One download at a time**, in order, and only **while the app is open**.
- Partly downloaded files **resume** where they stopped, also after
  restarting the app. (If the server refuses to continue, you'll see
  "Couldn't resume: the server started it again from the beginning.")
- **Pausing the running download pauses the whole queue** (just like
  "Pause all"), and it stays paused after a restart. It continues when you
  press Resume on a download (that one then goes first) or "Resume all".
- **Pausing a queued (not running) download** only skips that one; the
  rest carry on.
- A download that was paused because you started playing continues by
  itself when playback stops.

### Playing while downloading, and offline

- Playing something from the provider while a download runs asks first,
  because most providers allow only one stream at a time — see
  [section 12](#12-one-stream-at-a-time).
- **Downloaded** movies and episodes play from the file: no provider, no
  network, no question. They share their position and watched marks with
  the streamed version, so you can start online and finish offline.
- Recordings and archive programmes keep no position and don't appear in
  Continue watching.

### Recordings

Recordings are made in the player (see
[Recording live TV](#recording-live-tv)). Programmes downloaded from the
archive land in the same "Recordings" section.

### Where files go

By default: a `tvplayer` folder in your Videos folder (usually
`~/Videos/tvplayer`). You can change it in
[Settings › Downloads & recording](#downloads--recording). On Android it is
a `tvplayer` folder in the app's own storage
(`Android/data/io.github.bbglind.tvplayer/files/tvplayer`); it can't be
changed yet, and uninstalling the app deletes it. Files are saved
exactly as the provider sends them:

```
Movies/<Title> (<Year>).<ext>
Series/<Series>/Season 01/<Series> - S01E02 - <Episode>.<ext>
Recordings/<Channel> - <Programme> - 2026-10-27 20-00.ts
```

If a name is taken, " (2)" is added. These are ordinary files; you can play
them with any player.

### Disk space

The "Minimum free disk space" setting (default 5 GB) protects your disk:

- 1 GB above the minimum, a message warns: "The disk is almost full:
  downloads pause at 5 GB free."
- Below the minimum, downloads pause (until you resume) and recordings
  stop, keeping what was saved.
- A download whose size is known and doesn't fit doesn't start ("Not enough
  disk space: needs 4.2 GB, 6.0 GB free, keeps 5 GB free.").

---

## 10. Settings

**Settings** is at the bottom of the sidebar. Changes are saved immediately.

### Provider

Shows the type ("Xtream" or "M3U playlist"); connection details are stored
in the system keyring ("Connection details are stored in the system
keyring."). On Android they are stored encrypted in the Android Keystore
("Connection details are stored encrypted on this device."), and if that
can't be read the app shows "Secure storage unavailable" with "Retry".

- **"Edit provider"**: the same form as when adding one.
- **"Remove provider"**: deletes the saved connection details from the
  keyring, or from the device on Android (asks first). The app then returns
  to "Add a provider".

### Playlist

One row per part: **Channels**, **Movies**, **Series**, **TV guide**, with
when it was last updated and how much it holds ("Updated Today 12:40 ·
4,512 channels"), "Updating…" or "Waiting…" during a refresh. If an update
fails, the row says why in plain words, that the previous list is kept,
and when the last successful update was. Parts your provider doesn't have
say "Not available for this provider".

An empty list counts as a failure when it can't be right: no channels at
all, no movies or series while the provider lists categories for them, or
nothing where there was a list before ("The provider sent an empty list.
Try again later."). It is tried again like any other failure.

- **"Automatic refresh"**: Off, On app start, Every 6 hours, **Daily**
  (default).
  - Daily = once per calendar day: the first time the app is open on a new
    day, also if it stays open past midnight.
  - It only runs while the app is open, waits while something is playing,
    and after a failure tries again an hour later at the earliest.
  - Off still downloads parts that were never downloaded. Channels are
    downloaded on every start whatever the setting.
  - A failed automatic refresh shows only a short message ("Couldn't
    refresh movies. The previous data is kept.") with "Details", which
    opens this page. Never while something is playing.
- **"No longer listed by the provider"** (only when it applies): how many
  of your favourites and Continue watching items the provider has dropped;
  the favourites count opens a list of their names.
- **"Refresh all"**: downloads every part again, one after another
  ("Refreshing 2 of 4…").

The ⟳ buttons on Live TV, TV Guide, Movies and Series refresh just that
part, the same way.

### TV guide

- **"Time zone"**: which time zone guide times are shown in, with its
  current offset from UTC, e.g. "Device time zone (Europe/Stockholm,
  UTC+01:00)". Default: your device's time zone. Pick another from a
  searchable list.
- **"Time shift"**: moves all guide times by whole hours (−12 to +12,
  default "None"), for providers whose times are wrong. If programmes are
  consistently an hour off, try this.

### Subtitles and audio

- **"Subtitles on by default"** (default: on). Off still shows forced
  subtitles (for foreign-language parts).
- **"Subtitle languages"**: your preferred subtitle languages, in order;
  the first one available is used. Default: Swedish, then English. "Add
  language", drag to reorder, or remove one.
- **"Audio languages"**: preferred audio languages, in order. Default:
  none ("Stream default", the stream's own default track).
- A choice you make while watching a series is remembered for the rest of
  that series.

### Player

- **"Play next episode"**: how long before the end of an episode the
  countdown starts: Off, 15, 20, **30** (default), 45, 60, 90 or 120 s.
- **"Show playback statistics"** (default off): dropped-frame counters
  below the video.
- **"Player debug info"** (default off): mpv property overlay, hardware
  decoding selector and log. On Android it adds a "Debug info" button to
  the player that opens them in a side panel.

### Downloads & recording

- **"Folder"**: where downloads and recordings go. "Change…" opens a
  folder picker; "Use default" appears when changed. Default:
  `~/Videos/tvplayer` (your Videos folder). On Android the folder is fixed
  (no "Change…"); see [Where files go](#where-files-go).
- **"End margin"**: minutes recorded and saved after a programme ends, in
  case it runs late. None, 5, 10, **15** (default), 20, 30, 45, 60 min.
- **"Start margin (replay)"**: minutes saved before a programme starts,
  when downloading it from the archive. None, 1, **2** (default), 5, 10
  min.
- **"Maximum recording length"**: a recording stops after this long in any
  case (e.g. when the guide has no end time). 1, 2, 3, **4** (default), 6,
  8, 12 h.
- **"Minimum free disk space"**: downloads pause and recordings stop below
  this. 1, 2, **5** (default), 10, 20, 50 GB. A warning comes 1 GB before.

### Categories

**Live TV**, **Movies** and **Series** each open a page to manage that
section's categories in one place: my categories ("New category", "Rename
or change icon", "Delete", "Move up"/"Move down"), and the provider
categories with show/hide per category, "Hide all"/"Show all", a "Filter
categories" field (with "Hide these"/"Show these" for the filtered ones),
drag-to-reorder and "Reset to provider order". The row shows a summary such
as "My categories: 2 · 5 hidden".

### Search

- **"Show hidden categories in global search"** (default off): also find
  channels, movies and series in hidden categories on the Search page.

---

## 11. Keyboard shortcuts

The whole app can be used with the keyboard; the focused item always has a
gold ring.

| Where | Key | Does |
|---|---|---|
| Everywhere | Tab / Shift+Tab, arrow keys | Move focus |
| Everywhere | Enter or Space | Activate the focused button, row, poster or programme |
| Everywhere | Menu key or Shift+F10 | Context menu of the focused item (channels, movies, series, episodes, categories, programmes) |
| Menus, dialogs, panels | Esc | Close / answer no |
| Home, Featured banner | ← / → | Previous / next featured item |
| Search page | Esc | Back from "Show all" to all results |
| TV Guide | Enter (on a programme) | Open the programme panel |
| Player | Space | Play/pause (live TV: pause, on channels with an archive) |
| Player | ← / → | Seek 10 s back / forward |
| Player | Shift+← / Shift+→ | Seek 1 min back / forward |
| Player | ↑ / ↓ | Volume up / down |
| Player | f | Fullscreen on/off |
| Player | Esc | Cancel the next-episode countdown, close a panel or answer no, leave fullscreen |
| Player | s | Next subtitle track (or off) |
| Player | m | Mute on/off |
| Player | c | Channels panel (live TV) |
| Player | n | Next episode |
| Player | l | Go live (in a replay or while live TV is paused) |
| Player | r | Record / stop recording (live TV) |
| Player | Enter (on the end time) | Switch between length and time left |

In the player, while a side panel has focus, the arrow keys, Space and Enter
work inside the panel instead of controlling playback. No player key works
while you are typing in a text field.

---

## 12. One stream at a time

Most providers allow **one stream at a time** per account. Playing,
downloading and recording all count. tvplayer is built around that:

- **Playing while a download runs** asks first: **"Pause the download?"**
  — "Your provider allows one stream at a time. “X” is downloading
  (45 %). It continues when playback stops." Choose **"Pause download"**
  (default) to play, or **"Don't play"**. Inside the player the
  same question appears as a side panel.
- **Downloads wait while something plays.** A download paused this way
  shows "Paused while playing" and continues by itself when playback stops.
- **Recording uses the stream you are watching**, so it doesn't need a
  second one. That is also why switching channel stops the recording
  (and asks first).
- **Downloaded files play offline** and never ask.
- **Automatic playlist refresh** waits while something plays.

If your provider allows more than one stream, the question still appears;
just choose "Pause download" and it resumes when you stop.

---

## 13. Known limitations and tips

### Limitations

- **Linux only for now.** Android is in early testing (below); no other
  platform is supported.
- **The player needs X11.** On Wayland, video opens in a separate mpv
  window and the in-app controls, panels, fullscreen overlay and recording
  aren't available. Log in with an X11 ("Xorg") session.
- **Recording** works only in the Linux mpv player, only for live TV, and
  only while you watch the channel ("Record now"). There are no scheduled
  recordings and no recording in the background. To save a programme you
  missed, download it from the archive in the TV guide instead.
- **Downloads run only while the app is open**, one at a time. Closing the
  app pauses them; they resume on the next start.
- **M3U playlists** give live channels only: no Movies, Series, TV guide or
  replay.
- **One provider at a time.** To switch, edit or remove the provider in
  Settings.
- **Replay** and **pause live TV** depend on the provider keeping an archive
  for that channel (the replay mark). How far back depends on the provider.
- The UI is in **English** only.

### Android test builds

Android builds are for testing. They can add a provider and download the
playlist, and the player is made for touch (see
[The player on Android](#the-player-on-android)); the phone layout of the
other screens is still being worked on. Differences from Linux so far:

- Connection details are kept in the Android Keystore, not a keyring.
- Plain `http://` providers work: Android normally blocks unencrypted
  connections, and the app allows them because most providers use them.
- The downloads folder is fixed and there is no "Open folder" (see
  [Where files go](#where-files-go)).
- "Device time zone" is the time zone set in Android's settings.
- No recording (it needs the Linux mpv player).

### Tips

- **Guide times are off by an hour or more?** First check that Settings ›
  TV guide › "Time zone" shows the right UTC offset. If it does, the
  provider's guide data is off (some providers get daylight saving wrong,
  sometimes only on some channels): use "Time shift".
- **Video stutters or drops frames?** Turn on "Show playback statistics" to
  see dropped frames. "Player debug info" has a hardware-decoding selector
  to try other modes than the default (VA-API).
- **Want the video in mpv's own window?** Start the app with
  `TVPLAYER_EMBED_MPV=0` (e.g. `TVPLAYER_EMBED_MPV=0 ./tvplayer`). Mainly
  useful for comparing playback; the in-app player features are then
  limited as on Wayland.
- **Large text.** If your desktop uses a large text scale, the app follows
  it. If some text looks cut off, please report where.
- **Too many categories?** Hide the ones you never use (Edit categories, or
  Settings › Categories with "Filter categories" and "Hide these"). Hidden
  categories disappear from lists, search, Home and the guide.
- **Build your own lineup**: put your everyday channels in one of my
  categories and sort them with "Reorder"; the player's Channels panel
  (c) then becomes a quick zap list.
- **Where your data lives**: connection details in the system keyring;
  the downloaded playlist, favourites, watch history and settings in the
  app's data folder (`~/.local/share/io.github.bbglind.tvplayer`); downloads in
  the downloads folder. Removing the provider deletes the keyring entry.
  If you used an earlier test build, its data folder
  (`~/.local/share/dev.example.tvplayer`), cache and saved provider are moved
  over automatically the first time this version starts.

### Reporting problems

When something goes wrong, note what you did, what you expected and what
happened, plus the exact message if one was shown. Please **don't** share
your server address, username, password or stream links: messages in the
app are written to leave them out, and screenshots are fine as long as no
connection details are visible.
