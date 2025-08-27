import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:moon_design/moon_design.dart';
import 'faceIdLogin.dart';

class LoginPage extends StatefulWidget {
  final File? faceImage; // Image Face ID si existante
  const LoginPage({super.key, this.faceImage});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _obscurePw = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final form = _formKey.currentState;
    if (form == null) return;
    if (!form.validate()) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logged in!')));
      Navigator.of(context).pushReplacementNamed('/home');
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'invalid-email' => 'Invalid email address.',
        'user-not-found' => 'No user found for that email.',
        'wrong-password' => 'Incorrect password.',
        'user-disabled' => 'This account has been disabled.',
        _ => 'Login failed: ${e.code}',
      };
      _showError(msg);
    } catch (_) {
      _showError('Something went wrong.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: const MoonSquircleBorder(
          borderRadius: MoonSquircleBorderRadius.all(
            MoonSquircleRadius(cornerRadius: 16),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Oops'),
              const SizedBox(height: 8),
              MoonErrorMessage(errorText: message),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: MoonTextButton(
                  onTap: () => Navigator.of(context).pop(),
                  label: const Text('OK'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.moonTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.login,
                      size: 48,
                      color: theme?.tokens.colors.piccolo,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Welcome back',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),
                    MoonFormTextInput(
                      hintText: 'Email',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      leading: const Icon(Icons.mail_outline),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'Email is required';
                        final re = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
                        if (!re.hasMatch(v)) return 'Enter a valid email';
                        return null;
                      },
                      onChanged: (v) => _emailCtrl.text = v,
                    ),
                    const SizedBox(height: 12),
                    MoonFormTextInput(
                      hintText: 'Password',
                      obscureText: _obscurePw,
                      textInputAction: TextInputAction.done,
                      leading: const Icon(Icons.lock_outline),
                      trailing: IconButton(
                        onPressed: () => setState(() => _obscurePw = !_obscurePw),
                        icon: Icon(_obscurePw ? Icons.visibility : Icons.visibility_off),
                      ),
                      validator: (value) {
                        final v = value ?? '';
                        if (v.isEmpty) return 'Password is required';
                        return null;
                      },
                      onChanged: (v) => _passwordCtrl.text = v,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 48,
                      child: MoonFilledButton(
                        onTap: _isLoading ? null : _login,
                        label: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Sign in'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pushReplacementNamed('/register'),
                        child: const Text("Don't have an account? Register"),
                      ),
                    ),
                    if (widget.faceImage != null) ...[
                      const SizedBox(height: 12),
                      MoonFilledButton(
                        onTap: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => FaceIdLoginPage(
                                faceImage: widget.faceImage,
                                user: FirebaseAuth.instance.currentUser,
                              ),
                            ),
                          );
                        },
                        label: const Text('Login with Face ID'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
