import 'package:cloud_firestore/cloud_firestore.dart';

class Listing {
  final String id;
  final String ownerUid;
  final double price;
  final String city;
  final String npa; // postal code as String (keeps leading zeros)
  final double latitude;
  final double longitude;
  final double surface;
  final int numRooms;
  final String type; // e.g. "entire_home" | "single_room"
  final bool isFurnish;
  final int floor;
  final bool wifiIncl;
  final bool chargesIncl;
  final bool carPark;
  final double distPublicTransportKm;
  final double proximHessoKm;
  final String nearestHessoName;
  final List<String> photos; // Storage URLs
  final DateTime createdAt;

  Listing({
    required this.id,
    required this.ownerUid,
    required this.price,
    required this.city,
    required this.npa,
    required this.latitude,
    required this.longitude,
    required this.surface,
    required this.numRooms,
    required this.type,
    required this.isFurnish,
    required this.floor,
    required this.wifiIncl,
    required this.chargesIncl,
    required this.carPark,
    required this.distPublicTransportKm,
    required this.proximHessoKm,
    required this.nearestHessoName,
    required this.photos,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'ownerUid': ownerUid,
      'price': price,
      'city': city,
      'npa': npa,
      'latitude': latitude,
      'longitude': longitude,
      'surface': surface,
      'num_rooms': numRooms,
      'type': type,
      'is_furnish': isFurnish,
      'floor': floor,
      'wifi_incl': wifiIncl,
      'charges_incl': chargesIncl,
      'car_park': carPark,
      'dist_public_transport_km': distPublicTransportKm,
      'proxim_hesso_km': proximHessoKm,
      'nearest_hesso_name': nearestHessoName,
      'photos': photos,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory Listing.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Listing(
      id: doc.id,
      ownerUid: d['ownerUid'] as String,
      price: (d['price'] as num).toDouble(),
      city: d['city'] as String,
      npa: d['npa'] as String,
      latitude: (d['latitude'] as num).toDouble(),
      longitude: (d['longitude'] as num).toDouble(),
      surface: (d['surface'] as num).toDouble(),
      numRooms: (d['num_rooms'] as num).toInt(),
      type: d['type'] as String,
      isFurnish: d['is_furnish'] as bool,
      floor: (d['floor'] as num).toInt(),
      wifiIncl: d['wifi_incl'] as bool,
      chargesIncl: d['charges_incl'] as bool,
      carPark: d['car_park'] as bool,
      distPublicTransportKm: (d['dist_public_transport_km'] as num).toDouble(),
      proximHessoKm: (d['proxim_hesso_km'] as num).toDouble(),
      nearestHessoName: (d['nearest_hesso_name'] as String),
      photos: (d['photos'] as List).cast<String>(),
      createdAt: (d['createdAt'] as Timestamp).toDate(),
    );
  }
}
