import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:buddy/services/auth_service.dart';
import 'package:buddy/views/screens/bottomnavbarscreen/bottom_navbar_screen.dart';
import 'package:buddy/views/screens/onboarding/login_screen.dart';

import 'package:buddy/views/widgets/buddy_loading_indicator.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        debugPrint(
          '🔍 AUTH WRAPPER: connectionState=${snapshot.connectionState}, '
          'hasData=${snapshot.hasData}, user=${snapshot.data?.uid}',
        );

        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          debugPrint('⏳ AUTH WRAPPER: Waiting for auth state...');
          return Scaffold(
            body: BuddyLoadingIndicator.centered(),
          );
        }

        // If user is logged in (including guest), show main app
        if (snapshot.hasData) {
          debugPrint('✅ AUTH WRAPPER: User authenticated, showing home');
          return const BottomNavbarScreen();
        }

        // Otherwise show login screen
        debugPrint('❌ AUTH WRAPPER: No user, showing login');
        return const LoginScreen();
      },
    );
  }
}
