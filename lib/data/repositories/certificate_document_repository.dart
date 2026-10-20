import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/models.dart';

class CertificateDocumentRepository {
  Future<Uint8List> generate(EarnedCertificate certificate) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-Variable.ttf'),
    );
    final document = pw.Document(
      title: 'Certificado ${certificate.code}',
      author: 'EducaDor',
    );
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (_) => pw.Container(
          padding: const pw.EdgeInsets.all(32),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColor.fromHex('#0D9488'), width: 3),
          ),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                'EducaDor',
                style: pw.TextStyle(
                  fontSize: 18,
                  color: PdfColor.fromHex('#0D9488'),
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                'Certificado de conclusão',
                style: const pw.TextStyle(fontSize: 28),
              ),
              pw.SizedBox(height: 24),
              pw.Text(
                'Certificamos que',
                style: const pw.TextStyle(fontSize: 14),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                certificate.employeeName,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 22),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'concluiu o curso',
                style: const pw.TextStyle(fontSize: 14),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                certificate.courseTitle,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(fontSize: 20),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                certificate.companyName,
                style: const pw.TextStyle(fontSize: 14),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Emitido em ${certificate.issuedAt.toLocal().day.toString().padLeft(2, '0')}/${certificate.issuedAt.toLocal().month.toString().padLeft(2, '0')}/${certificate.issuedAt.toLocal().year}',
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                'Código: ${certificate.code}',
                style: const pw.TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
    return document.save();
  }

  Future<void> download(EarnedCertificate certificate) async {
    await Printing.sharePdf(
      bytes: await generate(certificate),
      filename:
          'certificado-${certificate.code.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf',
    );
  }
}
