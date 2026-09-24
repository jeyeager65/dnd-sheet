import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Exports [json] as a file named [fileName] - the character, homebrew,
/// and backup exports. See [shareBytes].
Future<void> shareJson(BuildContext context, String json, String fileName) =>
    shareBytes(context, Uint8List.fromList(utf8.encode(json)), fileName);

/// Exports [bytes] as a file named [fileName]. On a phone, opens the OS
/// share sheet (Drive, email, "Save to device", ...) - a sandboxed app
/// can't just save to a folder without it or a storage-permission flow.
/// On a desktop, opens a Save As dialog instead: the Windows share panel
/// usually has nothing that accepts a file, and fails with "We couldn't
/// show you all the ways you could share".
Future<void> shareBytes(
  BuildContext context,
  Uint8List bytes,
  String fileName,
) async {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final extension = fileName.contains('.') ? fileName.split('.').last : null;
    final saved = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      dialogTitle: 'Save $fileName',
      type: extension == null ? FileType.any : FileType.custom,
      allowedExtensions: extension == null ? null : [extension],
    );
    if (saved != null) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Saved to ${saved.toFilePath()}')),
      );
    }
    return;
  }
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], subject: fileName),
  );
}
