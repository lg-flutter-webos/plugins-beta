import 'package:flutter/material.dart';

import 'guided_validation_screen.dart' show ValidationResult;

/// Static results screen shown after the guided validation completes.
/// Built once from a fixed list — no live updates, no streams, no timers.
class ResultsScreen extends StatelessWidget {
  final List<ValidationResult> results;

  const ResultsScreen({super.key, required this.results});

  @override
  Widget build(BuildContext context) {
    final passed = results.where((r) => r.passed).length;
    final total = results.length;
    final allPassed = passed == total;

    return Scaffold(
      appBar: AppBar(title: const Text('Validation Results')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: (allPassed ? Colors.green : Colors.red).withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(
                  allPassed ? Icons.check_circle : Icons.error,
                  color: allPassed ? Colors.green : Colors.red,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  '$passed / $total passed',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final r = results[index];
                final color = r.passed ? Colors.green : Colors.red;
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: color, width: 4)),
                    ),
                    child: ListTile(
                      leading: Icon(
                        r.passed ? Icons.check_circle : Icons.error,
                        color: color,
                      ),
                      title: Text(
                        r.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        r.detail,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
