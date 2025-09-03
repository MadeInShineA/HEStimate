import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:moon_design/moon_design.dart';

class AdminPage extends StatefulWidget {
  @override
  _AdminPageState createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  bool _isAdmin = false;
  bool _isLoading = true;
  late TabController _tabController;

  // Dashboard data
  int _totalUsers = 0;
  int _totalListings = 0;
  int _totalBookings = 0;
  int _pendingBookings = 0;
  Map<String, int> _usersByRole = {'student': 0, 'homeowner': 0, 'admin': 0};
  Map<String, int> _listingsByType = {'room': 0, 'entire_home': 0};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkAdminRole();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkAdminRole() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser != null) {
        DocumentSnapshot userDoc = await _firestore
            .collection('users')
            .doc(currentUser.uid)
            .get();
        
        if (userDoc.exists && userDoc.data() != null) {
          Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
          setState(() {
            _isAdmin = userData['role'] == 'admin';
          });
          
          if (_isAdmin) {
            await _loadDashboardData();
          }
        }
      }
    } catch (e) {
      print('Erreur lors de la vérification du rôle admin: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDashboardData() async {
    try {
      await Future.wait([
        _loadUsersData(),
        _loadListingsData(),
        _loadBookingsData(),
      ]);
    } catch (e) {
      print('Erreur lors du chargement des données: $e');
    }
  }

  Future<void> _loadUsersData() async {
    QuerySnapshot usersSnapshot = await _firestore.collection('users').get();
    
    Map<String, int> roleCount = {'student': 0, 'homeowner': 0, 'admin': 0};
    
    for (var doc in usersSnapshot.docs) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      String role = data['role'] ?? 'student';
      roleCount[role] = (roleCount[role] ?? 0) + 1;
    }
    
    setState(() {
      _totalUsers = usersSnapshot.docs.length;
      _usersByRole = roleCount;
    });
  }

  Future<void> _loadListingsData() async {
    QuerySnapshot listingsSnapshot = await _firestore.collection('listings').get();
    
    Map<String, int> typeCount = {'room': 0, 'entire_home': 0};
    
    for (var doc in listingsSnapshot.docs) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      String type = data['type'] ?? 'room';
      typeCount[type] = (typeCount[type] ?? 0) + 1;
    }
    
    setState(() {
      _totalListings = listingsSnapshot.docs.length;
      _listingsByType = typeCount;
    });
  }

  Future<void> _loadBookingsData() async {
    QuerySnapshot bookingsSnapshot = await _firestore.collection('booking_requests').get();
    
    int pending = 0;
    for (var doc in bookingsSnapshot.docs) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      String status = data['status'] ?? '';
      if (status == 'pending') pending++;
    }
    
    setState(() {
      _totalBookings = bookingsSnapshot.docs.length;
      _pendingBookings = pending;
    });
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

    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: bg,
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Access Denied'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Container(
          decoration: bg,
          child: Center(
            child: _MoonCard(
              isDark: isDark,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 64,
                    color: Colors.red.withOpacity(0.7),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Administrator Access Required',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You don\'t have administrative privileges to access this page.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cs.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Dashboard'),
            Tab(icon: Icon(Icons.people_outline), text: 'Users'),
            Tab(icon: Icon(Icons.home_work_outlined), text: 'Listings'),
          ],
        ),
      ),
      body: Container(
        decoration: bg,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildDashboardTab(isDark),
            _buildUsersTab(isDark),
            _buildListingsTab(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTab(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        const contentMax = 1000.0;

        final horizontalPad = math.max(
          16.0,
          (constraints.maxWidth - contentMax) / 2 + 16.0,
        );

        return SingleChildScrollView(
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
                  _MoonCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.dashboard_outlined, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'Platform Overview',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Real-time statistics and metrics',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Stats grid
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: isWide ? 4 : 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    children: [
                      _buildDashboardCard(
                        'Total Users',
                        _totalUsers.toString(),
                        Icons.people_outline,
                        Colors.blue,
                        isDark,
                      ),
                      _buildDashboardCard(
                        'Active Listings',
                        _totalListings.toString(),
                        Icons.home_work_outlined,
                        Colors.green,
                        isDark,
                      ),
                      _buildDashboardCard(
                        'Total Bookings',
                        _totalBookings.toString(),
                        Icons.book_online_outlined,
                        Colors.orange,
                        isDark,
                      ),
                      _buildDashboardCard(
                        'Pending Requests',
                        _pendingBookings.toString(),
                        Icons.pending_outlined,
                        Colors.red,
                        isDark,
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // User breakdown
                  _MoonCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.pie_chart_outline, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'User Distribution',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ..._usersByRole.entries.map((entry) {
                          final percentage = _totalUsers > 0 
                              ? (entry.value / _totalUsers * 100).round()
                              : 0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Icon(
                                  _getRoleIcon(entry.key),
                                  color: _getRoleColor(entry.key),
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _getRoleName(entry.key),
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text(
                                  '${entry.value} ($percentage%)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: _getRoleColor(entry.key),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Listing breakdown
                  _MoonCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.analytics_outlined, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Listing Types',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ..._listingsByType.entries.map((entry) {
                          final percentage = _totalListings > 0 
                              ? (entry.value / _totalListings * 100).round()
                              : 0;
                          final typeName = entry.key == 'entire_home' ? 'Entire Homes' : 'Single Rooms';
                          final typeIcon = entry.key == 'entire_home' ? Icons.home : Icons.meeting_room;
                          final typeColor = entry.key == 'entire_home' ? Colors.purple : Colors.teal;
                          
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Icon(typeIcon, color: typeColor, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    typeName,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text(
                                  '${entry.value} ($percentage%)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: typeColor,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
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

  Widget _buildUsersTab(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        const contentMax = 1000.0;

        final horizontalPad = math.max(
          16.0,
          (constraints.maxWidth - contentMax) / 2 + 16.0,
        );

        return SingleChildScrollView(
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
                  _MoonCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.people_outline, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'User Management',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Manage platform users and their roles',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore.collection('users').snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _MoonCard(
                          isDark: isDark,
                          child: Center(
                            child: Text(
                              'Error loading users: ${snapshot.error}',
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _MoonCard(
                          isDark: isDark,
                          child: const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32.0),
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        );
                      }

                      List<DocumentSnapshot> users = snapshot.data!.docs;
                      
                      return Column(
                        children: users.map((user) {
                          Map<String, dynamic> userData = user.data() as Map<String, dynamic>;
                          String userId = user.id;
                          
                          // Vérifier si c'est l'admin actuellement connecté
                          bool isCurrentAdmin = userId == _auth.currentUser?.uid;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _MoonCard(
                              isDark: isDark,
                              child: Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: _getRoleColor(userData['role']).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(25),
                                      border: Border.all(
                                        color: _getRoleColor(userData['role']).withOpacity(0.3),
                                        width: isCurrentAdmin ? 2 : 1,
                                      ),
                                    ),
                                    child: Icon(
                                      _getRoleIcon(userData['role']),
                                      color: _getRoleColor(userData['role']),
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              userData['name'] ?? 'No name',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                              ),
                                            ),
                                            if (isCurrentAdmin) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.blue.withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Text(
                                                  'You',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.blue,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          userData['email'] ?? 'No email',
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _getRoleColor(userData['role']).withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                _getRoleName(userData['role']),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: _getRoleColor(userData['role']),
                                                ),
                                              ),
                                            ),
                                            if (userData['school']?.toString().isNotEmpty == true) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                '• ${userData['school']}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (userData['createdAt'] != null)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              'Joined: ${_formatDate(userData['createdAt'])}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  // N'afficher le bouton de suppression que si ce n'est pas l'admin actuellement connecté
                                  if (!isCurrentAdmin)
                                    MoonButton(
                                      onTap: () => _showDeleteDialog(userId, userData['name']),
                                      backgroundColor: Colors.red.withOpacity(0.1),
                                      leading: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                    )
                                  else
                                    // Espace vide pour maintenir l'alignement
                                    const SizedBox(width: 48),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildListingsTab(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        const contentMax = 1000.0;

        final horizontalPad = math.max(
          16.0,
          (constraints.maxWidth - contentMax) / 2 + 16.0,
        );

        return SingleChildScrollView(
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
                  _MoonCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.home_work_outlined, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'Listings Management',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Monitor and manage all property listings',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore.collection('listings').snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _MoonCard(
                          isDark: isDark,
                          child: Center(
                            child: Text(
                              'Error loading listings: ${snapshot.error}',
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _MoonCard(
                          isDark: isDark,
                          child: const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32.0),
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        );
                      }

                      List<DocumentSnapshot> listings = snapshot.data!.docs;
                      
                      return Column(
                        children: listings.map((listing) {
                          Map<String, dynamic> data = listing.data() as Map<String, dynamic>;
                          String listingId = listing.id;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _MoonCard(
                              isDark: isDark,
                              child: Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(25),
                                      border: Border.all(
                                        color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                      ),
                                    ),
                                    child: Icon(
                                      data['type'] == 'entire_home' ? Icons.home : Icons.meeting_room,
                                      color: Theme.of(context).colorScheme.primary,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          data['type'] == 'entire_home' ? 'Entire Home' : 'Single Room',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${data['address'] ?? ''}, ${data['npa'] ?? ''} ${data['city'] ?? ''}',
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            if (data['price'] != null) ...[
                                              Icon(
                                                Icons.price_change_outlined,
                                                size: 14,
                                                color: Theme.of(context).colorScheme.primary,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${(data['price'] as num).toStringAsFixed(0)} CHF/mo',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(context).colorScheme.primary,
                                                ),
                                              ),
                                            ],
                                            if (data['surface'] != null) ...[
                                              const SizedBox(width: 12),
                                              Icon(
                                                Icons.square_foot_outlined,
                                                size: 14,
                                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${(data['surface'] as num).toStringAsFixed(0)} m²',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  MoonButton(
                                    onTap: () => _showDeleteListingDialog(listingId, data['address']),
                                    backgroundColor: Colors.red.withOpacity(0.1),
                                    leading: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDashboardCard(String title, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(isDark ? .5 : 1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getRoleName(String? role) {
    switch (role) {
      case 'admin':
        return 'Administrator';
      case 'homeowner':
        return 'Homeowner';
      case 'student':
        return 'Student';
      default:
        return 'Unknown';
    }
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'admin':
        return Colors.red;
      case 'homeowner':
        return Colors.orange;
      case 'student':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getRoleIcon(String? role) {
    switch (role) {
      case 'admin':
        return Icons.admin_panel_settings_outlined;
      case 'homeowner':
        return Icons.home_outlined;
      case 'student':
        return Icons.school_outlined;
      default:
        return Icons.person_outline;
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    
    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is String) {
        date = DateTime.parse(timestamp);
      } else {
        return 'Invalid date';
      }
      
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  Future<void> _showDeleteDialog(String userId, String? userName) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete User'),
          content: Text(
            'Are you sure you want to delete the user "${userName ?? 'Unknown'}"? This action cannot be undone.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                Navigator.of(context).pop();
                await _deleteUser(userId);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDeleteListingDialog(String listingId, String? address) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Listing'),
          content: Text(
            'Are you sure you want to delete the listing at "${address ?? 'Unknown address'}"? This action cannot be undone.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                Navigator.of(context).pop();
                await _deleteListing(listingId);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteUser(String userId) async {
    // Double vérification pour éviter la suppression de l'admin actuel
    if (userId == _auth.currentUser?.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete your own admin account'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Delete user document from Firestore
      await _firestore.collection('users').doc(userId).delete();
      
      // Also delete any related booking requests
      QuerySnapshot bookings = await _firestore
          .collection('booking_requests')
          .where('studentId', isEqualTo: userId)
          .get();
      
      for (var booking in bookings.docs) {
        await booking.reference.delete();
      }
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Refresh dashboard data
      await _loadDashboardData();
    } catch (e) {
      print('Error deleting user: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting user: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteListing(String listingId) async {
    try {
      // Delete listing document from Firestore
      await _firestore.collection('listings').doc(listingId).delete();
      
      // Also delete any related booking requests
      QuerySnapshot bookings = await _firestore
          .collection('booking_requests')
          .where('listingId', isEqualTo: listingId)
          .get();
      
      for (var booking in bookings.docs) {
        await booking.reference.delete();
      }
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Listing deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Refresh dashboard data
      await _loadDashboardData();
    } catch (e) {
      print('Error deleting listing: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting listing: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// Custom Moon Card Widget
class _MoonCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  final EdgeInsets? padding;

  const _MoonCard({
    required this.child,
    required this.isDark,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark 
            ? const Color(0xFF1A1D29).withOpacity(0.8)
            : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark 
              ? Colors.white.withOpacity(0.1)
              : Colors.black.withOpacity(0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
