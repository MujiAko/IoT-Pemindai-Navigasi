import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../main.dart' show appState;
import '../services/map_service.dart';
import '../state/app_state.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _map = MapController();
  final _searchCtrl = TextEditingController();
  StreamSubscription<Position>? _posSub;
  Timer? _debounce;

  LatLng? _me;
  double _heading = 0;
  PlaceResult? _dest;
  RouteResult? _route;
  List<PlaceResult> _suggestions = [];
  bool _loadingRoute = false;
  bool _searching = false;
  bool _follow = true;

  static const _fallback = LatLng(-6.2088, 106.8456); // Jakarta

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

    // Akurasi tinggi + filter jarak 5 m supaya posisi tidak "loncat-loncat".
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5),
    ).listen((p) {
      final ll = LatLng(p.latitude, p.longitude);
      setState(() {
        _me = ll;
        if (p.speed > 1) _heading = p.heading;
      });
      appState.nav.updatePosition(ll); // instruksi belok ke ESP32
      if (_follow) _map.move(ll, _map.camera.zoom);
    });

    final p = await Geolocator.getCurrentPosition();
    final ll = LatLng(p.latitude, p.longitude);
    setState(() => _me = ll);
    appState.nav.updatePosition(ll);
    _map.move(ll, 15);
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    // Debounce 600ms — Nominatim membatasi 1 request/detik.
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      setState(() => _searching = true);
      try {
        final r = await MapService.search(q, near: _me);
        if (mounted) setState(() => _suggestions = r);
      } catch (_) {}
      if (mounted) setState(() => _searching = false);
    });
  }

  Future<void> _pick(PlaceResult p) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _dest = p;
      _suggestions = [];
      _searchCtrl.clear();
      _follow = false;
    });
    await _buildRoute();
  }

  Future<void> _onLongPress(LatLng ll) async {
    setState(() {
      _dest = PlaceResult('Mencari alamat…', ll);
      _follow = false;
    });
    final name = await MapService.reverse(ll);
    if (!mounted) return;
    setState(() => _dest = PlaceResult(name, ll));
    await _buildRoute();
  }

  Future<void> _buildRoute() async {
    final from = _me;
    final to = _dest?.point;
    if (to == null) return;
    if (from == null) {
      _map.move(to, 15);
      return;
    }
    setState(() => _loadingRoute = true);
    try {
      final r = await MapService.route(from, to, appState.profile);
      if (!mounted) return;
      setState(() => _route = r);
      if (appState.nav.active) appState.nav.stop(); // rute berubah, mulai ulang manual
      if (r != null) {
        _map.fitCamera(CameraFit.coordinates(
          coordinates: r.points,
          padding: const EdgeInsets.fromLTRB(48, 120, 48, 380),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Gagal mengambil rute. Cek koneksi internet.')));
      }
    }
    if (mounted) setState(() => _loadingRoute = false);
  }

  void _clear() {
    appState.nav.stop();
    setState(() {
      _dest = null;
      _route = null;
    });
  }

  void _recenter() {
    setState(() => _follow = true);
    if (_me != null) _map.move(_me!, 16);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: appState,
      builder: (_, _) {
        final style = appState.mapStyle;
        return Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _me ?? _fallback,
                initialZoom: 14,
                minZoom: 3,
                maxZoom: 19,
                onLongPress: (_, ll) => _onLongPress(ll),
                onPositionChanged: (_, byGesture) {
                  if (byGesture && _follow) setState(() => _follow = false);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: style.url,
                  subdomains: style.subdomains,
                  userAgentPackageName: 'com.example.iot_pemindai_navigasi',
                  maxNativeZoom: 19,
                  retinaMode: RetinaMode.isHighDensity(context),
                ),
                if (_route != null)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: _route!.points,
                      strokeWidth: 7,
                      color: const Color(0xFF3B82F6),
                      borderStrokeWidth: 2,
                      borderColor: Colors.white,
                      strokeCap: StrokeCap.round,
                      strokeJoin: StrokeJoin.round,
                    ),
                  ]),
                MarkerLayer(markers: [
                  if (_me != null)
                    Marker(
                      point: _me!,
                      width: 44,
                      height: 44,
                      child: Transform.rotate(
                        angle: _heading * 3.14159 / 180,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
                          ),
                          child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                  if (_dest != null)
                    Marker(
                      point: _dest!.point,
                      width: 44,
                      height: 52,
                      alignment: Alignment.topCenter,
                      child: Icon(Icons.location_on_rounded, color: cs.error, size: 48),
                    ),
                ]),
                const RichAttributionWidget(
                  alignment: AttributionAlignment.bottomLeft,
                  attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
                ),
              ],
            ),

            // Search bar + suggestions
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  children: [
                    Material(
                      elevation: 3,
                      borderRadius: BorderRadius.circular(28),
                      color: cs.surface,
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: _onQueryChanged,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Cari tujuan…',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _searching
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    if (_suggestions.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        constraints: const BoxConstraints(maxHeight: 280),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _suggestions.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) => ListTile(
                            dense: true,
                            leading: Icon(Icons.place_outlined, color: cs.primary),
                            title: Text(_suggestions[i].name, maxLines: 2, overflow: TextOverflow.ellipsis),
                            onTap: () => _pick(_suggestions[i]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Map controls
            Positioned(
              right: 16,
              bottom: _dest != null ? 330 : 24,
              child: Column(
                children: [
                  _RoundBtn(Icons.add, () => _map.move(_map.camera.center, _map.camera.zoom + 1)),
                  const SizedBox(height: 10),
                  _RoundBtn(Icons.remove, () => _map.move(_map.camera.center, _map.camera.zoom - 1)),
                  const SizedBox(height: 10),
                  _RoundBtn(_follow ? Icons.my_location_rounded : Icons.location_searching_rounded, _recenter,
                      active: _follow),
                ],
              ),
            ),

            // Bottom panel
            if (_dest != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _RoutePanel(
                  dest: _dest!,
                  route: _route,
                  loading: _loadingRoute,
                  profile: appState.profile,
                  onProfile: (p) {
                    appState.update(() => appState.profile = p);
                    _buildRoute();
                  },
                  onClose: _clear,
                  onStart: _route == null ? null : _startNavigation,
                ),
              ),
          ],
        );
      },
    );
  }

  void _startNavigation() {
    setState(() => _follow = true);
    if (_me != null) _map.move(_me!, 17);
    // Instruksi belok dikirim ke ESP32 lewat BLE. Pengiriman gambar peta lewat Wi-Fi
    // menunggu penerima gambar di firmware (belum ada).
    final r = _route;
    if (r == null) return;
    appState.nav.start(r);
    if (_me != null) appState.nav.updatePosition(_me!);
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  const _RoundBtn(this.icon, this.onTap, {this.active = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      shape: const CircleBorder(),
      color: active ? cs.primary : cs.primaryContainer,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, color: active ? cs.onPrimary : cs.onPrimaryContainer),
        ),
      ),
    );
  }
}

class _RoutePanel extends StatelessWidget {
  final PlaceResult dest;
  final RouteResult? route;
  final bool loading;
  final RouteProfile profile;
  final ValueChanged<RouteProfile> onProfile;
  final VoidCallback onClose;
  final VoidCallback? onStart;

  const _RoutePanel({
    required this.dest,
    required this.route,
    required this.loading,
    required this.profile,
    required this.onProfile,
    required this.onClose,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
            child: Row(
              children: [
                Icon(Icons.location_on, color: cs.primary),
                const SizedBox(width: 14),
                Expanded(child: Text(dest.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.titleMedium)),
                IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<RouteProfile>(
            showSelectedIcon: true,
            style: SegmentedButton.styleFrom(backgroundColor: cs.surface),
            segments: const [
              ButtonSegment(value: RouteProfile.driving, label: Text('Driving')),
              ButtonSegment(value: RouteProfile.walking, label: Text('Walking')),
              ButtonSegment(value: RouteProfile.cycling, label: Text('Cycling')),
            ],
            selected: {profile},
            onSelectionChanged: (s) => onProfile(s.first),
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: loading
                ? const Center(child: SizedBox(height: 28, width: 28, child: CircularProgressIndicator(strokeWidth: 3)))
                : Row(
                    children: [
                      _Stat(route?.distanceText ?? '—', 'Distance'),
                      Container(width: 1, height: 36, color: cs.outlineVariant),
                      _Stat(route?.durationText ?? '—', 'Duration'),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        ListenableBuilder(
          listenable: Listenable.merge([appState.nav, appState]),
          builder: (_, _) {
            final nav = appState.nav;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (nav.active && nav.lastText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(nav.lastText, style: tt.titleSmall, textAlign: TextAlign.center),
                  ),
                if (nav.active && !appState.bleConnected)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('ESP32 belum terhubung, instruksi tidak terkirim',
                        style: tt.bodySmall?.copyWith(color: cs.error), textAlign: TextAlign.center),
                  ),
                FilledButton(
                  onPressed: nav.active ? nav.stop : onStart,
                  child: Text(nav.active ? 'Stop Navigation' : 'Start Navigation'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String value, label;
  const _Stat(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(value, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(label, style: tt.labelLarge?.copyWith(letterSpacing: 0.5)),
        ],
      ),
    );
  }
}