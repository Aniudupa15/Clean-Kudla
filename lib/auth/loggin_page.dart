import 'package:cleankudla/auth/register_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../admin/organization_page.dart';
import '../faculty/faculty_page.dart'; // Replace if needed for "worker"
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
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      String userEmail = userCredential.user!.email!;
      String uid = userCredential.user!.uid;

      DocumentSnapshot? userRoleDoc;
      bool isApproved = false;

      userRoleDoc = await _firestore.collection('users').doc(uid).get();

      if (userRoleDoc.exists) {
        isApproved = (userRoleDoc['status'] ?? '') == 'approved';
      } else {
        userRoleDoc = await _firestore.collection('users').doc(userEmail).get();
        if (userRoleDoc.exists) {
          isApproved = (userRoleDoc['status'] ?? '') == 'approved';
        } else {
          DocumentSnapshot userPendingDoc = await _firestore.collection('pending_users').doc(userEmail).get();
          if (userPendingDoc.exists) {
            isApproved = (userPendingDoc['status'] ?? '') == 'approved';
            if (isApproved) {
              _displayMessageToUser('Account approved but user data not found. Contact admin.');
              await _auth.signOut();
              return;
            }
          } else {
            _displayMessageToUser('User data not found.');
            await _auth.signOut();
            return;
          }
        }
      }

      if (!isApproved) {
        _displayMessageToUser('Your account is pending approval.');
        await _auth.signOut();
        return;
      }

      Map<String, dynamic> userData = userRoleDoc!.data() as Map<String, dynamic>;
      String userType = userData['userType'] ?? '';

      if (userType == 'admin') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => OrganizationHome()));
      } else if (userType == 'worker') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => IndividualHome()));
      } else {
        _displayMessageToUser('Unknown user type: $userType');
        await _auth.signOut();
      }

    } on FirebaseAuthException catch (e) {
      String errorMessage = 'Login failed.';
      if (e.code == 'user-not-found') {
        errorMessage = 'No user found for this email.';
      } else if (e.code == 'wrong-password') {
        errorMessage = 'Incorrect password.';
      }
      _displayMessageToUser(errorMessage);
    } catch (e) {
      _displayMessageToUser('Unexpected error: ${e.toString()}');
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
                      } catch (e) {
                        _displayMessageToUser('Error: ${e.toString()}');
                      } finally {
                        if (mounted) setState(() => _isLoading = false);
                      }
                    }),
                    SizedBox(width: 16),
                    _socialButton('assets/facebook.png', onTap: () {}),
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
