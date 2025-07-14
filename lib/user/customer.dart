import 'dart:async'; // For StreamSubscription

import 'package:cleankudla/home_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // For getting current user UID
import 'package:cloud_firestore/cloud_firestore.dart'; // For Firestore interactions
import 'package:intl/intl.dart'; // For date formatting
import 'package:google_fonts/google_fonts.dart'; // For the desired font styling

class UserHome extends StatefulWidget {
  const UserHome({super.key});

  @override
  State<UserHome> createState() => _UserHomeState();
}

class _UserHomeState extends State<UserHome> {
  int _currentUserPoints = 0;
  String _todayCollectorName = "N/A";
  String _todayCollectionTime = "N/A";
  bool _hasCollectionToday = false; // Flag to determine which message to show
  User? _currentUser;
  bool _isLoading = true;
  StreamSubscription<DocumentSnapshot>? _userSubscription;

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    if (_currentUser == null) {
      // User is not logged in, handle accordingly (e.g., redirect to login)
      _isLoading = false;
      _showSnackbar("Please log in to view your dashboard.");
      // Optional: Add a Future.delayed to navigate back to login after showing snackbar
    } else {
      _fetchUserDataAndCollections();
    }
  }

  @override
  void dispose() {
    _userSubscription?.cancel(); // Cancel the Firestore stream to prevent memory leaks
    super.dispose();
  }

  void _showSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _fetchUserDataAndCollections() async {
    if (_currentUser == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    print('DEBUG: Fetching data for user UID: ${_currentUser!.uid}'); // DEBUG

    // Listen to the current user's document for real-time updates
    _userSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser!.uid)
        .snapshots()
        .listen((DocumentSnapshot userDoc) async {
      if (!userDoc.exists || userDoc.data() == null) {
        _showSnackbar("User data not found in Firestore.");
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;

      // Update current user points
      _currentUserPoints = (userData['points'] as num?)?.toInt() ?? 0;

      // Process collectedByRoutes for today's collections
      final collectedByRoutes = (userData['collectedByRoutes'] as Map<String, dynamic>?) ?? {};
      DateTime? latestCollectionDateTimeToday;
      String? latestCollectorUidToday;

      // --- CRUCIAL DATE COMPARISON LOGIC REFINEMENT ---
      // Get today's date range (start and end of day)
      // It's best to normalize to UTC for comparison with Firestore Timestamps.
      final now = DateTime.now(); // Current local time
      final startOfTodayLocal = DateTime(now.year, now.month, now.day);
      final endOfTodayLocal = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

      // Convert local date range to UTC for comparison with Firestore Timestamps
      final startOfTodayUtc = startOfTodayLocal.toUtc();
      final endOfTodayUtc = endOfTodayLocal.toUtc();

      print('DEBUG: Local Date: ${now.toIso8601String()}'); // DEBUG
      print('DEBUG: Start of Today (UTC): ${startOfTodayUtc.toIso8601String()}'); // DEBUG
      print('DEBUG: End of Today (UTC): ${endOfTodayUtc.toIso8601String()}'); // DEBUG

      for (var entry in collectedByRoutes.entries) {
        final collectionDetails = entry.value as Map<String, dynamic>;
        final Timestamp? timestamp = collectionDetails['timestamp'] as Timestamp?;
        final String? workerUid = collectionDetails['workerUid'] as String?;

        if (timestamp != null && workerUid != null) {
          final collectionDateTime = timestamp.toDate(); // This is already in UTC

          print('DEBUG: Processing collection - Route ID: ${entry.key}, Worker UID: $workerUid'); // DEBUG
          print('DEBUG: Collection Timestamp (Firestore): ${timestamp.toDate().toIso8601String()} (UTC)'); // DEBUG

          // Check if collection happened today in UTC
          if (collectionDateTime.isAfter(startOfTodayUtc.subtract(const Duration(milliseconds: 1))) &&
              collectionDateTime.isBefore(endOfTodayUtc.add(const Duration(milliseconds: 1)))) {
            print('DEBUG: Collection IS within today\'s UTC range.'); // DEBUG
            // Keep track of the latest collection for today
            if (latestCollectionDateTimeToday == null ||
                collectionDateTime.isAfter(latestCollectionDateTimeToday)) {
              latestCollectionDateTimeToday = collectionDateTime;
              latestCollectorUidToday = workerUid;
            }
          } else {
            print('DEBUG: Collection IS NOT within today\'s UTC range. (Out of bounds)'); // DEBUG
          }
        } else {
          print('DEBUG: Collection entry missing timestamp or workerUid: $collectionDetails'); // DEBUG
        }
      }

      // Update UI state based on the latest collection found today
      if (latestCollectionDateTimeToday != null && latestCollectorUidToday != null) {
        _hasCollectionToday = true;
        // Format time to local time for display (as user expects local time)
        _todayCollectionTime = DateFormat('hh:mm a').format(latestCollectionDateTimeToday.toLocal());

        // Fetch worker's full name
        String workerName = "Unknown Worker";
        try {
          DocumentSnapshot workerDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(latestCollectorUidToday)
              .get();
          if (workerDoc.exists && workerDoc.data() != null) {
            workerName = (workerDoc.data() as Map<String, dynamic>)['fullName'] as String? ?? "Unknown Worker";
          }
        } catch (e) {
          print("Error fetching worker details for $latestCollectorUidToday: $e");
        }
        _todayCollectorName = workerName;
        print('DEBUG: Latest collection found today by: $_todayCollectorName at $_todayCollectionTime'); // DEBUG
      } else {
        _hasCollectionToday = false;
        _todayCollectorName = "N/A";
        _todayCollectionTime = "N/A";
        print('DEBUG: No collection found for today.'); // DEBUG
      }

      setState(() {
        _isLoading = false; // Data has been loaded or processed
      });
    }, onError: (error) {
      _showSnackbar("Error fetching user data: ${error.toString()}");
      print('DEBUG: Firestore Stream Error: $error'); // DEBUG
      setState(() {
        _isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9), // Background color from UserDashboard
      appBar: AppBar(
        title: Text(
          "Your Dashboard",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.green.shade700, // Matching theme from previous UserHome AppBar
        elevation: 0, // Flat app bar
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              // Navigate back to login page. Pop until the first route (login page)
              Navigator.pushReplacement(
                  context, MaterialPageRoute(builder: (context) => const HomePage()));
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Center(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 30),
                // Conditional display for collection status today
                _hasCollectionToday
                    ? Column(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.green, size: 100),
                    const SizedBox(height: 20),
                    Text(
                      'Your waste has been collected today!',
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 15),
                    Center(
                      child: Text(
                        'Collected by: $_todayCollectorName at $_todayCollectionTime',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                  ],
                )
                    : Column(
                  children: [
                    Icon(Icons.access_time_filled, color: Colors.amber, size: 100), // Changed icon for no collection
                    const SizedBox(height: 20),
                    Text(
                      'No waste collection recorded today yet.',
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 15),
                    Text(
                      'Keep your waste ready for collection!',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[800],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                // Reward Points Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple, // Color from UserDashboard
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [ // Optional: Add a subtle shadow
                      BoxShadow(
                        color: Colors.deepPurple.withOpacity(0.3),
                        spreadRadius: 2,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Your Reward Points',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '$_currentUserPoints', // Dynamic points
                        style: GoogleFonts.poppins(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () {
                    // TODO: Implement navigation to a history page or other user features
                    _showSnackbar("View More functionality for collection history coming soon!");
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    elevation: 5, // Adds a subtle elevation
                  ),
                  child: Text(
                    'View More',
                    style: GoogleFonts.poppins(fontSize: 16, color: Colors.white),
                  ),
                ),
                const Spacer(), // Pushes content to the top
                // You can add a logout button here if the one in AppBar is not enough
                // or for redundancy. Removed for cleaner UI at the bottom in this design.
              ],
            ),
          ),
        ),
      ),
    );
  }
}