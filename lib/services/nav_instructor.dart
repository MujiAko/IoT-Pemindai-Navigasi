import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../ble_service.dart';
import 'map_service.dart';

/// Mengirim instruksi belok-per-belok ke ESP32 sebagai teks.
/// Firmware yang ada belum punya characteristic khusus navigasi, jadi `bleService.sendNav`
/// memakai characteristic notifikasi dengan awalan "NAV: " (tampil di halaman Notify ESP32).
class NavInstructor extends ChangeNotifier {
  static const _distance = Distance();

  RouteResult? _route;
  int _next = 1; // indeks langkah (manuver) berikutnya
  String? _lastSent;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool active = false;
  String lastText = '';

  /// Dipanggil saat berpindah ke manuver berikutnya (untuk getar/haptic).
  VoidCallback? onStepChanged;

  void start(RouteResult route) {
    if (route.steps.length < 2) return;
    _route = route;
    _next = 1;
    _lastSent = null;
    lastText = '';
    active = true;
    notifyListeners();
  }

  void stop() {
    if (!active) return;
    active = false;
    _route = null;
    lastText = '';
    notifyListeners();
  }

  void updatePosition(LatLng me) {
    final route = _route;
    if (!active || route == null) return;
    final steps = route.steps;

    // Maju ke manuver berikutnya kalau titik ini sudah dilewati (< 25 m).
    var moved = false;
    while (_next < steps.length - 1 && _distance.distance(me, steps[_next].location) < 25) {
      _next++;
      moved = true;
    }
    if (moved) onStepChanged?.call();

    final step = steps[_next];
    final d = _distance.distance(me, step.location);

    if (step.type == 'arrive' && d < 25) {
      lastText = 'Tiba di tujuan';
      _send(lastText, force: true);
      onStepChanged?.call();
      stop();
      return;
    }

    final road = _ascii(step.name);
    final text = step.type == 'arrive'
        ? 'Tujuan ${_fmt(d)}'
        : '${step.instruction} ${_fmt(d)}${road.isEmpty ? '' : ' - $road'}';
    if (text != lastText) {
      lastText = text;
      notifyListeners();
    }
    _send(text);
  }

  void _send(String text, {bool force = false}) {
    if (!bleService.isConnected) return;
    final now = DateTime.now();
    // Teks berubah hanya saat jarak (yang sudah dibulatkan) atau manuver berganti,
    // ditambah jeda minimal 2 detik supaya BLE tidak kebanjiran.
    if (!force && (text == _lastSent || now.difference(_lastSentAt).inSeconds < 2)) return;
    _lastSent = text;
    _lastSentAt = now;
    unawaited(bleService.sendNav(text));
  }

  static String _fmt(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
    if (m >= 100) return '${(m / 50).round() * 50} m';
    return '${(m / 10).round() * 10} m';
  }

  /// Layar ESP32 memakai font ASCII, jadi karakter lain dibuang.
  static String _ascii(String s) => s.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
}