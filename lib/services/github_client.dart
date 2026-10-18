import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Reads and writes this app's own GitHub repo — question files in, quiz
/// results out — with a fine-grained token the user pastes in once.
class GitHubClient {
  static const _contents =
      'https://api.github.com/repos/Merthocaoglu/organizer/contents';
  static const _tokenKey = 'github_token';

  // Keystore-backed: shared_preferences would put the token in backups.
  final _storage = const FlutterSecureStorage();

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token.trim());

  /// Raw contents of every .json file in data/questions.
  Future<List<String>> fetchQuestionFiles() async {
    final listing = await _get('data/questions', 'application/vnd.github+json');
    return [
      for (final file in jsonDecode(listing) as List)
        if ((file['name'] as String).endsWith('.json'))
          await _get(file['path'] as String, 'application/vnd.github.raw+json'),
    ];
  }

  /// Commits a new file; fails if [path] already exists.
  Future<void> createFile(String path, String content, String message) async {
    final response = await http.put(
      Uri.parse('$_contents/$path'),
      headers: await _headers('application/vnd.github+json'),
      body: jsonEncode({
        'message': message,
        'content': base64Encode(utf8.encode(content)),
      }),
    );
    if (response.statusCode != 201) {
      throw Exception('GitHub ${response.statusCode} for $path');
    }
  }

  Future<String> _get(String path, String accept) async {
    final response = await http.get(Uri.parse('$_contents/$path'),
        headers: await _headers(accept));
    if (response.statusCode != 200) {
      throw Exception('GitHub ${response.statusCode} for $path');
    }
    return utf8.decode(response.bodyBytes); // Turkish text, whatever the header says
  }

  Future<Map<String, String>> _headers(String accept) async => {
        'Authorization': 'Bearer ${await readToken()}',
        'Accept': accept,
        'X-GitHub-Api-Version': '2022-11-28',
      };
}
