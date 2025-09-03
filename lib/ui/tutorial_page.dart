// tutorial_page.dart
import 'package:flutter/material.dart';
import 'package:moon_design/moon_design.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'page.dart'; // same wrapper you use on ProfilePage

class TutorialPage extends StatefulWidget {
  const TutorialPage({super.key});

  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  bool _loading = true;
  bool _isHomeowner = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final role = (snap.data()?['role'] ?? '').toString();
        _isHomeowner = role == 'homeowner';
      }
    } catch (_) {
      _isHomeowner = false;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.moonTheme?.tokens ?? MoonTokens.light;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return BasePage(
      title: 'Tutorial',
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(
                    context,
                    icon: Icons.school_outlined,
                    title: 'Welcome to HEStimate',
                    subtitle:
                        'This short guide walks you through the main features. '
                        'Screenshots follow the Moon theme.',
                  ),

                  const SizedBox(height: 24),
                  _sectionTitle(context, 'Browse & discover'),

                  _card(
                    context,
                    title: 'Search & filters',
                    description:
                        'Filter by type, amenities and price. Tap the heart to add favorites.',
                    child: _tutorialImage('assets/tutorial/all_properties.png'),
                  ),

                  const SizedBox(height: 16),
                  finalWrap(
                    children: [
                      _card(
                        context,
                        title: 'Listing details',
                        description:
                            'Photos, address and quick chips (price, m², rooms, floor, proximity).',
                        child: _tutorialImage(
                            'assets/tutorial/listing_header.png'),
                      ),
                      _card(
                        context,
                        title: 'Price estimation',
                        description:
                            'Tap “Estimate price”. We compare the predicted and actual price.',
                        child: _tutorialImage(
                            'assets/tutorial/price_estimation_result.png'),
                      ),
                      _card(
                        context,
                        title: 'Public transport to HES',
                        description:
                            'Upcoming routes for the next 2 hours. Swipe to browse.',
                        child: _tutorialImage(
                            'assets/tutorial/transit_to_hes.png'),
                      ),
                      _card(
                        context,
                        title: 'Nearby bars',
                        description:
                            'Best-rated bars around the listing. Tap to expand or open Maps.',
                        child:
                            _tutorialImage('assets/tutorial/nearby_bars.png'),
                      ),

                      _card(
                        context,
                        title: 'Property reviews',
                        description:
                            'See the average rating, tags, and all reviews for a listing.',
                        child: _tutorialImage(
                            'assets/tutorial/listing_reviews.png'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  finalWrap(
                    children: [
                      _card(
                        context,
                        title: 'Availability',
                        description:
                            'Calendar shows available days and existing bookings with a legend.',
                        child: _tutorialImage(
                            'assets/tutorial/availability_calendar.png'),
                      ),
                      _card(
                        context,
                        title: 'Request a booking',
                        description:
                            'Pick your dates, write a short intro message, optionally add a phone.',
                        child:
                            _tutorialImage('assets/tutorial/booking_panel.png'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  _sectionTitle(context, 'Manage your bookings'),

                  finalWrap(
                    children: [
                      _card(
                        context,
                        title: 'Current',
                        description:
                            'Upcoming or ongoing stays are grouped here with clear dates.',
                        child: _tutorialImage(
                            'assets/tutorial/bookings_current.png'),
                      ),
                      _card(
                        context,
                        title: 'Pending',
                        description:
                            'Requests you sent but aren’t approved yet. You can cancel them here.',
                        child: _tutorialImage(
                            'assets/tutorial/bookings_pending.png'),
                      ),
                      _card(
                        context,
                        title: 'Rate',
                        description:
                            'Finished stays appear here; add your rating once the booking is completed.',
                        child:
                            _tutorialImage('assets/tutorial/bookings_rate.png'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  _sectionTitle(context, 'Profile & Face ID'),

                  finalWrap(
                    children: [
                      _card(
                        context,
                        title: 'Profile',
                        description:
                            'See your details and quick actions (edit, Face ID, sign out).',
                        child:
                            _tutorialImage('assets/tutorial/profile_view.png'),
                      ),
                      _card(
                        context,
                        title: 'Edit profile',
                        description:
                            'Update your name and (if you are a student) your school.',
                        child:
                            _tutorialImage('assets/tutorial/profile_edit.png'),
                      ),
                      _card(
                        context,
                        title: 'Face ID',
                        description:
                            'Enable Face ID and manage your local face photo securely.',
                        child: _tutorialImage('assets/tutorial/face_id.png'),
                      ),
                    ],
                  ),

                  // ---------- HOMEOWNER ONLY ----------
                  if (_isHomeowner) ...[
                    const SizedBox(height: 28),
                    _divider(tokens),
                    const SizedBox(height: 20),
                    _sectionTitle(context, 'For homeowners'),

                    _card(
                      context,
                      title: 'My Properties',
                      description:
                          'All your listings with the same filters and favorite toggles.',
                      child: _tutorialImage(
                          'assets/tutorial/owner_my_properties.png'),
                    ),

                    const SizedBox(height: 16),
                    _card(
                      context,
                      title: 'Quick actions on a listing',
                      description:
                          'From the Listing screen, use the heart to favorite and the pencil to edit your property.',
                      child: _tutorialImageThemeAware('listing_edit_appbar'),
                    ),

                    const SizedBox(height: 16),
                    _sectionTitle(context, 'Create or edit a listing'),

                    finalWrap(
                      children: [
                        _card(
                          context,
                          title: 'Basics',
                          description:
                              'Address, city, postal code (NPA), surface, rooms, floor and type.',
                          child: _tutorialImage(
                              'assets/tutorial/new_listing_basics.png'),
                        ),
                        _card(
                          context,
                          title: 'Amenities',
                          description:
                              'Furnished, Wi-Fi included, Charges included and Car park.',
                          child: _tutorialImage(
                              'assets/tutorial/new_listing_amenities.png'),
                        ),
                        _card(
                          context,
                          title: 'Availability',
                          description:
                              'Choose a start date and an optional end date or enable “No end”.',
                          child: _tutorialImage(
                              'assets/tutorial/new_listing_availability.png'),
                        ),
                        _card(
                          context,
                          title: 'Distances',
                          description:
                              'We compute public transport distance and HES proximity.',
                          child: _tutorialImage(
                              'assets/tutorial/new_listing_distances.png'),
                        ),
                        _card(
                          context,
                          title: 'Photos',
                          description:
                              'Pick multiple images to showcase your place; they appear in the gallery.',
                          child: _tutorialImage(
                              'assets/tutorial/new_listing_photos.png'),
                        ),
                        _card(
                          context,
                          title: 'Pricing & Estimator',
                          description:
                              'Set your price and optionally run the estimator to compare.',
                          child: _tutorialImage(
                              'assets/tutorial/new_listing_pricing.png'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    _sectionTitle(context, 'Owner management'),

                    finalWrap(
                      children: [
                        _card(
                          context,
                          title: 'Requests',
                          description:
                              'Approve or reject booking requests with one tap.',
                          child: _tutorialImage(
                              'assets/tutorial/owner_requests.png'),
                        ),
                        _card(
                          context,
                          title: 'Reviews',
                          description:
                              'See ratings left by students for completed stays.',
                          child:
                              _tutorialImage('assets/tutorial/owner_reviews.png'),
                        ),
                        _card(
                          context,
                          title: 'Students',
                          description:
                              'Overview of upcoming guests per property.',
                          child:
                              _tutorialImage('assets/tutorial/owner_students.png'),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 24),
                  _footerNote(
                    context,
                    'Tip: Reopen this tutorial anytime from the help icon in the top bar.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- helpers ----------
  Widget _header(BuildContext context,
      {required IconData icon, required String title, String? subtitle}) {
    final tokens = context.moonTheme?.tokens ?? MoonTokens.light;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.colors.piccolo.withOpacity(.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: tokens.colors.piccolo),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Theme.of(context).hintColor),
                  ),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    final tokens = context.moonTheme?.tokens ?? MoonTokens.light;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.star_outline_rounded, color: tokens.colors.piccolo, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _divider(MoonTokens tokens) =>
      Container(height: 1, color: tokens.colors.piccolo.withOpacity(.15));

  Widget finalWrap({required List<Widget> children}) {
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth;
        final cardW = maxW >= 900 ? (maxW - 16) / 2 : maxW;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: children
              .map((w) => SizedBox(width: cardW, child: w))
              .toList(),
        );
      },
    );
  }

  Widget _card(BuildContext context,
      {required String title, String? description, required Widget child}) {
    final tokens = context.moonTheme?.tokens ?? MoonTokens.light;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.colors.piccolo.withOpacity(.15)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          if (description != null) ...[
            const SizedBox(height: 6),
            Text(
              description,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Theme.of(context).hintColor),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // ---------- Click-to-expand images ----------
  Widget _tutorialImage(String assetPath) {
    final heroTag = 'tut:$assetPath';
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: GestureDetector(
          onTap: () => _openAssetViewer(assetPath,
              heroTag: heroTag, fallbackPath: null),
          child: Hero(
            tag: heroTag,
            child: Image.asset(
              assetPath,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stack) => _missing(assetPath),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tutorialImageThemeAware(String baseName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themed =
        'assets/tutorial/${baseName}_${isDark ? 'dark' : 'light'}.png';
    final fallback = 'assets/tutorial/$baseName.png';
    final heroTag = 'tut_theme:$baseName:${isDark ? 'dark' : 'light'}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: GestureDetector(
          onTap: () => _openAssetViewer(themed,
              heroTag: heroTag, fallbackPath: fallback),
          child: Hero(
            tag: heroTag,
            child: Image.asset(
              themed,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => Image.asset(
                fallback,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (c, e, s) => _missing(fallback),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openAssetViewer(String primaryPath,
      {required String heroTag, String? fallbackPath}) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, a, b) {
        return GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: Hero(
                      tag: heroTag,
                      child: InteractiveViewer(
                        maxScale: 4,
                        minScale: 0.5,
                        child: Image.asset(
                          primaryPath,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) {
                            if (fallbackPath != null) {
                              return Image.asset(
                                fallbackPath,
                                fit: BoxFit.contain,
                                errorBuilder: (c, e, s) => _missing(fallbackPath),
                              );
                            }
                            return _missing(primaryPath);
                          },
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _missing(String path) => Container(
        color: Theme.of(context).cardColor,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image_outlined, size: 28),
            const SizedBox(height: 8),
            Text(
              'Missing asset:\n$path',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );

  Widget _footerNote(BuildContext context, String note) {
    final tokens = context.moonTheme?.tokens ?? MoonTokens.light;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.colors.piccolo.withOpacity(.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: tokens.colors.piccolo),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              note,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor),
            ),
          ),
        ],
      ),
    );
  }
}
