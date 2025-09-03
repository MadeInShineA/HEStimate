import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminPage extends StatefulWidget {
  @override
  _AdminPageState createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  bool _isAdmin = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAdminRole();
  }

  Future<void> _checkAdminRole() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser != null) {
        DocumentSnapshot userDoc = await _firestore
            .collection('users')
            .doc(currentUser.uid)
            .get();
        
        if (userDoc.exists && userDoc.data() != null) {
          Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
          setState(() {
            _isAdmin = userData['role'] == 'admin';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Erreur lors de la vérification du rôle admin: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('Administration')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(title: Text('Accès refusé')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'Vous n\'avez pas les droits d\'administration',
                style: TextStyle(fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Administration - Gestion Utilisateurs'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erreur: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          List<DocumentSnapshot> users = snapshot.data!.docs;

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              Map<String, dynamic> userData = users[index].data() as Map<String, dynamic>;
              String userId = users[index].id;

              return Card(
                margin: EdgeInsets.all(8.0),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getRoleColor(userData['role']),
                    child: Icon(
                      _getRoleIcon(userData['role']),
                      color: Colors.white,
                    ),
                  ),
                  title: Text(userData['name'] ?? 'Nom non défini'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Email: ${userData['email'] ?? 'Email non défini'}'),
                      Text('École: ${userData['school'] ?? 'École non définie'}'),
                      Text('Face ID: ${userData['faceIdEnabled'] == true ? 'Activé' : 'Désactivé'}'),
                      if (userData['createdAt'] != null)
                        Text('Créé le: ${_formatDate(userData['createdAt'])}'),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) => _handleUserAction(value, userId, userData),
                    itemBuilder: (BuildContext context) => [
                      PopupMenuItem(
                        value: 'edit_role',
                        child: Row(
                          children: [
                            Icon(Icons.admin_panel_settings, size: 20),
                            SizedBox(width: 8),
                            Text('Changer le rôle'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle_face_id',
                        child: Row(
                          children: [
                            Icon(Icons.face, size: 20),
                            SizedBox(width: 8),
                            Text(userData['faceIdEnabled'] == true 
                                ? 'Désactiver Face ID' 
                                : 'Activer Face ID'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Supprimer', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'admin':
        return Colors.red;
      case 'teacher':
        return Colors.blue;
      case 'student':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getRoleIcon(String? role) {
    switch (role) {
      case 'admin':
        return Icons.admin_panel_settings;
      case 'teacher':
        return Icons.school;
      case 'student':
        return Icons.person;
      default:
        return Icons.help;
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Date inconnue';
    
    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else {
        return timestamp.toString();
      }
      
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Date invalide';
    }
  }

  Future<void> _handleUserAction(String action, String userId, Map<String, dynamic> userData) async {
    switch (action) {
      case 'edit_role':
        _showRoleDialog(userId, userData['role']);
        break;
      case 'toggle_face_id':
        _toggleFaceId(userId, userData['faceIdEnabled'] == true);
        break;
      case 'delete':
        _showDeleteDialog(userId, userData['name']);
        break;
    }
  }

  void _showRoleDialog(String userId, String currentRole) {
    String selectedRole = currentRole;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Changer le rôle'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    title: Text('Étudiant'),
                    value: 'student',
                    groupValue: selectedRole,
                    onChanged: (value) => setState(() => selectedRole = value!),
                  ),
                  RadioListTile<String>(
                    title: Text('Professeur'),
                    value: 'teacher',
                    groupValue: selectedRole,
                    onChanged: (value) => setState(() => selectedRole = value!),
                  ),
                  RadioListTile<String>(
                    title: Text('Administrateur'),
                    value: 'admin',
                    groupValue: selectedRole,
                    onChanged: (value) => setState(() => selectedRole = value!),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _updateUserRole(userId, selectedRole);
                    Navigator.pop(context);
                  },
                  child: Text('Confirmer'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateUserRole(String userId, String newRole) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'role': newRole,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rôle mis à jour avec succès')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la mise à jour: $e')),
      );
    }
  }

  Future<void> _toggleFaceId(String userId, bool currentState) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'faceIdEnabled': !currentState,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Face ID ${!currentState ? 'activé' : 'désactivé'}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la mise à jour: $e')),
      );
    }
  }

  void _showDeleteDialog(String userId, String? userName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Confirmer la suppression'),
          content: Text('Êtes-vous sûr de vouloir supprimer l\'utilisateur "${userName ?? 'Inconnu'}" ?\n\nCette action est irréversible.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Annuler'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                await _deleteUser(userId);
                Navigator.pop(context);
              },
              child: Text('Supprimer', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteUser(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Utilisateur supprimé avec succès')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la suppression: $e')),
      );
    }
  }
}
