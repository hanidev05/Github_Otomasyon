import 'package:flutter/material.dart';
import 'ui/pat.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 16, 200, 19),
        ),

  scaffoldBackgroundColor: const Color.fromARGB(255, 88, 142, 189)
      ),
      home: const PatLogin(),
    );
  }
}

