#include "legacy_keyring.h"

#include <libsecret/secret.h>

#include <cstring>

static const char kChannel[] = "tvplayer/legacy_keyring";

// The schema and attribute flutter_secure_storage_linux uses for an
// application ID; the label doubles as the schema name.
typedef struct {
  gchar* label;
  SecretSchema schema;
  GHashTable* attributes;
} Item;

static void item_init(Item* item, const char* id) {
  item->label = g_strdup_printf("%s/FlutterSecureStorage", id);
  item->schema = {item->label,
                  SECRET_SCHEMA_NONE,
                  {
                      {"account", SECRET_SCHEMA_ATTRIBUTE_STRING},
                      {nullptr, SECRET_SCHEMA_ATTRIBUTE_STRING},
                  }};
  item->attributes = g_hash_table_new_full(g_str_hash, g_str_equal, nullptr,
                                           g_free);
  g_hash_table_insert(item->attributes, const_cast<char*>("account"),
                      g_strdup_printf("%s.secureStorage", id));
}

static void item_clear(Item* item) {
  g_free(item->label);
  g_hash_table_unref(item->attributes);
}

// The stored value, or null when there is none. Free with secret_password_free.
static gchar* lookup(Item* item, GError** error) {
  return secret_password_lookupv_sync(&item->schema, item->attributes, nullptr,
                                      error);
}

static FlMethodResponse* error_response(GError* error) {
  return FL_METHOD_RESPONSE(fl_method_error_response_new(
      "keyring", error != nullptr ? error->message : "Keyring error",
      nullptr));
}

static FlMethodResponse* success(const char* result) {
  g_autoptr(FlValue) value = fl_value_new_string(result);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(value));
}

static FlMethodResponse* migrate(const char* legacy_id) {
  Item current, legacy;
  item_init(&current, APPLICATION_ID);
  item_init(&legacy, legacy_id);
  FlMethodResponse* response = nullptr;
  g_autoptr(GError) error = nullptr;
  gchar* existing = nullptr;
  gchar* old_value = nullptr;
  gchar* copy = nullptr;

  existing = lookup(&current, &error);
  if (error != nullptr) {
    response = error_response(error);
  } else if (existing != nullptr) {
    response = success("exists");
  } else if ((old_value = lookup(&legacy, &error)), error != nullptr) {
    response = error_response(error);
  } else if (old_value == nullptr) {
    response = success("none");
  } else if (!secret_password_storev_sync(&current.schema, current.attributes,
                                          nullptr, current.label, old_value,
                                          nullptr, &error)) {
    response = error_response(error);
  } else if ((copy = lookup(&current, &error)), error != nullptr) {
    response = error_response(error);
  } else if (copy == nullptr || strcmp(copy, old_value) != 0) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "keyring", "The copied keyring item did not read back the same",
        nullptr));
  } else {
    // Copied; a failure to clear the old item only leaves it behind.
    secret_password_clearv_sync(&legacy.schema, legacy.attributes, nullptr,
                                nullptr);
    response = success("migrated");
  }

  secret_password_free(existing);
  secret_password_free(old_value);
  secret_password_free(copy);
  item_clear(&current);
  item_clear(&legacy);
  return response;
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* call,
                           gpointer user_data) {
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "migrate") == 0 &&
      fl_value_get_type(args) == FL_VALUE_TYPE_STRING &&
      strcmp(fl_value_get_string(args), APPLICATION_ID) != 0) {
    response = migrate(fl_value_get_string(args));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(call, response, &error)) {
    g_warning("legacy_keyring: failed to respond: %s", error->message);
  }
}

void legacy_keyring_register(FlView* view) {
  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel =
      fl_method_channel_new(messenger, kChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, nullptr,
                                            nullptr);
  // Lives as long as the view.
  g_object_set_data_full(G_OBJECT(view), "tvplayer-legacy-keyring", channel,
                         g_object_unref);
}
