import 'package:flutter/material.dart';
import 'package:moon_design/moon_design.dart';
import 'page.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String appName = "HEStimate";
  static const String appVersion = "1.0.0";

  // Team data
  static const _team = <_Member>[
    _Member("Filip", "Silivuniuk"),
    _Member("Olivier", "Amaker"),
    _Member("Simon", "Masserey"),
    _Member("Yolan", "Savioz"),
    _Member("Robin", "Bütikofer"),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = BoxDecoration(
      gradient: isDark
          ? const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF0B0F14), Color(0xFF121826)],
            )
          : const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFFF6F7FB), Color(0xFFFFFFFF)],
            ),
    );

    return BasePage(
      title: "About",
      child: Container(
        decoration: bg,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(MoonIcons.arrows_boost_24_regular, size: 20, color: cs.primary),
                          const SizedBox(width: 8),
                          Text(appName,
                              style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              )),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          "HEStimate is a student-focused housing app. "
                          "Students can list, discover, and book properties, compare prices with a predictive model, "
                          "and get practical information such as public transport options.",
                          style: TextStyle(color: cs.onSurface.withOpacity(.85)),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  _SectionCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(MoonIcons.arrows_cross_lines_24_regular, size: 20, color: cs.primary),
                          const SizedBox(width: 8),
                          Text("Team",
                              style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              )),
                        ]),
                        const SizedBox(height: 12),

                        LayoutBuilder(
                          builder: (context, c) {
                            final isWide = c.maxWidth >= 720;
                            final gap = 12.0;
                            final cardW = isWide
                                ? ((c.maxWidth.clamp(600, 1100) - (gap * 2)) / 3)
                                : c.maxWidth;

                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: _team.map((m) {
                                return SizedBox(
                                  width: isWide ? cardW : double.infinity,
                                  child: _MemberCard(member: m, isDark: isDark),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  _SectionCard(
                    isDark: isDark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(MoonIcons.arrows_diagonals_tlbr_24_regular, size: 20, color: cs.primary),
                          const SizedBox(width: 8),
                          Text("Project details",
                              style: TextStyle(
                                color: cs.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              )),
                        ]),
                        const SizedBox(height: 8),
                        _Bullet("Responsive mobile-first UI with dark/light theme (Moon)."),
                        _Bullet("User authentication and profiles."),
                        _Bullet("Property listings with photos and availability."),
                        _Bullet("Search & filters (location, price, type, amenities)."),
                        _Bullet("Booking, reviews, and ratings."),
                        _Bullet("Public transport suggestions and extra info."),
                        _Bullet("Admin view for user management."),
                      ],
                    ),
                  ),

                 

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  const _SectionCard({required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(isDark ? .5 : 1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withOpacity(0.15)),
      ),
      child: child,
    );
  }
}

class _MemberCard extends StatelessWidget {
  final _Member member;
  final bool isDark;
  const _MemberCard({required this.member, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final initials = "${member.first[0]}${member.last[0]}".toUpperCase();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withOpacity(isDark ? .6 : 1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: cs.primary.withOpacity(.12),
            child: Text(initials,
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w800,
                )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("${member.first} ${member.last}",
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                    )),
                Text("Developer",
                    style: TextStyle(
                      color: cs.onSurface.withOpacity(.7),
                    )),
              ],
            ),
          ),
         

        ],
      ),
    );
  }
}

class _Member {
  final String first;
  final String last;
  const _Member(this.first, this.last);
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(MoonIcons.arrows_forward_24_regular, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: cs.onSurface.withOpacity(.9))),
          ),
        ],
      ),
    );
  }
}
