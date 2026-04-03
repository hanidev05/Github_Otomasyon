import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CreateRepoScreen extends StatefulWidget {
  final String pat;

  const CreateRepoScreen({super.key, required this.pat});

  @override
  State<CreateRepoScreen> createState() => _CreateRepoScreenState();
}

class _CreateRepoScreenState extends State<CreateRepoScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  bool _isPrivate = false;
  bool _isLoading = false;
  String _defaultBranch = "main"; // main / master seçilebilir

  Future<void> _createRepo() async {
    final name = _nameController.text.trim();
    final desc = _descController.text.trim();

    if (name.isEmpty) {
      _showError("Repo adı boş olamaz");
      return;
    }

    setState(() => _isLoading = true);

    final url = Uri.parse("https://api.github.com/user/repos");

    try {
      final response = await http.post(
        url,
        headers: {
          "Authorization": "token ${widget.pat}",
          "Accept": "application/vnd.github+json",
        },
        body: jsonEncode({
          "name": name,
          "description": desc,
          "private": _isPrivate,
          "auto_init": true,
        }),
      );

      if (response.statusCode == 201) {
        // Branch değiştirmek istersek ikinci API call gerekir (opsiyonel)
        Navigator.pop(context, true);
      } else {
        final body = jsonDecode(response.body);
        _showError(body['message'] ?? "Repo oluşturulamadı");
      }
    } catch (e) {
      _showError("Hata: $e");
    }

    if (mounted) setState(() => _isLoading = false);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Create Repository"),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Card(
          elevation: 5,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.create_new_folder,
                    size: 60, color: Colors.blue),

                const SizedBox(height: 20),

                /// Repo Name
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: "Repository Name",
                    prefixIcon: Icon(Icons.folder),
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 15),

                /// Description
                TextField(
                  controller: _descController,
                  decoration: const InputDecoration(
                    labelText: "Description (optional)",
                    prefixIcon: Icon(Icons.description),
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 15),

                /// Private Switch
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Private Repo"),
                    Switch(
                      value: _isPrivate,
                      onChanged: (val) {
                        setState(() => _isPrivate = val);
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 15),

                /// Branch seçimi (UI only)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Default Branch"),
                    DropdownButton<String>(
                      value: _defaultBranch,
                      items: const [
                        DropdownMenuItem(
                            value: "main", child: Text("main")),
                        DropdownMenuItem(
                            value: "master", child: Text("master")),
                      ],
                      onChanged: (val) {
                        setState(() => _defaultBranch = val!);
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 25),

                /// Create Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton.icon(
                          onPressed: _createRepo,
                          icon: const Icon(Icons.add),
                          label: const Text(
                            "Create Repository",
                            style: TextStyle(fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}