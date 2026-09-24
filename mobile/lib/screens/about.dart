import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The attribution the SRD's CC BY 4.0 license asks for, shown in the
/// app itself as well as the README - every build that ships SRD content
/// carries it.
const srdAttribution =
    'This work includes material from the System Reference Document 5.2.1 '
    '("SRD 5.2.1") by Wizards of the Coast LLC, available at '
    'https://www.dndbeyond.com/srd. The SRD 5.2.1 is licensed under the '
    'Creative Commons Attribution 4.0 International License, available at '
    'https://creativecommons.org/licenses/by/4.0/legalcode.\n\n'
    'Unofficial fan content, not affiliated with or endorsed by Wizards of '
    'the Coast. Dungeons & Dragons and D&D are trademarks of Wizards of the '
    'Coast LLC.';

/// "1.2.0 (build 57)" - pubspec.yaml's version, or the one a CI build
/// passed with --build-name/--build-number.
Future<String> appVersionLabel() async {
  final info = await PackageInfo.fromPlatform();
  return info.buildNumber.isEmpty || info.buildNumber == '0'
      ? info.version
      : '${info.version} (build ${info.buildNumber})';
}

/// Flutter's About dialog: name, version, the SRD attribution, and a
/// "View licenses" page listing every package's license.
Future<void> showAppAbout(BuildContext context) async {
  final version = await appVersionLabel();
  if (!context.mounted) return;
  showAboutDialog(
    context: context,
    applicationName: 'D&D Sheet',
    applicationVersion: version,
    applicationLegalese: srdAttribution,
  );
}
