import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/scraper_provider.dart';
import '../services/api_service.dart';
import 'scraping_screen.dart';

class StateSelectionScreen extends StatefulWidget {
  @override
  _StateSelectionScreenState createState() => _StateSelectionScreenState();
}

class _StateSelectionScreenState extends State<StateSelectionScreen> {
  String? _selectedCountry = 'USA';
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
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _loadInitialData();
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

  Future<void> _loadInitialData() async {
    try {
      // 1. Load available countries (only set default on first load)
      final countries = await _apiService.getCountries();
      // Set default only if the user hasn't selected a country yet
      if (_selectedCountry == null) {
        if (countries.contains('USA')) {
          _selectedCountry = 'USA';
        } else if (countries.isNotEmpty) {
          _selectedCountry = countries.first;
        }
      }

      // 2. Load states/regions for the selected country
      final statesByCountry = await _apiService.getStates();
      List<String> states = [];
      // The backend returns a map where each country key maps to its list of states/regions.
      // Example: {"USA": ["Alabama", ...], "UK": ["Greater London", ...]}
      if (_selectedCountry != null &&
          statesByCountry[_selectedCountry] != null) {
        states = List<String>.from(statesByCountry[_selectedCountry]!);
      }

      // 3. Load cities for each state/region
      final Map<String, List<String>> statesData = {};
      for (String state in states) {
        final cities = await _apiService.getCities(state);
        statesData[state] = List<String>.from(cities);
      }

      if (mounted) {
        setState(() {
          _statesAndCities = statesData;
          _filteredStates = states;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading initial data: $e');
      // Fallback sample data
      if (mounted) {
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
          _filteredStates = _statesAndCities.keys.toList();
          _isLoading = false;
        });
      }
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
                  // Country selector
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(Icons.public, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('Select Country',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Spacer(),
                          // Expanded to give dropdown full width and avoid layout issues
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: _selectedCountry,
                                items: ['USA', 'UK']
                                    .map((c) => DropdownMenuItem<String>(
                                        value: c, child: Text(c)))
                                    .toList(),
                                onChanged: (val) async {
                                  if (val != null && val != _selectedCountry) {
                                    setState(() {
                                      _selectedCountry = val;
                                      _selectedState = null;
                                      _statesAndCities = {};
                                      _isLoading = true;
                                    });
                                    await _loadInitialData();
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                                // Join each "city, state" pair with a semicolon to keep the pair together when split later
                                // Build a semicolon‑separated list of "city, state" pairs.
                                // The scraping screen now expects each pair to be separated by ';'.
                                final citiesText = _selectedCities
                                    .map((city) => '$city, $_selectedState')
                                    .join('; ');

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
