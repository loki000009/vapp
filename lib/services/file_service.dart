import 'dart:convert';
import 'dart:developer' as developer; // Added for logging
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class FileService {
  /// Imports data from a file (CSV, XLSX, or JSON) and returns it as a list of maps.
  Future<List<Map<String, dynamic>>> importData() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'json'],
    );

    if (result == null || result.files.isEmpty) return [];

    final File file = File(result.files.single.path!);
    final String extension = result.files.single.extension!.toLowerCase();

    switch (extension) {
      case 'csv':
        return _parseCsv(await file.readAsString());
      case 'xlsx':
        return _parseExcel(await file.readAsBytes());
      case 'json':
        return _parseJson(await file.readAsString());
      default:
        return [];
    }
  }

  /// Parses a CSV string into a list of maps.
  List<Map<String, dynamic>> _parseCsv(String csvData) {
    final List<List<dynamic>> rowsAsListOfValues =
        const CsvToListConverter().convert(csvData);

    if (rowsAsListOfValues.isEmpty) return [];

    final List<String> headers = List<String>.from(rowsAsListOfValues[0]);
    final List<Map<String, dynamic>> data = [];

    for (var i = 1; i < rowsAsListOfValues.length; i++) {
      final Map<String, dynamic> row = {};
      for (var j = 0; j < headers.length; j++) {
        row[headers[j]] = rowsAsListOfValues[i][j];
      }
      data.add(row);
    }

    return data;
  }

  /// Parses an Excel file (bytes) into a list of maps.
  List<Map<String, dynamic>> _parseExcel(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.tables.keys.first];
    if (sheet == null || sheet.rows.isEmpty) return [];

    final List<Map<String, dynamic>> data = [];
    final List<String> headers = sheet.rows[0]
        .map((cell) => cell?.value?.toString() ?? '')
        .toList();

    for (var i = 1; i < sheet.rows.length; i++) {
      final Map<String, dynamic> row = {};
      for (var j = 0; j < headers.length; j++) {
        row[headers[j]] = sheet.rows[i][j]?.value;
      }
      data.add(row);
    }

    return data;
  }

  /// Parses a JSON string into a list of maps.
  List<Map<String, dynamic>> _parseJson(String jsonData) {
    final dynamic jsonList = json.decode(jsonData);
    if (jsonList is List) {
      return List<Map<String, dynamic>>.from(jsonList);
    }
    return [];
  }

  /// Exports data to a file in the specified format (CSV, Excel, or JSON).
  Future<bool> exportData(List<Map<String, dynamic>> data, String format) async {
    try {
      if (data.isEmpty) return false;

      final directory = await getApplicationDocumentsDirectory();
      final String fileName = 'export_${DateTime.now().millisecondsSinceEpoch}';

      switch (format.toLowerCase()) {
        case 'csv':
          return await _exportToCsv(data, directory.path, fileName);
        case 'excel':
          return await _exportToExcel(data, directory.path, fileName);
        case 'json':
          return await _exportToJson(data, directory.path, fileName);
        default:
          return false;
      }
    } catch (e) {
      // Replaced print with developer.log
      developer.log('Error exporting data: $e', name: 'FileService');
      return false;
    }
  }

  /// Exports data to a CSV file.
  Future<bool> _exportToCsv(
      List<Map<String, dynamic>> data, String path, String fileName) async {
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

  /// Exports data to an Excel file.
  Future<bool> _exportToExcel(
      List<Map<String, dynamic>> data, String path, String fileName) async {
    if (data.isEmpty) return false;

    final excel = Excel.createExcel();
    final Sheet sheet = excel[excel.getDefaultSheet()!];

    // Add headers
    final List<String> headers = data.first.keys.toList();
    for (var i = 0; i < headers.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(headers[i]);
    }

    // Add data
    for (var i = 0; i < data.length; i++) {
      for (var j = 0; j < headers.length; j++) {
        final dynamic value = data[i][headers[j]];
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: i + 1))
            .value = _toCellValue(value);
      }
    }

    final file = File('$path/$fileName.xlsx');
    await file.writeAsBytes(excel.encode()!);
    return true;
  }

  /// Helper method to convert dynamic values to CellValue for Excel.
  CellValue? _toCellValue(dynamic value) {
    if (value == null) return null;
    if (value is String) return TextCellValue(value);
    if (value is int) return IntCellValue(value);
    if (value is double) return DoubleCellValue(value);
    if (value is bool) return BoolCellValue(value);
    return TextCellValue(value.toString());
  }

  /// Exports data to a JSON file.
  Future<bool> _exportToJson(
      List<Map<String, dynamic>> data, String path, String fileName) async {
    final file = File('$path/$fileName.json');
    await file.writeAsString(json.encode(data));
    return true;
  }
}