import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class ChartWidgets {
  static Widget lineChart(List<Map<String, dynamic>> data, String xAxis, String yAxis) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true),
          titlesData: FlTitlesData(show: true),
          borderData: FlBorderData(show: true),
          lineBarsData: [
            LineChartBarData(
              spots: data.asMap().entries.map((entry) {
                return FlSpot(
                  entry.key.toDouble(),
                  double.tryParse(entry.value[yAxis].toString()) ?? 0,
                );
              }).toList(),
              isCurved: true,
              color: Colors.blue,
              dotData: FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
  }

  static Widget barChart(List<Map<String, dynamic>> data, String xAxis, String yAxis) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      child: BarChart(
        BarChartData(
          gridData: FlGridData(show: true),
          titlesData: FlTitlesData(show: true),
          borderData: FlBorderData(show: true),
          barGroups: data.asMap().entries.map((entry) {
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: double.tryParse(entry.value[yAxis].toString()) ?? 0,
                  color: Colors.blue,
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  static Widget pieChart(List<Map<String, dynamic>> data, String categoryField, String valueField) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      child: PieChart(
        PieChartData(
          sections: data.map((item) {
            return PieChartSectionData(
              value: double.tryParse(item[valueField].toString()) ?? 0,
              title: item[categoryField].toString(),
              color: Colors.primaries[data.indexOf(item) % Colors.primaries.length],
              radius: 100,
            );
          }).toList(),
          sectionsSpace: 2,
          centerSpaceRadius: 40,
        ),
      ),
    );
  }
}