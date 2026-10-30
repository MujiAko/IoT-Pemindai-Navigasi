import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import '../main.dart' show appState;

/// Pilih aplikasi yang notifikasinya diteruskan ke ESP32.
class NotificationAppsPage extends StatefulWidget {
  const NotificationAppsPage({super.key});

  @override
  State<NotificationAppsPage> createState() => _NotificationAppsPageState();
}

class _NotificationAppsPageState extends State<NotificationAppsPage> {
  // Elemennya AppInfo dari paket installed_apps (name, packageName, icon).
  List<dynamic> _apps = const [];
  bool _loading = true;
  bool _showSystem = false;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apps = await InstalledApps.getInstalledApps(
        excludeSystemApps: !_showSystem,
        excludeNonLaunchableApps: true,
        withIcon: true,
      );
      final list = List<dynamic>.from(apps);
      list.sort((a, b) => (a.name as String).toLowerCase().compareTo((b.name as String).toLowerCase()));
      if (mounted) setState(() => _apps = list);
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal membaca daftar aplikasi: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Notification apps')),
      body: ListenableBuilder(
        listenable: appState,
        builder: (_, _) {
          final q = _query.trim().toLowerCase();
          final shown = _apps.where((a) => q.isEmpty || (a.name as String).toLowerCase().contains(q)).toList();
          // Yang sudah dipilih tampil di atas.
          shown.sort((a, b) {
            final sa = appState.notifApps.containsKey(a.packageName) ? 0 : 1;
            final sb = appState.notifApps.containsKey(b.packageName) ? 0 : 1;
            return sa != sb ? sa.compareTo(sb) : (a.name as String).toLowerCase().compareTo((b.name as String).toLowerCase());
          });

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Cari aplikasi…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: cs.primaryContainer.withValues(alpha: 0.45),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: const Text('Tampilkan aplikasi sistem'),
                value: _showSystem,
                onChanged: (v) {
                  _showSystem = v;
                  _load();
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${appState.whitelistedApps} aplikasi dipilih',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.primary)),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                        : ListView.builder(
                            itemCount: shown.length,
                            itemBuilder: (_, i) {
                              final a = shown[i];
                              final pkg = a.packageName as String;
                              final name = a.name as String;
                              final icon = a.icon;
                              return SwitchListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                                secondary: icon != null
                                    ? Image.memory(icon, width: 36, height: 36, gaplessPlayback: true)
                                    : Icon(Icons.apps_rounded, color: cs.onSurfaceVariant),
                                title: Text(name),
                                subtitle: Text(pkg, maxLines: 1, overflow: TextOverflow.ellipsis),
                                value: appState.notifApps.containsKey(pkg),
                                onChanged: (v) => appState.setNotifApp(pkg, name, v),
                              );
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}