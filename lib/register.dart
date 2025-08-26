import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:moon_design/moon_design.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscurePw = true;
  bool _isHes = false;

  String? _selectedSchool;
  List<String> _schools = [];

  @override
  void initState() {
    super.initState();
    _fetchSchools();
  }

  Future<void> _fetchSchools() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('schools').get();
      setState(() {
        _schools = snapshot.docs.map((doc) => doc['name'] as String).toList();
      });
    } catch (e) {
      debugPrint("Error fetching schools: $e");
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final form = _formKey.currentState;
    if (form == null) return;
    if (!form.validate()) return;

    setState(() => _isLoading = true);
    try {
      final userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      final uid = userCred.user?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'name': _nameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'isHes': _isHes,
          'school': _isHes ? _selectedSchool : null,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      _showToast(context, 'Welcome! Account created.');
      Navigator.of(context).pushReplacementNamed('/home');
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'email-already-in-use' => 'That email is already in use.',
        'weak-password' => 'Password is too weak.',
        'invalid-email' => 'That email looks invalid.',
        _ => 'Registration failed. (${e.code})',
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
        shape: MoonSquircleBorder(
          borderRadius: const MoonSquircleBorderRadius.all(
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

  void _showToast(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.moonTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      Icon(
                        Icons.nightlight_round,
                        size: 48,
                        color: theme?.tokens.colors.piccolo,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Create your account',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 24),

                      // Name
                      MoonFormTextInput(
                        hintText: 'Full name',
                        textInputAction: TextInputAction.next,
                        leading: const Icon(Icons.person_outline),
                        controller: _nameCtrl,
                        validator: (value) {
                          final v = value?.trim() ?? '';
                          if (v.isEmpty) return 'Name is required';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Email
                      MoonFormTextInput(
                        hintText: 'Email',
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        leading: const Icon(Icons.mail_outline),
                        controller: _emailCtrl,
                        validator: (value) {
                          final v = value?.trim() ?? '';
                          if (v.isEmpty) return 'Email is required';
                          final emailRx = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                          if (!emailRx.hasMatch(v)) return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Password
                      MoonFormTextInput(
                        hintText: 'Password',
                        obscureText: _obscurePw,
                        textInputAction: TextInputAction.next,
                        leading: const Icon(Icons.lock_outline),
                        trailing: IconButton(
                          onPressed: () =>
                              setState(() => _obscurePw = !_obscurePw),
                          icon: Icon(
                            _obscurePw ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                        controller: _passwordCtrl,
                        validator: (value) {
                          final v = value ?? '';
                          if (v.isEmpty) return 'Password is required';
                          if (v.length < 6) return 'Use at least 6 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Confirm Password
                      MoonFormTextInput(
                        hintText: 'Confirm password',
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        leading: const Icon(Icons.check_circle_outline),
                        controller: _confirmCtrl,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your password';
                          }
                          if (value != _passwordCtrl.text) {
                            return "Passwords don't match";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Checkbox HES
                      Row(
                        children: [
                          Checkbox(
                            value: _isHes,
                            onChanged: (v) {
                              setState(() {
                                _isHes = v ?? false;
                                if (!_isHes) _selectedSchool = null;
                              });
                            },
                          ),
                          const Text("I am a HES student"),
                        ],
                      ),

                      // Select school if HES
                      if (_isHes)
                        DropdownButtonFormField<String>(
                          value: _selectedSchool,
                          items: _schools
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s),
                                ),
                              )
                              .toList(),
                          onChanged: (val) => setState(() {
                            _selectedSchool = val;
                          }),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: "Select your school",
                          ),
                          validator: (val) {
                            if (_isHes && (val == null || val.isEmpty)) {
                              return "School is required";
                            }
                            return null;
                          },
                        ),

                      const SizedBox(height: 20),

                      // Submit
                      SizedBox(
                        height: 48,
                        child: MoonFilledButton(
                          onTap: _isLoading ? null : _register,
                          label: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Create account'),
                        ),
                      ),

                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacementNamed('/login');
                          },
                          child: const Text('Already have an account? Sign in'),
                        ),
                      ),

                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),

                      // Terms
                      Text(
                        'By creating an account you agree to our Terms and Privacy Policy.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
