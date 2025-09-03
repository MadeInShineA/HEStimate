import 'package:flutter/material.dart';
import 'package:moon_design/moon_design.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Your pages
import 'listingsView.dart'; // Updated import
import 'new_listing_page.dart';
import 'profile.dart';
import 'about_page.dart';
import 'home.dart'; // DashboardPage lives here
import 'owner_management.dart';
import 'student_management.dart';
import 'tutorial_page.dart';

/// Pages add this mixin to provide menu metadata while staying Stateless/Stateful.
mixin MenuPageMeta {
  String get menuLabel;
  IconData get menuIcon;
  IconData? get menuSelectedIcon => null;
}

/// Moon-flavored menu container:
/// - Phone & Tablet: AppBar + Drawer + Bottom NavigationBar (avec pages limitées)
/// - Desktop: AppBar + Drawer only (toutes les pages)
class MoonMenuShell extends StatefulWidget {
  final List<Widget> allPages;
  final List<int>? bottomNavPageIndices;
  final int initialIndex; // starting tab
  final String? title; // null => current tab label
  final List<Widget>? actions; // extra AppBar actions
  final FloatingActionButton? fab;
  final double desktopBreakpoint; // >= => desktop
  final VoidCallback? onToggleTheme; // top-right theme toggle

  const MoonMenuShell({
    super.key,
    required this.allPages,
    this.bottomNavPageIndices,
    this.initialIndex = 0,
    this.title,
    this.actions,
    this.fab,
    this.desktopBreakpoint = 1100,
    this.onToggleTheme,
  });

  @override
  State<MoonMenuShell> createState() => _MoonMenuShellState();
}

class _MoonMenuShellState extends State<MoonMenuShell> {
  late int _index = widget.initialIndex;

  List<MenuPageMeta> get _allMeta => widget.allPages
      .map((w) {
        if (w is MenuPageMeta) return w as MenuPageMeta;
        throw ArgumentError(
          'All pages passed to MoonMenuShell must mix in MenuPageMeta.',
        );
      })
      .toList(growable: false);

  List<int> get _bottomNavIndices =>
      widget.bottomNavPageIndices ??
      List.generate(widget.allPages.length, (i) => i);

  int _bottomNavToGlobalIndex(int bottomNavIndex) {
    return _bottomNavIndices[bottomNavIndex];
  }

  int _globalToBottomNavIndex(int globalIndex) {
    return _bottomNavIndices.indexOf(globalIndex);
  }

  List<Widget> _buildActions(BuildContext context, MoonTokens tokens) {
    return [
      // Tutorial button in the app bar
      IconButton(
        tooltip: 'Tutorial',
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TutorialPage()),
          );
        },
        icon: Icon(Icons.help_outline, color: tokens.colors.bulma),
      ),
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
    final isDesktop = width >= widget.desktopBreakpoint;

    // Get Moon tokens via ThemeExtension (fallback to light tokens)
    final moon = Theme.of(context).extension<MoonTheme>();
    final tokens = moon?.tokens ?? MoonTokens.light;

    final allMeta = _allMeta;
    final current = allMeta[_index];
    final page = KeyedSubtree(
      key: ValueKey(_index),
      child: widget.allPages[_index],
    );

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
              for (int i = 0; i < allMeta.length; i++)
                ListTile(
                  leading: Icon(
                    i == _index
                        ? (allMeta[i].menuSelectedIcon ?? allMeta[i].menuIcon)
                        : allMeta[i].menuIcon,
                    color: tokens.colors.bulma,
                  ),
                  title: Text(allMeta[i].menuLabel),
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
      bottomNavigationBar: isDesktop
          ? null
          : Theme(
              data: Theme.of(context).copyWith(
                navigationBarTheme: NavigationBarThemeData(
                  backgroundColor: tokens.colors.gohan,
                  indicatorColor: tokens.colors.piccolo,
                  surfaceTintColor: Colors.transparent,
                  iconTheme: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return IconThemeData(
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.white
                            : tokens.colors.bulma,
                      );
                    }
                    return IconThemeData(color: tokens.colors.bulma);
                  }),
                ),
              ),
              child: NavigationBar(
                selectedIndex: _globalToBottomNavIndex(_index)
                    .clamp(0, _bottomNavIndices.length - 1),
                onDestinationSelected: (bottomNavIndex) {
                  setState(() =>
                      _index = _bottomNavToGlobalIndex(bottomNavIndex));
                },
                destinations: [
                  for (final globalIndex in _bottomNavIndices)
                    NavigationDestination(
                      icon: Icon(_allMeta[globalIndex].menuIcon),
                      selectedIcon: Icon(
                        _allMeta[globalIndex].menuSelectedIcon ??
                            _allMeta[globalIndex].menuIcon,
                      ),
                      label: _allMeta[globalIndex].menuLabel,
                    ),
                ],
              ),
            ),
    );
  }
}

/// Convenience: a ready-made "menu home" page using the sections below.
class HomeMenuPage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const HomeMenuPage({super.key, required this.onToggleTheme});

  @override
  State<HomeMenuPage> createState() => _HomeMenuPageState();
}

class _HomeMenuPageState extends State<HomeMenuPage> {
  bool _isHomeowner = false;
  bool _isStudent = false;

  @override
  void initState() {
    super.initState();
    _checkHomeownerStatus();
  }

  Future<void> _checkHomeownerStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data();
        setState(() {
          _isHomeowner = data?['role'] == "homeowner";
          _isStudent = data?['role'] == "student";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // If an int is passed as route arguments, use it as the initial tab index.
    final maybeIndex = ModalRoute.of(context)?.settings.arguments as int?;

    // Build pages list based on homeowner/student status
    final pages = <Widget>[
      const DashboardPage(),         // 0
      const ListingsSection(),       // 1
      if (_isHomeowner) ...[
        const MyListingsSection(),
        const NewListingSection(),
        const OwnerManagementSection(),
      ],
      if (_isStudent) ...[
        const StudentManagementSection(),
      ],
      const ProfileSection(),
      const AboutSection(),
    ];

    // Helper to find page indices by type safely.
    int idxOf<T>() => pages.indexWhere((w) => w is T);

    final dashboardIdx = idxOf<DashboardPage>();
    final propertiesIdx = idxOf<ListingsSection>();
    final myPropsIdx = idxOf<MyListingsSection>();
    final newIdx = idxOf<NewListingSection>();
    final manageOwnerIdx = idxOf<OwnerManagementSection>();
    final manageStudentIdx = idxOf<StudentManagementSection>();
    final profileIdx = idxOf<ProfileSection>();
    final aboutIdx = idxOf<AboutSection>();

    // Mobile bottom nav (no invalid -1 indices)
    final bottomNavIndices = _isHomeowner
        ? [
            dashboardIdx,
            propertiesIdx,
            if (myPropsIdx != -1) myPropsIdx,
            if (newIdx != -1) newIdx,
            if (manageOwnerIdx != -1) manageOwnerIdx,
            profileIdx,
          ].where((i) => i != -1).toList()
        : [
            dashboardIdx,
            propertiesIdx,
            profileIdx,
            aboutIdx,
          ].where((i) => i != -1).toList();

    return MoonMenuShell(
      title: 'HEStimate',
      initialIndex: maybeIndex ?? 0,
      onToggleTheme: widget.onToggleTheme,
      desktopBreakpoint: 1100,
      allPages: pages,
      bottomNavPageIndices: bottomNavIndices,
    );
  }
}

/// ----------------------
/// Sections
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
  Widget build(BuildContext context) =>
      const ListingsPage(mode: ListingsMode.all);
}

class MyListingsSection extends StatelessWidget with MenuPageMeta {
  const MyListingsSection({super.key});
  @override
  String get menuLabel => 'My Properties';
  @override
  IconData get menuIcon => Icons.home_outlined;
  @override
  IconData? get menuSelectedIcon => Icons.home;
  @override
  Widget build(BuildContext context) =>
      const ListingsPage(mode: ListingsMode.owner);
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

class OwnerManagementSection extends StatelessWidget with MenuPageMeta {
  const OwnerManagementSection({super.key});
  @override
  String get menuLabel => 'Manage';
  @override
  IconData get menuIcon => Icons.manage_accounts_outlined;
  @override
  IconData? get menuSelectedIcon => Icons.manage_accounts;
  @override
  Widget build(BuildContext context) => const OwnerManagementPage();
}

class StudentManagementSection extends StatelessWidget with MenuPageMeta {
  const StudentManagementSection({super.key});
  @override
  String get menuLabel => 'Manage';
  @override
  IconData get menuIcon => Icons.manage_accounts_outlined;
  @override
  IconData? get menuSelectedIcon => Icons.manage_accounts;
  @override
  Widget build(BuildContext context) => const StudentManagementPage();
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
