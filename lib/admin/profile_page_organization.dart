import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../home_page.dart';

class ProfilePageOrg extends StatefulWidget {
  const ProfilePageOrg({super.key});

  @override
  State<ProfilePageOrg> createState() => _ProfilePageOrgState();
}

class _ProfilePageOrgState extends State<ProfilePageOrg> {
  String userName = "N/A";
  String email = "N/A";
  String mobileNumber = "N/A";
  String dateOfBirth = "N/A";
  String address = "N/A";
  String organizationName = "N/A";
  String? imageUrl;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    fetchUserData();
    _requestPermissions();
  }

  Future<void> fetchUserData() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (userDoc.exists) {
        setState(() {
          userName = userDoc.data()?['fullName'] ?? "N/A";
          email = userDoc.data()?['email'] ?? "N/A";
          mobileNumber = userDoc.data()?['Mobile Number'] ?? "N/A";
          dateOfBirth = userDoc.data()?['Date of Birth'] ?? "N/A";
          address = userDoc.data()?['Address'] ?? "N/A";
          organizationName = userDoc.data()?['Organization Name'] ?? "N/A";
          imageUrl = userDoc.data()?['imageUrl'];
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error fetching user data: $e");
      }
    }
  }

  Future<void> saveUserData(String field, String value) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .update({field: value});

      setState(() {
        if (field == 'username') userName = value;
        if (field == 'email') email = value;
        if (field == 'Mobile Number') mobileNumber = value;
        if (field == 'Date of Birth') dateOfBirth = value;
        if (field == 'Address') address = value;
        if (field == 'Organization Name') organizationName = value;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Changes saved successfully!'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        print("Error saving user data: $e");
      }
    }
  }

  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    await Permission.storage.request();
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 500,
      maxHeight: 500,
    );

    if (pickedFile != null) {
      setState(() {
        imageUrl = pickedFile.path;
      });
    }
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (context) => const HomePage()));
  }

  void _showEditDialog(String title, String field, String currentValue) {
    TextEditingController controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit $title'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: 'Enter new $title'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                saveUserData(field, controller.text);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FC),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: CircleAvatar(
                    radius: 75,
                    backgroundColor: Colors.indigo.shade100,
                    backgroundImage:
                    imageUrl != null ? FileImage(File(imageUrl!)) : null,
                    child: imageUrl == null
                        ? const Icon(Icons.camera_alt, size: 40, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(height: 25),
                Text(
                  userName,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo),
                ),
                const SizedBox(height: 10),
                Text(
                  email,
                  style: const TextStyle(fontSize: 16, color: Colors.black54),
                ),
                const SizedBox(height: 25),
                buildEditableField("Mobile Number", mobileNumber, "Mobile Number"),
                buildEditableField("Date of Birth", dateOfBirth, "Date of Birth"),
                buildEditableField("Address", address, "Address"),
                buildEditableField("Organization", organizationName, "Organization Name"),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout,color: Colors.white,),
                  label: const Text("Logout",style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildEditableField(String title, String value, String field) {
    return GestureDetector(
      onTap: () => _showEditDialog(title, field, value),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.indigo.withOpacity(0.1),
              spreadRadius: 2,
              blurRadius: 6,
              offset: const Offset(0, 3),
            )
          ],
        ),
        child: Row(
          children: [
            Text(
              "$title: ",
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: Colors.indigo,
              ),
            ),
            Flexible(
              child: Text(
                value,
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
