import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: const Color(0xFF8B5CF6),
        secondary: const Color(0xFF06B6D4),
        surface: const Color(0xFF13131A),
        onSurface: Colors.white.withValues(alpha: 0.9),
      ),
      scaffoldBackgroundColor: const Color(0xFF0B0B0F),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF13131A),
        elevation: 0,
        centerTitle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF13131A),
        indicatorColor: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    );
  }
}

/// Eliminates the Android 12+ elastic stretch overscroll distortion.
/// Using [ClampingScrollPhysics] and returning [child] directly from
/// [buildOverscrollIndicator] ensures clean, stable scrolling without
/// stretching or contracting UI elements and text.
class NonStretchingScrollBehavior extends MaterialScrollBehavior {
  const NonStretchingScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}

