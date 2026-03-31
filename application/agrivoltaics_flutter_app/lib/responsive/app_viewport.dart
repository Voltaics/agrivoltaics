import 'package:agrivoltaics_flutter_app/app_constants.dart';
import 'package:flutter/widgets.dart';

enum AppViewport {
  mobilePortrait,
  mobileLandscape,
  desktop,
}

class AppViewportInfo {
  const AppViewportInfo._(this.viewport);

  final AppViewport viewport;

  bool get isDesktop => viewport == AppViewport.desktop;
  bool get isMobileLandscape => viewport == AppViewport.mobileLandscape;
  bool get isMobilePortrait => viewport == AppViewport.mobilePortrait;

  static AppViewportInfo fromMediaQuery(MediaQueryData mediaQuery) {
    final size = mediaQuery.size;
    final orientation = mediaQuery.orientation;

    if (size.width >= AppConstants.desktopMinWidth) {
      return const AppViewportInfo._(AppViewport.desktop);
    }

    if (orientation == Orientation.landscape) {
      return const AppViewportInfo._(AppViewport.mobileLandscape);
    }

    return const AppViewportInfo._(AppViewport.mobilePortrait);
  }
}
