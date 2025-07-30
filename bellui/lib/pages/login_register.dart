import 'package:flutter/material.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensure Flutter engine is initialized
  await Hive.initFlutter(); // Initialize Hive
  await Hive.openBox('authBox'); // Pre-open your box
  runApp(MaterialApp(debugShowCheckedModeBanner: false, home: HomePage()));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<void> fetchVilles() async {
    final url = Uri.parse('$baseurl/api/ville');
    try {
      final response = await http.get(url);
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');
      if (response.statusCode == 200) {
        List data = jsonDecode(response.body);
        print('Data decoded: $data');
        setState(() {
          _villes = List<Map<String, dynamic>>.from(data);
          _isLoadingVilles = false;
        });
      } else {
        setState(() {
          _villes = [];
          _isLoadingVilles = false;
        });
      }
    } catch (e) {
      print('Error fetching villes: $e');
      setState(() {
        _villes = [];
        _isLoadingVilles = false;
      });
    }
  }

  final baseurl = 'https://066e5a41f389.ngrok-free.app';
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

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final dateOfBirth = _dateController.text.trim();
    final codePostal = _codePostalController.text.trim();
    final number = _numberController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty ||
        lastName.isEmpty ||
        dateOfBirth.isEmpty ||
        codePostal.isEmpty ||
        number.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        _selectedVilleId == null) {
      setState(() {
        _feedback = 'Please fill in all fields.';
      });
      return;
    }

    final url = Uri.parse('$baseurl/api/register');

    setState(() {
      _feedback = 'Registering...';
    });

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'nom': name,
          'prenom': lastName,
          'date_naissance': dateOfBirth,
          'code_postal': codePostal,
          'num_tel': number,
          'email': email,
          'password': password,
          'id_ville': _selectedVilleId,
        }),
      );

      final data = jsonDecode(response.body);

      if (data.containsKey('errors')) {
        // Show validation errors
        final errors = data['errors'] as Map<String, dynamic>;
        String errorMessage = errors.entries
            .map((entry) => "${entry.key}: ${entry.value.join(', ')}")
            .join('\n');

        setState(() {
          _feedback = 'Registration failed:\n$errorMessage';
        });
      } else {
        // Treat as success
        setState(() {
          _feedback = 'Registration successful!';
        });

        if (data.containsKey('token')) {
          var box = Hive.box('authBox');
          await box.put('token', data['token']);
          await box.put('user', data['user']);
        }
        var box = Hive.box('authBox');
        final user = box.get('user');
        final fcmToken = await FirebaseMessaging.instance.getToken();
        await http.post(
          Uri.parse('$baseurl/api/save-fcm-token'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${data['token']}',
          },
          body: jsonEncode({'fcm_token': fcmToken, 'email': user['email']}),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _feedback = 'Error: $e';
      });
    }
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _feedback = 'Please fill in both fields.';
      });
      return;
    }

    final url = Uri.parse('$baseurl/api/login'); // Change to your real API URL

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          _feedback = 'Login successful!';
        });

        if (data.containsKey('token')) {
          var box = Hive.box('authBox');
          await box.put('token', data['token']);
          await box.put('user', data['user']);
        }
        var box = Hive.box('authBox');
        final user = box.get('user');
        print(data['token']);
        final fcmToken = await FirebaseMessaging.instance.getToken();
        print(fcmToken);
        await http.post(
          Uri.parse('$baseurl/api/save-fcm-token'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${data['token']}',
          },
          body: jsonEncode({'fcm_token': fcmToken, 'email': user['email']}),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
        print("Navigating to HomeScreen...");
      } else {
        setState(() {
          _feedback = 'Login failed (${response.statusCode}).';
        });
      }
    } catch (e) {
      setState(() {
        _feedback = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: AnimatedSwitcher(
          duration: Duration(milliseconds: 300),
          child: _showLogin ? buildLogin() : buildRegister(),
        ),
      ),
    );
  }

  // Variable to show API response
  String _feedback = '';

  Widget buildLogin() {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            colors: [
              const Color.fromARGB(255, 70, 46, 37),
              const Color.fromARGB(255, 75, 50, 42),
              const Color.fromARGB(255, 104, 79, 70),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(height: 80),
            Padding(
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
            SizedBox(height: 20),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(60)),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(30),
                  child: Column(
                    children: <Widget>[
                      SizedBox(height: 60),
                      Container(
                        margin: EdgeInsets.all(25),
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
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
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: TextField(
                                controller: _emailController,
                                decoration: InputDecoration(
                                  hintText: "Email",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: TextField(
                                controller: _passwordController,
                                obscureText: true,
                                decoration: InputDecoration(
                                  hintText: "password",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 20),
                      Text(
                        "forgot password ?",
                        style: TextStyle(color: Colors.grey),
                      ),
                      SizedBox(height: 40),
                      GestureDetector(
                        onTap: _login,
                        child: Container(
                          height: 60,
                          margin: EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            color: Color.fromARGB(255, 70, 46, 37),
                          ),
                          child: Center(
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
                      SizedBox(height: 20),
                      Column(
                        children: [
                          Container(
                            padding: EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Color.fromARGB(255, 70, 46, 37),
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
                              child: Text(
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
                      SizedBox(height: 20),
                      Text(_feedback, style: TextStyle(color: Colors.red)),
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

  Widget buildRegister() {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            colors: [
              const Color.fromARGB(255, 70, 46, 37),
              const Color.fromARGB(255, 75, 50, 42),
              const Color.fromARGB(255, 104, 79, 70),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(height: 80),
            Padding(
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
            SizedBox(height: 20),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(60)),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(30),
                  child: Column(
                    children: <Widget>[
                      SizedBox(height: 60),
                      Container(
                        margin: EdgeInsets.all(15),
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
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
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: TextField(
                                controller: _nameController,
                                decoration: InputDecoration(
                                  hintText: "Name",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: TextField(
                                controller: _lastNameController,
                                decoration: InputDecoration(
                                  hintText: "Last Name",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
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
                                    decoration: InputDecoration(
                                      hintText: "Date Of Birth",
                                      hintStyle: TextStyle(color: Colors.grey),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: TextField(
                                controller: _codePostalController,
                                decoration: InputDecoration(
                                  hintText: "Code Postal",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: TextField(
                                controller: _numberController,
                                decoration: InputDecoration(
                                  hintText: "Number",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: TextField(
                                controller: _emailController,
                                decoration: InputDecoration(
                                  hintText: "Email",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: TextField(
                                controller: _passwordController,
                                obscureText: true,
                                decoration: InputDecoration(
                                  hintText: "Password",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: Colors.blueGrey),
                                ),
                              ),
                              child: _isLoadingVilles
                                  ? CircularProgressIndicator()
                                  : DropdownButtonFormField<int>(
                                      decoration: InputDecoration(
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
                      SizedBox(height: 40),
                      GestureDetector(
                        onTap: _register,
                        child: Container(
                          height: 60,
                          margin: EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            color: Color.fromARGB(255, 70, 46, 37),
                          ),
                          child: Center(
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
                      SizedBox(height: 20),
                      Column(
                        children: [
                          Container(
                            padding: EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Color.fromARGB(255, 70, 46, 37),
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
                              child: Text(
                                "you have a account ?,login !",
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 20),
                      Text(_feedback, style: TextStyle(color: Colors.red)),
                      SizedBox(height: 20),
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
