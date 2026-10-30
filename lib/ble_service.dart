import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService {
  static const serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const _nameUuid = '4fafc202-1fb5-459e-8fcc-c5c9c331914b';
  static const _battUuid = '4fafc203-1fb5-459e-8fcc-c5c9c331914b';
  static const _wifiUuid = '4fafc204-1fb5-459e-8fcc-c5c9c331914b';
  static const _notifUuid = '4fafc205-1fb5-459e-8fcc-c5c9c331914b';
  static const _cmdUuid = '4fafc206-1fb5-459e-8fcc-c5c9c331914b';
  static const _navUuid = '4fafc208-1fb5-459e-8fcc-c5c9c331914b'; // opsional, belum ada di firmware

  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? _name, _batt, _wifi, _notif, _cmd, _nav;
  Timer? _batteryTimer;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  Future<void> _tail = Future.value(); // Antrean tulis: Android tidak suka write paralel

  /// Dipanggil saat koneksi putus (termasuk ESP32 restart).
  VoidCallback? onDisconnected;

  String get deviceName => connectedDevice?.platformName.isNotEmpty == true
      ? connectedDevice!.platformName
      : 'ESP32-NAV';

  bool get isConnected => connectedDevice != null && _cmd != null;

  // ------------------------------------------------------------ connect
  Future<bool> connectToEsp32({Duration scanTimeout = const Duration(seconds: 6)}) async {
    BluetoothDevice? found;
    final done = Completer<BluetoothDevice?>();
    
    // Perbaikan: Pastikan kita mencari perangkat yang sesuai ("ESP32-NAV")
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final n = r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;
        if (n.startsWith('ESP32-NAV') && !done.isCompleted) done.complete(r.device);
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: scanTimeout);
      found = await done.future.timeout(scanTimeout, onTimeout: () => null);
    } catch (e) {
      debugPrint('Scan gagal: $e');
    }
    
    await FlutterBluePlus.stopScan();
    await sub.cancel();
    if (found == null) return false;

    try {
      await found.connect(license: License.nonprofit, timeout: const Duration(seconds: 15));
      connectedDevice = found;
      await _discoverServices();
      
      // Jika salah satu UUID perintah gagal ditemukan, batalkan.
      if (_cmd == null) throw 'Characteristic ESP32 tidak ditemukan';

      _connSub?.cancel();
      _connSub = found.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) _cleanup();
      });

      await Future.delayed(const Duration(milliseconds: 500)); // Beri waktu stack BLE ESP32
      await _sendNameAndBattery();
      return true;
    } catch (e) {
      debugPrint('Gagal terhubung: $e');
      await disconnectDevice();
      return false;
    }
  }

  Future<void> _discoverServices() async {
    final services = await connectedDevice!.discoverServices();
    for (final s in services) {
      if (s.uuid.str128.toLowerCase() != serviceUuid) continue;
      for (final c in s.characteristics) {
        switch (c.uuid.str128.toLowerCase()) {
          case _nameUuid: _name = c;
          case _battUuid: _batt = c;
          case _wifiUuid: _wifi = c;
          case _notifUuid: _notif = c;
          case _cmdUuid: _cmd = c;
          case _navUuid: _nav = c;
        }
      }
    }
  }

  // ------------------------------------------------------------ tulis
  Future<bool> _write(BluetoothCharacteristic? c, String text) {
    // Memasukkan pengiriman data ke dalam antrean (queue)
    final result = _tail.then((_) async {
      if (c == null || connectedDevice == null) return false;
      try {
        // PERBAIKAN FATAL: "withoutResponse" sekarang menjadi false (menyesuaikan dengan ESP32)
        // PERBAIKAN FATAL: Menghilangkan "allowLongWrites: true" yang menjadi sumber error sebelumnya
        await c.write(utf8.encode(text), withoutResponse: false);
        return true;
      } catch (e) {
        debugPrint('Write gagal: $e');
        return false;
      }
    });
    _tail = result.then((_) {});
    return result;
  }

  Future<void> _sendNameAndBattery() async {
    var name = 'HP';
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      name = '${a.brand} ${a.model}';
    } else if (Platform.isIOS) {
      name = (await info.iosInfo).name;
    }
    
    // Kirim Nama dan Baterai (masuk antrean)
    await _write(_name, name);
    await _sendBattery();
    
    // Ulangi kirim baterai setiap 60 detik
    _batteryTimer?.cancel();
    _batteryTimer = Timer.periodic(const Duration(seconds: 60), (_) => _sendBattery());
  }

  Future<void> _sendBattery() async {
    final level = await Battery().batteryLevel;
    await _write(_batt, level.toString());
  }

  Future<bool> sendWifiCredentials(String ssid, String password) => _write(_wifi, '$ssid|$password');

  /// Baca IP Wi-Fi dari ESP32 lewat characteristic c204.
  /// Mengembalikan null kalau belum ada IP atau pembacaan gagal.
  Future<String?> readWifiIp() {
    // Lewat antrean yang sama dengan _write, supaya operasi BLE tidak tumpang tindih
    final result = _tail.then<String?>((_) async {
      final c = _wifi;
      if (c == null || connectedDevice == null) return null;
      try {
        final bytes = await c.read();
        final ip = utf8.decode(bytes, allowMalformed: true).trim();
        return ip.isEmpty ? null : ip;
      } catch (e) {
        debugPrint('Read IP gagal: $e');
        return null;
      }
    });
    _tail = result.then((_) {});
    return result;
  }

  /// RESTART, THEME_DARK, THEME_LIGHT, QUALITY_85, INTERVAL_0.5, dst.
  Future<bool> sendCommand(String cmd) => _write(_cmd, cmd);

  /// Teks notifikasi HP -> halaman Notify di ESP32 (maks 200 karakter).
  Future<bool> sendNotification(String text) =>
      _write(_notif, text.length > 200 ? text.substring(0, 200) : text);

  /// Instruksi navigasi. Kalau firmware belum punya characteristic c208,
  /// sementara dikirim lewat characteristic notifikasi dengan awalan "NAV:".
  Future<bool> sendNav(String text) =>
      _nav != null ? _write(_nav, text) : sendNotification('NAV: $text');

  // ------------------------------------------------------------ putus
  void _cleanup() {
    _batteryTimer?.cancel();
    _connSub?.cancel();
    connectedDevice = null;
    _name = _batt = _wifi = _notif = _cmd = _nav = null;
    onDisconnected?.call();
  }

  Future<void> disconnectDevice() async {
    final d = connectedDevice;
    try {
      await d?.disconnect();
    } catch (_) {}
    if (connectedDevice != null) _cleanup();
  }
}

final bleService = BleService();