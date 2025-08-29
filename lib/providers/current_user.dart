import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../services/user_service.dart';

class CurrentUser extends ChangeNotifier {
  final UserService _svc;
  CurrentUser(this._svc);

  AppUser? _user;
  AppUser? get user => _user;
  bool get isHomeowner => _user?.role == UserRole.homeowner;

  Future<void> load(String uid) async {
    _user = await _svc.getUser(uid);
    notifyListeners();
  }
}