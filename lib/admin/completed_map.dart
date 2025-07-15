import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

// Define UserLocation class if not already globally available
// (If you have this in a shared file like main.dart, you can remove this definition
// and instead import it, e.g., `import 'package:your_app_name/models/user_location.dart';`
// or `import 'package:your_app_name/main.dart';` if defined there.)
class UserLocation {
  final String uid;
  final LatLng location;
  final Map<String, dynamic> collectedByRoutes; // Map to track collection by routeId

  UserLocation({
    required this.uid,
    required this.location,
    this.collectedByRoutes = const {},
  });

  factory UserLocation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw Exception("Document data is null for user ${doc.id}");
    }
    final double? lat = (data['latitude'] as num?)?.toDouble();
    final double? lng = (data['longitude'] as num?)?.toDouble();

    if (lat == null || lng == null) {
      // Handle cases where lat/lng might be missing or null
      // For this context, we'll throw an error or return a default/skip
      print("Warning: Missing or invalid latitude/longitude for user ${doc.id}");
      // Returning a default LatLng for robust behavior, but ideally data should be consistent.
      return UserLocation(uid: doc.id, location: const LatLng(0, 0));
    }

    return UserLocation(
      uid: doc.id,
      location: LatLng(lat, lng),
      collectedByRoutes: (data['collectedByRoutes'] as Map<String, dynamic>?)?.cast<String, dynamic>() ?? {},
    );
  }
}


class AllCollectedAreasMapPage extends StatefulWidget {
  const AllCollectedAreasMapPage({super.key});

  @override
  State<AllCollectedAreasMapPage> createState() => _AllCollectedAreasMapPageState();
}

class _AllCollectedAreasMapPageState extends State<AllCollectedAreasMapPage> {
  final MapController _mapController = MapController();
  List<Polyline> _routeLines = [];
  List<Marker> _allHouseMarkers = []; // This will now hold all house markers (collected/not)

  @override
  void initState() {
    super.initState();
    _loadMapData(); // Call a single function to load all necessary map data
  }

  Future<void> _loadMapData() async {
    try {
      // --- 1. Load Today's Completed Routes (Polylines) ---
      final now = DateTime.now();
      // Start of today in local time (adjust to UTC if your Firestore timestamps are UTC)
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final routesSnapshot = await FirebaseFirestore.instance
          .collectionGroup('logs') // Queries all 'logs' subcollections
          .where('status', isEqualTo: 'completed')
          .where('endedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('endedAt', isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      final List<Polyline> loadedPolylines = [];
      for (var doc in routesSnapshot.docs) {
        final data = doc.data();
        // Ensure the keys for latitude and longitude in 'path' list are 'lat' and 'lng'
        final pathList = (data['path'] as List<dynamic>?) ?? [];
        final points = pathList.map((e) => LatLng(e['lat'], e['lng'])).toList();

        if (points.isNotEmpty) {
          loadedPolylines.add(
            Polyline(
              points: points,
              strokeWidth: 3,
              color: Colors.green, // Color for today's completed routes
            ),
          );
        }
      }

      // --- 2. Load All Houses (Users) and differentiate by collection status ---
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('userType', isEqualTo: 'user') // Assuming 'userType' field exists to identify houses
          .get();

      final List<Marker> allHousesMarkers = [];
      for (var doc in usersSnapshot.docs) {
        try {
          final userLocation = UserLocation.fromFirestore(doc);
          // A house is considered 'collected' if its collectedByRoutes map is not empty
          final bool isCollected = userLocation.collectedByRoutes.isNotEmpty;

          allHousesMarkers.add(
            Marker(
              point: userLocation.location,
              width: 30,
              height: 30,
              child: Icon(
                Icons.home,
                // Use different colors for collected vs. not collected
                color: isCollected ? Colors.blue : Colors.red, // Blue for collected, Red for not collected
                size: 25,
              ),
            ),
          );
        } catch (e) {
          print("Error processing user document ${doc.id}: $e");
          // Optionally, you could add a special marker for problematic data or skip.
        }
      }

      setState(() {
        _routeLines = loadedPolylines;
        _allHouseMarkers = allHousesMarkers; // Update state with all new house markers
      });

    } catch (e) {
      print("Error loading map data: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Failed to load map data: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Collected Areas & All Houses"),
        backgroundColor: Colors.green.shade800,
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: const LatLng(12.9141, 74.8560), // Default to Mangaluru
          initialZoom: 13,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
        ),
        children: [
          TileLayer(
            urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
            userAgentPackageName: "com.example.clean_kudla",
          ),
          PolylineLayer(polylines: _routeLines), // Today's completed routes
          MarkerLayer(markers: _allHouseMarkers), // All houses (collected/not)
        ],
      ),
    );
  }
}