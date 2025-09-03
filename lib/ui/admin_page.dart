import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:moon_design/moon_design.dart';
import 'package:fl_chart/fl_chart.dart';

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

  // Analytics data
  List<FlSpot> _dailyListingsData = [];
  List<FlSpot> _dailyBookingsData = [];
  List<String> _chartDates = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); // Changé à 3 onglets
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
            await _loadAnalyticsData();
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

  Future<void> _loadAnalyticsData() async {
    try {
      await Future.wait([
        _loadDailyListingsData(),
        _loadDailyBookingsData(),
      ]);
    } catch (e) {
      print('Erreur lors du chargement des données analytiques: $e');
    }
  }

  Future<void> _loadDailyListingsData() async {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    
    QuerySnapshot snapshot = await _firestore
        .collection('listings')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
        .orderBy('createdAt')
        .get();

    Map<String, int> dailyCounts = {};
    List<String> dates = [];
    
    // Initialize all dates with 0
    for (int i = 0; i < 30; i++) {
      final date = thirtyDaysAgo.add(Duration(days: i));
      final dateKey = '${date.day}/${date.month}';
      dailyCounts[dateKey] = 0;
      dates.add(dateKey);
    }

    // Count actual listings
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['createdAt'] != null) {
        final createdAt = (data['createdAt'] as Timestamp).toDate();
        final dateKey = '${createdAt.day}/${createdAt.month}';
        if (dailyCounts.containsKey(dateKey)) {
          dailyCounts[dateKey] = dailyCounts[dateKey]! + 1;
        }
      }
    }

    setState(() {
      _dailyListingsData = dailyCounts.entries
          .toList()
          .asMap()
          .entries
          .map((entry) => FlSpot(entry.key.toDouble(), entry.value.value.toDouble()))
          .toList();
      _chartDates = dates;
    });
  }

  Future<void> _loadDailyBookingsData() async {
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    
    QuerySnapshot snapshot = await _firestore
        .collection('booking_requests')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
        .orderBy('createdAt')
        .get();

    Map<String, int> dailyCounts = {};
    
    // Initialize all dates with 0
    for (int i = 0; i < 30; i++) {
      final date = thirtyDaysAgo.add(Duration(days: i));
      final dateKey = '${date.day}/${date.month}';
      dailyCounts[dateKey] = 0;
    }

    // Count actual bookings
    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['createdAt'] != null) {
        final createdAt = (data['createdAt'] as Timestamp).toDate();
        final dateKey = '${createdAt.day}/${createdAt.month}';
        if (dailyCounts.containsKey(dateKey)) {
          dailyCounts[dateKey] = dailyCounts[dateKey]! + 1;
        }
      }
    }

    setState(() {
      _dailyBookingsData = dailyCounts.entries
          .toList()
          .asMap()
          .entries
          .map((entry) => FlSpot(entry.key.toDouble(), entry.value.value.toDouble()))
          .toList();
    });
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
            Tab(icon: Icon(Icons.people_outlined), text: 'Users'),
            Tab(icon: Icon(Icons.analytics_outlined), text: 'Analytics'),
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
            _buildAnalyticsTab(isDark),
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
                            const Icon(Icons.people_outlined, size: 24),
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
                          'Manage all platform users and their roles',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Users list
                  _MoonCard(
                    isDark: isDark,
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _firestore
                          .collection('users')
                          .orderBy('createdAt', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_outline, size: 64, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  'No users found',
                                  style: TextStyle(fontSize: 18, color: Colors.grey),
                                ),
                              ],
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'All Users (${snapshot.data!.docs.length})',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ...snapshot.data!.docs.map((user) {
                              Map<String, dynamic> userData = user.data() as Map<String, dynamic>;
                              String userId = user.id;
                              bool isCurrentAdmin = userId == _auth.currentUser?.uid;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: _getRoleColor(userData['role']).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(25),
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
                                                    borderRadius: BorderRadius.circular(6),
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
                                              fontSize: 14,
                                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: _getRoleColor(userData['role']).withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  _getRoleName(userData['role']),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: _getRoleColor(userData['role']),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Created: ${_formatDate(userData['createdAt'])}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!isCurrentAdmin) ...[
                                      IconButton(
                                        onPressed: () => _showDeleteDialog(userId, userData['name']),
                                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                                        tooltip: 'Delete user',
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        );
                      },
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

  Widget _buildAnalyticsTab(bool isDark) {
    double maxYListings = _dailyListingsData.isEmpty ? 1 : _dailyListingsData.map((spot) => spot.y).reduce(math.max);
    double intervalListings = (maxYListings / 5).ceilToDouble().clamp(1, double.infinity);

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
                            const Icon(Icons.analytics_outlined, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'Analytics Dashboard',
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
                          'Daily trends and insights over the last 30 days',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // New Listings Chart
                  _MoonCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.home_work_outlined, size: 20, color: Colors.green),
                            const SizedBox(width: 8),
                            Text(
                              'New Listings per Day',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 200,
                          child: _dailyListingsData.isEmpty 
                              ? const Center(child: CircularProgressIndicator())
                              : LineChart(
                                  LineChartData(
                                    gridData: FlGridData(
                                      show: true,
                                      drawVerticalLine: false,
                                      horizontalInterval: 1,
                                      getDrawingHorizontalLine: (value) {
                                        return FlLine(
                                          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                                          strokeWidth: 1,
                                        );
                                      },
                                    ),
                                    titlesData: FlTitlesData(
                                      show: true,
                                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 30,
                                          interval: 5,
                                          getTitlesWidget: (value, meta) {
                                            final index = value.toInt();
                                            if (index >= 0 && index < _chartDates.length) {
                                              return SideTitleWidget(
                                                axisSide: meta.axisSide,
                                                child: Text(
                                                  _chartDates[index],
                                                  style: TextStyle(
                                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              );
                                            }
                                            return const Text('');
                                          },
                                        ),
                                      ),
                                      leftTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          interval: intervalListings,
                                          getTitlesWidget: (value, meta) {
                                            return Text(
                                              value.toInt().toString(),
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                                fontSize: 10,
                                              ),
                                            );
                                          },
                                          reservedSize: 32,
                                        ),
                                      ),
                                    ),
                                    borderData: FlBorderData(show: false),
                                    minX: 0,
                                    maxX: (_dailyListingsData.length - 1).toDouble(),
                                    minY: 0,
                                    maxY: _dailyListingsData.map((spot) => spot.y).reduce(math.max) + 1,
                                    lineBarsData: [
                                      LineChartBarData(
                                        spots: _dailyListingsData,
                                        gradient: LinearGradient(
                                          colors: [Colors.green.withOpacity(0.8), Colors.green],
                                        ),
                                        barWidth: 3,
                                        isStrokeCapRound: true,
                                        dotData: FlDotData(
                                          show: true,
                                          getDotPainter: (spot, percent, barData, index) {
                                            return FlDotCirclePainter(
                                              radius: 4,
                                              color: Colors.green,
                                              strokeWidth: 2,
                                              strokeColor: Colors.white,
                                            );
                                          },
                                        ),
                                        belowBarData: BarAreaData(
                                          show: true,
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.green.withOpacity(0.3),
                                              Colors.green.withOpacity(0.1),
                                            ],
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // New Bookings Chart
                  _MoonCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.book_online_outlined, size: 20, color: Colors.orange),
                            const SizedBox(width: 8),
                            Text(
                              'New Bookings per Day',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 200,
                          child: _dailyBookingsData.isEmpty 
                              ? const Center(child: CircularProgressIndicator())
                              : LineChart(
                                  LineChartData(
                                    gridData: FlGridData(
                                      show: true,
                                      drawVerticalLine: false,
                                      horizontalInterval: 1,
                                      getDrawingHorizontalLine: (value) {
                                        return FlLine(
                                          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                                          strokeWidth: 1,
                                        );
                                      },
                                    ),
                                    titlesData: FlTitlesData(
                                      show: true,
                                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 30,
                                          interval: 5,
                                          getTitlesWidget: (value, meta) {
                                            final index = value.toInt();
                                            if (index >= 0 && index < _chartDates.length) {
                                              return SideTitleWidget(
                                                axisSide: meta.axisSide,
                                                child: Text(
                                                  _chartDates[index],
                                                  style: TextStyle(
                                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              );
                                            }
                                            return const Text('');
                                          },
                                        ),
                                      ),
                                      leftTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          interval: intervalListings,
                                          getTitlesWidget: (value, meta) {
                                            return Text(
                                              value.toInt().toString(),
                                              style: TextStyle(
                                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                                fontSize: 10,
                                              ),
                                            );
                                          },
                                          reservedSize: 32,
                                        ),
                                      ),
                                    ),
                                    borderData: FlBorderData(show: false),
                                    minX: 0,
                                    maxX: (_dailyBookingsData.length - 1).toDouble(),
                                    minY: 0,
                                    maxY: _dailyBookingsData.map((spot) => spot.y).reduce(math.max) + 1,
                                    lineBarsData: [
                                      LineChartBarData(
                                        spots: _dailyBookingsData,
                                        gradient: LinearGradient(
                                          colors: [Colors.orange.withOpacity(0.8), Colors.orange],
                                        ),
                                        barWidth: 3,
                                        isStrokeCapRound: true,
                                        dotData: FlDotData(
                                          show: true,
                                          getDotPainter: (spot, percent, barData, index) {
                                            return FlDotCirclePainter(
                                              radius: 4,
                                              color: Colors.orange,
                                              strokeWidth: 2,
                                              strokeColor: Colors.white,
                                            );
                                          },
                                        ),
                                        belowBarData: BarAreaData(
                                          show: true,
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.orange.withOpacity(0.3),
                                              Colors.orange.withOpacity(0.1),
                                            ],
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                          ),
                                        ),
                                      ),
                                    ],
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
