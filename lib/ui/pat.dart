import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'repo.dart';
import 'package:http/http.dart' as http;


class PatLogin extends StatefulWidget {
  const PatLogin({super.key});

  @override
  State<PatLogin> createState() => _PatLoginState();
}

class _PatLoginState extends State<PatLogin> {
  final TextEditingController _controller = TextEditingController();
  bool _remember = false;
  bool _isLoading = false;
  final _storage = const FlutterSecureStorage();
  String? _currentPat; // RAM token

  Future<bool> _checkPat(String pat) async {
    final url = Uri.parse('https://api.github.com/user');
    final response = await http.get(
      url,
      headers: {'Authorization': 'token $pat'},
    );
    return response.statusCode == 200;
  }

  @override
  void initState() {
    super.initState();
    _loadPat();
  }

  void _loadPat() async {
    String? savedPat = await _storage.read(key: 'github_pat');
    if (savedPat != null) {
      bool valid = await _checkPat(savedPat);
      if (valid && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => RepoScreen(pat: savedPat)),
        );
      } else {
        await _storage.delete(key: 'github_pat');
      }
    }
  }

  void _submitPat() async {
    final pat = _controller.text.trim();
    if (pat.isEmpty) {
      _showError("PAT boş olamaz!");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final valid = await _checkPat(pat);
      if (!valid) {
        _showError("PAT geçersiz!");
        return;
      }

      _currentPat = pat; // RAM’de tut

      if (_remember) {
        await _storage.write(key: 'github_pat', value: pat);
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => RepoScreen(pat: _currentPat)),
        );
      }
    } catch (e) {
      _showError("Hata oluştu: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("GitHub PAT Girişi"),
        centerTitle: true,
        elevation: 2,
      ),
      body: Container(
  decoration: const BoxDecoration(
    gradient: LinearGradient(
      colors: [
        Color.fromARGB(255, 42, 29, 180), // neredeyse saf beyaz
        Color.fromARGB(255, 133, 149, 173), // çok hafif gri-mavi
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
  ),
  child: Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Card(
        elevation: 6,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.vpn_key, size: 60, color: Colors.blue),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: "Personal Access Token",
                  prefixIcon: Icon(Icons.key),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Remember token securely"),
                  Switch(
                    value: _remember,
                    onChanged: (v) => setState(() => _remember = v),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _submitPat,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          "Submit",
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
),
    );
  }
}