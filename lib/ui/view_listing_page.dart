import 'dart:math' as math;
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:moon_design/moon_design.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';
import 'rate_listing_page.dart';

import 'rate_listing_page.dart';
import 'edit_listing_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:photo_view/photo_view.dart'; // ⬅️ needed for HeroAttributes & ComputedScale
// import 'rate_listing_page.dart'; // Add this import for RateListingPage

// Clé Google (Directions + Places)
final _googleMapsApiKey = dotenv.env['GOOGLE_API_KEY'] ?? '';

const _hesCollection = 'schools';

class ListingPhotoCarousel extends StatefulWidget {
  final List<String> imageUrls;
  final double aspectRatio;
  final BorderRadius? borderRadius;

  const ListingPhotoCarousel({
    super.key,
    required this.imageUrls,
    this.aspectRatio = 16 / 9,
    this.borderRadius,
  });

  @override
  State<ListingPhotoCarousel> createState() => _ListingPhotoCarouselState();
}

class _ListingPhotoCarouselState extends State<ListingPhotoCarousel> {
  final _ctrl = PageController(viewportFraction: .92);
  int _index = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = widget.borderRadius ?? BorderRadius.circular(16);

    if (widget.imageUrls.isEmpty) {
      return _EmptyImage(radius: radius);
    }

    return Column(
      children: [
        AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: PageView.builder(
            controller: _ctrl,
            itemCount: widget.imageUrls.length,
            onPageChanged: (i) => setState(() => _index = i),
            physics: const BouncingScrollPhysics(),
            itemBuilder: (_, i) {
              final url = widget.imageUrls[i];
              return AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.symmetric(horizontal: i == _index ? 4 : 10),
                child: _ImageCard(
                  url: url,
                  radius: radius,
                  onTap: () => _openGallery(context, startIndex: i),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        _Dots(count: widget.imageUrls.length, index: _index, color: cs.primary),
        const SizedBox(height: 4),
        if (widget.imageUrls.length > 1)
          Text(
            '${_index + 1}/${widget.imageUrls.length}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(.6),
              fontSize: 12,
            ),
          ),
      ],
    );
  }

  void _openGallery(BuildContext context, {required int startIndex}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => _FullscreenGallery(
          imageUrls: widget.imageUrls,
          initialIndex: startIndex,
        ),
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  final String url;
  final BorderRadius radius;
  final VoidCallback onTap;
  final double aspectRatio;

  const _ImageCard({
    required this.url,
    required this.radius,
    required this.onTap,
    this.aspectRatio = 16 / 9,
  });

  @override
  Widget build(BuildContext context) {
    // Target a stable bucket width to maximize CDN/device cache reuse.
    final deviceW = MediaQuery.of(context).size.width;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final renderW = (deviceW * 0.92 * dpr).clamp(360.0, 1280.0).round();

    return GestureDetector(
      onTap: onTap,
      child: Hero(
        tag: 'photo_$url',
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Use Image.network directly — fastest path in Flutter.
              // cacheWidth helps the engine decode to the right size.
              Image.network(
                sizedUrlBucketed(url, renderW), // see helper below
                fit: BoxFit.cover,
                cacheWidth: renderW, // key for perf
                gaplessPlayback: true, // avoid flicker when rebuilding
                filterQuality: FilterQuality.low, // cheaper scaling
                // no fadeIn, no shimmer
                loadingBuilder: (ctx, child, prog) {
                  if (prog == null) return child;
                  return Container(color: Theme.of(ctx).cardColor); // static
                },
                errorBuilder: (_, __, ___) =>
                    const ColoredBox(color: Color(0x11000000)),
              ),
              // keep ultra-light scrim (cheap)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black12, Colors.transparent],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Use width BUCKETS so the same URLs are reused & cached.
String sizedUrlBucketed(String url, int renderW) {
  // Choose from buckets; tune as needed.
  const buckets = [480, 720, 1080, 1440];
  int w = buckets.first;
  for (final b in buckets) {
    if (renderW <= b) {
      w = b;
      break;
    }
    w = b;
  }
  // If your URLs don’t support params, just return url.
  if (!url.contains('http')) return url;
  return url.contains('?') ? '$url&w=$w' : '$url?w=$w';
}

class _Dots extends StatelessWidget {
  final int count;
  final int index;
  final Color color;

  const _Dots({required this.count, required this.index, required this.color});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: active ? 18 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? color.withOpacity(.9) : color.withOpacity(.25),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}

class _ShimmerPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.4),
      highlightColor: Colors.white.withOpacity(.35),
      child: Container(color: Theme.of(context).cardColor),
    );
  }
}

class _ErrorImage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceVariant.withOpacity(.4),
      child: Center(
        child: Icon(Icons.broken_image_outlined, color: cs.onSurface),
      ),
    );
  }
}

class _EmptyImage extends StatelessWidget {
  final BorderRadius radius;
  const _EmptyImage({required this.radius});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: cs.surfaceVariant.withOpacity(.35),
        border: Border.all(color: cs.primary.withOpacity(.12)),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_outlined, size: 18),
            const SizedBox(width: 8),
            Text(
              'No photos yet',
              style: TextStyle(color: cs.onSurface.withOpacity(.8)),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullscreenGallery extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  const _FullscreenGallery({
    required this.imageUrls,
    required this.initialIndex,
  });

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late int _current = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            pageController: PageController(initialPage: widget.initialIndex),
            itemCount: widget.imageUrls.length,
            builder: (_, i) {
              final url = widget.imageUrls[i];
              return PhotoViewGalleryPageOptions(
                heroAttributes: PhotoViewHeroAttributes(tag: 'photo_$url'),
                imageProvider: CachedNetworkImageProvider(url),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3.0,
              );
            },
            onPageChanged: (i) => setState(() => _current = i),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
          ),

          // ⬇️ Close button overlay
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton(
                  icon: const Icon(Icons.close),
                  iconSize: 26,
                  color: Colors.white,
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.all(Colors.black54),
                    shape: WidgetStateProperty.all(
                      const CircleBorder(),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // (optional) small counter at top-left
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${_current + 1}/${widget.imageUrls.length}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ViewListingPage extends StatefulWidget {
  final String listingId;
  const ViewListingPage({super.key, required this.listingId});

  @override
  State<ViewListingPage> createState() => _ViewListingPageState();
}

class _ViewListingPageState extends State<ViewListingPage> {
  bool _loading = true;
  String? _error;

  // Données listing
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

  // Géoloc
  double? _latitude;
  double? _longitude;

  // HES (vol d’oiseau pour le listing — on garde le plus proche)
  double? _proximHesKm;
  String? _nearestHesId; // id Firestore dans `schools`
  String? _nearestHesName; // name résolu depuis `schools`
  bool _computingHes = false;

  // Destination PT (peut être la HES de l’étudiant)
  String? _destHesId;
  String? _destHesName;
  bool _destIsUserSchool = false;

  // Transport public → HES (prochaines 2h)
  bool _loadingPt = false;
  String? _ptError;
  List<_TransitRoute> _ptRoutes = [];

  // Bars à proximité (Places API v1)
  bool _loadingBars = false;
  String? _barsError;
  List<_NearbyPlace> _bars = [];

  // Dispo & photos
  DateTime? _availStart;
  DateTime? _availEnd;
  List<String> _photos = [];

  // Estimation prix
  bool _estimatingPrice = false;
  double? _estimatedPrice;
  String? _estimateError;

  // Calendrier
  DateTime _shownMonth = _monthDate(DateTime.now());
  static DateTime _monthDate(DateTime d) => DateTime(d.year, d.month);
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // Carrousels
  late final PageController _photoCtrl;

  // ---- Favoris (link-table `favorites`) ----
  late final Stream<bool> _favStream;

  // Carrousels PT & Bars + états
  late final PageController _ptCtrl = PageController(viewportFraction: 1.0);
  late final PageController _barsCtrl = PageController(viewportFraction: 1.0);
  int _ptPage = 0;
  int _barsPage = 0;
  int? _expandedBarIndex;

  // Réservations (formulaire)
  List<Map<String, dynamic>> _bookedDates = [];
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();
  DateTime? _selectedStart;
  DateTime? _selectedEnd;
  bool _submittingBooking = false;

  // Validation téléphone
  String? _phoneError;
  bool _isValidPhone = false;

  // Notes
  int _rating = 0;

  // User profile (role/school) for behavior
  String? _userRole;
  String? _userSchool;

  bool get _isOwner =>
      FirebaseAuth.instance.currentUser?.uid != null &&
      FirebaseAuth.instance.currentUser!.uid == _ownerUid;

  // Real student check (from users/{uid}.role)
  bool get _isStudent =>
      FirebaseAuth.instance.currentUser != null &&
      !_isOwner &&
      (_userRole?.toLowerCase() == 'student');

  // Whether we should route to user's HES
  bool get _useStudentSchoolAsDestination =>
      _isStudent && (_userSchool != null && _userSchool!.trim().isNotEmpty);

  Future<void> _loadMyExistingReviewIfAny() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final query = await FirebaseFirestore.instance
        .collection('listing_reviews')
        .where('listingId', isEqualTo: widget.listingId)
        .where('studentUid', isEqualTo: user.uid)
        .get();

    if (query.docs.isNotEmpty) {
      final data = query.docs.first.data();
      setState(() {
        _rating = (data['rating'] as num?)?.toInt() ?? 0;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _photoCtrl = PageController(viewportFraction: 0.92);
    _favStream = _favoriteStream();
    _phoneController.addListener(_validatePhoneNumber);
    _load();
    _loadMyExistingReviewIfAny();
  }

  @override
  void dispose() {
    _photoCtrl.dispose();
    _ptCtrl.dispose();
    _barsCtrl.dispose();
    _messageController.dispose();
    _phoneController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  // --- FAVORITES (link table) ------------------------------------------------
  Stream<bool> _favoriteStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(false);
    final favDocId = '${uid}_${widget.listingId}';
    return FirebaseFirestore.instance
        .collection('favorites')
        .doc(favDocId)
        .snapshots()
        .map((d) => d.exists);
  }

  Future<void> _toggleFavorite() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connecte-toi pour utiliser les favoris.'),
        ),
      );
      return;
    }
    final favRef = FirebaseFirestore.instance
        .collection('favorites')
        .doc('${uid}_${widget.listingId}');
    try {
      final snap = await favRef.get();
      if (snap.exists) {
        await favRef.delete();
      } else {
        await favRef.set({
          'userUid': uid,
          'listingId': widget.listingId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur favoris: $e')));
    }
  }
  // --------------------------------------------------------------------------

  // Dots helper (PageView)
  Widget _dots(BuildContext context, {required int count, required int index}) {
    final cs = Theme.of(context).colorScheme;
    if (count <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final active = i == index;
          return Container(
            width: active ? 10 : 8,
            height: active ? 10 : 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? cs.primary : cs.primary.withOpacity(.25),
            ),
          );
        }),
      ),
    );
  }

  void _validatePhoneNumber() {
    final phoneText = _phoneController.text.trim();
    if (phoneText.isEmpty) {
      setState(() {
        _phoneError = null;
        _isValidPhone = true; // optionnel → vide = ok
      });
      return;
    }
    try {
      PhoneNumber phoneNumber;
      if (phoneText.startsWith('+')) {
        phoneNumber = PhoneNumber.parse(phoneText);
      } else {
        phoneNumber = PhoneNumber.parse(
          phoneText,
          destinationCountry: IsoCode.CH,
        );
      }
      if (phoneNumber.isValid()) {
        setState(() {
          _phoneError = null;
          _isValidPhone = true;
        });
      } else {
        setState(() {
          _phoneError = 'Invalid phone number format';
          _isValidPhone = false;
        });
      }
    } catch (_) {
      setState(() {
        _phoneError = 'Invalid phone number format';
        _isValidPhone = false;
      });
    }
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

      // Champs persistant (pour le listing: plus proche HES)
      _proximHesKm = (m['proxim_hesso_km'] as num?)?.toDouble();
      _nearestHesId = (m['nearest_hesso_id'] ?? '').toString();
      _nearestHesName = null;

      final tsStart = m['availability_start'] as Timestamp?;
      final tsEnd = m['availability_end'] as Timestamp?;
      _availStart = tsStart?.toDate();
      _availEnd = tsEnd?.toDate();

      final List photos = (m['photos'] as List?) ?? const [];
      _photos = photos.map((e) => e.toString()).toList();

      // Load current user's role/school (for routing + booking UI)
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final ud = userDoc.data() ?? {};
        _userRole = (ud['role'] ?? '').toString();
        _userSchool = (ud['school'] ?? '').toString();
      } else {
        _userRole = null;
        _userSchool = null;
      }

      await _loadBookedDates();

      setState(() {
        _loading = false;
        if (_availStart != null) _shownMonth = _monthDate(_availStart!);
      });

      // Make sure nearest school (for listing metrics) is computed/resolved
      await _ensureNearestSchool();

      // Resolve destination school for transit (student school > nearest)
      await _ensureDestinationSchool();

      _autoLoadSections();
    } catch (e) {
      setState(() {
        _error = 'Failed to load listing: $e';
        _loading = false;
      });
    }
  }

  Future<void> _ensureNearestSchool() async {
    if (_latitude != null &&
        _longitude != null &&
        (_proximHesKm == null || (_nearestHesId ?? '').isEmpty)) {
      await _computeNearestHes(persist: true);
    }
    if ((_nearestHesId ?? '').isNotEmpty && _nearestHesName == null) {
      await _resolveHesNameById(_nearestHesId!);
    }
  }

  /// Sets _destHesId/_destHesName and whether it is user school.
  Future<void> _ensureDestinationSchool() async {
    // Prefer student's school if available
    if (_useStudentSchoolAsDestination) {
      final doc = await _findHesByName(_userSchool!.trim());
      if (doc != null && doc.exists) {
        final name = (doc.data()?['name'] ?? '').toString();
        setState(() {
          _destHesId = doc.id;
          _destHesName = name.isEmpty ? doc.id : name;
          _destIsUserSchool = true;
        });
        return;
      }
    }
    // Fallback to nearest (already ensured by _ensureNearestSchool)
    if ((_nearestHesId ?? '').isNotEmpty) {
      setState(() {
        _destHesId = _nearestHesId;
        _destHesName = _nearestHesName;
        _destIsUserSchool = false;
      });
    } else {
      // As a last resort, compute nearest now
      await _computeNearestHes(persist: true);
      setState(() {
        _destHesId = _nearestHesId;
        _destHesName = _nearestHesName;
        _destIsUserSchool = false;
      });
    }
  }

  /// Exact-name match in `schools`. If not found, returns null.
  Future<DocumentSnapshot<Map<String, dynamic>>?> _findHesByName(
    String name,
  ) async {
    try {
      final q = await FirebaseFirestore.instance
          .collection(_hesCollection)
          .where('name', isEqualTo: name)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return q.docs.first;
      // Optional secondary pass: linear scan (case-insensitive) if exact not found.
      final all = await FirebaseFirestore.instance
          .collection(_hesCollection)
          .get();
      for (final d in all.docs) {
        final n = (d.data()['name'] ?? '').toString();
        if (n.toLowerCase().trim() == name.toLowerCase().trim()) {
          return d;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void _autoLoadSections() {
    if (_latitude != null && _longitude != null) {
      _loadPtRoutesNext2h();
      _loadNearbyBars();
    }
  }

  Future<void> _loadBookedDates() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('booking_requests')
          .where('listingId', isEqualTo: widget.listingId)
          .where('status', isEqualTo: 'approved')
          .get();

      _bookedDates = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'startDate': (data['startDate'] as Timestamp).toDate(),
          'endDate': (data['endDate'] as Timestamp).toDate(),
        };
      }).toList();
    } catch (e) {
      // ignore
    }
  }

  bool _isDateBooked(DateTime day) {
    final d = _dateOnly(day);
    for (final booking in _bookedDates) {
      final start = _dateOnly(booking['startDate']);
      final end = _dateOnly(booking['endDate']);
      if (!d.isBefore(start) && !d.isAfter(end)) return true;
    }
    return false;
  }

  bool _isDateAvailableForSelection(DateTime day) {
    return _isAvailableOn(day) && !_isDateBooked(day);
  }

  Future<bool> _checkBookingConflict(
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('booking_requests')
          .where('listingId', isEqualTo: widget.listingId)
          .where('status', isEqualTo: 'approved')
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final existingStart = _dateOnly(
          (data['startDate'] as Timestamp).toDate(),
        );
        final existingEnd = _dateOnly((data['endDate'] as Timestamp).toDate());
        final reqStart = _dateOnly(startDate);
        final reqEnd = _dateOnly(endDate);
        if (!(reqEnd.isBefore(existingStart) ||
            reqStart.isAfter(existingEnd))) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  Future<void> _estimatePrice() async {
    if (_latitude == null ||
        _longitude == null ||
        _surface == null ||
        _rooms == null ||
        _floor == null ||
        _distTransportKm == null ||
        _proximHesKm == null) {
      setState(() => _estimateError = 'Missing data for estimation');
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
          "proxim_hesso_km":
              _proximHesKm!, // estimation reste basée sur la plus proche HES
        },
      ];

      final response = await http.post(
        Uri.parse(
          'https://hestimate-api-production.up.railway.app/estimate-price',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List &&
            data.isNotEmpty &&
            data[0]['predicted_price_chf'] != null) {
          setState(() {
            _estimatedPrice = (data[0]['predicted_price_chf'] as num)
                .toDouble();
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

  // --- HES helpers -----------------------------------------------------------

  double _deg2rad(double d) => d * math.pi / 180.0;

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) *
            math.cos(_deg2rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  Future<void> _resolveHesNameById(String campusId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_hesCollection)
          .doc(campusId)
          .get();
      if (doc.exists) {
        final name = (doc.data()?['name'] ?? '').toString();
        if (mounted) {
          setState(() {
            _nearestHesName = name.isEmpty ? campusId : name;
          });
        }
      } else {
        await _computeNearestHes(persist: true);
      }
    } catch (_) {
      /* no-op */
    }
  }

  Future<void> _computeNearestHes({bool persist = true}) async {
    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing listing coordinates')),
      );
      return;
    }

    setState(() => _computingHes = true);
    try {
      final query = await FirebaseFirestore.instance
          .collection(_hesCollection)
          .get();

      if (query.docs.isEmpty) {
        throw Exception('No school records found in "$_hesCollection".');
      }

      double bestKm = double.infinity;
      String? bestId;
      String? bestName;

      for (final d in query.docs) {
        final m = d.data();
        final lat = (m['latitude'] as num?)?.toDouble();
        final lon = (m['longitude'] as num?)?.toDouble();
        final name = (m['name'] ?? '').toString();
        if (lat == null || lon == null) continue;

        final km = _haversineKm(_latitude!, _longitude!, lat, lon);
        if (km < bestKm) {
          bestKm = km;
          bestId = d.id;
          bestName = name.isEmpty ? d.id : name;
        }
      }

      if (bestId == null) {
        throw Exception('No valid school coordinates found.');
      }

      setState(() {
        _proximHesKm = double.parse(bestKm.toStringAsFixed(3));
        _nearestHesId = bestId;
        _nearestHesName = bestName;
      });

      if (persist) {
        await FirebaseFirestore.instance
            .collection('listings')
            .doc(widget.listingId)
            .update({
              'proxim_hesso_km': _proximHesKm,
              'nearest_hesso_id': _nearestHesId,
            });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to compute nearest school: $e')),
      );
    } finally {
      if (mounted) setState(() => _computingHes = false);
    }
  }

  // --- Directions (transit) next 2h -----------------------------------------

  Future<void> _loadPtRoutesNext2h() async {
    if (_latitude == null || _longitude == null) {
      setState(() => _ptError = 'Missing listing coordinates');
      return;
    }
    if (_googleMapsApiKey.isEmpty) {
      setState(() => _ptError = 'Google Directions API key missing.');
      return;
    }

    // Ensure destination school selection is ready
    await _ensureDestinationSchool();
    if (_destHesId == null || _destHesId!.isEmpty) {
      setState(
        () => _ptError = 'No destination school found for this listing/user',
      );
      return;
    }

    // Load destination school doc
    DocumentSnapshot<Map<String, dynamic>>? hesDoc;
    try {
      hesDoc = await FirebaseFirestore.instance
          .collection(_hesCollection)
          .doc(_destHesId!)
          .get();

      // If _destHesId came from name search fallback, it should exist;
      // but if not, try recompute nearest and use that.
      if (!hesDoc.exists) {
        await _ensureNearestSchool();
        if ((_nearestHesId ?? '').isNotEmpty) {
          hesDoc = await FirebaseFirestore.instance
              .collection(_hesCollection)
              .doc(_nearestHesId!)
              .get();
          _destHesId = _nearestHesId;
          _destHesName = _nearestHesName;
          _destIsUserSchool = false;
        }
      }
    } catch (_) {
      hesDoc = null;
    }

    if (hesDoc == null || !hesDoc.exists) {
      setState(() => _ptError = 'Destination school not found in database');
      return;
    }

    final schoolData = hesDoc.data()!;
    final hesLat = (schoolData['latitude'] as num?)?.toDouble();
    final hesLon = (schoolData['longitude'] as num?)?.toDouble();
    final hesName = (schoolData['name'] ?? '').toString();

    if (hesLat == null || hesLon == null) {
      setState(() => _ptError = 'School has no coordinates');
      return;
    }

    setState(() {
      _destHesName = (hesName.isEmpty ? _destHesId! : hesName);
      _ptError = null;
      _loadingPt = true;
      _ptRoutes = [];
      _ptPage = 0;
    });

    try {
      final now = DateTime.now();
      final horizon = now.add(const Duration(hours: 2));
      final anchors = <DateTime>[];
      var cursor = now;
      while (cursor.isBefore(horizon) && anchors.length < 6) {
        anchors.add(cursor);
        cursor = cursor.add(const Duration(minutes: 20));
      }

      final results = <_TransitRoute>[];
      for (final dt in anchors) {
        final secs = (dt.millisecondsSinceEpoch / 1000).round();
        final uri =
            Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
              'origin': '${_latitude!},${_longitude!}',
              'destination': '$hesLat,$hesLon',
              'mode': 'transit',
              'alternatives': 'true',
              'transit_routing_preference': 'less_walking',
              'language': 'en',
              'departure_time': '$secs',
              'key': _googleMapsApiKey,
            });

        final resp = await http.get(uri);
        if (resp.statusCode != 200) {
          setState(() => _ptError = 'HTTP ${resp.statusCode}: ${resp.body}');
          continue;
        }
        final jd = jsonDecode(resp.body);
        if (jd['status'] != 'OK' || jd['routes'] == null) {
          final em = (jd['error_message'] ?? '').toString();
          setState(
            () => _ptError =
                'Directions status: ${jd['status']}${em.isNotEmpty ? ' • $em' : ''}',
          );
          continue;
        }

        for (final r in jd['routes']) {
          final leg = (r['legs'] as List).first;
          final route = _TransitRoute.fromGoogle(leg, r, anchor: dt);
          if (route == null) continue;
          if (route.departureTime.isAfter(horizon)) continue;

          // Build a more specific, stable signature for the route:
          final transitSig = route.steps
              .where((s) => s.type == _StepType.transit)
              .map(
                (s) =>
                    '${s.transitLine ?? ''}|${s.transitHeadsign ?? ''}|${s.departureStop ?? ''}|${s.arrivalStop ?? ''}',
              )
              .join('>');

          // NOTE: includes both departure and arrival times → same route at a different time shows up.
          final key =
              '${route.departureTime.millisecondsSinceEpoch}-'
              '${route.arrivalTime.millisecondsSinceEpoch}-'
              '${route.summary}-$transitSig';

          if (!results.any((x) => x._dedupeKey == key)) {
            results.add(route.._dedupeKey = key);
          }
        }
      }

      results.sort((a, b) => a.departureTime.compareTo(b.departureTime));

      setState(() {
        _ptRoutes = results.take(12).toList();
        _loadingPt = false;
        if (_ptRoutes.isEmpty && _ptError == null) {
          _ptError = 'No scheduled routes found in the next 2 hours.';
        }
      });
    } catch (e) {
      setState(() {
        _ptError = 'Failed to load transit routes: $e';
        _loadingPt = false;
      });
    }
  }

  // --- Places API v1 Nearby Bars --------------------------------------------

  Future<void> _loadNearbyBars() async {
    if (_latitude == null || _longitude == null) {
      setState(() => _barsError = 'Missing listing coordinates');
      return;
    }
    if (_googleMapsApiKey.isEmpty) {
      setState(() => _barsError = 'Google Places API key missing.');
      return;
    }

    setState(() {
      _loadingBars = true;
      _barsError = null;
      _bars = [];
      _barsPage = 0;
      _expandedBarIndex = null;
    });

    try {
      final url = Uri.parse(
        'https://places.googleapis.com/v1/places:searchNearby',
      );

      final body = {
        "includedTypes": ["bar"],
        "maxResultCount": 15,
        "locationRestriction": {
          "circle": {
            "center": {"latitude": _latitude, "longitude": _longitude},
            "radius": 1500.0,
          },
        },
      };

      final headers = {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': _googleMapsApiKey,
        'X-Goog-FieldMask':
            'places.displayName,places.formattedAddress,places.rating,places.userRatingCount,places.location,places.types',
      };

      final resp = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      );

      if (resp.statusCode != 200) {
        setState(() {
          _barsError = 'HTTP ${resp.statusCode}: ${resp.body}';
          _loadingBars = false;
        });
        return;
      }

      final jd = jsonDecode(resp.body);
      final List items = (jd['places'] as List?) ?? const [];

      final parsed = <_NearbyPlace>[];
      for (final p in items) {
        final name = (p['displayName']?['text'] ?? '').toString();
        final addr = (p['formattedAddress'] ?? '').toString();
        final rating = (p['rating'] as num?)?.toDouble();
        final urc = (p['userRatingCount'] as num?)?.toInt();
        final plat = (p['location']?['latitude'] as num?)?.toDouble();
        final plon = (p['location']?['longitude'] as num?)?.toDouble();
        if (plat == null || plon == null || name.isEmpty) continue;

        final km = _haversineKm(_latitude!, _longitude!, plat, plon);
        parsed.add(
          _NearbyPlace(
            name: name,
            address: addr,
            rating: rating,
            ratingCount: urc,
            latitude: plat,
            longitude: plon,
            distanceKm: double.parse(km.toStringAsFixed(2)),
          ),
        );
      }

      // Dedup (name, address)
      final seen = <String>{};
      final deduped = <_NearbyPlace>[];
      for (final p in parsed) {
        final k = '${p.name.toLowerCase()}|${p.address.toLowerCase()}';
        if (seen.add(k)) deduped.add(p);
      }

      // Sort by rating desc, then count desc, then distance asc
      deduped.sort((a, b) {
        final ar = a.rating ?? -1.0;
        final br = b.rating ?? -1.0;
        if (ar != br) return br.compareTo(ar);
        final arc = a.ratingCount ?? -1;
        final brc = b.ratingCount ?? -1;
        if (arc != brc) return brc.compareTo(arc);
        return a.distanceKm.compareTo(b.distanceKm);
      });

      setState(() {
        _bars = deduped.take(20).toList();
        _loadingBars = false;
        if (_bars.isEmpty) _barsError = 'No bars found nearby.';
      });
    } catch (e) {
      setState(() {
        _barsError = 'Failed to load nearby bars: $e';
        _loadingBars = false;
      });
    }
  }

  // ---------------------------------------------------------------------------

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

  void _onDateTap(DateTime date) {}

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
      final isBooked = _isDateBooked(date);

      Color bgColor = Colors.transparent;
      Color borderColor = cs.primary.withOpacity(.12);
      Color textColor = cs.onSurface;

      if (isBooked) {
        bgColor = Colors.red.withOpacity(.2);
        borderColor = Colors.red.withOpacity(.5);
        textColor = Colors.red;
      } else if (available) {
        bgColor = cs.primary.withOpacity(.12);
        borderColor = cs.primary.withOpacity(.45);
        textColor = cs.primary;
      }

      items.add(
        Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Center(
            child: Text(
              '$day',
              style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
            ),
          ),
        ),
      );
    }

    return items;
  }

  // Ratings preview
  Widget _starsRow(BuildContext context, int value, double avg, int count) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (i) {
          final idx = i + 1;
          final filled = idx <= avg.round();
          final icon = filled ? Icons.star_rounded : Icons.star_border_rounded;
          final color = filled ? cs.primary : cs.onSurface.withOpacity(.35);
          return Icon(icon, size: 16, color: color);
        }),
        const SizedBox(width: 6),
        Text(
          count == 0 ? 'No ratings' : '${avg.toStringAsFixed(1)} ($count)',
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withOpacity(.8),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildHomeownerRatingSection(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('listings')
          .where('ownerUid', isEqualTo: _ownerUid)
          .snapshots(),
      builder: (context, listingsSnapshot) {
        if (!listingsSnapshot.hasData) {
          return const SizedBox.shrink();
        }

        final ownerListingIds = listingsSnapshot.data!.docs
            .map((doc) => doc.id)
            .toList();

        if (ownerListingIds.isEmpty) {
          return const SizedBox.shrink();
        }

        // Handle Firestore's 30-item limit for 'whereIn' queries
        return FutureBuilder<Map<String, dynamic>>(
          future: _getOwnerRatings(ownerListingIds),
          builder: (context, ratingsSnapshot) {
            if (!ratingsSnapshot.hasData) {
              return _buildHomeownerRatingCard(
                context,
                0,
                0,
                ownerListingIds.length,
                isLoading: true,
              );
            }

            final data = ratingsSnapshot.data!;
            final overallAvg = data['average'] as double;
            final totalReviews = data['count'] as int;

            return _buildHomeownerRatingCard(
              context,
              overallAvg,
              totalReviews,
              ownerListingIds.length,
            );
          },
        );
      },
    );
  }

  Future<Map<String, dynamic>> _getOwnerRatings(
    List<String> ownerListingIds,
  ) async {
    double totalSum = 0;
    int totalCount = 0;

    // Split listing IDs into chunks of 30 to handle Firestore's limit
    for (int i = 0; i < ownerListingIds.length; i += 30) {
      final chunk = ownerListingIds.sublist(
        i,
        math.min(i + 30, ownerListingIds.length),
      );

      final querySnapshot = await FirebaseFirestore.instance
          .collection('listing_reviews')
          .where('listingId', whereIn: chunk)
          .get();

      for (final doc in querySnapshot.docs) {
        final rating = (doc.data()['rating'] as num?)?.toDouble() ?? 0.0;
        totalSum += rating;
        totalCount++;
      }
    }

    final average = totalCount > 0 ? totalSum / totalCount : 0.0;

    return {'average': average, 'count': totalCount};
  }

  Widget _buildHomeownerRatingCard(
    BuildContext context,
    double overallAvg,
    int totalReviews,
    int totalListings, {
    bool isLoading = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _MoonCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_outline, size: 20),
              const SizedBox(width: 8),
              Text(
                'Homeowner Rating',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isLoading)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cs.primary.withOpacity(0.12),
                  width: 1,
                ),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Loading ratings...'),
                ],
              ),
            )
          else if (totalReviews == 0)
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
                children: [
                  Icon(
                    Icons.star_border_rounded,
                    color: cs.onSurface.withOpacity(.5),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No reviews yet',
                          style: TextStyle(
                            color: cs.onSurface.withOpacity(.8),
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'This homeowner hasn\'t received any reviews',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface.withOpacity(.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
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
                  Icon(Icons.star_rounded, color: cs.primary, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Overall rating',
                          style: TextStyle(
                            color: cs.onSurface.withOpacity(.8),
                            fontSize: 14,
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              overallAvg.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Display stars
                            ...List.generate(5, (i) {
                              final idx = i + 1;
                              final filled = idx <= overallAvg.round();
                              final icon = filled
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded;
                              final color = filled
                                  ? cs.primary
                                  : cs.onSurface.withOpacity(.35);
                              return Icon(icon, size: 20, color: color);
                            }),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Based on $totalReviews review${totalReviews == 1 ? '' : 's'} across $totalListings listing${totalListings == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withOpacity(.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRatingsPreview(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(
            'listing_reviews',
          ) // Changez 'ratings' en 'listing_reviews'
          .where('listingId', isEqualTo: widget.listingId)
          .snapshots(),
      builder: (context, snap) {
        double avg = 0;
        int count = 0;
        if (snap.hasData) {
          final docs = snap.data!.docs;
          count = docs.length;
          if (count > 0) {
            final sum = docs.fold<double>(
              0.0,
              (acc, d) =>
                  acc +
                  ((d.data()['rating'] as num?)?.toDouble() ??
                      0.0), // Changez 'stars' en 'rating'
            );
            avg = sum / count;
          }
        }
        return InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RateListingPage(
                  listingId: widget.listingId,
                  allowAdd: false,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(top: 6.0, bottom: 2.0),
            child: _starsRow(context, avg.round(), avg, count),
          ),
        );
      },
    );
  }

  // --- Open place in Maps ----------------------------------------------------

  Future<void> _openPlaceInMaps(_NearbyPlace p) async {
    final lat = p.latitude.toStringAsFixed(6);
    final lon = p.longitude.toStringAsFixed(6);
    final encodedQuery = Uri.encodeComponent('${p.name}, ${p.address}');

    final List<Uri> candidates;
    if (kIsWeb) {
      candidates = [
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon'),
      ];
    } else if (Platform.isIOS) {
      candidates = [
        Uri.parse('comgooglemaps://?q=$lat,$lon&center=$lat,$lon&zoom=16'),
        Uri.parse('maps://?q=$encodedQuery&ll=$lat,$lon'),
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon'),
      ];
    } else if (Platform.isAndroid) {
      candidates = [
        Uri.parse('geo:$lat,$lon?q=$encodedQuery'),
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon'),
      ];
    } else {
      candidates = [
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon'),
      ];
    }

    for (final uri in candidates) {
      try {
        final launched = await launchUrl(
          uri,
          mode: kIsWeb
              ? LaunchMode.platformDefault
              : LaunchMode.externalApplication,
          webOnlyWindowName: kIsWeb ? '_blank' : null,
        );
        if (launched) return;
      } catch (_) {}
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps')),
      );
    }
  }

  Widget _buildBookingPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Book your stay',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),

          // Start Date
          TextField(
            readOnly: true,
            controller: _startDateController,
            decoration: InputDecoration(
              labelText: 'Start Date',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.all(12),
              suffixIcon: const Icon(Icons.calendar_today),
            ),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedStart ?? (_availStart ?? DateTime.now()),
                firstDate: _availStart ?? DateTime.now(),
                lastDate:
                    _availEnd ?? DateTime.now().add(const Duration(days: 365)),
                selectableDayPredicate: _isDateAvailableForSelection,
              );
              if (picked != null) {
                setState(() {
                  _selectedStart = picked;
                  _startDateController.text = _fmt(picked);
                  if (_selectedEnd != null && _selectedEnd!.isBefore(picked)) {
                    _selectedEnd = null;
                    _endDateController.text = '';
                  }
                });
              }
            },
          ),
          const SizedBox(height: 12),

          // End Date
          TextField(
            readOnly: true,
            controller: _endDateController,
            decoration: InputDecoration(
              labelText: 'End Date',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.all(12),
              suffixIcon: const Icon(Icons.calendar_today),
            ),
            onTap: () async {
              if (_selectedStart == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please select a start date first'),
                  ),
                );
                return;
              }

              final picked = await showDatePicker(
                context: context,
                initialDate:
                    _selectedEnd ??
                    _selectedStart!.add(const Duration(days: 1)),
                firstDate: _selectedStart!.add(const Duration(days: 1)),
                lastDate:
                    _availEnd ?? DateTime.now().add(const Duration(days: 365)),
                selectableDayPredicate: _isDateAvailableForSelection,
              );
              if (picked != null) {
                setState(() {
                  _selectedEnd = picked;
                  _endDateController.text = _fmt(picked);
                });
              }
            },
          ),

          // Message
          const SizedBox(height: 12),
          TextField(
            controller: _messageController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Message to owner *',
              hintText: 'Tell the owner about yourself...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),

          // Phone
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Phone number (optional)',
              hintText: '+41 79 123 45 67 or 079 123 45 67',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: _phoneError != null ? Colors.red : Colors.grey,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: _phoneError != null ? Colors.red : Colors.grey,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: _phoneError != null
                      ? Colors.red
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
              contentPadding: const EdgeInsets.all(12),
              errorText: _phoneError,
              suffixIcon: _phoneController.text.isNotEmpty
                  ? Icon(
                      _isValidPhone ? Icons.check_circle : Icons.error,
                      color: _isValidPhone ? Colors.green : Colors.red,
                    )
                  : null,
            ),
          ),

          // Submit
          const SizedBox(height: 16),
          MoonFilledButton(
            isFullWidth: true,
            onTap:
                _selectedStart != null &&
                    _selectedEnd != null &&
                    _messageController.text.isNotEmpty &&
                    _isValidPhone &&
                    !_submittingBooking
                ? () => _submitBookingRequestWithDates(
                    _selectedStart!,
                    _selectedEnd!,
                  )
                : null,
            leading: _submittingBooking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send),
            label: Text(
              _submittingBooking ? 'Sending...' : 'Send booking request',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitBookingRequestWithDates(
    DateTime start,
    DateTime end,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _submittingBooking = true);

    try {
      final hasConflict = await _checkBookingConflict(start, end);
      if (hasConflict) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Selected dates are no longer available. Please choose different dates.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _submittingBooking = false);
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? {};

      String? formattedPhone;
      if (_phoneController.text.trim().isNotEmpty) {
        try {
          PhoneNumber phoneNumber;
          if (_phoneController.text.trim().startsWith('+')) {
            phoneNumber = PhoneNumber.parse(_phoneController.text.trim());
          } else {
            phoneNumber = PhoneNumber.parse(
              _phoneController.text.trim(),
              destinationCountry: IsoCode.CH,
            );
          }
          formattedPhone = phoneNumber.international;
        } catch (_) {
          formattedPhone = _phoneController.text.trim();
        }
      }

      await FirebaseFirestore.instance.collection('booking_requests').add({
        'listingId': widget.listingId,
        'studentUid': user.uid,
        'ownerUid': _ownerUid,
        'startDate': Timestamp.fromDate(start),
        'endDate': Timestamp.fromDate(end),
        'message': _messageController.text.trim(),
        'studentName': userData['name'] ?? user.email,
        'studentEmail': user.email,
        'studentPhone': formattedPhone,
        'status': 'pending',
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });

      setState(() {
        _messageController.clear();
        _phoneController.clear();
        _startDateController.clear();
        _endDateController.clear();
        _selectedStart = null;
        _selectedEnd = null;
        _submittingBooking = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Booking request sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _submittingBooking = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
                  Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/home', (route) => false);
                }
              },
            );
          },
        ),
        actions: [
          // Bouton favori (live)
          StreamBuilder<bool>(
            stream: _favStream,
            builder: (context, snap) {
              final isFav = snap.data ?? false;
              return IconButton(
                tooltip: isFav ? 'Retirer des favoris' : 'Ajouter aux favoris',
                icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
                color: isFav ? Colors.redAccent : null,
                onPressed: _toggleFavorite,
              );
            },
          ),
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
                            // Photos (edge-to-edge, before first card)
                            if (_photos.isNotEmpty) ...[
                              ListingPhotoCarousel(
                                imageUrls: _photos,
                              ), // uses your existing _photos list
                              const SizedBox(height: 16),
                            ] else
                              _MoonCard(
                                isDark: isDark,
                                child: Container(
                                  height: 180,
                                  alignment: Alignment.center,
                                  child: Text(
                                    'No photos',
                                    style: TextStyle(
                                      color: cs.onSurface.withOpacity(.7),
                                    ),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 16),

                            // Header + bouton Edit + ratings
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
                                            const SizedBox(height: 8),
                                            _buildRatingsPreview(context),
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
                                      if (_proximHesKm != null)
                                        _chip(
                                          context,
                                          icon: Icons.school_outlined,
                                          text:
                                              _nearestHesName != null &&
                                                  _nearestHesName!
                                                      .trim()
                                                      .isNotEmpty
                                              ? '${_proximHesKm!.toStringAsFixed(1)} km • $_nearestHesName'
                                              : '${_proximHesKm!.toStringAsFixed(1)} km HES',
                                        )
                                      else
                                        MoonButton(
                                          isFullWidth: false,
                                          onTap: _computingHes
                                              ? null
                                              : () => _computeNearestHes(
                                                  persist: true,
                                                ),
                                          leading: _computingHes
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.school_outlined,
                                                ),
                                          label: const Text('Nearest HES'),
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
                                        'Wi-Fi included',
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

                            _buildHomeownerRatingSection(context),

                            _MoonCard(
                              isDark: isDark,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.analytics_outlined,
                                        size: 20,
                                      ),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.trending_up,
                                            color: cs.primary,
                                            size: 24,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Estimated price',
                                                  style: TextStyle(
                                                    color: cs.onSurface
                                                        .withOpacity(.8),
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                Text(
                                                  '${((_estimatedPrice! / 0.05).round() * 0.05).toStringAsFixed(2)} CHF/month',
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (_price != null) ...[
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    'Actual price',
                                                    style: TextStyle(
                                                      color: cs.onSurface
                                                          .withOpacity(.8),
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                  Text(
                                                    '${((_price! / 0.05).round() * 0.05).toStringAsFixed(2)} CHF/month',
                                                    style: TextStyle(
                                                      color: cs.onSurface,
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  Text(
                                                    '${((_price! - _estimatedPrice!) / 0.05).round() * 0.05 >= 0 ? '+' : ''}${(((_price! - _estimatedPrice!) / 0.05).round() * 0.05).toStringAsFixed(2)} CHF/month',
                                                    style: TextStyle(
                                                      color:
                                                          (_price! >
                                                              _estimatedPrice!)
                                                          ? Colors.red
                                                          : Colors.green,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
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
                                          const Icon(
                                            Icons.error_outline,
                                            color: Colors.red,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _estimateError!,
                                              style: const TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  MoonFilledButton(
                                    onTap: _estimatingPrice
                                        ? null
                                        : _estimatePrice,
                                    isFullWidth: true,
                                    leading: _estimatingPrice
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.calculate_outlined),
                                    label: Text(
                                      _estimatingPrice
                                          ? 'Estimating...'
                                          : 'Estimate price',
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Public transport → HES (student's HES if student)
                            _MoonCard(
                              isDark: isDark,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: const [
                                      Icon(Icons.alt_route_outlined, size: 20),
                                      SizedBox(width: 8),
                                    ],
                                  ),
                                  Text(
                                    'Public transport to HES (next 2h)',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Swipe horizontally to browse routes.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: cs.onSurface.withOpacity(.7),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (_destHesName != null)
                                    Text(
                                      _destIsUserSchool
                                          ? 'Destination: $_destHesName (your HES)'
                                          : 'Destination: $_destHesName',
                                      style: TextStyle(
                                        color: cs.onSurface.withOpacity(.8),
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  if (_ptError != null)
                                    Text(
                                      _ptError!,
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  else if (_loadingPt)
                                    const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: LinearProgressIndicator(),
                                    )
                                  else if (_ptRoutes.isEmpty)
                                    Text(
                                      'No routes found in the next 2 hours.',
                                      style: TextStyle(
                                        color: cs.onSurface.withOpacity(.7),
                                      ),
                                    )
                                  else ...[
                                    Builder(
                                      builder: (ctx) {
                                        final pvHeight = math.min(
                                          MediaQuery.of(ctx).size.height * 0.5,
                                          420.0,
                                        );
                                        return SizedBox(
                                          height: pvHeight,
                                          child: PageView.builder(
                                            controller: _ptCtrl,
                                            padEnds: true,
                                            itemCount: _ptRoutes.length,
                                            onPageChanged: (i) =>
                                                setState(() => _ptPage = i),
                                            itemBuilder: (ctx, i) {
                                              final r = _ptRoutes[i];
                                              return _routeCard(context, r);
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                    _dots(
                                      context,
                                      count: _ptRoutes.length,
                                      index: _ptPage,
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Bars à proximité
                            _MoonCard(
                              isDark: isDark,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: const [
                                      Icon(Icons.local_bar_outlined, size: 20),
                                      SizedBox(width: 8),
                                    ],
                                  ),
                                  Text(
                                    'Nearby bars (best rated first)',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Swipe horizontally. Tap a card to expand details.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: cs.onSurface.withOpacity(.7),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (_barsError != null)
                                    Text(
                                      _barsError!,
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  else if (_loadingBars)
                                    const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: LinearProgressIndicator(),
                                    )
                                  else if (_bars.isEmpty)
                                    Text(
                                      'No bars found nearby.',
                                      style: TextStyle(
                                        color: cs.onSurface.withOpacity(.7),
                                      ),
                                    )
                                  else ...[
                                    SizedBox(
                                      height: 170,
                                      child: PageView.builder(
                                        controller: _barsCtrl,
                                        padEnds: true,
                                        itemCount: _bars.length,
                                        onPageChanged: (i) => setState(() {
                                          _barsPage = i;
                                          _expandedBarIndex = null;
                                        }),
                                        itemBuilder: (ctx, i) {
                                          final p = _bars[i];
                                          final expanded =
                                              _expandedBarIndex == i;
                                          return _barCard(
                                            context,
                                            p,
                                            index: i,
                                            expanded: expanded,
                                            onTap: () {
                                              setState(() {
                                                _expandedBarIndex = expanded
                                                    ? null
                                                    : i;
                                              });
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                    _dots(
                                      context,
                                      count: _bars.length,
                                      index: _barsPage,
                                    ),
                                    if (_bars.length > 1)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          '${_barsPage + 1} / ${_bars.length}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: cs.onSurface.withOpacity(.6),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
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
                                    children: [
                                      Expanded(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.calendar_today_outlined,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                'Availability',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w800,
                                                  color: cs.onSurface,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Previous month',
                                        onPressed: _prevMonth,
                                        icon: const Icon(
                                          Icons.chevron_left,
                                          size: 20,
                                        ),
                                        padding: const EdgeInsets.all(8),
                                        constraints: const BoxConstraints(
                                          minWidth: 36,
                                          minHeight: 36,
                                        ),
                                      ),
                                      Container(
                                        constraints: const BoxConstraints(
                                          minWidth: 80,
                                        ),
                                        child: Text(
                                          '${_shownMonth.year}-${_shownMonth.month.toString().padLeft(2, '0')}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: cs.onSurface,
                                            fontSize: 14,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Next month',
                                        onPressed: _nextMonth,
                                        icon: const Icon(
                                          Icons.chevron_right,
                                          size: 20,
                                        ),
                                        padding: const EdgeInsets.all(8),
                                        constraints: const BoxConstraints(
                                          minWidth: 36,
                                          minHeight: 36,
                                        ),
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
                                    // Légende calendrier
                                    Wrap(
                                      spacing: 16,
                                      runSpacing: 8,
                                      children: [
                                        _buildLegendItem(
                                          context,
                                          'Available',
                                          cs.primary.withOpacity(.25),
                                          cs.primary.withOpacity(.6),
                                        ),
                                        _buildLegendItem(
                                          context,
                                          'Booked',
                                          Colors.red.withOpacity(.2),
                                          Colors.red.withOpacity(.5),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
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

                            // Formulaire de réservation (étudiant)
                            if (_isStudent) _buildBookingPanel(context),

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

  Widget _buildLegendItem(
    BuildContext context,
    String label,
    Color bgColor,
    Color borderColor,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(.8),
            fontSize: 12,
          ),
        ),
      ],
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
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
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

  // --- UI: transit route card ------------------------------------------------

  Widget _routeCard(BuildContext context, _TransitRoute r) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: cs.primary.withOpacity(.12)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Times + duration
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '${_clock(r.departureTime)} → ${_clock(r.arrivalTime)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  r.totalText,
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (r.summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text(
                  r.summary,
                  style: TextStyle(color: cs.onSurface.withOpacity(.7)),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            const SizedBox(height: 8),
            // Steps
            Column(
              children: r.steps.map((s) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5.0),
                      child: Icon(
                        s.type == _StepType.walk
                            ? Icons.directions_walk
                            : Icons.directions_transit,
                        size: 16,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (s.type == _StepType.walk) ...[
                            Text(
                              'Walk • ${s.durationText ?? ''} • ${s.distanceText ?? ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (s.instruction?.isNotEmpty == true)
                              Text(
                                s.instruction!,
                                style: TextStyle(
                                  color: cs.onSurface.withOpacity(.8),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ] else ...[
                            Text(
                              '${s.transitLine ?? 'Transit'} • ${s.transitHeadsign ?? ''}'
                                  .trim(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'From ${s.departureStop ?? '?'} (${_clock(s.departureTime!)}) to ${s.arrivalStop ?? '?'} (${_clock(s.arrivalTime!)})',
                              style: TextStyle(
                                color: cs.onSurface.withOpacity(.85),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if ((s.platform ?? '').isNotEmpty)
                              Text(
                                'Platform: ${s.platform}',
                                style: TextStyle(
                                  color: cs.onSurface.withOpacity(.7),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            if ((s.numStops ?? 0) > 0)
                              Text(
                                '${s.numStops} stops',
                                style: TextStyle(
                                  color: cs.onSurface.withOpacity(.7),
                                ),
                              ),
                          ],
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  // --- UI: nearby bar card ---------------------------------------------------

  Widget _barCard(
    BuildContext context,
    _NearbyPlace p, {
    required int index,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;

    final walkMins = (p.distanceKm / 4.5 * 60).round();
    final bikeMins = (p.distanceKm / 14.0 * 60).round();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: cs.primary.withOpacity(.12)),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (ctx, constraints) {
            return SingleChildScrollView(
              physics: expanded
                  ? const BouncingScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name
                    Text(
                      p.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                        fontSize: 16,
                      ),
                      maxLines: expanded ? 3 : 1,
                      overflow: expanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Address
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.place_outlined, size: 14, color: cs.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${p.distanceKm.toStringAsFixed(2)} km • ${p.address}',
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(.8),
                            ),
                            maxLines: expanded ? null : 2,
                            overflow: expanded
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Rating
                    if (p.rating != null)
                      Row(
                        children: [
                          Icon(
                            Icons.star_rate_rounded,
                            size: 16,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${p.rating!.toStringAsFixed(1)}'
                            '${p.ratingCount != null ? ' (${p.ratingCount})' : ''}',
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(.9),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'No rating yet',
                        style: TextStyle(color: cs.onSurface.withOpacity(.6)),
                      ),

                    // Extra (expanded)
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 180),
                      sizeCurve: Curves.easeOut,
                      alignment: Alignment.topLeft,
                      crossFadeState: expanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: const SizedBox.shrink(),
                      secondChild: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: cs.primary.withOpacity(.15),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Travel time
                              Row(
                                children: [
                                  const Icon(Icons.directions_walk, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Walk ~ $walkMins min',
                                    style: TextStyle(
                                      color: cs.onSurface.withOpacity(.9),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Icon(Icons.pedal_bike, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Bike ~ $bikeMins min',
                                    style: TextStyle(
                                      color: cs.onSurface.withOpacity(.9),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // Open in Maps
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _openPlaceInMaps(p),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.map_outlined, size: 16),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Open in Google Maps',
                                        style: TextStyle(
                                          color: cs.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
    );
  }

  String _clock(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// --- Nearby place model -------------------------------------------------------

class _NearbyPlace {
  final String name;
  final String address;
  final double? rating;
  final int? ratingCount;
  final double latitude;
  final double longitude;
  final double distanceKm;

  _NearbyPlace({
    required this.name,
    required this.address,
    required this.rating,
    required this.ratingCount,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
  });
}

// --- Models for Directions response ------------------------------------------

enum _StepType { walk, transit }

class _TransitStep {
  final _StepType type;
  final String? instruction;
  final String? distanceText;
  final String? durationText;

  // Transit-only
  final String? transitLine;
  final String? transitHeadsign;
  final String? departureStop;
  final String? arrivalStop;
  final String? platform;
  final int? numStops;
  final DateTime? departureTime;
  final DateTime? arrivalTime;

  _TransitStep.walk({this.instruction, this.distanceText, this.durationText})
    : type = _StepType.walk,
      transitLine = null,
      transitHeadsign = null,
      departureStop = null,
      arrivalStop = null,
      platform = null,
      numStops = null,
      departureTime = null,
      arrivalTime = null;

  _TransitStep.transit({
    this.transitLine,
    this.transitHeadsign,
    this.departureStop,
    this.arrivalStop,
    this.platform,
    this.numStops,
    this.departureTime,
    this.arrivalTime,
    this.distanceText,
    this.durationText,
  }) : type = _StepType.transit,
       instruction = null;
}

class _TransitRoute {
  late String _dedupeKey; // internal

  final DateTime departureTime;
  final DateTime arrivalTime;
  final String totalText;
  final String summary;
  final List<_TransitStep> steps;

  _TransitRoute({
    required this.departureTime,
    required this.arrivalTime,
    required this.totalText,
    required this.summary,
    required this.steps,
  });

  static _TransitRoute? fromGoogle(Map leg, Map route, {DateTime? anchor}) {
    try {
      final durText = (leg['duration']?['text'] ?? '').toString();
      final durSec = (leg['duration']?['value'] as num?)?.toInt(); // seconds
      final summary = (route['summary'] ?? '').toString();

      final rawSteps = (leg['steps'] as List?) ?? const [];
      final steps = <_TransitStep>[];

      DateTime? firstTransitDep;
      DateTime? lastTransitArr;

      for (final s in rawSteps) {
        final travelMode = (s['travel_mode'] ?? '').toString();

        if (travelMode == 'WALKING') {
          steps.add(
            _TransitStep.walk(
              instruction: (s['html_instructions'] ?? '').toString().replaceAll(
                RegExp(r'<[^>]+>'),
                '',
              ),
              distanceText: (s['distance']?['text'] ?? '').toString(),
              durationText: (s['duration']?['text'] ?? '').toString(),
            ),
          );
        } else if (travelMode == 'TRANSIT') {
          final td = s['transit_details'] ?? {};
          final line = td['line'] ?? {};
          final depStop = td['departure_stop']?['name']?.toString();
          final arrStop = td['arrival_stop']?['name']?.toString();
          final headsign = (td['headsign'] ?? '').toString();
          final lineName = (line['short_name'] ?? line['name'] ?? '')
              .toString();
          final numStops = (td['num_stops'] as num?)?.toInt();
          final depTime = _parseGoogleTime(td['departure_time']);
          final arrTime = _parseGoogleTime(td['arrival_time']);
          final platform = (td['departure_platform'] ?? '').toString();

          firstTransitDep ??= depTime;
          if (arrTime != null) lastTransitArr = arrTime;

          steps.add(
            _TransitStep.transit(
              transitLine: lineName.isEmpty ? null : lineName,
              transitHeadsign: headsign.isNotEmpty ? headsign : null,
              departureStop: depStop,
              arrivalStop: arrStop,
              numStops: numStops,
              departureTime: depTime,
              arrivalTime: arrTime,
              platform: platform.isEmpty ? null : platform,
              distanceText: (s['distance']?['text'] ?? '').toString(),
              durationText: (s['duration']?['text'] ?? '').toString(),
            ),
          );
        }
      }

      // Prefer leg-level times
      DateTime? legDep = _parseGoogleTime(leg['departure_time']);
      DateTime? legArr = _parseGoogleTime(leg['arrival_time']);

      // Fallback to transit-step times if available
      legDep ??= firstTransitDep;
      legArr ??= lastTransitArr;

      // If still missing (e.g., walking-only route), use anchor + duration
      if (legDep == null && anchor != null) {
        legDep = anchor;
        if (durSec != null) legArr ??= anchor.add(Duration(seconds: durSec));
      }
      if (legArr == null && legDep != null && durSec != null) {
        legArr = legDep.add(Duration(seconds: durSec));
      }

      // If we still couldn't establish times, give up on this route
      if (legDep == null || legArr == null) {
        return null;
      }

      return _TransitRoute(
        departureTime: legDep,
        arrivalTime: legArr,
        totalText: durText,
        summary: summary,
        steps: steps,
      );
    } catch (_) {
      return null;
    }
  }

  static DateTime? _parseGoogleTime(dynamic obj) {
    if (obj == null) return null;
    final v = obj['value'];
    if (v is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        v * 1000,
        isUtc: false,
      ).toLocal();
    }
    return null;
  }
}

// --- Reusable card ------------------------------------------------------------

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
