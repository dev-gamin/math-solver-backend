import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_math_fork/flutter_math.dart';  // For LaTeX rendering
import 'package:fl_chart/fl_chart.dart';  // For graphing
import 'package:speech_to_text/speech_to_text.dart' as stt;  // For voice input
import 'package:retry/retry.dart';  // For Render wake retries

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Math Solver',  // App store-friendly title
      theme: ThemeData(primarySwatch: Colors.blue, brightness: Brightness.light),
      home: const MathSolverScreen(),
    );
  }
}

class MathSolverScreen extends StatefulWidget {
  const MathSolverScreen({super.key});

  @override
  State<MathSolverScreen> createState() => _MathSolverScreenState();
}

class _MathSolverScreenState extends State<MathSolverScreen> {
  final String backendUrl = 'https://math-solver-backend.onrender.com';  // Replace with your Render URL
  List<String> equations = [];
  String solution = '';
  Map<String, dynamic> solveResult = {};  // For graphing and steps
  stt.SpeechToText speech = stt.SpeechToText();  // Voice init
  bool isListening = false;
  bool isLoading = false;  // For loading indicators

  int solveCount = 0;  // Future: Freemium limit (integrate Firebase for persistence)

  Future<void> pickAndRecognize(ImageSource source) async {
    setState(() => isLoading = true);
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source);
      if (pickedFile == null) return;

      var request = http.MultipartRequest('POST', Uri.parse('$backendUrl/recognize'));
      request.files.add(await http.MultipartFile.fromPath('image', pickedFile.path));
      var response = await retry(() => request.send().timeout(const Duration(seconds: 30)), maxAttempts: 3);
      var respStr = await response.stream.bytesToString();
      var jsonResp = jsonDecode(respStr);

      if (jsonResp.containsKey('equations')) {
        setState(() {
          equations = List<String>.from(jsonResp['equations']);
          solution = '';
          solveResult = {};
        });
        _showSnack('Equations detected! Tap to solve.');
      } else {
        _showSnack('Error: ${jsonResp['error']}');
      }
    } catch (e) {
      _showSnack('Image process failed: $e. Check connection/photo.');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> listenForEquation() async {
    if (!isListening) {
      bool available = await speech.initialize();
      if (available) {
        setState(() => isListening = true);
        speech.listen(onResult: (result) {
          if (result.finalResult) {
            setState(() => isListening = false);
            solveEquation(result.recognizedWords);
          }
        });
      } else {
        _showSnack('Voice unavailable. Check permissions.');
      }
    } else {
      setState(() => isListening = false);
      speech.stop();
    }
  }

  Future<void> solveEquation(String eq) async {
    if (solveCount >= 5) {
      _showSnack('Daily limit reached. Upgrade to premium!');
      return;
    }

    setState(() => isLoading = true);
    try {
      var response = await retry(() => http.post(
        Uri.parse('$backendUrl/solve'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'equation': eq}),
      ).timeout(const Duration(seconds: 30)), maxAttempts: 3);
      var jsonResp = jsonDecode(response.body);
      if (jsonResp.containsKey('error')) {
        _showSnack('Solve error: ${jsonResp['error']}');
      } else {
        setState(() {
          solution = 'Solutions: ${jsonResp['solutions'].join(', ')}\nSteps:\n${jsonResp['steps'].join('\n')}';
          solveResult = jsonResp;
        });
        solveCount++;
        _showSnack('Solved! Check graph if applicable.');
      }
    } catch (e) {
      _showSnack('Solve failed: $e. Ensure backend active.');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Widget buildGraph() {
    if (solveResult.isEmpty || solveResult['solutions'].isEmpty) return const SizedBox.shrink();
    List<FlSpot> spots = [];
    List<double> sols = solveResult['solutions'].map((s) => double.tryParse(s.toString()) ?? 0).toList();
    double mid = sols.reduce((a, b) => a + b) / sols.length;  // Midpoint for range
    if (sols.length == 2) {  // Assume quadratic, dummy parabola y=(x-mid)^2
      for (double x = mid - 5; x <= mid + 5; x += 0.5) {
        spots.add(FlSpot(x, (x - mid) * (x - mid)));
      }
    } else {  // Linear/default, y=x line
      for (double x = mid - 5; x <= mid + 5; x += 1) {
        spots.add(FlSpot(x, x));
      }
    }
    return Container(
      height: 200,
      padding: const EdgeInsets.all(8),
      child: LineChart(
        LineChartData(
          lineBarsData: [LineChartBarData(spots: spots, isCurved: sols.length == 2, color: Colors.blue)],
          titlesData: const FlTitlesData(show: true),
        ),
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Math Solver')),
      body: Stack(
        children: [
          Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Tip: Clear photos for best results. Supports handwritten/printed.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(onPressed: () => pickAndRecognize(ImageSource.camera), child: const Text('Camera')),
                  const SizedBox(width: 10),
                  ElevatedButton(onPressed: () => pickAndRecognize(ImageSource.gallery), child: const Text('Upload')),
                  const SizedBox(width: 10),
                  ElevatedButton(onPressed: listenForEquation, child: Text(isListening ? 'Stop Voice' : 'Voice Input')),
                ],
              ),
              if (equations.isNotEmpty)
                Expanded(
                  child: ListView.builder(
                    itemCount: equations.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Math.tex(equations[index]),
                        onTap: () => solveEquation(equations[index]),
                      );
                    },
                  ),
                ),
              if (solution.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Math.tex(solution.replaceAll('\n', ' \\\\ ')),
                      buildGraph(),
                    ],
                  ),
                ),
            ],
          ),
          if (isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}