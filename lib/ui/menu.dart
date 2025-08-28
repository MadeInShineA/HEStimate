// lib/ui/menu.dart
import 'package:flutter/material.dart';
import 'package:moon_design/moon_design.dart';

// Your pages
import 'property_list.dart';
import 'new_listing_page.dart';
import 'profile.dart';
import 'about_page.dart';
import 'home.dart'; // DashboardPage lives here

/// Pages add this mixin to provide menu metadata while staying Stateless/Stateful.
mixin MenuPageMeta {
  String get menuLabel;
  IconData get menuIcon;
  IconData? get menuSelectedIcon => null;
}

/// Adaptive Moon-flavored menu container:
/// - Phones & Tablets: AppBar + Drawer + Bottom NavigationBar
/// - Desktop (wide screens): Purple NavigationRail + AppBar
class MoonMenuShell extends StatefulWidget {
  final List<Widget> pages; // Widgets that also mix in MenuPageMeta
  final int initialIndex; // starting tab
  final String? title; // null => current tab label
  final List<Widget>? actions; // extra AppBar actions
  final FloatingActionButton? fab;

  /// We treat widths < desktopBreakpoint as "compact" (phone-style UI).
  /// This keeps tablets looking like phones, as requested.
  final double desktopBreakpoint; // >= => desktop rail
  final VoidCallback? onToggleTheme; // top-right theme toggle

  const MoonMenuShell({
    super.key,
    required this.pages,
    this.initialIndex = 0,
    this.title,
    this.actions,
    this.fab,
    this.desktopBreakpoint = 1100, // phone/tablet below this, desktop at/above
    this.onToggleTheme,
  });

  @override
  State<MoonMenuShell> createState() => _MoonMenuShellState();
}

class _MoonMenuShellState extends State<MoonMenuShell> {
  late int _index = widget.initialIndex;

  List<MenuPageMeta> get _meta => widget.pages
      .map((w) {
        if (w is MenuPageMeta) return w as MenuPageMeta;
        throw ArgumentError(
          'All pages passed to MoonMenuShell must mix in MenuPageMeta.',
        );
      })
      .toList(growable: false);

  List<Widget> _buildActions(BuildContext context, MoonTokens tokens) {
    return [
      ...?widget.actions,
      if (widget.onToggleTheme != null)
        IconButton(
          tooltip: 'Toggle theme',
          onPressed: widget.onToggleTheme,
          icon: Icon(
            Theme.of(context).brightness == Brightness.dark
                ? Icons.dark_mode
                : Icons.light_mode,
            color: tokens.colors.bulma,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= widget.desktopBreakpoint; // desktop only here

    // Get Moon tokens via ThemeExtension (fallback to light tokens)
    final moon = Theme.of(context).extension<MoonTheme>();
    final tokens = moon?.tokens ?? MoonTokens.light;

    final meta = _meta;
    final current = meta[_index];
    final page = KeyedSubtree(
      key: ValueKey(_index),
      child: widget.pages[_index],
    );

    if (!isDesktop) {
      // PHONE & TABLET: AppBar + Drawer + Bottom NavigationBar
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title ?? current.menuLabel),
          backgroundColor: tokens.colors.gohan,
          foregroundColor: tokens.colors.bulma,
          elevation: 0,
          actions: _buildActions(context, tokens),
        ),
        drawer: Drawer(
          backgroundColor: tokens.colors.goku,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                const SizedBox(height: 8),
                for (int i = 0; i < meta.length; i++)
                  ListTile(
                    leading: Icon(
                      i == _index
                          ? (meta[i].menuSelectedIcon ?? meta[i].menuIcon)
                          : meta[i].menuIcon,
                      color: tokens.colors.bulma,
                    ),
                    title: Text(meta[i].menuLabel),
                    selected: i == _index,
                    onTap: () {
                      Navigator.of(context).pop();
                      setState(() => _index = i);
                    },
                  ),
              ],
            ),
          ),
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: page,
        ),
        floatingActionButton: widget.fab,
        bottomNavigationBar: NavigationBar(
          backgroundColor: tokens.colors.gohan,
          indicatorColor: tokens.colors.piccolo,
          surfaceTintColor: Colors.transparent,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final m in meta)
              NavigationDestination(
                icon: Icon(m.menuIcon, color: tokens.colors.bulma),
                selectedIcon: Icon(
                  m.menuSelectedIcon ?? m.menuIcon,
                  color: tokens.colors.bulma,
                ),
                label: m.menuLabel,
              ),
          ],
        ),
      );
    }

    // DESKTOP: Purple NavigationRail + AppBar
    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            child: NavigationRail(
              backgroundColor: tokens.colors.piccolo, // purple rail bg
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              extended: true, // labels visible on desktop
              selectedIconTheme: IconThemeData(color: tokens.colors.bulma),
              unselectedIconTheme: IconThemeData(
                color: tokens.colors.bulma.withOpacity(0.8),
              ),
              destinations: [
                for (final m in meta)
                  NavigationRailDestination(
                    icon: Icon(m.menuIcon),
                    selectedIcon: Icon(m.menuSelectedIcon ?? m.menuIcon),
                    label: Text(
                      m.menuLabel,
                      style: TextStyle(color: tokens.colors.bulma),
                    ),
                  ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Scaffold(
              appBar: AppBar(
                title: Text(widget.title ?? current.menuLabel),
                backgroundColor: tokens.colors.piccolo, // purple app bar
                foregroundColor: tokens.colors.bulma,
                elevation: 0,
                actions: _buildActions(context, tokens),
              ),
              body: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: page,
              ),
              floatingActionButton: widget.fab,
            ),
          ),
        ],
      ),
    );
  }
}

/// Convenience: a ready-made “menu home” page using the sections below.
/// - Phone & Tablet: phone-style UI
/// - Desktop: purple NavigationRail
class HomeMenuPage extends StatelessWidget {
  final VoidCallback onToggleTheme;
  const HomeMenuPage({super.key, required this.onToggleTheme});

  @override
  Widget build(BuildContext context) {
    // If an int is passed as route arguments, use it as the initial tab index.
    final maybeIndex = ModalRoute.of(context)?.settings.arguments as int?;
    return MoonMenuShell(
      title: 'HEStimate',
      initialIndex: maybeIndex ?? 0,
      onToggleTheme: onToggleTheme,
      desktopBreakpoint: 1100, // tablets use phone UI; desktop gets rail
      pages: const [
        DashboardPage(), // from home.dart
        ListingsSection(),
        NewListingSection(),
        ProfileSection(),
        AboutSection(),
      ],
    );
  }
}

/// ----------------------
/// Other sections
/// ----------------------
class ListingsSection extends StatelessWidget with MenuPageMeta {
  const ListingsSection({super.key});
  @override
  String get menuLabel => 'Properties';
  @override
  IconData get menuIcon => Icons.apartment_outlined;
  @override
  IconData? get menuSelectedIcon => Icons.apartment;
  @override
  Widget build(BuildContext context) => const ListingsPage();
}

class NewListingSection extends StatelessWidget with MenuPageMeta {
  const NewListingSection({super.key});
  @override
  String get menuLabel => 'New';
  @override
  IconData get menuIcon => Icons.add_box_outlined;
  @override
  IconData? get menuSelectedIcon => Icons.add_box;
  @override
  Widget build(BuildContext context) => const NewListingPage();
}

class ProfileSection extends StatelessWidget with MenuPageMeta {
  const ProfileSection({super.key});
  @override
  String get menuLabel => 'Profile';
  @override
  IconData get menuIcon => Icons.person_outline;
  @override
  IconData? get menuSelectedIcon => Icons.person;
  @override
  Widget build(BuildContext context) => const ProfilePage();
}

class AboutSection extends StatelessWidget with MenuPageMeta {
  const AboutSection({super.key});
  @override
  String get menuLabel => 'About';
  @override
  IconData get menuIcon => Icons.info_outline;
  @override
  IconData? get menuSelectedIcon => Icons.info;
  @override
  Widget build(BuildContext context) => const AboutPage();
}
