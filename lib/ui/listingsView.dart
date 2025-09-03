import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:moon_design/moon_design.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart' as fstorage;

import 'view_listing_page.dart';
import 'rate_listing_page.dart';

enum ListingsMode {
  all, // Show all listings
  owner, // Show only current user's listings
}

class ListingsPage extends StatefulWidget {
  final ListingsMode mode;

  const ListingsPage({
    super.key,
    this.mode = ListingsMode.all,
  });

  @override
  State<ListingsPage> createState() => _ListingsPageState();
}

class _ListingsPageState extends State<ListingsPage>
    with AutomaticKeepAliveClientMixin {
  final _searchCtrl = TextEditingController();

  // Filters
  int _typeIndex = -1; // -1 = all, 0 = entire_home, 1 = room
  int _sortIndex = 0; // 0 = Newest, 1 = Price ↑, 2 = Price ↓
  bool _furnishedOnly = false;
  bool _wifiOnly = false;
  bool _chargesInclOnly = false;
  bool _carParkOnly = false;
  bool _favoritesOnly = false;

  double? _globalMinPrice;
  double? _globalMaxPrice;
  double? _minPrice;
  double? _maxPrice;

  @override
  bool get wantKeepAlive => true;

  // --- FAVORITES STREAM (user ↔ listing link table) ---
  late final Stream<Set<String>> _favoritesStream;
  late final StreamSubscription<Set<String>> _favSub;
  Set<String> _lastFavIds = {};

  Stream<Set<String>> _userFavoritesStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(<String>{});
    return FirebaseFirestore.instance
        .collection('favorites')
        .where('userUid', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) {
              final m = d.data() as Map<String, dynamic>;
              final lid = (m['listingId'] ?? '').toString();
              return lid.isNotEmpty ? lid : d.id.split('_').last;
            })
            .where((id) => id.isNotEmpty)
            .toSet());
  }

  Future<void> _fetchPriceBounds() async {
    Query<Map<String, dynamic>> baseQuery =
        FirebaseFirestore.instance.collection('listings');

    if (widget.mode == ListingsMode.owner) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() {
          _globalMinPrice = 0;
          _globalMaxPrice = 10000;
          _minPrice = 0;
          _maxPrice = 10000;
        });
        return;
      }
      baseQuery = baseQuery.where('ownerUid', isEqualTo: uid);
    }

    final minSnap =
        await baseQuery.orderBy('price', descending: false).limit(1).get();
    final maxSnap =
        await baseQuery.orderBy('price', descending: true).limit(1).get();

    final minPrice = minSnap.docs.isNotEmpty
        ? (minSnap.docs.first['price'] ?? 0).toDouble()
        : 0;
    final maxPrice = maxSnap.docs.isNotEmpty
        ? (maxSnap.docs.first['price'] ?? 0).toDouble()
        : 10000;

    setState(() {
      _globalMinPrice = minPrice;
      _globalMaxPrice = maxPrice;
      _minPrice = minPrice;
      _maxPrice = maxPrice;
    });
  }

  // -----------------------------
  //        PAGINATION STATE
  // -----------------------------
  static const int _pageSize = 16;
  int _pageIndex = 0; // 0-based
  bool _isLoadingPage = false;
  bool _isInitialLoad = true; // NOUVEAU: pour distinguer le premier chargement
  bool _hasNextPage = true;

  // Curseurs: dernier doc de chaque page, pour startAfter de la page suivante.
  final List<DocumentSnapshot<Map<String, dynamic>>?> _pageCursors = [];

  // Résultats de la page courante (bruts serveur, avant filtrage client)
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _currentPageDocs = [];

  // (Optionnel) total de résultats côté serveur (si count() dispo)
  int? _totalCount;

  // -----------------------------
  //        INIT / DISPOSE
  // -----------------------------
  @override
  void initState() {
    super.initState();
    _favoritesStream = _userFavoritesStream();
    _favSub = _favoritesStream.listen((s) => _lastFavIds = s);
    _fetchPriceBounds();
    _pageCursors.add(null); // cursor initial (page 0)
    _loadPage(toIndex: 0);
  }

  @override
  void dispose() {
    _favSub.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // -----------------------------
  //      QUERIES CONSTRUCTION
  // -----------------------------
  bool get _hasActivePriceRange => _minPrice != null || _maxPrice != null;

  bool get _clientOnlyFiltersActive {
    final query = _searchCtrl.text.trim();
    return query.isNotEmpty ||
        _favoritesOnly ||
        _furnishedOnly ||
        _wifiOnly ||
        _chargesInclOnly ||
        _carParkOnly;
  }

  Query<Map<String, dynamic>> _baseServerQuery() {
    Query<Map<String, dynamic>> q =
        FirebaseFirestore.instance.collection('listings');

    // 1) Filtre owner (coté serveur = OK)
    if (widget.mode == ListingsMode.owner) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      q = uid == null
          ? q.where('ownerUid', isEqualTo: '__none__')
          : q.where('ownerUid', isEqualTo: uid);
    }

    // 2) Quelques filtres sûrs côté serveur (éviter explosion d'index)
    if (_typeIndex == 0) q = q.where('type', isEqualTo: 'entire_home');
    if (_typeIndex == 1) q = q.where('type', isEqualTo: 'room');

    if (_hasActivePriceRange) {
      if (_minPrice != null) {
        q = q.where('price', isGreaterThanOrEqualTo: _minPrice);
      }
      if (_maxPrice != null) {
        q = q.where('price', isLessThanOrEqualTo: _maxPrice);
      }

      // IMPORTANT: le 1er orderBy = le champ des inégalités (price)
      final priceDesc = (_sortIndex == 2); // "Price ↓" => desc
      q = q.orderBy('price', descending: priceDesc);

      // Secondaire pour stabiliser : pas obligatoire, mais pratique
      q = q.orderBy('createdAt', descending: true);
    } else {
      // Pas de range sur price -> on peut trier comme on veut
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
    }

    return q;
  }

  // -----------------------------
  //          LOAD PAGE
  // -----------------------------
  Future<void> _loadPage({int? toIndex}) async {
    if (_isLoadingPage) return;
    setState(() => _isLoadingPage = true);

    try {
      if (toIndex != null && toIndex != _pageIndex) {
        _pageIndex = toIndex.clamp(0, _pageCursors.length);
      }

      // On va potentiellement boucler pour remplir la page filtrée
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> collected = [];
      DocumentSnapshot<Map<String, dynamic>>? localCursor =
          _pageIndex > 0 ? _pageCursors[_pageIndex - 1] : null;

      // Si filtres clients actifs → on tire des batchs plus gros pour remplir la page
      final int serverBatch = _clientOnlyFiltersActive ? (_pageSize * 3) : _pageSize;

      bool hasMoreServer = true;
      while (true) {
        Query<Map<String, dynamic>> q = _baseServerQuery().limit(serverBatch);
        if (localCursor != null) q = q.startAfterDocument(localCursor);

        final snap = await q.get();
        final batchDocs = snap.docs;
        if (batchDocs.isEmpty) {
          hasMoreServer = false;
        } else {
          collected.addAll(batchDocs);
          localCursor = batchDocs.last; // avance le curseur
        }

        // Vérifie si, après filtrage client, on a assez d'items à afficher
        final filteredNow = _applyClientSideFilters(collected, _lastFavIds);
        final enoughForPage = filteredNow.length >= _pageSize;
        final noMoreServerNow = batchDocs.length < serverBatch;

        if (enoughForPage || !hasMoreServer || noMoreServerNow) {
          _currentPageDocs = collected;

          // Curseur de page = dernier doc collecté
          if (_pageCursors.length <= _pageIndex) {
            _pageCursors.add(collected.isNotEmpty ? collected.last : null);
          } else {
            _pageCursors[_pageIndex] =
                collected.isNotEmpty ? collected.last : null;
          }

          // S'il reste potentiellement une suite côté serveur
          _hasNextPage = hasMoreServer && !noMoreServerNow;
          break;
        }
      }

      // (Optionnel) total
      try {
        final agg = await _baseServerQuery().count().get();
        _totalCount = agg.count;
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur chargement: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPage = false;
          _isInitialLoad = false; // NOUVEAU: marquer la fin du premier chargement
        });
      }
    }
  }

  void _resetAndReload() {
    _pageIndex = 0;
    _pageCursors
      ..clear()
      ..add(null);
    setState(() {
      _isInitialLoad = true; // NOUVEAU: reset pour le chargement initial
    });
    _loadPage(toIndex: 0);
  }

  // -----------------------------
  //    CLIENT-SIDE EXTRA FILTERS
  // -----------------------------
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyClientSideFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Set<String> favIds,
  ) {
    var filtered = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);

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

    // Si certains filtres n'ont pas pu être poussés serveur, on les garde ici :
    if (_typeIndex == 0) {
      filtered = filtered
          .where((d) =>
              (d.data()['type'] ?? '').toString().trim() == 'entire_home')
          .toList();
    }
    if (_typeIndex == 1) {
      filtered = filtered
          .where((d) => (d.data()['type'] ?? '').toString().trim() == 'room')
          .toList();
    }
    if (_furnishedOnly) {
      filtered = filtered.where((d) => d.data()['is_furnish'] == true).toList();
    }
    if (_wifiOnly) {
      filtered = filtered.where((d) => d.data()['wifi_incl'] == true).toList();
    }
    if (_chargesInclOnly) {
      filtered =
          filtered.where((d) => d.data()['charges_incl'] == true).toList();
    }
    if (_carParkOnly) {
      filtered = filtered.where((d) => d.data()['car_park'] == true).toList();
    }
    if (_favoritesOnly) {
      filtered = filtered.where((d) => favIds.contains(d.id)).toList();
    }

    if (_minPrice != null && _maxPrice != null) {
      filtered = filtered.where((d) {
        final price = (d.data()['price'] ?? 0).toDouble();
        return price >= _minPrice! && price <= _maxPrice!;
      }).toList();
    }

    // Re-sort si des filtres ont potentiellement cassé l'ordre initial
    final hasFilters = _typeIndex >= 0 ||
        _furnishedOnly ||
        _wifiOnly ||
        _chargesInclOnly ||
        _carParkOnly ||
        _favoritesOnly ||
        query.isNotEmpty ||
        _minPrice != null ||
        _maxPrice != null;

    if (hasFilters) {
      switch (_sortIndex) {
        case 1:
          filtered.sort((a, b) =>
              (a.data()['price'] ?? 0).compareTo(b.data()['price'] ?? 0));
          break;
        case 2:
          filtered.sort((a, b) =>
              (b.data()['price'] ?? 0).compareTo(a.data()['price'] ?? 0));
          break;
        case 0:
        default:
          filtered.sort((a, b) {
            final aCreated = a.data()['createdAt'] ?? '';
            final bCreated = b.data()['createdAt'] ?? '';
            return bCreated.compareTo(aCreated);
          });
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
        title = furnished
            ? 'Furnished ${rooms}-Room Apartment'
            : '${rooms}-Room Apartment';
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

  String get _pageTitle =>
      widget.mode == ListingsMode.all ? 'All Properties' : 'My Properties';
  String get _emptyStateMessage => widget.mode == ListingsMode.all
      ? 'No listings match your filters'
      : 'You have no listings yet';
  String get _emptyStateSubMessage => widget.mode == ListingsMode.all
      ? 'Try adjusting filters or clearing the search.'
      : 'Create your first listing to get started.';

  Future<void> _toggleFavorite(
      String listingId, bool isCurrentlyFavorite) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connecte-toi pour utiliser les favoris.')),
      );
      return;
    }
    final favDocId = '${uid}_$listingId';
    final ref =
        FirebaseFirestore.instance.collection('favorites').doc(favDocId);

    try {
      if (isCurrentlyFavorite) {
        await ref.delete();
      } else {
        await ref.set({
          'userUid': uid,
          'listingId': listingId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur favoris: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_pageTitle),
        actions: [
          IconButton(
            tooltip: 'Clear search',
            onPressed: () {
              if (_searchCtrl.text.isNotEmpty) {
                setState(() => _searchCtrl.clear());
                _resetAndReload();
              }
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
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
                      horizontal:
                          isXL ? (constraints.maxWidth - 1200) / 2 + 16 : 16,
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
                      favoritesOnly: _favoritesOnly,
                      minPrice: _minPrice ?? (_globalMinPrice ?? 0),
                      maxPrice: _maxPrice ?? (_globalMaxPrice ?? 10000),
                      globalMinPrice: _globalMinPrice,
                      globalMaxPrice: _globalMaxPrice,
                      onChanged: (f) {
                        setState(() {
                          _typeIndex = f.typeIndex;
                          _sortIndex = f.sortIndex;
                          _furnishedOnly = f.furnishedOnly;
                          _wifiOnly = f.wifiOnly;
                          _chargesInclOnly = f.chargesInclOnly;
                          _carParkOnly = f.carParkOnly;
                          _favoritesOnly = f.favoritesOnly;
                          _minPrice = f.minPrice;
                          _maxPrice = f.maxPrice;
                        });
                        _resetAndReload();
                      },
                    ),
                  ),
                ),

                // MODIFIÉ: Gestion améliorée des loaders
                StreamBuilder<Set<String>>(
                  stream: _favoritesStream,
                  builder: (context, favSnap) {
                    final favIds = favSnap.data ?? <String>{};

                    // Filtrage client + coupe à _pageSize pour la page
                    final filtered =
                        _applyClientSideFilters(_currentPageDocs, favIds);
                    final pageItems = filtered.take(_pageSize).toList();

                    // Responsive grid settings
                    int crossAxisCount = 1;
                    double childAspectRatio = 1.1;
                    final w = constraints.maxWidth;
                    if (w >= 1400) {
                      crossAxisCount = 4;
                      childAspectRatio = 0.95;
                    } else if (w >= 1000) {
                      crossAxisCount = 3;
                      childAspectRatio = 1.0;
                    } else if (w >= 700) {
                      crossAxisCount = 2;
                      childAspectRatio = 1.05;
                    }

                    // NOUVEAU: Loader pour le premier chargement (prend toute la page)
                    if (_isLoadingPage && _isInitialLoad) {
                      return const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Chargement des annonces...'),
                            ],
                          ),
                        ),
                      );
                    }

                    // NOUVEAU: Loader pour la pagination (remplace temporairement le grid)
                    if (_isLoadingPage && !_isInitialLoad) {
                      return SliverPadding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isXL ? (constraints.maxWidth - 1200) / 2 + 16 : 16,
                          vertical: 8,
                        ),
                        sliver: const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text('Chargement de la page...'),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    if (pageItems.isEmpty) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyState(
                          message: _emptyStateMessage,
                          subMessage: _emptyStateSubMessage,
                          mode: widget.mode,
                        ),
                      );
                    }

                    return SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal:
                            isXL ? (constraints.maxWidth - 1200) / 2 + 16 : 16,
                        vertical: 8,
                      ),
                      sliver: SliverGrid(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: childAspectRatio,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final doc = pageItems[i];
                            final data = doc.data();
                            final title = _generateTitle(data);
                            final isFav = favIds.contains(doc.id);

                            return _ListingCard(
                              key: ValueKey(doc.id),
                              listingId: doc.id,
                              data: data,
                              title: title,
                              isFavorite: isFav,
                              onToggleFavorite: () =>
                                  _toggleFavorite(doc.id, isFav),
                            );
                          },
                          childCount: pageItems.length,
                          findChildIndexCallback: (Key key) {
                            final id = (key as ValueKey<String>).value;
                            final index =
                                pageItems.indexWhere((d) => d.id == id);
                            return index == -1 ? null : index;
                          },
                          addAutomaticKeepAlives: false,
                          addRepaintBoundaries: true,
                        ),
                      ),
                    );
                  },
                ),

                // Pagination footer
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          isXL ? (constraints.maxWidth - 1200) / 2 + 16 : 16,
                      vertical: 12,
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: (_pageIndex > 0 && !_isLoadingPage)
                                  ? () async {
                                      setState(() => _pageIndex--);
                                      await _loadPage();
                                    }
                                  : null,
                              icon: const Icon(Icons.chevron_left),
                              label: const Text('Précédent'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: (_hasNextPage && !_isLoadingPage)
                                  ? () async {
                                      setState(() => _pageIndex++);
                                      await _loadPage();
                                    }
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                              label: const Text('Suivant'),
                            ),
                          ],
                        ),
                        // NOUVEAU: Affichage de l'état de pagination
                        if (!_isLoadingPage && _currentPageDocs.isNotEmpty)
                          Text(
                            'Page ${_pageIndex + 1}${_totalCount != null ? ' / ${((_totalCount! - 1) ~/ _pageSize) + 1}' : ''}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
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

// Les classes _FilterBar, _BoolChip, _EmptyState, _ListingCard et _Filters restent identiques
class _FilterBar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final int typeIndex;
  final int sortIndex;
  final bool furnishedOnly;
  final bool wifiOnly;
  final bool chargesInclOnly;
  final bool carParkOnly;
  final bool favoritesOnly;
  final double minPrice;
  final double maxPrice;
  final double? globalMinPrice;
  final double? globalMaxPrice;
  final ValueChanged<_Filters> onChanged;

  const _FilterBar({
    required this.searchCtrl,
    required this.typeIndex,
    required this.sortIndex,
    required this.furnishedOnly,
    required this.wifiOnly,
    required this.chargesInclOnly,
    required this.carParkOnly,
    required this.favoritesOnly,
    required this.minPrice,
    required this.maxPrice,
    required this.globalMinPrice,
    required this.globalMaxPrice,
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
                hintText: 'Search by city, NPA',
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
                    favoritesOnly: favoritesOnly,
                    minPrice: minPrice,
                    maxPrice: maxPrice,
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
            // Type
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: MoonSegmentedControl(
                initialIndex: typeIndex < 0 ? 2 : typeIndex, // All hack
                segments: const [
                  Segment(label: Text('Entire home')),
                  Segment(label: Text('Single room')),
                  Segment(label: Text('All')),
                ],
                onSegmentChanged: (i) {
                  final mapped = i == 2 ? -1 : i;
                  onChanged(
                    _Filters(
                      typeIndex: mapped,
                      sortIndex: sortIndex,
                      furnishedOnly: furnishedOnly,
                      wifiOnly: wifiOnly,
                      chargesInclOnly: chargesInclOnly,
                      carParkOnly: carParkOnly,
                      favoritesOnly: favoritesOnly,
                      minPrice: minPrice,
                      maxPrice: maxPrice,
                    ),
                  );
                },
                isExpanded: false,
              ),
            ),

            // Sort
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
                    favoritesOnly: favoritesOnly,
                    minPrice: minPrice,
                    maxPrice: maxPrice,
                  ),
                ),
                isExpanded: false,
              ),
            ),

            // Toggles (client-only pour limiter les index)
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
                  favoritesOnly: favoritesOnly,
                  minPrice: minPrice,
                  maxPrice: maxPrice,
                ),
              ),
            ),
            _BoolChip(
              label: 'Wi-Fi included',
              value: wifiOnly,
              onChanged: (v) => onChanged(
                _Filters(
                  typeIndex: typeIndex,
                  sortIndex: sortIndex,
                  furnishedOnly: furnishedOnly,
                  wifiOnly: v,
                  chargesInclOnly: chargesInclOnly,
                  carParkOnly: carParkOnly,
                  favoritesOnly: favoritesOnly,
                  minPrice: minPrice,
                  maxPrice: maxPrice,
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
                  favoritesOnly: favoritesOnly,
                  minPrice: minPrice,
                  maxPrice: maxPrice,
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
                  favoritesOnly: favoritesOnly,
                  minPrice: minPrice,
                  maxPrice: maxPrice,
                ),
              ),
            ),

            // Favorites only
            _BoolChip(
              label: 'Favorites',
              value: favoritesOnly,
              onChanged: (v) => onChanged(
                _Filters(
                  typeIndex: typeIndex,
                  sortIndex: sortIndex,
                  furnishedOnly: furnishedOnly,
                  wifiOnly: wifiOnly,
                  chargesInclOnly: chargesInclOnly,
                  carParkOnly: carParkOnly,
                  favoritesOnly: v,
                  minPrice: minPrice,
                  maxPrice: maxPrice,
                ),
              ),
            ),
          ],
        ),

        if (globalMinPrice != null && globalMaxPrice != null) ...[
          const SizedBox(height: 16),
          const Text(
            "Price range (CHF)",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          RangeSlider(
            values: RangeValues(minPrice, maxPrice),
            min: globalMinPrice!,
            max: globalMaxPrice!,
            divisions: 50,
            labels: RangeLabels(
              minPrice.round().toString(),
              maxPrice.round().toString(),
            ),
            onChanged: (values) {
              onChanged(
                _Filters(
                  typeIndex: typeIndex,
                  sortIndex: sortIndex,
                  furnishedOnly: furnishedOnly,
                  wifiOnly: wifiOnly,
                  chargesInclOnly: chargesInclOnly,
                  carParkOnly: carParkOnly,
                  favoritesOnly: favoritesOnly,
                  minPrice: values.start,
                  maxPrice: values.end,
                ),
              );
            },
          ),
        ],
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
  final String message;
  final String subMessage;
  final ListingsMode mode;

  const _EmptyState({
    required this.message,
    required this.subMessage,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          mode == ListingsMode.owner ? Icons.home_outlined : Icons.search,
          size: 56,
          color: cs.primary.withOpacity(.7),
        ),
        const SizedBox(height: 12),
        Text(
          message,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subMessage,
          style: TextStyle(color: cs.onSurface.withOpacity(.7)),
        ),
        if (mode == ListingsMode.owner) ...[
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pushNamed('/newListing');
            },
            icon: const Icon(Icons.add),
            label: const Text('Create your first listing'),
          ),
        ],
      ],
    );
  }
}

class _ListingCard extends StatelessWidget {
  final String listingId;
  final Map<String, dynamic> data;
  final String title;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  const _ListingCard({
    super.key,
    required this.listingId,
    required this.data,
    required this.title,
    required this.isFavorite,
    required this.onToggleFavorite,
  });

  // --- Helpers image -------------------------------------------------

  Future<String?> _resolveImageUrl(String? raw) async {
    if (raw == null) return null;
    final u = raw.trim();
    if (u.isEmpty) return null;

    // Normaliser protocole
    if (u.startsWith('//')) return 'https:$u';
    if (u.startsWith('http://')) return 'https://${u.substring(7)}';
    if (u.startsWith('https://')) return u;

    // gs:// => Storage downloadURL
    if (u.startsWith('gs://')) {
      try {
        final ref = fstorage.FirebaseStorage.instance.refFromURL(u);
        return await ref.getDownloadURL();
      } catch (_) {
        return null;
      }
    }

    // Autres formats non supportés
    return null;
  }

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
      if (data['wifi_incl'] == true) 'Wi-Fi',
      if (data['charges_incl'] == true) 'Charges incl.',
      if (data['car_park'] == true) 'Car park',
    ];

    Widget _starsRow(BuildContext context, double avg, int count) {
      final cs = Theme.of(context).colorScheme;
      final full = avg.round().clamp(0, 5);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...List.generate(5, (i) {
            final filled = i < full;
            return Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(
                filled ? Icons.star_rounded : Icons.star_border_rounded,
                size: 16,
                color: filled ? cs.primary : cs.onSurface.withOpacity(.35),
              ),
            );
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

    final ratingsPreview = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('listing_reviews')
          .where('listingId', isEqualTo: listingId)
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
                  acc + ((d.data()['rating'] as num?)?.toDouble() ?? 0.0),
            );
            avg = sum / count;
          }
        }
        return InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => RateListingPage(
                  listingId: listingId,
                  allowAdd: false,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(top: 6.0, bottom: 2.0),
            child: _starsRow(context, avg, count),
          ),
        );
      },
    );

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ViewListingPage(listingId: listingId),
          ),
        );
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
            // --- Image ---------------------------------------------------
            Expanded(
              flex: 6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<String?>(
                    future: _resolveImageUrl(imageUrl),
                    builder: (context, snap) {
                      final url = snap.data;
                      if (snap.connectionState == ConnectionState.waiting) {
                        return Container(
                          color: cs.primary.withOpacity(.08),
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      if (url == null) {
                        return Container(
                          color: cs.primary.withOpacity(.08),
                          child: Center(
                            child: Icon(
                              Icons.image_outlined,
                              size: 40,
                              color: cs.primary.withOpacity(.6),
                            ),
                          ),
                        );
                      }
                      return Image.network(
                        url,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, __, ___) => Container(
                          color: cs.primary.withOpacity(.08),
                          child: Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 40,
                              color: cs.primary.withOpacity(.6),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: ClipOval(
                      child: Material(
                        color: Colors.black.withOpacity(0.35),
                        child: IconButton(
                          splashRadius: 24,
                          iconSize: 22,
                          icon: Icon(isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border),
                          color: isFavorite ? Colors.redAccent : Colors.white,
                          tooltip: isFavorite
                              ? 'Retirer des favoris'
                              : 'Ajouter aux favoris',
                          onPressed: onToggleFavorite,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // --- Content -------------------------------------------------
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Prix + type
                    Row(
                      children: [
                        Text(
                          priceStr,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: cs.primary.withOpacity(.25)),
                            ),
                            child: Text(
                              type,
                              style: TextStyle(
                                fontSize: 11,
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

                    ratingsPreview,

                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.place,
                            size: 13, color: cs.onSurface.withOpacity(.7)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '$city${npa.isNotEmpty ? ' · $npa' : ''}',
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withOpacity(.8)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),

                    Row(
                      children: [
                        Icon(Icons.square_foot,
                            size: 13, color: cs.onSurface.withOpacity(.7)),
                        const SizedBox(width: 4),
                        Text(
                          surface.isNotEmpty ? '$surface m²' : '—',
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(.8)),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.meeting_room,
                            size: 13, color: cs.onSurface.withOpacity(.7)),
                        const SizedBox(width: 4),
                        Text(
                          rooms.isNotEmpty ? '$rooms rooms' : '—',
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(.8)),
                        ),
                      ],
                    ),

                    if (amenities.isNotEmpty) ...[
                      const SizedBox(height: 6),
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
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: cs.primary.withOpacity(.08),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        border: Border.all(
                                            color: cs.primary
                                                .withOpacity(.18)),
                                      ),
                                      child: Text(
                                        a,
                                        style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600),
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
  final bool favoritesOnly;
  final double? minPrice;
  final double? maxPrice;

  _Filters({
    required this.typeIndex,
    required this.sortIndex,
    required this.furnishedOnly,
    required this.wifiOnly,
    required this.chargesInclOnly,
    required this.carParkOnly,
    required this.favoritesOnly,
    this.minPrice,
    this.maxPrice,
  });
}