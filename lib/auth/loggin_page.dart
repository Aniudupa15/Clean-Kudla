import 'package:cleankudla/auth/register_page.dart';
import 'package:cleankudla/user/customer.dart';
import 'package:cleankudla/worker/worker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../admin/organization_page.dart';
import 'auth_services.dart';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _displayMessageToUser(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Authenticate user with Firebase
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      String userEmail = userCredential.user!.email!;
      String uid = userCredential.user!.uid;

      DocumentSnapshot? userDoc; // Renamed from userRoleDoc for clarity

      // 2. Try to get user data from 'users' collection using UID
      userDoc = await _firestore.collection('users').doc(uid).get();

      // 3. If not found by UID, try getting by email (less common, but kept your logic)
      if (!userDoc.exists) {
        userDoc = await _firestore.collection('users').doc(userEmail).get();
      }

      // 4. Check if user document exists in 'users' collection
      if (!userDoc.exists) {
        // If user data is not found in the 'users' collection at all,
        // it implies the user wasn't fully set up or data is missing.
        _displayMessageToUser('User data not found. Please register or contact admin.');
        await _auth.signOut(); // Sign out the user if their data isn't set up
        return;
      }

      // 5. Get userType directly from the document
      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      String userType = userData['userType'] ?? ''; // Default to empty string if not found

      // 6. Redirect based on userType
      if (userType == 'admin') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => OrganizationHome()));
      } else if (userType == 'worker') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => IndividualHome()));
      } else if (userType == 'user') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => UserHome()));
      } else {
        _displayMessageToUser('Unknown user type: $userType. Please contact admin.');
        await _auth.signOut();
      }

    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Login failed.';
      if (e.code == 'user-not-found') {
        errorMessage = 'No user found for this email.';
      } else if (e.code == 'wrong-password') {
        errorMessage = 'Incorrect password.';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'The email address is not valid.';
      } else if (e.code == 'user-disabled') {
        errorMessage = 'This user account has been disabled.';
      }
      _displayMessageToUser(errorMessage);
    } catch (e) {
      _displayMessageToUser('Unexpected error during login: ${e.toString()}');
      // print('Login Error Details: $e'); // You can keep this for your own debugging
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Clean Kudla',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Welcome! Log in to manage smart sanitation.',
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                SizedBox(height: 24),
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email address',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (value) {
                            setState(() {
                              _rememberMe = value!;
                            });
                          },
                        ),
                        Text('Remember me'),
                      ],
                    ),
                    InkWell(
                      onTap: () {}, // TODO: Implement forgot password logic
                      child: Text('Forgot password?', style: TextStyle(color: Colors.blue)),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    child: _isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text('Login'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: Colors.black,
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Or continue with'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _socialButton('assets/google.png', onTap: () async {
                      setState(() => _isLoading = true);
                      try {
                        await AuthServices().signInWithGoogle(context);
                        // After Google sign-in, AuthServices should handle redirection based on user data
                        // If AuthServices doesn't handle it, you might need additional logic here
                        // to fetch userType and navigate, similar to the email/password flow.
                      } catch (e) {
                        _displayMessageToUser('Error: ${e.toString()}');
                      } finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    }),
                    SizedBox(width: 16),
                    _socialButton('assets/facebook.png', onTap: () {
                      _displayMessageToUser("Facebook login not implemented.");
                    }),
                  ],
                ),
                SizedBox(height: 24),
                InkWell(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => FacultyRegisterPage()));
                  },
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(color: Colors.black, fontSize: 16),
                      children: [
                        TextSpan(text: "Don't have an account? "),
                        TextSpan(
                          text: 'Sign up',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _socialButton(String assetPath, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(child: Image.asset(assetPath, width: 24)),
      ),
    );
  }
}