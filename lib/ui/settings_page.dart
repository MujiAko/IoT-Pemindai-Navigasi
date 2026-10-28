import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart' show appState;
import '../state/app_state.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return SafeArea(
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text('Settings', style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            const TabBar(
              dividerColor: Colors.transparent,
              tabs: [Tab(text: 'App'), Tab(text: 'ESP32')],
            ),
            const Expanded(
              child: TabBarView(children: [_AppTab(), _EspTab()]),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- App tab
class _AppTab extends StatelessWidget {
  const _AppTab();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (_, _) {
        final s = appState;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const _Section('Appearance'),
            _Tile(
              icon: Icons.dark_mode_outlined,
              title: 'Theme',
              subtitle: const {ThemeMode.light: 'Light', ThemeMode.dark: 'Dark', ThemeMode.system: 'System'}[s.themeMode]!,
              onTap: () => _pick<ThemeMode>(
                context, 'Theme', ThemeMode.values, s.themeMode,
                (v) => v.name[0].toUpperCase() + v.name.substring(1),
                (v) => s.update(() => s.themeMode = v),
              ),
            ),
            const _Section('Map'),
            _Tile(
              icon: Icons.map_outlined,
              title: 'Map style',
              subtitle: s.mapStyle.label,
              onTap: () => _pick<MapStyle>(context, 'Map style', MapStyle.values, s.mapStyle,
                  (v) => v.label, (v) => s.update(() => s.mapStyle = v)),
            ),
            _Tile(
              icon: Icons.route_outlined,
              title: 'Route profile',
              subtitle: s.profile.label,
              onTap: () => _pick<RouteProfile>(context, 'Route profile', RouteProfile.values, s.profile,
                  (v) => v.label, (v) => s.update(() => s.profile = v)),
            ),
            const _Section('Navigation'),
            _SwitchTile(
              icon: Icons.vibration_rounded,
              title: 'Haptic feedback',
              subtitle: 'Vibrate for navigation events',
              value: s.haptic,
              onChanged: (v) {
                s.update(() => s.haptic = v);
                if (v) HapticFeedback.mediumImpact();
              },
            ),
            const _Section('Notifications'),
            _SwitchTile(
              icon: Icons.notifications_none_rounded,
              title: 'Forward notifications',
              subtitle: 'Send phone notifications to ESP32 HUD',
              value: s.forwardNotifications,
              onChanged: (v) => s.update(() => s.forwardNotifications = v),
            ),
            _Tile(
              icon: Icons.shield_outlined,
              title: 'Notification access',
              subtitle: s.notificationAccess ? 'Active' : 'Not granted',
              trailing: Icon(
                s.notificationAccess ? Icons.check_circle_rounded : Icons.error_outline,
                color: Theme.of(context).colorScheme.primary,
              ),
              onTap: () {/* TODO: buka pengaturan Notification Listener Android */},
            ),
            _Tile(
              icon: Icons.timer_outlined,
              title: 'Notification duration',
              subtitle: s.notificationDuration,
              onTap: () => _pick<String>(
                context, 'Notification duration',
                const ['Dynamic (auto)', '3 detik', '5 detik', '10 detik'], s.notificationDuration,
                (v) => v, (v) => s.update(() => s.notificationDuration = v),
              ),
            ),
            _Tile(
              icon: Icons.apps_rounded,
              title: 'Notification apps',
              subtitle: '${s.whitelistedApps} app whitelisted',
              onTap: () {/* TODO: halaman pilih aplikasi (installed_apps) */},
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- ESP32 tab
class _EspTab extends StatelessWidget {
  const _EspTab();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: appState,
      builder: (_, _) {
        final s = appState;
        Widget dot(bool on) => Icon(Icons.circle, size: 12, color: on ? cs.primary : cs.outline);
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const _Section('ESP32 Connection'),
            _Tile(
              icon: Icons.bluetooth_rounded,
              title: 'Bluetooth',
              subtitle: s.bleConnected ? 'Connected' : 'Disconnected',
              trailing: dot(s.bleConnected),
            ),
            _Tile(
              icon: Icons.wifi_rounded,
              title: 'Wi-Fi',
              subtitle: s.wifiIp ?? 'Not connected',
              trailing: dot(s.wifiIp != null),
            ),
            _espTile(context, 'WiFi mode', Icons.smartphone_rounded,
                const ['External WiFi — ESP32 connects to saved network', 'Hotspot — ESP32 joins phone hotspot', 'AP — Phone joins ESP32']),
            _espTile(context, 'Screen Orientation', Icons.screen_rotation_rounded,
                const ['Portrait', 'Landscape', 'Reverse Landscape']),
            _espTile(context, 'Screen Theme', Icons.palette_outlined, const ['Terang', 'Gelap']),
            _espTile(context, 'Map update', Icons.timer_outlined,
                const ['0.5s refresh interval', '1s refresh interval', '2s refresh interval', '5s refresh interval']),
            _espTile(context, 'Image quality', Icons.hd_outlined,
                const ['Low (40)', 'Medium (65)', 'High (85)']),
            _Tile(
              icon: Icons.restart_alt_rounded,
              title: 'Restart ESP32',
              subtitle: 'Reboot the connected ESP32',
              onTap: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Restart ESP32?'),
                  content: const Text('Perangkat akan reboot dan koneksi terputus sebentar.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
                      onPressed: () {
                        // TODO: kirim perintah restart via BLE/HTTP
                        Navigator.pop(ctx);
                      },
                      child: const Text('Restart'),
                    ),
                  ],
                ),
              ),
            ),
            const _Section('Background Operation'),
            const _Tile(icon: Icons.location_on_outlined, title: 'Location', subtitle: 'Allowed', trailing: _Check()),
            const _Tile(icon: Icons.bluetooth_searching_rounded, title: 'Bluetooth', subtitle: 'Allowed', trailing: _Check()),
          ],
        );
      },
    );
  }

  Widget _espTile(BuildContext context, String key, IconData icon, List<String> options) {
    return _Tile(
      icon: icon,
      title: key,
      subtitle: appState.esp[key]!,
      onTap: () => _pick<String>(context, key, options, appState.esp[key]!, (v) => v, (v) {
        appState.update(() => appState.esp[key] = v);
        // TODO: kirim konfigurasi ke ESP32
      }),
    );
  }
}

// ---------------------------------------------------------------- shared widgets
Future<void> _pick<T>(
  BuildContext context,
  String title,
  List<T> options,
  T current,
  String Function(T) label,
  ValueChanged<T> onSelected,
) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            ),
          ),
          for (final o in options)
            ListTile(
              title: Text(label(o)),
              trailing: o == current ? Icon(Icons.check_rounded, color: Theme.of(ctx).colorScheme.primary) : null,
              onTap: () {
                onSelected(o);
                Navigator.pop(ctx);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500),
        ),
      );
}

class _Check extends StatelessWidget {
  const _Check();
  @override
  Widget build(BuildContext context) =>
      Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary);
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _Tile({required this.icon, required this.title, required this.subtitle, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Icon(icon, color: cs.onSurfaceVariant, size: 28),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(subtitle),
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right_rounded) : null),
      onTap: onTap,
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchTile(
      {required this.icon, required this.title, required this.subtitle, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      secondary: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 28),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}