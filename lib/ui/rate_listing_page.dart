import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:moon_design/moon_design.dart';

class RateListingPage extends StatefulWidget {
  final String listingId;
  final bool allowAdd;

  const RateListingPage({
    super.key,
    required this.listingId,
    this.allowAdd = true,
  });

  @override
  State<RateListingPage> createState() => _RateListingPageState();
}

class _RateListingPageState extends State<RateListingPage> {
  int _rating = 0;
  final _commentCtrl = TextEditingController();
  bool _wasClean = true;
  bool _ownerWasHelpful = true;
  bool _saving = false;
  String? _err;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMyExistingReviewIfAny() async {
    if (!widget.allowAdd) return; 
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Chercher une review existante de cet utilisateur pour ce listing
    final query = await FirebaseFirestore.instance
        .collection('listing_reviews')
        .where('listingId', isEqualTo: widget.listingId)
        .where('studentUid', isEqualTo: user.uid)
        .get();

    if (query.docs.isNotEmpty) {
      final data = query.docs.first.data();
      setState(() {
        _rating = (data['rating'] as num?)?.toInt() ?? 0;
        _commentCtrl.text = (data['comment'] ?? '').toString();
        _wasClean = data['wasClean'] ?? true;
        _ownerWasHelpful = data['ownerWasHelpful'] ?? true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMyExistingReviewIfAny();
  }

  Future<void> _submit() async {
    if (!widget.allowAdd) return;
    if (_rating < 1 || _rating > 5) {
      setState(() => _err = 'Please select a rating (1–5 stars).');
      return;
    }
    setState(() {
      _saving = true;
      _err = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('You must be signed in to rate.');
      }

      // Récupérer le nom de l'utilisateur
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      final studentName = userDoc.exists 
          ? (userDoc.data()?['name'] ?? 'Anonymous') 
          : 'Anonymous';

      // Récupérer l'ownerUid depuis le listing
      final listingDoc = await FirebaseFirestore.instance
          .collection('listings')
          .doc(widget.listingId)
          .get();
      
      if (!listingDoc.exists) {
        throw Exception('Listing not found.');
      }
      
      final ownerUid = listingDoc.data()?['ownerUid'];
      if (ownerUid == null) {
        throw Exception('Owner information not found.');
      }

      // Chercher une review existante
      final existingQuery = await FirebaseFirestore.instance
          .collection('listing_reviews')
          .where('listingId', isEqualTo: widget.listingId)
          .where('studentUid', isEqualTo: user.uid)
          .get();

      final reviewData = {
        'listingId': widget.listingId,
        'ownerUid': ownerUid,
        'studentUid': user.uid,
        'studentName': studentName,
        'rating': _rating,
        'wasClean': _wasClean,
        'ownerWasHelpful': _ownerWasHelpful,
        'comment': _commentCtrl.text.trim(),
        'createdAt': Timestamp.now(),
      };

      if (existingQuery.docs.isNotEmpty) {
        // Mettre à jour la review existante
        await existingQuery.docs.first.reference.update(reviewData);
      } else {
        // Créer une nouvelle review
        await FirebaseFirestore.instance
            .collection('listing_reviews')
            .add(reviewData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks for your feedback!')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _reviewsStream() {
    return FirebaseFirestore.instance
        .collection('listing_reviews')
        .where('listingId', isEqualTo: widget.listingId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Widget _starsRow(int value, {double size = 28, bool interactive = false}) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final idx = i + 1;
        final filled = idx <= value;
        final icon = filled ? Icons.star_rounded : Icons.star_border_rounded;
        final color = filled ? cs.primary : cs.onSurface.withOpacity(.35);
        if (!interactive || !widget.allowAdd) {
          return Icon(icon, size: size, color: color);
        }
        return InkWell(
          onTap: () => setState(() => _rating = idx),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(icon, size: size, color: color),
          ),
        );
      }),
    );
  }

  Widget _readOnlyBanner() {
    if (widget.allowAdd) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withOpacity(.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Reviews are read-only on this screen.',
              style: TextStyle(color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
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
        title: const Text('Reviews'),
      ),
      body: Container(
        decoration: bg,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _reviewsStream(),
          builder: (context, snap) {
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
                // Résumé des notes
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withOpacity(.96),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.primary.withOpacity(.12)),
                  ),
                  child: Row(
                    children: [
                      _starsRow(avg.round(), size: 26),
                      const SizedBox(width: 12),
                      Text(
                        count == 0
                            ? 'No reviews yet'
                            : '${avg.toStringAsFixed(1)} / 5 · $count review${count > 1 ? 's' : ''}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Bannière read-only
                _readOnlyBanner(),

                // Formulaire d'ajout de review
                if (widget.allowAdd) ...[
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
                        Text('Your review',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            )),
                        const SizedBox(height: 16),
                        
                        // Rating stars
                        Text('Overall rating', style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        )),
                        const SizedBox(height: 8),
                        _starsRow(_rating, size: 32, interactive: true),
                        const SizedBox(height: 16),
                        
                        // Was clean question
                        Text('Was the property clean?', style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        )),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Radio<bool>(
                              value: true,
                              groupValue: _wasClean,
                              onChanged: (value) => setState(() => _wasClean = value!),
                            ),
                            const Text('Yes'),
                            const SizedBox(width: 16),
                            Radio<bool>(
                              value: false,
                              groupValue: _wasClean,
                              onChanged: (value) => setState(() => _wasClean = value!),
                            ),
                            const Text('No'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // Owner helpful question
                        Text('Was the owner helpful?', style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        )),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Radio<bool>(
                              value: true,
                              groupValue: _ownerWasHelpful,
                              onChanged: (value) => setState(() => _ownerWasHelpful = value!),
                            ),
                            const Text('Yes'),
                            const SizedBox(width: 16),
                            Radio<bool>(
                              value: false,
                              groupValue: _ownerWasHelpful,
                              onChanged: (value) => setState(() => _ownerWasHelpful = value!),
                            ),
                            const Text('No'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // Comment
                        MoonFormTextInput(
                          hasFloatingLabel: false,
                          hintText: 'Add a comment (optional)',
                          controller: _commentCtrl,
                          maxLines: 4,
                        ),
                        const SizedBox(height: 10),
                        
                        // Error message
                        if (_err != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              _err!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        
                        // Submit button
                        MoonFilledButton(
                          isFullWidth: true,
                          onTap: _saving ? null : _submit,
                          leading: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.send_rounded),
                          label: Text(_saving ? 'Saving…' : 'Submit review'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Liste des reviews
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
                      Text('All Reviews', style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      )),
                      const SizedBox(height: 12),
                      snap.connectionState == ConnectionState.waiting
                          ? const Center(child: Padding(
                              padding: EdgeInsets.all(12.0),
                              child: CircularProgressIndicator(),
                            ))
                          : (docs.isEmpty
                              ? Text(
                                  widget.allowAdd
                                      ? 'Be the first to leave a review.'
                                      : 'No reviews yet.',
                                  style: TextStyle(color: cs.onSurface.withOpacity(.7)),
                                )
                              : Column(
                                  children: docs.map((d) {
                                    final data = d.data();
                                    final rating = (data['rating'] as num?)?.toInt() ?? 0;
                                    final comment = (data['comment'] ?? '').toString();
                                    final studentName = (data['studentName'] ?? 'Anonymous').toString();
                                    final wasClean = data['wasClean'] ?? true;
                                    final ownerWasHelpful = data['ownerWasHelpful'] ?? true;
                                    final ts = data['createdAt'] as Timestamp?;
                                    final dateStr = ts == null
                                        ? ''
                                        : '${ts.toDate().day.toString().padLeft(2, '0')}/${ts.toDate().month.toString().padLeft(2, '0')}/${ts.toDate().year}';

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
                                          // Header with stars and name
                                          Row(
                                            children: [
                                              _starsRow(rating, size: 18),
                                              const Spacer(),
                                              Text(
                                                studentName,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: cs.onSurface,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          
                                          // Clean and helpful indicators
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: wasClean ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      wasClean ? Icons.check : Icons.close,
                                                      size: 12,
                                                      color: wasClean ? Colors.green : Colors.red,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Clean',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: wasClean ? Colors.green : Colors.red,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: ownerWasHelpful ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      ownerWasHelpful ? Icons.check : Icons.close,
                                                      size: 12,
                                                      color: ownerWasHelpful ? Colors.green : Colors.red,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Helpful Owner',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: ownerWasHelpful ? Colors.green : Colors.red,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          
                                          // Comment
                                          if (comment.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              comment,
                                              style: TextStyle(color: cs.onSurface),
                                            ),
                                          ],
                                          
                                          // Date
                                          const SizedBox(height: 8),
                                          Text(
                                            dateStr,
                                            style: TextStyle(
                                              color: cs.onSurface.withOpacity(.6),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                )),
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