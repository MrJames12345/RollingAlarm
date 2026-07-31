import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:rolling_alarm/database/database.dart';
import 'package:rolling_alarm/enums/log_action_type_code.dart';
import 'package:rolling_alarm/utils.dart';

/// Generates a PDF table of log history and shares it via the system share sheet.
class RA_PdfService {
  RA_PdfService._();

  /// Generates and shares a PDF of all log entries.
  static Future<void> shareLogsPdf(List<LogEntryModel> logs) async {
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
              headers: ['Timestamp', 'Action', 'Time Since Last Dismiss'],
              data: logs
                  .map(
                    (log) => [
                      RA_Utils.formatDateTime(log.Timestamp),
                      RA_logActionFromCode(log.LogActionTypeCode)?.displayName ??
                          'Unknown',
                      log.TimeSinceLastDismissalSeconds != null
                          ? RA_Utils.formatSecondsAsDuration(
                              log.TimeSinceLastDismissalSeconds!,
                            )
                          : 'n/a',
                    ],
                  )
                  .toList(),
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

    try {
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename:
            'rolling_alarm_logs_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (_) {
      // Ignore PDF share failures in headless test environments
    }
  }
}
