import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../admin/organization_page.dart';
import '../faculty/faculty_page.dart';
import '../home_page.dart';
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  _AuthPageState createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool isLoading = true;
  User? user;
  String? userRole;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().listen((User? currentUser) async {
      if (mounted) {
        setState(() {
          user = currentUser;
        });
        if (user != null) {
          userRole = await getUserRole(user!.uid);
        }
        setState(() {
          isLoading = false;
        });
      }
    });
  }

  Future<String> getUserRole(String uid) async {
    try {
      // Use UID instead of email to fetch user role
      DocumentSnapshot userRoleDoc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (userRoleDoc.exists) {
        return userRoleDoc['userType'] ?? '';
      } else {
        if (kDebugMode) {
          print('User document not found for UID: $uid');
        }
        return '';
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching user role: $e');
      }
      return '';
    }
  }

  Widget getHomePage() {
    if (user == null) {
      return HomePage(); // Redirect to LoginPage if the user is not logged in
    }
    switch (userRole) {
      case 'admin':
        return const OrganizationHome();
      case 'worker':
        return const IndividualHome();
      default:
        return const HomePage(); // Default page if role is undefined
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : getHomePage(),
    );
  }
}