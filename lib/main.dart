import 'package:flutter/material.dart';

import 'ui/home_page.dart';

void main() {
  runApp(const ResumeTermApp());
}

class ResumeTermApp extends StatelessWidget {
  const ResumeTermApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Resume-Term',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F7CAC),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

