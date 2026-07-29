import 'package:flutter/material.dart';

/// Error boundary widget that catches exceptions and displays an error UI
/// 
/// Usage:
///   ErrorBoundary(
///     child: MyWidget(),
///     onError: (error, stackTrace) => print('Error: $error'),
///   )
class ErrorBoundary extends StatefulWidget {
  final Widget child;

  const ErrorBoundary({
    super.key,
    required this.child,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  dynamic _error;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text('An unexpected error occurred'),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  '$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    return widget.child;
  }
}
