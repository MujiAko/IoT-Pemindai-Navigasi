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
// Start/stop diatur AppState: start saat IP WiFi ESP32 ketahuan (c207),
// stop saat BLE putus. Interval + kualitas ngikutin setting ESP32 yang udah
// ada di aplikasi (Map update + Image quality).
//
// Butuh di pubspec.yaml:
//   image: ^4.0.0
//
// Syarat saat jalan: HP dan ESP32 satu jaringan yang sama (hotspot HP atau
// WiFi rumah), DAN tab Map lagi dibuka di aplikasi (peta harus ke-render
// supaya bisa di-capture), layar HP nyala.

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

  bool get running => _timer != null;

  static const int port = 8080;

  /// Buka socket ke ESP32 lalu kirim frame tiap [interval].
  /// Mengembalikan false kalau socket gagal dibuka (ESP32 belum siap / beda
  /// jaringan). Panggil lagi nanti (mis. di polling WiFi berikutnya).
  Future<bool> start({
    required String espIp,
    Duration interval = const Duration(seconds: 1),
    int quality = 65,
  }) async {
    await stop();
    try {
      _socket = await Socket.connect(
        espIp,
        port,
        timeout: const Duration(seconds: 5),
      );
      _espIp = espIp;
      _timer = Timer.periodic(interval, (_) => _sendFrame(quality));
      return true;
    } catch (_) {
      await stop();
      return false;
    }
  }

  Future<void> _sendFrame(int quality) async {
    if (_sending) {
      // ignore: avoid_print
      print('[MapStreamer] skip, frame sebelumnya belum selesai');
      return;
    }
    _sending = true;
    try {
      // Socket mati (mis. firmware buang client karena frame rusak):
      // sambung ulang dulu, kalau gagal coba lagi di tick berikut.
      if (_socket == null) {
        if (_espIp == null) return;
        try {
          _socket = await Socket.connect(
            _espIp!,
            port,
            timeout: const Duration(seconds: 5),
          );
        } catch (_) {
          return;
        }
      }
      final boundary =
          mapBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      // ignore: avoid_print
      print('[MapStreamer] tick, boundary=${boundary == null ? "NULL" : "ok"}');
      if (boundary == null) return; // tab Map belum dibuka / belum ke-render
      final image = await boundary
          .toImage(pixelRatio: 1.0)
          // Jangan sampai nyangkut selamanya pas peta lagi di-geser:
          // kalau capture tidak selesai dalam 3 detik, lempar error
          // supaya _sending ke-reset dan tick berikut coba lagi.
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
      // ignore: avoid_print
      print('[MapStreamer] jpg ${jpg.length} byte, kirim ke $_espIp:$port');
      final header = ByteData(4)..setUint32(0, jpg.length, Endian.big);
      _socket!.add(header.buffer.asUint8List());
      _socket!.add(jpg);
      await _socket!
          .flush()
          // Jangan sampai nyangkut selamanya kalau ESP32 berhenti baca
          // (buffer socket penuh): timeout -> error -> socket ditutup
          // dan sambung ulang di tick berikut.
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      // ignore: avoid_print
      print('[MapStreamer] ERROR $e');
      // Kirim gagal (socket putus di tengah jalan): tutup, tick berikut
      // sambung ulang otomatis. Satu frame gagal biasa (mis. tab Map baru
      // ditutup) juga ketangkep di sini dan dicoba lagi interval berikut.
      try {
        await _socket?.close();
      } catch (_) {}
      _socket = null;
    } finally {
      _sending = false;
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _espIp = null;
    // Reset juga flag kirim: kalau _sendFrame sempat nyangkut, stop()
    // harus bersihin flag-nya supaya start() berikutnya bisa jalan lagi.
    _sending = false;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}
