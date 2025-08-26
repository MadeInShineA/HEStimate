import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:moon_design/moon_design.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FaceIdLoginPage extends StatefulWidget {
  final File? faceImage;
  final User? user;

  const FaceIdLoginPage({super.key, this.faceImage, this.user});

  @override
  State<FaceIdLoginPage> createState() => _FaceIdLoginPageState();
}

class _FaceIdLoginPageState extends State<FaceIdLoginPage> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;

  Future<void> _pickImageFromCamera() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  Future<void> _pickImageFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.moonTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Face ID Login')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Scan your face to login',
                    style: TextStyle(fontSize: 20),
                  ),
                  const SizedBox(height: 24),
                  _selectedImage != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            _selectedImage!,
                            width: 200,
                            height: 200,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Icon(
                          Icons.account_circle,
                          size: 120,
                          color: theme?.tokens.colors.piccolo,
                        ),
                  const SizedBox(height: 24),
                  MoonFilledButton(
                    onTap: _pickImageFromCamera,
                    label: const Text('Take Photo'),
                  ),
                  const SizedBox(height: 12),
                  MoonFilledButton(
                    onTap: _pickImageFromGallery,
                    label: const Text('Select from Gallery'),
                  ),
                  const SizedBox(height: 24),
                  MoonTextButton(
                    onTap: () {
                      Navigator.of(context).pushReplacementNamed('/login');
                    },
                    label: Text(
                      'Login with Email/Password instead',
                      style: TextStyle(color: theme?.tokens.colors.piccolo),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
