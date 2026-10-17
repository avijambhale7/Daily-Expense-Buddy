import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/dates/local_date.dart';
import '../../domain/models/expense.dart';

/// Premium: a one-month PDF statement (totals, categories, every expense).
///
/// Formatting is passed in so the PDF uses the same currency and date
/// formats as the app. Uses the bundled Inter font, which includes ₹.
abstract final class MonthlyStatement {
  static Future<Uint8List> build({
    required LocalDate month,
    required String monthLabel,
    required String ownerName,
    required List<Expense> expenses,
    required String Function(int minor) amount,
    required String Function(LocalDate date) date,
    required String Function(String categoryId) categoryName,
    DateTime? generatedAt,
  }) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/inter/Inter-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/inter/Inter-Bold.ttf'),
    );
    final items = [...expenses]..sort((a, b) => a.date.compareTo(b.date));
    final total = items.fold<int>(0, (s, e) => s + e.amountMinor);
    final byCategory = <String, int>{};
    for (final e in items) {
      byCategory.update(
        e.categoryId,
        (v) => v + e.amountMinor,
        ifAbsent: () => e.amountMinor,
      );
    }
    final categories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final days = DateRange(month.startOfMonth, month.endOfMonth).dayCount;
    const brand = PdfColor.fromInt(0xFF1E63E9);

    final doc = pw.Document(
      title: 'Daily Expense Buddy – $monthLabel',
      author: 'Daily Expense Buddy',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    pw.Widget stat(String label, String value) => pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFFF1F5FF),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 2),
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 12),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: brand, width: 2)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Daily Expense Buddy',
                style: pw.TextStyle(
                  color: brand,
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text('Statement · $monthLabel'),
            ],
          ),
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              generatedAt == null
                  ? ''
                  : 'Generated ${date(LocalDate.fromDateTime(generatedAt))}',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
        build: (context) => [
          pw.SizedBox(height: 12),
          if (ownerName.isNotEmpty)
            pw.Text(ownerName, style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              stat('Total spent', amount(total)),
              pw.SizedBox(width: 8),
              stat('Expenses', '${items.length}'),
              pw.SizedBox(width: 8),
              stat('Average per day', amount(days == 0 ? 0 : total ~/ days)),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'By category',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          if (categories.isEmpty)
            pw.Text('No expenses this month.')
          else
            pw.TableHelper.fromTextArray(
              headers: ['Category', 'Amount', 'Share'],
              data: [
                for (final c in categories)
                  [
                    categoryName(c.key),
                    amount(c.value),
                    '${total == 0 ? 0 : (c.value * 100 / total).round()}%',
                  ],
              ],
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
              ),
              headerDecoration: const pw.BoxDecoration(color: brand),
              cellAlignments: {
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
              },
              cellStyle: const pw.TextStyle(fontSize: 10),
            ),
          pw.SizedBox(height: 18),
          pw.Text(
            'All expenses',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          if (items.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Description', 'Category', 'Payment', 'Amount'],
              data: [
                for (final e in items)
                  [
                    date(e.date),
                    e.description.isEmpty ? '–' : e.description,
                    categoryName(e.categoryId),
                    e.paymentMethod?.label ?? '–',
                    amount(e.amountMinor),
                  ],
              ],
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
              ),
              headerDecoration: const pw.BoxDecoration(color: brand),
              cellAlignments: {4: pw.Alignment.centerRight},
              cellStyle: const pw.TextStyle(fontSize: 9),
              oddRowDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF7F8FA),
              ),
            ),
        ],
      ),
    );
    return doc.save();
  }
}
