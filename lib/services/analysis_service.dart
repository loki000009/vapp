import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/analysis_model.dart';
import '../services/file_service.dart';

class AnalysisService {
  final String backendUrl = "http://127.0.0.1:5000/api/analyze"; // Flask API endpoint

  Future<DataAnalysis?> analyzeFile(String filePath, {required void Function(dynamic progress) onProgress}) async {
    try {
      final fileService = FileService();
      final data = await fileService.importData();

      // Convert data to JSON string
      final dataJson = jsonEncode({"data": data});

      // Send JSON to Flask
      final response = await http.post(
        Uri.parse(backendUrl),
        headers: {"Content-Type": "application/json"},
        body: dataJson,
      );

      if (response.statusCode == 200) {
        final analysisResult = jsonDecode(response.body);
        return DataAnalysis.fromJson(analysisResult);
      } else {
        throw Exception("Error from Flask: ${response.body}");
      }
    } catch (e) {
      print('Error analyzing data: $e');
      return null;
    }
  }
}
