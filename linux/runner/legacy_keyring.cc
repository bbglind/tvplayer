#include "legacy_keyring.h"

#include <libsecret/secret.h>

#include <cstring>

static const char kChannel[] = "tvplayer/legacy_keyring";

// flutter_secure_storage_linux 3.0.3 keeps its schema name as a pointer into
// a std::string it reassigns afterwards, so items carry an arbitrary
// xdg:schema (e.g. ")"). Match on the "account" attribute alone.
static const SecretSchema kSchema = {
    "tvplayer.LegacyFlutterSecureStorage",
    SECRET_SCHEMA_DONT_MATCH_NAME,
    {
        {"account", SECRET_SCHEMA_ATTRIBUTE_STRING},
        {nullptr, SECRET_SCHEMA_ATTRIBUTE_STRING},
    }};

static GHashTable* attributes_new(const char* id) {
  GHashTable* attributes =
      g_hash_table_new_full(g_str_hash, g_str_equal, nullptr, g_free);
  g_hash_table_insert(attributes, const_cast<char*>("account"),
                      g_strdup_printf("%s.secureStorage", id));
  return attributes;
}

static FlMethodResponse* error_response(GError* error) {
  return FL_METHOD_RESPONSE(fl_method_error_response_new(
      "keyring", error != nullptr ? error->message : "Keyring error",
      nullptr));
}

static FlMethodResponse* read(const char* legacy_id) {
  g_autoptr(GHashTable) attributes = attributes_new(legacy_id);
  g_autoptr(GError) error = nullptr;
  gchar* value =
      secret_password_lookupv_sync(&kSchema, attributes, nullptr, &error);
  if (error != nullptr) return error_response(error);
  g_autoptr(FlValue) result =
      value != nullptr ? fl_value_new_string(value) : fl_value_new_null();
  secret_password_free(value);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* clear(const char* legacy_id) {
  g_autoptr(GHashTable) attributes = attributes_new(legacy_id);
  g_autoptr(GError) error = nullptr;
  secret_password_clearv_sync(&kSchema, attributes, nullptr, &error);
  if (error != nullptr) return error_response(error);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* call,
                           gpointer user_data) {
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;

  // Never touch the current ID's item.
  const bool legacy_arg = fl_value_get_type(args) == FL_VALUE_TYPE_STRING &&
                          strcmp(fl_value_get_string(args), APPLICATION_ID) != 0;
  if (legacy_arg && strcmp(method, "read") == 0) {
    response = read(fl_value_get_string(args));
  } else if (legacy_arg && strcmp(method, "clear") == 0) {
    response = clear(fl_value_get_string(args));
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
