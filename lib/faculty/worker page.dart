import 'dart:async';
import 'dart:convert'; // Added for JSON encoding/decoding
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
import 'package:shared_preferences/shared_preferences.dart'; // Added for SharedPreferences
import 'package:firebase_core/firebase_core.dart'; // Added for Firebase.initializeApp()

// Global variables for background service
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
const String isolatePortName = 'location_service_port';

class WorkerPage extends StatefulWidget {
  const WorkerPage({super.key});

  @override
  State<WorkerPage> createState() => _WorkerPageState();
}

class _WorkerPageState extends State<WorkerPage> {
  final MapController _mapController = MapController();
  bool _isTracking = false;
  StreamSubscription<Position>? _positionStream; // This stream is now managed by the background service
  List<LatLng> _routePoints = [];
  List<LatLng> _markedHouses = [];
  String? _routeId;
  String? _uid;
  final Distance _distance = const Distance();
  ReceivePort? _receivePort;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _initializeNotifications();
    _checkLocationPermission();
    _setupBackgroundService(); // This will now also handle re-syncing state
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
        autoStart: false, // We will manually start it
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

    // Setup port for communication with background service
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

            // Check if house should be marked
            final alreadyMarked = _markedHouses.any(
                  (existing) => _distance.as(LengthUnit.Meter, existing, point) < 5,
            );

            if (!alreadyMarked) {
              _markedHouses.add(point);
              _showNotification("🏠 House marked automatically");
            }
          });

          // Only move map if tracking is active and points are being added
          if (_isTracking && _routePoints.isNotEmpty) {
            _mapController.move(point, 17);
          }
        } else if (data['type'] == 'current_state') {
          // Received current state from background service
          setState(() {
            _isTracking = data['isTracking'] as bool;
            _routeId = data['routeId'] as String?;
            _routePoints = (data['routePoints'] as List<dynamic>)
                .map((e) => LatLng(e['latitude'] as double, e['longitude'] as double))
                .toList();
            _markedHouses = (data['markedHouses'] as List<dynamic>)
                .map((e) => LatLng(e['latitude'] as double, e['longitude'] as double))
                .toList();
          });
          if (_routePoints.isNotEmpty) {
            _mapController.move(_routePoints.last, 17);
          }
          _showSnackbar("🔄 Re-synced with background tracking.");
        }
      }
    });

    // Check if service is already running and request current state
    if (await service.isRunning()) {
      service.invoke('request_current_state');
    }
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

    // Request background location permission for Android
    await Permission.locationAlways.request();
  }

  @override
  void dispose() {
    // No need to cancel _positionStream here, it's managed by background service
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
      _markedHouses = [startPoint];
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
    });

    // Start background service
    final service = FlutterBackgroundService();
    await service.startService();

    // Send initial data to background service
    service.invoke('start_tracking', {
      'uid': _uid,
      'routeId': _routeId,
      'initialRoutePoints': _routePoints.map((p) => {'latitude': p.latitude, 'longitude': p.longitude}).toList(),
      'initialMarkedHouses': _markedHouses.map((p) => {'latitude': p.latitude, 'longitude': p.longitude}).toList(),
    });

    _showSnackbar("🟢 Tracking started. Move to auto-mark houses.");
    _showNotification("🟢 Collection tracking started");
  }

  void _stopTracking() async {
    final service = FlutterBackgroundService();
    service.invoke('stop_tracking'); // Tell background service to stop tracking
    service.invoke('stopService'); // Tell background service to stop itself

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
        _routePoints = []; // Clear UI state on stop
        _markedHouses = []; // Clear UI state on stop
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
      0,
      'Clean Kudla',
      message,
      notificationDetails,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Explicitly define the generic type for Polyline as Object
    final routePolyline = Polyline<Object>(
      points: _routePoints,
      strokeWidth: 4.0,
      color: Colors.green,
    );

    final List<Marker> houseMarkers = _markedHouses.map(
          (point) => Marker(
        width: 30,
        height: 30,
        point: point,
        child: const Icon(Icons.home, color: Colors.orange),
      ),
    ).toList();

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
              initialCenter: _routePoints.isNotEmpty ? _routePoints.last : LatLng(12.9141, 74.8560),
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
              // Ensure the empty list is also explicitly typed
              PolylineLayer(polylines: _routePoints.isNotEmpty ? [routePolyline] : <Polyline<Object>>[]),
              MarkerLayer(markers: houseMarkers),
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
  // Initialize Firebase if not already initialized
  if (Firebase.apps.isEmpty) {
    // For a real app, you might need to pass options:
    // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await Firebase.initializeApp(); // Assuming default Firebase project setup
  }
  // Ensure user is authenticated for Firestore writes
  // This is a simplified approach. In a real app, you might re-authenticate
  // or use a persistent login.
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

  // Setup communication port
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

  // If service restarts and was tracking, resume position stream
  if (isTracking && uid != null && routeId != null) {
    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((Position position) async {
      if (!isTracking) return;
      _handleLocationUpdate(service, position, sendPort, preferences, routePoints, markedHouses, distance);
    });

    // Manually update notification if service was already tracking
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

    // Clear and set initial points from UI
    routePoints = (event['initialRoutePoints'] as List<dynamic>).map((e) => e as Map<String, dynamic>).toList();
    markedHouses = (event['initialMarkedHouses'] as List<dynamic>).map((e) => e as Map<String, dynamic>).toList();

    // Save initial state
    await preferences.setStringList('routePoints', routePoints.map((e) => jsonEncode(e)).toList());
    await preferences.setStringList('markedHouses', markedHouses.map((e) => jsonEncode(e)).toList());
    await preferences.setBool('isTracking', isTracking);
    await preferences.setString('uid', uid!);
    await preferences.setString('routeId', routeId!);


    // Start location tracking
    positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((Position position) async {
      if (!isTracking) return; // Ensure we only process if tracking is active
      _handleLocationUpdate(service, position, sendPort, preferences, routePoints, markedHouses, distance);
    });

    // Update service notification
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }
  });

  service.on('stop_tracking').listen((event) async {
    isTracking = false;
    positionStream?.cancel();
    positionStream = null; // Clear the stream
    await preferences.setBool('isTracking', false);
    await preferences.remove('routePoints'); // Clear stored data
    await preferences.remove('markedHouses');
    await preferences.remove('uid');
    await preferences.remove('routeId');
  });

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Handle requests from UI for current state
  service.on('request_current_state').listen((event) {
    sendPort?.send({
      'type': 'current_state',
      'isTracking': isTracking,
      'routeId': routeId,
      'routePoints': routePoints,
      'markedHouses': markedHouses,
    });
  });

  // Keep service alive and update notification and Firestore
  Timer.periodic(const Duration(seconds: 30), (timer) async { // Changed to 30 seconds for Firestore updates
    if (service is AndroidServiceInstance) {
      if (isTracking && uid != null && routeId != null) {
        service.setAsForegroundService();

        // Update Firestore with current route and houses
        try {
          final routeRef = FirebaseFirestore.instance
              .collection('routes')
              .doc(uid)
              .collection('logs')
              .doc(routeId);

          await routeRef.set({
            'currentPath': routePoints, // Store current path for ongoing routes
            'currentHousesVisited': markedHouses, // Store current marked houses
            'lastUpdated': FieldValue.serverTimestamp(),
            'status': 'ongoing', // Ensure status is explicitly set
          }, SetOptions(merge: true));
        } catch (e) {
          // Log error but don't stop service
          print("Firestore update error in background: $e");
        }
      }
    }

    if (!isTracking) {
      timer.cancel();
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
    ) async {
  final point = {
    'latitude': position.latitude,
    'longitude': position.longitude,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };

  routePoints.add(point);

  // Check if house should be marked
  final currentLatLng = LatLng(position.latitude, position.longitude);
  final alreadyMarked = markedHouses.any((existing) {
    final existingLatLng = LatLng(existing['latitude'], existing['longitude']);
    return distance.as(LengthUnit.Meter, existingLatLng, currentLatLng) < 5;
  });

  if (!alreadyMarked) {
    markedHouses.add(point);

    // Show notification for automatically marked house (this remains)
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
      '🏠 House marked automatically',
      notificationDetails,
    );
  }

  // Save current state to preferences
  await preferences.setStringList('routePoints', routePoints.map((e) => jsonEncode(e)).toList());
  await preferences.setStringList('markedHouses', markedHouses.map((e) => jsonEncode(e)).toList());

  // Send location update to UI
  sendPort?.send({
    'type': 'location_update',
    'latitude': position.latitude,
    'longitude': position.longitude,
  });

  // Update service notification (this ensures the foreground service stays active)
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }
}


@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}
