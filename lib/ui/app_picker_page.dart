import 'package:flutter/material.dart';
import 'package:installed_apps/installed_apps.dart';
import '../main.dart' show appState;


class AppPickerPage extends StatefulWidget {
  const AppPickerPage({super.key});

  @override
  State<AppPickerPage> createState() => _AppPickerPageState();
}

class _AppPickerPageState extends State<AppPickerPage> {
  List<AppInfo>? _apps;
  bool _showSystem = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

Future<void> _load() async {
    setState(() => _apps = null);
    // Menggunakan parameter bernama (named arguments) untuk versi terbaru
    final list = await InstalledApps.getInstalledApps(
      excludeSystemApps: !_showSystem, 
      withIcon: true,
    );
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (mounted) setState(() => _apps = list);
  }

  @override
  Widget build(BuildContext context) {
    final apps = _apps?.where((a) => a.name.toLowerCase().contains(_query.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification apps'),
        actions: [
          IconButton(
            tooltip: 'Tampilkan app sistem',
            icon: Icon(_showSystem ? Icons.visibility : Icons.visibility_off_outlined),
            onPressed: () {
              _showSystem = !_showSystem;
              _load();
            },
          ),
        ],
      ),
      body: apps == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      hintText: 'Cari aplikasi…',
                      prefixIcon: Icon(Icons.search_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: appState,
                    builder: (_, _) => ListView.builder(
                      itemCount: apps.length,
                      itemBuilder: (_, i) {
                        final a = apps[i];
                        final on = appState.notifApps.containsKey(a.packageName);
                        return CheckboxListTile(
                          value: on,
                          title: Text(a.name),
                          subtitle: Text(a.packageName, style: Theme.of(context).textTheme.bodySmall),
                          secondary: a.icon != null
                              ? Image.memory(a.icon!, width: 40, height: 40)
                              : const Icon(Icons.android),
                          onChanged: (v) => appState.setNotifApp(a.packageName, a.name, v == true),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}