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
    // Safely parse latitude and longitude
    final double? lat = (data['latitude'] as num?)?.toDouble();
    final double? lng = (data['longitude'] as num?)?.toDouble();

    if (lat == null || lng == null) {
      // Throw an error if location data is missing, as these users won't be mappable
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
  List<LatLng> _markedHouses = []; // Houses worker auto-marks on their path
  String? _routeId;
  String? _uid;
  final Distance _distance = const Distance();
  ReceivePort? _receivePort;

  // Stream to listen to all user locations from Firestore
  Stream<List<UserLocation>>? _allUsersStream;
  List<UserLocation> _allUsers = []; // Stores all user data from Firestore

  // Variable to hold the worker's current location
  LatLng? _currentWorkerLocation;


  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _initializeNotifications();
    _checkLocationPermission();
    _setupBackgroundService();
    _setupAllUsersStream(); // New: Setup stream to listen to all users
  }

  void _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // Request notification permission
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
            // Update worker's current location
            _currentWorkerLocation = point;

            // Check if worker's own path should auto-mark a house
            final alreadyMarked = _markedHouses.any(
                  (existing) => _distance.as(LengthUnit.Meter, existing, point) < 5,
            );

            if (!alreadyMarked) {
              _markedHouses.add(point);
              // Notification for worker's own path house marking
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
            // Set initial worker location from background state
            if (_routePoints.isNotEmpty) {
              _currentWorkerLocation = _routePoints.last;
            }
          });
          if (_routePoints.isNotEmpty) {
            _mapController.move(_routePoints.last, 17);
          }
          _showSnackbar("🔄 Re-synced with background tracking.");
        } else if (data['type'] == 'user_collected_notification') {
          // Notification from background service when a user is collected
          final collectedUserFullName = data['fullName'] as String? ?? 'A user';
          final collectedUserEmail = data['email'] as String? ?? 'No email';
          _showNotification("✅ Collected: $collectedUserFullName ($collectedUserEmail)! (+10 points)");
          // The UI will refresh the user markers via _allUsersStream
        }
      }
    });

    if (await service.isRunning()) {
      service.invoke('request_current_state');
    }
  }

  // Function to setup stream for all users in Firestore
  void _setupAllUsersStream() {
    _allUsersStream = FirebaseFirestore.instance
        .collection('users')
        .where('userType', isEqualTo: 'user') // ADDED FILTER HERE
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => UserLocation.fromFirestore(doc)).toList());

    _allUsersStream?.listen((users) {
      setState(() {
        _allUsers = users;
        // print('DEBUG: _allUsers list updated with ${users.length} users.'); // Debug print removed
      });
      // Optionally move map to the last collected user or the worker's last position
      if (_isTracking && _routePoints.isNotEmpty) {
        _mapController.move(_routePoints.last, _mapController.camera.zoom);
      } else if (_allUsers.isNotEmpty && _currentWorkerLocation == null) {
        // Move to a default user location if no tracking AND worker's location isn't known yet
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
      _markedHouses = [startPoint]; // Initial mark for the starting point
      // Set initial worker location on start
      _currentWorkerLocation = startPoint;
    });

    final routeRef = FirebaseFirestore.instance
        .collection('routes')
        .doc(_uid)
        .collection('logs')
        .doc(_routeId);

    await routeRef.set({
      'startedAt': FieldValue.serverTimestamp(),
      'status': 'ongoing',
      'routeId': _routeId,
      'workerUid': _uid, // Store worker UID in the route log
    });

    final service = FlutterBackgroundService();
    await service.startService();

    // Send initial data and current allUsers list to background service
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
    });

    _showSnackbar("🟢 Tracking started. Move to auto-mark houses and collect users.");
    _showNotification("🟢 Collection tracking started");
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

      _showSnackbar("✅ Route completed and uploaded.");
      _showNotification("✅ Collection route completed");

      setState(() {
        _isTracking = false;
        _routeId = null;
        _routePoints = [];
        _markedHouses = [];
        _currentWorkerLocation = null; // Clear worker location on stop
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
        child: const Icon(Icons.location_on, color: Colors.blueAccent), // Icon for worker's marked houses
      ),
    ).toList();

    // Marker for the worker's current location
    Marker? workerCurrentLocationMarker;
    if (_currentWorkerLocation != null) {
      workerCurrentLocationMarker = Marker(
        width: 40,
        height: 40,
        point: _currentWorkerLocation!,
        child: const Icon(Icons.directions_walk, color: Colors.purple, size: 35),
      );
    }


    // Markers for all users based on their collected status
    final List<Marker> allUsersMarkers = _allUsers.map(
          (user) {
        final bool isCollectedOnCurrentRoute = _routeId != null && user.collectedByRoutes.containsKey(_routeId);
        // Determine icon based on whether user is collected on current route or ever
        IconData iconData = Icons.person_pin;
        Color iconColor = Colors.grey; // Default uncollected

        if (isCollectedOnCurrentRoute) {
          iconData = Icons.check_circle; // Collected on THIS route
          iconColor = Colors.green;
        } else if (user.collectedByRoutes.isNotEmpty) {
          iconData = Icons.person_pin; // Collected on a previous route
          iconColor = Colors.blue;
        } else {
          // Not collected yet
          iconData = Icons.person_pin_circle;
          iconColor = Colors.red;
        }

        return Marker(
          width: 50,
          height: 50,
          point: user.location, // Uses the LatLng from the UserLocation object
          child: Column(
            children: [
              Icon(iconData, color: iconColor, size: 30),
              Text(
                user.fullName.split(' ')[0], // Display first name
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

    // Combine all markers for the map
    List<Marker> allMapMarkers = [
      ...workerPathHouseMarkers,
      ...allUsersMarkers, // All user markers added here
    ];
    // Add the worker's current location marker if it exists
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
              // Prioritize current worker location if available, then route points, then default
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
              MarkerLayer(markers: allMapMarkers), // All markers combined
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
  // Ensure user is authenticated for Firestore writes
  // In a real app, you'd handle persistent login more robustly
  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously(); // Or re-authenticate with stored credentials
  }

  final SharedPreferences preferences = await SharedPreferences.getInstance();
  String? uid;
  String? routeId;
  bool isTracking = false;
  StreamSubscription<Position>? positionStream;
  List<Map<String, dynamic>> routePoints = [];
  List<Map<String, dynamic>> markedHouses = [];
  final Distance distance = const Distance();

  // List to hold all user locations fetched by the background service
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

  // Set up listener for all users in the background service
  allUsersStreamSubscription = FirebaseFirestore.instance
      .collection('users')
      .where('userType', isEqualTo: 'user') // ADDED FILTER HERE
      .snapshots()
      .listen((snapshot) {
    allUsersInBg = snapshot.docs.map((doc) => UserLocation.fromFirestore(doc)).toList();
    // print('Background: Fetched ${allUsersInBg.length} users in background service.'); // Debug print removed
  });


  if (isTracking && uid != null && routeId != null) {
    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((Position position) async {
      if (!isTracking) return;
      _handleLocationUpdate(service, position, sendPort, preferences, routePoints, markedHouses, distance, allUsersInBg, uid!, routeId!);
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

    routePoints = (event['initialRoutePoints'] as List<dynamic>).map((e) => e as Map<String, dynamic>).toList();
    markedHouses = (event['initialMarkedHouses'] as List<dynamic>).map((e) => e as Map<String, dynamic>).toList();
    // Get current list of all users from UI on start_tracking
    // Note: This 'allUsers' list passed from the UI would already be filtered
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


    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((Position position) async {
      if (!isTracking) return;
      _handleLocationUpdate(service, position, sendPort, preferences, routePoints, markedHouses, distance, allUsersInBg, uid!, routeId!);
    });

    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }
  });

  service.on('stop_tracking').listen((event) async {
    isTracking = false;
    positionStream?.cancel();
    positionStream = null;
    allUsersStreamSubscription?.cancel(); // Cancel user stream on stop
    await preferences.setBool('isTracking', false);
    await preferences.remove('routePoints');
    await preferences.remove('markedHouses');
    await preferences.remove('uid');
    await preferences.remove('routeId');
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

  Timer.periodic(const Duration(seconds: 30), (timer) async {
    if (service is AndroidServiceInstance) {
      if (isTracking && uid != null && routeId != null) {
        service.setAsForegroundService();

        try {
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
          }, SetOptions(merge: true));
        } catch (e) {
          print("Firestore update error in background: $e");
        }
      }
    }

    // Stop the background service if tracking is not active and the timer runs
    if (!isTracking) {
      timer.cancel();
      service.stopSelf(); // Automatically stop after some time if not tracking
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
    List<UserLocation> allUsers, // Pass all users to the handler
    String workerUid, // Pass worker UID
    String currentRouteId, // Pass current route ID
    ) async {
  final workerCurrentLatLng = LatLng(position.latitude, position.longitude);

  final point = {
    'latitude': position.latitude,
    'longitude': position.longitude,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };

  routePoints.add(point);

  // Check if worker's own path should auto-mark a house
  final alreadyMarkedWorkerHouse = markedHouses.any((existing) {
    final existingLatLng = LatLng(existing['latitude'], existing['longitude']);
    return distance.as(LengthUnit.Meter, existingLatLng, workerCurrentLatLng) < 5;
  });

  if (!alreadyMarkedWorkerHouse) {
    markedHouses.add(point);
    // Show notification for automatically marked house on worker's path
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

    // Check if within 5 meters and not already collected on THIS route
    if (distanceToUser < 5000 && !user.collectedByRoutes.containsKey(currentRouteId)) {
      // print('Background: Worker is near user ${user.uid} (${user.fullName}). Distance: $distanceToUser m'); // Debug print removed

      try {
        final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

        // Use a transaction to safely update points and collected status
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final freshUserDoc = await transaction.get(userDocRef);
          final currentPoints = (freshUserDoc.data()?['points'] as num?)?.toInt() ?? 0;
          final currentCollectedByRoutes = (freshUserDoc.data()?['collectedByRoutes'] as Map<String, dynamic>?) ?? {};

          // Double check if already collected on this route within the transaction
          if (!currentCollectedByRoutes.containsKey(currentRouteId)) {
            final newPoints = currentPoints + 10;
            currentCollectedByRoutes[currentRouteId] = {
              'workerUid': workerUid,
              'timestamp': FieldValue.serverTimestamp(),
            };

            transaction.update(userDocRef, {
              'points': newPoints,
              'collectedByRoutes': currentCollectedByRoutes,
              'lastCollectedAt': FieldValue.serverTimestamp(), // Optional: last collected time
            });

            // print('Background: User ${user.uid} (${user.fullName}) collected. Points: $newPoints'); // Debug print removed
            // Send notification to UI for user collection
            sendPort?.send({
              'type': 'user_collected_notification',
              'uid': user.uid,
              'fullName': user.fullName,
              'email': user.email,
            });

            // Show local notification for collected user
            await flutterLocalNotificationsPlugin.show(
              DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1, // Unique ID
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