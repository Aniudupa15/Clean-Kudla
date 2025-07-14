import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // For Firebase Authentication
import 'package:mailer/mailer.dart'; // For direct email sending - USE WITH CAUTION
import 'package:mailer/smtp_server/gmail.dart'; // For Gmail SMTP server
import 'dart:math'; // For password generation


class AdminPanel extends StatefulWidget {
  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final doorController = TextEditingController();
  final addressController = TextEditingController();
  final latController = TextEditingController();
  final lngController = TextEditingController();
  final employeeIdController = TextEditingController();
  final fullNameController = TextEditingController();


  final MapController _mapController = MapController();

  // Firestore collection reference for users
  final CollectionReference usersCollection =
  FirebaseFirestore.instance.collection('users');

  // Default location (corresponding to the provided initialCenter in MapOptions)
  LatLng markerPosition = LatLng(12.9141, 74.8560); // Mangaluru coordinates

  // Marker list for the FlutterMap implementation (shows the selected location)
  List<Marker> _currentSelectionMarker = [];

  // Placeholder for Polylines if required by the application, though not used in this specific admin flow
  List<Polyline> _routeLines = [];

  final String _adminEmail = 'aniudupa15@gmail.com';
  final String _adminEmailAppPassword =
      'sdtr oxvf vont mqpk';

  @override
  void initState() {
    super.initState();
    latController.text = markerPosition.latitude.toString();
    lngController.text = markerPosition.longitude.toString();
    _updateSelectionMarkerList();
  }

  // Helper function to update the single marker list on the map
  void _updateSelectionMarkerList() {
    _currentSelectionMarker = [
      Marker(
        point: markerPosition,
        width: 40,
        height: 40,
        child: Icon(Icons.location_pin, size: 40, color: Colors.red),
      ),
    ];
  }

  // Updates map marker and text fields on map tap
  void updateMarker(LatLng tappedPoint) {
    setState(() {
      markerPosition = tappedPoint;
      latController.text = tappedPoint.latitude.toString();
      lngController.text = tappedPoint.longitude.toString();
      _updateSelectionMarkerList();
    });
    // Move the map view to the newly selected point
    _mapController.move(tappedPoint, _mapController.camera.zoom);
  }

  // Function to generate a random password
  String _generateRandomPassword({int length = 10}) {
    const String _chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()';
    Random _rnd = Random();
    return String.fromCharCodes(Iterable.generate(
      length,
          (_) => _chars.codeUnitAt(_rnd.nextInt(_chars.length)),
    ));
  }

  // --- Main function to process customer data, create user, save to Firestore, and send email ---
  Future<void> submitCustomerData() async {
    final String userEmail = emailController.text.trim();
    final String userPhone = phoneController.text.trim();
    final String door = doorController.text.trim();
    final String address = addressController.text.trim();
    final double latitude = markerPosition.latitude;
    final double longitude = markerPosition.longitude;
    final String generatedPassword = _generateRandomPassword();
    // NEW: Get values for employeeId and fullName
    final String employeeId = employeeIdController.text.trim();
    final String fullName = fullNameController.text.trim();


    // Basic validation
    if (userEmail.isEmpty || userPhone.isEmpty || address.isEmpty || fullName.isEmpty || employeeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please fill in all required fields (Email, Phone, Address, Full Name, Employee ID).')));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Processing user data...')));

    try {
      // 1. Create User in Firebase Authentication
      final UserCredential userCredential =
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: userEmail,
        password: generatedPassword,
      );
      final String uid = userCredential.user!.uid; // Get the new user's UID

      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User created in Firebase Auth.')));

      // 2. Save User Data to Firestore under 'users' collection with UID as document ID
      await usersCollection.doc(uid).set({
        'uid': uid, // Store UID inside the document as well
        'email': userEmail,
        'phone': userPhone,
        'door_no': door,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'employeeId': employeeId, // NEW
        'fullName': fullName,     // NEW
        'userType': 'user',       // NEW: Set userType to 'user'
        'createdAt': FieldValue.serverTimestamp(), // Use createdAt as requested
      });

      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User data saved to Firestore.')));

      // 3. Send Login Credentials via Email automatically (using mailer)
      // WARNING: HARDCODING CREDENTIALS IS A SECURITY RISK.
      // FOR PRODUCTION, USE A SECURE BACKEND SERVICE (e.g., Firebase Cloud Functions)
      // THAT HANDLES YOUR EMAIL API KEYS/SMTP CREDENTIALS SECURELY.
      final smtpServer = gmail(_adminEmail, _adminEmailAppPassword);

      final message = Message()
        ..from = Address(_adminEmail, 'Solid Waste Management Team')
        ..recipients.add(userEmail)
        ..subject = 'Welcome to Mangalore City Corporation Waste Management Portal - Your Account Credentials'
        ..text = '''
Dear $fullName,

Welcome to the Mangalore City Corporation's Waste Management Portal!

Your account has been successfully created. You can now log in and begin tracking and managing your waste services efficiently.

Here are your login credentials:

User ID: $userEmail
Password: $generatedPassword

Please keep this information confidential and secure.

Thank you for joining our effort in keeping Mangalore clean and sustainable.

Warm regards,
Mangalore City Corporation (MCC)
Solid Waste Management Team''';

      try {
        final sendReport = await send(message, smtpServer);
        print('Email sent successfully: ${sendReport.toString()}');
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Login credentials email sent to $userEmail.')));
      } catch (e) {
        print('Failed to send email. Error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send login email. Error: $e')));
      }

      // 4. Note on Automatic SMS:
      // Sending SMS automatically directly from the Flutter client without user interaction
      // is NOT possible securely. It requires a backend service (e.g., Firebase Cloud Functions
      // integrating with Twilio, Vonage, etc.) to handle the SMS API keys securely.
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('SMS automation requires backend integration.')));


    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Firebase Auth Error: ';
      if (e.code == 'weak-password') {
        errorMessage += 'The password provided is too weak.';
      } else if (e.code == 'email-already-in-use') {
        errorMessage += 'The account already exists for that email.';
      } else {
        errorMessage += e.message ?? 'An unknown authentication error occurred.';
      }
      print(errorMessage);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
    } catch (e) {
      print('General error during submission: $e');
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An unexpected error occurred: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Admin Panel"),
        backgroundColor: Colors.deepOrange,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            // NEW: Full Name and Employee ID fields
            buildTextField(fullNameController, "Full Name"),
            buildTextField(employeeIdController, "Employee ID"),
            // Existing fields
            buildTextField(emailController, "Email (User's Login ID)"),
            buildTextField(phoneController, "Phone No"),
            buildTextField(doorController, "Door No"),
            buildTextField(addressController, "Address"),
            buildTextField(latController, "Latitude", readOnly: true),
            buildTextField(lngController, "Longitude", readOnly: true),

            SizedBox(height: 20),
            Container(
              height: 300,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: markerPosition, // Use the current marker position as center
                  initialZoom: 13,
                  interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.all),
                  onTap: (tapPosition, latLng) => updateMarker(latLng), // Corrected onTap
                ),
                children: [
                  TileLayer(
                    urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                    userAgentPackageName: "com.example.clean_kudla",
                  ),
                  PolylineLayer(
                      polylines:
                      _routeLines), // Placeholder, can be populated if needed
                  MarkerLayer(
                      markers:
                      _currentSelectionMarker), // Shows the selected location
                ],
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: submitCustomerData,
              child: Text("Register User & Notify"),
            )
          ],
        ),
      ),
    );
  }

  Widget buildTextField(TextEditingController controller, String label,
      {bool readOnly = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(),
        ),
      ),
    );
  }
}