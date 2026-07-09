import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'state/app_state.dart';
import 'pages/home_page.dart';

TextTheme _applyFont(String fontFamily, TextTheme base) {
  switch (fontFamily) {
    case 'Roboto':
      return GoogleFonts.robotoTextTheme(base);
    case 'Lato':
      return GoogleFonts.latoTextTheme(base);
    case 'Merriweather':
      return GoogleFonts.merriweatherTextTheme(base);
    case 'Open Sans':
      return GoogleFonts.openSansTextTheme(base);
    default:
      return GoogleFonts.interTextTheme(base);
  }
}

ThemeData _buildTheme(Brightness brightness, String fontFamily) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3B6CF4),
    brightness: brightness,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    brightness: brightness,
  );
  final textTheme = _applyFont(fontFamily, base.textTheme);

  return base.copyWith(
    textTheme: textTheme,
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
      thickness: 0.5,
      space: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}

class DartLingvoApp extends ConsumerWidget {
  const DartLingvoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final fontFamily = ref.watch(fontFamilyProvider);
    final textScale = ref.watch(textScaleProvider);

    return MaterialApp(
      title: 'DartLingvo',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: _buildTheme(Brightness.light, fontFamily),
      darkTheme: _buildTheme(Brightness.dark, fontFamily),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        );
      },
      home: const HomePage(),
    );
  }
}
