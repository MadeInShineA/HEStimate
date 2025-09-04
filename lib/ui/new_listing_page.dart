import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import 'package:moon_design/moon_design.dart';
import 'package:moon_icons/moon_icons.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../data/listing_repository.dart';
import 'view_listing_page.dart';

class NewListingPage extends StatefulWidget {
  const NewListingPage({super.key});
  @override
  State<NewListingPage> createState() => _NewListingPageState();
}

class _NewListingPageState extends State<NewListingPage> {
  final _formKey = GlobalKey<FormState>();
  final _repo = ListingRepository();

  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _npaCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _surfaceCtrl = TextEditingController();
  final _roomsCtrl = TextEditingController();
  final _floorCtrl = TextEditingController();
  final _distTransportCtrl = TextEditingController();

  final FocusNode _addressFocus = FocusNode();
  final FocusNode _priceFocus = FocusNode();

  Timer? _addrDebounce;
  List<_AddressSuggestion> _addressSuggestions = [];
  bool _isLoadingAddr = false;
  bool _suspendAddrSearch = false;

  final _typeOptions = const ['Entire home', 'Single room'];
  int _typeIndex = 1;

  bool _isFurnish = false;
  bool _wifiIncl = false;
  bool _chargesIncl = false;
  bool _carPark = false;

  DateTime? _availStart;
  DateTime? _availEnd;
  bool _noEndDate = false;

  final ImagePicker _picker = ImagePicker();
  final List<File> _images = [];

  double? _geoLat;
  double? _geoLng;
  double? _proximHesKm;
  String? _nearestHesId;
  String? _nearestHesName;

  bool _isComputingTransit = false;
  double? _distTransitKm;
  String? _nearestTransitName;

  bool _saving = false;
  String? _error;

  static const _apiBase = 'https://hestimate-api-production.up.railway.app';
  static const _estimatePath = '/estimate-price';
  static const _observationPath = '/observations';

  bool _estimating = false;
  double? _estimatedPrice;
  String? _estimationError;

  Timer? _hesDebounce;
  bool _isComputingHes = false;

  @override
  void initState() {
    super.initState();
    _addressCtrl.addListener(_onAddressChanged);
    _cityCtrl.addListener(_onAddressPiecesChanged);
    _npaCtrl.addListener(_onAddressPiecesChanged);
    _priceFocus.addListener(() {
      if (!_priceFocus.hasFocus) {
        final raw = _priceCtrl.text.replaceAll(',', '.').trim();
        final v = double.tryParse(raw);
        if (v != null && v > 0) {
          final rounded = _roundToNearest005(v);
          _priceCtrl.text = rounded.toStringAsFixed(2);
          setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    _hesDebounce?.cancel();
    _addrDebounce?.cancel();
    _addressCtrl.removeListener(_onAddressChanged);
    _addressCtrl.dispose();
    _cityCtrl.removeListener(_onAddressPiecesChanged);
    _npaCtrl.removeListener(_onAddressPiecesChanged);
    _cityCtrl.dispose();
    _npaCtrl.dispose();
    _priceCtrl.dispose();
    _surfaceCtrl.dispose();
    _roomsCtrl.dispose();
    _floorCtrl.dispose();
    _distTransportCtrl.dispose();
    _addressFocus.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  double _roundToNearest005(double v) => (v * 20).round() / 20.0;
  bool _isOn005Step(double v) => ((v * 20).roundToDouble() == v * 20);

  void _onAddressChanged() {
    if (_suspendAddrSearch) return;
    _addrDebounce?.cancel();
    _addrDebounce = Timer(const Duration(milliseconds: 350), () async {
      final q = _addressCtrl.text.trim();
      if (q.length < 3) {
        if (mounted) setState(() => _addressSuggestions = []);
        return;
      }
      await _fetchAddressSuggestions(q);
    });
  }

  void _onAddressPiecesChanged() {
    _hesDebounce?.cancel();
    _hesDebounce = Timer(
      const Duration(milliseconds: 500),
      _recomputeHesDistanceIfPossible,
    );
  }

  Future<void> _recomputeHesDistanceIfPossible() async {
    final address = _addressCtrl.text.trim();
    final city = _cityCtrl.text.trim();
    final npa = _npaCtrl.text.trim();
    if (address.isEmpty || city.isEmpty || npa.isEmpty) return;

    setState(() {
      _isComputingHes = true;
      _isComputingTransit = true;
    });
    try {
      final coords = await _geocodeAddress(
        address: address,
        city: city,
        npa: npa,
      );
      _geoLat = coords.lat;
      _geoLng = coords.lng;

      final nearest = await _computeNearestSchoolRoadKm(
        lat: _geoLat!,
        lng: _geoLng!,
        mode: 'driving',
      );
      setState(() {
        _proximHesKm = nearest.km;
        _nearestHesId = nearest.id;
        _nearestHesName = nearest.name;
      });

      try {
        final t = await _computeNearestTransitStop(
          lat: _geoLat!,
          lng: _geoLng!,
        );
        setState(() {
          _distTransitKm = t.km;
          _nearestTransitName = t.name;
        });
      } catch (_) {
        setState(() {
          _distTransitKm = null;
          _nearestTransitName = null;
        });
      }
    } catch (_) {
      setState(() {
        _proximHesKm = null;
        _nearestHesId = null;
        _nearestHesName = null;
        _distTransitKm = null;
        _nearestTransitName = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isComputingHes = false;
          _isComputingTransit = false;
        });
      }
    }
  }

  Future<void> _fetchAddressSuggestions(String query) async {
    try {
      setState(() => _isLoadingAddr = true);

      final url = 'https://nominatim.openstreetmap.org/search'
          '?format=json'
          '&addressdetails=1'
          '&countrycodes=ch'
          '&q=${Uri.encodeQueryComponent(query)}'
          '&limit=6';

      final res = await http.get(
        Uri.parse(url),
        headers: const {
          'User-Agent': 'HEStimate/1.0 (student project; contact: none)',
        },
      );
      if (res.statusCode != 200) {
        throw Exception('Address search failed (${res.statusCode}).');
      }

      final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;

      final suggestions = data
          .map((e) {
            final m = e as Map<String, dynamic>;
            final addr = (m['address'] as Map?) ?? const {};
            final String? road = (addr['road'] ??
                    addr['pedestrian'] ??
                    addr['footway'] ??
                    addr['residential'] ??
                    addr['path'])
                ?.toString();
            final String? houseNumber = addr['house_number']?.toString();

            return _AddressSuggestion(
              displayName: (m['display_name'] ?? '').toString(),
              lat: double.tryParse(m['lat']?.toString() ?? ''),
              lon: double.tryParse(m['lon']?.toString() ?? ''),
              city: (addr['city'] ??
                      addr['town'] ??
                      addr['village'] ??
                      addr['municipality'] ??
                      '')
                  .toString(),
              postcode: (addr['postcode'] ?? '').toString(),
              road: road,
              houseNumber: houseNumber,
            );
          })
          .where((s) => s.lat != null && s.lon != null)
          .take(6)
          .toList();

      if (mounted) setState(() => _addressSuggestions = suggestions);
    } catch (_) {
      if (mounted) setState(() => _addressSuggestions = []);
    } finally {
      if (mounted) setState(() => _isLoadingAddr = false);
    }
  }

  static String? _tryAddrPiece(Map<String, dynamic> root, List<String> path) {
    dynamic cur = root;
    for (final k in path) {
      if (cur is Map && cur.containsKey(k)) {
        cur = cur[k];
      } else {
        return null;
      }
    }
    return cur?.toString();
  }

  Future<void> _applySuggestion(_AddressSuggestion s) async {
    String streetLine = '';
    final road = (s.road ?? '').trim();
    final house = (s.houseNumber ?? '').trim();

    if (road.isNotEmpty && house.isNotEmpty) {
      streetLine = '$road $house';
    } else if (road.isNotEmpty) {
      streetLine = road;
    } else {
      final parts = s.displayName.split(',').map((e) => e.trim()).toList();
      if (parts.length >= 2 && RegExp(r'^\d+[A-Za-z]?$').hasMatch(parts.first)) {
        streetLine = '${parts[1]} ${parts.first}';
      } else {
        streetLine = parts.isNotEmpty ? parts.first : s.displayName;
      }
    }

    _suspendAddrSearch = true;
    _addrDebounce?.cancel();

    _addressCtrl.text = streetLine;
    _cityCtrl.text = s.city;
    _npaCtrl.text = s.postcode;
    _geoLat = s.lat!;
    _geoLng = s.lon!;

    if (mounted) {
      setState(() {
        _addressSuggestions = [];
        _isLoadingAddr = false;
      });
    }

    _addressFocus.unfocus();

    await Future<void>.delayed(const Duration(milliseconds: 80));
    _suspendAddrSearch = false;

    _recomputeHesDistanceIfPossible();
  }

  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage(imageQuality: 85);
    if (picked.isEmpty) return;

    setState(() {
      final existing = _images.map((f) => f.path).toSet();
      for (final x in picked) {
        if (!existing.contains(x.path)) {
          _images.add(File(x.path));
        }
      }
    });
  }

  Future<({double lat, double lng})> _geocodeAddress({
    required String address,
    required String city,
    required String npa,
  }) async {
    final q = Uri.encodeQueryComponent('$address, $npa $city, Switzerland');
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=$q&format=json&limit=1',
    );

    final res = await http.get(
      uri,
      headers: const {
        'User-Agent': 'HEStimate/1.0 (student project; contact: none)',
      },
    );

    if (res.statusCode != 200) {
      throw Exception('Geocoding failed (HTTP ${res.statusCode})');
    }

    final List data = jsonDecode(res.body) as List;
    if (data.isEmpty) {
      throw Exception('Address not found. Please check the address fields.');
    }

    final first = data.first as Map<String, dynamic>;
    final lat = double.tryParse(first['lat']?.toString() ?? '');
    final lng = double.tryParse(first['lon']?.toString() ?? '');
    if (lat == null || lng == null) {
      throw Exception('Invalid geocoding response.');
    }
    return (lat: lat, lng: lng);
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  Future<int> _directionsDistanceMeters({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    String mode = 'driving',
  }) async {
    final mapsKey = dotenv.env['GOOGLE_API_KEY'] ?? '';
    if (mapsKey.isEmpty) {
      throw Exception('GOOGLE_API_KEY missing. Add it in .env and load dotenv.');
    }

    final uri = Uri.parse('https://maps.googleapis.com/maps/api/directions/json')
        .replace(queryParameters: {
      'origin': '$originLat,$originLng',
      'destination': '$destLat,$destLng',
      'mode': mode,
      'units': 'metric',
      'key': mapsKey,
    });

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Directions HTTP ${res.statusCode}.');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['status'] != 'OK') {
      final msg = data['error_message']?.toString() ?? '';
      throw Exception('Directions error: ${data['status']} $msg');
    }

    final routes = data['routes'] as List? ?? const [];
    final legs =
        (routes.isNotEmpty ? routes.first['legs'] : []) as List? ?? const [];
    if (legs.isEmpty) throw Exception('No legs returned.');
    final leg = legs.first as Map<String, dynamic>;
    final distMeters = (leg['distance'] as Map?)?['value'] as int?;
    if (distMeters == null) throw Exception('No distance value.');
    return distMeters;
  }

  Future<({double km, String id, String name})> _computeNearestSchoolRoadKm({
    required double lat,
    required double lng,
    String mode = 'driving',
  }) async {
    final snap = await FirebaseFirestore.instance.collection('schools').get();
    if (snap.docs.isEmpty) {
      throw Exception('No schools found in Firestore.');
    }

    String? bestId;
    String? bestName;
    double? bestLat, bestLng;
    double? bestAirKm;

    for (final d in snap.docs) {
      final m = d.data();
      final sLat = (m['latitude'] as num?)?.toDouble();
      final sLng = (m['longitude'] as num?)?.toDouble();
      if (sLat == null || sLng == null) continue;

      final airKm = _haversineKm(lat, lng, sLat, sLng);
      if (bestAirKm == null || airKm < bestAirKm) {
        bestAirKm = airKm;
        bestId = d.id;
        bestName = (m['name'] ?? '').toString();
        bestLat = sLat;
        bestLng = sLng;
      }
    }

    if (bestId == null || bestLat == null || bestLng == null) {
      throw Exception('Could not determine nearest school.');
    }

    final meters = await _directionsDistanceMeters(
      originLat: lat,
      originLng: lng,
      destLat: bestLat,
      destLng: bestLng,
      mode: mode,
    );

    final kmRounded = double.parse((meters / 1000.0).toStringAsFixed(2));
    return (km: kmRounded, id: bestId!, name: bestName ?? '');
  }

  double _toRad(double degrees) => degrees * math.pi / 180.0;

  Future<({double km, String name})> _computeNearestTransitStop({
    required double lat,
    required double lng,
  }) async {
    final radii = [500, 1000, 1500, 2500];
    for (final r in radii) {
      final query = """
[out:json][timeout:15];
(
  node(around:$r,$lat,$lng)[highway=bus_stop];
  node(around:$r,$lat,$lng)[public_transport=platform];
  node(around:$r,$lat,$lng)[public_transport=stop_position];
  node(around:$r,$lat,$lng)[railway=station];
  node(around:$r,$lat,$lng)[railway=halt];
  node(around:$r,$lat,$lng)[railway=tram_stop];
);
out body;
""";
      final resp = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        headers: const {
          'Content-Type': 'text/plain; charset=utf-8',
          'User-Agent': 'HEStimate/1.0 (student project; contact: none)',
        },
        body: query,
      );

      if (resp.statusCode != 200) {
        if (r == radii.last) {
          throw Exception('Overpass error (HTTP ${resp.statusCode}).');
        }
        continue;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final elements = (data['elements'] as List?) ?? const [];
      if (elements.isEmpty) continue;

      double? bestKm;
      String bestName = 'Stop';
      for (final e in elements) {
        final m = e as Map<String, dynamic>;
        final slat = (m['lat'] as num?)?.toDouble();
        final slon = (m['lon'] as num?)?.toDouble();
        if (slat == null || slon == null) continue;
        final d = _haversineKm(lat, lng, slat, slon);
        if (bestKm == null || d < bestKm) {
          bestKm = d;
          final tags = (m['tags'] as Map?) ?? const {};
          bestName = (tags['name'] ??
                  tags['ref'] ??
                  tags['uic_name'] ??
                  tags['uic_ref'] ??
                  'Stop')
              .toString();
        }
      }
      if (bestKm != null) return (km: bestKm, name: bestName);
    }
    throw Exception('No public transport stops found within 2.5 km.');
  }

  DateTime get _todayDateOnly {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String _formatDate(DateTime? d) {
    if (d == null) return 'Select date';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _availStart ?? _todayDateOnly,
      firstDate: _todayDateOnly,
      lastDate: DateTime(_todayDateOnly.year + 5),
    );
    if (picked != null) {
      setState(() {
        _availStart = DateTime(picked.year, picked.month, picked.day);
        if (_availEnd != null && _availEnd!.isBefore(_availStart!)) {
          _availEnd = null;
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    if (_noEndDate) return;
    final first = _availStart ?? _todayDateOnly;
    final picked = await showDatePicker(
      context: context,
      initialDate: _availEnd ?? first,
      firstDate: first,
      lastDate: DateTime(first.year + 6),
    );
    if (picked != null) {
      setState(() {
        _availEnd = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Future<void> _ensureGeoAndNearestSchool() async {
    if (_geoLat == null || _geoLng == null) {
      final coords = await _geocodeAddress(
        address: _addressCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        npa: _npaCtrl.text.trim(),
      );
      _geoLat = coords.lat;
      _geoLng = coords.lng;
    }
    if (_proximHesKm == null ||
        _nearestHesId == null ||
        _nearestHesId!.isEmpty) {
      final nearest = await _computeNearestSchoolRoadKm(
        lat: _geoLat!,
        lng: _geoLng!,
        mode: 'driving',
      );
      _proximHesKm = nearest.km;
      _nearestHesId = nearest.id;
      _nearestHesName = nearest.name;
    }
  }

  Map<String, dynamic> _buildExactEstimatePayload() {
    double reqNum(String label, String s, {double? min}) {
      final raw = s.trim();
      if (raw.isEmpty) throw '$label is required';
      final v = double.tryParse(raw.replaceAll(',', '.'));
      if (v == null) throw '$label must be a number';
      if (min != null && v < min) throw '$label must be ≥ ${min.toStringAsFixed(0)}';
      return v;
    }

    int reqInt(String label, String s, {int? min}) {
      final raw = s.trim();
      if (raw.isEmpty) throw '$label is required';
      final v = int.tryParse(raw);
      if (v == null) throw '$label must be an integer';
      if (min != null && v < min) throw '$label must be ≥ $min';
      return v;
    }

    if (_geoLat == null || _geoLng == null) {
      throw 'Latitude/Longitude missing; please provide a valid address.';
    }
    if (_proximHesKm == null) {
      throw 'HES proximity could not be computed from the address.';
    }
    if (_distTransitKm == null) {
      throw 'Public transport distance not available yet.';
    }

    return {
      "latitude": _geoLat!,
      "longitude": _geoLng!,
      "surface_m2": reqNum('Surface (m²)', _surfaceCtrl.text, min: 1),
      "num_rooms": reqInt('Number of rooms', _roomsCtrl.text, min: 1),
      "type": _typeOptions[_typeIndex] == 'Single room' ? "room" : "entire_home",
      "is_furnished": _isFurnish,
      "floor": reqInt('Floor', _floorCtrl.text),
      "wifi_incl": _wifiIncl,
      "charges_incl": _chargesIncl,
      "car_park": _carPark,
      "dist_public_transport_km": _distTransitKm!,
      "proxim_hesso_km": _proximHesKm!,
    };
  }

  String? _validateForEstimate() {
    if (_addressCtrl.text.trim().isEmpty) return 'Address is required.';
    if (_cityCtrl.text.trim().isEmpty) return 'City is required.';
    if (_npaCtrl.text.trim().isEmpty) return 'Postal code (NPA) is required.';
    if (_surfaceCtrl.text.trim().isEmpty) return 'Surface (m²) is required.';
    if (_roomsCtrl.text.trim().isEmpty) return 'Number of rooms is required.';
    if (_floorCtrl.text.trim().isEmpty) return 'Floor is required.';
    return null;
  }

  Future<void> _ensureTransitIfMissing() async {
    await _ensureGeoAndNearestSchool();
    if (_distTransitKm == null && _geoLat != null && _geoLng != null) {
      final t = await _computeNearestTransitStop(lat: _geoLat!, lng: _geoLng!);
      setState(() {
        _distTransitKm = t.km;
        _nearestTransitName = t.name;
      });
    }
  }

  Future<void> _estimatePrice() async {
    final quickErr = _validateForEstimate();
    if (quickErr != null) {
      setState(() {
        _estimationError = quickErr;
        _estimatedPrice = null;
      });
      return;
    }

    setState(() {
      _estimating = true;
      _estimationError = null;
      _estimatedPrice = null;
    });

    try {
      await _ensureTransitIfMissing();

      final payload = _buildExactEstimatePayload();

      final uri = Uri.parse('$_apiBase$_estimatePath');
      final resp = await http.post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
          'User-Agent': 'HEStimate/1.0 (student project; contact: none)',
        },
        body: jsonEncode(payload),
      );

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('Estimate failed (HTTP ${resp.statusCode}).');
      }

      final Map<String, dynamic> data =
          jsonDecode(resp.body) as Map<String, dynamic>;

      final raw = data['predicted_price_chf'];
      final parsed = (raw is num)
          ? raw.toDouble()
          : double.tryParse(raw?.toString() ?? '');
      if (parsed == null) {
        throw Exception('No valid predicted_price_chf in response.');
      }

      final rounded = _roundToNearest005(parsed);

      if (rounded.isNaN || rounded.isInfinite || rounded < 0) {
        throw Exception('Invalid predicted price: $parsed');
      }

      setState(() => _estimatedPrice = rounded);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Estimated price: CHF ${rounded.toStringAsFixed(2)}'),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _estimationError = e.toString();
        _estimatedPrice = null;
      });
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  void _applyEstimateToPriceField() {
    if (_estimatedPrice == null) return;
    _priceCtrl.text = _estimatedPrice!.toStringAsFixed(2);
    setState(() {});
  }

  Future<void> _postObservationOnCreate({
    required String listingId,
    required double price,
  }) async {
    try {
      await _ensureGeoAndNearestSchool();

      final payload = <String, dynamic>{
        'longitude': _geoLng,
        'latitude': _geoLat,
        'price_chf': price,
      };

      final uri = Uri.parse('$_apiBase$_observationPath');
      final apiKey = dotenv.env['API_KEY'];
      final resp = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'HEStimate/1.0 (student project; contact: none)',
          if (apiKey != null && apiKey.isNotEmpty) 'API-KEY': apiKey,
        },
        body: jsonEncode([payload]),
      );

      if (!(resp.statusCode >= 200 && resp.statusCode < 300)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Observation failed (HTTP ${resp.statusCode}).'),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Observation sent.')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Observation error: $e')));
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_availStart == null) {
      setState(() => _error = 'Please select an availability start date.');
      return;
    }
    if (_availStart!.isBefore(_todayDateOnly)) {
      setState(() => _error = 'Start date cannot be before today.');
      return;
    }
    if (!_noEndDate && _availEnd != null && _availEnd!.isBefore(_availStart!)) {
      setState(() => _error = 'End date cannot be before start date.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      if (_geoLat == null || _geoLng == null) {
        final coords = await _geocodeAddress(
          address: _addressCtrl.text.trim(),
          city: _cityCtrl.text.trim(),
          npa: _npaCtrl.text.trim(),
        );
        _geoLat = coords.lat;
        _geoLng = coords.lng;
      }

      final nearest = await _computeNearestSchoolRoadKm(
        lat: _geoLat!,
        lng: _geoLng!,
        mode: 'driving',
      );
      _proximHesKm = nearest.km;
      _nearestHesId = nearest.id;
      _nearestHesName = nearest.name;

      if (_distTransitKm == null) {
        final t = await _computeNearestTransitStop(
          lat: _geoLat!,
          lng: _geoLng!,
        );
        _distTransitKm = t.km;
        _nearestTransitName = t.name;
      }

      double parseD(String s) => double.parse(s.replaceAll(',', '.'));
      int parseI(String s) => int.parse(s);

      if (_surfaceCtrl.text.trim().isEmpty ||
          _roomsCtrl.text.trim().isEmpty ||
          _floorCtrl.text.trim().isEmpty) {
        throw Exception('Surface, number of rooms, and floor are required.');
      }

      if (_distTransitKm == null || _distTransitKm! < 0) {
        throw Exception(
          'Distance to public transport is required and must be ≥ 0.',
        );
      }

      final price = parseD(_priceCtrl.text);
      if (price <= 0) {
        throw Exception('Price must be > 0.');
      }
      if (!_isOn005Step(price)) {
        throw Exception('Price must be multiple of 0.05.');
      }

      final data = <String, dynamic>{
        'ownerUid': user.uid,
        'price': price,
        'address': _addressCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'npa': _npaCtrl.text.trim(),
        'latitude': _geoLat,
        'longitude': _geoLng,
        'surface': parseD(_surfaceCtrl.text),
        'num_rooms': parseI(_roomsCtrl.text),
        'type': _typeOptions[_typeIndex] == "Entire home" ? "entire_home" : "room",
        'is_furnish': _isFurnish,
        'floor': parseI(_floorCtrl.text),
        'wifi_incl': _wifiIncl,
        'charges_incl': _chargesIncl,
        'car_park': _carPark,
        'dist_public_transport_km': _distTransitKm,
        'proxim_hesso_km': _proximHesKm,
        'nearest_hesso_id': _nearestHesId,
        'nearest_hesso_name': _nearestHesName,
        'availability_start': Timestamp.fromDate(_availStart!),
        'availability_end': _noEndDate || _availEnd == null
            ? null
            : Timestamp.fromDate(_availEnd!),
        'photos': <String>[],
        'createdAt': Timestamp.now(),
      };

      final listingId = await _repo.createListing(data);

      if (_images.isNotEmpty) {
        final urls = await _repo.uploadListingImages(
          ownerUid: user.uid,
          listingId: listingId,
          files: _images,
        );
        await FirebaseFirestore.instance
            .collection('listings')
            .doc(listingId)
            .update({'photos': urls});
      }

      await _postObservationOnCreate(listingId: listingId, price: price);

      if (mounted) {
        final km = _proximHesKm?.toStringAsFixed(2) ?? '?';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Listing saved. Nearest HES stored ($km km).'),
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ViewListingPage(listingId: listingId),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _moonInput({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    Widget? leading,
    TextAlign textAlign = TextAlign.left,
    bool readOnly = false,
    VoidCallback? onTap,
    FocusNode? focusNode,
  }) {
    return MoonFormTextInput(
      hasFloatingLabel: false,
      hintText: hint,
      controller: controller,
      keyboardType: keyboardType,
      leading: leading,
      validator: validator,
      textAlign: textAlign,
      readOnly: readOnly,
      onTap: onTap,
      focusNode: focusNode,
    );
  }

  Widget _imageThumb(File f, ColorScheme cs) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 1,
            child: Image.file(f, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: InkWell(
            onTap: () {
              setState(() {
                _images.remove(f);
              });
            },
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface.withOpacity(0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.primary.withOpacity(.2)),
              ),
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.close, size: 16),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = BoxDecoration(
      gradient: isDark
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B0F14), Color(0xFF121826)],
            )
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF6F7FB), Color(0xFFFFFFFF)],
            ),
    );

    return Scaffold(
      appBar: AppBar(
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '${_images.length} photos',
                style: TextStyle(color: cs.onSurface.withOpacity(.7)),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 720;
          final isXL = constraints.maxWidth >= 1100;

          final gap = 12.0;
          final double contentMax = 900;
          final double gridWidth =
              (constraints.maxWidth.clamp(360, contentMax)).toDouble();
          final double fieldWidth = isWide ? ((gridWidth - gap) / 2) : gridWidth;

          final thumbsPerRow = isWide ? 4 : 2;
          final thumbSize = (gridWidth - (thumbsPerRow - 1) * 8) / thumbsPerRow;

          return Container(
            decoration: bg,
            child: AbsorbPointer(
              absorbing: _saving,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isXL
                      ? (constraints.maxWidth - contentMax) / 2 + 16
                      : 16,
                  vertical: 16,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentMax),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          _MoonCard(
                            isDark: isDark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      MoonIcons.arrows_boost_24_regular,
                                      size: 20,
                                      color: cs.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Listing details',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Basics',
                                    style: TextStyle(
                                      color: cs.onSurface.withOpacity(.8),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: gap,
                                  runSpacing: gap,
                                  children: [
                                    SizedBox(
                                      width: fieldWidth,
                                      child: Column(
                                        children: [
                                          _moonInput(
                                            controller: _addressCtrl,
                                            hint: 'Address (street & number)',
                                            keyboardType:
                                                TextInputType.streetAddress,
                                            leading: const Icon(
                                              Icons.place_outlined,
                                            ),
                                            validator: (v) => (v == null || v.isEmpty)
                                                ? 'Required'
                                                : null,
                                            textAlign: TextAlign.center,
                                            focusNode: _addressFocus,
                                          ),
                                          if (_addressFocus.hasFocus ||
                                              _isLoadingAddr ||
                                              _addressSuggestions.isNotEmpty)
                                            const SizedBox(height: 6),
                                          if (_isLoadingAddr)
                                            const LinearProgressIndicator(
                                              minHeight: 2,
                                            ),
                                          if (_addressSuggestions.isNotEmpty)
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Theme.of(context).cardColor,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: cs.primary.withOpacity(.15),
                                                ),
                                              ),
                                              child: ListView.separated(
                                                shrinkWrap: true,
                                                physics:
                                                    const NeverScrollableScrollPhysics(),
                                                itemCount:
                                                    _addressSuggestions.length,
                                                separatorBuilder: (_, __) => Divider(
                                                  height: 1,
                                                  color: cs.primary.withOpacity(.08),
                                                ),
                                                itemBuilder: (ctx, i) {
                                                  final s = _addressSuggestions[i];
                                                  final road = s.road?.trim() ?? '';
                                                  final house = s.houseNumber?.trim() ?? '';
                                                  final street = [road, house].where((x) => x.isNotEmpty).join(' ').trim();
                                                  final locality = [
                                                    s.postcode.trim(),
                                                    s.city.trim(),
                                                  ].where((x) => x.isNotEmpty).join(' ').trim();
                                                  final fullLabel = [
                                                    street.isNotEmpty ? street : s.displayName.split(',').first.trim(),
                                                    if (locality.isNotEmpty) locality,
                                                  ].join(', ');

                                                  return ListTile(
                                                    dense: true,
                                                    leading: const Icon(Icons.location_on_outlined),
                                                    title: Text(
                                                      fullLabel,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    subtitle: Text(
                                                      s.displayName,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    onTap: () => _applySuggestion(s),
                                                  );
                                                },
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _moonInput(
                                        controller: _cityCtrl,
                                        hint: 'City',
                                        leading: const Icon(
                                          Icons.location_city_outlined,
                                        ),
                                        validator: (v) =>
                                            (v == null || v.isEmpty) ? 'Required' : null,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _moonInput(
                                        controller: _npaCtrl,
                                        hint: 'Postal code (NPA)',
                                        keyboardType: TextInputType.number,
                                        leading: const Icon(
                                          Icons.local_post_office_outlined,
                                        ),
                                        validator: (v) =>
                                            (v == null || v.isEmpty) ? 'Required' : null,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _moonInput(
                                        controller: _surfaceCtrl,
                                        hint: 'Surface (m²)',
                                        keyboardType: TextInputType.number,
                                        leading: const Icon(
                                          Icons.square_foot_outlined,
                                        ),
                                        validator: (v) {
                                          if (v == null || v.isEmpty) return 'Required';
                                          final n = double.tryParse(
                                            v.replaceAll(',', '.'),
                                          );
                                          if (n == null) return 'Invalid number';
                                          if (n < 1) return 'Must be ≥ 1';
                                          return null;
                                        },
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _moonInput(
                                        controller: _roomsCtrl,
                                        hint: 'Number of rooms',
                                        keyboardType: TextInputType.number,
                                        leading: const Icon(
                                          Icons.meeting_room_outlined,
                                        ),
                                        validator: (v) {
                                          if (v == null || v.isEmpty) return 'Required';
                                          final n = int.tryParse(v);
                                          if (n == null) return 'Invalid integer';
                                          if (n < 1) return 'Must be ≥ 1';
                                          return null;
                                        },
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _moonInput(
                                        controller: _floorCtrl,
                                        hint: 'Floor',
                                        keyboardType: TextInputType.number,
                                        leading: const Icon(
                                          Icons.unfold_more_outlined,
                                        ),
                                        validator: (v) {
                                          if (v == null || v.isEmpty) return 'Required';
                                          final n = int.tryParse(v);
                                          if (n == null) return 'Invalid integer';
                                          return null;
                                        },
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: gridWidth,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Type',
                                            style: TextStyle(
                                              color: cs.onSurface.withOpacity(.8),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          LayoutBuilder(
                                            builder: (context, box) {
                                              final isNarrow = box.maxWidth < 300;
                                              if (isNarrow) {
                                                return Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  alignment: WrapAlignment.center,
                                                  children: List.generate(
                                                    _typeOptions.length,
                                                    (i) {
                                                      return SizedBox(
                                                        width: box.maxWidth,
                                                        child: MoonSegmentedControl(
                                                          initialIndex:
                                                              _typeIndex == i ? 0 : -1,
                                                          segments: [
                                                            Segment(
                                                              label: Text(_typeOptions[i]),
                                                            ),
                                                          ],
                                                          onSegmentChanged: (_) =>
                                                              setState(() => _typeIndex = i),
                                                          isExpanded: true,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                );
                                              }
                                              return MoonSegmentedControl(
                                                initialIndex: _typeIndex,
                                                segments: _typeOptions
                                                    .map((t) => Segment(label: Text(t)))
                                                    .toList(),
                                                onSegmentChanged: (i) =>
                                                    setState(() => _typeIndex = i),
                                                isExpanded: true,
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Divider(color: cs.primary.withOpacity(.1)),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Amenities',
                                    style: TextStyle(
                                      color: cs.onSurface.withOpacity(.8),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _AmenitySwitch(
                                        title: 'Have furniture?',
                                        value: _isFurnish,
                                        onChanged: (v) => setState(() => _isFurnish = v),
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _AmenitySwitch(
                                        title: 'Wi-Fi included?',
                                        value: _wifiIncl,
                                        onChanged: (v) => setState(() => _wifiIncl = v),
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _AmenitySwitch(
                                        title: 'Charges included?',
                                        value: _chargesIncl,
                                        onChanged: (v) => setState(() => _chargesIncl = v),
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _AmenitySwitch(
                                        title: 'Car park?',
                                        value: _carPark,
                                        onChanged: (v) => setState(() => _carPark = v),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Divider(color: cs.primary.withOpacity(.1)),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Availability',
                                    style: TextStyle(
                                      color: cs.onSurface.withOpacity(.8),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    SizedBox(
                                      width: fieldWidth,
                                      child: MoonFilledButton(
                                        isFullWidth: true,
                                        onTap: _pickStartDate,
                                        leading: const Icon(
                                          Icons.event_available_outlined,
                                        ),
                                        label: Text(
                                          'Start: ${_formatDate(_availStart)}',
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Expanded(
                                            child: MoonFilledButton(
                                              isFullWidth: true,
                                              onTap: _noEndDate ? null : _pickEndDate,
                                              leading: const Icon(
                                                Icons.event_note_outlined,
                                              ),
                                              label: Text(
                                                _noEndDate
                                                    ? 'End: None'
                                                    : 'End: ${_formatDate(_availEnd)}',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'No end',
                                                style: TextStyle(
                                                  color: cs.onSurface.withOpacity(.8),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              MoonSwitch(
                                                value: _noEndDate,
                                                onChanged: (v) => setState(() {
                                                  _noEndDate = v;
                                                  if (v) _availEnd = null;
                                                }),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Start date cannot be before today. End date is optional.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: cs.onSurface.withOpacity(.65),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Divider(color: cs.primary.withOpacity(.1)),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Distances',
                                    style: TextStyle(
                                      color: cs.onSurface.withOpacity(.8),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_isComputingTransit)
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    if (_isComputingTransit) const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        _distTransitKm == null
                                            ? 'Nearest transit: —'
                                            : 'Nearest transit: ${_nearestTransitName ?? 'Stop'} • ${_distTransitKm!.toStringAsFixed(2)} km',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: cs.onSurface.withOpacity(.85),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_isComputingHes)
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    if (_isComputingHes) const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        _proximHesKm == null
                                            ? 'HES proximity: —'
                                            : (_nearestHesName == null || _nearestHesName!.isEmpty)
                                                ? 'HES proximity: ${_proximHesKm!.toStringAsFixed(2)} km'
                                                : 'HES proximity: ${_nearestHesName!} • ${_proximHesKm!.toStringAsFixed(2)} km',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: cs.onSurface.withOpacity(.85),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Divider(color: cs.primary.withOpacity(.1)),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Photos',
                                    style: TextStyle(
                                      color: cs.onSurface.withOpacity(.8),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 12,
                                  runSpacing: 12,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    MoonButton(
                                      onTap: _pickImages,
                                      leading: const Icon(Icons.image_outlined),
                                      label: const Text('Pick images'),
                                    ),
                                    Text(
                                      '${_images.length} selected',
                                      style: TextStyle(
                                        color: cs.onSurface.withOpacity(.65),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (_images.isNotEmpty)
                                  LayoutBuilder(
                                    builder: (context, _) {
                                      return Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: _images.map((f) {
                                          return SizedBox(
                                            width: thumbSize,
                                            height: thumbSize,
                                            child: _imageThumb(f, cs),
                                          );
                                        }).toList(),
                                      );
                                    },
                                  ),
                                const SizedBox(height: 16),
                                Divider(color: cs.primary.withOpacity(.1)),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Pricing',
                                    style: TextStyle(
                                      color: cs.onSurface.withOpacity(.8),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: fieldWidth,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _moonInput(
                                          controller: _priceCtrl,
                                          hint: 'Price (CHF)',
                                          keyboardType: TextInputType.number,
                                          leading: const Icon(
                                            MoonIcons.arrows_boost_24_regular,
                                          ),
                                          validator: (v) {
                                            if (v == null || v.isEmpty) return 'Required';
                                            final value = double.tryParse(
                                              v.replaceAll(',', '.'),
                                            );
                                            if (value == null) return 'Invalid number';
                                            if (value <= 0) return 'Must be > 0';
                                            if (!_isOn005Step(value)) {
                                              return 'Must be multiple of 0.05';
                                            }
                                            return null;
                                          },
                                          textAlign: TextAlign.center,
                                          focusNode: _priceFocus,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      MoonButton(
                                        onTap: _estimating ? null : _estimatePrice,
                                        leading: _estimating
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(strokeWidth: 2),
                                              )
                                            : const Icon(Icons.calculate_outlined),
                                        label: Text(_estimating ? '...' : 'Estimate'),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_estimatedPrice != null || _estimationError != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).cardColor.withOpacity(.95),
                                      border: Border.all(
                                        color: cs.primary.withOpacity(.15),
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: _estimationError != null
                                        ? Text(
                                            _estimationError!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.redAccent,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          )
                                        : Row(
                                            children: [
                                              const Icon(Icons.trending_up),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Estimated price: CHF ${_estimatedPrice!.toStringAsFixed(2)}',
                                                  softWrap: true,
                                                  overflow: TextOverflow.fade,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    color: cs.onSurface,
                                                  ),
                                                ),
                                              ),
                                              MoonButton(
                                                onTap: _applyEstimateToPriceField,
                                                label: const Text('Apply'),
                                                leading: const Icon(
                                                  Icons.check_circle_outline,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_error != null)
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          const SizedBox(height: 4),
                          MoonFilledButton(
                            isFullWidth: true,
                            onTap: _saving ? null : _save,
                            leading: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(MoonIcons.arrows_boost_24_regular),
                            label: Text(_saving ? 'Saving…' : 'Save listing'),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MoonCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  const _MoonCard({required this.child, required this.isDark, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(isDark ? .5 : 1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withOpacity(0.15)),
      ),
      child: child,
    );
  }
}

class _AmenitySwitch extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _AmenitySwitch({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          MoonSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _AddressSuggestion {
  final String displayName;
  final double? lat;
  final double? lon;
  final String city;
  final String postcode;
  final String? road;
  final String? houseNumber;

  const _AddressSuggestion({
    required this.displayName,
    required this.lat,
    required this.lon,
    required this.city,
    required this.postcode,
    this.road,
    this.houseNumber,
  });
}
