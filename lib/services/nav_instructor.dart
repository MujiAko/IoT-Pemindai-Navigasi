import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../ble_service.dart';
import 'map_service.dart';

/// Mengirim instruksi belok-per-belok ke ESP32 sebagai teks.
/// Firmware yang ada belum punya characteristic khusus navigasi, jadi `bleService.sendNav`
/// memakai characteristic notifikasi dengan awalan "NAV: " (tampil di halaman Notify ESP32).
/// Selain itu, info bar bawah LCD (sisa jarak, kecepatan, ETA) dikirim lewat
/// characteristic c209 (`bleService.sendNavInfo`, firmware v1.2.2).
class NavInstructor extends ChangeNotifier {
  static const _distance = Distance();

  RouteResult? _route;
  int _next = 1; // indeks langkah (manuver) berikutnya
  String? _lastSent;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Buat info bar bawah LCD (c209): kecepatan + sisa jarak + ETA.
  LatLng? _lastPos;
  DateTime _lastPosAt = DateTime.fromMillisecondsSinceEpoch(0);
  double _speedKmh = 0;
  String? _lastNavInfoSent;
  DateTime _lastNavInfoAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _arrived = false;

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
    _lastPos = null;
    _speedKmh = 0;
    _lastNavInfoSent = null;
    _arrived = false;
    active = true;
    notifyListeners();
  }

  void stop() {
    if (!active) return;
    active = false;
    _route = null;
    lastText = '';
    // Bar bawah LCD: sampai tujuan tampil 0, batal navigasi tampil "-".
    if (bleService.isConnected) {
      unawaited(bleService.sendNavInfo(_arrived ? '0|0|0' : '-1|-1|-1'));
    }
    _arrived = false;
    _lastNavInfoSent = null;
    notifyListeners();
  }

  void updatePosition(LatLng me, {double? speedMps}) {
    final route = _route;
    if (!active || route == null) return;
    final steps = route.steps;

    // Kecepatan: pakai speed GPS kalau caller ngasih, kalau tidak hitung
    // dari perpindahan posisi (dengan peredam noise GPS saat diam).
    final now = DateTime.now();
    if (speedMps != null) {
      _speedKmh = speedMps * 3.6;
      _lastPos = me;
      _lastPosAt = now;
    } else if (_lastPos == null) {
      _lastPos = me;
      _lastPosAt = now;
    } else {
      final dt = now.difference(_lastPosAt).inMilliseconds / 1000.0;
      if (dt >= 1.0) {
        final moved = _distance.distance(_lastPos!, me);
        final raw = moved < 3 ? 0.0 : (moved / dt) * 3.6;
        _speedKmh = _speedKmh * 0.6 + raw * 0.4; // rata-rata bergerak
        _lastPos = me;
        _lastPosAt = now;
      }
    }

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
      _arrived = true;
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

    // Info bar bawah LCD (c209): sisa jarak rute + kecepatan + ETA.
    double remaining = _distance.distance(me, steps[_next].location);
    for (var k = _next; k < steps.length - 1; k++) {
      remaining += _distance.distance(steps[k].location, steps[k + 1].location);
    }
    // ETA dari kecepatan sekarang; kalau pelan/berhenti, ETA tidak diketahui.
    final etaMin = _speedKmh > 5 ? (remaining / 1000 / _speedKmh * 60).round() : -1;
    _sendNavInfo(remaining.round(), _speedKmh.round(), etaMin);
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

  /// Kirim "sisaMeter|kmh|etaMenit" ke c209, paling cepat tiap 2 detik
  /// dan hanya kalau nilainya berubah (sudah dibulatkan ke int).
  void _sendNavInfo(int sisa, int kmh, int eta) {
    if (!bleService.isConnected) return;
    final text = '$sisa|$kmh|$eta';
    final now = DateTime.now();
    if (text == _lastNavInfoSent) return;
    if (now.difference(_lastNavInfoAt).inSeconds < 2) return;
    _lastNavInfoSent = text;
    _lastNavInfoAt = now;
    unawaited(bleService.sendNavInfo(text));
  }

  static String _fmt(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
    if (m >= 100) return '${(m / 50).round() * 50} m';
    return '${(m / 10).round() * 10} m';
  }

  /// Layar ESP32 memakai font ASCII, jadi karakter lain dibuang.
  static String _ascii(String s) => s.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
}
