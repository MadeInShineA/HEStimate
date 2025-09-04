import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:moon_design/moon_design.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'loader.dart';
import 'page.dart';
import 'rate_student_page.dart';

// Student Rating Preview Widget (CLIQUABLE)
class StudentRatingPreview extends StatelessWidget {
  final String studentUid;
  final String studentName;

  const StudentRatingPreview({
    super.key,
    required this.studentUid,
    required this.studentName,
  });

  @override
  Widget build(BuildContext context) {
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

        final cs = Theme.of(context).colorScheme;
        final full = avg.round().clamp(0, 5);

        Widget starsRow() => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ...List.generate(5, (i) {
                  final filled = i < full;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 24,
                      color: filled ? cs.primary : cs.onSurface.withOpacity(.35),
                    ),
                  );
                }),
              ],
            );

        return InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => StudentReviewsPage(
                  studentUid: studentUid,
                  studentName: studentName.isNotEmpty ? studentName : 'Unknown Student',
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: starsRow(),
          ),
        );
      },
    );
  }
}

// Homeowner Rating Preview Widget (NON CLIQUABLE)
class HomeownerRatingPreview extends StatelessWidget {
  final String ownerUid;

  const HomeownerRatingPreview({
    super.key,
    required this.ownerUid,
  });

  Future<Map<String, dynamic>> _getOwnerRatings(List<String> ownerListingIds) async {
    double totalSum = 0;
    int totalCount = 0;

    // Split listing IDs into chunks of 30 to handle Firestore's limit
    for (int i = 0; i < ownerListingIds.length; i += 30) {
      final chunk = ownerListingIds.sublist(
        i, 
        math.min(i + 30, ownerListingIds.length)
      );

      final querySnapshot = await FirebaseFirestore.instance
          .collection('listing_reviews')
          .where('listingId', whereIn: chunk)
          .get();

      for (final doc in querySnapshot.docs) {
        final rating = (doc.data()['rating'] as num?)?.toDouble() ?? 0.0;
        totalSum += rating;
        totalCount++;
      }
    }

    final average = totalCount > 0 ? totalSum / totalCount : 0.0;

    return {
      'average': average,
      'count': totalCount,
    };
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('listings')
          .where('ownerUid', isEqualTo: ownerUid)
          .snapshots(),
      builder: (context, listingsSnapshot) {
        if (!listingsSnapshot.hasData) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          );
        }

        final ownerListingIds = listingsSnapshot.data!.docs
            .map((doc) => doc.id)
            .toList();

        if (ownerListingIds.isEmpty) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ...List.generate(5, (i) {
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.star_border_rounded,
                    size: 24,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(.35),
                  ),
                );
              }),
            ],
          );
        }

        return FutureBuilder<Map<String, dynamic>>(
          future: _getOwnerRatings(ownerListingIds),
          builder: (context, ratingsSnapshot) {
            if (!ratingsSnapshot.hasData) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              );
            }

            final data = ratingsSnapshot.data!;
            final overallAvg = data['average'] as double;
            final totalReviews = data['count'] as int;
            final cs = Theme.of(context).colorScheme;
            final full = overallAvg.round().clamp(0, 5);

            // NON CLIQUABLE - juste les étoiles avec infos
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ...List.generate(5, (i) {
                  final filled = i < full;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 24,
                      color: filled ? cs.primary : cs.onSurface.withOpacity(.35),
                    ),
                  );
                }),
                const SizedBox(width: 8),
                Text(
                  totalReviews == 0 
                      ? 'No reviews yet' 
                      : '${overallAvg.toStringAsFixed(1)} (${totalReviews} review${totalReviews != 1 ? 's' : ''})',
                  style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface.withOpacity(.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic>? _userData;
  bool _isEditing = false;
  bool _isLoading = true;

  final _nameCtrl = TextEditingController();
  String? _role;
  String? _school;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _user = FirebaseAuth.instance.currentUser;

  List<String> _schools = [];
  File? _faceIdImage;

  @override
  void initState() {
    super.initState();
    _loadSchools();
    _loadUserData();
    _loadFaceIdImage();
  }

  Future<void> _loadSchools() async {
    try {
      final snapshot = await _firestore.collection('schools').get();
      setState(() {
        _schools = snapshot.docs.map((d) => d['name'] as String).toList();
      });
    } catch (e) {
      debugPrint('Error loading schools: $e');
    }
  }

  Future<void> _loadUserData() async {
    if (_user == null) return;

    try {
      final docRef = _firestore.collection('users').doc(_user!.uid);
      final doc = await docRef.get();
      if (!doc.exists) {
        _userData = {
          'name': '',
          'role': 'student',
          'school': null,
          'faceIdEnabled': false,
        };
        await docRef.set(_userData!);
      } else {
        final data = doc.data()!;
        // Migration: if there's no 'role' but there is 'isHes', infer role
        if (!data.containsKey('role')) {
          final bool isHes = data['isHes'] ?? false;
          _role = isHes ? 'student' : 'homeowner';
          await docRef.update({'role': _role});
          data['role'] = _role;
        }
        _userData = data;
      }

      _nameCtrl.text = _userData?['name'] ?? '';
      _role = _userData?['role'] ?? 'homeowner';
      _school = _userData?['school'];
    } catch (e) {
      debugPrint('Error loading user data: $e');
      _userData = {
        'name': '',
        'role': 'homeowner',
        'school': null,
        'faceIdEnabled': false,
      };
      _role = 'homeowner';
      _school = null;
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFaceIdImage() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/face_id.png');
    if (await file.exists()) {
      setState(() => _faceIdImage = file);
    }
  }

  Future<void> _saveUserData() async {
    if (_user == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      // Only update mutable fields: name and school (school only if role == 'student')
      await _firestore.collection('users').doc(_user!.uid).update({
        'name': _nameCtrl.text.trim(),
        'school': _role == 'student' ? _school : null,
      });
      setState(() {
        _userData?['name'] = _nameCtrl.text.trim();
        _userData?['school'] = _role == 'student' ? _school : null;
        _isEditing = false;
      });
    } catch (e) {
      debugPrint('Error saving user data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save user data')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _cleanupFaceIdData() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/face_id.png');
      if (await file.exists()) {
        await file.delete();
        debugPrint('Face ID image deleted successfully');
      }

      if (_user != null) {
        await _firestore.collection('users').doc(_user!.uid).update({
          'faceIdEnabled': false,
        });
        debugPrint('Face ID disabled in Firestore');
      }
    } catch (e) {
      debugPrint('Error cleaning up Face ID data: $e');
    }
  }

  Future<void> _signOut() async {
    setState(() => _isLoading = true);
    
    try {
      await _cleanupFaceIdData();
      
      await FirebaseAuth.instance.signOut();
      
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      debugPrint('Error during sign out: $e');
      // Même en cas d'erreur, on procède à la déconnexion
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
  }

  void _openFaceIdConfig() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FaceIdConfigPage(
          faceImage: _faceIdImage,
          userData: _userData,
          onImageChanged: (file) {
            setState(() => _faceIdImage = file);
          },
        ),
      ),
    );
    await _loadFaceIdImage();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.moonTheme;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return BasePage(
      title: '',
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.account_circle,
                      size: 80, color: theme?.tokens.colors.piccolo),
                  const SizedBox(height: 12),
                  // Rating stars for both student and homeowner - CENTRÉES SOUS L'ICÔNE
                  if (_userData?['role'] == 'student')
                    StudentRatingPreview(
                      studentUid: _user?.uid ?? '',
                      studentName: _userData?['name'] ?? '',
                    )
                  else if (_userData?['role'] == 'homeowner')
                    HomeownerRatingPreview(
                      ownerUid: _user?.uid ?? '',
                    ),
                  const SizedBox(height: 16),
                  _isEditing ? _buildEditForm() : _buildUserInfo(),
                  const SizedBox(height: 24),
                  if (!_isEditing)
                    MoonFilledButton(
                      onTap: () => setState(() => _isEditing = true),
                      label: const Text('Edit Info'),
                    ),
                  if (_isEditing)
                    Row(
                      children: [
                        Expanded(
                          child: MoonFilledButton(
                            onTap: _saveUserData,
                            label: const Text('Save'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MoonFilledButton(
                            onTap: () => setState(() => _isEditing = false),
                            label: const Text('Cancel'),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  if (!_isEditing) ...[
                    MoonFilledButton(
                      onTap: _openFaceIdConfig,
                      label: const Text('Configure Face ID'),
                    ),
                    const SizedBox(height: 16),
                    MoonFilledButton(
                      onTap: _signOut,
                      label: const Text('Sign out'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center, // Centrer horizontalement
      children: [
        Text(
          'Full Name: ${_userData?['name'] ?? ''}',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center, // Optionnel
        ),
        const SizedBox(height: 8),
        Text(
          'Email: ${_user?.email ?? ''}',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Role: ${_userData?['role'] ?? 'homeowner'}',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        if (_userData?['role'] == 'student') ...[
          const SizedBox(height: 8),
          Text(
            'School: ${_userData?['school'] ?? ''}',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Face ID: ${_userData?['faceIdEnabled'] == true ? 'Enabled' : 'Disabled'}',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MoonFormTextInput(
            hintText: 'Full Name',
            controller: _nameCtrl,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Name is required';
              return null;
            },
          ),
          const SizedBox(height: 12),
          // Role is NOT editable here; display as readonly text
          Row(
            children: [
              const Text('Role: ', style: TextStyle(fontWeight: FontWeight.w600)),
              Text(_role ?? 'homeowner'),
            ],
          ),
          const SizedBox(height: 12),
          // If the role is student, allow selecting the school
          if (_role == 'student')
            DropdownButtonFormField<String>(
              value: _school,
              hint: const Text('Select your school'),
              items: _schools
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _school = v),
              validator: (v) {
                if (_role == 'student' && (v == null || v.isEmpty)) {
                  return 'Please select your school';
                }
                return null;
              },
            ),
        ],
      ),
    );
  }
}

/// ----------------- FaceIdConfigPage -----------------
class FaceIdConfigPage extends StatefulWidget {
  final File? faceImage;
  final Function(File?) onImageChanged;
  final Map<String, dynamic>? userData;

  const FaceIdConfigPage({
    super.key,
    required this.faceImage,
    required this.onImageChanged,
    required this.userData,
  });

  @override
  State<FaceIdConfigPage> createState() => _FaceIdConfigPageState();
}

class _FaceIdConfigPageState extends State<FaceIdConfigPage> {
  bool _faceIdEnabled = false;
  File? _faceImage;
  bool _isLoading = false;
  String _imageKey = DateTime.now().millisecondsSinceEpoch.toString();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _user = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _faceImage = widget.faceImage;
    _faceIdEnabled = widget.userData?['faceIdEnabled'] ?? false;
  }

  Future<String> _verifyFaceImage(File image) async {
    try {
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);
      final response = await http.post(
        Uri.parse('https://hestimate-api-production.up.railway.app/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': base64Image}),
      );

      debugPrint('Response body: ${response.body}');
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return data['success'] == true ? "success" : '';
      }
      return data['detail'];
    } catch (e) {
      debugPrint('Error verifying image: $e');
      return "Server error during verification";
    }
  }

  Future<void> _pickFaceImage() async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Select from Gallery'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source, maxWidth: 600, maxHeight: 600);
    if (image == null) return;

    setState(() => _isLoading = true);

    final result = await _verifyFaceImage(File(image.path));
    if (result != 'success') {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Invalid face image. $result')));
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final target = File('${dir.path}/face_id.png');
      if (await target.exists()) await target.delete();
      final savedImage = await File(image.path).copy('${dir.path}/face_id.png');

      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      setState(() {
        _faceImage = savedImage;
        _imageKey = DateTime.now().millisecondsSinceEpoch.toString();
        _faceIdEnabled = true;
      });

      if (_user != null) {
        await _firestore.collection('users').doc(_user!.uid).update({'faceIdEnabled': true});
        widget.userData?['faceIdEnabled'] = true;
      }

      widget.onImageChanged(savedImage);

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Face ID image updated successfully')));
      }
    } catch (e) {
      debugPrint('Error saving face image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Failed to save Face ID image')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFaceId(bool value) async {
    // Si l'utilisateur active Face ID et qu'il n'y a pas de photo
    if (value && _faceImage == null) {
      // Demander directement de prendre une photo
      final ImageSource? source = await showModalBottomSheet<ImageSource>(
        context: context,
        isDismissible: false, // Empêche la fermeture en tapant à côté
        enableDrag: false, // Empêche la fermeture en glissant
        builder: (context) {
          return WillPopScope(
            onWillPop: () async => false, // Empêche le retour avec le bouton back
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Face ID Photo Required',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'To enable Face ID, you need to add a photo. Please choose an option:',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.camera_alt),
                      title: const Text('Take Photo'),
                      onTap: () => Navigator.of(context).pop(ImageSource.camera),
                    ),
                    ListTile(
                      leading: const Icon(Icons.photo_library),
                      title: const Text('Select from Gallery'),
                      onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      // Si l'utilisateur a annulé, on ne change pas l'état du switch
      if (source == null) {
        return; // Le switch reste à false
      }

      // L'utilisateur a choisi une source, on procède à la prise de photo
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: source, maxWidth: 600, maxHeight: 600);
      
      // Si l'utilisateur a annulé la prise de photo
      if (image == null) {
        return; // Le switch reste à false
      }

      setState(() => _isLoading = true);

      final result = await _verifyFaceImage(File(image.path));
      if (result != 'success') {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Invalid face image. $result')));
          setState(() => _isLoading = false);
        }
        return; // Le switch reste à false
      }

      try {
        final dir = await getApplicationDocumentsDirectory();
        final target = File('${dir.path}/face_id.png');
        if (await target.exists()) await target.delete();
        final savedImage = await File(image.path).copy('${dir.path}/face_id.png');

        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();

        setState(() {
          _faceImage = savedImage;
          _imageKey = DateTime.now().millisecondsSinceEpoch.toString();
          _faceIdEnabled = true; // Active Face ID seulement si la photo est sauvegardée avec succès
        });

        if (_user != null) {
          await _firestore.collection('users').doc(_user!.uid).update({'faceIdEnabled': true});
          widget.userData?['faceIdEnabled'] = true;
        }

        widget.onImageChanged(savedImage);

        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Face ID enabled and image saved successfully')));
        }
      } catch (e) {
        debugPrint('Error saving face image: $e');
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Failed to save Face ID image')));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      // Cas normal : désactivation ou activation avec photo existante
      setState(() => _faceIdEnabled = value);
      if (_user != null) {
        await _firestore.collection('users').doc(_user!.uid).update({'faceIdEnabled': value});
        widget.userData?['faceIdEnabled'] = value;
      }
    }
  }

  Future<void> _removeFaceImage() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/face_id.png');
      if (await file.exists()) {
        await file.delete();
      }

      setState(() {
        _faceImage = null;
        _faceIdEnabled = false;
        _imageKey = DateTime.now().millisecondsSinceEpoch.toString();
      });

      if (_user != null) {
        await _firestore.collection('users').doc(_user!.uid).update({'faceIdEnabled': false});
        widget.userData?['faceIdEnabled'] = false;
      }

      widget.onImageChanged(null);

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Face ID photo removed successfully')));
      }
    } catch (e) {
      debugPrint('Error removing face image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Failed to remove Face ID photo')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      title: 'Configure Face ID',
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Icon(
                    Icons.face_retouching_natural,
                    size: 80,
                    color: context.moonTheme?.tokens.colors.piccolo,
                  ),
                ),
                const SizedBox(height: 24),
                SwitchListTile(
                  title: const Text('Enable Face ID'),
                  value: _faceIdEnabled,
                  onChanged: _toggleFaceId,
                ),
                const SizedBox(height: 16),
                // Image avec effet grisé/flou si Face ID désactivé
                _faceImage != null
                    ? Container(
                        constraints: const BoxConstraints(
                          maxHeight: 300,
                          maxWidth: 300,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: ColorFiltered(
                            colorFilter: _faceIdEnabled
                                ? const ColorFilter.mode(Colors.transparent, BlendMode.multiply)
                                : const ColorFilter.mode(Colors.grey, BlendMode.saturation),
                            child: Opacity(
                              opacity: _faceIdEnabled ? 1.0 : 0.5,
                              child: Image.file(
                                _faceImage!,
                                key: ValueKey(_imageKey),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      )
                    : Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Text(
                            'No Face ID image',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                const SizedBox(height: 16),
                // Bouton Add/Change Photo (désactivé si Face ID désactivé)
                MoonFilledButton(
                  onTap: (_isLoading || !_faceIdEnabled) ? null : _pickFaceImage,
                  backgroundColor: (_faceIdEnabled) ? null : Colors.grey.shade300,
                  label: Text(
                    _faceImage != null ? 'Change Face ID Photo' : 'Add Face ID Photo',
                    style: TextStyle(
                      color: _faceIdEnabled ? null : Colors.grey.shade600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Bouton Remove Photo (rouge, toujours activé s'il y a une photo)
                if (_faceImage != null)
                  MoonFilledButton(
                    onTap: _isLoading ? null : _removeFaceImage,
                    backgroundColor: Colors.red,
                    label: const Text(
                      'Remove Photo',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          if (_isLoading) const FullScreenLoader(message: 'Processing Face ID...'),
        ],
      ),
    );
  }
}
