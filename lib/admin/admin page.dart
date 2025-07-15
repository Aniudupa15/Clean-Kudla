import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class AdminRoute extends StatefulWidget {
  const AdminRoute({super.key});

  @override
  State<AdminRoute> createState() => _AdminRouteState();
}

class _AdminRouteState extends State<AdminRoute> {
  // Helper function to get worker's full name
  Future<String> _getWorkerFullName(String uid) async {
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (userDoc.exists) {
        return (userDoc.data() as Map<String, dynamic>?)?['fullName'] as String? ?? 'Unknown Collector';
      }
      return 'Collector Not Found';
    } catch (e) {
      print("Error fetching worker name for $uid: $e");
      return 'Error Fetching Name';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Panel - Live Routes"),
        backgroundColor: Colors.blueAccent, // Admin app bar color
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('admin_ongoing_routes').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No ongoing routes found.'));
          }

          final ongoingRoutes = snapshot.data!.docs;

          return ListView.builder(
            itemCount: ongoingRoutes.length,
            itemBuilder: (context, index) {
              final routeData = ongoingRoutes[index].data() as Map<String, dynamic>;
              final String uid = routeData['workerUid'] ?? 'N/A'; // Corrected to workerUid as per previous context
              final String routeId = routeData['routeId'] ?? 'N/A';
              final Timestamp lastUpdated = routeData['lastUpdated'] ?? Timestamp.now();
              final String lastUpdatedString = lastUpdated.toDate().toLocal().toString().split('.')[0];

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: FutureBuilder<String>(
                  future: _getWorkerFullName(uid), // Fetch worker's name
                  builder: (context, nameSnapshot) {
                    String collectorName = nameSnapshot.data ?? 'Loading Name...';
                    if (nameSnapshot.connectionState == ConnectionState.waiting) {
                      collectorName = 'Loading Name...';
                    } else if (nameSnapshot.hasError) {
                      collectorName = 'Error Name';
                    }

                    return ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(
                        'Collector: $collectorName', // Display collector's name
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('Route ID: ${routeId.substring(0, 8)}...'), // Shorten Route ID for display
                          Text('Last Updated: $lastUpdatedString'),
                          Text('Houses Visited: ${(routeData['currentHousesVisited'] as List?)?.length ?? 0}'),
                        ],
                      ),
                      trailing: const Icon(Icons.map, color: Colors.green),
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          '/route_details',
                          arguments: {
                            'routeId': routeId,
                            'uid': uid, // Pass UID to fetch name in details page too
                          },
                        );
                      },
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// RouteDetailsPage Widget

class RouteDetailsPage extends StatefulWidget {
  final String routeId;
  final String uid; // Added UID to retrieve collector name

  const RouteDetailsPage({super.key, required this.routeId, required this.uid});

  @override
  State<RouteDetailsPage> createState() => _RouteDetailsPageState();
}

class _RouteDetailsPageState extends State<RouteDetailsPage> {
  final MapController _mapController = MapController();
  late Future<String> _collectorNameFuture; // Future to hold the collector's name

  @override
  void initState() {
    super.initState();
    _collectorNameFuture = _getWorkerFullName(widget.uid); // Initialize the future
  }

  // Helper function to get worker's full name (duplicated for clarity, can be shared)
  Future<String> _getWorkerFullName(String uid) async {
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (userDoc.exists) {
        return (userDoc.data() as Map<String, dynamic>?)?['fullName'] as String? ?? 'Unknown Collector';
      }
      return 'Collector Not Found';
    } catch (e) {
      print("Error fetching worker name for $uid: $e");
      return 'Error Fetching Name';
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Use FutureBuilder to display collector's name in AppBar title
        title: FutureBuilder<String>(
          future: _collectorNameFuture,
          builder: (context, snapshot) {
            String collectorName = snapshot.data ?? 'Loading...';
            if (snapshot.connectionState == ConnectionState.waiting) {
              collectorName = 'Loading Collector...';
            } else if (snapshot.hasError) {
              collectorName = 'Error Collector';
            }
            return Text("Route: ${widget.routeId.substring(0, 8)}... by $collectorName");
          },
        ),
        backgroundColor: Colors.blueAccent, // Admin app bar color
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('admin_ongoing_routes')
            .doc(widget.routeId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Route not found or no longer ongoing.'));
          }

          final routeData = snapshot.data!.data() as Map<String, dynamic>;
          final List<LatLng> currentPath = (routeData['currentPath'] as List<dynamic>?)
              ?.map((e) => LatLng(e['latitude'] as double, e['longitude'] as double))
              .toList() ?? [];
          final List<LatLng> currentHousesVisited = (routeData['currentHousesVisited'] as List<dynamic>?)
              ?.map((e) => LatLng(e['latitude'] as double, e['longitude'] as double))
              .toList() ?? [];

          // Optionally, add a marker for the current worker's location if available in routeData
          LatLng? workerLocation;
          if (currentPath.isNotEmpty) {
            workerLocation = currentPath.last;
          }

          final routePolyline = Polyline<Object>(
            points: currentPath,
            strokeWidth: 4.0,
            color: Colors.blue, // Different color for admin view
          );

          final List<Marker> houseMarkers = currentHousesVisited.map(
                (point) => Marker(
              width: 30,
              height: 30,
              point: point,
              child: const Icon(Icons.home, color: Colors.red), // Different color for admin view
            ),
          ).toList();

          List<Marker> allMarkers = [...houseMarkers];
          if (workerLocation != null) {
            allMarkers.add(Marker(
              width: 40,
              height: 40,
              point: workerLocation,
              child: const Icon(Icons.directions_walk, color: Colors.purple, size: 35), // Worker's current location
            ));
          }


          // Determine initial map center and zoom
          LatLng initialCenter = LatLng(12.9141, 74.8560); // Default to Mangaluru
          double initialZoom = 12;

          if (currentPath.isNotEmpty) {
            initialCenter = currentPath.last;
            initialZoom = 16;
          } else if (currentHousesVisited.isNotEmpty) {
            initialCenter = currentHousesVisited.last;
            initialZoom = 16;
          }


          return FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: initialZoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.clean_kudla',
              ),
              PolylineLayer(polylines: currentPath.isNotEmpty ? [routePolyline] : <Polyline<Object>>[]),
              MarkerLayer(markers: allMarkers), // Display all markers
            ],
          );
        },
      ),
    );
  }
}