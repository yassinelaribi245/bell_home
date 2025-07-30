import 'package:flutter/material.dart';
import 'dart:convert'; // For json.decode/encode
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:bellui/pages/enhanced_main_dashboard.dart'; // Import the new dashboard
import 'package:bellui/services/api_service.dart'; // Import the new API service
import 'package:bellui/utils/utils.dart'; // Import the new utils

class LoginRegisterPage extends StatefulWidget { // Renamed from LoginPage
  const LoginRegisterPage({super.key});

  @override
  _LoginRegisterPageState createState() => _LoginRegisterPageState(); // Renamed state class
}

class _LoginRegisterPageState extends State<LoginRegisterPage> { // Renamed state class
  // ApiService instance
  final ApiService _apiService = ApiService();

  Future<void> fetchVilles() async {
    // Use ApiService for network requests
    try {
      final response = await _apiService.get('/ville');
      if (!mounted) return; // Check mounted before using context
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        setState(() {
          _villes = List<Map<String, dynamic>>.from(data);
          _isLoadingVilles = false;
        });
      } else {
        setState(() {
          _villes = [];
          _isLoadingVilles = false;
        });
        UIUtils.showSnackBar(context, 'Failed to load cities: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return; // Check mounted before using context
      UIUtils.showSnackBar(context, 'Error fetching cities: $e');
      setState(() {
        _villes = [];
        _isLoadingVilles = false;
      });
    }
  }

  List<Map<String, dynamic>> _villes = [];
  int? _selectedVilleId;
  bool _isLoadingVilles = true;

  bool _showLogin = true;
  // Controllers to get input text
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _codePostalController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();

  String _feedback = '';

  @override
  void initState() {
    super.initState();
    // Only fetch cities if we are showing the register form initially
    // This was causing an issue if _showLogin was true initially
    // The fetchVilles() call should be triggered when switching to register form
    // or if the initial state is register.
    if (!_showLogin) {
      fetchVilles();
    }
  }

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final dateOfBirth = _dateController.text.trim();
    final codePostal = _codePostalController.text.trim();
    final number = _numberController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // Basic validation using ValidationUtils
    if (ValidationUtils.validateRequired(name, 'Name') != null ||
        ValidationUtils.validateRequired(lastName, 'Last Name') != null ||
        ValidationUtils.validateRequired(dateOfBirth, 'Date of Birth') != null ||
        ValidationUtils.validateRequired(codePostal, 'Postal Code') != null ||
        ValidationUtils.validateRequired(number, 'Number') != null ||
        ValidationUtils.validateEmail(email) != null ||
        ValidationUtils.validatePassword(password) != null ||
        _selectedVilleId == null) {
      setState(() {
        _feedback = 'Please fill in all fields correctly.';
      });
      return;
    }

    UIUtils.showLoadingDialog(context, message: 'Registering...');

    try {
      final response = await _apiService.post(
        '/register',
        body: {
          'nom': name,
          'prenom': lastName,
          'date_naissance': dateOfBirth,
          'code_postal': codePostal,
          'num_tel': number,
          'email': email,
          'password': password,
          'id_ville': _selectedVilleId,
        },
      );

      if (!mounted) return; // Check mounted before using context
      UIUtils.hideLoadingDialog(context);

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          _feedback = 'Registration successful!';
        });

        if (data.containsKey('token')) {
          await _apiService.saveAuthToken(data['token']);
          // Assuming User model can be created from data['user']
          // User user = User.fromJson(data['user']); // You might need to implement fromJson in your User model
          // await _apiService.saveUserData(user);
        }

        final fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          await _apiService.post(
            '/save-fcm-token',
            body: {'fcm_token': fcmToken, 'email': email}, // Use email directly
          );
        }

        if (!mounted) return; // Check mounted before using context
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const EnhancedMainDashboard()),
        );
      } else {
        String errorMessage = 'Registration failed.';
        if (data.containsKey('errors')) {
          final errors = data['errors'] as Map<String, dynamic>;
          errorMessage = errors.entries
              .map((entry) => "${entry.key}: ${entry.value.join(', ')}")
              .join('\n');
        }
        setState(() {
          _feedback = errorMessage;
        });
        UIUtils.showSnackBar(context, errorMessage, backgroundColor: Colors.red);
      }
    } catch (e) {
      if (!mounted) return; // Check mounted before using context
      UIUtils.hideLoadingDialog(context);
      setState(() {
        _feedback = 'Error: $e';
      });
      UIUtils.showSnackBar(context, 'Error: $e', backgroundColor: Colors.red);
    }
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (ValidationUtils.validateEmail(email) != null ||
        ValidationUtils.validateRequired(password, 'Password') != null) {
      setState(() {
        _feedback = 'Please fill in both fields correctly.';
      });
      return;
    }

    UIUtils.showLoadingDialog(context, message: 'Logging in...');

    try {
      final response = await _apiService.post(
        '/login',
        body: {'email': email, 'password': password},
      );

      if (!mounted) return; // Check mounted before using context
      UIUtils.hideLoadingDialog(context);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          _feedback = 'Login successful!';
        });

        if (data.containsKey('token')) {
          await _apiService.saveAuthToken(data['token']);
          await _apiService.saveUserData(data['user']);
        }

        final fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          final userEmail = data['user']['email'];
          final response = await _apiService.post(
            '/save-fcm-token',
            body: {
              'fcm_token': fcmToken,
              'email': userEmail,
              'platform': 'android', // or 'ios' if on iOS
            },
          );
          if (response.statusCode != 200) {
            debugPrint('FCM token registration failed: ${response.body}');
          }
        }

        if (!mounted) return; // Check mounted before using context
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const EnhancedMainDashboard()),
        );
      } else {
        setState(() {
          _feedback = 'Login failed (${response.statusCode}).';
        });
        UIUtils.showSnackBar(context, 'Login failed: ${response.statusCode}', backgroundColor: Colors.red);
      }
    } catch (e) {
      if (!mounted) return; // Check mounted before using context
      UIUtils.hideLoadingDialog(context);
      setState(() {
        _feedback = 'Error: $e';
      });
      UIUtils.showSnackBar(context, 'Error: $e', backgroundColor: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _showLogin ? _buildLogin() : _buildRegister(),
        ),
      ),
    );
  }

  Widget _buildLogin() {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            colors: [
              Color.fromARGB(255, 70, 46, 37),
              Color.fromARGB(255, 75, 50, 42),
              Color.fromARGB(255, 104, 79, 70),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 80),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "Login",
                    style: TextStyle(color: Colors.white, fontSize: 50),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Welcome Again",
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(60)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: 60),
                      Container(
                        margin: const EdgeInsets.all(25),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: Color.fromRGBO(225, 95, 27, .3),
                              blurRadius: 20,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: TextField(
                                controller: _emailController,
                                decoration: const InputDecoration(
                                  hintText: "Email",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: TextField(
                                controller: _passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  hintText: "password",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "forgot password ?",
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 40),
                      GestureDetector(
                        onTap: _login,
                        child: Container(
                          height: 60,
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            color: const Color.fromARGB(255, 70, 46, 37),
                          ),
                          child: const Center(
                            child: Text(
                              "Login",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 70, 46, 37),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: TextButton(
                              onPressed: () {
                                setState(() {
                                  _showLogin = false;
                                  _isLoadingVilles = true;
                                  _feedback = "";
                                  fetchVilles();
                                });
                              },
                              child: const Text(
                                "Don't have an account? Register",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(_feedback, style: const TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegister() {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            colors: [
              Color.fromARGB(255, 70, 46, 37),
              Color.fromARGB(255, 75, 50, 42),
              Color.fromARGB(255, 104, 79, 70),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 80),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "Register",
                    style: TextStyle(color: Colors.white, fontSize: 50),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "Welcome We Are Happy To Have You",
                    style: TextStyle(color: Colors.white, fontSize: 20),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(60)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: 60),
                      Container(
                        margin: const EdgeInsets.all(15),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: Color.fromRGBO(225, 95, 27, .3),
                              blurRadius: 20,
                              offset: Offset(5, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: TextField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  hintText: "Name",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: TextField(
                                controller: _lastNameController,
                                decoration: const InputDecoration(
                                  hintText: "Last Name",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: InkWell(
                                onTap: () async {
                                  DateTime? pickedDate = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime(2000),
                                    firstDate: DateTime(1900),
                                    lastDate: DateTime.now(),
                                  );

                                  String formattedDate =
                                      "${pickedDate?.toLocal()}".split(' ')[0];
                                  setState(() {
                                    _dateController.text = formattedDate;
                                  });
                                },
                                child: IgnorePointer(
                                  child: TextField(
                                    controller: _dateController,
                                    decoration: const InputDecoration(
                                      hintText: "Date Of Birth",
                                      hintStyle: TextStyle(color: Colors.grey),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: TextField(
                                controller: _codePostalController,
                                decoration: const InputDecoration(
                                  hintText: "Code Postal",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: TextField(
                                controller: _numberController,
                                decoration: const InputDecoration(
                                  hintText: "Number",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: TextField(
                                controller: _emailController,
                                decoration: const InputDecoration(
                                  hintText: "Email",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: TextField(
                                controller: _passwordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  hintText: "Password",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: _isLoadingVilles
                                  ? const CircularProgressIndicator()
                                  : DropdownButtonFormField<int>(
                                      decoration: const InputDecoration(
                                        hintText: "Select Ville",
                                        border: InputBorder.none,
                                      ),
                                      value: _selectedVilleId,
                                      items: _villes.map((ville) {
                                        return DropdownMenuItem<int>(
                                          value: ville['id'],
                                          child: Text(ville['label']),
                                        );
                                      }).toList(),
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedVilleId = value;
                                        });
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      GestureDetector(
                        onTap: _register,
                        child: Container(
                          height: 60,
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            color: const Color.fromARGB(255, 70, 46, 37),
                          ),
                          child: const Center(
                            child: Text(
                              "Register",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 70, 46, 37),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: TextButton(
                              onPressed: () {
                                setState(() {
                                  _showLogin = true;
                                  _villes = [];
                                  _selectedVilleId = null;
                                  _feedback = "";
                                });
                              },
                              child: const Text(
                                "you have a account ?,login !",
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(_feedback, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


