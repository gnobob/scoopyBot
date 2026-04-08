import 'package:flutter/material.dart';
import 'dashboard.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await NotificationService.instance.init();
  } catch (e) {
    debugPrint('NotificationService init failed: $e');
  }

  runApp(const ScoopyApp());
}

class ScoopyApp extends StatelessWidget {
  const ScoopyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const Home(),
    );
  }
}

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1D1E33), Color(0xFF0A0E21)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueAccent.withAlpha(50),
                border: Border.all(color: Colors.blueAccent, width: 2),
              ),
              child: const Icon(Icons.smart_toy_outlined,
                  size: 100, color: Colors.blueAccent),
            ),
            const SizedBox(height: 30),
            const Text(
              "SCOOPY BOT",
              style: TextStyle(
                  fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4),
            ),
            const SizedBox(height: 80),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const Dashboard()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 50, vertical: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blueAccent.withAlpha(100),
                      blurRadius: 15,
                    )
                  ],
                  gradient: const LinearGradient(
                      colors: [Colors.blueAccent, Colors.cyan]),
                ),
                child: const Text(
                  "LET'S SCOOP",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}