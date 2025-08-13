import 'package:bellui/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AddCameraPage extends StatefulWidget {
  const AddCameraPage({Key? key} ) : super(key: key);

  @override
  State<AddCameraPage> createState() => _AddCameraPageState();
}

class _AddCameraPageState extends State<AddCameraPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _longitudeController = TextEditingController();
  final TextEditingController _camCodeController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();

  List<dynamic> _homes = [];
  dynamic _selectedHome;

  bool _isLoadingHomes = false;
  bool _isSubmitting = false;

  static const String apiBaseUrl = ApiService.baseUrl;

  Future<String?> _getEmail() async {
    final box = await Hive.openBox('authBox');
    return box.get('user')['email'] as String?;
  }

  Future<void> _loadHomes() async {
    setState(() {
      _isLoadingHomes = true;
    });

    final email = await _getEmail();
    if (email == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User email not found'), backgroundColor: Colors.red),
        );
      }
      setState(() {
        _isLoadingHomes = false;
      });
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/homes_user' ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('API Response for homes: $data'); // Log API response
        setState(() {
          _homes = data['homes'] ?? [];
          if (_homes.isNotEmpty) {
            _selectedHome = _homes[0];
          } else {
            _selectedHome = null;
          }
          print('Loaded homes: $_homes'); // Log loaded homes
          print('Selected home after load: $_selectedHome'); // Log selected home
        });
      } else {
        final errorMsg = jsonDecode(response.body)['message'] ?? 'Failed to load homes';
        print('Error loading homes: $errorMsg'); // Log error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      print('Exception during home loading: $e'); // Log exceptions
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingHomes = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    print('Attempting to submit form...'); // Added for debugging
    if (!_formKey.currentState!.validate()) {
      print('Form validation failed!'); // Added for debugging
      return;
    }
    if (_selectedHome == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a home'), backgroundColor: Colors.red),
      );
      print('No home selected!'); // Added for debugging
      return;
    }

    final email = await _getEmail();
    if (email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User email not found'), backgroundColor: Colors.red),
      );
      print('User email not found!'); // Added for debugging
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final payload = {
      'longitude': _longitudeController.text.trim(),
      'cam_code': _camCodeController.text.trim(),
      'latitude': _latitudeController.text.trim(),
      'id_home': _selectedHome['id'],
    };

    print('Submitting payload: $payload'); // Log payload before submission

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/addcamera' ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        print('Camera added successfully!'); // Log success
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera added successfully!'), backgroundColor: Colors.green),
          );
          Navigator.pop(context);
        }
      } else {
        final errorMsg = jsonDecode(response.body)['message'] ?? 'Failed to add camera';
        print('API Error during camera add: $errorMsg'); // Log API error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      print('Exception during camera add: $e'); // Log exceptions
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadHomes();
  }

  @override
  Widget build(BuildContext context) {
    print('_isSubmitting: $_isSubmitting'); // Added for debugging
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Camera'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 2,
      ),
      body: _isLoadingHomes
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(12),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _camCodeController,
                      decoration: InputDecoration(
                        labelText: 'Camera Code',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a camera code';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _longitudeController,
                      decoration: InputDecoration(
                        labelText: 'Camera Longitude',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter the longitude';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _latitudeController,
                      decoration: InputDecoration(
                        labelText: 'Camera Latitude',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter the latitude';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<dynamic>(
                      value: _selectedHome,
                      items: _homes
                          .map((home) => DropdownMenuItem(
                                value: home,
                                child: Text(home['id'].toString()),
                              ))
                          .toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedHome = val;
                          print('Dropdown selected: $_selectedHome'); // Log dropdown selection
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Select Home',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (value) {
                        if (value == null) {
                          return 'Please select a home';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isSubmitting
                            ? null
                            : () {
                                print('Add Camera button pressed!'); // Added for debugging
                                _submit();
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSubmitting
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Add Camera', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
