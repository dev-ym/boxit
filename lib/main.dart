import 'package:flutter/material.dart';
import 'home_page.dart';

void main() => runApp(const BoxItApp());

class BoxItApp extends StatelessWidget {
  const BoxItApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BoxIt',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F3460),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}
