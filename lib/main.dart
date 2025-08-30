import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';

// Moon Design
import 'package:moon_design/moon_design.dart';

// Your UI pages
import 'ui/property_list.dart';
import 'ui/new_listing_page.dart';
import 'ui/register.dart';
import 'ui/login.dart';
import 'ui/profile.dart';
import 'ui/about_page.dart';
import 'ui/faceIdLogin.dart';
import 'ui/faceIdSetup.dart';
import 'ui/menu.dart';
import 'ui/not_allowed.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final currentUser = FirebaseAuth.instance.currentUser;

  bool faceIdEnabled = false;
  File? faceImage;

  if (currentUser != null) {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();
    if (doc.exists) {
      faceIdEnabled = doc.data()?['faceIdEnabled'] ?? false;
      if (faceIdEnabled) {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/face_id.png');
        if (await file.exists()) {
          faceImage = file;
        } else {
          faceIdEnabled = false;
        }
      }
    }
  }

  runApp(
    MyApp(
      initialUser: currentUser,
      faceIdEnabled: faceIdEnabled,
      faceImage: faceImage,
    ),
  );
}

class MyApp extends StatefulWidget {
  final User? initialUser;
  final bool faceIdEnabled;
  final File? faceImage;

  const MyApp({
    super.key,
    this.initialUser,
    required this.faceIdEnabled,
    this.faceImage,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  Future<bool> _checkHomeowner() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return false;
    final d = await FirebaseFirestore.instance.collection('users').doc(u.uid).get();
    final role = (d.data()?['role'] as String?)?.toLowerCase();
    return role == 'homeowner';
  }

  @override
  Widget build(BuildContext context) {
    final lightTokens = MoonTokens.light;
    final darkTokens = MoonTokens.dark;

    final baseLight = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      useMaterial3: true,
    );
    final baseDark = ThemeData(
      colorScheme: const ColorScheme.dark().copyWith(
        primary: Colors.deepPurple,
        secondary: Colors.deepPurpleAccent,
      ),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'HEStimate App',
      themeMode: _themeMode,
      theme: baseLight.copyWith(extensions: [MoonTheme(tokens: lightTokens)]),
      darkTheme: baseDark.copyWith(extensions: [MoonTheme(tokens: darkTokens)]),
      initialRoute: widget.initialUser == null
          ? '/login'
          : (widget.faceIdEnabled ? '/faceLogin' : '/home'),
      routes: {
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/faceIdSetup': (context) => const FaceIdSetupPage(),
        // HomeMenuPage lit le rôle en live (voir menu.dart)
        '/home': (context) => HomeMenuPage(onToggleTheme: _toggleTheme),

        '/profile': (context) => const ProfilePage(),
        '/faceLogin': (context) => FaceIdLoginPage(
              faceImage: widget.faceImage,
              user: widget.initialUser,
            ),

        // Routes protégées : on re-vérifie Firestore à chaque ouverture
        '/listings': (context) => FutureBuilder<bool>(
              future: _checkHomeowner(),
              builder: (ctx, snap) =>
                  (snap.data ?? false) ? const ListingsPage() : const NotAllowedPage(),
            ),
        '/newListing': (context) => FutureBuilder<bool>(
              future: _checkHomeowner(),
              builder: (ctx, snap) =>
                  (snap.data ?? false) ? const NewListingPage() : const NotAllowedPage(),
            ),

        '/about': (context) => const AboutPage(),
      },
      debugShowCheckedModeBanner: false,
    );
  }

  class MyApp extends StatefulWidget {
    final User? initialUser;
    final bool faceIdEnabled;
    final File? faceImage;

    const MyApp({
      super.key,
      this.initialUser,
      required this.faceIdEnabled,
      this.faceImage,
    });

    @override
    State<MyApp> createState() => _MyAppState();
  }

  class _MyAppState extends State<MyApp> {
    ThemeMode _themeMode = ThemeMode.system;

    void _toggleTheme() {
      setState(() {
        _themeMode = _themeMode == ThemeMode.dark
            ? ThemeMode.light
            : ThemeMode.dark;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valeur ajoutée à Firebase !')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }

  Future<void> _removeValue() async {
    try {
      await _firestore.collection('test_collection').doc('counter_doc').delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valeur supprimée de Firebase !')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => Navigator.of(context).pushNamed('/profile'),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton.icon(
              icon: const Icon(Icons.add_business),
              label: const Text("Go to Property List"),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ListingsPage()),
                );
              },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_business),
              label: const Text("Go to New Listing"),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NewListingPage()),
                );
              },
            ),
            const Text('Counter:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            MoonButton(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutPage()),
              ),
              leading: const Icon(MoonIcons.arrows_forward_24_regular),
              label: const Text('About'),
            ),
            ElevatedButton(
              onPressed: _addValue,
              child: const Text('Ajouter à Firebase'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _removeValue,
              child: const Text('Supprimer de Firebase'),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
