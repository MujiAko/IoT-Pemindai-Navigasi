import 'package:flutter/material.dart';
import '../main.dart' show appState;

class HomePage extends StatelessWidget {
  final VoidCallback onOpenMap;
  const HomePage({super.key, required this.onOpenMap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: appState,
      builder: (_, _) {
        final s = appState;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            children: [
              Center(child: Text('ESP32 Maps', style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w600))),
              const SizedBox(height: 32),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.circle, size: 12, color: s.bleConnected ? cs.primary : cs.outline),
                          const SizedBox(width: 10),
                          Text(s.statusLabel, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text(s.deviceName,
                              style: tt.titleSmall?.copyWith(letterSpacing: 0.5, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _InfoRow('BLE', s.bleConnected ? 'Connected' : 'Disconnected'),
                      _InfoRow('Wi-Fi', s.wifiIp ?? '—'),
                      _InfoRow('Sync', s.syncReady ? 'Ready' : '—'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onOpenMap,
                icon: const Icon(Icons.map_rounded),
                label: const Text('Open Map'),
              ),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 12),
                child: Text('Connection',
                    style: tt.titleMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w500)),
              ),
              OutlinedButton.icon(
                onPressed: s.toggleConnection,
                icon: Icon(s.bleConnected ? Icons.bluetooth_disabled : Icons.bluetooth),
                label: Text(s.bleConnected ? 'Disconnect' : 'Connect'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _hotspotSheet(context),
                icon: const Icon(Icons.wifi_rounded),
                label: const Text('Hotspot Setup'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _hotspotSheet(BuildContext context) {
    final ssid = TextEditingController();
    final pass = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hotspot Setup', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Kirim kredensial Wi-Fi ke ESP32 lewat BLE.',
                style: Theme.of(ctx).textTheme.bodyMedium),
            const SizedBox(height: 20),
            TextField(
              controller: ssid,
              decoration: const InputDecoration(labelText: 'SSID', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pass,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                // TODO: tulis ssid & pass ke karakteristik BLE ESP32
                Navigator.pop(ctx);
              },
              child: const Text('Kirim ke ESP32'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 96, child: Text(label, style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant))),
          Text(value, style: tt.titleMedium),
        ],
      ),
    );
  }
}