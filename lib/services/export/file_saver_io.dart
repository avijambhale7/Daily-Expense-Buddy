import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'file_saver.dart';

Future<FileSaveResult> saveText({
  required String fileName,
  required String content,
  required String mimeType,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/${FileSaver.sanitize(fileName)}');
  // UTF-8 BOM so spreadsheet apps detect the encoding (₹, €, …).
  await file.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(content)]);
  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType)],
      subject: 'Daily Expense Buddy export',
      title: 'Export expenses',
    ),
  );
  return result.status == ShareResultStatus.dismissed
      ? FileSaveResult.dismissed
      : FileSaveResult.shared;
}
