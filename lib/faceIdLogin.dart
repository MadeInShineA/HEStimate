import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:moon_design/moon_design.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'loader.dart';

class FaceIdLoginPage extends StatefulWidget {
  final User? user;
  final File? faceImage;

  const FaceIdLoginPage({super.key, this.user, this.faceImage});

  @override
  State<FaceIdLoginPage> createState() => _FaceIdLoginPageState();
}

class _FaceIdLoginPageState extends State<FaceIdLoginPage> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  bool _isLoading = false;

  Future<void> _pickImageFromCamera() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() => _selectedImage = File(image.path));
      await _verifyFaceAndLogin();
    }
  }

  Future<void> _verifyFaceAndLogin() async {
    if (_selectedImage == null || widget.user == null || widget.faceImage == null) return;

    setState(() => _isLoading = true);

    try {
      // Image stockée depuis Profile
      final storedBytes = await widget.faceImage!.readAsBytes();
      final storedBase64 = base64Encode(storedBytes);

      // Image prise à l’instant
      final takenBytes = await _selectedImage!.readAsBytes();
      final takenBase64 = base64Encode(takenBytes);

      final verifyResult = await http.post(
        Uri.parse('https://hestimate-api-production.up.railway.app/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'image': takenBase64}),
      );

      if (verifyResult.statusCode != 200) {
        final responseBody = jsonDecode(verifyResult.body);
        debugPrint('Face verification failed with status: ${verifyResult.body}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to verify face. ${responseBody["detail"] == null ? '' : ' ${responseBody["detail"]}'}')),
          );
        }
        return;
      }

      final response = await http.post(
        Uri.parse('https://hestimate-api-production.up.railway.app/compare'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'image1': storedBase64,
          'image2': takenBase64,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/home');
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(data['message'] ?? 'Face not recognized')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to verify face.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error verifying face: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error during face verification.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.moonTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Face ID Login')),
      body: Stack(
        children: [
          SafeArea(
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
                      Icon(
                            Icons.account_circle,
                            size: 120,
                            color: theme?.tokens.colors.piccolo,
                      ),
                      const SizedBox(height: 24),
                      MoonFilledButton(
                        onTap: _isLoading ? null : _pickImageFromCamera,
                        label: const Text('Take Photo'),
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
          if (_isLoading) const FullScreenLoader(message: 'Verifying Face ID...'),
        ],
      ),
    );
  }
}
