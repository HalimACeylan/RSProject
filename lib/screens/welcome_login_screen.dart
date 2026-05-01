import 'package:flutter/material.dart';
import 'package:fridge_app/routes.dart';

class WelcomeLoginScreen extends StatelessWidget {
  const WelcomeLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          Image.asset('assets/images/welcome_bg.png', fit: BoxFit.cover),
          // Gradient Overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.2),
                  Colors.transparent,
                  Colors.black.withOpacity(0.6),
                ],
              ),
            ),
          ),
          // Content
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          const SizedBox(height: 32),
                          // Logo Area
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: const Color(0xFF13EC13),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF13EC13,
                                  ).withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            transform: Matrix4.rotationZ(0.05), // ~3 degrees
                            child: const Icon(
                              Icons.kitchen,
                              color: Color(0xFF102210),
                              size: 36,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'FridgeFresh',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 40),
                            child: Text(
                              'Eat fresh, waste less. Scan receipts & find recipes instantly.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const Spacer(),
                          // Bottom Sheet / Login Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.85),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(32),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 40,
                                  offset: const Offset(0, -10),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Handle
                                Container(
                                  width: 48,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(height: 32),
                                // Get Started Button
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.pushNamed(
                                      context,
                                      AppRoutes.insideFridge,
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF13EC13),
                                    foregroundColor: Colors.black,
                                    minimumSize: const Size(
                                      double.infinity,
                                      56,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Get Started',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(Icons.arrow_forward),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // I have an account Button
                                OutlinedButton(
                                  onPressed: () {},
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.grey[800],
                                    side: const BorderSide(
                                      color: Color(0xFFF3F4F6),
                                      width: 2,
                                    ),
                                    minimumSize: const Size(
                                      double.infinity,
                                      56,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'I have an account',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 32),
                                // Social Divider
                                Row(
                                  children: [
                                    Expanded(
                                      child: Divider(color: Colors.grey[200]),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      child: Text(
                                        'Or continue with',
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Divider(color: Colors.grey[200]),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 32),
                                // Social Row
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildSocialButton(
                                      child: Image.asset(
                                        'assets/images/google_logo.png',
                                        width: 24,
                                        height: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    _buildSocialButton(
                                      child: const Icon(
                                        Icons.apple,
                                        size: 24,
                                        color: Colors.black,
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    _buildSocialButton(
                                      child: const Icon(
                                        Icons.facebook,
                                        size: 24,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pushNamed(
                                      context,
                                      AppRoutes.insideFridge,
                                    );
                                  },
                                  child: const Text(
                                    'Continue as Guest',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialButton({required Widget child}) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(child: child),
    );
  }
}
