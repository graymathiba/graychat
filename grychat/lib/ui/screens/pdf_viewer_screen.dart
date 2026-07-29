import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

class PdfViewerScreen extends StatefulWidget {
  final Uint8List pdfBytes;
  final String? fileName;

  const PdfViewerScreen({
    super.key,
    required this.pdfBytes,
    this.fileName,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  PdfController? _controller;
  int _currentPage = 1;
  int _totalPages = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      _controller = PdfController(
        document: PdfDocument.openData(widget.pdfBytes),
      );
      final doc = await _controller!.document;
      setState(() {
        _totalPages = doc.pagesCount;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B4EBA),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.fileName ?? 'PDF Viewer',
          style: const TextStyle(color: Colors.white, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_totalPages > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '$_currentPage / $_totalPages',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load PDF',
                        style: TextStyle(color: Colors.grey[700], fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : PdfView(
                  controller: _controller!,
                  onDocumentLoaded: (doc) {
                    setState(() => _totalPages = doc.pagesCount);
                  },
                  onPageChanged: (page) {
                    setState(() => _currentPage = page);
                  },
                ),
    );
  }
}
