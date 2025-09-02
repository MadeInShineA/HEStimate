import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:moon_design/moon_design.dart';
import 'page.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    final form = _formKey.currentState;
    if (form == null) return;
    if (!form.validate()) return;

    setState(() => _isLoading = true);
    
    try {
      print('Attempting to send password reset email to: ${_emailCtrl.text.trim()}');
      
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailCtrl.text.trim(),
      );
      
      print('Password reset email sent successfully');
      
      if (!mounted) return;
      setState(() {
        _emailSent = true;
        _isLoading = false;
      });
      
      // Show success immediately instead of using the flag
      _showSuccess();
      
    } on FirebaseAuthException catch (e) {
      print('FirebaseAuthException: ${e.code} - ${e.message}');
      final msg = switch (e.code) {
        'invalid-email' => 'Invalid email address.',
        'user-not-found' => 'No account found with that email address.',
        'too-many-requests' => 'Too many requests. Please try again later.',
        'missing-email' => 'Email address is required.',
        'invalid-continue-uri' => 'Invalid continue URL.',
        'unauthorized-continue-uri' => 'Unauthorized continue URL.',
        _ => 'Failed to send reset email: ${e.code}',
      };
      _showError(msg);
    } catch (e) {
      print('General exception: $e');
      _showError('Something went wrong. Please try again.');
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
              const Text('Error'),
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

  void _showSuccess() {
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
              const Text('Email Sent!'),
              const SizedBox(height: 8),
              Text(
                'A password reset link has been sent to ${_emailCtrl.text.trim()}. Please check your email and follow the instructions to reset your password.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: MoonTextButton(
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pushReplacementNamed('/login');
                  },
                  label: const Text('Back to Login'),
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

    return BasePage(
      title: '',
      child: SafeArea(
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
                      Icons.lock_reset,
                      size: 48,
                      color: theme?.tokens.colors.piccolo,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Forgot Password?',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter your email address and we\'ll send you a link to reset your password.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: theme?.tokens.colors.trunks,
                      ),
                    ),
                    const SizedBox(height: 24),
                    MoonFormTextInput(
                      controller: _emailCtrl,
                      hintText: 'Email',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      leading: const Icon(Icons.mail_outline),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'Email is required';
                        final re = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
                        if (!re.hasMatch(v)) return 'Enter a valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 48,
                      child: MoonFilledButton(
                        onTap: _isLoading ? null : _resetPassword,
                        label: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Send Reset Email'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pushReplacementNamed('/login'),
                        child: const Text('Back to Login'),
                      ),
                    ),
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
