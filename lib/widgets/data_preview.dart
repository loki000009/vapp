import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/data_model.dart';

class DataPreview extends StatefulWidget {
  const DataPreview({super.key});

  @override
  State<DataPreview> createState() => _DataPreviewState();
}

class _DataPreviewState extends State<DataPreview> {
  final int _itemsPerPage = 20;
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final dataSet = context.watch<DataSet>();
    final pageCount = (dataSet.data.length / _itemsPerPage).ceil();
    final startIndex = _currentPage * _itemsPerPage;
    final endIndex = startIndex + _itemsPerPage;
    final pageData = dataSet.data.sublist(
      startIndex,
      endIndex < dataSet.data.length ? endIndex : dataSet.data.length,
    );

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: dataSet.columns.map((column) {
                return DataColumn(label: Text(column));
              }).toList(),
              rows: pageData.map((row) {
                return DataRow(
                  cells: dataSet.columns.map((column) {
                    return DataCell(Text(row[column]?.toString() ?? ''));
                  }).toList(),
                );
              }).toList(),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _currentPage > 0
                  ? () => setState(() => _currentPage--)
                  : null,
            ),
            Text('Page ${_currentPage + 1} of $pageCount'),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _currentPage < pageCount - 1
                  ? () => setState(() => _currentPage++)
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}
