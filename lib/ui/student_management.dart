import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:moon_design/moon_design.dart';
import 'package:url_launcher/url_launcher.dart';

class StudentManagementPage extends StatefulWidget {
  const StudentManagementPage({super.key});

  @override
  State<StudentManagementPage> createState() => _StudentManagementPageState();
}

class _StudentManagementPageState extends State<StudentManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String currentStudentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        foregroundColor: cs.onSurface,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: cs.primary,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurface.withOpacity(0.6),
          tabs: const [
            Tab(text: 'Current', icon: Icon(Icons.home)),
            Tab(text: 'Pending', icon: Icon(Icons.pending)),
            Tab(text: 'Rate', icon: Icon(Icons.star)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          CurrentBookingsTab(studentUid: currentStudentUid),
          PendingRequestsTab(studentUid: currentStudentUid),
          RateBookingsTab(studentUid: currentStudentUid),
        ],
      ),
    );
  }
}

// Helper function to generate listing title
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

// ============================================
// ONGLET CURRENT - Appartements actuels (approuvés et pas terminés)
// ============================================
class CurrentBookingsTab extends StatefulWidget {
  final String studentUid;
  const CurrentBookingsTab({super.key, required this.studentUid});

  @override
  State<CurrentBookingsTab> createState() => _CurrentBookingsTabState();
}

class _CurrentBookingsTabState extends State<CurrentBookingsTab> with AutomaticKeepAliveClientMixin {
  late final Stream<QuerySnapshot> _bookingsStream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _bookingsStream = FirebaseFirestore.instance
        .collection('booking_requests')
        .where('studentUid', isEqualTo: widget.studentUid)
        .where('status', isEqualTo: 'approved')
        .orderBy('startDate', descending: false)
        .snapshots();
  }

  Future<Map<String, dynamic>?> _getOwnerInfo(String ownerUid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(ownerUid)
          .get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _showContactOptions(Map<String, dynamic> bookingData) async {
    final ownerInfo = await _getOwnerInfo(bookingData['ownerUid']);
    
    if (!mounted) return;
    
    return showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Contact Owner',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            if (ownerInfo?['email'] != null)
              ListTile(
                leading: const Icon(Icons.email),
                title: const Text('Send Email'),
                subtitle: Text(ownerInfo!['email']),
                onTap: () async {
                  final uri = Uri(
                    scheme: 'mailto',
                    path: ownerInfo['email'],
                    query: 'subject=Regarding my booking',
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                  if (mounted) Navigator.of(context).pop();
                },
              ),
            if (ownerInfo?['phone'] != null)
              ListTile(
                leading: const Icon(Icons.phone),
                title: const Text('Call'),
                subtitle: Text(ownerInfo?['phone']),
                onTap: () async {
                  final uri = Uri(scheme: 'tel', path: ownerInfo?['phone']);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                  if (mounted) Navigator.of(context).pop();
                },
              ),
            if (ownerInfo?['phone'] != null)
              ListTile(
                leading: const Icon(Icons.message),
                title: const Text('Send SMS'),
                subtitle: Text(ownerInfo?['phone']),
                onTap: () async {
                  final uri = Uri(scheme: 'sms', path: ownerInfo?['phone']);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                  if (mounted) Navigator.of(context).pop();
                },
              ),
            if (ownerInfo == null)
              const ListTile(
                leading: Icon(Icons.error),
                title: Text('Owner contact info not available'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    
    return StreamBuilder<QuerySnapshot>(
      stream: _bookingsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final bookings = snapshot.data?.docs ?? [];
        final now = DateTime.now();
        
        // Filtrer les réservations actuelles (pas encore terminées)
        final currentBookings = bookings.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final endDate = (data['endDate'] as Timestamp).toDate();
          return endDate.isAfter(now) || endDate.isAtSameMomentAs(now);
        }).toList();

        if (currentBookings.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.home, size: 64, color: cs.onSurface.withOpacity(0.3)),
                const SizedBox(height: 16),
                Text(
                  'No current bookings',
                  style: TextStyle(
                    fontSize: 18,
                    color: cs.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: currentBookings.length,
          itemBuilder: (context, index) {
            final doc = currentBookings[index];
            final data = doc.data() as Map<String, dynamic>;
            final startDate = (data['startDate'] as Timestamp).toDate();
            final endDate = (data['endDate'] as Timestamp).toDate();
            final daysUntilStart = startDate.difference(now).inDays;
            final daysUntilEnd = endDate.difference(now).inDays;
            final listingId = data['listingId'];

            String statusText;
            Color statusColor;

            if (daysUntilStart > 0) {
              statusText = "Starts in $daysUntilStart day${daysUntilStart > 1 ? 's' : ''}";
              statusColor = Colors.orange;
            } else if (daysUntilEnd > 0) {
              statusText = "$daysUntilEnd day${daysUntilEnd > 1 ? 's' : ''} remaining";
              statusColor = cs.primary;
            } else if (daysUntilEnd == 0) {
              statusText = "Ends today";
              statusColor = Colors.redAccent;
            } else {
              statusText = "Ended ${daysUntilEnd.abs()} day${daysUntilEnd.abs() > 1 ? 's' : ''} ago";
              statusColor = cs.onSurface.withOpacity(0.6);
            }
            
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: InkWell(
                onTap: () => _showContactOptions(data),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Listing info
                      FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('listings')
                            .doc(listingId)
                            .get(),
                        builder: (context, listingSnapshot) {
                          String listingTitle = 'Loading...';
                          if (listingSnapshot.hasData && listingSnapshot.data!.exists) {
                            final listingData = listingSnapshot.data!.data() as Map<String, dynamic>;
                            listingTitle = _generateTitle(listingData);
                          }
                          
                          return Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: cs.primary.withOpacity(0.2)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.home, size: 20, color: cs.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    listingTitle,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: cs.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.calendar_today, size: 16, color: statusColor),
                                const SizedBox(width: 8),
                                Text(
                                  '${_formatDate(startDate)} - ${_formatDate(endDate)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.schedule, size: 16, color: statusColor),
                                const SizedBox(width: 8),
                                Text(
                                  statusText,
                                  style: TextStyle(color: statusColor),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Tap to contact owner',
                              style: TextStyle(
                                color: cs.onSurface.withOpacity(0.6),
                                fontStyle: FontStyle.italic,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.contact_phone,
                            color: cs.primary,
                            size: 16,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

// ============================================
// ONGLET PENDING - Demandes en attente
// ============================================
class PendingRequestsTab extends StatefulWidget {
  final String studentUid;
  const PendingRequestsTab({super.key, required this.studentUid});

  @override
  State<PendingRequestsTab> createState() => _PendingRequestsTabState();
}

class _PendingRequestsTabState extends State<PendingRequestsTab> with AutomaticKeepAliveClientMixin {
  late final Stream<QuerySnapshot> _requestsStream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _requestsStream = FirebaseFirestore.instance
        .collection('booking_requests')
        .where('studentUid', isEqualTo: widget.studentUid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _cancelRequest(String requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Request'),
        content: const Text('Are you sure you want to cancel this booking request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          MoonFilledButton(
            backgroundColor: Colors.red,
            onTap: () => Navigator.of(context).pop(true),
            label: const Text('Yes, Cancel', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('booking_requests')
            .doc(requestId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Booking request cancelled'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    
    return StreamBuilder<QuerySnapshot>(
      stream: _requestsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final requests = snapshot.data?.docs ?? [];

        if (requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.pending, size: 64, color: cs.onSurface.withOpacity(0.3)),
                const SizedBox(height: 16),
                Text(
                  'No pending requests',
                  style: TextStyle(
                    fontSize: 18,
                    color: cs.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final doc = requests[index];
            final data = doc.data() as Map<String, dynamic>;
            final listingId = data['listingId'];
            final startDate = (data['startDate'] as Timestamp).toDate();
            final endDate = (data['endDate'] as Timestamp).toDate();
            final createdAt = (data['createdAt'] as Timestamp).toDate();
            
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Listing info
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('listings')
                          .doc(listingId)
                          .get(),
                      builder: (context, listingSnapshot) {
                        String listingTitle = 'Loading...';
                        if (listingSnapshot.hasData && listingSnapshot.data!.exists) {
                          final listingData = listingSnapshot.data!.data() as Map<String, dynamic>;
                          listingTitle = _generateTitle(listingData);
                        }
                        
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: cs.primary.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.home, size: 20, color: cs.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  listingTitle,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.calendar_today, size: 16, color: Colors.orange),
                              const SizedBox(width: 8),
                              Text(
                                '${_formatDate(startDate)} - ${_formatDate(endDate)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.pending, size: 16, color: Colors.orange),
                              const SizedBox(width: 8),
                              Text(
                                'Sent ${_formatDate(createdAt)}',
                                style: const TextStyle(color: Colors.orange),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your message:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data['message'] ?? 'No message',
                      style: TextStyle(color: cs.onSurface.withOpacity(0.8)),
                    ),
                    const SizedBox(height: 16),
                    MoonFilledButton(
                      isFullWidth: true,
                      backgroundColor: Colors.red,
                      onTap: () => _cancelRequest(doc.id),
                      leading: const Icon(Icons.cancel, color: Colors.white),
                      label: const Text('Cancel Request', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

// ============================================
// ONGLET RATE - Évaluer les appartements passés
// ============================================
class RateBookingsTab extends StatefulWidget {
  final String studentUid;
  const RateBookingsTab({super.key, required this.studentUid});

  @override
  State<RateBookingsTab> createState() => _RateBookingsTabState();
}

class _RateBookingsTabState extends State<RateBookingsTab> with AutomaticKeepAliveClientMixin {
  late final Stream<QuerySnapshot> _bookingsStream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _bookingsStream = FirebaseFirestore.instance
        .collection('booking_requests')
        .where('studentUid', isEqualTo: widget.studentUid)
        .where('status', isEqualTo: 'approved')
        .orderBy('endDate', descending: true)
        .snapshots();
  }

  Future<void> _showRatingDialog(Map<String, dynamic> bookingData, String bookingId) async {
    final TextEditingController reviewController = TextEditingController();
    int rating = 5;
    bool wasClean = true;
    bool ownerWasHelpful = true;

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Rate this Property'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Was the property clean?'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Radio<bool>(
                      value: true,
                      groupValue: wasClean,
                      onChanged: (value) => setState(() => wasClean = value!),
                    ),
                    const Text('Yes'),
                    Radio<bool>(
                      value: false,
                      groupValue: wasClean,
                      onChanged: (value) => setState(() => wasClean = value!),
                    ),
                    const Text('No'),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Was the owner helpful?'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Radio<bool>(
                      value: true,
                      groupValue: ownerWasHelpful,
                      onChanged: (value) => setState(() => ownerWasHelpful = value!),
                    ),
                    const Text('Yes'),
                    Radio<bool>(
                      value: false,
                      groupValue: ownerWasHelpful,
                      onChanged: (value) => setState(() => ownerWasHelpful = value!),
                    ),
                    const Text('No'),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Overall rating (1-5 stars):'),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(5, (index) {
                    return IconButton(
                      onPressed: () => setState(() => rating = index + 1),
                      icon: Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reviewController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Additional comments (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            MoonFilledButton(
              onTap: () async {
                try {
                  await FirebaseFirestore.instance.collection('listing_reviews').add({
                    'bookingId': bookingId,
                    'listingId': bookingData['listingId'],
                    'ownerUid': bookingData['ownerUid'],
                    'studentUid': widget.studentUid,
                    'studentName': bookingData['studentName'],
                    'rating': rating,
                    'wasClean': wasClean,
                    'ownerWasHelpful': ownerWasHelpful,
                    'comment': reviewController.text.trim(),
                    'createdAt': Timestamp.now(),
                  });

                  // Marquer la réservation comme évaluée
                  await FirebaseFirestore.instance
                      .collection('booking_requests')
                      .doc(bookingId)
                      .update({'studentReviewed': true});

                  if (mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Review submitted successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              label: const Text('Submit Review'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    
    return StreamBuilder<QuerySnapshot>(
      stream: _bookingsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final bookings = snapshot.data?.docs ?? [];
        final now = DateTime.now();
        
        // Filtrer les réservations terminées
        final completedBookings = bookings.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final endDate = (data['endDate'] as Timestamp).toDate();
          return endDate.isBefore(now);
        }).toList();

        if (completedBookings.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.star, size: 64, color: cs.onSurface.withOpacity(0.3)),
                const SizedBox(height: 16),
                Text(
                  'No completed bookings to rate',
                  style: TextStyle(
                    fontSize: 18,
                    color: cs.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: completedBookings.length,
          itemBuilder: (context, index) {
            final doc = completedBookings[index];
            final data = doc.data() as Map<String, dynamic>;
            final hasReview = data['studentReviewed'] == true;
            final listingId = data['listingId'];
            
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Listing info
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('listings')
                          .doc(listingId)
                          .get(),
                      builder: (context, listingSnapshot) {
                        String listingTitle = 'Loading...';
                        if (listingSnapshot.hasData && listingSnapshot.data!.exists) {
                          final listingData = listingSnapshot.data!.data() as Map<String, dynamic>;
                          listingTitle = _generateTitle(listingData);
                        }
                        
                        return Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: cs.primary.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.home, size: 20, color: cs.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  listingTitle,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_formatDate((data['startDate'] as Timestamp).toDate())} - ${_formatDate((data['endDate'] as Timestamp).toDate())}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Booking completed',
                                style: TextStyle(
                                  color: cs.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (hasReview)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check, size: 16, color: Colors.green),
                                SizedBox(width: 4),
                                Text('Rated', style: TextStyle(color: Colors.green)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!hasReview)
                      MoonFilledButton(
                        isFullWidth: true,
                        onTap: () => _showRatingDialog(data, doc.id),
                        leading: const Icon(Icons.star),
                        label: const Text('Rate Property'),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}