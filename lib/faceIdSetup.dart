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

class FaceIdSetupPage extends StatefulWidget {
  const FaceIdSetupPage({super.key});

  @override
  State<FaceIdSetupPage> createState() => _FaceIdSetupPageState();
}

class _FaceIdSetupPageState extends State<FaceIdSetupPage> {
  File? _faceImage;
  bool _isLoading = false;
  String _imageKey = DateTime.now().millisecondsSinceEpoch.toString();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _user = FirebaseAuth.instance.currentUser;

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
      });

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Face ID photo added successfully')));
      }
    } catch (e) {
      debugPrint('Error saving face image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Failed to save Face ID photo')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _enableFaceIdAndContinue() async {
    if (_faceImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a Face ID photo first')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_user != null) {
        await _firestore.collection('users').doc(_user!.uid).update({
          'faceIdEnabled': true,
        });
      }

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } catch (e) {
      debugPrint('Error enabling Face ID: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Failed to enable Face ID')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _skipFaceId() async {
    if (_user != null) {
      await _firestore.collection('users').doc(_user!.uid).update({
        'faceIdEnabled': false,
      });
    }
    
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.moonTheme;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  Icon(
                    Icons.face_retouching_natural,
                    size: 80,
                    color: theme?.tokens.colors.piccolo,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Set up Face ID',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Would you like to enable Face ID for faster and more secure login?',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 40),
                  
                  // Zone d'affichage de l'image
                  Container(
                    height: 300,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: _faceImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              _faceImage!,
                              key: ValueKey(_imageKey),
                              fit: BoxFit.contain,
                              width: double.infinity,
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_a_photo_outlined,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No photo added yet',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Bouton pour ajouter/changer la photo
                  MoonFilledButton(
                    onTap: _isLoading ? null : _pickFaceImage,
                    label: Text(_faceImage != null ? 'Change Photo' : 'Add Face ID Photo'),
                  ),
                  
                  const Spacer(),
                  
                  // Boutons de navigation
                  if (_faceImage != null) ...[
                    MoonFilledButton(
                      onTap: _isLoading ? null : _enableFaceIdAndContinue,
                      backgroundColor: Colors.green,
                      label: const Text(
                        'Enable Face ID',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  MoonOutlinedButton(
                    onTap: _isLoading ? null : _skipFaceId,
                    label: Text(
                      _faceImage != null ? 'Skip for now' : 'Skip Face ID',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  Text(
                    _faceImage != null
                        ? 'You can always change this later in your profile settings.'
                        : 'You can always enable Face ID later in your profile settings.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            if (_isLoading) const FullScreenLoader(message: 'Setting up Face ID...'),
          ],
        ),
      ),
    );
  }
}