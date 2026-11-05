// MapStreamer: tangkap peta yang tampil di HP, kirim sebagai JPEG ke ESP32
// lewat socket TCP (WiFi), supaya halaman Navigate di LCD nunjukin peta yang
// sama kayak di HP.
//
// Alur:
//   MapPage membungkus FlutterMap dengan RepaintBoundary(key: mapBoundaryKey)
//   -> tiap interval, boundary di-capture -> PNG -> resize/crop ke 320x240
//   (ukuran LCD, rotation 1 = landscape) -> encode JPEG -> kirim ke ESP32
//   dengan header 4 byte (panjang JPEG, big-endian) + isi JPEG.
//
// Start/stop diatur AppState: start saat IP WiFi ESP32 ketahuan (c207), stop
// saat BLE putus. Interval + kualitas ngikutin setting ESP32 di aplikasi.
//
// Butuh di pubspec.yaml:
//   image: ^4.0.0
//
// Syarat saat jalan: HP dan ESP32 satu jaringan yang sama, DAN tab Map lagi
// dibuka di aplikasi (peta harus ke-render supaya bisa di-capture), layar HP
// nyala.
//
// Perubahan dari versi sebelumnya:
//  - Socket ditutup pakai destroy(), BUKAN close(). close() menunggu data yang
//    belum terkirim; kalau ESP32 berhenti membaca, dia bisa menggantung lama,
//    _sending nyangkut true, dan reconnect tidak pernah jalan.
//  - Socket didengarkan (listen) supaya kalau ESP32 memutus koneksi, langsung
//    ketahuan dan tick berikut sambung ulang.
//  - Timeout flush 3 dtk -> 10 dtk. Frame 16 KB lewat WiFi yang lagi rebutan
//    radio dengan BLE kadang butuh 2-3 dtk; 3 dtk bikin aplikasi sendiri yang
//    memutus koneksi di tengah frame.
//  - tcpNoDelay + jeda minimal antar percobaan connect.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

/// Key untuk RepaintBoundary di MapPage. Pasang di sana:
///   RepaintBoundary(key: mapBoundaryKey, child: FlutterMap(...))
final GlobalKey mapBoundaryKey = GlobalKey();

class MapStreamer {
  Socket? _socket;
  Timer? _timer;
  bool _sending = false;
  String? _espIp; // IP ESP32, buat sambung ulang kalau socket diputus firmware
  DateTime _terakhirCoba = DateTime.fromMillisecondsSinceEpoch(0);

  bool get running => _timer != null;

  static const int port = 8080;
  static const Duration _connectTimeout = Duration(seconds: 5);
  static const Duration _flushTimeout = Duration(seconds: 10);
  static const Duration _jedaCoba = Duration(seconds: 2);

  /// Buka koneksi ke ESP32. Mengembalikan null kalau gagal.
  Future<Socket?> _connect(String ip) async {
    try {
      final s = await Socket.connect(ip, port, timeout: _connectTimeout);
      s.setOption(SocketOption.tcpNoDelay, true);
      // Dengarkan socket supaya putus dari sisi ESP32 langsung ketahuan.
      // ESP32 tidak mengirim apa-apa ke HP, jadi data masuk diabaikan.
      s.listen(
        (_) {},
        onError: (_) => _drop(s),
        onDone: () => _drop(s),
        cancelOnError: true,
      );
      // Cegah error "done" tidak tertangani saat socket putus mendadak.
      s.done.catchError((_) {});
      return s;
    } catch (_) {
      return null;
    }
  }

  /// Tutup socket langsung (destroy, bukan close) dan lupakan kalau itu
  /// socket yang sedang dipakai.
  void _drop(Socket s) {
    try {
      s.destroy();
    } catch (_) {}
    if (identical(_socket, s)) _socket = null;
  }

  /// Buka socket ke ESP32 lalu kirim frame tiap [interval].
  /// Mengembalikan false kalau socket gagal dibuka (ESP32 belum siap / beda
  /// jaringan). Panggil lagi nanti (mis. di polling WiFi berikutnya).
  Future<bool> start({
    required String espIp,
    Duration interval = const Duration(seconds: 1),
    int quality = 65,
  }) async {
    await stop();
    final s = await _connect(espIp);
    if (s == null) return false;
    _socket = s;
    _espIp = espIp;
    _timer = Timer.periodic(interval, (_) => _sendFrame(quality));
    return true;
  }

  Future<void> _sendFrame(int quality) async {
    if (_sending) {
      // ignore: avoid_print
      print('[MapStreamer] skip, frame sebelumnya belum selesai');
      return;
    }
    _sending = true;
    try {
      // Socket mati (mis. firmware buang client): sambung ulang. Kalau gagal,
      // coba lagi di tick berikut (dengan jeda minimal supaya tidak spam).
      if (_socket == null) {
        final ip = _espIp;
        if (ip == null) return;
        if (DateTime.now().difference(_terakhirCoba) < _jedaCoba) return;
        _terakhirCoba = DateTime.now();
        final s = await _connect(ip);
        if (s == null) return;
        if (_timer == null) {
          // stop() dipanggil selama kita menunggu connect
          s.destroy();
          return;
        }
        _socket = s;
        // ignore: avoid_print
        print('[MapStreamer] sambung ulang ke $ip:$port');
      }

      final boundary =
          mapBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      // ignore: avoid_print
      print('[MapStreamer] tick, boundary=${boundary == null ? "NULL" : "ok"}');
      if (boundary == null) return; // tab Map belum dibuka / belum ke-render
      final image = await boundary
          .toImage(pixelRatio: 1.0)
          // Jangan sampai nyangkut selamanya pas peta lagi di-geser.
          .timeout(const Duration(seconds: 3));
      // ignore: avoid_print
      print('[MapStreamer] captured ${image.width}x${image.height}');
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return;
      final decoded = img.decodePng(png.buffer.asUint8List());
      if (decoded == null) return;

      // LCD 320x240 landscape: resize jaga aspek, lalu crop tengah ke 320x240.
      var frame = img.copyResize(decoded, width: 320);
      if (frame.height < 240) frame = img.copyResize(decoded, height: 240);
      if (frame.width > 320 || frame.height > 240) {
        frame = img.copyCrop(
          frame,
          x: (frame.width - 320) ~/ 2,
          y: (frame.height - 240) ~/ 2,
          width: 320,
          height: 240,
        );
      }

      final jpg = img.encodeJpg(frame, quality: quality);

      // Socket bisa saja sudah di-drop selama proses encode di atas.
      final sock = _socket;
      if (sock == null) return;

      // ignore: avoid_print
      print('[MapStreamer] jpg ${jpg.length} byte, kirim ke $_espIp:$port');
      final header = ByteData(4)..setUint32(0, jpg.length, Endian.big);
      sock.add(header.buffer.asUint8List());
      sock.add(jpg);
      await sock.flush().timeout(_flushTimeout);
    } catch (e) {
      // ignore: avoid_print
      print('[MapStreamer] ERROR $e');
      // Kirim gagal / macet: putus total (destroy) supaya tidak menggantung,
      // tick berikut sambung ulang otomatis.
      final s = _socket;
      if (s != null) _drop(s);
    } finally {
      _sending = false;
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _espIp = null;
    // Reset juga flag kirim supaya start() berikutnya bisa jalan lagi.
    _sending = false;
    final s = _socket;
    _socket = null;
    if (s != null) {
      try {
        s.destroy();
      } catch (_) {}
    }
  }
}