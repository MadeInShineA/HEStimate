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
  int _stars = 0;
  final _commentCtrl = TextEditingController();
  bool _saving = false;
  String? _err;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  String _ratingDocIdFor(String listingId, String userId) => '${listingId}_$userId';

  Future<void> _loadMyExistingRatingIfAny() async {
    if (!widget.allowAdd) return; 
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final docId = _ratingDocIdFor(widget.listingId, user.uid);
    final doc = await FirebaseFirestore.instance.collection('ratings').doc(docId).get();
    if (doc.exists) {
      final m = doc.data()!;
      setState(() {
        _stars = (m['stars'] as num?)?.toInt() ?? 0;
        _commentCtrl.text = (m['comment'] ?? '').toString();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMyExistingRatingIfAny();
  }

  Future<void> _submit() async {
    if (!widget.allowAdd) return;
    if (_stars < 1 || _stars > 5) {
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

      final docId = _ratingDocIdFor(widget.listingId, user.uid);
      final data = <String, dynamic>{
        'listingId': widget.listingId,
        'userId': user.uid,
        'stars': _stars,
        'comment': _commentCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(), 
      };

      final docRef = FirebaseFirestore.instance.collection('ratings').doc(docId);
      final snap = await docRef.get();

      if (snap.exists) {
        // Update only (garde createdAt)
        final existing = snap.data()!;
        await docRef.update({
          ...data,
          'createdAt': existing['createdAt'] ?? FieldValue.serverTimestamp(),
        });
      } else {
        // Create
        await docRef.set(data);
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

  Stream<QuerySnapshot<Map<String, dynamic>>> _ratingsStream() {
    return FirebaseFirestore.instance
        .collection('ratings')
        .where('listingId', isEqualTo: widget.listingId)
        .orderBy('updatedAt', descending: true)
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
          onTap: () => setState(() => _stars = idx),
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
              'Ratings are read-only on this screen.',
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
        title: const Text('Ratings'),
      ),
      body: Container(
        decoration: bg,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _ratingsStream(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            final count = docs.length;
            final avg = count == 0
                ? 0.0
                : docs
                        .map((d) => (d.data()['stars'] as num?)?.toDouble() ?? 0.0)
                        .fold<double>(0.0, (a, b) => a + b) /
                    count;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                
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
                            ? 'No ratings yet'
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

                
                _readOnlyBanner(),

                
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
                        Text('Your rating',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            )),
                        const SizedBox(height: 8),
                        _starsRow(_stars, size: 32, interactive: true),
                        const SizedBox(height: 12),
                        MoonFormTextInput(
                          hasFloatingLabel: false,
                          hintText: 'Add a short comment (optional)',
                          controller: _commentCtrl,
                          maxLines: 4,
                        ),
                        const SizedBox(height: 10),
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
                          label: Text(_saving ? 'Saving…' : 'Submit rating'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Liste des avis
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withOpacity(.96),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.primary.withOpacity(.12)),
                  ),
                  child: snap.connectionState == ConnectionState.waiting
                      ? const Center(child: Padding(
                          padding: EdgeInsets.all(12.0),
                          child: CircularProgressIndicator(),
                        ))
                      : (docs.isEmpty
                          ? Text(
                              widget.allowAdd
                                  ? 'Be the first to leave a rating.'
                                  : 'No ratings yet.',
                              style: TextStyle(color: cs.onSurface.withOpacity(.7)),
                            )
                          : Column(
                              children: docs.map((d) {
                                final m = d.data();
                                final stars = (m['stars'] as num?)?.toInt() ?? 0;
                                final comment = (m['comment'] ?? '').toString();
                                final ts = m['updatedAt'] as Timestamp?;
                                final dateStr = ts == null
                                    ? ''
                                    : '${ts.toDate().year}-${ts.toDate().month.toString().padLeft(2, '0')}-${ts.toDate().day.toString().padLeft(2, '0')}';

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: cs.primary.withOpacity(.10)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _starsRow(stars, size: 18),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (comment.isNotEmpty)
                                              Text(
                                                comment,
                                                style: TextStyle(color: cs.onSurface),
                                              ),
                                            Text(
                                              dateStr,
                                              style: TextStyle(
                                                color: cs.onSurface.withOpacity(.6),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            )),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
