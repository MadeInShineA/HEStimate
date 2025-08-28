import 'package:flutter/material.dart';
import 'package:moon_design/moon_design.dart';

import 'menu.dart'; // for MenuPageMeta

/// ----------------------
/// Dashboard / Landing Page
/// ----------------------
class DashboardPage extends StatelessWidget with MenuPageMeta {
  const DashboardPage({super.key});

  @override
  String get menuLabel => 'Home';
  @override
  IconData get menuIcon => Icons.home_outlined;
  @override
  IconData? get menuSelectedIcon => Icons.home;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<MoonTheme>()?.tokens ?? MoonTokens.light;

    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // App icon
                Icon(
                  Icons.house_rounded,
                  size: 100,
                  color: tokens.colors.piccolo,
                ),
                const SizedBox(height: 24),

                // App name
                Text(
                  "HEStimate",
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Tagline
                Text(
                  "Your student housing companion",
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: tokens.colors.trunks,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Description
                Text(
                  "HEStimate helps students find and share housing with ease. "
                  "Browse affordable rooms and apartments, create listings, and "
                  "connect with the student community — all in one place.",
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: tokens.colors.bulma,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // Footer
                Text(
                  "Built for students, by students 💡",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.colors.trunks,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
