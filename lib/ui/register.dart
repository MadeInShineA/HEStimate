import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:moon_design/moon_design.dart';
import 'page.dart';

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

  // NEW: loading + error for schools
  bool _isLoadingSchools = false;
  String? _schoolsError;

  String? _selectedSchool;
  List<String> _schools = [];

  String _role = "student";

  @override
  void initState() {
    super.initState();
    _fetchSchools();
  }

  Future<void> _fetchSchools() async {
    setState(() {
      _isLoadingSchools = true;
      _schoolsError = null;
    });
    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('schools').get();

      final names = snapshot.docs
          .map((doc) => (doc.data()['name'] as String?)?.trim())
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      setState(() {
        _schools = names;
        // Ensure current value is present in items, otherwise clear it
        if (_selectedSchool != null && !_schools.contains(_selectedSchool)) {
          _selectedSchool = null;
        }
      });
    } catch (e) {
      debugPrint("Error fetching schools: $e");
      setState(() {
        _schoolsError = 'Could not load schools. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSchools = false;
        });
      }
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

    // Prevent proceeding if student has not selected a school
    if (_role == 'student' && (_selectedSchool == null || _selectedSchool!.isEmpty)) {
      _showError('Please select your school.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final userCred =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      final uid = userCred.user?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'name': _nameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'role': _role,
          'school': _role == "student" ? _selectedSchool : null,
          'faceIdEnabled': false, // default disabled
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      _showToast(context, 'Welcome! Account created.');
      Navigator.of(context).pushReplacementNamed('/faceIdSetup');
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

  void _showToast(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.moonTheme;
    final primary = Theme.of(context).colorScheme.primary;

    final segments = [
      Segment(
        label: const Text('Student'),
        segmentStyle: SegmentStyle(
          selectedSegmentColor: primary,
          selectedTextColor: Colors.white,
          segmentBorderRadius: BorderRadius.circular(12),
          segmentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
      Segment(
        label: const Text('Homeowner'),
        segmentStyle: SegmentStyle(
          selectedSegmentColor: primary,
          selectedTextColor: Colors.white,
          segmentBorderRadius: BorderRadius.circular(12),
          segmentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    ];

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
                child: SingleChildScrollView(
                  child: Column(
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
                          if (!emailRx.hasMatch(v)) {
                            return 'Enter a valid email';
                          }
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
                            _obscurePw
                                ? Icons.visibility
                                : Icons.visibility_off,
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

                      // Role selector
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: MoonSegmentedControl(
                          isExpanded: true,
                          initialIndex: _role == 'student' ? 0 : 1,
                          segments: segments,
                          gap: 8,
                          borderRadius: BorderRadius.circular(12),
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceVariant
                              .withOpacity(0.5),
                          onSegmentChanged: (index) {
                            setState(() {
                              _role = index == 0 ? 'student' : 'homeowner';
                              if (_role != 'student') _selectedSchool = null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Student -> school selection with proper states
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _role != "student"
                            ? const SizedBox(
                                key: ValueKey("empty"),
                                height: 60,
                              )
                            : Column(
                                key: const ValueKey("student"),
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_isLoadingSchools) ...[
                                    const Center(
                                      child: Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 12),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  ] else if (_schoolsError != null) ...[
                                    MoonErrorMessage(
                                      errorText: _schoolsError!,
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: MoonTextButton(
                                        onTap: _fetchSchools,
                                        label: const Text('Retry'),
                                      ),
                                    ),
                                  ] else if (_schools.isEmpty) ...[
                                    const Text(
                                      'No schools available yet. Please contact support or try again later.',
                                      textAlign: TextAlign.left,
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: MoonTextButton(
                                        onTap: _fetchSchools,
                                        label: const Text('Refresh list'),
                                      ),
                                    ),
                                  ] else ...[
                                    DropdownButtonFormField<String>(
                                      key: const ValueKey("dropdown"),
                                      value: _selectedSchool,
                                      isExpanded: true, // better on tablets
                                      menuMaxHeight: 320,
                                      hint: const Text('Select your school'),
                                      items: _schools
                                          .map(
                                            (s) => DropdownMenuItem(
                                              value: s,
                                              child: Text(
                                                s,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (_isLoadingSchools ||
                                              _schools.isEmpty)
                                          ? null
                                          : (val) => setState(() {
                                                _selectedSchool = val;
                                              }),
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        labelText: "School",
                                      ),
                                      validator: (val) {
                                        if (_role == "student" &&
                                            (_schoolsError == null) &&
                                            _schools.isNotEmpty &&
                                            (val == null || val.isEmpty)) {
                                          return "School is required";
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                ],
                              ),
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
                            Navigator.of(context)
                                .pushReplacementNamed('/login');
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
