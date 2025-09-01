// lib/ui/view_listing_page.dart
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:moon_design/moon_design.dart';
import 'package:http/http.dart' as http;

import 'edit_listing_page.dart';

class ViewListingPage extends StatefulWidget {
  final String listingId;
  const ViewListingPage({super.key, required this.listingId});

  @override
  State<ViewListingPage> createState() => _ViewListingPageState();
}

class _ViewListingPageState extends State<ViewListingPage> {
  bool _loading = true;
  String? _error;

  // Données
  String _ownerUid = '';
  String _address = '';
  String _city = '';
  String _npa = '';
  double? _price;
  double? _surface;
  int? _rooms;
  int? _floor;
  bool _isFurnish = false;
  bool _wifiIncl = false;
  bool _chargesIncl = false;
  bool _carPark = false;
  String _type = 'room';
  double? _distTransportKm;

  double? _latitude;
  double? _longitude;
  double? _proximHesKm;
  String? _nearestHesId;

  DateTime? _availStart;
  DateTime? _availEnd;
  List<String> _photos = [];

  bool _estimatingPrice = false;
  double? _estimatedPrice;
  String? _estimateError;

  // Calendrier
  DateTime _shownMonth = _monthDate(DateTime.now());
  static DateTime _monthDate(DateTime d) => DateTime(d.year, d.month);
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // Carrousel
  late final PageController _photoCtrl;

  bool get _isOwner =>
      FirebaseAuth.instance.currentUser?.uid != null &&
      FirebaseAuth.instance.currentUser!.uid == _ownerUid;

  @override
  void initState() {
    super.initState();
    _photoCtrl = PageController(viewportFraction: 0.92);
    _load();
  }

  @override
  void dispose() {
    _photoCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
      _ownerUid = (m['ownerUid'] ?? '').toString();

      _address = (m['address'] ?? '').toString();
      _city = (m['city'] ?? '').toString();
      _npa = (m['npa'] ?? '').toString();

      _price = (m['price'] as num?)?.toDouble();
      _surface = (m['surface'] as num?)?.toDouble();
      _rooms = (m['num_rooms'] as num?)?.toInt();
      _floor = (m['floor'] as num?)?.toInt();

      _isFurnish = (m['is_furnish'] ?? false) as bool;
      _wifiIncl = (m['wifi_incl'] ?? false) as bool;
      _chargesIncl = (m['charges_incl'] ?? false) as bool;
      _carPark = (m['car_park'] ?? false) as bool;

      _type = (m['type'] ?? 'room').toString().trim();
      _distTransportKm = (m['dist_public_transport_km'] as num?)?.toDouble();

      _latitude = (m['latitude'] as num?)?.toDouble();
      _longitude = (m['longitude'] as num?)?.toDouble();
      _proximHesKm = (m['proxim_hesso_km'] as num?)?.toDouble();
      _nearestHesId = (m['nearest_hesso_id'] ?? '').toString();

      final tsStart = m['availability_start'] as Timestamp?;
      final tsEnd = m['availability_end'] as Timestamp?;
      _availStart = tsStart?.toDate();
      _availEnd = tsEnd?.toDate();

      final List photos = (m['photos'] as List?) ?? const [];
      _photos = photos.map((e) => e.toString()).toList();

      setState(() {
        _loading = false;
        if (_availStart != null) _shownMonth = _monthDate(_availStart!);
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load listing: $e';
        _loading = false;
      });
    }
  }

  Future<void> _estimatePrice() async {
    // Vérifier que nous avons les données nécessaires
    if (_latitude == null || 
        _longitude == null || 
        _surface == null || 
        _rooms == null || 
        _floor == null ||
        _distTransportKm == null ||
        _proximHesKm == null) {
      setState(() {
        _estimateError = 'Missing data for estimation';
      });
      return;
    }

    setState(() {
      _estimatingPrice = true;
      _estimateError = null;
    });

    try {
      final body = [
        {
          "latitude": _latitude!,
          "longitude": _longitude!,
          "surface_m2": _surface!,
          "num_rooms": _rooms!,
          "type": _type,
          "is_furnished": _isFurnish,
          "floor": _floor!,
          "wifi_incl": _wifiIncl,
          "charges_incl": _chargesIncl,
          "car_park": _carPark,
          "dist_public_transport_km": _distTransportKm!,
          "proxim_hesso_km": _proximHesKm!,
        }
      ];

      final response = await http.post(
        Uri.parse('https://hestimate-api-production.up.railway.app/estimate-price'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List && data.isNotEmpty && data[0]['predicted_price_chf'] != null) {
          setState(() {
            _estimatedPrice = (data[0]['predicted_price_chf'] as num).toDouble();
            _estimatingPrice = false;
          });
        } else {
          setState(() {
            _estimateError = 'Unexpected response format';
            _estimatingPrice = false;
          });
        }
      } else {
        setState(() {
          _estimateError = 'Erreur ${response.statusCode}: ${response.body}';
          _estimatingPrice = false;
        });
      }
    } catch (e) {
      setState(() {
        _estimateError = 'Erreur de connexion: $e';
        _estimatingPrice = false;
      });
    }
  }

  // Calendrier
  bool _isAvailableOn(DateTime day) {
    if (_availStart == null) return false;
    final d = _dateOnly(day);
    final start = _dateOnly(_availStart!);
    if (_availEnd == null) return !d.isBefore(start);
    final end = _dateOnly(_availEnd!);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  void _prevMonth() {
    final d = DateTime(_shownMonth.year, _shownMonth.month - 1);
    setState(() => _shownMonth = _monthDate(d));
  }

  void _nextMonth() {
    final d = DateTime(_shownMonth.year, _shownMonth.month + 1);
    setState(() => _shownMonth = _monthDate(d));
  }

  List<Widget> _buildCalendar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final firstOfMonth = DateTime(_shownMonth.year, _shownMonth.month, 1);
    final int daysInMonth = DateTime(
      _shownMonth.year,
      _shownMonth.month + 1,
      0,
    ).day;

    final int weekdayStart = firstOfMonth.weekday; // 1..7 (Mon..Sun)
    final int leadingEmpty = weekdayStart - 1;
    final items = <Widget>[];

    const names = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    items.addAll(
      names.map((n) {
        return Center(
          child: Text(
            n,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: cs.onSurface.withOpacity(.75),
            ),
          ),
        );
      }),
    );

    for (var i = 0; i < leadingEmpty; i++) {
      items.add(const SizedBox.shrink());
    }

    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_shownMonth.year, _shownMonth.month, day);
      final available = _isAvailableOn(date);

      items.add(
        Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: available ? cs.primary.withOpacity(.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: available
                  ? cs.primary.withOpacity(.45)
                  : cs.primary.withOpacity(.12),
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              '$day',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: available ? cs.primary : cs.onSurface,
              ),
            ),
          ),
        ),
      );
    }

    return items;
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
        title: const Text('Listing'),
        leading: Builder(
          builder: (context) {
            final canPop = Navigator.of(context).canPop();
            return IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: canPop ? 'Back' : 'Home',
              onPressed: () {
                if (canPop) {
                  Navigator.of(context).pop();
                } else {
                  // No back stack (e.g., after pushReplacement) → go Home.
                  Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/home', (route) => false);
                  // If you want to land on a specific tab inside HomeMenuPage,
                  // pass an index as arguments, e.g.:
                  // Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false, arguments: 0); // Dashboard
                  // Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false, arguments: 1); // Properties
                }
              },
            );
          },
        ),
        actions: [
          if (!_loading && _isOwner)
            IconButton(
              tooltip: 'Edit',
              onPressed: () {
                Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) =>
                            EditListingPage(listingId: widget.listingId),
                      ),
                    )
                    .then((_) => _load());
              },
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;
                const contentMax = 1000.0;

                // ❗ Fix: ne jamais produire un padding négatif
                final horizontalPad = math.max(
                  16.0,
                  (constraints.maxWidth - contentMax) / 2 + 16.0,
                );

                return Container(
                  decoration: bg,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? horizontalPad : 16.0,
                      vertical: 16.0,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: contentMax),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Photos
                            _MoonCard(
                              isDark: isDark,
                              child: _photos.isEmpty
                                  ? Container(
                                      height: 180,
                                      alignment: Alignment.center,
                                      child: Text(
                                        'No photos',
                                        style: TextStyle(
                                          color: cs.onSurface.withOpacity(.7),
                                        ),
                                      ),
                                    )
                                  : SizedBox(
                                      height: 220,
                                      child: PageView.builder(
                                        controller: _photoCtrl,
                                        padEnds: false,
                                        itemCount: _photos.length,
                                        itemBuilder: (_, i) {
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  Image.network(
                                                    _photos[i],
                                                    fit: BoxFit.cover,
                                                  ),
                                                  Positioned(
                                                    right: 8,
                                                    bottom: 8,
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.black54,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        '${i + 1}/${_photos.length}',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                            ),

                            const SizedBox(height: 16),

                            // Header + bouton Edit (si propriétaire)
                            _MoonCard(
                              isDark: isDark,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _type == 'entire_home'
                                                  ? 'Entire home'
                                                  : 'Single room',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800,
                                                color: cs.onSurface,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '$_address, $_npa $_city',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: cs.onSurface.withOpacity(
                                                  .8,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_isOwner)
                                        MoonButton(
                                          onTap: () async {
                                            await Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => EditListingPage(
                                                  listingId: widget.listingId,
                                                ),
                                              ),
                                            );
                                            _load();
                                          },
                                          leading: const Icon(Icons.edit),
                                          label: const Text('Edit'),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 8,
                                    children: [
                                      _chip(
                                        context,
                                        icon: Icons.price_change_outlined,
                                        text: _price != null
                                            ? '${_price!.toStringAsFixed(0)} CHF/mo'
                                            : '—',
                                      ),
                                      _chip(
                                        context,
                                        icon: Icons.square_foot_outlined,
                                        text: _surface != null
                                            ? '${_surface!.toStringAsFixed(0)} m²'
                                            : '—',
                                      ),
                                      _chip(
                                        context,
                                        icon: Icons.meeting_room_outlined,
                                        text: _rooms != null
                                            ? '$_rooms rooms'
                                            : '—',
                                      ),
                                      _chip(
                                        context,
                                        icon: Icons.unfold_more_outlined,
                                        text: _floor != null
                                            ? 'Floor $_floor'
                                            : '—',
                                      ),
                                      _chip(
                                        context,
                                        icon: Icons.directions_bus_outlined,
                                        text: _distTransportKm != null
                                            ? '${_distTransportKm!.toStringAsFixed(1)} km PT'
                                            : '—',
                                      ),
                                      _chip(
                                        context,
                                        icon: Icons.school_outlined,
                                        text: _proximHesKm != null
                                            ? '${_proximHesKm!.toStringAsFixed(1)} km HES'
                                            : '—',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Amenities
                            _MoonCard(
                              isDark: isDark,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.tune, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Amenities',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: cs.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _amenityPill(
                                        context,
                                        'Furnished',
                                        _isFurnish,
                                      ),
                                      _amenityPill(
                                        context,
                                        'Wifi included',
                                        _wifiIncl,
                                      ),
                                      _amenityPill(
                                        context,
                                        'Charges included',
                                        _chargesIncl,
                                      ),
                                      _amenityPill(
                                        context,
                                        'Car park',
                                        _carPark,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            _MoonCard(
                              isDark: isDark,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.analytics_outlined, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Price estimation',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: cs.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (_estimatedPrice != null) ...[
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: cs.primary.withOpacity(0.12),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.trending_up, color: cs.primary, size: 24),
                                        const SizedBox(width: 12),
                                        Expanded( // ✅ ça permet au texte de se couper si nécessaire
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Estimated price',
                                                style: TextStyle(
                                                  color: cs.onSurface.withOpacity(.8),
                                                  fontSize: 14,
                                                ),
                                              ),
                                              Text(
                                                '${((_estimatedPrice! / 0.05).round() * 0.05).toStringAsFixed(2)} CHF/mois',
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                                overflow: TextOverflow.ellipsis, // ✅ coupe si trop long
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (_price != null) ...[
                                          const SizedBox(width: 12),
                                          Expanded( // ✅ pareil pour la partie "Actual price"
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  'Actual price',
                                                  style: TextStyle(
                                                    color: cs.onSurface.withOpacity(.8),
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                Text(
                                                  '${((_price! / 0.05).round() * 0.05).toStringAsFixed(2)} CHF/mois',
                                                  style: TextStyle(
                                                    color: cs.onSurface,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  '${((_price! - _estimatedPrice!) / 0.05).round() * 0.05 >= 0 ? '+' : ''}${(((_price! - _estimatedPrice!) / 0.05).round() * 0.05).toStringAsFixed(2)} CHF/mois',
                                                  style: TextStyle(
                                                    color: (_price! > _estimatedPrice!) 
                                                        ? Colors.red 
                                                        : Colors.green,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    ),
                                                  overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  if (_estimateError != null) ...[
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.error_outline, color: Colors.red, size: 20),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _estimateError!,
                                              style: const TextStyle(color: Colors.red),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  MoonFilledButton(
                                    onTap: _estimatingPrice ? null : _estimatePrice,
                                    isFullWidth: true,
                                    leading: _estimatingPrice 
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.calculate_outlined),
                                    label: Text(_estimatingPrice ? 'Estimating...': 'Estimate price'),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Calendrier disponibilité
                            _MoonCard(
                              isDark: isDark,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.calendar_today_outlined,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Availability',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: cs.onSurface,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          IconButton(
                                            tooltip: 'Previous month',
                                            onPressed: _prevMonth,
                                            icon: const Icon(
                                              Icons.chevron_left,
                                            ),
                                          ),
                                          Text(
                                            '${_shownMonth.year}-${_shownMonth.month.toString().padLeft(2, '0')}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: cs.onSurface,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Next month',
                                            onPressed: _nextMonth,
                                            icon: const Icon(
                                              Icons.chevron_right,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  if (_availStart == null)
                                    Text(
                                      'No availability information.',
                                      style: TextStyle(
                                        color: cs.onSurface.withOpacity(.7),
                                      ),
                                    )
                                  else ...[
                                    GridView.count(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      crossAxisCount: 7,
                                      children: _buildCalendar(context),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Container(
                                          width: 16,
                                          height: 16,
                                          decoration: BoxDecoration(
                                            color: cs.primary.withOpacity(.25),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            border: Border.all(
                                              color: cs.primary.withOpacity(.6),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Available days',
                                          style: TextStyle(
                                            color: cs.onSurface.withOpacity(.8),
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          _availEnd == null
                                              ? 'From ${_fmt(_availStart!)} • no end'
                                              : '${_fmt(_availStart!)} → ${_fmt(_availEnd!)}',
                                          style: TextStyle(
                                            color: cs.onSurface.withOpacity(.8),
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            if (_isOwner)
                              MoonFilledButton(
                                isFullWidth: true,
                                onTap: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => EditListingPage(
                                        listingId: widget.listingId,
                                      ),
                                    ),
                                  );
                                  _load();
                                },
                                leading: const Icon(Icons.edit),
                                label: const Text('Edit listing'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _chip(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurface.withOpacity(.75)),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _amenityPill(BuildContext context, String title, bool on) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: on
            ? cs.primary.withOpacity(.15)
            : Theme.of(context).cardColor.withOpacity(.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: on ? cs.primary.withOpacity(.5) : cs.primary.withOpacity(.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            on ? Icons.check_circle_outline : Icons.remove_circle_outline,
            size: 16,
            color: on ? cs.primary : cs.onSurface.withOpacity(.6),
          ),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(color: cs.onSurface)),
        ],
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
