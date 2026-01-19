import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/scraper_provider.dart';
import '../screens/home_screen.dart';
import 'state_selection_screen.dart';
import '../providers/scraper_provider.dart' show ScrapingStatus;
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class ScrapingScreen extends StatefulWidget {
  final String initialCategory;
  final String initialCities;
  final String initialMaxResults;

  ScrapingScreen({
    this.initialCategory = '',
    this.initialCities = '',
    this.initialMaxResults = '10',
  });

  @override
  _ScrapingScreenState createState() => _ScrapingScreenState();
}

class _ScrapingScreenState extends State<ScrapingScreen> {
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _citiesController = TextEditingController();
  final TextEditingController _maxResultsController =
      TextEditingController(text: '10');

  @override
  void initState() {
    super.initState();
    _categoryController.text = widget.initialCategory;
    _citiesController.text = widget.initialCities;
    _maxResultsController.text = widget.initialMaxResults;
  }

  Future<void> _saveCSVToFile(String csvContent, String filename) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        // Request storage permission
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Storage permission denied')),
          );
          return;
        }
      }
      
      // For mobile, we'll show the CSV content in a dialog
      // In a real app, you'd use a file picker or share functionality
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Results Downloaded'),
          content: SingleChildScrollView(
            child: Text('CSV data ready. Length: ${csvContent.length} characters'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving file: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scraperProvider = Provider.of<ScraperProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Start Scraping'),
        backgroundColor: Color(0xFF667eea),
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF667eea).withOpacity(0.1),
              Colors.white,
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // API Status Card
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: scraperProvider.isApiConnected
                          ? [Colors.green.shade400, Colors.green.shade600]
                          : [Colors.red.shade400, Colors.red.shade600],
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          scraperProvider.isApiConnected
                              ? Icons.check_circle
                              : Icons.error,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              scraperProvider.isApiConnected
                                  ? 'API Connected'
                                  : 'API Disconnected',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              scraperProvider.isApiConnected
                                  ? 'Ready to scrape'
                                  : 'Please check connection',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 24),
              // Category Input
              Text(
                'Search Category',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              SizedBox(height: 8),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _categoryController,
                  decoration: InputDecoration(
                    labelText: 'e.g., Restaurants, Hotels, Shops',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: Icon(Icons.search, color: Color(0xFF667eea)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              SizedBox(height: 20),
              // Cities Input
              Text(
                'Cities',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              SizedBox(height: 8),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _citiesController,
                  decoration: InputDecoration(
                    labelText: 'Select cities or enter manually',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: Icon(Icons.location_city, color: Color(0xFF667eea)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  maxLines: 3,
                ),
              ),
              SizedBox(height: 20),
              // Max Results Input
              Text(
                'Max Results per City',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              SizedBox(height: 8),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _maxResultsController,
                  decoration: InputDecoration(
                    labelText: 'Number of results',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: Icon(Icons.format_list_numbered, color: Color(0xFF667eea)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              SizedBox(height: 32),
              // Action Buttons Row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => StateSelectionScreen(),
                          ),
                        );
                      },
                      icon: Icon(Icons.location_on),
                      label: Text('Select Cities'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Color(0xFF667eea), width: 2),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: scraperProvider.status == ScrapingStatus.running
                          ? null
                          : () async {
                              if (_categoryController.text.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Please enter a search category'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }

                              if (_citiesController.text.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Please select cities'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }

                              try {
                                final citiesText = _citiesController.text;
                                final citiesList = citiesText
                                    .split(',')
                                    .map((city) => city.trim())
                                    .where((city) => city.isNotEmpty)
                                    .toList();

                                if (citiesList.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('No valid cities found'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }

                                final maxResults =
                                    int.tryParse(_maxResultsController.text) ?? 10;
                                if (maxResults <= 0) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Max results must be greater than 0'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }

                                await scraperProvider.startScraping(
                                  category: _categoryController.text,
                                  citiesData: citiesList,
                                  maxResultsPerCity: maxResults,
                                );

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Scraping started successfully!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Failed to start scraping: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                      icon: Icon(Icons.play_arrow),
                      label: Text('Start Scraping'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF667eea),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),
              // Progress Indicator
              if (scraperProvider.status == ScrapingStatus.running)
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Scraping in progress...',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: (scraperProvider.currentJob?.progress ?? 0) / 100,
                                    backgroundColor: Colors.grey[200],
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                                    minHeight: 8,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '${scraperProvider.currentJob?.progress ?? 0}% Complete',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (scraperProvider.currentJob?.currentCity != null) ...[
                          SizedBox(height: 16),
                          Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Color(0xFF667eea).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.location_on, size: 16, color: Color(0xFF667eea)),
                                SizedBox(width: 8),
                                Text(
                                  'Current: ${scraperProvider.currentJob?.currentCity}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF667eea),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            scraperProvider.reset();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Scraping stopped'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: Text('Stop Scraping'),
                        ),
                      ],
                    ),
                  ),
                ),
              // Results Display
              if (scraperProvider.status == ScrapingStatus.completed)
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [Colors.green.shade400, Colors.green.shade600],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.white, size: 32),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Scraping Completed!',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Found ${scraperProvider.currentJob?.results.length ?? 0} results',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () async {
                            try {
                              final csvData = await scraperProvider.downloadResults();
                              await _saveCSVToFile(csvData, 'results.csv');
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to download results: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          icon: Icon(Icons.download),
                          label: Text('Download Results'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.green.shade700,
                            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              SizedBox(height: 24),
              // Logs Display
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.description, color: Color(0xFF667eea)),
                          SizedBox(width: 8),
                          Text(
                            'Activity Logs',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.all(12),
                          itemCount: scraperProvider.getCurrentLogs().length,
                          itemBuilder: (context, index) {
                            final log = scraperProvider.getCurrentLogs()[index];
                            return Padding(
                              padding: EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                log,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _categoryController.dispose();
    _citiesController.dispose();
    _maxResultsController.dispose();
    super.dispose();
  }
}
