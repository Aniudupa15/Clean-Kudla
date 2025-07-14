import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

class AllCollectedAreasMapPage extends StatefulWidget {
  const AllCollectedAreasMapPage({super.key});

  @override
  State<AllCollectedAreasMapPage> createState() => _AllCollectedAreasMapPageState();
}

class _AllCollectedAreasMapPageState extends State<AllCollectedAreasMapPage> {
  final MapController _mapController = MapController();
  List<Polyline> _routeLines = [];
  List<Marker> _houseMarkers = [];

  @override
  void initState() {
    super.initState();
    _loadTodayCompletedRoutes();
  }

  Future<void> _loadTodayCompletedRoutes() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final snapshot = await FirebaseFirestore.instance
          .collectionGroup('logs')
          .where('status', isEqualTo: 'completed')
          .where('endedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('endedAt', isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      final List<Polyline> loadedPolylines = [];
      final List<Marker> loadedMarkers = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();

        final pathList = (data['path'] as List<dynamic>?) ?? [];
        final houseList = (data['housesVisited'] as List<dynamic>?) ?? [];

        final points = pathList.map((e) => LatLng(e['lat'], e['lng'])).toList();
        final houses = houseList.map((e) => LatLng(e['lat'], e['lng'])).toList();

        if (points.isNotEmpty) {
          loadedPolylines.add(
            Polyline(
              points: points,
              strokeWidth: 3,
              color: Colors.green,
            ),
          );
        }

        loadedMarkers.addAll(
          houses.map((point) => Marker(
            point: point,
            width: 25,
            height: 25,
            child: const Icon(Icons.home, color: Colors.orange),
          )),
        );
      }

      setState(() {
        _routeLines = loadedPolylines;
        _houseMarkers = loadedMarkers;
      });
    } catch (e) {
      print("Error loading completed routes: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Failed to load routes: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("All Collected Areas (Today)"),
        backgroundColor: Colors.green.shade800,
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: const LatLng(12.9141, 74.8560),
          initialZoom: 13,
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
        ),
        children: [
          TileLayer(
            urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
            userAgentPackageName: "com.example.clean_kudla",
          ),
          PolylineLayer(polylines: _routeLines),
          MarkerLayer(markers: _houseMarkers),
        ],
      ),
    );
  }
}