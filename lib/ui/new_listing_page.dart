import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

// Moon
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

  // Controllers
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _npaCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _surfaceCtrl = TextEditingController();
  final _roomsCtrl = TextEditingController();
  final _floorCtrl = TextEditingController();
  final _distTransportCtrl = TextEditingController();
  final _proximHessoCtrl = TextEditingController();
  final _nearestHessoCtrl = TextEditingController();

  // Type: Entire home / Single room  -> segmented control
  final _typeOptions = const ['Entire home', 'Single room'];
  int _typeIndex = 1;

  bool _isFurnish = false;
  bool _wifiIncl = false;
  bool _chargesIncl = false;
  bool _carPark = false;

  final ImagePicker _picker = ImagePicker();
  final List<File> _images = [];

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _npaCtrl.dispose();
    _priceCtrl.dispose();
    _surfaceCtrl.dispose();
    _roomsCtrl.dispose();
    _floorCtrl.dispose();
    _distTransportCtrl.dispose();
    _proximHessoCtrl.dispose();
    _nearestHessoCtrl.dispose();
    super.dispose();
  }

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

  // --- Geocoding using OpenStreetMap Nominatim ---
  Future<({double lat, double lng})> _geocodeAddress({
    required String address,
    required String city,
    required String npa,
  }) async {
    // Build a friendly single-line address
    final q = Uri.encodeQueryComponent('$address, $npa $city, Switzerland');
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=$q&format=json&limit=1',
    );

    final res = await http.get(
      uri,
      headers: const {
        // Nominatim etiquette: identify your app
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // 1) Geocode the address -> lat/lng
      final coords = await _geocodeAddress(
        address: _addressCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        npa: _npaCtrl.text.trim(),
      );

      double parseD(String s) => double.parse(s.replaceAll(',', '.'));
      int parseI(String s) => int.parse(s);

      // 2) Build Firestore data
      final data = <String, dynamic>{
        'ownerUid': user.uid,
        'price': parseD(_priceCtrl.text),
        'address': _addressCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'npa': _npaCtrl.text.trim(),
        'latitude': coords.lat,
        'longitude': coords.lng,
        'surface': _surfaceCtrl.text.trim().isEmpty ? null : parseD(_surfaceCtrl.text),
        'num_rooms': _roomsCtrl.text.trim().isEmpty ? null : parseI(_roomsCtrl.text),
        'type': _typeOptions[_typeIndex],
        'is_furnish': _isFurnish,
        'floor': _floorCtrl.text.trim().isEmpty ? null : parseI(_floorCtrl.text),
        'wifi_incl': _wifiIncl,
        'charges_incl': _chargesIncl,
        'car_park': _carPark,
        'dist_public_transport_km': _distTransportCtrl.text.trim().isEmpty ? null : parseD(_distTransportCtrl.text),
        'proxim_hesso_km': _proximHessoCtrl.text.trim().isEmpty ? null : parseD(_proximHessoCtrl.text),
        'nearest_hesso_name': _nearestHessoCtrl.text.trim(),
        'photos': <String>[],
        'createdAt': Timestamp.now(),
      };

      // 3) Create listing
      final listingId = await _repo.createListing(data);

      // 4) Upload images (optional)
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Listing saved successfully')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Moon input helper
  Widget _moonInput({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    Widget? leading,
    TextAlign textAlign = TextAlign.left, // allow centered text if needed
  }) {
    return MoonFormTextInput(
      hasFloatingLabel: false,
      hintText: hint,
      controller: controller,
      keyboardType: keyboardType,
      leading: leading,
      validator: validator,
      textAlign: textAlign,
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
          // Breakpoints
          final isWide = constraints.maxWidth >= 720;
          final isXL = constraints.maxWidth >= 1100;

          // Grid widths (fields centered)
          final gap = 12.0;
          final double contentMax = 900; // narrower to emphasize centering
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
                  // Center all content
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

                                // Responsive Wrap (centered)
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
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _moonInput(
                                        controller: _addressCtrl,
                                        hint: 'Address (street & number)',
                                        keyboardType: TextInputType.streetAddress,
                                        leading: const Icon(MoonIcons.arrows_forward_24_regular),
                                        validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _moonInput(
                                        controller: _cityCtrl,
                                        hint: 'City',
                                        leading: const Icon(MoonIcons.arrows_forward_24_regular),
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
                                        leading: const Icon(MoonIcons.arrows_down_24_regular),
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
                                        leading: const Icon(MoonIcons.arrows_bottom_right_24_regular),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _moonInput(
                                        controller: _roomsCtrl,
                                        hint: 'Number of rooms',
                                        keyboardType: TextInputType.number,
                                        leading: const Icon(MoonIcons.arrows_left_24_regular),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _moonInput(
                                        controller: _floorCtrl,
                                        hint: 'Floor',
                                        keyboardType: TextInputType.number,
                                        leading: const Icon(MoonIcons.arrows_refresh_24_regular),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    // Type selector (spans full "grid" width)
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
                                                  alignment:
                                                      WrapAlignment.center,
                                                  children: List.generate(
                                                      _typeOptions.length,
                                                      (i) {
                                                    return SizedBox(
                                                      width: box.maxWidth,
                                                      child:
                                                          MoonSegmentedControl(
                                                        initialIndex:
                                                            _typeIndex == i
                                                                ? 0
                                                                : -1,
                                                        segments: [
                                                          Segment(
                                                            label: Text(
                                                                _typeOptions[
                                                                    i]),
                                                          )
                                                        ],
                                                        onSegmentChanged: (_) =>
                                                            setState(() =>
                                                                _typeIndex =
                                                                    i),
                                                        isExpanded: true,
                                                      ),
                                                    );
                                                  }),
                                                );
                                              }
                                              return MoonSegmentedControl(
                                                initialIndex: _typeIndex,
                                                segments: _typeOptions
                                                    .map((t) =>
                                                        Segment(label: Text(t)))
                                                    .toList(),
                                                onSegmentChanged: (i) =>
                                                    setState(
                                                        () => _typeIndex = i),
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
                                    Icon(MoonIcons.arrows_cross_lines_24_regular,
                                        size: 20, color: cs.primary),
                                    const SizedBox(width: 8),
                                    Text('Amenities',
                                        style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            color: cs.onSurface)),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: gap,
                                  runSpacing: gap,
                                  children: [
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _AmenitySwitch(
                                        title: 'Have furniture?',
                                        value: _isFurnish,
                                        onChanged: (v) =>
                                            setState(() => _isFurnish = v),
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
                                        onChanged: (v) =>
                                            setState(() => _chargesIncl = v),
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
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ==== Distances ====
                          _MoonCard(
                            isDark: isDark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(MoonIcons.arrows_diagonals_tlbr_24_regular,
                                        size: 20, color: cs.primary),
                                    const SizedBox(width: 8),
                                    Text('Distances',
                                        style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            color: cs.onSurface)),
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
                                        controller: _distTransportCtrl,
                                        hint:
                                            'Distance to public transport (km)',
                                        keyboardType: TextInputType.number,
                                        leading: const Icon(
                                            MoonIcons.arrows_forward_24_regular),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: fieldWidth,
                                      child: _moonInput(
                                        controller: _proximHessoCtrl,
                                        hint: 'Proximity to HES (km)',
                                        keyboardType: TextInputType.number,
                                        leading: const Icon(
                                            MoonIcons.arrows_up_24_regular),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(
                                      width: gridWidth,
                                      child: _moonInput(
                                        controller: _nearestHessoCtrl,
                                        hint: 'Nearest HES name',
                                        keyboardType: TextInputType.text,
                                        leading: const Icon(MoonIcons
                                            .arrows_chevron_right_double_24_regular),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
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
                                leading: const Icon(
                                    MoonIcons.arrows_cross_lines_24_regular),
                                label: const Text('Pick images'),
                              ),
                              Text(
                                '${_images.length} selected',
                                style: TextStyle(
                                    color: cs.onSurface.withOpacity(.65)),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          if (_error != null)
                            Text(_error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.w700)),

                          const SizedBox(height: 4),

                          MoonFilledButton(
                            isFullWidth: true,
                            onTap: _saving ? null : _save,
                            leading: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(
                                    MoonIcons.arrows_boost_24_regular),
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
  const _AmenitySwitch(
      {required this.title, required this.value, required this.onChanged, super.key});

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
              child: Text(title,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600))),
          MoonSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Member {
  final String first;
  final String last;
  const _Member(this.first, this.last);
}
