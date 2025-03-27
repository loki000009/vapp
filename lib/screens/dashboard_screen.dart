import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/data_model.dart';
import '../services/file_service.dart';
import '../services/analysis_service.dart';
import '../models/analysis_model.dart';
import '../widgets/chart_widgets.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'dart:typed_data';
import '../main.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import '../widgets/data_preview.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FileService _fileService = FileService();
  final AnalysisService _analysisService = AnalysisService();
  final GlobalKey _chartKey = GlobalKey();
  bool _isLoading = false;
  double _uploadProgress = 0.0;
  DataAnalysis? _analysis;
  List<List<dynamic>>? _rawData; // Store raw data for rendering

  @override
  Widget build(BuildContext context) {
    final _ = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Vapp - Data Visualization'),
          elevation: 0,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.analytics), text: 'Visualization'),
              Tab(icon: Icon(Icons.table_chart), text: 'Data Preview'),
            ],
          ),
          actions: [
            Tooltip(
              message: 'Toggle Theme',
              child: IconButton(
                icon: Icon(
                  Theme.of(context).brightness == Brightness.light
                      ? Icons.dark_mode
                      : Icons.light_mode,
                ),
                onPressed: () {
                  context.read<ThemeProvider>().toggleTheme();
                },
              ),
            ),
            Tooltip(
              message: 'Import Data',
              child: IconButton(
                icon: const Icon(Icons.file_upload),
                onPressed: _importData,
              ),
            ),
            if (context.watch<DataSet>().data.isNotEmpty) ...[
              Tooltip(
                message: 'Export Data',
                child: IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: () => _exportData(context),
                ),
              ),
              Tooltip(
                message: 'Save as Image',
                child: IconButton(
                  icon: const Icon(Icons.photo),
                  onPressed: () => _saveChartAsImage(context),
                ),
              ),
            ],
          ],
        ),
        body: TabBarView(
          children: [
            _buildVisualizationTab(),
            const DataPreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualizationTab() {
    return Consumer<DataSet>(
      builder: (context, dataSet, child) {
        if (_isLoading) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                LoadingAnimationWidget.staggeredDotsWave(
                  color: Theme.of(context).colorScheme.primary,
                  size: 50,
                ),
                const SizedBox(height: 16),
                Text(
                  'Analyzing data...',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_uploadProgress > 0) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: _uploadProgress,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Uploading data: ${(_uploadProgress * 100).toStringAsFixed(2)}%',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ],
            ),
          );
        }

        if (dataSet.data.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.bar_chart,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'No Data Available',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Upload a CSV or Excel file to begin',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _importData,
                  icon: const Icon(Icons.file_upload),
                  label: const Text('Import Data'),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_analysis != null) _buildAnalysisCard(),
                const SizedBox(height: 16),
                if (_analysis?.visualizationSuggestions != null)
                  ..._analysis!.visualizationSuggestions.entries.map((entry) {
                    final col = entry.key;
                    final vizTypes = entry.value;
                    final colIdx = _rawData![0].indexOf(col);

                    return Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$col Visualization',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            RepaintBoundary(
                              key: _chartKey,
                              child: _buildSuggestedChart(vizTypes, colIdx, dataSet),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuggestedChart(List<String> vizTypes, int colIdx, DataSet dataSet) {
    if (vizTypes.contains('bar')) {
      final catIdx = _analysis!.dataTypes.values.toList().indexOf('categorical');
      if (catIdx == -1) return Container(); // Skip if no categorical column
      return ChartWidgets.barChart(
        dataSet.data,
        _rawData![0][catIdx], // X-axis: categorical column
        _rawData![0][colIdx], // Y-axis: numerical column
      );
    } else if (vizTypes.contains('line')) {
      final dateIdx = _analysis!.dataTypes.values.toList().indexOf('date');
      if (dateIdx == -1) return Container(); // Skip if no date column
      return ChartWidgets.lineChart(
        dataSet.data,
        _rawData![0][dateIdx], // X-axis: date column
        _rawData![0][colIdx], // Y-axis: numerical column
      );
    } else if (vizTypes.contains('pie')) {
      return ChartWidgets.pieChart(
        dataSet.data,
        _rawData![0][colIdx], // Categorical column for pie chart
        _rawData![0][colIdx], // Use same column for values
      );
    }
    return Container();
  }

  Widget _buildAnalysisCard() {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Data Analysis',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (_analysis?.visualizationSuggestions != null) ...[
              Text(
                'Suggested Visualizations',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _analysis!.visualizationSuggestions.entries.map((entry) {
                  return Chip(
                    label: Text('${entry.key}: ${entry.value.join(", ")}'),
                  );
                }).toList(),
              ),
            ],
            if (_analysis?.statistics != null) ...[
              const SizedBox(height: 16),
              Text(
                'Statistics',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...(_analysis!.statistics.entries.map((entry) {
                final stats = entry.value;
                if (stats['mean'] != null) {
                  return ListTile(
                    title: Text(entry.key),
                    subtitle: Text(
                      'Mean: ${stats['mean'].toStringAsFixed(2)}, '
                      'Median: ${stats['median'].toStringAsFixed(2)}, '
                      'Std: ${stats['std'].toStringAsFixed(2)}',
                    ),
                  );
                } else {
                  return ListTile(
                    title: Text(entry.key),
                    subtitle: Text(
                      'Unique values: ${stats['unique_values']}\n'
                      'Most common: ${(stats['most_common'] as Map).entries.map((e) => "${e.key}: ${e.value}").join(", ")}',
                    ),
                  );
                }
              }).toList()),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _importData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Pick file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
      );

      if (result != null) {
        final file = File(result.files.single.path!);

        // Show upload progress
        final progressStream = StreamController<double>();
        progressStream.stream.listen((progress) {
          if (mounted) {
            setState(() {
              _uploadProgress = progress;
            });
          }
        });

        // Analyze the data using the ML backend
        final analysisResult = await _analysisService.analyzeFile(
          file.path,
          onProgress: (progress) => progressStream.add(progress),
        );
        setState(() {
          _analysis = DataAnalysis.fromJson(analysisResult as Map<String, dynamic>);
        });

        // Import the data for visualization
        final data = await _fileService.importData();
        if (data.isNotEmpty && mounted) {
          context.read<DataSet>().updateData(data, 'Imported Dataset');
        }

        // Store raw data for rendering
        final headers = data.first.keys.toList();
        _rawData = [headers];
        for (var row in data) {
          _rawData!.add(headers.map((header) => row[header]).toList());
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }

  Future<void> _exportData(BuildContext parentContext) async {
    final dataSet = parentContext.read<DataSet>();
    if (dataSet.data.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(parentContext).showSnackBar(
        const SnackBar(content: Text('No data to export')),
      );
      return;
    }

    if (!mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(parentContext);

    await showDialog(
      context: parentContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Export Data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('CSV'),
              onTap: () async {
                Navigator.pop(dialogContext);
                final success = await _fileService.exportData(dataSet.data, 'csv');
                if (mounted) {
                  _showExportResult(scaffoldMessenger, success);
                }
              },
            ),
            ListTile(
              title: const Text('Excel'),
              onTap: () async {
                Navigator.pop(dialogContext);
                final success = await _fileService.exportData(dataSet.data, 'excel');
                if (mounted) {
                  _showExportResult(scaffoldMessenger, success);
                }
              },
            ),
            ListTile(
              title: const Text('JSON'),
              onTap: () async {
                Navigator.pop(dialogContext);
                final success = await _fileService.exportData(dataSet.data, 'json');
                if (mounted) {
                  _showExportResult(scaffoldMessenger, success);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showExportResult(ScaffoldMessengerState scaffoldMessenger, bool success) {
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(success ? 'Export successful' : 'Export failed'),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _saveChartAsImage(BuildContext parentContext) async {
    try {
      final RenderRepaintBoundary? boundary = _chartKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(parentContext).showSnackBar(
          const SnackBar(
            content: Text('No chart available to save'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(parentContext).showSnackBar(
          const SnackBar(
            content: Text('Failed to generate chart image'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/chart_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      final scaffoldMessenger = ScaffoldMessenger.of(parentContext);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Chart Export',
      );

      if (mounted) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Chart ready to share')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(parentContext).showSnackBar(
        SnackBar(
          content: Text('Failed to save chart as image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}