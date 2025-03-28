import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/analysis_model.dart';
// No longer importing file_service.dart here

// --- Added Imports ---
import 'dart:async'; // For TimeoutException
import 'package:flutter/foundation.dart'; // For debugPrint

class AnalysisService {
  // Use your actual backend URL if deployed, otherwise keep localhost
  final String backendUrl = "http://192.168.178.53:5000/api/analyze";

  // Accepts parsed data directly
  Future<DataAnalysis?> analyzeData(
      List<Map<String, dynamic>> data, {
      required void Function(double progress) onProgress,
  }) async {
    if (data.isEmpty) {
      // Use debugPrint instead of print
      debugPrint("analyzeData called with empty data.");
      onProgress(0.0); // Reset progress if no data
      return null;
    }

    try {
      onProgress(0.1); // 10% - Starting analysis request
      final dataJson = jsonEncode({"data": data});
      onProgress(0.2); // 20% - JSON Encoded

      final response = await http.post(
        Uri.parse(backendUrl),
        headers: {"Content-Type": "application/json"},
        body: dataJson,
      ).timeout(
        // Increased timeout slightly, adjust as needed
        const Duration(seconds: 45),
        onTimeout: () {
          // TimeoutException is now defined via dart:async import
          throw TimeoutException("Connection timeout. Backend server might be down or taking too long.");
        },
      );

      onProgress(0.8); // 80% - Received response

      if (response.statusCode == 200) {
        final analysisResult = jsonDecode(response.body);
        if (analysisResult.containsKey('error')) {
          // Braces are needed here for map access
          throw Exception("Backend error: ${analysisResult['error']}");
        }
        onProgress(1.0); // 100% - Done processing response
        return DataAnalysis.fromJson(analysisResult);
      } else {
        // Provide more context on HTTP errors
        // Fixed string concatenation using interpolation
        String errorBody = response.body.length > 200 ? '${response.body.substring(0, 200)}...' : response.body;
        // Braces needed for errorBody variable interpolation
        throw Exception("HTTP Error ${response.statusCode}: $errorBody");
      }
    } catch (e) {
      // Log the specific error for debugging using debugPrint
      debugPrint('Error analyzing data: $e');
      onProgress(0.0); // Reset progress on error
      // Optionally rethrow or handle specific errors differently
      // throw e; // Rethrow if the caller should handle it
      return null; // Return null to indicate failure
    }
  }
}