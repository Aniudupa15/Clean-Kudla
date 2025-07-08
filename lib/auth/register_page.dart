import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../faculty/faculty_page.dart';
import 'loggin_page.dart';

class FacultyRegisterPage extends StatefulWidget {
  @override
  _FacultyRegisterPageState createState() => _FacultyRegisterPageState();
}

class _FacultyRegisterPageState extends State<FacultyRegisterPage> {
  final _formKey = GlobalKey<FormState>();
  bool isLoading = false;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _employeeIdController = TextEditingController();

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _employeeIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('Worker Registration – Clean Kudla',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Text(
                'Join Mangaluru’s smart waste monitoring network',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        _buildTextField(_nameController, 'Full Name', 'e.g., Ravi Kumar'),
                        _buildTextField(_emailController, 'Email', 'e.g., user@example.com', isEmail: true),
                        _buildTextField(_phoneController, 'Phone Number', 'e.g., 9876543210'),
                        _buildTextField(_employeeIdController, 'Worker ID', 'e.g., MCC2345'),
                        _buildPasswordField(_passwordController, 'Password'),
                        _buildPasswordField(_confirmPasswordController, 'Confirm Password', isConfirm: true),
                        SizedBox(height: 20),
                        isLoading
                            ? CircularProgressIndicator()
                            : ElevatedButton(
                          onPressed: _submitForm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            padding: EdgeInsets.symmetric(vertical: 14, horizontal: 60),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text('Register', style: TextStyle(color: Colors.white, fontSize: 16)),
                        ),
                        SizedBox(height: 20),
                        InkWell(
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => LoginPage()),
                            );
                          },
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(color: Colors.black, fontSize: 16),
                              children: [
                                TextSpan(text: "Already registered? "),
                                TextSpan(
                                  text: 'Login here',
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
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, String hint,
      {bool isEmail = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) return 'This field is required';
          if (isEmail && !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) return 'Invalid email address';
          return null;
        },
      ),
    );
  }

  Widget _buildPasswordField(TextEditingController controller, String label, {bool isConfirm = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        obscureText: isConfirm ? obscureConfirmPassword : obscurePassword,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          suffixIcon: IconButton(
            icon: Icon(isConfirm
                ? (obscureConfirmPassword ? Icons.visibility_off : Icons.visibility)
                : (obscurePassword ? Icons.visibility_off : Icons.visibility)),
            onPressed: () {
              setState(() {
                if (isConfirm) {
                  obscureConfirmPassword = !obscureConfirmPassword;
                } else {
                  obscurePassword = !obscurePassword;
                }
              });
            },
          ),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) return 'Password is required';
          if (!isConfirm && value.length < 6) return 'Min 6 characters required';
          if (isConfirm && value != _passwordController.text) return 'Passwords do not match';
          return null;
        },
      ),
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      UserCredential userCred = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      await _saveUserData(userCred.user!.uid);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registration submitted for approval')),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => IndividualHome()),
      );
    } on FirebaseAuthException catch (e) {
      String message = switch (e.code) {
        'weak-password' => 'Weak password. Use at least 6 characters.',
        'email-already-in-use' => 'Email already in use.',
        'invalid-email' => 'Invalid email address.',
        _ => 'Error: ${e.message}',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _saveUserData(String userId) async {
    Map<String, dynamic> userData = {
      'uid': userId,
      'email': _emailController.text.trim(),
      'phoneNumber': _phoneController.text.trim(),
      'userType': 'worker',
      'fullName': _nameController.text.trim(),
      'employeeId': _employeeIdController.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _firestore.collection('users').doc(userId).set(userData);
  }
}
