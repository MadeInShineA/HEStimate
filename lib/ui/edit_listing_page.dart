// lib/ui/edit_listing_page.dart
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

import '../data/listing_repository.dart';

class EditListingPage extends StatefulWidget {
  final String listingId;
  const EditListingPage({super.key, required this.listingId});

  @override
  State<EditListingPage> createState() => _EditListingPageState();
}

class _EditListingPageState extends State<EditListingPage> {
  final _formKey = GlobalKey<FormState>();
  final _repo = ListingRepository();

  // Controllers (user inputs)
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _npaCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _surfaceCtrl = TextEditingController();
  final _roomsCtrl = TextEditingController();
  final _floorCtrl = TextEditingController();

  // Address suggestions
  final FocusNode _addressFocus = FocusNode();
  final FocusNode _priceFocus = FocusNode();
  Timer? _addrDebounce;
  List<_AddressSuggestion> _addressSuggestions = [];
  bool _isLoadingAddr = false;

  // Debounce for recomputing distances (HES + transit)
  Timer? _hesDebounce;
  bool _isComputingHes = false;
  bool _isComputingTransit = false;

  // Type: Entire home / Single room  -> segmented control
  final _typeOptions = const ['Entire home', 'Single room'];
  int _typeIndex = 1;

  // Amenities
  bool _isFurnish = false;
  bool _wifiIncl = false;
  bool _chargesIncl = false;
  bool _carPark = false;

  // Availability
  DateTime? _availStart;
  DateTime? _availEnd;
  bool _noEndDate = false;

  // Images
  final ImagePicker _picker = ImagePicker();
  final List<File> _newImages = [];
  List<String> _existingPhotos = [];
  final Set<String> _photosToRemove = <String>{};

  // Derived / auto-computed state
  double? _geoLat;
  double? _geoLng;

  // HES
  double? _proximHesKm; // auto
  String? _nearestHesId; // auto (doc id)
  String? _nearestHesName; // auto (name)

  // Transit
  double? _distTransitKm; // auto
  String? _nearestTransitName; // auto

  bool _loading = true;
  bool _saving = false;
  String? _error;

  // To decide if we must re-geocode / recompute proximity
  String _initialAddrKey = ''; // "$address|$npa|$city"

  // ===== HEStimate API integration (same as New) =====
  static const _apiBase = 'https://hestimate-api-production.up.railway.app';
  static const _estimatePath = '/estimate-price';

  bool _estimating = false;
  double? _estimatedPrice;
  String? _estimationError;

  @override
  void initState() {
    super.initState();
    _addressCtrl.addListener(_onAddressChanged);
    _cityCtrl.addListener(_onAddressPiecesChanged);
    _npaCtrl.addListener(_onAddressPiecesChanged);

    // Round price to nearest 0.05 on blur (ONLY if > 0), identical to NewListingPage
    _priceFocus.addListener(() {
      if (!_priceFocus.hasFocus) {
        final raw = _priceCtrl.text.replaceAll(',', '.').trim();
        final v = double.tryParse(raw);
        if (v != null && v > 0) {
          final rounded = _roundToNearest005(v);
          _priceCtrl.text = rounded.toStringAsFixed(2);
          setState(() {}); // refresh UI/validators
        }
      }
    });

    _loadListing();
  }

  @override
  void dispose() {
    _addrDebounce?.cancel();
    _hesDebounce?.cancel();

    _addressCtrl
      ..removeListener(_onAddressChanged)
      ..dispose();
    _addressFocus.dispose();
    _priceFocus.dispose();

    _cityCtrl.removeListener(_onAddressPiecesChanged);
    _npaCtrl.removeListener(_onAddressPiecesChanged);

    _cityCtrl.dispose();
    _npaCtrl.dispose();
    _priceCtrl.dispose();
    _surfaceCtrl.dispose();
    _roomsCtrl.dispose();
    _floorCtrl.dispose();

    super.dispose();
  }

  // ---------- rounding helpers (nearest 0.05) ----------
  double _roundToNearest005(double v) => (v * 20).round() / 20.0;
  bool _isOn005Step(double v) => ((v * 20).roundToDouble() == v * 20);

  // ─────────────────────────────────────────────────────────────────────────────
  // Load existing listing
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _loadListing() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('listings')
          .doc(widget.listingId)
          .get();

      if (!snap.exists) {
        setState(() {
          _error = 'Listing not found.';
          _loading = false;
        });
        return;
      }

      final m = snap.data()!;
      // Fill controllers
      _addressCtrl.text = (m['address'] ?? '').toString();
      _cityCtrl.text = (m['city'] ?? '').toString();
      _npaCtrl.text = (m['npa'] ?? '').toString();
      _priceCtrl.text = (m['price'] ?? '').toString();
      _surfaceCtrl.text = (m['surface']?.toString() ?? '');
      _roomsCtrl.text = (m['num_rooms']?.toString() ?? '');
      _floorCtrl.text = (m['floor']?.toString() ?? '');

      // Flags / enums
      final type = (m['type'] ?? 'room').toString();
      _typeIndex = type == 'entire_home' ? 0 : 1;

      _isFurnish = (m['is_furnish'] ?? false) as bool;
      _wifiIncl = (m['wifi_incl'] ?? false) as bool;
      _chargesIncl = (m['charges_incl'] ?? false) as bool;
      _carPark = (m['car_park'] ?? false) as bool;

      // Availability
      final tsStart = m['availability_start'] as Timestamp?;
      final tsEnd = m['availability_end'] as Timestamp?;
      _availStart = tsStart?.toDate();
      _availEnd = tsEnd?.toDate();
      _noEndDate = tsEnd == null;

      // Geo + auto computed
      _geoLat = (m['latitude'] as num?)?.toDouble();
      _geoLng = (m['longitude'] as num?)?.toDouble();

      // Distances
      _proximHesKm = (m['proxim_hesso_km'] as num?)?.toDouble();
      _nearestHesId = (m['nearest_hesso_id'] ?? '').toString();
      _nearestHesName = (m['nearest_hesso_name'] ?? '').toString();
      _distTransitKm = (m['dist_public_transport_km'] as num?)?.toDouble();
      _nearestTransitName = (m['nearest_transit_name'] ?? '').toString();

      // Photos
      final List photos = (m['photos'] as List?) ?? const [];
      _existingPhotos = photos.map((e) => e.toString()).toList();

      _initialAddrKey =
          '${_addressCtrl.text.trim()}|${_npaCtrl.text.trim()}|${_cityCtrl.text.trim()}';

      setState(() => _loading = false);

      // If we have coords but missing any distance/name, recompute them
      if (_geoLat != null &&
          _geoLng != null &&
          (_proximHesKm == null ||
              _distTransitKm == null ||
              (_nearestHesName == null || _nearestHesName!.isEmpty))) {
        // ignore: unawaited_futures
        _recomputeDistancesIfPossible();
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load listing: $e';
        _loading = false;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Address suggestions (Nominatim) with debounce
  // ─────────────────────────────────────────────────────────────────────────────
  void _onAddressChanged() {
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
      _recomputeDistancesIfPossible,
    );
  }

  Future<void> _fetchAddressSuggestions(String query) async {
    try {
      setState(() => _isLoadingAddr = true);
      final url =
          'https://nominatim.openstreetmap.org/search?format=json&addressdetails=1&countrycodes=ch&q=${Uri.encodeQueryComponent(query)}&limit=6';
      final res = await http.get(
        Uri.parse(url),
        headers: const {
          'User-Agent': 'HEStimate/1.0 (student project; contact: none)',
        },
      );
      if (res.statusCode != 200) {
        throw Exception('Address search failed (${res.statusCode}).');
      }
      final List data = jsonDecode(res.body) as List;
      final suggestions = data
          .map((e) {
            final m = e as Map<String, dynamic>;
            return _AddressSuggestion(
              displayName: (m['display_name'] ?? '').toString(),
              lat: double.tryParse(m['lat']?.toString() ?? ''),
              lon: double.tryParse(m['lon']?.toString() ?? ''),
              city:
                  _tryAddrPiece(m, ['address', 'city']) ??
                  _tryAddrPiece(m, ['address', 'town']) ??
                  _tryAddrPiece(m, ['address', 'village']) ??
                  '',
              postcode: _tryAddrPiece(m, ['address', 'postcode']) ?? '',
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

  void _applySuggestion(_AddressSuggestion s) {
    _addressCtrl.text = s.displayName.split(',').first;
    if (s.city.isNotEmpty) _cityCtrl.text = s.city;
    if (s.postcode.isNotEmpty) _npaCtrl.text = s.postcode;
    _geoLat = s.lat!;
    _geoLng = s.lon!;
    setState(() => _addressSuggestions = []);
    // recompute with the new coordinates
    // ignore: unawaited_futures
    _recomputeDistancesIfPossible();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Image pick
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage(imageQuality: 85);
    if (picked.isNotEmpty) {
      setState(() {
        _newImages
          ..clear()
          ..addAll(picked.map((x) => File(x.path)));
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Geocoding (OpenStreetMap Nominatim)
  // ─────────────────────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────────────────────
  // Schools fetching + distance computation (Haversine)
  // ─────────────────────────────────────────────────────────────────────────────
  Future<List<_School>> _fetchSchools() async {
    final snap = await FirebaseFirestore.instance.collection('schools').get();
    return snap.docs.map((d) {
      final m = d.data();
      return _School(
        id: d.id,
        name: (m['name'] ?? '').toString(),
        latitude: (m['latitude'] as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
      );
    }).toList();
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371.0; // km
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRad(double degrees) => degrees * math.pi / 180.0;

  Future<({double km, String id, String name})> _computeNearestSchool({
    required double lat,
    required double lng,
  }) async {
    final schools = await _fetchSchools();
    if (schools.isEmpty) {
      throw Exception('No schools found in Firestore (collection "schools").');
    }

    _School? best;
    double? bestKm;

    for (final s in schools) {
      final dist = _haversineKm(lat, lng, s.latitude, s.longitude);
      if (bestKm == null || dist < bestKm) {
        best = s;
        bestKm = dist;
      }
    }

    return (
      km: bestKm ?? double.nan,
      id: best?.id ?? '',
      name: best?.name ?? '',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Nearest public transport stop using Overpass API
  // ─────────────────────────────────────────────────────────────────────────────
  Future<({double km, String name})> _computeNearestTransitStop({
    required double lat,
    required double lng,
  }) async {
    final radii = [500, 1000, 1500, 2500]; // meters
    for (final r in radii) {
      final query =
          """
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
          bestName =
              (tags?['name'] ??
                      tags?['ref'] ??
                      tags?['uic_name'] ??
                      tags?['uic_ref'] ??
                      'Stop')
                  .toString();
        }
      }
      if (bestKm != null) return (km: bestKm, name: bestName);
    }
    throw Exception('No public transport stops found within 2.5 km.');
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Distances recompute
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _recomputeDistancesIfPossible() async {
    final address = _addressCtrl.text.trim();
    final city = _cityCtrl.text.trim();
    final npa = _npaCtrl.text.trim();
    if (address.isEmpty || city.isEmpty || npa.isEmpty) return;

    setState(() {
      _isComputingHes = true;
      _isComputingTransit = true;
    });
    try {
      // Always refresh coords from current address fields
      final coords = await _geocodeAddress(
        address: address,
        city: city,
        npa: npa,
      );
      _geoLat = coords.lat;
      _geoLng = coords.lng;

      // HES
      final nearest = await _computeNearestSchool(lat: _geoLat!, lng: _geoLng!);
      setState(() {
        _proximHesKm = nearest.km;
        _nearestHesId = nearest.id;
        _nearestHesName = nearest.name;
      });

      // Transit
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

  // ─────────────────────────────────────────────────────────────────────────────
  // Availability pickers
  // ─────────────────────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────────────────────
  // Estimate helpers (same contract as New)
  // ─────────────────────────────────────────────────────────────────────────────
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
        (_nearestHesId?.isEmpty ?? true)) {
      final nearest = await _computeNearestSchool(lat: _geoLat!, lng: _geoLng!);
      _proximHesKm = nearest.km;
      _nearestHesId = nearest.id;
      _nearestHesName = nearest.name;
    }
    if (_distTransitKm == null) {
      final t = await _computeNearestTransitStop(lat: _geoLat!, lng: _geoLng!);
      _distTransitKm = t.km;
      _nearestTransitName = t.name;
    }
  }

  Map<String, dynamic> _buildExactEstimatePayload() {
    double reqNum(String label, String s, {double? min}) {
      final raw = s.trim();
      if (raw.isEmpty) throw '$label is required';
      final v = double.tryParse(raw.replaceAll(',', '.'));
      if (v == null) throw '$label must be a number';
      if (min != null && v < min)
        throw '$label must be ≥ ${min.toStringAsFixed(0)}';
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
      throw 'Nearest public transport distance is not available yet; try again.';
    }

    return {
      "latitude": _geoLat!,
      "longitude": _geoLng!,
      "surface_m2": reqNum('Surface (m²)', _surfaceCtrl.text, min: 1),
      "num_rooms": reqInt('Number of rooms', _roomsCtrl.text, min: 1),
      "type": _typeOptions[_typeIndex] == 'Single room'
          ? "room"
          : "entire_home",
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
      await _ensureGeoAndNearestSchool();

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
    setState(() {}); // refresh validators
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Save flow
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate availability rules
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

      // Parse numbers
      double parseD(String s) => double.parse(s.replaceAll(',', '.'));
      int parseI(String s) => int.parse(s);

      // Price must be > 0 and on 0.05 step (align with NewListingPage)
      final price = parseD(_priceCtrl.text);
      if (price <= 0) {
        setState(() {
          _saving = false;
          _error = 'Price must be > 0.';
        });
        return;
      }
      if (!_isOn005Step(price)) {
        setState(() {
          _saving = false;
          _error = 'Price must be multiple of 0.05.';
        });
        return;
      }

      // Re-geocode / recompute distances if address|npa|city changed or coords are null
      final currentAddrKey =
          '${_addressCtrl.text.trim()}|${_npaCtrl.text.trim()}|${_cityCtrl.text.trim()}';
      final needGeocode =
          _geoLat == null ||
          _geoLng == null ||
          currentAddrKey != _initialAddrKey;

      if (needGeocode) {
        final coords = await _geocodeAddress(
          address: _addressCtrl.text.trim(),
          city: _cityCtrl.text.trim(),
          npa: _npaCtrl.text.trim(),
        );
        _geoLat = coords.lat;
        _geoLng = coords.lng;

        final nearest = await _computeNearestSchool(
          lat: _geoLat!,
          lng: _geoLng!,
        );
        _proximHesKm = nearest.km;
        _nearestHesId = nearest.id;
        _nearestHesName = nearest.name;

        final t = await _computeNearestTransitStop(
          lat: _geoLat!,
          lng: _geoLng!,
        );
        _distTransitKm = t.km;
        _nearestTransitName = t.name;
      } else {
        // If distances are still missing for any reason, compute them now
        if (_proximHesKm == null ||
            _nearestHesId == null ||
            (_nearestHesName == null || _nearestHesName!.isEmpty)) {
          final nearest = await _computeNearestSchool(
            lat: _geoLat!,
            lng: _geoLng!,
          );
          _proximHesKm = nearest.km;
          _nearestHesId = nearest.id;
          _nearestHesName = nearest.name;
        }
        if (_distTransitKm == null) {
          final t = await _computeNearestTransitStop(
            lat: _geoLat!,
            lng: _geoLng!,
          );
          _distTransitKm = t.km;
          _nearestTransitName = t.name;
        }
      }

      // Build update data
      final data = <String, dynamic>{
        'price': price,
        'address': _addressCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'npa': _npaCtrl.text.trim(),
        'latitude': _geoLat,
        'longitude': _geoLng,
        'surface': _surfaceCtrl.text.trim().isEmpty
            ? null
            : parseD(_surfaceCtrl.text),
        'num_rooms': _roomsCtrl.text.trim().isEmpty
            ? null
            : parseI(_roomsCtrl.text),
        'type': _typeOptions[_typeIndex] == "Entire home"
            ? "entire_home"
            : "room",
        'is_furnish': _isFurnish,
        'floor': _floorCtrl.text.trim().isEmpty
            ? null
            : parseI(_floorCtrl.text),
        'wifi_incl': _wifiIncl,
        'charges_incl': _chargesIncl,
        'car_park': _carPark,

        // Auto-computed distances
        'dist_public_transport_km': _distTransitKm,
        'nearest_transit_name': _nearestTransitName,
        'proxim_hesso_km': _proximHesKm,
        'nearest_hesso_id': _nearestHesId,
        'nearest_hesso_name': _nearestHesName,

        // Availability:
        'availability_start': Timestamp.fromDate(_availStart!),
        'availability_end': _noEndDate || _availEnd == null
            ? null
            : Timestamp.fromDate(_availEnd!),

        'updatedAt': Timestamp.now(),
      };

      // 1) Update document fields
      await FirebaseFirestore.instance
          .collection('listings')
          .doc(widget.listingId)
          .update(data);

      // 2) Handle images: remove selected, then upload new, then save final photos array
      List<String> finalPhotos = List.of(_existingPhotos);

      if (_photosToRemove.isNotEmpty) {
        finalPhotos.removeWhere((url) => _photosToRemove.contains(url));
        // If your repository supports deletion in storage, call it here.
        // await _repo.deleteListingImages(urls: _photosToRemove.toList());
      }

      if (_newImages.isNotEmpty) {
        final urls = await _repo.uploadListingImages(
          ownerUid: user.uid,
          listingId: widget.listingId,
          files: _newImages,
        );
        finalPhotos.addAll(urls);
      }

      // Persist final photos array
      await FirebaseFirestore.instance
          .collection('listings')
          .doc(widget.listingId)
          .update({'photos': finalPhotos});

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Listing updated.')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // MOON input helper
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

  // Small helper: image thumb for picked files
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
                _newImages.remove(f);
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
        title: const Text('Edit Listing'),
        actions: [
          if (!_loading)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${_existingPhotos.length + _newImages.length} photos',
                  style: TextStyle(color: cs.onSurface.withOpacity(.7)),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 720;
                final isXL = constraints.maxWidth >= 1100;

                final gap = 12.0;
                final double contentMax = 900;
                final double gridWidth = (constraints.maxWidth.clamp(
                  360,
                  contentMax,
                )).toDouble();
                final double fieldWidth = isWide
                    ? ((gridWidth - gap) / 2)
                    : gridWidth;

                // Image grid sizes
                final thumbsPerRow = isWide ? 4 : 2;
                final thumbSize =
                    (gridWidth - (thumbsPerRow - 1) * 8) / thumbsPerRow;

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
                                // SINGLE unified card (Basics + Amenities + Availability + Distances + Photos + Pricing)
                                _MoonCard(
                                  isDark: isDark,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
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

                                      // --- BASICS ---
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
                                          // Address + suggestions
                                          SizedBox(
                                            width: fieldWidth,
                                            child: Column(
                                              children: [
                                                _moonInput(
                                                  controller: _addressCtrl,
                                                  hint:
                                                      'Address (street & number)',
                                                  keyboardType: TextInputType
                                                      .streetAddress,
                                                  leading: const Icon(
                                                    Icons.place_outlined,
                                                  ),
                                                  validator: (v) =>
                                                      (v == null || v.isEmpty)
                                                      ? 'Required'
                                                      : null,
                                                  textAlign: TextAlign.center,
                                                  focusNode: _addressFocus,
                                                ),
                                                if (_addressFocus.hasFocus ||
                                                    _isLoadingAddr ||
                                                    _addressSuggestions
                                                        .isNotEmpty)
                                                  const SizedBox(height: 6),
                                                if (_isLoadingAddr)
                                                  const LinearProgressIndicator(
                                                    minHeight: 2,
                                                  ),
                                                if (_addressSuggestions
                                                    .isNotEmpty)
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      color: Theme.of(
                                                        context,
                                                      ).cardColor,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                      border: Border.all(
                                                        color: cs.primary
                                                            .withOpacity(.15),
                                                      ),
                                                    ),
                                                    child: ListView.separated(
                                                      shrinkWrap: true,
                                                      physics:
                                                          const NeverScrollableScrollPhysics(),
                                                      itemCount:
                                                          _addressSuggestions
                                                              .length,
                                                      separatorBuilder:
                                                          (_, __) => Divider(
                                                            height: 1,
                                                            color: cs.primary
                                                                .withOpacity(
                                                                  .08,
                                                                ),
                                                          ),
                                                      itemBuilder: (ctx, i) {
                                                        final s =
                                                            _addressSuggestions[i];
                                                        return ListTile(
                                                          dense: true,
                                                          leading: const Icon(
                                                            Icons
                                                                .location_on_outlined,
                                                          ),
                                                          title: Text(
                                                            s.displayName,
                                                            maxLines: 2,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                          onTap: () =>
                                                              _applySuggestion(
                                                                s,
                                                              ),
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
                                                  (v == null || v.isEmpty)
                                                  ? 'Required'
                                                  : null,
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                          SizedBox(
                                            width: fieldWidth,
                                            child: _moonInput(
                                              controller: _npaCtrl,
                                              hint: 'Postal code (NPA)',
                                              keyboardType:
                                                  TextInputType.number,
                                              leading: const Icon(
                                                Icons
                                                    .local_post_office_outlined,
                                              ),
                                              validator: (v) =>
                                                  (v == null || v.isEmpty)
                                                  ? 'Required'
                                                  : null,
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                          SizedBox(
                                            width: fieldWidth,
                                            child: _moonInput(
                                              controller: _surfaceCtrl,
                                              hint: 'Surface (m²)',
                                              keyboardType:
                                                  TextInputType.number,
                                              leading: const Icon(
                                                Icons.square_foot_outlined,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                          SizedBox(
                                            width: fieldWidth,
                                            child: _moonInput(
                                              controller: _roomsCtrl,
                                              hint: 'Number of rooms',
                                              keyboardType:
                                                  TextInputType.number,
                                              leading: const Icon(
                                                Icons.meeting_room_outlined,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                          SizedBox(
                                            width: fieldWidth,
                                            child: _moonInput(
                                              controller: _floorCtrl,
                                              hint: 'Floor',
                                              keyboardType:
                                                  TextInputType.number,
                                              leading: const Icon(
                                                Icons.unfold_more_outlined,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),

                                          // Type
                                          SizedBox(
                                            width: gridWidth,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Text(
                                                  'Type',
                                                  style: TextStyle(
                                                    color: cs.onSurface
                                                        .withOpacity(.8),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                LayoutBuilder(
                                                  builder: (context, box) {
                                                    final isNarrow =
                                                        box.maxWidth < 300;
                                                    if (isNarrow) {
                                                      return Wrap(
                                                        spacing: 8,
                                                        runSpacing: 8,
                                                        alignment: WrapAlignment
                                                            .center,
                                                        children: List.generate(
                                                          _typeOptions.length,
                                                          (i) {
                                                            return SizedBox(
                                                              width:
                                                                  box.maxWidth,
                                                              child: MoonSegmentedControl(
                                                                initialIndex:
                                                                    _typeIndex ==
                                                                        i
                                                                    ? 0
                                                                    : -1,
                                                                segments: [
                                                                  Segment(
                                                                    label: Text(
                                                                      _typeOptions[i],
                                                                    ),
                                                                  ),
                                                                ],
                                                                onSegmentChanged:
                                                                    (
                                                                      _,
                                                                    ) => setState(
                                                                      () =>
                                                                          _typeIndex =
                                                                              i,
                                                                    ),
                                                                isExpanded:
                                                                    true,
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      );
                                                    }
                                                    return MoonSegmentedControl(
                                                      initialIndex: _typeIndex,
                                                      segments: _typeOptions
                                                          .map(
                                                            (t) => Segment(
                                                              label: Text(t),
                                                            ),
                                                          )
                                                          .toList(),
                                                      onSegmentChanged: (i) =>
                                                          setState(
                                                            () =>
                                                                _typeIndex = i,
                                                          ),
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
                                      Divider(
                                        color: cs.primary.withOpacity(.1),
                                      ),
                                      const SizedBox(height: 8),

                                      // --- AMENITIES ---
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
                                              onChanged: (v) => setState(
                                                () => _isFurnish = v,
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: fieldWidth,
                                            child: _AmenitySwitch(
                                              title: 'Wifi included?',
                                              value: _wifiIncl,
                                              onChanged: (v) =>
                                                  setState(() => _wifiIncl = v),
                                            ),
                                          ),
                                          SizedBox(
                                            width: fieldWidth,
                                            child: _AmenitySwitch(
                                              title: 'Charges included?',
                                              value: _chargesIncl,
                                              onChanged: (v) => setState(
                                                () => _chargesIncl = v,
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: fieldWidth,
                                            child: _AmenitySwitch(
                                              title: 'Car park?',
                                              value: _carPark,
                                              onChanged: (v) =>
                                                  setState(() => _carPark = v),
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 16),
                                      Divider(
                                        color: cs.primary.withOpacity(.1),
                                      ),
                                      const SizedBox(height: 8),

                                      // --- AVAILABILITY ---
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
                                                    onTap: _noEndDate
                                                        ? null
                                                        : _pickEndDate,
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
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      'No end',
                                                      style: TextStyle(
                                                        color: cs.onSurface
                                                            .withOpacity(.8),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    MoonSwitch(
                                                      value: _noEndDate,
                                                      onChanged: (v) =>
                                                          setState(() {
                                                            _noEndDate = v;
                                                            if (v)
                                                              _availEnd = null;
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
                                      Divider(
                                        color: cs.primary.withOpacity(.1),
                                      ),
                                      const SizedBox(height: 8),

                                      // --- DISTANCES (two separate lines, no input field) ---
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
                                      // Line 1: Nearest transit
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          if (_isComputingTransit)
                                            const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          if (_isComputingTransit)
                                            const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              _distTransitKm == null
                                                  ? 'Nearest transit: —'
                                                  : 'Nearest transit: ${_nearestTransitName?.isNotEmpty == true ? _nearestTransitName : 'Stop'} • ${_distTransitKm!.toStringAsFixed(2)} km',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: cs.onSurface.withOpacity(
                                                  .85,
                                                ),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      // Line 2: HES proximity
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          if (_isComputingHes)
                                            const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          if (_isComputingHes)
                                            const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              _proximHesKm == null
                                                  ? 'HES proximity: —'
                                                  : (_nearestHesName == null ||
                                                        _nearestHesName!
                                                            .isEmpty)
                                                  ? 'HES proximity: ${_proximHesKm!.toStringAsFixed(2)} km'
                                                  : 'HES proximity: ${_nearestHesName!} • ${_proximHesKm!.toStringAsFixed(2)} km',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: cs.onSurface.withOpacity(
                                                  .85,
                                                ),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 16),
                                      Divider(
                                        color: cs.primary.withOpacity(.1),
                                      ),
                                      const SizedBox(height: 8),

                                      // --- PHOTOS (existing + add/remove + new previews) ---
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

                                      if (_existingPhotos.isEmpty)
                                        Text(
                                          'No existing photos',
                                          style: TextStyle(
                                            color: cs.onSurface.withOpacity(.7),
                                          ),
                                        ),
                                      if (_existingPhotos.isNotEmpty)
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: _existingPhotos.map((url) {
                                            final selected = _photosToRemove
                                                .contains(url);
                                            return Stack(
                                              children: [
                                                Container(
                                                  width: thumbSize,
                                                  height: thumbSize,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    border: Border.all(
                                                      color: selected
                                                          ? Colors.redAccent
                                                          : cs.primary
                                                                .withOpacity(
                                                                  .15,
                                                                ),
                                                      width: selected ? 2 : 1,
                                                    ),
                                                    image: DecorationImage(
                                                      image: NetworkImage(url),
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  top: 6,
                                                  right: 6,
                                                  child: InkWell(
                                                    onTap: () {
                                                      setState(() {
                                                        if (selected) {
                                                          _photosToRemove
                                                              .remove(url);
                                                        } else {
                                                          _photosToRemove.add(
                                                            url,
                                                          );
                                                        }
                                                      });
                                                    },
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: selected
                                                            ? Colors.redAccent
                                                            : Colors.black45,
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Icon(
                                                        selected
                                                            ? Icons.check
                                                            : Icons.close,
                                                        size: 14,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                          }).toList(),
                                        ),

                                      const SizedBox(height: 12),

                                      if (_newImages.isNotEmpty)
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: _newImages
                                              .map(
                                                (f) => SizedBox(
                                                  width: thumbSize,
                                                  height: thumbSize,
                                                  child: _imageThumb(f, cs),
                                                ),
                                              )
                                              .toList(),
                                        ),

                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          MoonButton(
                                            onTap: _pickImages,
                                            leading: const Icon(
                                              Icons
                                                  .add_photo_alternate_outlined,
                                            ),
                                            label: const Text('Add images'),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            '${_existingPhotos.length} existing • ${_newImages.length} new',
                                            style: TextStyle(
                                              color: cs.onSurface.withOpacity(
                                                .7,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 16),
                                      Divider(
                                        color: cs.primary.withOpacity(.1),
                                      ),
                                      const SizedBox(height: 8),

                                      // --- PRICING (identical to NewListingPage) ---
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

                                      // Price field same width as others + Estimate button
                                      SizedBox(
                                        width: fieldWidth,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: _moonInput(
                                                controller: _priceCtrl,
                                                hint: 'Price (CHF)',
                                                keyboardType:
                                                    TextInputType.number,
                                                leading: const Icon(
                                                  MoonIcons
                                                      .arrows_boost_24_regular,
                                                ),
                                                validator: (v) {
                                                  if (v == null || v.isEmpty) {
                                                    return 'Required';
                                                  }
                                                  final value = double.tryParse(
                                                    v.replaceAll(',', '.'),
                                                  );
                                                  if (value == null) {
                                                    return 'Invalid number';
                                                  }
                                                  if (value <= 0) {
                                                    return 'Must be > 0';
                                                  }
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
                                              onTap: _estimating
                                                  ? null
                                                  : _estimatePrice,
                                              leading: _estimating
                                                  ? const SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                    )
                                                  : const Icon(
                                                      Icons.calculate_outlined,
                                                    ),
                                              label: Text(
                                                _estimating
                                                    ? '...'
                                                    : 'Estimate',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      if (_estimatedPrice != null ||
                                          _estimationError != null) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(
                                              context,
                                            ).cardColor.withOpacity(.95),
                                            border: Border.all(
                                              color: cs.primary.withOpacity(
                                                .15,
                                              ),
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
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
                                                    const Icon(
                                                      Icons.trending_up,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        'Estimated price: CHF ${_estimatedPrice!.toStringAsFixed(2)}',
                                                        softWrap: true,
                                                        overflow:
                                                            TextOverflow.fade,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: cs.onSurface,
                                                        ),
                                                      ),
                                                    ),
                                                    MoonButton(
                                                      onTap:
                                                          _applyEstimateToPriceField,
                                                      label: const Text(
                                                        'Apply',
                                                      ),
                                                      leading: const Icon(
                                                        Icons
                                                            .check_circle_outline,
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
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          MoonIcons.arrows_boost_24_regular,
                                        ),
                                  label: Text(
                                    _saving ? 'Saving…' : 'Save changes',
                                  ),
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

// Card container Moon-like (opacity in dark)
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

// Label + MoonSwitch line item
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

// Simple models
class _School {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  const _School({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

class _AddressSuggestion {
  final String displayName;
  final double? lat;
  final double? lon;
  final String city;
  final String postcode;

  const _AddressSuggestion({
    required this.displayName,
    required this.lat,
    required this.lon,
    required this.city,
    required this.postcode,
  });
}
