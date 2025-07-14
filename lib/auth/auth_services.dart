import 'package:cleankudla/user/customer.dart';
import 'package:cleankudla/worker/worker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../admin/organization_page.dart';

class AuthServices {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> sendEmailVerification() async {
    try {
      await _auth.currentUser?.sendEmailVerification();
    } catch (e) {
      if (kDebugMode) {
        print("Email verification error: $e");
      }
    }
  }

  Future<UserCredential?> loginWithGoogle() async {
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );
      return await _auth.signInWithCredential(credential);
    } catch (e) {
      if (kDebugMode) {
        print("Google login error: $e");
      }
      return null;
    }
  }

  Future<void> signInWithGoogle(BuildContext context) async {
    try {
      final GoogleSignInAccount? gUser = await GoogleSignIn().signIn();
      if (gUser == null) {
        throw FirebaseAuthException(
          code: 'ERROR_ABORTED_BY_USER',
          message: 'Sign-in aborted by user',
        );
      }

      final GoogleSignInAuthentication gAuth = await gUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );

      UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      User? user = userCredential.user;

      if (user != null) {
        if (user.email == null) {
          throw FirebaseAuthException(
            code: 'ERROR_NO_EMAIL',
            message: 'No email found for this user',
          );
        }

        // First, try to get user role using UID
        DocumentSnapshot userRoleDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        // If document doesn't exist using UID, try checking with email
        // This is for backward compatibility with previously created users
        if (!userRoleDoc.exists) {
          // Try to find user by email in a separate collection
          QuerySnapshot emailQuery = await FirebaseFirestore.instance
              .collection('userEmails')
              .where('email', isEqualTo: user.email)
              .limit(1)
              .get();

          if (emailQuery.docs.isNotEmpty) {
            String uid = emailQuery.docs.first['uid'];
            userRoleDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .get();
          } else {
            // Legacy approach - try with email as doc ID
            userRoleDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.email)
                .get();
          }
        }

        if (!userRoleDoc.exists) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("User role not found. Contact admin.")),
          );
          return;
        }

        String? role = userRoleDoc['userType'] as String?;
        if (role == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Invalid role for user.")),
          );
          return;
        }
        // Navigate based on role
        if (role == 'admin') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const OrganizationHome()),
          );
        }else if (role == 'user') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const UserHome()),
          );
        } else if (role == 'worker') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) =>IndividualHome()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Invalid user role.")),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error during Google sign-in: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error during Google sign-in: ${e.toString()}")),
      );
    }
  }

  User? getCurrentUser() {
    return _auth.currentUser;
  }
}