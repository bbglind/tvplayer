#ifndef RUNNER_VIDEO_EMBED_H_
#define RUNNER_VIDEO_EMBED_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// A native X11 child window laid over the Flutter view, for mpv to draw
// into via --wid. Controlled from Dart over the "tvplayer/video_embed"
// method channel:
//
//   create()                      -> X11 window id, or error "unsupported"
//   setRect({x, y, width, height}) position in logical pixels of the view
//   hide()
//   setFullscreen(bool)           fullscreens the whole app window
//
// and calls back "doubleClick" and "fullscreenChanged"(bool).
typedef struct _VideoEmbed VideoEmbed;

// Wraps |view| in an overlay inside |window| and sets up the channel. Call
// instead of adding |view| to |window| directly. Lives as long as |window|.
void video_embed_new(GtkWindow* window, FlView* view);

#endif  // RUNNER_VIDEO_EMBED_H_
