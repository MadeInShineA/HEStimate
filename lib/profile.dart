import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:moon_design/moon_design.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'loader.dart';

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
  bool _isHes = false;
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
      final doc = await _firestore.collection('users').doc(_user!.uid).get();
      if (!doc.exists) {
        _userData = {
          'name': '',
          'isHes': false,
          'school': null,
          'faceIdEnabled': false,
        };
        await _firestore.collection('users').doc(_user!.uid).set(_userData!);
      } else {
        _userData = doc.data();
      }

      _nameCtrl.text = _userData?['name'] ?? '';
      _isHes = _userData?['isHes'] ?? false;
      _school = _userData?['school'];
    } catch (e) {
      debugPrint('Error loading user data: $e');
      _userData = {
        'name': '',
        'isHes': false,
        'school': null,
        'faceIdEnabled': false,
      };
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
      await _firestore.collection('users').doc(_user!.uid).update({
        'name': _nameCtrl.text.trim(),
        'isHes': _isHes,
        'school': _isHes ? _school : null,
      });
      setState(() {
        _userData?['name'] = _nameCtrl.text.trim();
        _userData?['isHes'] = _isHes;
        _userData?['school'] = _isHes ? _school : null;
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

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    Navigator.of(context).pushReplacementNamed('/login');
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

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Full Name: ${_userData?['name'] ?? ''}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Email: ${_user?.email ?? ''}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Student at HES: ${_userData?['isHes'] == true ? 'Yes' : 'No'}',
            style: Theme.of(context).textTheme.titleMedium),
        if (_userData?['isHes'] == true)
          Text('School: ${_userData?['school'] ?? ''}',
              style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Face ID: ${_userData?['faceIdEnabled'] == true ? 'Enabled' : 'Disabled'}',
            style: Theme.of(context).textTheme.titleMedium),
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
          Row(
            children: [
              Checkbox(
                value: _isHes,
                onChanged: (v) => setState(() => _isHes = v ?? false),
              ),
              const Text('I am a student at HES'),
            ],
          ),
          if (_isHes)
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
                if (_isHes && (v == null || v.isEmpty)) {
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
        return data['success'] ==  true ? "success" : '';
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
    setState(() => _faceIdEnabled = value);
    if (_user != null) {
      await _firestore.collection('users').doc(_user!.uid).update({'faceIdEnabled': value});
      widget.userData?['faceIdEnabled'] = value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configure Face ID')),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  title: const Text('Enable Face ID'),
                  value: _faceIdEnabled,
                  onChanged: _toggleFaceId,
                ),
                const SizedBox(height: 16),
                _faceImage != null
                    ? Image.file(_faceImage!, key: ValueKey(_imageKey), height: 200)
                    : const SizedBox(height: 200, child: Center(child: Text('No Face ID image'))),
                const SizedBox(height: 16),
                MoonFilledButton(
                  onTap: _isLoading ? null : _pickFaceImage,
                  label: Text(_faceImage != null ? 'Change Face ID Photo' : 'Add Face ID Photo'),
                ),
              ],
            ),
          ),
          if (_isLoading) const FullScreenLoader(message: 'Saving Face ID image...'),
        ],
      ),
    );
  }
}
