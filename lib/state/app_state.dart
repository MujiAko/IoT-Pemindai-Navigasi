import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  // App settings
  ThemeMode themeMode = ThemeMode.light;
  MapStyle mapStyle = MapStyle.osm;
  RouteProfile profile = RouteProfile.driving;
  bool haptic = true;
  bool forwardNotifications = true;
  bool notificationAccess = true; // TODO: baca status asli dari plugin notification listener
  String notificationDuration = 'Dynamic (auto)';
  int whitelistedApps = 1;

  // ESP32 status (TODO: hubungkan ke flutter_blue_plus + HTTP ke ESP32)
  String deviceName = 'ESP32-NAV-FD8C';
  bool bleConnected = true;
  String? wifiIp = '10.146.223.212';
  bool syncReady = true;

  // ESP32 preferences
  final Map<String, String> esp = {
    'WiFi mode': 'External WiFi — ESP32 connects to saved network',
    'Screen Orientation': 'Reverse Landscape',
    'Screen Theme': 'Gelap',
    'Map update': '1s refresh interval',
    'Image quality': 'High (85)',
  };

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    themeMode = ThemeMode.values[p.getInt('theme') ?? 1];
    mapStyle = MapStyle.values[p.getInt('mapStyle') ?? 0];
    profile = RouteProfile.values[p.getInt('profile') ?? 0];
    haptic = p.getBool('haptic') ?? true;
    forwardNotifications = p.getBool('fwd') ?? true;
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('theme', themeMode.index);
    await p.setInt('mapStyle', mapStyle.index);
    await p.setInt('profile', profile.index);
    await p.setBool('haptic', haptic);
    await p.setBool('fwd', forwardNotifications);
  }

  void update(void Function() fn) {
    fn();
    notifyListeners();
    _save();
  }

  String get statusLabel => !bleConnected ? 'Disconnected' : (syncReady ? 'Ready' : 'Syncing');

  void toggleConnection() => update(() {
        bleConnected = !bleConnected;
        if (!bleConnected) {
          wifiIp = null;
          syncReady = false;
        } else {
          wifiIp = '10.146.223.212';
          syncReady = true;
        }
      });
}