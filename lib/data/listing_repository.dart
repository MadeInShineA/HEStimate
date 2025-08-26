import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ListingRepository {
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  Future<List<String>> uploadListingImages({
    required String ownerUid,
    required String listingId,
    required List<File> files,
  }) async {
    final List<String> urls = [];
    for (int i = 0; i < files.length; i++) {
      final ref = _storage
          .ref()
          .child('listings')
          .child(ownerUid)
          .child(listingId)
          .child('img_$i.jpg');

      final task = await ref.putFile(files[i]);
      final url = await task.ref.getDownloadURL();
      urls.add(url);
    }
    return urls;
  }

  Future<String> createListing(Map<String, dynamic> data) async {
    final doc = await _db.collection('listings').add(data);
    return doc.id;
  }

  Future<void> attachOwner(String listingId, String ownerUid) {
    return _db.collection('listings').doc(listingId).update({'ownerUid': ownerUid});
  }
}
