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
import '../main.dart'; // For ThemeProvider
import 'package:loading_animation_widget/loading_animation_widget.dart';
// Removed FilePicker import as FileService handles it
import 'dart:async';
import '../widgets/data_preview.dart'; // Ensure this widget is defined

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FileService _fileService = FileService();
  final AnalysisService _analysisService = AnalysisService();
  final GlobalKey _chartContainerKey = GlobalKey(); // Use a key for the container
  bool _isLoading = false;
  double _analysisProgress = 0.0;
  DataAnalysis? _analysis;
  // Removed _rawData as DataSet from provider is used directly

  // Function to show snackbar messages
  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).snackBarTheme.backgroundColor ?? Colors.green,
        ),
      );
    }
  }

  Future<void> _importData() async {
    if (_isLoading) return; // Prevent concurrent imports

    setState(() {
      _isLoading = true;
      _analysisProgress = 0.0;
      _analysis = null; // Clear previous analysis
      // Optionally clear data in provider immediately or wait for new data
      // context.read<DataSet>().updateData([], ''); 
    });

    List<Map<String, dynamic>>? parsedData;
    try {
      // 1. Pick and Parse file ONCE using FileService
      parsedData = await _fileService.importData();

      if (parsedData == null || parsedData.isEmpty) {
        _showSnackBar('File selection cancelled or file is empty/invalid.');
        setState(() => _isLoading = false);
        return;
      }

      // Update progress indication
      if (mounted) setState(() => _analysisProgress = 0.05); // 5% - File parsed

      // 2. Update DataSet Provider with parsed data
      // Use a temporary title or derive from file name if FileService provided it
      String dataTitle = "Imported Dataset"; 
      if (mounted) {
           context.read<DataSet>().updateData(parsedData, dataTitle);
      }
      
      if (mounted) setState(() => _analysisProgress = 0.1); // 10% - Data loaded into state

      // 3. Call Analysis Service with PARSED data
      final progressStream = StreamController<double>();
      progressStream.stream.listen((progress) {
        if (mounted) {
          // Scale analysis progress (0.0-1.0) to the remaining progress bar range (0.1-0.95)
          setState(() => _analysisProgress = 0.1 + progress * 0.85); 
        }
      });

      DataAnalysis? analysisResult = await _analysisService.analyzeData(
        parsedData, // Pass the parsed data
        onProgress: (progress) => progressStream.add(progress),
      );

      await progressStream.close(); // Close stream after use

      if (mounted) {
         if (analysisResult != null) {
            setState(() {
              _analysis = analysisResult;
              _analysisProgress = 1.0; // Mark as complete
            });
            _showSnackBar('Analysis complete!');
         } else {
            setState(() {
              _analysis = null; // Ensure analysis is null on failure
              _analysisProgress = 0.0; // Reset progress on failure
            });
            _showSnackBar('Failed to get analysis results from backend.', isError: true);
            // Optionally clear data if analysis failed critically
            // context.read<DataSet>().updateData([], '');
         }
       }

    } catch (e) {
      if (mounted) {
        setState(() {
          _analysis = null; // Clear analysis on error
          _analysisProgress = 0.0;
        });
        _showSnackBar('Error during import/analysis: ${e.toString()}', isError: true);
         // Optionally clear data on error
         // context.read<DataSet>().updateData([], '');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false; // Ensure loading indicator stops
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
     // Theme access simplified
    final theme = Theme.of(context); 
    final colorScheme = theme.colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Vapp - Data Visualization'),
          elevation: 0, // Keep it flat
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
                  theme.brightness == Brightness.light
                      ? Icons.dark_mode_outlined // Use outlined icons
                      : Icons.light_mode_outlined,
                ),
                onPressed: () {
                  context.read<ThemeProvider>().toggleTheme();
                },
              ),
            ),
            Tooltip(
              message: 'Import Data',
              child: IconButton(
                icon: _isLoading 
                       ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary))) // Show progress in button
                       : const Icon(Icons.file_upload_outlined), // Use outlined icon
                onPressed: _isLoading ? null : _importData, // Disable while loading
              ),
            ),
            // Use Consumer or context.watch for reacting to DataSet changes
            Consumer<DataSet>(
              builder: (context, dataSet, child) {
                if (dataSet.data.isNotEmpty && _analysis != null && !_isLoading) {
                  return Row( // Keep export/save together
                    mainAxisSize: MainAxisSize.min,
                    children: [
                     Tooltip(
                       message: 'Export Data',
                       child: IconButton(
                         icon: const Icon(Icons.save_alt_outlined), // Use outlined icon
                         onPressed: () => _exportData(context),
                       ),
                     ),
                     Tooltip(
                       message: 'Save Chart Image',
                       child: IconButton(
                         icon: const Icon(Icons.image_outlined), // Use outlined icon
                         onPressed: () => _saveChartAsImage(context),
                       ),
                     ),
                    ],
                  );
                } else {
                  return const SizedBox.shrink(); // Return empty space if no data/analysis
                }
              },
            ),
          ],
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(), // Prevent swiping between tabs if needed
          children: [
            _buildVisualizationTab(),
            const DataPreview(), // Assumes DataPreview uses context.watch<DataSet>()
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
     final theme = Theme.of(context);
     return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                LoadingAnimationWidget.staggeredDotsWave(
                  color: theme.colorScheme.primary,
                  size: 50,
                ),
                const SizedBox(height: 20),
                Text(
                  'Analyzing data...',
                  style: theme.textTheme.titleMedium, // Slightly smaller title
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: LinearProgressIndicator(
                    value: _analysisProgress > 0 ? _analysisProgress : null, // Indeterminate if 0
                    backgroundColor: theme.colorScheme.surfaceVariant,
                  ),
                ),
                 const SizedBox(height: 8),
                 Text(
                   _analysisProgress > 0 
                       ? '${(_analysisProgress * 100).toStringAsFixed(0)}%' 
                       : 'Starting...', // More user-friendly text
                   style: theme.textTheme.bodySmall,
                 ),
              ],
            ),
          );
  }

   Widget _buildEmptyState() {
      final theme = Theme.of(context);
      return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_upload_outlined, // Different icon
                  size: 64,
                  color: theme.colorScheme.primary.withOpacity(0.6),
                ),
                const SizedBox(height: 16),
                Text(
                  'No Data Loaded',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: Text(
                    'Click the upload icon in the top bar to import a CSV or Excel file and generate visualizations.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                  onPressed: _isLoading ? null : _importData,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Import Data'),
                ),
              ],
            ),
          );
   }


  Widget _buildVisualizationTab() {
    // Use Consumer for reacting to DataSet changes
    return Consumer<DataSet>(
      builder: (context, dataSet, child) {
        if (_isLoading) {
          return _buildLoadingIndicator();
        }

        // Check for both data and analysis results
        if (dataSet.data.isEmpty || _analysis == null) {
           return _buildEmptyState();
        }

        // --- Data and Analysis available ---
        // Use RepaintBoundary around the chart container for image saving
         return RepaintBoundary(
           key: _chartContainerKey,
           child: Container( // Add a background color matching the theme
               color: Theme.of(context).scaffoldBackgroundColor,
               child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                     _buildAnalysisSummaryCard(), // Display analysis summary first
                     const SizedBox(height: 16),
                     // Generate chart cards based on suggestions
                      if (_analysis?.visualizationSuggestions != null && _analysis!.visualizationSuggestions.isNotEmpty)
                        ..._analysis!.visualizationSuggestions.entries
                            .map((entry) => _buildChartCard(entry.key, entry.value, dataSet))
                            .where((widget) => widget != null) // Filter out null widgets if chart fails
                            .map((widget) => Padding( // Add spacing between charts
                                padding: const EdgeInsets.only(bottom: 16.0), 
                                child: widget!,
                             )) 
                      else 
                         _buildNoSuggestionsCard(), // Show if analysis succeeded but no suggestions were made
                  ],
                ),
                         ),
             ),
         );
      },
    );
  }

   Widget? _buildChartCard(String columnName, List<String> vizTypes, DataSet dataSet) {
      final theme = Theme.of(context);
      final chartWidget = _buildSuggestedChart(columnName, vizTypes, dataSet);

      // Don't build a card if no suitable chart could be generated
      if (chartWidget == null) {
         print("Skipping chart card for '$columnName' as no suitable chart could be generated.");
         return null; 
      } 

      return Card(
           elevation: 2,
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
           clipBehavior: Clip.antiAlias, // Improves rendering with rounded corners
           child: Padding(
             padding: const EdgeInsets.all(16.0),
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Text(
                    // More descriptive title
                   'Suggested Visualization for "$columnName"', 
                   style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                 ),
                 const SizedBox(height: 8),
                 Text(
                    // Indicate the type(s) suggested
                    'Type: ${vizTypes.join(", ")}', 
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                 ),
                 const SizedBox(height: 16),
                 // Center the chart or ensure it fills available space
                 Center(child: chartWidget), 
               ],
             ),
           ),
         );
   }

   Widget _buildNoSuggestionsCard() {
        final theme = Theme.of(context);
        return Card(
           elevation: 2,
           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
           child: Padding(
             padding: const EdgeInsets.all(24.0),
             child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lightbulb_outline, size: 40, color: theme.hintColor),
                  const SizedBox(height: 16),
                  Text(
                    'No Specific Visualizations Suggested', 
                    style: theme.textTheme.titleMedium, 
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The analysis was successful, but the backend didn\'t provide specific chart recommendations based on this data. You can still explore the raw data in the "Data Preview" tab.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
             ),
           ),
         );
   }


  // Modified to accept columnName and DataSet
  Widget? _buildSuggestedChart(String columnName, List<String> vizTypes, DataSet dataSet) {
     if (_analysis == null || dataSet.data.isEmpty) return null; // Guard clause

     // Helper to find the first column of a specific type (numerical, date, categorical)
     String? findFirstColumnOfType(String type) {
        return _analysis!.dataTypes.entries
            .firstWhere((entry) => entry.value.toLowerCase() == type.toLowerCase(), orElse: () => const MapEntry('', ''))
            .key;
     }
     
     // --- Determine Axis/Fields based on Viz Type ---
     
     // Use the primary visualization type suggested first
     final primaryViz = vizTypes.first.toLowerCase(); 

     try {
        if (primaryViz == 'bar') {
          // Bar chart needs a category (X) and a numerical value (Y)
          // Use the suggested column 'columnName' as Y if numerical, or find another numerical
          // Use the first categorical/date column as X
          
          String? categoryField = findFirstColumnOfType('categorical') ?? findFirstColumnOfType('date');
          String valueField = columnName; // Assume suggested column is the value

          // If suggested column is not numerical, try finding the first numerical one
          if (_analysis!.dataTypes[columnName]?.toLowerCase() != 'numerical') {
             valueField = findFirstColumnOfType('numerical') ?? columnName; // Fallback to original column
          }
          
          if (categoryField == null || categoryField.isEmpty) {
             print("Bar chart: Could not find a suitable category field.");
             return null; 
          }
          
          // Basic aggregation for bar chart (count by category) if value field isn't distinct enough
          // Or pass data directly if backend assumes pre-aggregated or distinct rows per category
          // For simplicity, we'll try direct plotting first. Aggregation might be needed.
          return ChartWidgets.barChart(dataSet.data, categoryField, valueField);

        } else if (primaryViz == 'line') {
           // Line chart typically needs a sequence (X, often date/numerical) and a numerical value (Y)
           // Use the suggested column 'columnName' as Y if numerical.
           // Use the first date/numerical column as X.

           String? sequenceField = findFirstColumnOfType('date') ?? findFirstColumnOfType('numerical');
           String valueField = columnName; // Assume suggested column is the value
           
           // Ensure the sequence field is not the same as the value field if possible
           if (sequenceField == valueField) {
              sequenceField = _analysis!.dataTypes.entries
                  .firstWhere((entry) => 
                       (entry.value.toLowerCase() == 'date' || entry.value.toLowerCase() == 'numerical') && 
                       entry.key != valueField, 
                       orElse: () => MapEntry(sequenceField!, '') // Keep original if no alternative
                  ).key;
           }

           // If suggested column is not numerical, try finding the first numerical one for Y
           if (_analysis!.dataTypes[columnName]?.toLowerCase() != 'numerical') {
              valueField = findFirstColumnOfType('numerical') ?? columnName;
           }
           
           if (sequenceField == null || sequenceField.isEmpty) {
              print("Line chart: Could not find a suitable sequence field (date or numerical).");
              return null;
           }
           
           return ChartWidgets.lineChart(dataSet.data, sequenceField, valueField);

        } else if (primaryViz == 'pie' || primaryViz == 'word_cloud') { // Treat word cloud suggestion similar to pie for now
          // Pie chart needs a category and a value.
          // Use the suggested 'columnName' as the category.
          // For value, calculate the count of each category as default.
          
          final String categoryField = columnName;
          
          // --- Calculate Counts ---
          final Map<String, double> categoryCounts = {};
          for (var row in dataSet.data) {
             final category = row[categoryField]?.toString() ?? 'Unknown';
             categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
          }
          
          if (categoryCounts.isEmpty) {
             print("Pie chart: No categories found or data is empty for column '$categoryField'.");
             return null;
          }

          // --- Convert counts to list suitable for PieChart widget ---
          final List<Map<String, dynamic>> pieData = categoryCounts.entries.map((entry) {
             // PieChart widget expects fields for category and value
             return {'category': entry.key, 'value': entry.value};
          }).toList();

          // Pass the field names used in the pieData map
          return ChartWidgets.pieChart(pieData, 'category', 'value'); 
        } else {
           print("Unsupported visualization type suggested: $primaryViz");
           return null; // Or return a placeholder Text widget
        }
     } catch (e) {
        print("Error building chart for column '$columnName' with type '$primaryViz': $e");
        // Return a placeholder indicating the error
        return Center(
            child: Text(
               'Error building chart for "$columnName".\nPlease check data compatibility.', 
               style: TextStyle(color: Theme.of(context).colorScheme.error),
               textAlign: TextAlign.center,
             ),
           );
     }
  }


  Widget _buildAnalysisSummaryCard() {
    // Builds the card showing overall stats and suggestions
     final theme = Theme.of(context);
     if (_analysis == null) return const SizedBox.shrink(); // Should not happen if called correctly

     // Helper to format statistic values
     String formatStatValue(dynamic value) {
        if (value == null) return 'N/A';
        if (value is double) return value.toStringAsFixed(2);
        return value.toString();
     }

     return Card(
       elevation: 2,
       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
       clipBehavior: Clip.antiAlias,
       child: Padding(
         padding: const EdgeInsets.all(16.0),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Text(
               'Data Analysis Summary',
               style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
             ),
             const Divider(height: 24), // Add a divider

             // Section for Data Types
             if (_analysis!.dataTypes.isNotEmpty) ...[
                Text(
                   'Detected Column Types',
                   style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                 Wrap(
                   spacing: 8,
                   runSpacing: 4,
                   children: _analysis!.dataTypes.entries.map((entry) {
                     IconData iconData;
                     switch(entry.value.toLowerCase()){
                        case 'numerical': iconData = Icons.looks_one; break; // Or calculate_outlined
                        case 'date': iconData = Icons.calendar_today_outlined; break;
                        case 'text': iconData = Icons.text_fields_outlined; break;
                        case 'categorical': iconData = Icons.category_outlined; break;
                        default: iconData = Icons.help_outline;
                     }
                     return Chip(
                        avatar: Icon(iconData, size: 16, color: theme.chipTheme.labelStyle?.color),
                        label: Text('${entry.key}: ${entry.value}'),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                     );
                   }).toList(),
                 ),
                 const SizedBox(height: 16),
             ],

             // Section for Statistics (Improved Layout)
             if (_analysis!.statistics.isNotEmpty) ...[
               Text(
                 'Column Statistics',
                 style: theme.textTheme.titleMedium,
               ),
               const SizedBox(height: 8),
               // Use ExpansionTiles for cleaner display
                ..._analysis!.statistics.entries.map((entry) {
                   final stats = entry.value;
                   final type = stats['type']?.toString().toLowerCase() ?? 'unknown';
                   
                   return ExpansionTile(
                     tilePadding: EdgeInsets.zero, // Remove default padding
                     title: Text(entry.key, style: theme.textTheme.titleSmall),
                     childrenPadding: const EdgeInsets.only(left: 16, bottom: 8), // Indent children
                     expandedCrossAxisAlignment: CrossAxisAlignment.start,
                     children: type == 'numerical' 
                         ? [
                             Text('Type: Numerical'),
                             Text('Min: ${formatStatValue(stats['min'])}'),
                             Text('Max: ${formatStatValue(stats['max'])}'),
                             Text('Mean: ${formatStatValue(stats['mean'])}'),
                             Text('Median: ${formatStatValue(stats['median'])}'),
                             Text('Std Dev: ${formatStatValue(stats['std'])}'),
                           ]
                         : [ // Assumed categorical/text/date like
                             Text('Type: ${stats['type'] ?? 'Categorical'}'),
                             Text('Unique Values: ${formatStatValue(stats['unique_values'])}'),
                              if (stats['most_common'] is Map && (stats['most_common'] as Map).isNotEmpty)
                                 Text('Most Common: ${(stats['most_common'] as Map).entries.take(3).map((e) => "${e.key} (${e.value})").join(", ")}${(stats['most_common'] as Map).length > 3 ? ', ...' : ''}'),
                           ],
                   );
                }).toList(),
                const SizedBox(height: 16),
             ],
             
             // Section for Correlations (if available)
              if (_analysis!.correlations.isNotEmpty) ...[
               Text(
                 'Correlations (Top 3 per column)', // Adjust title as needed
                 style: theme.textTheme.titleMedium,
               ),
               const SizedBox(height: 8),
                ..._analysis!.correlations.entries.map((entry) {
                    // Sort correlations by absolute value, descending
                    final sortedCorrelations = entry.value.entries.toList()
                      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
                      
                    return ExpansionTile(
                       tilePadding: EdgeInsets.zero,
                       title: Text(entry.key, style: theme.textTheme.titleSmall),
                       childrenPadding: const EdgeInsets.only(left: 16, bottom: 8),
                       expandedCrossAxisAlignment: CrossAxisAlignment.start,
                       children: sortedCorrelations.take(3).map((corr) => 
                           Text('${corr.key}: ${corr.value.toStringAsFixed(3)}') // Show correlation value
                       ).toList(),
                    );
                }),
                 const SizedBox(height: 16),
             ],

             // Keep suggested viz summary here if desired
             if (_analysis!.visualizationSuggestions.isNotEmpty) ...[
               Text(
                 'Visualization Suggestions',
                 style: theme.textTheme.titleMedium,
               ),
               const SizedBox(height: 8),
               Wrap(
                 spacing: 8,
                 runSpacing: 4,
                 children: _analysis!.visualizationSuggestions.entries.map((entry) {
                    // Use icons for suggestion types
                    IconData iconData;
                    switch(entry.value.first.toLowerCase()) { // Use first suggestion for icon
                       case 'bar': iconData = Icons.bar_chart_outlined; break;
                       case 'line': iconData = Icons.show_chart_outlined; break;
                       case 'pie': iconData = Icons.pie_chart_outline; break;
                       case 'word_cloud': iconData = Icons.cloud_outlined; break;
                       default: iconData = Icons.auto_graph_outlined;
                    }
                   return Chip(
                     avatar: Icon(iconData, size: 16, color: theme.chipTheme.labelStyle?.color),
                     label: Text('${entry.key}: ${entry.value.join(", ")}'),
                     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                   );
                 }).toList(),
               ),
             ],
           ],
         ),
       ),
     );
  }

  // --- Export and Save Functions (Keep existing logic, ensure context/state checks) ---

  Future<void> _exportData(BuildContext parentContext) async {
     // Use parentContext to access Provider and ScaffoldMessenger
     final dataSet = parentContext.read<DataSet>(); 
     final scaffoldMessenger = ScaffoldMessenger.of(parentContext);

     if (dataSet.data.isEmpty) {
       _showSnackBar('No data to export', isError: true);
       return;
     }

    // Show dialog using parentContext
     await showDialog(
      context: parentContext, // Use the context passed to the function
      builder: (dialogContext) => AlertDialog(
        title: const Text('Export Data As'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['csv', 'excel', 'json'].map((format) {
             return ListTile(
               title: Text(format.toUpperCase()),
               onTap: () async {
                 Navigator.pop(dialogContext); // Close dialog first
                 bool success = false;
                 try {
                    success = await _fileService.exportData(dataSet.data, format);
                    // Show result AFTER export attempt finishes
                    _showSnackBar(success ? 'Export successful' : 'Export failed', isError: !success);
                 } catch(e) {
                    print("Export error ($format): $e");
                    _showSnackBar('Export failed: $e', isError: true);
                 }
               },
             );
          }).toList(),
        ),
      ),
    );
  }


  Future<void> _saveChartAsImage(BuildContext parentContext) async {
    // Use parentContext for ScaffoldMessenger
    final scaffoldMessenger = ScaffoldMessenger.of(parentContext);

    try {
      // Ensure the key is attached to the RepaintBoundary around the charts area
      final RenderRepaintBoundary? boundary = _chartContainerKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
          
      if (boundary == null) {
        _showSnackBar('Could not find chart area to save.', isError: true);
        return;
      }

      // Consider adding a small delay if charts animate, though RepaintBoundary usually waits
      // await Future.delayed(Duration(milliseconds: 300));

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0); // Adjust pixelRatio as needed
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
         _showSnackBar('Failed to generate chart image data.', isError: true);
        return;
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      // Use a more descriptive file name
      final fileName = 'DataViz_Chart_${DateTime.now().toIso8601String().replaceAll(':','-')}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pngBytes);

      // Use Share package
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Data Visualization Chart Export',
        subject: 'Chart Export', // Optional subject for email sharing
      );

       // Optionally show success message after sharing attempt (might close before user sees it)
       // _showSnackBar('Chart ready to share'); 

    } catch (e) {
       print("Save chart error: $e");
       _showSnackBar('Failed to save chart as image: $e', isError: true);
    }
  }
}