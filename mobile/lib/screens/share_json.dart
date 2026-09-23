import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Writes [json] to a temp file and opens the OS share sheet for it - the
/// export mechanism, since a sandboxed app can't just "save to a folder"
/// without either this or a full storage-permission flow. The user picks
/// where it actually ends up (Drive, email, Downloads via "Save to
/// device", ...). Shared by character export/import and the homebrew
/// catalog export.
Future<void> shareJson(
  BuildContext context,
  String json,
  String fileName,
) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(json);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], subject: fileName),
  );
}

/// Same mechanism as [shareJson], for binary output (the PDF character
/// sheet export) instead of a text file.
Future<void> shareBytes(
  BuildContext context,
  Uint8List bytes,
  String fileName,
) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], subject: fileName),
  );
}
