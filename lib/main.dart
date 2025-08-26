import 'package:flutter/material.dart';
// Firebase Core
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
// import 'login.dart'; 

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      // initialRoute: "/", 
      // routes: {
      //   "/": (context) => const LoginPage(), // commenté
      //   "/home": (context) => const MyHomePage(title: 'Flutter Demo Home Page'),
      // },
      home: const MyHomePage(title: 'Firebase Test Home Page'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
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

class Moon extends StatelessWidget {
  const Moon({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.yellow,
      ),
      child: const Center(
        child: Text(
          '🌙',
          style: TextStyle(fontSize: 40),
        ),
      ),
    );
  }
}
