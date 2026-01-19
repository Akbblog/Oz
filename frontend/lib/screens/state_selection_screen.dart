import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../providers/scraper_provider.dart';
import 'scraping_screen.dart';

class StateSelectionScreen extends StatefulWidget {
  @override
  _StateSelectionScreenState createState() => _StateSelectionScreenState();
}

class _StateSelectionScreenState extends State<StateSelectionScreen> {
  String? _selectedState;
  List<String> _selectedCities = [];
  bool _selectAllCities = false;
  bool _isLoading = true;
  Map<String, List<String>> _statesAndCities = {};
  List<String> _filteredStates = [];
  List<String> _filteredCities = [];
  final TextEditingController _stateSearchController = TextEditingController();
  final TextEditingController _citySearchController = TextEditingController();
  bool _isStateSearchFocused = false;
  bool _isCitySearchFocused = false;

  @override
  void initState() {
    super.initState();
    _loadStatesData();
    _stateSearchController.addListener(_filterStates);
    _citySearchController.addListener(_filterCities);
  }

  @override
  void dispose() {
    _stateSearchController.dispose();
    _citySearchController.dispose();
    super.dispose();
  }

  void _filterStates() {
    final query = _stateSearchController.text.toLowerCase();
    setState(() {
      _filteredStates = _statesAndCities.keys
          .where((state) => state.toLowerCase().contains(query))
          .toList();
    });
  }

  void _filterCities() {
    final query = _citySearchController.text.toLowerCase();
    setState(() {
      if (_selectedState != null) {
        _filteredCities = _statesAndCities[_selectedState]!
            .where((city) => city.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  Future<void> _loadStatesData() async {
    try {
      // Fetch states from backend API
      final response = await http.get(
        Uri.parse('http://localhost:8000/api/states'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> states = data['states'];

        // Fetch cities for each state
        final Map<String, List<String>> statesData = {};
        for (String state in states) {
          final citiesResponse = await http.get(
            Uri.parse(
                'http://localhost:8000/api/states/${Uri.encodeComponent(state)}/cities'),
          );

          if (citiesResponse.statusCode == 200) {
            final citiesData = json.decode(citiesResponse.body);
            statesData[state] = List<String>.from(citiesData['cities']);
          }
        }

        setState(() {
          _statesAndCities = statesData;
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load states');
      }
    } catch (e) {
      print('Error loading states data: $e');
      // Fallback to sample data if loading fails
      setState(() {
        _statesAndCities = {
          'California': [
            'Los Angeles',
            'San Diego',
            'San Jose',
            'San Francisco'
          ],
          'New York': ['New York', 'Buffalo', 'Rochester'],
          'Texas': ['Houston', 'Dallas', 'Austin'],
        };
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Select State and Cities'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Card for State Selection
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.location_on, color: Colors.blue),
                              SizedBox(width: 8),
                              Text(
                                'Select State',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          // State Search
                          TextField(
                            controller: _stateSearchController,
                            decoration: InputDecoration(
                              labelText: 'Search State',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.search),
                              suffixIcon: _isStateSearchFocused
                                  ? IconButton(
                                      icon: Icon(Icons.clear),
                                      onPressed: () {
                                        _stateSearchController.clear();
                                        _filterStates();
                                      },
                                    )
                                  : null,
                            ),
                            focusNode: FocusNode(),
                            onChanged: (value) => _filterStates(),
                          ),
                          SizedBox(height: 16),
                          // State Grid
                          Container(
                            height: 200,
                            child: GridView.builder(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 2,
                              ),
                              itemCount: _filteredStates.length,
                              itemBuilder: (context, index) {
                                final state = _filteredStates[index];
                                return ChoiceChip(
                                  label: Text(state),
                                  selected: _selectedState == state,
                                  onSelected: (selected) {
                                    setState(() {
                                      _selectedState = selected ? state : null;
                                      _selectedCities = [];
                                      _selectAllCities = false;
                                      _citySearchController.clear();
                                      _filterCities();
                                    });
                                  },
                                  backgroundColor: Colors.grey[200],
                                  selectedColor: Colors.blue,
                                  labelStyle: TextStyle(
                                    color: _selectedState == state
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 20),

                  // Card for Cities Selection
                  if (_selectedState != null)
                    Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.location_city, color: Colors.blue),
                                SizedBox(width: 8),
                                Text(
                                  'Select Cities in $_selectedState',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Spacer(),
                                Text(
                                  '${_selectedCities.length} selected',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 16),
                            // City Search
                            TextField(
                              controller: _citySearchController,
                              decoration: InputDecoration(
                                labelText: 'Search City',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.search),
                                suffixIcon:
                                    _citySearchController.text.isNotEmpty
                                        ? IconButton(
                                            icon: Icon(Icons.clear),
                                            onPressed: () {
                                              _citySearchController.clear();
                                              _filterCities();
                                            },
                                          )
                                        : null,
                              ),
                              onChanged: (value) => _filterCities(),
                            ),
                            SizedBox(height: 16),
                            // Select All Button
                            Row(
                              children: [
                                Checkbox(
                                  value: _selectAllCities,
                                  onChanged: (bool? value) {
                                    setState(() {
                                      _selectAllCities = value ?? false;
                                      if (_selectAllCities) {
                                        _selectedCities =
                                            List.from(_filteredCities);
                                      } else {
                                        _selectedCities = [];
                                      }
                                    });
                                  },
                                ),
                                Text('Select All'),
                                Spacer(),
                                Text(
                                  '${_filteredCities.length} cities available',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            // Cities List
                            Container(
                              height: 200,
                              child: ListView.builder(
                                itemCount: _filteredCities.length,
                                itemBuilder: (context, index) {
                                  final city = _filteredCities[index];
                                  return CheckboxListTile(
                                    title: Text(city),
                                    value: _selectedCities.contains(city),
                                    onChanged: (bool? value) {
                                      setState(() {
                                        if (value ?? false) {
                                          _selectedCities.add(city);
                                        } else {
                                          _selectedCities.remove(city);
                                        }
                                        // Update select all checkbox state
                                        _selectAllCities =
                                            _selectedCities.length ==
                                                _filteredCities.length;
                                      });
                                    },
                                    dense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      vertical: 2,
                                      horizontal: 8,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  SizedBox(height: 20),

                  // Selected Summary
                  if (_selectedState != null && _selectedCities.isNotEmpty)
                    Card(
                      elevation: 2,
                      color: Colors.blue[50],
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Icon(Icons.info, color: Colors.blue),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Selected ${_selectedCities.length} cities in $_selectedState',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.blue[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  SizedBox(height: 20),

                  // Continue Button
                  ElevatedButton(
                    onPressed:
                        _selectedState != null && _selectedCities.isNotEmpty
                            ? () {
                                final citiesText = _selectedCities
                                    .map((city) => '$city, $_selectedState')
                                    .join(', ');

                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => ScrapingScreen(
                                      initialCategory: '',
                                      initialCities: citiesText,
                                      initialMaxResults: '10',
                                    ),
                                  ),
                                );
                              }
                            : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      minimumSize: Size(double.infinity, 50),
                    ),
                    child: Text(
                      'Continue to Scraping',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
