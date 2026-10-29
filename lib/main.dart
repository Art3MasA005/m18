import 'package:flutter/material.dart';
import 'package:real_time_location_tracker/screens/location_tracker_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RealTimeLocationTrackerApp());
}

class RealTimeLocationTrackerApp extends StatelessWidget {
  const RealTimeLocationTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Real-Time Location Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          primary: Colors.blue,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      home: const LocationTrackerScreen(),
    );
  }
}
