import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';

// Global variables for background service
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
const String isolatePortName = 'location_service_port';

// Data model for a user location (from Firestore)
class UserLocation {
  final String uid;
  final String email;
  final LatLng location; // This stores the geographical coordinates
  final int points;
  final Map<String, dynamic> collectedByRoutes; // Map to track collection by routeId
  final String fullName; // Added to display in marker if needed

  UserLocation({
    required this.uid,
    required this.email,
    required this.location,
    this.points = 0,
    this.collectedByRoutes = const {},
    this.fullName = 'Unknown',
  });

  factory UserLocation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw Exception("Document data is null for user ${doc.id}");
    }
    final double? lat = (data['latitude'] as num?)?.toDouble();
    final double? lng = (data['longitude'] as num?)?.toDouble();

    if (lat == null || lng == null) {
      throw Exception("Missing or invalid latitude/longitude for user ${doc.id}");
    }

    return UserLocation(
      uid: doc.id,
      email: data['email'] as String? ?? 'No Email',
      location: LatLng(lat, lng),
      points: (data['points'] as num?)?.toInt() ?? 0,
      collectedByRoutes: (data['collectedByRoutes'] as Map<String, dynamic>?) ?? {},
      fullName: data['fullName'] as String? ?? 'User',
    );
  }
}

class WorkerPage extends StatefulWidget {
  const WorkerPage({super.key});

  @override
  State<WorkerPage> createState() => _WorkerPageState();
}

class _WorkerPageState extends State<WorkerPage> {
  final MapController _mapController = MapController();
  bool _isTracking = false;
  List<LatLng> _routePoints = [];
  List<LatLng> _markedHouses = [];
  String? _routeId;
  String? _uid;
  String? _workerFullName; // Store worker's full name for passing to background
  final Distance _distance = const Distance();
  ReceivePort? _receivePort;

  Stream<List<UserLocation>>? _allUsersStream;
  List<UserLocation> _allUsers = [];

  LatLng? _currentWorkerLocation;


  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _initializeNotifications();
    _checkLocationPermission();
    _fetchWorkerFullName(); // Fetch worker's name on init
    _setupBackgroundService();
    _setupAllUsersStream();
  }

  Future<void> _fetchWorkerFullName() async {
    if (_uid != null) {
      try {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
        if (userDoc.exists) {
          setState(() {
            _workerFullName = (userDoc.data() as Map<String, dynamic>?)?['fullName'] as String?;
          });
          print("Worker Full Name fetched: $_workerFullName"); // Debug print
        }
      } catch (e) {
        print("Error fetching worker full name: $e");
      }
    }
  }

  void _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
    InitializationSettings(android: AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    ));

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    await Permission.notification.request();
  }

  void _setupBackgroundService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'location_tracking',
        initialNotificationTitle: 'Clean Kudla',
        initialNotificationContent: 'Location tracking is running',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    _receivePort = ReceivePort();
    IsolateNameServer.registerPortWithName(_receivePort!.sendPort, isolatePortName);

    _receivePort!.listen((dynamic data) {
      if (data is Map<String, dynamic>) {
        if (data['type'] == 'location_update') {
          final lat = data['latitude'] as double;
          final lng = data['longitude'] as double;
          final point = LatLng(lat, lng);

          setState(() {
            _routePoints.add(point);
            _currentWorkerLocation = point;

            final alreadyMarked = _markedHouses.any(
                  (existing) => _distance.as(LengthUnit.Meter, existing, point) < 5,
            );

            if (!alreadyMarked) {
              _markedHouses.add(point);
              _showNotification("🏠 Worker path house marked automatically");
            }
          });

          if (_isTracking && _routePoints.isNotEmpty) {
            _mapController.move(point, 17);
          }
        } else if (data['type'] == 'current_state') {
          setState(() {
            _isTracking = data['isTracking'] as bool;
            _routeId = data['routeId'] as String?;
            _routePoints = (data['routePoints'] as List<dynamic>)
                .map((e) => LatLng(e['latitude'] as double, e['longitude'] as double))
                .toList();
            _markedHouses = (data['markedHouses'] as List<dynamic>)
                .map((e) => LatLng(e['latitude'] as double, e['longitude'] as double))
                .toList();
            if (_routePoints.isNotEmpty) {
              _currentWorkerLocation = _routePoints.last;
            }
          });
          if (_routePoints.isNotEmpty) {
            _mapController.move(_routePoints.last, 17);
          }
          _showSnackbar("🔄 Re-synced with background tracking.");
        } else if (data['type'] == 'user_collected_notification') {
          final collectedUserFullName = data['fullName'] as String? ?? 'A user';
          final collectedUserEmail = data['email'] as String? ?? 'No email';
          _showNotification("✅ Collected: $collectedUserFullName ($collectedUserEmail)! (+10 points)");
        }
      }
    });

    if (await service.isRunning()) {
      service.invoke('request_current_state');
    }
  }

  void _setupAllUsersStream() {
    _allUsersStream = FirebaseFirestore.instance
        .collection('users')
        .where('userType', isEqualTo: 'user')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => UserLocation.fromFirestore(doc)).toList());

    _allUsersStream?.listen((users) {
      setState(() {
        _allUsers = users;
      });
      if (_isTracking && _routePoints.isNotEmpty) {
        _mapController.move(_routePoints.last, _mapController.camera.zoom);
      } else if (_allUsers.isNotEmpty && _currentWorkerLocation == null) {
        _mapController.move(_allUsers.first.location, _mapController.camera.zoom);
      }
    });
  }


  void _checkLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackbar("📍 Location permission is required.");
      }
    } else if (permission == LocationPermission.deniedForever) {
      _showSnackbar("🚫 Location permissions are permanently denied.");
    }

    await Permission.locationAlways.request();
  }

  @override
  void dispose() {
    _receivePort?.close();
    IsolateNameServer.removePortNameMapping(isolatePortName);
    super.dispose();
  }

  void _startTracking() async {
    if (_uid == null) {
      _showSnackbar("❌ User not authenticated");
      return;
    }
    if (_workerFullName == null) {
      _showSnackbar("⏳ Worker name not loaded yet. Please wait a moment.");
      await _fetchWorkerFullName(); // Try fetching again
      if (_workerFullName == null) {
        _showSnackbar("❌ Could not get worker name. Cannot start tracking.");
        return;
      }
    }


    final hasPermission = await Geolocator.checkPermission();
    if (hasPermission == LocationPermission.denied || hasPermission == LocationPermission.deniedForever) {
      _checkLocationPermission();
      return;
    }

    Position position = await Geolocator.getCurrentPosition();
    final startPoint = LatLng(position.latitude, position.longitude);

    setState(() {
      _isTracking = true;
      _routeId = const Uuid().v4();
      _routePoints = [startPoint];
      _markedHouses = [startPoint];
      _currentWorkerLocation = startPoint;
    });

    final routeRef = FirebaseFirestore.instance
        .collection('routes')
        .doc(_uid)
        .collection('logs')
        .doc(_routeId);

    // Initial write to worker's log, including workerName
    await routeRef.set({
      'startedAt': FieldValue.serverTimestamp(),
      'status': 'ongoing',
      'routeId': _routeId,
      'workerUid': _uid,
      'workerName': _workerFullName, // Store worker's name here
    });

    // Initial write to admin_ongoing_routes
    final adminRouteRef = FirebaseFirestore.instance
        .collection('admin_ongoing_routes')
        .doc(_routeId);
    await adminRouteRef.set({
      'workerUid': _uid,
      'workerName': _workerFullName, // Store worker's name for admin view
      'routeId': _routeId,
      'currentPath': [_mapToGeoPoint(startPoint)], // Convert LatLng to GeoPoint for Firestore
      'currentHousesVisited': [_mapToGeoPoint(startPoint)],
      'lastUpdated': FieldValue.serverTimestamp(),
      'status': 'ongoing',
    }, SetOptions(merge: true));


    final service = FlutterBackgroundService();
    await service.startService();

    service.invoke('start_tracking', {
      'uid': _uid,
      'routeId': _routeId,
      'initialRoutePoints': _routePoints.map((p) => {'latitude': p.latitude, 'longitude': p.longitude}).toList(),
      'initialMarkedHouses': _markedHouses.map((p) => {'latitude': p.latitude, 'longitude': p.longitude}).toList(),
      'allUsers': _allUsers.map((u) => {
        'uid': u.uid,
        'email': u.email,
        'latitude': u.location.latitude,
        'longitude': u.location.longitude,
        'points': u.points,
        'collectedByRoutes': u.collectedByRoutes,
        'fullName': u.fullName,
      }).toList(),
      'workerFullName': _workerFullName, // Pass worker's full name to background service
    });

    _showSnackbar("🟢 Tracking started. Move to auto-mark houses and collect users.");
    _showNotification("🟢 Collection tracking started");
  }

  // Helper to convert LatLng to GeoPoint for Firestore
  Map<String, double> _mapToGeoPoint(LatLng point) {
    return {'latitude': point.latitude, 'longitude': point.longitude};
  }


  void _stopTracking() async {
    final service = FlutterBackgroundService();
    service.invoke('stop_tracking');
    service.invoke('stopService');

    if (_uid == null || _routeId == null) return;

    final routeRef = FirebaseFirestore.instance
        .collection('routes')
        .doc(_uid)
        .collection('logs')
        .doc(_routeId);

    // Final update to worker's log
    try {
      await routeRef.set({
        'endedAt': FieldValue.serverTimestamp(),
        'status': 'completed',
        'path': _routePoints.map((e) => {'lat': e.latitude, 'lng': e.longitude}).toList(),
        'housesVisited': _markedHouses.map((e) => {
          'lat': e.latitude,
          'lng': e.longitude,
          'timestamp': Timestamp.now(),
        }).toList(),
      }, SetOptions(merge: true));

      // Final update to admin_ongoing_routes (to remove or mark completed)
      final adminRouteRef = FirebaseFirestore.instance
          .collection('admin_ongoing_routes')
          .doc(_routeId);
      // Option 1: Delete from admin_ongoing_routes (if only truly ongoing routes are shown)
      await adminRouteRef.delete();
      // Option 2: Update status to 'completed' (if you want history in this collection)
      // await adminRouteRef.update({'status': 'completed', 'endedAt': FieldValue.serverTimestamp()});


      _showSnackbar("✅ Route completed and uploaded.");
      _showNotification("✅ Collection route completed");

      setState(() {
        _isTracking = false;
        _routeId = null;
        _routePoints = [];
        _markedHouses = [];
        _currentWorkerLocation = null;
      });

    } catch (e) {
      _showSnackbar("❌ Error saving route: $e");
    }
  }

  void _showSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  void _showNotification(String message) async {
    const AndroidNotificationDetails androidNotificationDetails =
    AndroidNotificationDetails(
      'location_tracking',
      'Location Tracking',
      channelDescription: 'Notifications for location tracking',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails notificationDetails =
    NotificationDetails(android: androidNotificationDetails);

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Clean Kudla',
      message,
      notificationDetails,
    );
  }

  @override
  Widget build(BuildContext context) {
    final routePolyline = Polyline<Object>(
      points: _routePoints,
      strokeWidth: 4.0,
      color: Colors.green,
    );

    final List<Marker> workerPathHouseMarkers = _markedHouses.map(
          (point) => Marker(
        width: 30,
        height: 30,
        point: point,
        child: const Icon(Icons.location_on, color: Colors.blueAccent),
      ),
    ).toList();

    Marker? workerCurrentLocationMarker;
    if (_currentWorkerLocation != null) {
      workerCurrentLocationMarker = Marker(
        width: 40,
        height: 40,
        point: _currentWorkerLocation!,
        child: const Icon(Icons.directions_walk, color: Colors.purple, size: 35),
      );
    }

    final List<Marker> allUsersMarkers = _allUsers.map(
          (user) {
        final bool isCollectedOnCurrentRoute = _routeId != null && user.collectedByRoutes.containsKey(_routeId);

        bool isCurrentlyNearByThisWorker = false;
        if (_currentWorkerLocation != null) {
          final double distanceToUser = _distance.as(LengthUnit.Meter, _currentWorkerLocation!, user.location);
          if (distanceToUser < 5) {
            isCurrentlyNearByThisWorker = true;
          }
        }

        IconData iconData = Icons.person_pin;
        Color iconColor = Colors.grey;

        if (isCurrentlyNearByThisWorker) {
          iconData = Icons.person_add_alt_1;
          iconColor = Colors.orange;
        } else if (isCollectedOnCurrentRoute) {
          iconData = Icons.check_circle;
          iconColor = Colors.green;
        } else if (user.collectedByRoutes.isNotEmpty) {
          iconData = Icons.person_pin;
          iconColor = Colors.blue;
        } else {
          iconData = Icons.person_pin_circle;
          iconColor = Colors.red;
        }

        return Marker(
          width: 50,
          height: 50,
          point: user.location,
          child: Column(
            children: [
              Icon(iconData, color: iconColor, size: 30),
              Text(
                user.fullName.split(' ')[0],
                style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                    shadows: [
                      Shadow(blurRadius: 2, color: Colors.black54),
                    ]
                ),
              ),
            ],
          ),
        );
      },
    ).toList();

    List<Marker> allMapMarkers = [
      ...workerPathHouseMarkers,
      ...allUsersMarkers,
    ];
    if (workerCurrentLocationMarker != null) {
      allMapMarkers.add(workerCurrentLocationMarker);
    }


    return Scaffold(
      appBar: AppBar(
        title: const Text("Clean Kudla – Worker"),
        backgroundColor: Colors.green.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              _showSnackbar("🕒 History view not implemented yet.");
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentWorkerLocation ?? (_routePoints.isNotEmpty ? _routePoints.last : LatLng(12.9141, 74.8560)),
              initialZoom: 16,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.clean_kudla',
              ),
              PolylineLayer(polylines: _routePoints.isNotEmpty ? [routePolyline] : <Polyline<Object>>[]),
              MarkerLayer(markers: allMapMarkers),
            ],
          ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              children: [
                if (!_isTracking)
                  ElevatedButton.icon(
                    onPressed: _startTracking,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text("Start Collection"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 25),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
                if (_isTracking)
                  ElevatedButton.icon(
                    onPressed: _stopTracking,
                    icon: const Icon(Icons.stop),
                    label: const Text("Stop Collection"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 25),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Background service entry point
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }

  final SharedPreferences preferences = await SharedPreferences.getInstance();
  String? uid;
  String? routeId;
  bool isTracking = false;
  StreamSubscription<Position>? positionStream;
  List<Map<String, dynamic>> routePoints = [];
  List<Map<String, dynamic>> markedHouses = [];
  final Distance distance = const Distance();

  // Variable to store worker's full name in background service
  String? _backgroundWorkerFullName;

  List<UserLocation> allUsersInBg = [];
  StreamSubscription<QuerySnapshot>? allUsersStreamSubscription;


  final SendPort? sendPort = IsolateNameServer.lookupPortByName(isolatePortName);

  // Load state from preferences on service start
  final storedRoutePoints = preferences.getStringList('routePoints');
  if (storedRoutePoints != null) {
    routePoints = storedRoutePoints.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }
  final storedMarkedHouses = preferences.getStringList('markedHouses');
  if (storedMarkedHouses != null) {
    markedHouses = storedMarkedHouses.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
  }
  isTracking = preferences.getBool('isTracking') ?? false;
  uid = preferences.getString('uid');
  routeId = preferences.getString('routeId');
  _backgroundWorkerFullName = preferences.getString('workerFullName'); // Load worker name


  // Fetch worker's full name if not already loaded (e.g., app restarted)
  if (_backgroundWorkerFullName == null && uid != null) {
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (userDoc.exists) {
        _backgroundWorkerFullName = (userDoc.data() as Map<String, dynamic>?)?['fullName'] as String?;
        await preferences.setString('workerFullName', _backgroundWorkerFullName ?? 'Unknown Collector');
      }
    } catch (e) {
      print("Background: Error fetching worker's full name on service start: $e");
    }
  }


  allUsersStreamSubscription = FirebaseFirestore.instance
      .collection('users')
      .where('userType', isEqualTo: 'user')
      .snapshots()
      .listen((snapshot) {
    allUsersInBg = snapshot.docs.map((doc) => UserLocation.fromFirestore(doc)).toList();
  });


  if (isTracking && uid != null && routeId != null) {
    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((Position position) async {
      if (!isTracking) return;
      // Pass the worker's full name to the handler
      _handleLocationUpdate(service, position, sendPort, preferences, routePoints, markedHouses, distance, allUsersInBg, uid!, routeId!, _backgroundWorkerFullName);
    });

    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
      flutterLocalNotificationsPlugin.show(
        888,
        "Clean Kudla - Tracking Active",
        "Location tracking is running in background.",
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'location_tracking',
            'Location Tracking',
            channelDescription: 'Notifications for location tracking',
            importance: Importance.high,
            priority: Priority.high,
            ongoing: true,
          ),
        ),
      );
    }
  }


  service.on('start_tracking').listen((event) async {
    uid = event!['uid'];
    routeId = event['routeId'];
    isTracking = true;
    _backgroundWorkerFullName = event['workerFullName'] as String?; // Receive worker's name from UI

    routePoints = (event['initialRoutePoints'] as List<dynamic>).map((e) => e as Map<String, dynamic>).toList();
    markedHouses = (event['initialMarkedHouses'] as List<dynamic>).map((e) => e as Map<String, dynamic>).toList();
    allUsersInBg = (event['allUsers'] as List<dynamic>).map((e) => UserLocation(
      uid: e['uid'],
      email: e['email'],
      location: LatLng(e['latitude'], e['longitude']),
      points: e['points'],
      collectedByRoutes: e['collectedByRoutes'],
      fullName: e['fullName'],
    )).toList();


    await preferences.setStringList('routePoints', routePoints.map((e) => jsonEncode(e)).toList());
    await preferences.setStringList('markedHouses', markedHouses.map((e) => jsonEncode(e)).toList());
    await preferences.setBool('isTracking', isTracking);
    await preferences.setString('uid', uid!);
    await preferences.setString('routeId', routeId!);
    await preferences.setString('workerFullName', _backgroundWorkerFullName ?? 'Unknown Collector'); // Save worker name


    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((Position position) async {
      if (!isTracking) return;
      // Pass the worker's full name to the handler
      _handleLocationUpdate(service, position, sendPort, preferences, routePoints, markedHouses, distance, allUsersInBg, uid!, routeId!, _backgroundWorkerFullName);
    });

    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }
  });

  service.on('stop_tracking').listen((event) async {
    isTracking = false;
    positionStream?.cancel();
    positionStream = null;
    allUsersStreamSubscription?.cancel();
    await preferences.setBool('isTracking', false);
    await preferences.remove('routePoints');
    await preferences.remove('markedHouses');
    await preferences.remove('uid');
    await preferences.remove('routeId');
    await preferences.remove('workerFullName'); // Clear worker name on stop
  });

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('request_current_state').listen((event) {
    sendPort?.send({
      'type': 'current_state',
      'isTracking': isTracking,
      'routeId': routeId,
      'routePoints': routePoints,
      'markedHouses': markedHouses,
    });
  });

  // Periodically update Firestore with current route status for Admin panel
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    if (service is AndroidServiceInstance) {
      if (isTracking && uid != null && routeId != null) {
        service.setAsForegroundService();

        try {
          // Update worker's own log (routes/{uid}/logs/{routeId})
          final routeRef = FirebaseFirestore.instance
              .collection('routes')
              .doc(uid)
              .collection('logs')
              .doc(routeId);

          await routeRef.set({
            'currentPath': routePoints,
            'currentHousesVisited': markedHouses,
            'lastUpdated': FieldValue.serverTimestamp(),
            'status': 'ongoing',
            'workerName': _backgroundWorkerFullName ?? 'Unknown Collector', // Ensure name is here too
            'workerUid': uid,
          }, SetOptions(merge: true));

          // NEW: Update admin_ongoing_routes collection
          final adminRouteRef = FirebaseFirestore.instance
              .collection('admin_ongoing_routes')
              .doc(routeId);

          await adminRouteRef.set({
            'workerUid': uid,
            'workerName': _backgroundWorkerFullName ?? 'Unknown Collector', // THIS IS THE KEY FIELD
            'routeId': routeId,
            'currentPath': routePoints,
            'currentHousesVisited': markedHouses,
            'lastUpdated': FieldValue.serverTimestamp(),
            'status': 'ongoing',
          }, SetOptions(merge: true));

        } catch (e) {
          print("Firestore update error in background: $e");
        }
      }
    }

    if (!isTracking) {
      timer.cancel();
      service.stopSelf();
    }
  });
}

// Helper function to handle location updates in background service
Future<void> _handleLocationUpdate(
    ServiceInstance service,
    Position position,
    SendPort? sendPort,
    SharedPreferences preferences,
    List<Map<String, dynamic>> routePoints,
    List<Map<String, dynamic>> markedHouses,
    Distance distance,
    List<UserLocation> allUsers,
    String workerUid,
    String currentRouteId,
    String? workerFullName, // New parameter for worker's full name
    ) async {
  final workerCurrentLatLng = LatLng(position.latitude, position.longitude);

  final point = {
    'latitude': position.latitude,
    'longitude': position.longitude,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };

  routePoints.add(point);

  final alreadyMarkedWorkerHouse = markedHouses.any((existing) {
    final existingLatLng = LatLng(existing['latitude'], existing['longitude']);
    return distance.as(LengthUnit.Meter, existingLatLng, workerCurrentLatLng) < 5;
  });

  if (!alreadyMarkedWorkerHouse) {
    markedHouses.add(point);
    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'Clean Kudla',
      '🏠 Worker path house marked automatically',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'location_tracking',
          'Location Tracking',
          channelDescription: 'Notifications for location tracking',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  // Proximity detection for all users
  for (var user in allUsers) {
    final userLocationLatLng = user.location;
    final double distanceToUser = distance.as(LengthUnit.Meter, workerCurrentLatLng, userLocationLatLng);

    if (distanceToUser < 5 && !user.collectedByRoutes.containsKey(currentRouteId)) {
      try {
        final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final freshUserDoc = await transaction.get(userDocRef);
          final currentPoints = (freshUserDoc.data()?['points'] as num?)?.toInt() ?? 0;
          final currentCollectedByRoutes = (freshUserDoc.data()?['collectedByRoutes'] as Map<String, dynamic>?) ?? {};

          if (!currentCollectedByRoutes.containsKey(currentRouteId)) {
            final newPoints = currentPoints + 10;
            currentCollectedByRoutes[currentRouteId] = {
              'workerUid': workerUid,
              'timestamp': FieldValue.serverTimestamp(),
            };

            transaction.update(userDocRef, {
              'points': newPoints,
              'collectedByRoutes': currentCollectedByRoutes,
              'lastCollectedAt': FieldValue.serverTimestamp(),
            });

            sendPort?.send({
              'type': 'user_collected_notification',
              'uid': user.uid,
              'fullName': user.fullName,
              'email': user.email,
            });

            await flutterLocalNotificationsPlugin.show(
              DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1,
              'Clean Kudla - User Collected!',
              '✅ ${user.fullName} (${user.email}) collected! (+10 points)',
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'location_tracking',
                  'Location Tracking',
                  channelDescription: 'Notifications for location tracking',
                  importance: Importance.high,
                  priority: Priority.high,
                ),
              ),
            );
          }
        });
      } catch (e) {
        print("Background: Error collecting user ${user.uid}: $e");
      }
    }
  }

  // Save current worker's route state to preferences
  await preferences.setStringList('routePoints', routePoints.map((e) => jsonEncode(e)).toList());
  await preferences.setStringList('markedHouses', markedHouses.map((e) => jsonEncode(e)).toList());

  // Send worker's location update to UI
  sendPort?.send({
    'type': 'location_update',
    'latitude': position.latitude,
    'longitude': position.longitude,
  });

  // Update service notification (ensures foreground service stays active)
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }
}


@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}