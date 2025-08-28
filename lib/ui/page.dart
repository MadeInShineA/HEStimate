import 'package:flutter/material.dart';

class BasePage extends StatelessWidget {
  final String title;
  final Widget child;
  final bool scrollable;
  final EdgeInsetsGeometry padding;
  final List<Widget>? actions;

  const BasePage({
    super.key,
    required this.title,
    required this.child,
    this.scrollable = true,
    this.padding = const EdgeInsets.all(16),
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(padding: padding, child: child);

    if (scrollable) {
      content = SingleChildScrollView(child: content);
    }

    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: SafeArea(child: content),
    );
  }
}
