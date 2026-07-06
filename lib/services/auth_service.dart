import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Check if user is guest
  Future<bool> isGuestUser() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isGuest') ?? false;
  }

  // Sign up with email and password
  // Sign up with email and password
  Future<UserCredential?> signUpWithEmailPassword({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      // Create user in Firebase Auth
      final UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password);

      // Update display name
      await userCredential.user?.updateDisplayName(name);

      // Save user data to Firestore (with error handling)
      try {
        await _firestore.collection('users').doc(userCredential.user!.uid).set({
          'name': name,
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
          'isGuest': false,
        });
        debugPrint('✅ User data saved to Firestore');
      } catch (firestoreError) {
        // Log Firestore error but don't fail the sign-up
        debugPrint(
          '⚠️ Failed to save to Firestore (non-critical): $firestoreError',
        );
      }

      // Save to SharedPreferences (always do this regardless of Firestore)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('name', name);
      await prefs.setString('email', email);
      await prefs.setBool('is_logged_in', true);
      await prefs.setBool('isGuest', false);
      await prefs.setString('userId', userCredential.user!.uid);

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      debugPrint('❌ SignUp Error: $e');
      throw 'An unexpected error occurred. Please try again.';
    }
  }

  // Sign in with email and password
  Future<UserCredential?> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final UserCredential userCredential = await _auth
          .signInWithEmailAndPassword(email: email, password: password);

      // Determine fallback name priority:
      // 1. Firebase Auth displayName (most reliable)
      // 2. Existing SharedPreferences
      // 3. 'User' as last resort
      final prefs = await SharedPreferences.getInstance();
      String fallbackName = userCredential.user?.displayName ?? 
                           prefs.getString('name') ?? 
                           'User';

      // Get user data from Firestore (with error handling - non-critical)
      String userName = fallbackName;
      try {
        final userDoc = await _firestore
            .collection('users')
            .doc(userCredential.user!.uid)
            .get();
        
        if (userDoc.exists && userDoc.data()?['name'] != null) {
          userName = userDoc.data()!['name'];
          debugPrint('✅ User data fetched from Firestore: $userName');
        } else {
          debugPrint('⚠️ Firestore doc missing or no name, using fallback: $fallbackName');
        }
      } catch (firestoreError) {
        // Log Firestore error but don't fail the sign-in
        debugPrint(
          '⚠️ Failed to fetch from Firestore (non-critical): $firestoreError',
        );
        debugPrint('ℹ️ Using fallback username: $fallbackName');
      }

      // Save to SharedPreferences (always do this regardless of Firestore)
      await prefs.setString('name', userName);
      await prefs.setString('email', email);
      await prefs.setBool('is_logged_in', true);
      await prefs.setBool('isGuest', false);
      await prefs.setString('userId', userCredential.user!.uid);

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      debugPrint('❌ SignIn Error: $e');
      throw 'An unexpected error occurred. Please try again.';
    }
  }

  // Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // User cancelled the sign-in
        return null;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );

      // Save user data to Firestore (with error handling)
      try {
        // Check if this is a new user
        final isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;

        if (isNewUser) {
          // Create new user document for new users
          await _firestore
              .collection('users')
              .doc(userCredential.user!.uid)
              .set({
                'name': userCredential.user!.displayName ?? 'User',
                'email': userCredential.user!.email ?? '',
                'photoURL': userCredential.user!.photoURL,
                'createdAt': FieldValue.serverTimestamp(),
                'isGuest': false,
                'signInMethod': 'google',
              });
          debugPrint('✅ New Google user created in Firestore');
        } else {
          debugPrint('ℹ️ Existing Google user signed in');
        }
      } catch (firestoreError) {
        // Log Firestore error but don't fail the sign-in
        debugPrint(
          '⚠️ Failed to save to Firestore (non-critical): $firestoreError',
        );
      }

      // Save to SharedPreferences (always do this regardless of Firestore)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('name', userCredential.user!.displayName ?? 'User');
      await prefs.setString('email', userCredential.user!.email ?? '');
      await prefs.setBool('is_logged_in', true);
      await prefs.setBool('isGuest', false);
      await prefs.setString('userId', userCredential.user!.uid);
      if (userCredential.user!.photoURL != null) {
        await prefs.setString('photoURL', userCredential.user!.photoURL!);
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      debugPrint('❌ Google Sign-In Error: $e');
      throw 'Failed to sign in with Google. Please try again.';
    }
  }

  // Continue as Guest (Anonymous Authentication)
  Future<UserCredential?> signInAsGuest() async {
    try {
      final UserCredential userCredential = await _auth.signInAnonymously();

      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('name', 'Guest User');
      await prefs.setString('email', 'guest@buddy.app');
      await prefs.setBool('is_logged_in', true);
      await prefs.setBool('isGuest', true);
      await prefs.setString('userId', userCredential.user!.uid);

      // Save minimal data to Firestore (with error handling - non-critical)
      try {
        await _firestore.collection('users').doc(userCredential.user!.uid).set({
          'name': 'Guest User',
          'isGuest': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
        debugPrint('✅ Guest user data saved to Firestore');
      } catch (firestoreError) {
        // Log Firestore error but don't fail the sign-in
        debugPrint(
          '⚠️ Failed to save to Firestore (non-critical): $firestoreError',
        );
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      debugPrint('❌ Guest SignIn Error: $e');
      throw 'Failed to continue as guest. Please try again.';
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      // Sign out from Google if signed in with Google
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }

      // Sign out from Firebase
      await _auth.signOut();

      // Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      throw 'Failed to sign out. Please try again.';
    }
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Failed to send password reset email. Please try again.';
    }
  }

  // Delete account
  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Delete user data from Firestore
        await _firestore.collection('users').doc(user.uid).delete();

        // Delete user from Firebase Auth
        await user.delete();

        // Clear SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw 'Please log in again to delete your account.';
      }
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Failed to delete account. Please try again.';
    }
  }

  // Convert guest account to permanent account
  Future<UserCredential?> convertGuestToEmailPassword({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null || !user.isAnonymous) {
        throw 'No guest account found';
      }

      // Create credential
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );

      // Link credential to anonymous account
      final userCredential = await user.linkWithCredential(credential);

      // Update display name
      await userCredential.user?.updateDisplayName(name);

      // Update Firestore
      await _firestore.collection('users').doc(user.uid).update({
        'name': name,
        'email': email,
        'isGuest': false,
        'convertedAt': FieldValue.serverTimestamp(),
      });

      // Update SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('name', name);
      await prefs.setString('email', email);
      await prefs.setBool('isGuest', false);

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Failed to convert guest account. Please try again.';
    }
  }

  // Handle Firebase Auth exceptions
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'email-already-in-use':
        return 'An account already exists for this email.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}
