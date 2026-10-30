import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../state/app_state.dart';

class PlaceResult {
  final String name;
  final LatLng point;
  PlaceResult(this.name, this.point);
}

/// Satu langkah rute dari OSRM: manuver di [location], lalu berjalan [distance] meter ke manuver berikutnya.
class RouteStep {
  final String type; // depart, turn, arrive, roundabout, ...
  final String? modifier; // left, right, slight left, ...
  final String name; // nama jalan
  final double distance;
  final LatLng location;
  RouteStep(this.type, this.modifier, this.name, this.distance, this.location);

  String get instruction {
    switch (type) {
      case 'depart':
        return 'Mulai';
      case 'arrive':
        return 'Tiba';
      case 'roundabout':
      case 'rotary':
      case 'roundabout turn':
        return 'Masuk bundaran';
      case 'exit roundabout':
      case 'exit rotary':
        return 'Keluar bundaran';
    }
    switch (modifier) {
      case 'left':
        return 'Belok kiri';
      case 'right':
        return 'Belok kanan';
      case 'slight left':
        return 'Serong kiri';
      case 'slight right':
        return 'Serong kanan';
      case 'sharp left':
        return 'Belok tajam kiri';
      case 'sharp right':
        return 'Belok tajam kanan';
      case 'uturn':
        return 'Putar balik';
      default:
        return 'Lurus';
    }
  }
}

class RouteResult {
  final List<LatLng> points;
  final double distanceM;
  final double durationS;
  final List<RouteStep> steps;
  RouteResult(this.points, this.distanceM, this.durationS, [this.steps = const []]);

  String get distanceText => distanceM >= 1000
      ? '${(distanceM / 1000).toStringAsFixed(1)} km'
      : '${distanceM.round()} m';

  String get durationText {
    final m = (durationS / 60).round();
    if (m < 60) return '$m min';
    return '${m ~/ 60} j ${m % 60} min';
  }
}

/// Geocoding: Nominatim (OSM). Routing: OSRM (server FOSSGIS, mendukung car/foot/bike).
/// Untuk produksi, ganti dengan server sendiri atau penyedia seperti OpenRouteService/Mapbox.
class MapService {
  static const _ua = {'User-Agent': 'iot_pemindai_navigasi/1.0 (ramzyfadlil105@gmail.com)'};

  static Future<List<PlaceResult>> search(String q, {LatLng? near}) async {
    if (q.trim().length < 3) return [];
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': q,
      'format': 'jsonv2',
      'limit': '6',
      'countrycodes': 'id',
      if (near != null)
        'viewbox':
            '${near.longitude - 0.5},${near.latitude + 0.5},${near.longitude + 0.5},${near.latitude - 0.5}',
    });
    final res = await http.get(uri, headers: _ua).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return [];
    final list = jsonDecode(res.body) as List;
    return list
        .map((e) => PlaceResult(
              e['display_name'] as String,
              LatLng(double.parse(e['lat']), double.parse(e['lon'])),
            ))
        .toList();
  }

  static Future<String> reverse(LatLng p) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': '${p.latitude}',
      'lon': '${p.longitude}',
      'format': 'jsonv2',
    });
    try {
      final res = await http.get(uri, headers: _ua).timeout(const Duration(seconds: 8));
      return (jsonDecode(res.body)['display_name'] as String?) ?? 'Lokasi dipilih';
    } catch (_) {
      return 'Lokasi dipilih';
    }
  }

  static Future<RouteResult?> route(LatLng a, LatLng b, RouteProfile profile) async {
    final (server, mode) = switch (profile) {
      RouteProfile.driving => ('routed-car', 'driving'),
      RouteProfile.walking => ('routed-foot', 'driving'),
      RouteProfile.cycling => ('routed-bike', 'driving'),
    };
    final uri = Uri.parse(
      'https://routing.openstreetmap.de/$server/route/v1/$mode/'
      '${a.longitude},${a.latitude};${b.longitude},${b.latitude}'
      '?overview=full&geometries=geojson&steps=true',
    );
    final res = await http.get(uri, headers: _ua).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body);
    if (json['code'] != 'Ok') return null;
    final r = json['routes'][0];
    final coords = (r['geometry']['coordinates'] as List)
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();
    final steps = <RouteStep>[];
    for (final leg in (r['legs'] as List? ?? const [])) {
      for (final s in (leg['steps'] as List? ?? const [])) {
        final m = s['maneuver'] as Map<String, dynamic>;
        final loc = m['location'] as List;
        steps.add(RouteStep(
          m['type'] as String,
          m['modifier'] as String?,
          (s['name'] as String?) ?? '',
          (s['distance'] as num).toDouble(),
          LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
        ));
      }
    }
    return RouteResult(coords, (r['distance'] as num).toDouble(), (r['duration'] as num).toDouble(), steps);
  }
}