#include "video_embed.h"

#include <cmath>

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

struct _VideoEmbed {
  GtkWindow* window;
  FlView* view;
  GtkWidget* overlay;
  // Created on the first "create" call; lives as long as the window.
  GtkWidget* area;
  FlMethodChannel* channel;
  GdkRectangle rect;
};

static const char kChannel[] = "tvplayer/video_embed";

static gboolean get_child_position_cb(GtkOverlay* overlay, GtkWidget* widget,
                                      GdkRectangle* allocation,
                                      VideoEmbed* self) {
  if (widget != self->area) return FALSE;
  *allocation = self->rect;
  return TRUE;
}

// Black until mpv draws, and wherever mpv letterboxes.
static gboolean draw_cb(GtkWidget* widget, cairo_t* cr, gpointer) {
  cairo_set_source_rgb(cr, 0, 0, 0);
  cairo_paint(cr);
  return TRUE;
}

// mpv runs with --input-cursor=no, so clicks on its window propagate here.
static gboolean button_press_cb(GtkWidget* widget, GdkEventButton* event,
                                VideoEmbed* self) {
  // Keep keyboard input (Esc) going to Flutter.
  gtk_widget_grab_focus(GTK_WIDGET(self->view));
  if (event->type == GDK_2BUTTON_PRESS && event->button == 1) {
    fl_method_channel_invoke_method(self->channel, "doubleClick", nullptr,
                                    nullptr, nullptr, nullptr);
  }
  return TRUE;
}

static gboolean window_state_cb(GtkWidget* widget, GdkEventWindowState* event,
                                VideoEmbed* self) {
  if (event->changed_mask & GDK_WINDOW_STATE_FULLSCREEN) {
    gboolean fullscreen =
        (event->new_window_state & GDK_WINDOW_STATE_FULLSCREEN) != 0;
    g_autoptr(FlValue) args = fl_value_new_bool(fullscreen);
    fl_method_channel_invoke_method(self->channel, "fullscreenChanged", args,
                                    nullptr, nullptr, nullptr);
  }
  return FALSE;
}

static void update_visibility(VideoEmbed* self) {
  if (self->area == nullptr) return;
  if (self->rect.width > 0 && self->rect.height > 0) {
    gtk_widget_show(self->area);
    gtk_widget_queue_resize(self->overlay);
  } else {
    gtk_widget_hide(self->area);
  }
}

static double number_arg(FlValue* map, const char* key) {
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr) return 0;
  switch (fl_value_get_type(value)) {
    case FL_VALUE_TYPE_FLOAT:
      return fl_value_get_float(value);
    case FL_VALUE_TYPE_INT:
      return fl_value_get_int(value);
    default:
      return 0;
  }
}

static FlMethodResponse* create(VideoEmbed* self) {
#ifdef GDK_WINDOWING_X11
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(self->window));
  if (!GDK_IS_X11_DISPLAY(display)) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "unsupported", "Not running on X11 (e.g. Wayland)", nullptr));
  }
  if (self->area == nullptr) {
    self->area = gtk_drawing_area_new();
    gtk_widget_add_events(self->area, GDK_BUTTON_PRESS_MASK);
    g_signal_connect(self->area, "draw", G_CALLBACK(draw_cb), nullptr);
    g_signal_connect(self->area, "button-press-event",
                     G_CALLBACK(button_press_cb), self);
    gtk_overlay_add_overlay(GTK_OVERLAY(self->overlay), self->area);
    gtk_widget_realize(self->area);
  }
  GdkWindow* gdk_window = gtk_widget_get_window(self->area);
  if (gdk_window == nullptr || !gdk_window_ensure_native(gdk_window)) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "unsupported", "Could not create a native X11 window", nullptr));
  }
  Window xid = gdk_x11_window_get_xid(gdk_window);
  if (xid == 0) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "unsupported", "Could not get the X11 window id", nullptr));
  }
  update_visibility(self);
  g_autoptr(FlValue) result = fl_value_new_int(static_cast<int64_t>(xid));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
#else
  return FL_METHOD_RESPONSE(fl_method_error_response_new(
      "unsupported", "GTK was built without X11 support", nullptr));
#endif
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* call,
                           gpointer user_data) {
  VideoEmbed* self = static_cast<VideoEmbed*>(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "create") == 0) {
    response = create(self);
  } else if (strcmp(method, "setRect") == 0 &&
             fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    double x = number_arg(args, "x");
    double y = number_arg(args, "y");
    double right = x + number_arg(args, "width");
    double bottom = y + number_arg(args, "height");
    self->rect.x = static_cast<int>(std::round(x));
    self->rect.y = static_cast<int>(std::round(y));
    self->rect.width = static_cast<int>(std::round(right)) - self->rect.x;
    self->rect.height = static_cast<int>(std::round(bottom)) - self->rect.y;
    update_visibility(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "hide") == 0) {
    self->rect = {0, 0, 0, 0};
    update_visibility(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "setFullscreen") == 0 &&
             fl_value_get_type(args) == FL_VALUE_TYPE_BOOL) {
    if (fl_value_get_bool(args)) {
      gtk_window_fullscreen(self->window);
    } else {
      gtk_window_unfullscreen(self->window);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(call, response, &error)) {
    g_warning("video_embed: failed to respond: %s", error->message);
  }
}

static void video_embed_free(gpointer data) {
  VideoEmbed* self = static_cast<VideoEmbed*>(data);
  fl_method_channel_set_method_call_handler(self->channel, nullptr, nullptr,
                                            nullptr);
  g_clear_object(&self->channel);
  g_free(self);
}

void video_embed_new(GtkWindow* window, FlView* view) {
  VideoEmbed* self = g_new0(VideoEmbed, 1);
  self->window = window;
  self->view = view;

  self->overlay = gtk_overlay_new();
  gtk_widget_show(self->overlay);
  gtk_container_add(GTK_CONTAINER(self->overlay), GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), self->overlay);
  g_signal_connect(self->overlay, "get-child-position",
                   G_CALLBACK(get_child_position_cb), self);
  g_signal_connect(window, "window-state-event", G_CALLBACK(window_state_cb),
                   self);

  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel =
      fl_method_channel_new(messenger, kChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb,
                                            self, nullptr);
  // Freed together with the window.
  g_object_set_data_full(G_OBJECT(window), "tvplayer-video-embed", self,
                         video_embed_free);
}
