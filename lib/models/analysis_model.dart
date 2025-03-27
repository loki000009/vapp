class DataAnalysis {
  final Map<String, String> dataTypes;
  final Map<String, List<String>> visualizationSuggestions;
  final Map<String, Map<String, dynamic>> statistics;
  final Map<String, Map<String, double>> correlations;

  DataAnalysis({
    required this.dataTypes,
    required this.visualizationSuggestions,
    required this.statistics,
    required this.correlations,
  });

  factory DataAnalysis.fromJson(Map<String, dynamic> json) {
    // Handle potential null or missing values in the response
    return DataAnalysis(
      dataTypes: json['data_types'] != null 
        ? Map<String, String>.from(json['data_types']) 
        : {},
      visualizationSuggestions: json['visualization_suggestions'] != null 
        ? Map<String, List<String>>.from(
            json['visualization_suggestions'].map(
              (key, value) => MapEntry(key, List<String>.from(value)),
            ),
          )
        : {},
      statistics: json['statistics'] != null 
        ? Map<String, Map<String, dynamic>>.from(
            json['statistics'].map(
              (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
            ),
          )
        : {},
      correlations: json['correlations'] != null 
        ? Map<String, Map<String, double>>.from(
            json['correlations'].map(
              (key, value) => MapEntry(
                key,
                Map<String, double>.from(value),
              ),
            ),
          )
        : {},
    );
  }
}
