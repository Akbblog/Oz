import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:csv/csv.dart';
import '../providers/scraper_provider.dart';

class ResultsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scraperProvider = Provider.of<ScraperProvider>(context);
    final results = scraperProvider.currentJob?.results ?? [];

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Results (${results.length} businesses)',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed:
                      results.isEmpty ? null : () => _downloadResults(context),
                  icon: Icon(Icons.download),
                  label: Text('Download CSV'),
                ),
              ],
            ),

            SizedBox(height: 16),

            // Results List
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No results yet',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Start a scraping job to see results here',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final business = results[index];
                        return BusinessCard(business: business);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadResults(BuildContext context) async {
    final scraperProvider =
        Provider.of<ScraperProvider>(context, listen: false);

    try {
      final csvContent = await scraperProvider.downloadResults();

      // In a real app, you'd write the file
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Results ready for download')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download: $e')),
      );
    }
  }
}

class BusinessCard extends StatelessWidget {
  final Map<String, dynamic> business;

  BusinessCard({required this.business});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Business Name
            Text(
              business['business_name'] ?? 'Unknown Business',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),

            SizedBox(height: 8),

            // Location
            Row(
              children: [
                Icon(Icons.location_on, size: 16, color: Colors.grey),
                SizedBox(width: 4),
                Text(
                  '${business['city']}, ${business['state']}',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),

            SizedBox(height: 4),

            // Contact Info
            Wrap(
              spacing: 16,
              children: [
                if (business['phone'] != null && business['phone'] != 'N/A')
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.phone, size: 16, color: Colors.green),
                      SizedBox(width: 4),
                      Text(business['phone']),
                    ],
                  ),
                if (business['website'] != null && business['website'] != 'N/A')
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.language, size: 16, color: Colors.blue),
                      SizedBox(width: 4),
                      Text(
                        'Website',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ],
                  ),
              ],
            ),

            SizedBox(height: 8),

            // Address
            if (business['address'] != null && business['address'] != 'N/A')
              Text(
                business['address'],
                style: TextStyle(color: Colors.grey[600]),
              ),

            // Category
            Chip(
              label: Text(business['category'] ?? 'Unknown'),
              backgroundColor: Colors.blue[50],
            ),
          ],
        ),
      ),
    );
  }
}
