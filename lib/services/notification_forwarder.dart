import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import '../ble_service.dart';
import '../state/app_state.dart';

/// Meneruskan notifikasi HP (hanya dari aplikasi yang di-whitelist) ke ESP32 lewat BLE.
class NotificationForwarder {
  NotificationForwarder(this._app);

  final AppState _app;
  StreamSubscription<dynamic>? _sub;
  AppLifecycleListener? _lifecycle;
  String _lastText = '';
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> start() async {
    // Cek ulang izin setiap aplikasi kembali dibuka (pengguna baru saja mengaktifkannya di Pengaturan).
    _lifecycle ??= AppLifecycleListener(onResume: () => _app.refreshNotificationAccess());
    await _app.refreshNotificationAccess();
  }

  /// Dipanggil AppState setelah izin diberikan. Aman dipanggil berulang.
  void ensureListening() {
    if (_sub != null) return;
    _sub = NotificationListenerService.notificationsStream.listen(
      (event) => _handle(event.packageName, event.title, event.content, event.hasRemoved),
      onError: (_) {},
    );
  }

  void _handle(String? pkg, String? title, String? content, bool removed) {
    if (removed || pkg == null) return;
    if (!_app.forwardNotifications || !bleService.isConnected) return;

    final appName = _app.notifApps[pkg];
    if (appName == null) return; // bukan aplikasi di whitelist

    final body = [title, content].whereType<String>().where((s) => s.trim().isNotEmpty).join(' - ');
    if (body.isEmpty) return;

    // Layar ESP32 memakai font ASCII: buang emoji dan karakter lain.
    final text = '$appName: $body'.replaceAll(RegExp(r'[^\x20-\x7E]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return;

    // Banyak aplikasi memposting ulang notifikasi yang sama beruntun.
    final now = DateTime.now();
    if (text == _lastText && now.difference(_lastAt).inSeconds < 5) return;
    _lastText = text;
    _lastAt = now;

    bleService.sendNotification(text);
  }
}