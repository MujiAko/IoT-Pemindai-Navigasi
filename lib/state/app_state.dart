import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ble_service.dart';
import '../services/nav_instructor.dart';
import '../services/notification_forwarder.dart';

enum RouteProfile { driving, walking, cycling }

enum MapStyle { osm, cartoLight, cartoDark }

extension RouteProfileX on RouteProfile {
  String get label => const ['Driving', 'Walking', 'Cycling'][index];
}

extension MapStyleX on MapStyle {
  String get label => const ['OpenStreetMap', 'Carto Light', 'Carto Dark'][index];
  String get url => const [
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
        'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
      ][index];
  List<String> get subdomains => this == MapStyle.osm ? const [] : const ['a', 'b', 'c', 'd'];
}

class AppState extends ChangeNotifier {
  AppState() {
    // ESP32 putus sendiri (mati, restart, keluar jangkauan) -> tampilan ikut berubah.
    bleService.onDisconnected = () {
      bleConnected = false;
      syncReady = false;
      wifiIp = null;
      wifiSentSsid = null;
      deviceName = 'Tidak Terhubung';
      notifyListeners();
    };
    // Getar saat berpindah ke manuver berikutnya (kalau Haptic feedback aktif).
    nav.onStepChanged = () {
      if (haptic) HapticFeedback.mediumImpact();
    };
  }

  final NavInstructor nav = NavInstructor();
  late final NotificationForwarder _forwarder = NotificationForwarder(this);

  // App settings
  ThemeMode themeMode = ThemeMode.light;
  MapStyle mapStyle = MapStyle.osm;
  RouteProfile profile = RouteProfile.driving;
  bool haptic = true;
  bool forwardNotifications = true;
  bool notificationAccess = false; // dibaca dari izin Notification Listener Android
  String notificationDuration = 'Dynamic (auto)'; // belum didukung firmware
  Map<String, String> notifApps = {}; // packageName -> nama aplikasi (whitelist)
  int get whitelistedApps => notifApps.length;

  // ESP32 status (data asli via BLE)
  String deviceName = 'Tidak Terhubung';
  bool bleConnected = false;
  bool connecting = false;
  String? wifiIp; // diisi dari characteristic status firmware (c207), null = belum tersambung
  String? wifiSentSsid; // SSID terakhir yang dikirim ke ESP32 (firmware lama tidak melaporkan hasilnya)
  bool syncReady = false;

  // Pengaturan ESP32. Nilai awal disamakan dengan default firmware
  // (tema terang, kualitas 65, interval 1 detik).
  final Map<String, String> esp = {
    'WiFi mode': 'External WiFi — ESP32 connects to saved network',
    'Screen Orientation': 'Reverse Landscape',
    'Screen Theme': 'Terang',
    'Map update': '1s refresh interval',
    'Image quality': 'Medium (65)',
  };

  /// Perintah firmware untuk tiap pengaturan. null = belum didukung firmware
  /// (Screen Orientation dan WiFi mode hanya tersimpan di HP).
  String? _commandFor(String label, String value) {
    switch (label) {
      case 'Screen Theme':
        return value == 'Gelap' ? 'THEME_DARK' : 'THEME_LIGHT';
      case 'Image quality':
        final m = RegExp(r'\((\d+)\)').firstMatch(value);
        return m == null ? null : 'QUALITY_${m.group(1)}';
      case 'Map update':
        final m = RegExp(r'^([\d.]+)s').firstMatch(value);
        return m == null ? null : 'INTERVAL_${m.group(1)}';
    }
    return null;
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[p.getInt('theme') ?? 1];
    mapStyle = MapStyle.values[p.getInt('mapStyle') ?? 0];
    profile = RouteProfile.values[p.getInt('profile') ?? 0];
    haptic = p.getBool('haptic') ?? true;
    forwardNotifications = p.getBool('fwd') ?? true;
    for (final k in esp.keys.toList()) {
      esp[k] = p.getString('esp_$k') ?? esp[k]!;
    }
    try {
      final raw = p.getString('notifApps');
      if (raw != null) notifApps = Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {}
    notifyListeners();
    _forwarder.start(); // cek izin notifikasi & mulai meneruskan
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('theme', themeMode.index);
    await p.setInt('mapStyle', mapStyle.index);
    await p.setInt('profile', profile.index);
    await p.setBool('haptic', haptic);
    await p.setBool('fwd', forwardNotifications);
    for (final e in esp.entries) {
      await p.setString('esp_${e.key}', e.value);
    }
    await p.setString('notifApps', jsonEncode(notifApps));
  }

  void update(void Function() fn) {
    fn();
    notifyListeners();
    _save();
  }

  String get statusLabel => !bleConnected ? 'Disconnected' : (syncReady ? 'Ready' : 'Syncing');

  // ------------------------------------------------------------- koneksi BLE
  Future<void> toggleConnection() async {
    if (connecting) return;

    if (bleConnected) {
      await bleService.disconnectDevice();
      update(() {
        bleConnected = false;
        wifiIp = null;
        wifiSentSsid = null;
        syncReady = false;
        deviceName = 'Tidak Terhubung';
      });
      return;
    }

    connecting = true;
    update(() => deviceName = 'Mencari ESP32...');

    // connectToEsp32 sudah menunggu scan + connect + kirim nama HP & baterai,
    // jadi tidak perlu menunggu waktu tetap lagi.
    final ok = await bleService.connectToEsp32();
    connecting = false;

    if (ok && bleService.connectedDevice != null) {
      update(() {
        bleConnected = true;
        syncReady = true;
        deviceName = bleService.deviceName;
      });
      await _syncSettingsToEsp();
      startWifiPolling(); // ESP32 mungkin sudah tersambung Wi-Fi dari pengaturan tersimpan
    } else {
      update(() {
        bleConnected = false;
        syncReady = false;
        deviceName = 'Gagal Terhubung';
      });
    }
  }

  /// Kirim pengaturan tersimpan supaya layar ESP32 cocok dengan aplikasi.
  Future<void> _syncSettingsToEsp() async {
    for (final e in esp.entries) {
      final cmd = _commandFor(e.key, e.value);
      if (cmd != null) await bleService.sendCommand(cmd);
    }
  }

  /// Baca IP ESP32 dari characteristic status tiap 2 detik (maks. ~30 detik).
  /// Berhenti kalau firmware belum punya characteristic itu.
  Future<void> startWifiPolling() async {
    for (var i = 0; i < 15 && bleConnected; i++) {
      final ip = await bleService.readWifiIp();
      if (ip == null) return; // firmware belum punya characteristic status (c207)
      final baru = ip.isEmpty ? null : ip;
      if (baru != wifiIp) {
        wifiIp = baru;
        notifyListeners();
      }
      if (baru != null) return;
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  // ------------------------------------------------------------- perintah ESP32
  Future<void> restartEsp() async {
    if (bleConnected) await bleService.sendCommand('RESTART');
  }

  /// Simpan pilihan pengaturan ESP32, dan kirim ke perangkat kalau sedang terhubung.
  Future<void> setEsp(String label, String value) async {
    update(() => esp[label] = value);
    final cmd = _commandFor(label, value);
    if (bleConnected && cmd != null) await bleService.sendCommand(cmd);
  }

  // ------------------------------------------------------------- Wi-Fi
  void markWifiSent(String ssid) {
    wifiSentSsid = ssid;
    notifyListeners();
  }

  // ------------------------------------------------------------- notifikasi
  Future<void> refreshNotificationAccess() async {
    var ok = false;
    try {
      ok = await NotificationListenerService.isPermissionGranted();
    } catch (_) {}
    if (ok != notificationAccess) {
      notificationAccess = ok;
      notifyListeners();
    }
    if (ok) _forwarder.ensureListening();
  }

  /// Membuka pengaturan "Notification access" Android, lalu cek ulang.
  Future<void> requestNotificationAccess() async {
    try {
      await NotificationListenerService.requestPermission();
    } catch (_) {}
    await refreshNotificationAccess();
  }

  void setNotifApp(String packageName, String label, bool on) {
    update(() {
      if (on) {
        notifApps[packageName] = label;
      } else {
        notifApps.remove(packageName);
      }
    });
  }
}