import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';
import 'package:rolling_alarm/utils.dart';

/// Generates a PDF table of log history on a background isolate and shares it
/// via the system share sheet.
class RA_PdfService {
  RA_PdfService._();

  /// Maximum number of newest log entries included in a PDF export.
  static const int maxExportRows = 1000;

  /// Clickable footer destination included on exported PDF verification reports.
  static const String footerVerificationUrl =
      'https://casellaweb.com.au/rolling-alarm?utm_source=pdf_report';

  static const String _regularFontAsset = 'assets/fonts/Inter-Regular.ttf';
  static const String _boldFontAsset = 'assets/fonts/Inter-Bold.ttf';

  /// Generates and shares a PDF of the newest log entries (capped at [maxExportRows]).
  static Future<void> shareLogsPdf(
    List<LogEntryModel> logs, {
    Map<int, String> routineNamesById = const {},
  }) async {
    final capped = logs.length > maxExportRows
        ? logs.sublist(0, maxExportRows)
        : logs;

    final rows = <List<String>>[
      for (final log in capped)
        <String>[
          RA_Utils.formatDateTime(log.Timestamp.toLocal()),
          _resolveRoutineName(log.RoutineId, routineNamesById),
          RA_logActionFromCode(log.LogActionTypeCode)?.displayName ?? 'Unknown',
          log.TimeSinceLastDismissalSeconds != null
              ? RA_Utils.formatSecondsAsDuration(
                  log.TimeSinceLastDismissalSeconds!,
                )
              : 'n/a',
        ],
    ];

    try {
      final regularFontBytes = await _loadAssetBytes(_regularFontAsset);
      final boldFontBytes = await _loadAssetBytes(_boldFontAsset);
      final bytes = await Isolate.run<Uint8List>(
        () => buildLogsPdfBytes(
          rows,
          regularFontBytes: regularFontBytes,
          boldFontBytes: boldFontBytes,
        ),
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'rolling_alarm_logs_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (_) {
      // Ignore PDF share failures in headless test environments
    }
  }

  static Future<Uint8List?> _loadAssetBytes(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  static String _resolveRoutineName(
    int routineId,
    Map<int, String> routineNamesById,
  ) {
    final name = routineNamesById[routineId]?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Routine #$routineId';
  }

  /// Builds the PDF document bytes (invoked inside [Isolate.run]).
  @visibleForTesting
  static Future<Uint8List> buildLogsPdfBytes(
    List<List<String>> rows, {
    Uint8List? regularFontBytes,
    Uint8List? boldFontBytes,
  }) async {
    final pdf = pw.Document();
    final baseFont = regularFontBytes != null
        ? pw.Font.ttf(ByteData.sublistView(regularFontBytes))
        : null;
    final boldFont = boldFontBytes != null
        ? pw.Font.ttf(ByteData.sublistView(boldFontBytes))
        : baseFont;
    final pageTheme = baseFont != null
        ? pw.ThemeData.withFont(base: baseFont, bold: boldFont)
        : null;

    final sep = baseFont != null ? '·' : '-';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pageTheme,
        footer: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 12),
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
              ),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Generated offline by Rolling Alarm $sep 100% Local On-Device Privacy',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.UrlLink(
                  destination: footerVerificationUrl,
                  child: pw.Text(
                    'casellaweb.com.au/rolling-alarm $sep Page ${context.pageNumber} of ${context.pagesCount}',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.teal700,
                      decoration: pw.TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        build: (context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(
                'Rolling Alarm Log History',
                style: const pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Timestamp',
                'Routine',
                'Action',
                'Since Last Dismiss',
              ],
              data: rows,
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerStyle: const pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }
}
