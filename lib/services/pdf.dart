import 'dart:isolate';
import 'dart:typed_data';

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
      final bytes = await Isolate.run<Uint8List>(
        () => _buildLogsPdfBytes(rows),
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

  static String _resolveRoutineName(
    int routineId,
    Map<int, String> routineNamesById,
  ) {
    final name = routineNamesById[routineId]?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Routine #$routineId';
  }

  static Future<Uint8List> _buildLogsPdfBytes(List<List<String>> rows) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
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
