import 'package:flutter/material.dart';

import '../services/tv_mode.dart';

/// The style every Filled/Outlined button that sits directly in a Row needs.
///
/// The button themes below set `minimumSize: Size.fromHeight(52)`, and Flutter
/// defines `Size.fromHeight(h)` as `Size(double.infinity, h)` — an infinite
/// MINIMUM width. That is what makes form buttons span their Column: a Column
/// bounds its children's width, so the infinity clamps to it. A Row does the
/// opposite, handing non-flex children unbounded width, so the button really
/// does demand infinity, RenderFlex throws 'BoxConstraints forces an infinite
/// width', and the framework then skips painting the whole row. The button is
/// built, holds correct data, and is simply never drawn — which reads like a
/// data bug and is not one.
///
/// Only minimumSize is set, so colour, shape and text style still come from the
/// theme. test/button_theme_row_test.dart guards both halves of this.
/// The bundled UI typeface (assets/fonts, declared in pubspec.yaml).
const kAppFontFamily = 'Inter';

const kInlineButtonStyle = ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size(0, 46)),
);

/// Fathom's visual identity. Material 3, dark-first, soft-indigo accent,
/// generously rounded surfaces (the Fladder-adjacent modern look).
class AppTheme {
  static const seed = Color(0xFF6C8CFF);

  static ThemeData dark(Color accent, {bool amoled = false}) {
    final scheme =
        ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark);
    return _base(amoled
        ? scheme.copyWith(
            surface: Colors.black,
            surfaceContainerLowest: Colors.black,
          )
        : scheme);
  }

  static ThemeData light(Color accent) => _base(
      ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.light));

  static ThemeData _base(ColorScheme scheme) {
    // Inter for its clean, tight, modern letterforms, which suit the bold
    // editorial headers below. Bundled (assets/fonts), not fetched from Google
    // at runtime: no third-party request from a self-hosted media app, and the
    // right font on a first launch with no internet.
    final baseText = (scheme.brightness == Brightness.dark
            ? Typography.material2021().white
            : Typography.material2021().black)
        .apply(fontFamily: kAppFontFamily);
    // Bold, tightly-tracked headers give Fathom a more premium, editorial feel.
    final textTheme = baseText.copyWith(
      displayLarge: baseText.displayLarge
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.0),
      displayMedium: baseText.displayMedium
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
      displaySmall: baseText.displaySmall
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
      headlineMedium: baseText.headlineMedium
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineSmall: baseText.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: baseText.titleLarge
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
      titleMedium:
          baseText.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      labelLarge: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );

    // Larger, tighter page headers give every screen a more editorial weight.
    final appBarTitle = textTheme.headlineSmall
        ?.copyWith(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.4);

    return ThemeData(
      colorScheme: scheme,
      fontFamily: kAppFontFamily,
      textTheme: textTheme,
      // Transparent so the app-shell's ambient wash shows through the content,
      // not just behind the sidebar. A base surface is painted below everything
      // in app.dart, so out-of-shell routes still have a solid backdrop.
      scaffoldBackgroundColor: Colors.transparent,
      visualDensity: VisualDensity.comfortable,
      // TV ONLY: a bold focus tint so D-pad focus is unmistakable from the couch
      // on ListTile rows / InkWell / native buttons app-wide (the audit found the
      // old subtle tint read as "nothing selected"). Framework default off TV so
      // desktop and mobile are unchanged.
      focusColor: isTvDevice ? scheme.primary.withValues(alpha: 0.34) : null,
      // A softer, more organic ripple than the default.
      splashFactory: InkSparkle.splashFactory,
      // Gentle cross-fades between pages on every platform.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        // Translucent so the ambient wash reads through the bar, glassy rather
        // than a flat slab. A hairline underline keeps it defined when content
        // scrolls beneath.
        backgroundColor: scheme.surface.withValues(alpha: 0.55),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 64,
        centerTitle: false,
        titleTextStyle: appBarTitle,
        shape: Border(
          bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.25)),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: textTheme.titleSmall,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor:
              WidgetStatePropertyAll(scheme.surfaceContainerHigh),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16))),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(
            fontFamily: kAppFontFamily,
            color: scheme.onInverseSurface,
            fontSize: 12.5),
        waitDuration: const Duration(milliseconds: 500),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.28),
        thickness: 0.6,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.primary.withValues(alpha: 0.22),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.14),
        trackHeight: 4,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primary.withValues(alpha: 0.16),
      ),
      listTileTheme: ListTileThemeData(
        selectedColor: scheme.primary,
        iconColor: scheme.onSurfaceVariant,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          // The family is named here because a button's own text style
          // replaces the theme's, and without it labels fall back to the
          // system font.
          textStyle: const TextStyle(
              fontFamily: kAppFontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ).copyWith(
          // TV ONLY: D-pad focus adds a bold ring (fill unchanged). Off TV this
          // resolves to null, so desktop/mobile buttons are unchanged.
          side: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.focused) && isTvDevice
                  ? BorderSide(color: scheme.onPrimary, width: 3)
                  : null),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          // The family is named here because a button's own text style
          // replaces the theme's, and without it labels fall back to the
          // system font.
          textStyle: const TextStyle(
              fontFamily: kAppFontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ).copyWith(
          // TV ONLY: focused outlined buttons fill + thick ring. Off TV, the
          // focused branch is skipped so the default outline is used (unchanged).
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.focused) && isTvDevice
                  ? scheme.primary.withValues(alpha: 0.22)
                  : null),
          side: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.focused) && isTvDevice
                  ? BorderSide(color: scheme.primary, width: 3)
                  : BorderSide(color: scheme.outline)),
        ),
      ),
      // TV ONLY. A D-pad remote must never land on an invisible target, so
      // focused IconButtons/TextButtons get a bold accent ring + soft fill. These
      // themes are applied ONLY on a TV (null elsewhere), so desktop and mobile
      // keep the framework defaults exactly — including desktop keyboard focus.
      iconButtonTheme: isTvDevice
          ? IconButtonThemeData(
              style: ButtonStyle(
                shape: const WidgetStatePropertyAll(CircleBorder()),
                overlayColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.focused)
                        ? scheme.primary.withValues(alpha: 0.22)
                        : null),
                side: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.focused)
                        ? BorderSide(color: scheme.primary, width: 2.5)
                        : null),
              ),
            )
          : null,
      textButtonTheme: isTvDevice
          ? TextButtonThemeData(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.focused)
                        ? scheme.primary.withValues(alpha: 0.16)
                        : null),
                side: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.focused)
                        ? BorderSide(color: scheme.primary, width: 2)
                        : null),
              ),
            )
          : null,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainer,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      chipTheme: ChipThemeData(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
        selectedIconTheme: IconThemeData(color: scheme.primary),
        selectedLabelTextStyle: TextStyle(
            fontFamily: kAppFontFamily,
            color: scheme.primary,
            fontWeight: FontWeight.w700),
        unselectedIconTheme:
            IconThemeData(color: scheme.onSurfaceVariant),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        modalBackgroundColor: scheme.surfaceContainerHigh,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
