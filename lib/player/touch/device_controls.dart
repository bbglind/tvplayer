import 'dart:async';

import 'package:flutter/services.dart';

/// The phone around the touch player: screen orientation and system bars,
/// the media volume and the brightness of the app window. Levels are 0–1.
abstract interface class DeviceControls {
  /// Landscape, fullscreen without system bars.
  Future<void> enterPlayer();

  /// Back to portrait with the system bars, and the window's brightness
  /// back to the phone's.
  Future<void> leavePlayer();

  /// The phone's media volume; null when it can't be read.
  Future<double?> mediaVolume();
  Future<void> setMediaVolume(double level);

  /// The app window's brightness, else the phone's; null when unknown.
  Future<double?> brightness();

  /// Sets the brightness of the app window only.
  Future<void> setBrightness(double level);
}

/// [DeviceControls] of the Android app (see MainActivity.kt).
class AndroidDeviceControls implements DeviceControls {
  static const _channel = MethodChannel('tvplayer/device');

  /// How long the turn to portrait may take before the app may turn with
  /// the phone again.
  static const _turnBack = Duration(seconds: 2);

  Timer? _release;

  @override
  Future<void> enterPlayer() async {
    _release?.cancel();
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  Future<void> leavePlayer() async {
    await _call('resetBrightness');
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    // Then as before the player: the other screens turn with the phone.
    _release?.cancel();
    _release = Timer(
      _turnBack,
      () => unawaited(SystemChrome.setPreferredOrientations(const [])),
    );
  }

  @override
  Future<double?> mediaVolume() => _call<double>('getMediaVolume');

  @override
  Future<void> setMediaVolume(double level) =>
      _call('setMediaVolume', {'level': level});

  @override
  Future<double?> brightness() => _call<double>('getBrightness');

  @override
  Future<void> setBrightness(double level) =>
      _call('setBrightness', {'level': level});

  static Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
