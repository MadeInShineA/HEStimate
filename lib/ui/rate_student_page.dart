import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:moon_design/moon_design.dart';

class StudentReviewsPage extends StatefulWidget {
  final String studentUid;
  final String studentName;

  const StudentReviewsPage({
    super.key,
    required this.studentUid,
    required this.studentName,
  });

  @override
  State<StudentReviewsPage> createState() => _StudentReviewsPageState();
}

class _StudentReviewsPageState extends State<StudentReviewsPage> {
  Stream<QuerySnapshot<Map<String, dynamic>>> _reviewsStream() {
    return FirebaseFirestore.instance
        .collection('reviews')
        .where('studentUid', isEqualTo: widget.studentUid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Widget _starsRow(int value, {double size = 26}) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < value;
        final icon = filled ? Icons.star_rounded : Icons.star_border_rounded;
        final color = filled ? cs.primary : cs.onSurface.withOpacity(.35);
        return Icon(icon, size: size, color: color);
      }),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<String> _getListingTitle(String? bookingId) async {
    if (bookingId == null || bookingId.isEmpty) return 'Unknown property';
    
    try {
      // Get booking details to find the listing
      final bookingDoc = await FirebaseFirestore.instance
          .collection('booking_requests')
          .doc(bookingId)
          .get();
      
      if (!bookingDoc.exists) return 'Unknown property';
      
      final listingId = bookingDoc.data()?['listingId'];
      if (listingId == null) return 'Unknown property';
      
      // Get listing details
      final listingDoc = await FirebaseFirestore.instance
          .collection('listings')
          .doc(listingId)
          .get();
      
      if (!listingDoc.exists) return 'Unknown property';
      
      final data = listingDoc.data()!;
      return _generateListingTitle(data);
    } catch (e) {
      return 'Unknown property';
    }
  }

  String _generateListingTitle(Map<String, dynamic> data) {
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
        title: Text('${widget.studentName}\'s Reviews'),
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        foregroundColor: cs.onSurface,
        elevation: 0,
      ),
      body: Container(
        decoration: bg,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _reviewsStream(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snap.hasError) {
              return Center(
                child: Text('Error loading reviews: ${snap.error}'),
              );
            }

            final docs = snap.data?.docs ?? [];
            final count = docs.length;
            final avg = count == 0
                ? 0.0
                : docs
                        .map((d) => (d.data()['rating'] as num?)?.toDouble() ?? 0.0)
                        .fold<double>(0.0, (a, b) => a + b) /
                    count;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Student info and summary
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withOpacity(.96),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.primary.withOpacity(.12)),
                  ),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: cs.primary,
                        child: Text(
                          widget.studentName[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.studentName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _starsRow(avg.round(), size: 24),
                          const SizedBox(width: 12),
                          Text(
                            count == 0
                                ? 'No reviews yet'
                                : '${avg.toStringAsFixed(1)} / 5 · $count review${count > 1 ? 's' : ''}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Reviews list
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withOpacity(.96),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.primary.withOpacity(.12)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reviews from Owners',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      docs.isEmpty
                          ? Text(
                              'No reviews yet.',
                              style: TextStyle(color: cs.onSurface.withOpacity(.7)),
                            )
                          : Column(
                              children: docs.map((d) {
                                final data = d.data();
                                final rating = (data['rating'] as num?)?.toInt() ?? 0;
                                final comment = (data['comment'] ?? '').toString();
                                final wasRespectful = data['wasRespectful'] ?? true;
                                final bookingId = data['bookingId']?.toString();
                                final ts = data['createdAt'] as Timestamp?;
                                final dateStr = ts == null
                                    ? ''
                                    : _formatDate(ts.toDate());

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: cs.primary.withOpacity(.10)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Rating and date
                                      Row(
                                        children: [
                                          _starsRow(rating, size: 18),
                                          const Spacer(),
                                          Text(
                                            dateStr,
                                            style: TextStyle(
                                              color: cs.onSurface.withOpacity(.6),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),

                                      // Property info (if available)
                                      FutureBuilder<String>(
                                        future: _getListingTitle(bookingId),
                                        builder: (context, snapshot) {
                                          final title = snapshot.data ?? 'Loading...';
                                          if (title == 'Unknown property') {
                                            return const SizedBox.shrink();
                                          }
                                          return Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            margin: const EdgeInsets.only(bottom: 8),
                                            decoration: BoxDecoration(
                                              color: cs.primary.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.home, size: 12, color: cs.primary),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    title,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: cs.primary,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),

                                      // Respectful indicator
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: wasRespectful 
                                              ? Colors.green.withOpacity(0.1) 
                                              : Colors.red.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              wasRespectful ? Icons.check : Icons.close,
                                              size: 12,
                                              color: wasRespectful ? Colors.green : Colors.red,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              wasRespectful ? 'Respectful' : 'Not respectful',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: wasRespectful ? Colors.green : Colors.red,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Comment
                                      if (comment.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          comment,
                                          style: TextStyle(color: cs.onSurface),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}