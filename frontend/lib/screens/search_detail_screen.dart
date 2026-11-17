import 'package:flutter/material.dart';

/// Search page (`/searches/<jobId>`). Placeholder created by FE-CORE; the
/// FE-SEARCH agent replaces the body. Page body only (AppShell provides the
/// top bar and navigation).
class SearchDetailScreen extends StatefulWidget {
  final String jobId;

  const SearchDetailScreen({super.key, required this.jobId});

  @override
  State<SearchDetailScreen> createState() => _SearchDetailScreenState();
}

class _SearchDetailScreenState extends State<SearchDetailScreen> {
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Search'));
  }
}
