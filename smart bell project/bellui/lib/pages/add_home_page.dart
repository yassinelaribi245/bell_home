import 'package:bellui/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AddHomePage extends StatefulWidget {
  const AddHomePage({Key? key} ) : super(key: key);

  @override
  State<AddHomePage> createState() => _AddHomePageState();
}

class _AddHomePageState extends State<AddHomePage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _superficieController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();

  bool _isLoading = false;

  // Use your actual API base URL here
  static const String apiBaseUrl = ApiService.baseUrl;

  Future<String?> _getEmail() async {
    final box = await Hive.openBox('authBox');
    return box.get('user')['email'] as String?;
  }

  Future<void> _submit() async {
    print('Attempting to submit home form...'); // Added for debugging
    if (!_formKey.currentState!.validate()) {
      print('Home form validation failed!'); // Added for debugging
      return;
    }

    final email = await _getEmail();
    if (email == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User email not found')));
      print('User email not found in home form!'); // Added for debugging
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final payload = {
      'superficie': _superficieController.text.trim(),
      'longitude': _longitudeController.text.trim(),
      'latitude': _latitudeController.text.trim(),
      'num_cam': 0,
      'email': email
    };

    print('Submitting home payload: $payload'); // Added for debugging

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/addhome' ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        // Success
        print('Home added successfully!'); // Added for debugging
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Home added successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context); // go back after success
        }
      } else {
        final errorMsg =
            jsonDecode(response.body)['message'] ?? 'Failed to add home';
        print('API Error during home add: $errorMsg'); // Added for debugging
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      print('Exception during home add: $e'); // Added for debugging
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    print('_isLoading: $_isLoading'); // Added for debugging
    // Match your exact padding, color, style from previous code
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Home'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 2,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12), // same padding as cards
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _superficieController,
                decoration: InputDecoration(
                  labelText: 'Superficie',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter Superficie'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _longitudeController,
                decoration: InputDecoration(
                  labelText: 'Longitude',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter Longitude'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _latitudeController,
                decoration: InputDecoration(
                  labelText: 'Latitude',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please enter Latitude'
                    : null,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          print('Add Home button pressed!'); // Added for debugging
                          _submit();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Add Home', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
