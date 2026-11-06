import 'package:flutter/material.dart';

import '../dashboard/dashboard_screen.dart';
import '../irrigation/irrigation_screen.dart';
import '../ai/ai_screen.dart';
import '../farm/farm_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedIndex = 0;

  void _onDestinationSelected(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      DashboardScreen(onNavigateTab: _onDestinationSelected),
      const IrrigationScreen(),
      const AIScreen(),
      const FarmScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: screens,
      ),

      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          indicatorColor: const Color(0xFFC8E6C9),
          backgroundColor: Colors.white,
          elevation: 0,
          onDestinationSelected: _onDestinationSelected,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: Color(0xFF1B5E20)),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.water_drop_outlined),
              selectedIcon: Icon(Icons.water_drop_rounded, color: Color(0xFF1B5E20)),
              label: 'Irrigation',
            ),
            NavigationDestination(
              icon: Icon(Icons.smart_toy_outlined),
              selectedIcon: Icon(Icons.smart_toy_rounded, color: Color(0xFF1B5E20)),
              label: 'AI Doctor',
            ),
            NavigationDestination(
              icon: Icon(Icons.agriculture_outlined),
              selectedIcon: Icon(Icons.agriculture_rounded, color: Color(0xFF1B5E20)),
              label: 'Farm',
            ),
          ],
        ),
      ),
    );
  }
}

