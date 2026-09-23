import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// The official 2024 D&D character sheet PDF - published freely by
/// Wizards of the Coast for players to download and fill in themselves.
/// Fetched once and cached to this device's own app support directory,
/// never bundled with the app itself (nothing of theirs ships in this
/// app's shared source - same "your own legitimate copy, not this app's
/// to redistribute" reasoning as assets/official/README.md, just for a
/// PDF instead of transcribed rules text). domain/character_sheet_pdf.dart
/// draws a character's data on top of a copy of this page - the same as
/// printing it and filling it in by hand, just automated.
const officialSheetUrl =
    'https://media.dndbeyond.com/compendium-images/phb/downloads/'
    'DnD_2024_Character-Sheet.pdf';

Future<File> _cacheFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}/official_character_sheet.pdf');
}

/// Returns the cached sheet's bytes, downloading and caching it first if
/// this is the first time it's needed. Throws if the download fails (no
/// connection, a non-200 response) - there's nothing to overlay onto yet,
/// so callers should catch this and show a clear "couldn't download the
/// sheet, check your connection" message rather than let it surface as a
/// raw exception.
Future<Uint8List> loadOfficialSheetBytes() async {
  final file = await _cacheFile();
  if (await file.exists()) {
    return file.readAsBytes();
  }
  final request = await HttpClient().getUrl(Uri.parse(officialSheetUrl));
  final response = await request.close();
  if (response.statusCode != 200) {
    throw Exception(
      'Could not download the official character sheet '
      '(HTTP ${response.statusCode}).',
    );
  }
  final builder = BytesBuilder();
  await for (final chunk in response) {
    builder.add(chunk);
  }
  final bytes = builder.toBytes();
  await file.writeAsBytes(bytes);
  return bytes;
}
