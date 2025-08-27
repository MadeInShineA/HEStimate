import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'firebase_options.dart';
import 'register.dart';
import 'login.dart';
import 'profile.dart';
import 'ui/about_page.dart';
import 'faceIdLogin.dart';
import 'package:moon_design/moon_design.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final currentUser = FirebaseAuth.instance.currentUser;

  // Vérification si Face ID est activé
  bool faceIdEnabled = false;
  File? faceImage;

  if (currentUser != null) {
    final doc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
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

  runApp(MyApp(
    initialUser: currentUser,
    faceIdEnabled: faceIdEnabled,
    faceImage: faceImage,
  ));
}

class MyApp extends StatelessWidget {
  final User? initialUser;
  final bool faceIdEnabled;
  final File? faceImage;

  const MyApp({super.key, this.initialUser, required this.faceIdEnabled, this.faceImage});

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
      theme: baseLight.copyWith(extensions: [MoonTheme(tokens: lightTokens)]),
      darkTheme: baseDark.copyWith(extensions: [MoonTheme(tokens: darkTokens)]),
      initialRoute: initialUser == null
          ? '/login'
          : (faceIdEnabled ? '/faceLogin' : '/home'),
      routes: {
        '/login': (context) => LoginPage(faceImage: faceImage),
        '/register': (context) => const RegisterPage(),
        '/home': (context) => const MyHomePage(title: 'Firebase Test Home Page'),
        '/profile': (context) => const ProfilePage(),
        '/faceLogin': (context) => FaceIdLoginPage(faceImage: faceImage, user: initialUser),
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int _counter = 0;

  Future<void> _addValue() async {
    try {
      await _firestore.collection('test_collection').doc('counter_doc').set({
        'counter': _counter,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valeur ajoutée à Firebase !')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _removeValue() async {
    try {
      await _firestore.collection('test_collection').doc('counter_doc').delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valeur supprimée de Firebase !')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
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
            onPressed: () {
              Navigator.of(context).pushNamed('/profile');
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('Counter:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            MoonButton(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutPage())),
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
