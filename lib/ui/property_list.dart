import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:moon_design/moon_design.dart';
import 'package:moon_icons/moon_icons.dart';
import 'package:intl/intl.dart';

class ListingsPage extends StatefulWidget {
  const ListingsPage({super.key});

  @override
  State<ListingsPage> createState() => _ListingsPageState();
}

class _ListingsPageState extends State<ListingsPage> {
  final _searchCtrl = TextEditingController();

  // Filters
  int _typeIndex = -1; // -1 = all, 0 = entire_home, 1 = room
  int _sortIndex = 0; // 0 = Newest, 1 = Price ↑, 2 = Price ↓
  bool _furnishedOnly = false;
  bool _wifiOnly = false;
  bool _chargesInclOnly = false;
  bool _carParkOnly = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Query<Map<String, dynamic>> _baseQuery() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance.collection(
      'listings',
    );

    switch (_sortIndex) {
      case 1:
        q = q.orderBy('price');
        break;
      case 2:
        q = q.orderBy('price', descending: true);
        break;
      case 0:
      default:
        q = q.orderBy('createdAt', descending: true);
    }

    return q;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyClientSideFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var filtered = docs;

    // Client-side search on city / npa
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((d) {
        final m = d.data();
        final hay = [
          (m['city'] ?? '').toString(),
          (m['npa'] ?? '').toString(),
        ].join(' ').toLowerCase();
        return hay.contains(query);
      }).toList();
    }

    // Type filter (client-side)
    if (_typeIndex == 0) {
      filtered = filtered.where((d) {
        final type = (d.data()['type'] ?? '').toString().trim();
        return type == 'entire_home';
      }).toList();
    }
    if (_typeIndex == 1) {
      filtered = filtered.where((d) {
        final type = (d.data()['type'] ?? '').toString().trim();
        return type == 'room';
      }).toList();
    }

    // Boolean amenity filters (client-side)
    if (_furnishedOnly) {
      filtered = filtered.where((d) => d.data()['is_furnish'] == true).toList();
    }
    if (_wifiOnly) {
      filtered = filtered.where((d) => d.data()['wifi_incl'] == true).toList();
    }
    if (_chargesInclOnly) {
      filtered = filtered.where((d) => d.data()['charges_incl'] == true).toList();
    }
    if (_carParkOnly) {
      filtered = filtered.where((d) => d.data()['car_park'] == true).toList();
    }

    // Client-side sorting si on a des filtres qui ont pu changer l'ordre
    bool hasFilters = _typeIndex >= 0 || _furnishedOnly || _wifiOnly || _chargesInclOnly || _carParkOnly;
    if (hasFilters) {
      switch (_sortIndex) {
        case 1:
          filtered.sort((a, b) => (a.data()['price'] ?? 0).compareTo(b.data()['price'] ?? 0));
          break;
        case 2:
          filtered.sort((a, b) => (b.data()['price'] ?? 0).compareTo(a.data()['price'] ?? 0));
          break;
        case 0:
        default:

          filtered.sort((a, b) {
            final aCreated = a.data()['createdAt'] ?? '';
            final bCreated = b.data()['createdAt'] ?? '';
            return bCreated.compareTo(aCreated);
          });
          break;
      }
    }

    return filtered;
  }

  String _generateTitle(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString();
    final rooms = (data['num_rooms'] ?? 0).toString();
    final surface = (data['surface'] ?? 0).toString();
    final city = (data['city'] ?? '').toString();
    final furnished = data['is_furnish'] == true;

    String title = '';
    
    if (type == 'room') {
      title = furnished ? 'Furnished Room' : 'Room';
    } else if (type == 'entire_home') {
      if (rooms == '1' || rooms == '1.0') {
        title = furnished ? 'Furnished Studio' : 'Studio';
      } else {
        title = furnished ? 'Furnished ${rooms}-Room Apartment' : '${rooms}-Room Apartment';
      }
    } else {
      title = furnished ? 'Furnished Property' : 'Property';
    }

    if (surface != '0' && surface.isNotEmpty) {
      title += ' - ${surface}m²';
    }

    if (city.isNotEmpty) {
      title += ' in $city';
    }

    return title;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Listings'),
        actions: [
          IconButton(
            tooltip: 'Clear search',
            onPressed: () {
              if (_searchCtrl.text.isNotEmpty)
                setState(() => _searchCtrl.clear());
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          final isXL = constraints.maxWidth >= 1280;

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

          return Container(
            decoration: bg,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isXL
                          ? (constraints.maxWidth - 1200) / 2 + 16
                          : 16,
                      vertical: 16,
                    ),
                    child: _FilterBar(
                      searchCtrl: _searchCtrl,
                      typeIndex: _typeIndex,
                      sortIndex: _sortIndex,
                      furnishedOnly: _furnishedOnly,
                      wifiOnly: _wifiOnly,
                      chargesInclOnly: _chargesInclOnly,
                      carParkOnly: _carParkOnly,
                      onChanged: (f) => setState(() {
                        _typeIndex = f.typeIndex;
                        _sortIndex = f.sortIndex;
                        _furnishedOnly = f.furnishedOnly;
                        _wifiOnly = f.wifiOnly;
                        _chargesInclOnly = f.chargesInclOnly;
                        _carParkOnly = f.carParkOnly;
                      }),
                    ),
                  ),
                ),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _baseQuery().snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Error: ${snapshot.error}'),
                        ),
                      );
                    }

                    final docs = snapshot.data?.docs ?? [];
                    final filtered = _applyClientSideFilters(docs);

                    if (filtered.isEmpty) {
                      return const SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyState(),
                      );
                    }

                    // Responsive grid avec aspect ratio ajusté
                    int crossAxisCount = 1;
                    double childAspectRatio = 1.1; // Augmenté pour plus de hauteur
                    final w = constraints.maxWidth;
                    if (w >= 1400) {
                      crossAxisCount = 4;
                      childAspectRatio = 0.95; // Plus de hauteur pour 4 colonnes
                    } else if (w >= 1000) {
                      crossAxisCount = 3;
                      childAspectRatio = 1.0;
                    } else if (w >= 700) {
                      crossAxisCount = 2;
                      childAspectRatio = 1.05;
                    }

                    return SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isXL
                            ? (constraints.maxWidth - 1200) / 2 + 16
                            : 16,
                        vertical: 8,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: childAspectRatio,
                        ),
                        delegate: SliverChildBuilderDelegate((context, i) {
                          final data = filtered[i].data();
                          final title = _generateTitle(data);
                          return _ListingCard(data: data, title: title);
                        }, childCount: filtered.length),
                      ),
                    );
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final int typeIndex;
  final int sortIndex;
  final bool furnishedOnly;
  final bool wifiOnly;
  final bool chargesInclOnly;
  final bool carParkOnly;
  final ValueChanged<_Filters> onChanged;

  const _FilterBar({
    required this.searchCtrl,
    required this.typeIndex,
    required this.sortIndex,
    required this.furnishedOnly,
    required this.wifiOnly,
    required this.chargesInclOnly,
    required this.carParkOnly,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search
        Row(
          children: [
            Expanded(
              child: MoonFormTextInput(
                hasFloatingLabel: false,
                hintText: 'Search by city, NPA…',
                controller: searchCtrl,
                leading: const Icon(Icons.search),
                onChanged: (_) => onChanged(
                  _Filters(
                    typeIndex: typeIndex,
                    sortIndex: sortIndex,
                    furnishedOnly: furnishedOnly,
                    wifiOnly: wifiOnly,
                    chargesInclOnly: chargesInclOnly,
                    carParkOnly: carParkOnly,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Filters row
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Type segmented
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: MoonSegmentedControl(
                initialIndex: typeIndex < 0
                    ? 2
                    : typeIndex, // hack to allow All
                segments: const [
                  Segment(label: Text('Entire home')),
                  Segment(label: Text('Single room')),
                  Segment(label: Text('All')),
                ],
                onSegmentChanged: (i) {
                  // If user taps All (index 2), map to -1
                  final mapped = i == 2 ? -1 : i;
                  onChanged(
                    _Filters(
                      typeIndex: mapped,
                      sortIndex: sortIndex,
                      furnishedOnly: furnishedOnly,
                      wifiOnly: wifiOnly,
                      chargesInclOnly: chargesInclOnly,
                      carParkOnly: carParkOnly,
                    ),
                  );
                },
                isExpanded: false,
              ),
            ),

            // Sort segmented
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: MoonSegmentedControl(
                initialIndex: sortIndex,
                segments: const [
                  Segment(label: Text('Newest')),
                  Segment(label: Text('Price ↑')),
                  Segment(label: Text('Price ↓')),
                ],
                onSegmentChanged: (i) => onChanged(
                  _Filters(
                    typeIndex: typeIndex,
                    sortIndex: i,
                    furnishedOnly: furnishedOnly,
                    wifiOnly: wifiOnly,
                    chargesInclOnly: chargesInclOnly,
                    carParkOnly: carParkOnly,
                  ),
                ),
                isExpanded: false,
              ),
            ),

            // Toggles
            _BoolChip(
              label: 'Furnished',
              value: furnishedOnly,
              onChanged: (v) => onChanged(
                _Filters(
                  typeIndex: typeIndex,
                  sortIndex: sortIndex,
                  furnishedOnly: v,
                  wifiOnly: wifiOnly,
                  chargesInclOnly: chargesInclOnly,
                  carParkOnly: carParkOnly,
                ),
              ),
            ),
            _BoolChip(
              label: 'Wi‑Fi included',
              value: wifiOnly,
              onChanged: (v) => onChanged(
                _Filters(
                  typeIndex: typeIndex,
                  sortIndex: sortIndex,
                  furnishedOnly: furnishedOnly,
                  wifiOnly: v,
                  chargesInclOnly: chargesInclOnly,
                  carParkOnly: carParkOnly,
                ),
              ),
            ),
            _BoolChip(
              label: 'Charges included',
              value: chargesInclOnly,
              onChanged: (v) => onChanged(
                _Filters(
                  typeIndex: typeIndex,
                  sortIndex: sortIndex,
                  furnishedOnly: furnishedOnly,
                  wifiOnly: wifiOnly,
                  chargesInclOnly: v,
                  carParkOnly: carParkOnly,
                ),
              ),
            ),
            _BoolChip(
              label: 'Car park',
              value: carParkOnly,
              onChanged: (v) => onChanged(
                _Filters(
                  typeIndex: typeIndex,
                  sortIndex: sortIndex,
                  furnishedOnly: furnishedOnly,
                  wifiOnly: wifiOnly,
                  chargesInclOnly: chargesInclOnly,
                  carParkOnly: v,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BoolChip extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _BoolChip({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: value
              ? cs.primary.withOpacity(.15)
              : Theme.of(context).cardColor.withOpacity(.9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.primary.withOpacity(value ? .4 : .2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.check_circle : Icons.circle_outlined,
              size: 16,
              color: value ? cs.primary : cs.onSurface.withOpacity(.6),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.search, size: 56, color: cs.primary.withOpacity(.7)),
        const SizedBox(height: 12),
        Text(
          'No listings match your filters',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Try adjusting filters or clearing the search.',
          style: TextStyle(color: cs.onSurface.withOpacity(.7)),
        ),
      ],
    );
  }
}

class _ListingCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String title;
  const _ListingCard({required this.data, required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final price = (data['price'] ?? 0).toDouble();
    final currency = NumberFormat.currency(symbol: 'CHF', decimalDigits: 0);
    final priceStr = currency.format(price);

    final city = (data['city'] ?? '').toString();
    final npa = (data['npa'] ?? '').toString();
    final surface = (data['surface'] ?? 0).toString();
    final rooms = (data['num_rooms'] ?? '').toString();
    final type = (data['type'] ?? '').toString();

    final photos =
        (data['photos'] as List?)?.cast<String>() ?? const <String>[];
    final imageUrl = photos.isNotEmpty ? photos.first : null;

    final amenities = <String>[
      if (data['is_furnish'] == true) 'Furnished',
      if (data['wifi_incl'] == true) 'Wi‑Fi',
      if (data['charges_incl'] == true) 'Charges incl.',
      if (data['car_park'] == true) 'Car park',
    ];

    return InkWell(
      onTap: () {
        // property details page could be implemented
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withOpacity(.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.primary.withOpacity(0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.08),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image section - ratio ajusté
            Expanded(
              flex: 6,
              child: SizedBox(
                width: double.infinity,
                child: imageUrl == null
                    ? Container(
                        color: cs.primary.withOpacity(.08),
                        child: Center(
                          child: Icon(
                            Icons.image_outlined,
                            size: 40,
                            color: cs.primary.withOpacity(.6),
                          ),
                        ),
                      )
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
              ),
            ),

            // Content section - plus d'espace et mieux organisé
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title - plus compact
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15, // Réduit de 16 à 15
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Price + type - plus compact
                    Row(
                      children: [
                        Text(
                          priceStr,
                          style: const TextStyle(
                            fontSize: 17, // Réduit de 18 à 17
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: cs.primary.withOpacity(.25)),
                            ),
                            child: Text(
                              type,
                              style: TextStyle(
                                fontSize: 11, // Réduit de 12 à 11
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),
                    // Location - plus compact
                    Row(
                      children: [
                        Icon(
                          Icons.place,
                          size: 13, // Réduit de 14 à 13
                          color: cs.onSurface.withOpacity(.7),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '$city${npa.isNotEmpty ? ' · $npa' : ''}',
                            style: TextStyle(
                              fontSize: 12, // Réduit de 13 à 12
                              color: cs.onSurface.withOpacity(.8)
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3), // Réduit de 4 à 3
                    
                    // Surface et rooms - une seule ligne
                    Row(
                      children: [
                        Icon(
                          Icons.square_foot,
                          size: 13, // Réduit de 14 à 13
                          color: cs.onSurface.withOpacity(.7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          surface.isNotEmpty ? '$surface m²' : '—',
                          style: TextStyle(
                            fontSize: 12, // Réduit de 13 à 12
                            color: cs.onSurface.withOpacity(.8)
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.meeting_room,
                          size: 13, // Réduit de 14 à 13
                          color: cs.onSurface.withOpacity(.7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          rooms.isNotEmpty ? '$rooms rooms' : '—',
                          style: TextStyle(
                            fontSize: 12, // Réduit de 13 à 12
                            color: cs.onSurface.withOpacity(.8)
                          ),
                        ),
                      ],
                    ),

                    // Amenities - avec espacement flexible
                    if (amenities.isNotEmpty) ...[
                      const SizedBox(height: 6), // Réduit de 8 à 6
                      Flexible(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: amenities
                                .map(
                                  (a) => Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2, // Réduit de 3 à 2
                                      ),
                                      decoration: BoxDecoration(
                                        color: cs.primary.withOpacity(.08),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(
                                          color: cs.primary.withOpacity(.18),
                                        ),
                                      ),
                                      child: Text(
                                        a,
                                        style: const TextStyle(
                                          fontSize: 10, // Réduit de 11 à 10
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Filters {
  final int typeIndex;
  final int sortIndex;
  final bool furnishedOnly;
  final bool wifiOnly;
  final bool chargesInclOnly;
  final bool carParkOnly;
  _Filters({
    required this.typeIndex,
    required this.sortIndex,
    required this.furnishedOnly,
    required this.wifiOnly,
    required this.chargesInclOnly,
    required this.carParkOnly,
  });
}