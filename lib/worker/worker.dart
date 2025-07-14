
import 'package:cleankudla/worker/profile_page_faculty.dart';
import 'package:cleankudla/worker/worker%20page.dart';
import 'package:flutter/material.dart';
import '../auth/loggin_page.dart';


class IndividualHome extends StatefulWidget {
  const IndividualHome({super.key});

  @override
  _IndividualHomeState createState() => _IndividualHomeState();
}

class _IndividualHomeState extends State<IndividualHome> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    WorkerPage(),
    ProfilePageFac()
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
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}