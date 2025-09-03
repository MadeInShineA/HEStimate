import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:moon_design/moon_design.dart';
import 'package:url_launcher/url_launcher.dart';
import 'rate_student_page.dart';

class OwnerManagementPage extends StatefulWidget {
  const OwnerManagementPage({super.key});

  @override
  State<OwnerManagementPage> createState() => _OwnerManagementPageState();
}

class _OwnerManagementPageState extends State<OwnerManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String currentOwnerUid = FirebaseAuth.instance.currentUser?.uid ?? '';

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
        title: const Text('Owner Management'),
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        foregroundColor: cs.onSurface,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: cs.primary,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurface.withOpacity(0.6),
          tabs: const [
            Tab(text: 'Requests', icon: Icon(Icons.pending_actions)),
            Tab(text: 'Reviews', icon: Icon(Icons.rate_review)),
            Tab(text: 'Students', icon: Icon(Icons.people)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          RequestsTab(ownerUid: currentOwnerUid),
          ReviewsTab(ownerUid: currentOwnerUid),
          StudentsTab(ownerUid: currentOwnerUid),
        ],
      ),
    );
  }
}

// Helper function to generate listing title (same as in ListingsPage)
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

Widget _starsRow(BuildContext context, double avg, int count, {bool isClickable = false}) {
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
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count == 0 ? 'No ratings' : '${avg.toStringAsFixed(1)} ($count)',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withOpacity(.8),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isClickable && count > 0) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_forward_ios,
              size: 10,
              color: cs.onSurface.withOpacity(.6),
            ),
          ],
        ],
      ),
    ],
  );
}

class StudentRatingPreview extends StatelessWidget {
  final String? studentUid;
  final String? studentName;
  const StudentRatingPreview({
    super.key, 
    required this.studentUid,
    this.studentName,
  });

  @override
  Widget build(BuildContext context) {
    if (studentUid == null || studentUid!.isEmpty) {
      return _starsRow(context, 0, 0, isClickable: false);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('reviews')
          .where('studentUid', isEqualTo: studentUid)
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
              (acc, d) => acc + ((d.data()['rating'] as num?)?.toDouble() ?? 0.0),
            );
            avg = sum / count;
          }
        }
        return Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: InkWell(
            onTap: count > 0 ? () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => StudentReviewsPage(
                    studentUid: studentUid!,
                    studentName: studentName ?? 'Unknown Student',
                  ),
                ),
              );
            } : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: _starsRow(context, avg, count, isClickable: count > 0),
            ),
          ),
        );
      },
    );
  }
}

// ============================================
// ONGLET REQUESTS - Gestion des demandes de réservation
// ============================================
class RequestsTab extends StatefulWidget {
  final String ownerUid;
  const RequestsTab({super.key, required this.ownerUid});

  @override
  State<RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<RequestsTab> with AutomaticKeepAliveClientMixin {
  late final Stream<QuerySnapshot> _requestsStream;

  @override
  bool get wantKeepAlive => true; // garde l'état du tab

  @override
  void initState() {
    super.initState();
    _requestsStream = FirebaseFirestore.instance
        .collection('booking_requests')
        .where('ownerUid', isEqualTo: widget.ownerUid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<List<Map<String, dynamic>>> _checkPendingConflicts(String listingId, DateTime startDate, DateTime endDate, String currentBookingId) async {
    try {
      // Get ALL other pending bookings for the same listing (excluding the current one being approved)
      final otherPendingBookings = await FirebaseFirestore.instance
          .collection('booking_requests')
          .where('listingId', isEqualTo: listingId)
          .where('status', isEqualTo: 'pending')
          .get();

      List<Map<String, dynamic>> conflicts = [];

      for (final doc in otherPendingBookings.docs) {
        // Skip the current booking we're trying to approve
        if (doc.id == currentBookingId) continue;

        final data = doc.data();
        final existingStart = (data['startDate'] as Timestamp).toDate();
        final existingEnd = (data['endDate'] as Timestamp).toDate();

        // Check if dates overlap (any overlap means conflict)
        if (!(endDate.isBefore(existingStart) || startDate.isAfter(existingEnd))) {
          conflicts.add({
            'id': doc.id,
            'studentName': data['studentName'],
            'startDate': existingStart,
            'endDate': existingEnd,
          });
        }
      }

      return conflicts;
    } catch (e) {
      print('Error checking pending conflicts: $e');
      return [];
    }
  }

  Future<void> _showConflictDialog(String bookingId, List<Map<String, dynamic>> conflicts) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            const SizedBox(width: 8),
            const Text('Date Conflict Warning'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Accepting this booking will conflict with other pending requests:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...conflicts.map((conflict) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conflict['studentName'] ?? 'Unknown Student',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${_formatDate(conflict['startDate'])} - ${_formatDate(conflict['endDate'])}',
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            )).toList(),
            const SizedBox(height: 12),
            const Text(
              'These pending requests will be automatically rejected if you proceed.',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          MoonFilledButton(
            backgroundColor: Colors.orange,
            onTap: () async {
              Navigator.of(context).pop();
              await _approveBookingWithConflicts(bookingId, conflicts);
            },
            label: const Text('Approve Anyway', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _approveBookingWithConflicts(String bookingId, List<Map<String, dynamic>> conflicts) async {
    try {
      // First, reject all conflicting bookings
      for (final conflict in conflicts) {
        await FirebaseFirestore.instance
            .collection('booking_requests')
            .doc(conflict['id'])
            .update({
          'status': 'rejected',
          'updatedAt': Timestamp.now(),
          'rejectionReason': 'Date conflict with approved booking',
        });
      }

      // Then approve the selected booking
      await FirebaseFirestore.instance
          .collection('booking_requests')
          .doc(bookingId)
          .update({
        'status': 'approved',
        'updatedAt': Timestamp.now(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              conflicts.isEmpty 
                  ? 'Booking approved'
                  : 'Booking approved and ${conflicts.length} conflicting booking${conflicts.length > 1 ? 's' : ''} rejected'
            ),
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
  }

  Future<void> _updateBookingStatus(String bookingId, String listingId, String status, DateTime? startDate, DateTime? endDate) async {
    try {
      if (status == 'approved' && startDate != null && endDate != null) {
        // Check for conflicts with other pending requests before approving
        final conflicts = await _checkPendingConflicts(listingId, startDate, endDate, bookingId);
        
        if (conflicts.isNotEmpty) {
          _showConflictDialog(bookingId, conflicts);
          return;
        }
      }

      await FirebaseFirestore.instance
          .collection('booking_requests')
          .doc(bookingId)
          .update({
        'status': status,
        'updatedAt': Timestamp.now(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Booking ${status == 'approved' ? 'approved' : 'rejected'}'),
            backgroundColor: status == 'approved' ? Colors.green : Colors.red,
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

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
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
                Icon(Icons.inbox, size: 64, color: cs.onSurface.withOpacity(0.3)),
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
                    Row(
                      children: [
                        CircleAvatar(
                          child: Text(data['studentName']?[0]?.toUpperCase() ?? 'S'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['studentName'] ?? 'Unknown Student',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                data['studentEmail'] ?? '',
                                style: TextStyle(
                                  color: cs.onSurface.withOpacity(0.6),
                                ),
                              ),
                              StudentRatingPreview(
                                studentUid: data['studentUid'],
                                studentName: data['studentName'],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.calendar_today, size: 16, color: cs.primary),
                              const SizedBox(width: 8),
                              Text(
                                '${_formatDate(startDate)} - ${_formatDate(endDate)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: cs.primary,
                                ),
                              ),
                            ],
                          ),
                          if (data['studentPhone'] != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.phone, size: 16, color: cs.primary),
                                const SizedBox(width: 8),
                                Text(data['studentPhone']),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Message:',
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
                    Row(
                      children: [
                        Expanded(
                          child: MoonFilledButton(
                            backgroundColor: Colors.green,
                            onTap: () => _updateBookingStatus(
                              doc.id, 
                              listingId, 
                              'approved', 
                              startDate, 
                              endDate
                            ),
                            leading: const Icon(Icons.check, color: Colors.white),
                            label: const Text('Approve', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MoonFilledButton(
                            backgroundColor: Colors.red,
                            onTap: () => _updateBookingStatus(doc.id, listingId, 'rejected', null, null),
                            leading: const Icon(Icons.close, color: Colors.white),
                            label: const Text('Reject', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
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
// ONGLET REVIEWS - Évaluer les anciens étudiants
// ============================================
class ReviewsTab extends StatefulWidget {
  final String ownerUid;
  const ReviewsTab({super.key, required this.ownerUid});

  @override
  State<ReviewsTab> createState() => _ReviewsTabState();
}

class _ReviewsTabState extends State<ReviewsTab> with AutomaticKeepAliveClientMixin {
  late final Stream<QuerySnapshot> _requestsStream;

  @override
  bool get wantKeepAlive => true; // garde l'état du tab

  @override
  void initState() {
    super.initState();
    _requestsStream = FirebaseFirestore.instance
        .collection('booking_requests')
        .where('ownerUid', isEqualTo: widget.ownerUid)
        .where('status', isEqualTo: 'approved')
        .orderBy('endDate', descending: true)
        .snapshots();
  }

  Future<void> _showReviewDialog(Map<String, dynamic> bookingData, String bookingId) async {
    final TextEditingController reviewController = TextEditingController();
    int rating = 5;
    bool wasRespectful = true;

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Review ${bookingData['studentName']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Was the student respectful?'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Radio<bool>(
                      value: true,
                      groupValue: wasRespectful,
                      onChanged: (value) => setState(() => wasRespectful = value!),
                    ),
                    const Text('Yes'),
                    Radio<bool>(
                      value: false,
                      groupValue: wasRespectful,
                      onChanged: (value) => setState(() => wasRespectful = value!),
                    ),
                    const Text('No'),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Rating (1-5 stars):'),
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
                  await FirebaseFirestore.instance.collection('reviews').add({
                    'bookingId': bookingId,
                    'ownerUid': widget.ownerUid,
                    'studentUid': bookingData['studentUid'],
                    'studentName': bookingData['studentName'],
                    'rating': rating,
                    'wasRespectful': wasRespectful,
                    'comment': reviewController.text.trim(),
                    'createdAt': Timestamp.now(),
                  });

                  // Marquer la réservation comme évaluée
                  await FirebaseFirestore.instance
                      .collection('booking_requests')
                      .doc(bookingId)
                      .update({'reviewed': true});

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
    super.build(context); // AutomaticKeepAliveClientMixin
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
                Icon(Icons.rate_review, size: 64, color: cs.onSurface.withOpacity(0.3)),
                const SizedBox(height: 16),
                Text(
                  'No completed bookings to review',
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
            final hasReview = data['reviewed'] == true;
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
                        CircleAvatar(
                          child: Text(data['studentName']?[0]?.toUpperCase() ?? 'S'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['studentName'] ?? 'Unknown Student',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${_formatDate((data['startDate'] as Timestamp).toDate())} - ${_formatDate((data['endDate'] as Timestamp).toDate())}',
                                style: TextStyle(
                                  color: cs.onSurface.withOpacity(0.6),
                                ),
                              ),
                              StudentRatingPreview(
                                studentUid: data['studentUid'],
                                studentName: data['studentName'],
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
                                Text('Reviewed', style: TextStyle(color: Colors.green)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!hasReview)
                      MoonFilledButton(
                        isFullWidth: true,
                        onTap: () => _showReviewDialog(data, doc.id),
                        leading: const Icon(Icons.rate_review),
                        label: const Text('Write Review'),
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
// ONGLET STUDENTS - Étudiants actuellement en séjour
// ============================================
class StudentsTab extends StatefulWidget {
  final String ownerUid;
  const StudentsTab({super.key, required this.ownerUid});

  @override
  State<StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<StudentsTab> with AutomaticKeepAliveClientMixin {
  late final Stream<QuerySnapshot> _requestsStream;

  @override
  bool get wantKeepAlive => true; // garde l'état du tab

  @override
  void initState() {
    super.initState();
    _requestsStream = FirebaseFirestore.instance
          .collection('booking_requests')
          .where('ownerUid', isEqualTo: widget.ownerUid)
          .where('status', isEqualTo: 'approved')
          .snapshots();
  }

  Future<void> _showContactOptions(Map<String, dynamic> studentData) async {
    return showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Contact ${studentData['studentName']}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            if (studentData['studentEmail'] != null)
              ListTile(
                leading: const Icon(Icons.email),
                title: const Text('Send Email'),
                subtitle: Text(studentData['studentEmail']),
                onTap: () async {
                  final uri = Uri(
                    scheme: 'mailto',
                    path: studentData['studentEmail'],
                    query: 'subject=Regarding your stay',
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                  if (mounted) Navigator.of(context).pop();
                },
              ),
            if (studentData['studentPhone'] != null)
              ListTile(
                leading: const Icon(Icons.phone),
                title: const Text('Call'),
                subtitle: Text(studentData['studentPhone']),
                onTap: () async {
                  final uri = Uri(scheme: 'tel', path: studentData['studentPhone']);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                  if (mounted) Navigator.of(context).pop();
                },
              ),
            if (studentData['studentPhone'] != null)
              ListTile(
                leading: const Icon(Icons.message),
                title: const Text('Send SMS'),
                subtitle: Text(studentData['studentPhone']),
                onTap: () async {
                  final uri = Uri(scheme: 'sms', path: studentData['studentPhone']);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                  if (mounted) Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
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

        final bookings = snapshot.data?.docs ?? [];
        final now = DateTime.now();
        
        // Filtrer les réservations actuelles (en cours)
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
                Icon(Icons.people, size: 64, color: cs.onSurface.withOpacity(0.3)),
                const SizedBox(height: 16),
                Text(
                  'No students currently staying',
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
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: cs.primary,
                            child: Text(
                              data['studentName']?[0]?.toUpperCase() ?? 'S',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['studentName'] ?? 'Unknown Student',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  data['studentEmail'] ?? '',
                                  style: TextStyle(
                                    color: cs.onSurface.withOpacity(0.6),
                                  ),
                                ),
                                StudentRatingPreview(
                                  studentUid: data['studentUid'],
                                  studentName: data['studentName'],
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.contact_phone,
                            color: cs.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
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
                      Text(
                        'Tap to contact',
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(0.6),
                          fontStyle: FontStyle.italic,
                          fontSize: 12,
                        ),
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