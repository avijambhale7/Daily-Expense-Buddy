import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'file_saver.dart';

Future<FileSaveResult> saveText({
  required String fileName,
  required String content,
  required String mimeType,
}) async {
  final bytes = utf8.encode('﻿$content');
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: '$mimeType;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = FileSaver.sanitize(fileName)
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return FileSaveResult.downloaded;
}
