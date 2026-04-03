import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'pat.dart';
import 'create_repo.dart';
import 'repo_screen.dart'; 
import 'dart:async';
 
class Repo {
  final String name;
  bool isPrivate;
  final String owner;
 
  Repo({required this.name, required this.isPrivate, required this.owner});
 
  factory Repo.fromJson(Map<String, dynamic> json) {
    return Repo(
      name: json['name'] ?? 'Unknown',
      isPrivate: json['private'] ?? false,
      owner: json['owner']?['login'] ?? 'Unknown',
    );
  }
}
 
class RepoScreen extends StatefulWidget {
  final String? pat;
  const RepoScreen({super.key, this.pat});
 
  @override
  State<RepoScreen> createState() => _RepoScreenState();
}
 
class _RepoScreenState extends State<RepoScreen> {
  final _storage = const FlutterSecureStorage();
  List<Repo> _repos = [];
  bool _isLoading = true;
 
  @override
  void initState() {
    super.initState();
    _loadRepos();
  }
 
  Future<void> _loadRepos() async {
    setState(() => _isLoading = true);
 
    String? pat = widget.pat ?? await _storage.read(key: 'github_pat');
    if (pat == null) {
      _showError("PAT bulunamadı. Lütfen giriş yapın.");
      setState(() => _isLoading = false);
      return;
    }
 
    final url = Uri.parse(
      'https://api.github.com/user/repos?visibility=all&affiliation=owner,collaborator&per_page=100',
    );
 
    try {
      final response = await http
          .get(url, headers: {'Authorization': 'token $pat'})
          .timeout(const Duration(seconds: 10));
 
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          setState(() {
            _repos = data.map((e) => Repo.fromJson(e)).toList();
            _isLoading = false;
          });
        } else {
          _showError("Beklenmeyen veri formatı.");
          setState(() => _isLoading = false);
        }
      } else if (response.statusCode == 401) {
        _showError("PAT geçersiz veya yetkisiz.");
        setState(() => _isLoading = false);
      } else {
        _showError("Repo yüklenemedi: ${response.statusCode}");
        setState(() => _isLoading = false);
      }
    } catch (e) {
      _showError("Hata oluştu: $e");
      setState(() => _isLoading = false);
    }
  }
 
  Future<void> _deleteToken() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Token Sil"),
        content: const Text(
          "Token'ı cihazdan silmek istediğinize emin misiniz?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("No"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Yes"),
          ),
        ],
      ),
    );
 
    if (confirm == true) {
      await _storage.delete(key: 'github_pat');
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PatLogin()),
        );
      }
    }
  }
 
  void _createRepo() async {
    String? pat = widget.pat ?? await _storage.read(key: 'github_pat');
    if (pat == null) {
      _showError("PAT bulunamadı");
      return;
    }
 
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateRepoScreen(pat: pat)),
    );
 
    if (result == true) {
      _loadRepos();
    }
  }
 
  Future<void> _deleteRepo(String repoName) async {
    String? pat = widget.pat ?? await _storage.read(key: 'github_pat');
    if (pat == null) {
      _showError("PAT bulunamadı");
      return;
    }
 
    bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DeleteRepoDialog(repoName: repoName),
    );
 
    if (confirm != true) return;
 
    final repo = _repos.firstWhere((r) => r.name == repoName);
    final url = Uri.parse(
        "https://api.github.com/repos/${repo.owner}/$repoName");
 
    try {
      final response = await http.delete(
        url,
        headers: {
          "Authorization": "token $pat",
          "Accept": "application/vnd.github+json",
        },
      );
 
      if (response.statusCode == 204) {
        _showError("'$repoName' başarıyla silindi.");
        _loadRepos();
      } else {
        final body = jsonDecode(response.body);
        _showError(body['message'] ?? "Repo silinemedi");
      }
    } catch (e) {
      _showError("Hata: $e");
    }
  }
 
  Future<void> _togglePrivate(Repo repo) async {
    String? pat = widget.pat ?? await _storage.read(key: 'github_pat');
    if (pat == null) {
      _showError("PAT bulunamadı");
      return;
    }
 
    final url = Uri.parse(
        "https://api.github.com/repos/${repo.owner}/${repo.name}");
    final newPrivateValue = !repo.isPrivate;
 
    try {
      final response = await http.patch(
        url,
        headers: {
          "Authorization": "token $pat",
          "Accept": "application/vnd.github+json",
          "Content-Type": "application/json"
        },
        body: jsonEncode({"private": newPrivateValue}),
      );
 
      if (response.statusCode == 200) {
        setState(() {
          repo.isPrivate = newPrivateValue;
        });
        _showError(
            "'${repo.name}' artık ${newPrivateValue ? 'Private' : 'Public'}");
      } else {
        final body = jsonDecode(response.body);
        _showError(body['message'] ?? "Gizlilik değiştirilemedi");
      }
    } catch (e) {
      _showError("Hata: $e");
    }
  }
 
  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }
 
 
  Future<void> _openRepoDetail(Repo repo) async {
    String? pat = widget.pat ?? await _storage.read(key: 'github_pat');
    if (pat == null) {
      _showError("PAT bulunamadı");
      return;
    }
 
  
    List<String> branches = [];
    try {
      final url = Uri.parse(
          'https://api.github.com/repos/${repo.owner}/${repo.name}/branches');
      final response = await http.get(url, headers: {
        'Authorization': 'token $pat',
        'Accept': 'application/vnd.github+json',
      });
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        branches = (data as List).map((e) => e['name'] as String).toList();
      }
    } catch (_) {}
 
    
    if (branches.isEmpty) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RepoDetailScreen(
            repoName: repo.name,
            owner: repo.owner,
            pat: pat,
            initialBranch: 'main',
          ),
        ),
      );
      return;
    }
 
    
    if (branches.length == 1) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RepoDetailScreen(
            repoName: repo.name,
            owner: repo.owner,
            pat: pat,
            initialBranch: branches.first,
          ),
        ),
      );
      return;
    }
 
    
    if (!mounted) return;
    final selectedBranch = await showDialog<String>(
      context: context,
      builder: (context) => _BranchPickerDialog(
        repoName: repo.name,
        branches: branches,
      ),
    );
 
    if (selectedBranch == null) return; 
 
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RepoDetailScreen(
          repoName: repo.name,
          owner: repo.owner,
          pat: pat,
          initialBranch: selectedBranch,
        ),
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("GitHub Repositories"),
        centerTitle: true,
        elevation: 2,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadRepos),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createRepo,
            tooltip: "Create Repo",
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: _deleteToken,
            tooltip: "Delete Token",
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _repos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.folder_off, size: 60, color: Colors.grey),
                      SizedBox(height: 10),
                      Text("Repo bulunamadı",
                          style: TextStyle(fontSize: 18)),
                      SizedBox(height: 5),
                      Text(
                        "Token izinlerini kontrol et",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _repos.length,
                  itemBuilder: (context, index) {
                    final repo = _repos[index];
                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        onTap: () => _openRepoDetail(repo), // ✅ güncellendi
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child:
                              const Icon(Icons.folder, color: Colors.blue),
                        ),
                        title: Text(
                          repo.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () => _togglePrivate(repo),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: repo.isPrivate
                                      ? Colors.red.shade100
                                      : Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  repo.isPrivate ? "Private" : "Public",
                                  style: TextStyle(
                                    color: repo.isPrivate
                                        ? Colors.red
                                        : Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete,
                                  color: Colors.red),
                              tooltip: "Delete Repo",
                              onPressed: () => _deleteRepo(repo.name),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
 

class _BranchPickerDialog extends StatelessWidget {
  final String repoName;
  final List<String> branches;
 
  const _BranchPickerDialog({
    required this.repoName,
    required this.branches,
  });
 
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Branch Seç"),
      content: SizedBox(
        width: double.minPositive,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: branches.length,
          itemBuilder: (context, index) {
            final branch = branches[index];
            return ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: Text(branch),
              onTap: () => Navigator.pop(context, branch),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text("İptal"),
        ),
      ],
    );
  }
}
 

class _DeleteRepoDialog extends StatefulWidget {
  final String repoName;
  const _DeleteRepoDialog({super.key, required this.repoName});
 
  @override
  State<_DeleteRepoDialog> createState() => _DeleteRepoDialogState();
}
 
class _DeleteRepoDialogState extends State<_DeleteRepoDialog> {
  bool yesEnabled = false;
  Timer? timer;
 
  @override
  void initState() {
    super.initState();
    timer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => yesEnabled = true);
    });
  }
 
  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }
 
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Repo Sil"),
      content: Text(
        "'${widget.repoName}' isimli repoyu silmek istediğinize emin misiniz?",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("No"),
        ),
        TextButton(
          onPressed: yesEnabled ? () => Navigator.pop(context, true) : null,
          child:
              yesEnabled ? const Text("Yes") : const Text("Wait 5s..."),
        ),
      ],
    );
  }
}