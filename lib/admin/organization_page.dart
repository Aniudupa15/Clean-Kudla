
import 'package:cleankudla/admin/admin%20page.dart';
import 'package:cleankudla/admin/completed_map.dart';
import 'package:cleankudla/admin/profile_page_organization.dart';
import 'package:flutter/material.dart';
import '../auth/loggin_page.dart';


class OrganizationHome extends StatefulWidget {
  const OrganizationHome({super.key});

  @override
  _OrganizationHomeState createState() => _OrganizationHomeState();
}

class _OrganizationHomeState extends State<OrganizationHome> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    AllCollectedAreasMapPage(),
    AdminRoute(),
    ProfilePageOrg()
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _logout(BuildContext context) {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}