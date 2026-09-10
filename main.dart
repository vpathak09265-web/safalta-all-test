import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String baseUrl = 'http://10.0.2.2:8000';

void main() => runApp(const ExamMockApp());

class ExamMockApp extends StatelessWidget {
  const ExamMockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Exam Mock Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool uploading = false;
  String? message;

  Future<void> uploadPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.single.path == null) return;

    setState(() {
      uploading = true;
      message = 'PDF upload हो रही है...';
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/v1/tests/upload'),
      );
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        result.files.single.path!,
      ));

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        throw Exception(body);
      }

      final data = jsonDecode(body);
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProcessingPage(testId: data['test_id']),
        ),
      );
    } catch (e) {
      setState(() => message = 'Error: $e');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exam Mock Test')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.picture_as_pdf, size: 80),
              const SizedBox(height: 20),
              const Text(
                'Answer Key से Mock Test बनाएं',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'PDF upload करें। Gemini questions और answers को process करेगा।',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: uploading ? null : uploadPdf,
                icon: const Icon(Icons.upload_file),
                label: Text(uploading ? 'Uploading...' : 'PDF Upload करें'),
              ),
              if (message != null) ...[
                const SizedBox(height: 15),
                Text(message!, textAlign: TextAlign.center),
              ]
            ],
          ),
        ),
      ),
    );
  }
}

class ProcessingPage extends StatefulWidget {
  final String testId;
  const ProcessingPage({super.key, required this.testId});

  @override
  State<ProcessingPage> createState() => _ProcessingPageState();
}

class _ProcessingPageState extends State<ProcessingPage> {
  Timer? timer;
  String status = 'PROCESSING';
  String? error;

  @override
  void initState() {
    super.initState();
    checkStatus();
    timer = Timer.periodic(const Duration(seconds: 2), (_) => checkStatus());
  }

  Future<void> checkStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/v1/tests/${widget.testId}/status'),
      );
      if (response.statusCode != 200) throw Exception(response.body);

      final data = jsonDecode(response.body);
      if (!mounted) return;

      setState(() {
        status = data['status'];
        error = data['error'];
      });

      if (status == 'READY') {
        timer?.cancel();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TestPage(testId: widget.testId),
          ),
        );
      } else if (status == 'FAILED') {
        timer?.cancel();
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test तैयार हो रहा है')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: status == 'FAILED'
              ? Text('Processing failed:\n$error')
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    Text('Status: $status'),
                    const SizedBox(height: 10),
                    const Text(
                      'Gemini PDF से questions निकाल रहा है। कृपया प्रतीक्षा करें।',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class TestPage extends StatefulWidget {
  final String testId;
  const TestPage({super.key, required this.testId});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  Map<String, dynamic>? test;
  int index = 0;
  int seconds = 3600;
  Timer? timer;
  final Map<String, String> answers = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadTest();
  }

  Future<void> loadTest() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/v1/tests/${widget.testId}/start'),
    );
    if (response.statusCode != 200) {
      throw Exception(response.body);
    }
    if (!mounted) return;
    setState(() {
      test = jsonDecode(response.body);
      loading = false;
    });
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (seconds > 0) {
        setState(() => seconds--);
      } else {
        submit();
      }
    });
  }

  String get timeText {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> submit() async {
    timer?.cancel();
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/tests/${widget.testId}/submit'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'answers': answers,
        'time_spent_seconds': 3600 - seconds,
      }),
    );

    if (response.statusCode != 200) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response.body)),
        );
      }
      return;
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultPage(result: jsonDecode(response.body)),
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final questions = test!['questions'] as List;
    final q = questions[index];
    final qNo = q['q_no'].toString();

    return Scaffold(
      appBar: AppBar(
        title: Text(test!['title'] ?? 'Mock Test'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                timeText,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            LinearProgressIndicator(value: (index + 1) / questions.length),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'प्रश्न ${index + 1} / ${questions.length}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 15),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                q['question_text'],
                style: const TextStyle(fontSize: 19),
              ),
            ),
            const SizedBox(height: 20),
            ...List<String>.from(q['options']).map((option) {
              final letter = option.trim().substring(0, 1).toUpperCase();
              return Card(
                child: RadioListTile<String>(
                  value: letter,
                  groupValue: answers[qNo],
                  title: Text(option),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => answers[qNo] = value);
                    }
                  },
                ),
              );
            }),
            const Spacer(),
            Row(
              children: [
                if (index > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => index--),
                      child: const Text('पिछला'),
                    ),
                  ),
                if (index > 0) const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: index == questions.length - 1
                        ? submit
                        : () => setState(() => index++),
                    child: Text(
                      index == questions.length - 1 ? 'टेस्ट जमा करें' : 'अगला',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ResultPage extends StatelessWidget {
  final Map<String, dynamic> result;
  const ResultPage({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final score = result['scorecard'];
    final breakdown = result['breakdown'] as List;

    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('आपका Score', style: TextStyle(fontSize: 18)),
                  const SizedBox(height: 8),
                  Text(
                    '${score['total_score']} / ${score['maximum_score']}',
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text('Accuracy: ${score['accuracy_percentage']}%'),
                  Text('सही: ${score['correct']}'),
                  Text('गलत: ${score['incorrect']}'),
                  Text('छोड़े: ${score['unattempted']}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),
          const Text(
            'Question Review',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          ...breakdown.map((q) {
            final status = q['status'];
            return Card(
              child: ListTile(
                leading: Icon(
                  status == 'CORRECT'
                      ? Icons.check_circle
                      : status == 'INCORRECT'
                          ? Icons.cancel
                          : Icons.remove_circle_outline,
                ),
                title: Text('Question ${q['q_no']} — $status'),
                subtitle: Text(
                  'आपका उत्तर: ${q['user_answer'] ?? '-'}\n'
                  'सही उत्तर: ${q['correct_answer'] ?? '-'}',
                ),
              ),
            );
          }),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            child: const Text('नया टेस्ट बनाएं'),
          ),
        ],
      ),
    );
  }
}
