import 'dart:convert'; // For utf8 decoding
import 'dart:developer' as developer;
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io'; // Used only for non-web
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint; // For kIsWeb and debugPrint
import 'dart:typed_data'; // For Uint8List (web)

class FileService {
  /// Imports data from a file (CSV, XLSX, XLS or JSON) and returns it as a list of maps.
  Future<List<Map<String, dynamic>>> importData() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls', 'json'],
        withData: kIsWeb, // Ensure bytes are loaded on web
      );
    } catch (e) {
      debugPrint("File Picker Error: $e");
      return [];
    }

    if (result == null || result.files.isEmpty) {
      debugPrint("File picking cancelled or no file selected.");
      return [];
    }

    final PlatformFile fileData = result.files.single;

    // --- Platform Specific Handling ---
    if (kIsWeb) {
      // WEB Implementation
      if (fileData.name.isEmpty) {
         debugPrint("Web file import error: File name is empty.");
         return [];
      }
      final String extension = fileData.name.split('.').last.toLowerCase();
      final Uint8List? bytes = fileData.bytes;

      if (bytes == null) {
        debugPrint("Web file import error: File bytes are null.");
        return [];
      }

      debugPrint("Attempting to import web file: ${fileData.name} with extension: $extension");

      try {
        switch (extension) {
          case 'csv':
            // Decode bytes to String for CSV parser
            return _parseCsv(utf8.decode(bytes));
          case 'xlsx':
          case 'xls':
            // Excel parser takes bytes directly
            return _parseExcel(bytes);
          case 'json':
            // Decode bytes to String for JSON parser
            return _parseJson(utf8.decode(bytes));
          default:
            debugPrint("Unsupported file extension: $extension");
            return [];
        }
      } catch (e) {
        debugPrint("Error processing web file content: $e");
        return [];
      }

    } else {
      // MOBILE/DESKTOP Implementation (Existing Logic)
      final String? path = fileData.path;
      if (path == null) {
         debugPrint("File import error: File path is null.");
         return [];
      }

      final File file = File(path);
      final String extension = path.split('.').last.toLowerCase();

      debugPrint("Attempting to import file: ${file.path} with extension: $extension");

      try {
        switch (extension) {
          case 'csv':
            return _parseCsv(await file.readAsString());
          case 'xlsx':
          case 'xls':
            return _parseExcel(await file.readAsBytes());
          case 'json':
            return _parseJson(await file.readAsString());
          default:
            debugPrint("Unsupported file extension: $extension");
            return [];
        }
      } catch (e) {
        debugPrint("Error processing file content: $e");
        return [];
      }
    }
  }

  /// Parses a CSV string into a list of maps with number conversion attempt.
  List<Map<String, dynamic>> _parseCsv(String csvData) {
    // (CSV Parsing logic remains the same)
    final List<List<dynamic>> rowsAsListOfValues =
        const CsvToListConverter(shouldParseNumbers: false) // Keep numbers as strings initially for parsing check
            .convert(csvData.trim());

    if (rowsAsListOfValues.length < 2) return [];

    final List<String> headers = rowsAsListOfValues[0].map((h) => h?.toString().trim() ?? '').toList();
    final List<Map<String, dynamic>> data = [];

    for (var i = 1; i < rowsAsListOfValues.length; i++) {
      if (rowsAsListOfValues[i].length != headers.length) {
          debugPrint("Skipping mismatched CSV row index $i");
          continue;
      }
      final Map<String, dynamic> row = {};
      for (var j = 0; j < headers.length; j++) {
        dynamic value = rowsAsListOfValues[i][j];
        String valueStr = value?.toString().trim() ?? '';
        num? numValue = num.tryParse(valueStr);
        // Assign number if parsed, otherwise assign the original (trimmed) string value
        row[headers[j]] = numValue ?? valueStr;
      }
      data.add(row);
    }
    debugPrint("CSV Parsed: ${data.length} rows");
    return data;
  }

  /// Parses an Excel file (bytes) into a list of maps with number conversion attempt.
  List<Map<String, dynamic>> _parseExcel(List<int> bytes) {
     // (Excel Parsing logic remains the same)
     final excelData = Excel.decodeBytes(bytes);
     if (excelData.sheets.isEmpty) return [];

     final sheetName = excelData.sheets.keys.first;
     final sheet = excelData.sheets[sheetName];

     if (sheet == null || sheet.rows.length < 2) return [];

     final List<Map<String, dynamic>> data = [];
     // Ensure headers are treated as strings
     final List<String> headers = sheet.rows[0]
         .map((cell) => cell?.value?.toString().trim() ?? '')
         .toList();

     for (var i = 1; i < sheet.rows.length; i++) {
        if(sheet.rows.length <= i) continue; // Bounds check
        final Map<String, dynamic> row = {};
        final rowData = sheet.rows[i];

        for (var j = 0; j < headers.length; j++) {
          // Ensure we don't go out of bounds for potentially shorter rows
          if (j >= rowData.length) {
              row[headers[j]] = null; // Assign null if cell doesn't exist
              continue;
          }

         final cell = rowData[j];
         final dynamic cellValue = cell?.value;

         // Handle different cell types, prioritize direct num type
         if (cellValue is num) {
             row[headers[j]] = cellValue;
         } else {
              String cellValueStr = cellValue?.toString().trim() ?? '';
              if (cellValueStr.isNotEmpty) {
                  num? numValue = num.tryParse(cellValueStr);
                  row[headers[j]] = numValue ?? cellValueStr; // Assign num if parsed, else string
              } else {
                  row[headers[j]] = null; // Assign null for empty cells
              }
         }
       }
       data.add(row);
     }
      debugPrint("Excel Parsed: ${data.length} rows");
     return data;
  }


  /// Parses a JSON string (assuming list of maps format) into a list of maps.
  List<Map<String, dynamic>> _parseJson(String jsonData) {
    // (JSON Parsing logic remains the same)
     try {
       final dynamic jsonDecoded = json.decode(jsonData);
       if (jsonDecoded is List) {
          // Check if every item in the list is a Map
          if (jsonDecoded.every((item) => item is Map)) {
             List<Map<String, dynamic>> data = [];
             for (var item in jsonDecoded) {
                 // Explicitly cast to Map<String, dynamic> after the check
                 Map<String, dynamic> itemMap = Map<String, dynamic>.from(item);
                 Map<String, dynamic> row = {};
                 itemMap.forEach((key, value) {
                      // Try to parse numbers, keep original value otherwise
                      if (value is num) {
                          row[key] = value;
                      } else if (value is String) {
                           String valueStr = value.trim();
                           num? numValue = num.tryParse(valueStr);
                           row[key] = numValue ?? valueStr; // Assign num if parsed, else trimmed string
                      } else {
                           row[key] = value; // Assign other types directly (bool, null, etc.)
                      }
                 });
                 data.add(row);
             }
             debugPrint("JSON Parsed: ${data.length} rows");
             return data;
         } else {
             debugPrint("JSON parsing error: List contains non-Map items.");
             return [];
         }
       } else {
          debugPrint("JSON parsing error: Decoded JSON is not a List.");
          return [];
       }
     } catch (e) {
        debugPrint("Error decoding JSON: $e");
        return [];
     }
  }

  // --- Export Functions (remain unchanged) ---
  Future<bool> exportData(List<Map<String, dynamic>> data, String format) async {
     // ...(Keep existing export logic)...
     try {
       if (data.isEmpty) return false;
       final directory = await getApplicationDocumentsDirectory();
       final String fileName = 'export_${DateTime.now().millisecondsSinceEpoch}';
       switch (format.toLowerCase()) {
         case 'csv': return await _exportToCsv(data, directory.path, fileName);
         case 'excel': return await _exportToExcel(data, directory.path, fileName);
         case 'json': return await _exportToJson(data, directory.path, fileName);
         default: return false;
       }
     } catch (e) {
       developer.log('Error exporting data: $e', name: 'FileService');
       return false;
     }
  }
  Future<bool> _exportToCsv(List<Map<String, dynamic>> data, String path, String fileName) async {
     if (data.isEmpty) return false;
     final List<String> headers = data.first.keys.toList();
     final List<List<dynamic>> rows = [headers];
     for (final row in data) {
       rows.add(headers.map((header) => row[header] ?? '').toList());
     }
     final String csv = const ListToCsvConverter().convert(rows);
     final file = File('$path/$fileName.csv');
     await file.writeAsString(csv);
     return true;
  }
  Future<bool> _exportToExcel(List<Map<String, dynamic>> data, String path, String fileName) async {
     if (data.isEmpty) return false;
     final excel = Excel.createExcel();
     final sheet = excel[excel.getDefaultSheet()!];
     final List<String> headers = data.first.keys.toList();
     for (var i = 0; i < headers.length; i++) {
       sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
           .value = TextCellValue(headers[i]);
     }
     for (var i = 0; i < data.length; i++) {
       for (var j = 0; j < headers.length; j++) {
         final dynamic value = data[i][headers[j]];
         sheet.cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: i + 1))
             .value = _toCellValue(value);
       }
     }
     final encodedData = excel.encode();
     if (encodedData == null) return false;
     final file = File('$path/$fileName.xlsx');
     await file.writeAsBytes(encodedData);
     return true;
  }
  CellValue? _toCellValue(dynamic value) {
     if (value == null) return null;
     if (value is int) return IntCellValue(value);
     if (value is double) return DoubleCellValue(value);
     if (value is String) return TextCellValue(value);
     if (value is bool) return BoolCellValue(value);
     return TextCellValue(value.toString());
   }
  Future<bool> _exportToJson(List<Map<String, dynamic>> data, String path, String fileName) async {
     final file = File('$path/$fileName.json');
     const jsonEncoder = JsonEncoder.withIndent('  ');
     await file.writeAsString(jsonEncoder.convert(data));
     return true;
  }
}