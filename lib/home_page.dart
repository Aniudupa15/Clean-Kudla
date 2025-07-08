import 'package:cleankudla/auth/loggin_page.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Image.asset(
                  'assets/img.png', // Replace with a relevant image
                  width: double.infinity,
                  height: 400,
                  fit: BoxFit.cover,
                ),
                Container(
                  height: 400,
                  width: double.infinity,
                  color: Colors.black.withOpacity(0.6),
                ),
                Positioned(
                  top: 80,
                  left: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Clean Kudla",
                        style: GoogleFonts.poppins(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        "Smart Sanitation for Smart Mangaluru",
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 15),
                      Text(
                        "AI-powered GPS tracking system for\nreal-time monitoring of ward-wise waste collection.",
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                      ),
                      SizedBox(height: 25),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => LoginPage(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text("Get Started", style: TextStyle(color: Colors.black)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Text(
                "Core Features",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  _featureBox(Icons.gps_fixed, "GPS Auto", "Tracking"),
                  _featureBox(Icons.map, "Zone-Wise", "Coverage"),
                  _featureBox(Icons.dashboard, "Live", "Dashboard"),
                ],
              ),
            ),
            SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Text(
                "Why Choose Clean Kudla?",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(height: 20),
            _reasonTile(
              icon: Icons.check_circle,
              title: "Hands-Free Logging",
              subtitle: "Tracks vehicle and worker movement without QR codes or taps.",
            ),
            _reasonTile(
              icon: Icons.check_circle,
              title: "Real-Time Oversight",
              subtitle: "Health officers get live zone status and alert summaries.",
            ),
            _reasonTile(
              icon: Icons.check_circle,
              title: "Citizen Transparency",
              subtitle: "Ward-level status can be verified publicly via web dashboard.",
            ),
            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _featureBox(IconData icon, String line1, String line2) {
    return Container(
      width: 100,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.black, size: 36),
          SizedBox(height: 5),
          Text(line1, textAlign: TextAlign.center),
          Text(line2, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _reasonTile({required IconData icon, required String title, required String subtitle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28),
            SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  SizedBox(height: 5),
                  Text(subtitle, style: TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
