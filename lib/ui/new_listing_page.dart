// lib/ui/new_listing_page.dart
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

class NewListingPage extends StatefulWidget {
  const NewListingPage({super.key});
  @override
  State<NewListingPage> createState() => _NewListingPageState();
}

class _NewListingPageState extends State<NewListingPage> {
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
  final _distTransportCtrl = TextEditingController();

  // Address suggestions
  final FocusNode _addressFocus = FocusNode();
  Timer? _addrDebounce;
  List<_AddressSuggestion> _addressSuggestions = [];
  bool _isLoadingAddr = false;

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
  final List<File> _images = [];

  // Derived / auto-computed state
  double? _geoLat;
  double? _geoLng;
  double? _proximHesKm;   // auto
  String? _nearestHesId;  // auto (doc id)

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _addressCtrl.addListener(_onAddressChanged);
  }

  @override
  void dispose() {
    _addrDebounce?.cancel();
    _addressCtrl
      ..removeListener(_onAddressChanged)
      ..dispose();
    _addressFocus.dispose();

    _cityCtrl.dispose();
    _npaCtrl.dispose();
    _priceCtrl.dispose();
    _surfaceCtrl.dispose();
    _roomsCtrl.dispose();
    _floorCtrl.dispose();
    _distTransportCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Address suggestions (Nominatim) with debounce
  // ─────────────────────────────────────────────────────────────────────────────
  void _onAddressChanged() {
    _addrDebounce?.cancel();
    _addrDebounce = Timer(const Duration(milliseconds: 350), () async {
      final q = _addressCtrl.text.trim();
      if (q.length < 3) {
        if (mounted) {
          setState(() => _addressSuggestions = []);
        }
        return;
      }
      await _fetchAddressSuggestions(q);
    });
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
      final suggestions = data.map((e) {
        final m = e as Map<String, dynamic>;
        return _AddressSuggestion(
          displayName: (m['display_name'] ?? '').toString(),
          lat: double.tryParse(m['lat']?.toString() ?? ''),
          lon: double.tryParse(m['lon']?.toString() ?? ''),
          city: _tryAddrPiece(m, ['address', 'city']) ??
              _tryAddrPiece(m, ['address', 'town']) ??
              _tryAddrPiece(m, ['address', 'village']) ??
              '',
          postcode: _tryAddrPiece(m, ['address', 'postcode']) ?? '',
        );
      }).where((s) => s.lat != null && s.lon != null).take(6).toList();

      if (mounted) {
        setState(() => _addressSuggestions = suggestions);
      }
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
    _addressCtrl.text = s.displayName.split(',').first; // street + number (best effort)
    if (s.city.isNotEmpty) _cityCtrl.text = s.city;
    if (s.postcode.isNotEmpty) _npaCtrl.text = s.postcode;
    _geoLat = s.lat!;
    _geoLng = s.lon!;
    setState(() => _addressSuggestions = []);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Image pick
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage(imageQuality: 85);
    if (picked.isNotEmpty) {
      setState(() {
        _images
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
  // Firestore collection expected: "schools" with fields:
  // - name: String
  // - latitude: double
  // - longitude: double
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
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRad(double degrees) => degrees * math.pi / 180.0;

  Future<({double km, String id})> _computeNearestSchool({
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

    return (km: bestKm ?? double.nan, id: best?.id ?? '');
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
  // Save flow:
  // 1) Validate availability
  // 2) Geocode address -> lat/lng (unless already from suggestion)
  // 3) Compute nearest school
  // 4) Save listing (with availability_start & availability_end)
  // 5) Upload images
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

      // 1) Geocode (only if not provided by a suggestion)
      if (_geoLat == null || _geoLng == null) {
        final coords = await _geocodeAddress(
          address: _addressCtrl.text.trim(),
          city: _cityCtrl.text.trim(),
          npa: _npaCtrl.text.trim(),
        );
        _geoLat = coords.lat;
        _geoLng = coords.lng;
      }

      // 2) Nearest school (id + km)
      final nearest = await _computeNearestSchool(lat: _geoLat!, lng: _geoLng!);
      _proximHesKm = nearest.km;
      _nearestHesId = nearest.id;

      double parseD(String s) => double.parse(s.replaceAll(',', '.'));
      int parseI(String s) => int.parse(s);

      // 3) Build Firestore data
      final data = <String, dynamic>{
        'ownerUid': user.uid,
        'price': parseD(_priceCtrl.text),
        'address': _addressCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'npa': _npaCtrl.text.trim(),
        'latitude': _geoLat,
        'longitude': _geoLng,
        'surface': _surfaceCtrl.text.trim().isEmpty ? null : parseD(_surfaceCtrl.text),
        'num_rooms': _roomsCtrl.text.trim().isEmpty ? null : parseI(_roomsCtrl.text),
        'type': _typeOptions[_typeIndex] == "Entire home"?"entire_home":"room",
        'is_furnish': _isFurnish,
        'floor': _floorCtrl.text.trim().isEmpty ? null : parseI(_floorCtrl.text),
        'wifi_incl': _wifiIncl,
        'charges_incl': _chargesIncl,
        'car_park': _carPark,
        'dist_public_transport_km': _distTransportCtrl.text.trim().isEmpty ? null : parseD(_distTransportCtrl.text),

        // Auto-computed and stored:
        'proxim_hesso_km': _proximHesKm,
        'nearest_hesso_id': _nearestHesId,

        // Availability:
        'availability_start': Timestamp.fromDate(_availStart!),
        'availability_end': _noEndDate || _availEnd == null ? null : Timestamp.fromDate(_availEnd!),

        'photos': <String>[],
        'createdAt': Timestamp.now(),
      };

      // 4) Create listing
      final listingId = await _repo.createListing(data);

      // 5) Upload images (optional)
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

      if (mounted) {
        final km = _proximHesKm?.toStringAsFixed(2) ?? '?';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Listing saved. Nearest HES stored ($km km).')),
        );
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
        title: const Text('New Listing'),
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
          final double fieldWidth =
              isWide ? ((gridWidth - gap) / 2) : gridWidth;

          return Container(
            decoration: bg,
            child: AbsorbPointer(
              absorbing: _saving,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal:
                      isXL ? (constraints.maxWidth - contentMax) / 2 + 16 : 16,
                  vertical: 16,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentMax),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // ==== Basics ====
                          _MoonCard(
                            isDark: isDark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Remplacement d'icône Moon "safe"
                                    Icon(MoonIcons.arrows_boost_24_regular,
                                        size: 20, color: cs.primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Basics',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: gap,
                                  runSpacing: gap,
                                  children: [
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _moonInput(
                                        controller: _priceCtrl,
                                        hint: 'Price (CHF)',
                                        keyboardType: TextInputType.number,
                                        leading: const Icon(MoonIcons.arrows_boost_24_regular),
                                        validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),

                                    // Address + suggestions panel
                                    SizedBox(
                                      width: fieldWidth,
                                      child: Column(
                                        children: [
                                          _moonInput(
                                            controller: _addressCtrl,
                                            hint: 'Address (street & number)',
                                            keyboardType: TextInputType.streetAddress,
                                            leading: const Icon(Icons.place_outlined),
                                            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                                            textAlign: TextAlign.center,
                                            focusNode: _addressFocus,
                                          ),
                                          if (_addressFocus.hasFocus || _isLoadingAddr || _addressSuggestions.isNotEmpty)
                                            const SizedBox(height: 6),
                                          if (_isLoadingAddr)
                                            const LinearProgressIndicator(minHeight: 2),
                                          if (_addressSuggestions.isNotEmpty)
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Theme.of(context).cardColor,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: cs.primary.withOpacity(.15)),
                                              ),
                                              child: ListView.separated(
                                                shrinkWrap: true,
                                                physics: const NeverScrollableScrollPhysics(),
                                                itemCount: _addressSuggestions.length,
                                                separatorBuilder: (_, __) => Divider(height: 1, color: cs.primary.withOpacity(.08)),
                                                itemBuilder: (ctx, i) {
                                                  final s = _addressSuggestions[i];
                                                  return ListTile(
                                                    dense: true,
                                                    leading: const Icon(Icons.location_on_outlined),
                                                    title: Text(
                                                      s.displayName,
                                                      maxLines: 2,
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
                                        leading: const Icon(Icons.location_city_outlined),
                                        validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _moonInput(
                                        controller: _npaCtrl,
                                        hint: 'Postal code (NPA)',
                                        keyboardType: TextInputType.number,
                                        leading: const Icon(Icons.local_post_office_outlined),
                                        validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _moonInput(
                                        controller: _surfaceCtrl,
                                        hint: 'Surface (m²)',
                                        keyboardType: TextInputType.number,
                                        leading: const Icon(Icons.square_foot_outlined),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _moonInput(
                                        controller: _roomsCtrl,
                                        hint: 'Number of rooms',
                                        keyboardType: TextInputType.number,
                                        leading: const Icon(Icons.meeting_room_outlined),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _moonInput(
                                        controller: _floorCtrl,
                                        hint: 'Floor',
                                        keyboardType: TextInputType.number,
                                        leading: const Icon(Icons.unfold_more_outlined),
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
                                                  children: List.generate(_typeOptions.length, (i) {
                                                    return SizedBox(
                                                      width: box.maxWidth,
                                                      child: MoonSegmentedControl(
                                                        initialIndex: _typeIndex == i ? 0 : -1,
                                                        segments: [Segment(label: Text(_typeOptions[i]))],
                                                        onSegmentChanged: (_) => setState(() => _typeIndex = i),
                                                        isExpanded: true,
                                                      ),
                                                    );
                                                  }),
                                                );
                                              }
                                              return MoonSegmentedControl(
                                                initialIndex: _typeIndex,
                                                segments: _typeOptions.map((t) => Segment(label: Text(t))).toList(),
                                                onSegmentChanged: (i) => setState(() => _typeIndex = i),
                                                isExpanded: true,
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ==== Amenities ====
                          _MoonCard(
                            isDark: isDark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(MoonIcons.arrows_cross_lines_24_regular, size: 20, color: cs.primary),
                                    const SizedBox(width: 8),
                                    Text('Amenities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.onSurface)),
                                  ],
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
                                        title: 'Wifi included?',
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
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ==== Availability ====
                          _MoonCard(
                            isDark: isDark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(MoonIcons.time_calendar_24_regular, size: 20, color: cs.primary),
                                    const SizedBox(width: 8),
                                    Text('Availability', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.onSurface)),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Start & End date pickers (more visible)
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
                                        leading: const Icon(Icons.event_available_outlined),
                                        label: Text('Start: ${_formatDate(_availStart)}'),
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
                                              leading: const Icon(Icons.event_note_outlined),
                                              label: Text(_noEndDate
                                                  ? 'End: None'
                                                  : 'End: ${_formatDate(_availEnd)}'),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text('No end', style: TextStyle(color: cs.onSurface.withOpacity(.8))),
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
                                  style: TextStyle(color: cs.onSurface.withOpacity(.65), fontSize: 12),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ==== Distances (only manual transport; HES auto & hidden) ====
                          _MoonCard(
                            isDark: isDark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(MoonIcons.arrows_diagonals_tlbr_24_regular, size: 20, color: cs.primary),
                                    const SizedBox(width: 8),
                                    Text('Distances', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.onSurface)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: fieldWidth,
                                  child: MoonFormTextInput(
                                    hasFloatingLabel: false,
                                    hintText: 'Distance to public transport (km)',
                                    controller: _distTransportCtrl,
                                    keyboardType: TextInputType.number,
                                    leading: const Icon(Icons.directions_bus_outlined),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'HES proximity is computed automatically from your address.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: cs.onSurface.withOpacity(.65), fontSize: 12),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ==== Images + Actions ====
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
                                style: TextStyle(color: cs.onSurface.withOpacity(.65)),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          if (_error != null)
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700),
                            ),

                          const SizedBox(height: 4),

                          MoonFilledButton(
                            isFullWidth: true,
                            onTap: _saving ? null : _save,
                            leading: _saving
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
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

// Card container Moon-like (opacité en dark)
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
              style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
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
