import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import 'call_history_screen.dart';
import 'dialpad_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundLight,
      body: IndexedStack(
        index: _currentIndex,
        children: const [CallHistoryScreen(), DialpadScreen()],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFEEEEEE), width: 1.0)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          backgroundColor: AppConstants.surfaceLight,
          indicatorColor: AppConstants.accentGreen.withValues(alpha: 0.15),
          elevation: 0,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.phone_in_talk_outlined),
              selectedIcon: Icon(
                Icons.phone_in_talk,
                color: AppConstants.accentGreen,
              ),
              label: 'Cuộc gọi',
            ),
            NavigationDestination(
              icon: Icon(Icons.dialpad_outlined),
              selectedIcon: Icon(
                Icons.dialpad,
                color: AppConstants.accentGreen,
              ),
              label: 'Bàn phím',
            ),
          ],
        ),
      ),
    );
  }
}
