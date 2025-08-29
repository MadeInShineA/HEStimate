enum UserRole { homeowner, student }

class AppUser {
  final String uid;
  final UserRole role;

  AppUser({required this.uid, required this.role});

  factory AppUser.fromMap(String uid, Map<String, dynamic> data) {
    final r = (data['role'] as String?)?.toLowerCase();
    return AppUser(
      uid: uid,
      role: r == 'homeowner' ? UserRole.homeowner : UserRole.student,
    );
  }

  Map<String, dynamic> toMap() => {
    'role': role.name, // 'homeowner' or 'student'
  };
}