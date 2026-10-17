import 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart'
    as impl;

enum FileSaveResult { downloaded, shared, dismissed }

/// Saves a text file: downloads it in the browser, or opens the system share
/// sheet on mobile (so the user decides where the file goes – no broad
/// storage permission is required).
abstract final class FileSaver {
  static Future<FileSaveResult> saveText({
    required String fileName,
    required String content,
    String mimeType = 'text/csv',
  }) => impl.saveText(fileName: fileName, content: content, mimeType: mimeType);

  /// Same as [saveText] for binary files such as PDFs.
  static Future<FileSaveResult> saveBytes({
    required String fileName,
    required List<int> bytes,
    required String mimeType,
  }) => impl.saveBytes(fileName: fileName, bytes: bytes, mimeType: mimeType);

  /// Restricts a file name to safe characters.
  static String sanitize(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'export.csv' : cleaned;
  }
}
