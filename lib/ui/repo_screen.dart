import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:process_run/shell.dart';

class FileNode {
  final String name;
  final String path;
  bool isFile;
  bool isGitTracked;
  bool isSelected;
  List<FileNode>? children;

  FileNode({
    required this.name,
    required this.path,
    required this.isFile,
    this.isGitTracked = false,
    this.isSelected = false,
    this.children,
  });
}

class RepoDetailScreen extends StatefulWidget {
  final String repoName;
  final String owner;
  final String? pat;
  final String initialBranch; 

  const RepoDetailScreen({
    super.key,
    required this.repoName,
    required this.owner,
    this.pat,
    this.initialBranch = 'main', 
  });

  @override
  State<RepoDetailScreen> createState() => _RepoDetailScreenState();
}

class _RepoDetailScreenState extends State<RepoDetailScreen> {
  List<FileNode> remoteTree = [];
  List<FileNode> localTree = [];
  List<String> logs = [];
  bool isLogOpen = true;
  String? selectedLocalPath;
  String? remoteUrl;
  String selectedBranch = 'main';
  final ScrollController _scrollController = ScrollController();
  final _storage = const FlutterSecureStorage();
  List<String> availableBranches = [];

  @override
  void initState() {
    super.initState();
    selectedBranch = widget.initialBranch; 
    _loadBranches().then((_) => _loadRemoteFiles());
  }

  void addLog(String text) {
    if (!mounted) return;
    setState(() {
      logs.add("${DateTime.now().toIso8601String()} - $text");
      if (logs.length > 2000) logs.removeAt(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _loadRemoteFiles([String path = '']) async {
    String? pat = widget.pat ?? await _storage.read(key: 'github_pat');
    if (pat == null) {
      addLog("PAT bulunamadı.");
      return;
    }

    final url = Uri.parse(
        'https://api.github.com/repos/${widget.owner}/${widget.repoName}/contents/$path?ref=$selectedBranch');
    remoteUrl = 'https://github.com/${widget.owner}/${widget.repoName}.git';

    try {
      final response = await http.get(url, headers: {
        'Authorization': 'token $pat',
        'Accept': 'application/vnd.github+json',
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<FileNode> nodes = (data as List)
            .map((e) => FileNode(
                  name: e['name'],
                  path: e['path'],
                  isFile: e['type'] == 'file',
                  isGitTracked: true,
                  children: e['type'] == 'dir' ? [] : null,
                ))
            .toList();

        if (!mounted) return;
        if (path.isEmpty) {
          setState(() => remoteTree = nodes);
        } else {
          _insertChildren(remoteTree, path, nodes);
        }
        addLog("Remote dosyalar yüklendi: $path");
      } else {
        addLog("Remote yüklenemedi (${response.statusCode})");
      }
    } catch (e) {
      addLog("Remote hata: $e");
    }
  }

  void _insertChildren(List<FileNode> nodes, String parentPath, List<FileNode> children) {
    for (var node in nodes) {
      if (!node.isFile && node.path == parentPath) {
        node.children = children;
        if (mounted) setState(() {});
        return;
      } else if (!node.isFile && node.children != null) {
        _insertChildren(node.children!, parentPath, children);
      }
    }
  }

  Future<void> _loadBranches() async {
    String? pat = widget.pat ?? await _storage.read(key: 'github_pat');
    if (pat == null) return;

    List<String> localBranches = [];
    if (selectedLocalPath != null) {
      var shell = Shell(workingDirectory: selectedLocalPath!);
      try {
        final result = await shell.run('git branch --format="%(refname:short)"');
        localBranches = result.outLines.map((e) => e.trim()).toList();
      } catch (_) {}
    }

    final url = Uri.parse(
        'https://api.github.com/repos/${widget.owner}/${widget.repoName}/branches');
    try {
      final response = await http.get(url, headers: {
        'Authorization': 'token $pat',
        'Accept': 'application/vnd.github+json',
      });
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<String> remoteBranches =
            (data as List).map((e) => e['name'] as String).toList();

        if (!mounted) return;
        Set<String> allBranches = {...remoteBranches, ...localBranches};
        setState(() {
          availableBranches = allBranches.toList();
          
          if (!allBranches.contains(selectedBranch)) {
            if (allBranches.contains('main')) {
              selectedBranch = 'main';
            } else if (allBranches.contains('master')) {
              selectedBranch = 'master';
            } else if (allBranches.isNotEmpty) {
              selectedBranch = allBranches.first;
            }
          }
        });
      }
    } catch (e) {
      addLog("Branch yükleme hatası: $e");
    }
  }

  void onBranchChanged(String? branch) {
    if (branch == null) return;
    setState(() => selectedBranch = branch);
    _loadRemoteFiles();
  }

  Future<void> pickLocalFolder() async {
    String? path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;
    if (!mounted) return;
    setState(() {
      selectedLocalPath = path;
      localTree = _loadTopLevel(Directory(path));
    });
    await _ensureGitInitialized();
    await _updateGitStatus(localTree);
    await _loadBranches();
    addLog("Local folder selected: $selectedLocalPath");
  }

  List<FileNode> _loadTopLevel(Directory dir) {
    List<FileNode> nodes = [];
    final entities = dir.listSync();
    for (var entity in entities) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name == ".git") continue;
      if (entity is File) {
        nodes.add(FileNode(name: name, path: entity.path, isFile: true));
      } else if (entity is Directory) {
        nodes.add(FileNode(name: name, path: entity.path, isFile: false, children: []));
      }
    }
    return nodes;
  }

  Future<void> _loadChildren(FileNode node) async {
    if (node.children != null && node.children!.isNotEmpty) return;
    setState(() { node.children = []; });

    List<FileNode> children = [];
    try {
      final entities = Directory(node.path).listSync();
      for (var entity in entities) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name == ".git") continue;
        if (entity is File) {
          bool tracked = await _checkGitTracked(entity.path);
          children.add(FileNode(name: name, path: entity.path, isFile: true, isGitTracked: tracked));
        } else if (entity is Directory) {
          children.add(FileNode(name: name, path: entity.path, isFile: false, children: []));
        }
      }
    } catch (e) {
      addLog("Folder load error: $e");
    }

    if (!mounted) return;
    setState(() => node.children = children);
  }

  Future<void> _ensureGitInitialized() async {
    if (selectedLocalPath == null) return;
    var shell = Shell(workingDirectory: selectedLocalPath!);

    try {
      await shell.run('git rev-parse --is-inside-work-tree');
    } catch (_) {
      addLog("Git repository bulunamadı, 'git init' çalıştırılıyor...");
      try {
        await shell.run('git init');
        addLog("Git repository başlatıldı!");
      } catch (e) {
        addLog("Git init hatası: $e");
      }
    }

    if (remoteUrl != null) {
      try { await shell.run('git remote remove origin'); } catch (_) {}
      try {
        await shell.run('git remote add origin $remoteUrl');
        addLog("Remote repository eklendi: $remoteUrl");
      } catch (e) {
        addLog("Remote ekleme hatası: $e");
      }
    }
  }

  Future<bool> _checkGitTracked(String filePath) async {
    if (selectedLocalPath == null) return false;
    try {
      var shell = Shell(workingDirectory: selectedLocalPath!);
      String relativePath = filePath.replaceAll("\\", "/");
      if (relativePath.startsWith(selectedLocalPath!.replaceAll("\\", "/"))) {
        relativePath = relativePath.substring(selectedLocalPath!.length + 1);
      }
      await shell.run('git ls-files --error-unmatch "$relativePath"');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _updateGitStatus(List<FileNode> nodes) async {
    for (var node in nodes) {
      if (node.isFile) {
        node.isGitTracked = await _checkGitTracked(node.path);
      }
      if (node.children != null) await _updateGitStatus(node.children!);
    }
    if (mounted) setState(() {});
  }

  void toggleSelection(FileNode node) {
    if (!mounted) return;
    setState(() => node.isSelected = !node.isSelected);
  }

  Widget buildNode(FileNode node, {bool isRemote = false}) {
    Widget title = Row(
      children: [
        Text(node.name),
        const SizedBox(width: 6),
        if (node.isFile && !isRemote)
          Row(
            children: [
              Checkbox(value: node.isSelected, onChanged: (_) => toggleSelection(node)),
              if (node.isGitTracked)
                const Text("G", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
      ],
    );

    if (node.isFile) {
      return ListTile(
        title: title,
        leading: Icon(isRemote ? Icons.insert_drive_file : Icons.insert_drive_file_outlined, size: 18),
      );
    } else {
      return ExpansionTile(
        leading: const Icon(Icons.folder),
        title: title,
        onExpansionChanged: (expanded) {
          if (expanded && !isRemote) _loadChildren(node);
        },
        children: node.children == null || node.children!.isEmpty
            ? [const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2))]
            : node.children!.map((e) => buildNode(e, isRemote: isRemote)).toList(),
      );
    }
  }

  void gitAdd(FileNode node) async {
    if (!node.isFile || selectedLocalPath == null) return;
    var shell = Shell(workingDirectory: selectedLocalPath!);
    try {
      await shell.run('git add "${node.path.replaceAll("\\", "/")}"');
      node.isGitTracked = true;
      addLog("${node.name} git'e eklendi");
    } catch (e) {
      addLog("Git Add Hatası: $e");
    }
    if (mounted) setState(() {});
  }

  void gitReset(FileNode node) async {
    if (!node.isFile || selectedLocalPath == null) return;
    var shell = Shell(workingDirectory: selectedLocalPath!);
    try {
      await shell.run('git reset "${node.path.replaceAll("\\", "/")}"');
      node.isGitTracked = false;
      addLog("${node.name} git'den çıkarıldı");
    } catch (e) {
      addLog("Git Reset Hatası: $e");
    }
    if (mounted) setState(() {});
  }

  void commitSelected() async {
    List<FileNode> selected = _collectSelected(localTree).where((f) => f.isGitTracked).toList();
    if (selected.isEmpty) {
      addLog("Hiç gitlenmiş dosya seçilmedi");
      return;
    }

    String? message = await showDialog<String>(
      context: context,
      builder: (context) {
        TextEditingController ctrl = TextEditingController();
        return AlertDialog(
          title: const Text("Commit Message"),
          content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: "Enter commit message")),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text("Commit")),
          ],
        );
      },
    );

    if (message != null && message.isNotEmpty && selectedLocalPath != null) {
      var shell = Shell(workingDirectory: selectedLocalPath!);
      try {
        await shell.run('git commit -m "$message"');
        addLog("Commit yapıldı: $message");
      } catch (e) {
        addLog("Commit Hatası: $e");
      }
    }
  }

 
  Future<void> pushToRemote() async {
    if (selectedLocalPath == null) return;

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Push Confirmation"),
        content: const Text("Mevcut reponuzdaki yapı üzerine yazılacak. Devam edilsin mi?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes")),
        ],
      ),
    );

    if (confirm != true) return;

    var shell = Shell(workingDirectory: selectedLocalPath!);

    try {
    
      final branchResult = await shell.run('git rev-parse --abbrev-ref HEAD');
      final localBranch = branchResult.outLines.first.trim();
      addLog("Local branch: $localBranch → Remote branch: $selectedBranch");

    
      bool remoteHasBranch = false;
      try {
        await shell.run('git ls-remote --exit-code --heads origin $selectedBranch');
        remoteHasBranch = true;
      } catch (_) {
        remoteHasBranch = false;
      }
      addLog("Remote branch mevcut mu: $remoteHasBranch");

    
      if (remoteHasBranch) {
        try {
          await shell.run('git pull --rebase origin $selectedBranch');
          addLog("Pull/rebase başarılı");
        } catch (e) {
          addLog("Pull/rebase çakışması var, force push ile devam ediliyor...");
        }
      }

     
      await shell.run('git push -u origin $localBranch:$selectedBranch --force');
      addLog("✅ Push başarılı! ($localBranch → $selectedBranch)");

      
      await _loadRemoteFiles();
    } catch (e) {
      addLog("❌ Push hatası: $e");
    }
  }

  List<FileNode> _collectSelected(List<FileNode> nodes) {
    List<FileNode> selected = [];
    for (var node in nodes) {
      if (node.isFile && node.isSelected) selected.add(node);
      if (node.children != null) selected.addAll(_collectSelected(node.children!));
    }
    return selected;
  }

  void clearLog() {
    if (!mounted) return;
    setState(() => logs.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Repo: ${widget.repoName}"),
        actions: [
          if (availableBranches.isNotEmpty)
            DropdownButton<String>(
              value: selectedBranch,
              dropdownColor: Colors.grey[200],
              onChanged: onBranchChanged,
              items: availableBranches.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
            ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
              child: remoteTree.isEmpty
                  ? const Center(child: Text("No remote files"))
                  : ListView(children: remoteTree.map((e) => buildNode(e, isRemote: true)).toList()),
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: pickLocalFolder,
                          icon: const Icon(Icons.folder_open),
                          label: const Text("Select Local Folder"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: ElevatedButton(onPressed: commitSelected, child: const Text("Commit Selected"))),
                      const SizedBox(width: 8),
                      Expanded(child: ElevatedButton(onPressed: pushToRemote, child: const Text("Push to Remote"))),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                    child: selectedLocalPath == null
                        ? const Center(child: Text("No folder selected"))
                        : ListView(
                            children: localTree.map((e) {
                              return Row(
                                children: [
                                  Expanded(child: buildNode(e, isRemote: false)),
                                  if (e.isFile)
                                    Row(
                                      children: [
                                        IconButton(icon: const Icon(Icons.add), onPressed: () => gitAdd(e)),
                                        IconButton(icon: const Icon(Icons.remove), onPressed: () => gitReset(e)),
                                      ],
                                    )
                                ],
                              );
                            }).toList(),
                          ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: isLogOpen ? 300 : 60,
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(isLogOpen ? Icons.arrow_forward_ios : Icons.arrow_back_ios, color: Colors.white),
                      onPressed: () {
                        if (!mounted) return;
                        setState(() => isLogOpen = !isLogOpen);
                      },
                    ),
                    if (isLogOpen)
                      TextButton(onPressed: clearLog, child: const Text("Clear", style: TextStyle(color: Colors.red))),
                  ],
                ),
                if (isLogOpen)
                  Expanded(
                    child: ListView(
                      controller: _scrollController,
                      children: logs.map((e) => Text(e, style: const TextStyle(color: Colors.white))).toList(),
                    ),
                  )
              ],
            ),
          )
        ],
      ),
    );
  }
}
