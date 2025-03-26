import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'dart:io';
import 'package:vapp/models/analysis_model.dart'; // Import DataAnalysis model

class AnalysisService {
  static const String baseUrl = 'https://windsurf-backend.onrender.com/api';
  static const int maxFileSize = 10485760; // 10MB to match backend

  Future<DataAnalysis> analyzeFile(String filePath, {Function(double)? onProgress}) async {
    try {
      final file = File(filePath);
      final fileSize = await file.length();

      if (fileSize > maxFileSize) {
        throw Exception('File size exceeds 10MB limit');
      }

      // Parse the file locally
      List<List<dynamic>> data;
      if (filePath.endsWith('.csv')) {
        final rawData = await file.readAsString();
        data = CsvToListConverter().convert(rawData);
      } else if (filePath.endsWith('.xlsx') || filePath.endsWith('.xls')) {
        final bytes = file.readAsBytesSync();
        final excel = Excel.decodeBytes(bytes);
        data = excel.tables[excel.tables.keys.first]!.rows;
      } else {
        throw Exception('Unsupported file type');
      }

      if (onProgress != null) {
        onProgress(0.5); // Halfway through parsing
      }

      // Send parsed data as JSON
      final uri = Uri.parse('$baseUrl/analyze');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'data': data}),
      );

      if (onProgress != null) {
        onProgress(1.0); // Complete
      }

      if (response.statusCode == 200) {
        return DataAnalysis.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to analyze file: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error analyzing file: $e');
    }
  }
}