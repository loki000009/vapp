import 'package:flutter/foundation.dart';

class DataSet with ChangeNotifier {
  List<Map<String, dynamic>> data = [];
  List<String> columns = [];
  String title = '';
  
  void updateData(List<Map<String, dynamic>> newData, String newTitle) {
    data = newData;
    title = newTitle;
    if (newData.isNotEmpty) {
      columns = newData.first.keys.toList();
    }
    notifyListeners();
  }

  void applyFilter(String column, dynamic value) {
    if (!columns.contains(column)) return;
    
    data = data.where((row) => row[column] == value).toList();
    notifyListeners();
  }

  void clearFilters(List<Map<String, dynamic>> originalData) {
    data = List.from(originalData);
    notifyListeners();
  }
}
