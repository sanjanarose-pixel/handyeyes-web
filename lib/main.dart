import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;

List<CameraDescription> _cameras = const [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const HandyEyesApp());
}

class HandyEyesApp extends StatelessWidget {
  const HandyEyesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HandyEyes',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        appBarTheme: const AppBarTheme(scrolledUnderElevation: 0),
      ),
      debugShowCheckedModeBanner: false,
      home: const DetectionScreen(),
    );
  }
}

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  // Paste your OpenAI API key here for hackathon/demo use.
  // Example: 'sk-...'
  // In production, use a backend proxy instead of embedding a key in app.
  static const String _openAiApiKey = 'PASTE_OPENAI_API_KEY_HERE';
  static const String _openAiModel = 'gpt-4.1-mini';
  static const bool _forceLocalMode = false;

  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final ImageLabeler _labeler = ImageLabeler(
    options: ImageLabelerOptions(confidenceThreshold: 0.55),
  );

  CameraController? _cameraController;
  String _status = 'Initializing camera...';
  bool _isDetecting = false;
  bool _isProcessingFrame = false;
  bool _isCloudMode = false;
  DateTime _lastProcessTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSpeechTime = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastSpokenLabel = '';
  String _currentStableLabel = '';
  int _stableLabelCount = 0;

  static const Duration _frameInterval = Duration(milliseconds: 350);
  static const Duration _speechCooldown = Duration(milliseconds: 2400);
  static const Duration _sameLabelRepeatCooldown = Duration(seconds: 7);
  static const Duration _cloudFrameInterval = Duration(seconds: 2);
  static const double _allowlistBypassConfidence = 0.9;
  static const double _defaultCloudConfidence = 0.8;

  static const Set<String> _priorityObjects = {
    'table',
    'paper',
    'pen',
    'mobile phone',
    'heart',
    'bracelet',
    'necklace',
    'green fan',
    'water bottle',
    'poster',
    'red bull can',
    'charger cable',
    'black headphones',
    'laptop',
    'hand',
    'chair',
    'person',
  };

  static const Set<String> _genericLabels = {
    'room',
    'indoor',
    'interior',
    'furniture',
    'home',
    'tableware',
    'product',
    'material',
    'design',
    'toy',
    'musical instrument',
    'instrument',
    'wing',
    'bird',
    'pool',
    'vehicle',
    'car',
    'transport',
    'wheel',
    'machine',
    'electronics',
    'technology',
    'tool',
    'shape',
    'pattern',
    'cool',
    'nice',
    'beautiful',
    'awesome',
    'good',
    'great',
    'amazing',
    'space',
    'galaxy',
    'universe',
    'cosmos',
  };

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _configureTts();
    await _setupVoiceCommands();
    await _setupCamera();
    if (mounted && !_isDetecting) {
      await _startDetection(announceStart: false);
    }
  }

  Future<void> _configureTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  Future<void> _setupCamera() async {
    if (_cameras.isEmpty) {
      setState(() => _status = 'No camera found on this device.');
      return;
    }

    final backCamera = _cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );

    final controller = CameraController(
      backCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _status = 'Camera ready.';
      });
    } catch (e) {
      await controller.dispose();
      if (mounted) {
        setState(() => _status = 'Camera initialization failed: $e');
      }
    }
  }

  Future<void> _setupVoiceCommands() async {
    final available = await _speech.initialize();
    if (!available) return;

    await _speak('Welcome to HandyEyes.');
  }

  Future<void> _toggleDetection() async {
    if (_isDetecting) {
      await _stopDetection();
      return;
    }
    await _startDetection();
  }

  Future<void> _startDetection({bool announceStart = true}) async {
    final controller = _cameraController;
    if (controller == null) return;

    _isCloudMode = !_forceLocalMode && _openAiApiKey.startsWith('sk-');
    setState(() {
      _isDetecting = true;
      _status = _isCloudMode
          ? 'Detecting with OpenAI vision...'
          : 'Detecting with image labeling...';
    });
    if (announceStart) {
      await _speak('Detection started.');
    }

    if (_isCloudMode) {
      _runCloudDetectionLoop();
      return;
    }

    await controller.startImageStream((image) async {
      if (!_isDetecting || _isProcessingFrame) return;
      if (DateTime.now().difference(_lastProcessTime) < _frameInterval) return;

      _isProcessingFrame = true;
      _lastProcessTime = DateTime.now();
      try {
        final inputImage = _toInputImage(image, controller.description);
        if (inputImage == null) return;
        final labels = await _labeler.processImage(inputImage);
        await _handleLabels(labels);
      } catch (e) {
        if (mounted) {
          setState(() => _status = 'Detection error: $e');
        }
      } finally {
        _isProcessingFrame = false;
      }
    });
  }

  Future<void> _runCloudDetectionLoop() async {
    final controller = _cameraController;
    if (controller == null) return;

    while (_isDetecting && _isCloudMode) {
      try {
        final shot = await controller.takePicture();
        final bytes = await File(shot.path).readAsBytes();
        final cloudLabel = await _analyzeImageWithOpenAi(bytes);
        final localCandidate = await _bestLocalLabelFromFile(shot.path);
        final finalLabel = _resolveBestLabel(
          cloudLabel: cloudLabel,
          localLabel: localCandidate?.$1,
          localConfidence: localCandidate?.$2 ?? 0,
        );

        if (finalLabel != null && finalLabel.isNotEmpty) {
          final cloudConfidence =
              localCandidate != null && finalLabel == localCandidate.$1
              ? localCandidate.$2
              : _defaultCloudConfidence;
          await _handleCloudLabel(
            finalLabel,
            confidence: cloudConfidence,
            source: localCandidate != null && finalLabel == localCandidate.$1
                ? 'Local check'
                : 'OpenAI',
          );
        } else if (mounted) {
          setState(
            () => _status =
                'OpenAI unsure. Move closer, center object, add light.',
          );
        }
      } catch (e) {
        if (mounted) {
          setState(
            () => _status = 'Cloud error. Switching to local detection.',
          );
        }
        _isCloudMode = false;
        if (_isDetecting) {
          await _startLocalStreamAfterCloudFailure();
        }
        return;
      }
      await Future.delayed(_cloudFrameInterval);
    }
  }

  Future<void> _startLocalStreamAfterCloudFailure() async {
    final controller = _cameraController;
    if (controller == null || !_isDetecting) return;
    setState(() => _status = 'Detecting with image labeling...');

    await controller.startImageStream((image) async {
      if (!_isDetecting || _isProcessingFrame) return;
      if (DateTime.now().difference(_lastProcessTime) < _frameInterval) return;

      _isProcessingFrame = true;
      _lastProcessTime = DateTime.now();
      try {
        final inputImage = _toInputImage(image, controller.description);
        if (inputImage == null) return;
        final labels = await _labeler.processImage(inputImage);
        await _handleLabels(labels);
      } catch (e) {
        if (mounted) {
          setState(() => _status = 'Detection error: $e');
        }
      } finally {
        _isProcessingFrame = false;
      }
    });
  }

  Future<void> _stopDetection() async {
    final controller = _cameraController;
    if (controller == null || !_isDetecting) return;
    if (!_isCloudMode) {
      await controller.stopImageStream();
    }
    await _tts.stop();
    if (mounted) {
      setState(() {
        _isDetecting = false;
        _status = 'Detection stopped.';
      });
    }
    _currentStableLabel = '';
    _stableLabelCount = 0;
  }

  Future<void> _handleCloudLabel(
    String rawLabel, {
    required double confidence,
    String source = 'OpenAI',
  }) async {
    final label = _normalizeLabel(rawLabel);
    if (label.isEmpty || _isIgnoredLabel(label)) return;

    final confidencePct = (confidence * 100).clamp(0, 100).toStringAsFixed(0);
    final summary =
        'There is a $confidencePct percent chance that this is a $label';
    if (mounted) {
      setState(() => _status = '$summary ($source)');
    }

    if (label == _currentStableLabel) {
      _stableLabelCount += 1;
    } else {
      _currentStableLabel = label;
      _stableLabelCount = 1;
    }

    final canSpeak =
        DateTime.now().difference(_lastSpeechTime) > _speechCooldown;
    final changed = label != _lastSpokenLabel;
    final sameLabelDelayPassed =
        DateTime.now().difference(_lastSpeechTime) > _sameLabelRepeatCooldown;
    final shouldSpeak = _shouldSpeakLabel(label, confidence);

    if (_stableLabelCount >= 2 &&
        shouldSpeak &&
        canSpeak &&
        (changed || sameLabelDelayPassed)) {
      _lastSpeechTime = DateTime.now();
      _lastSpokenLabel = label;
      await _speak(summary);
    }
  }

  InputImage? _toInputImage(CameraImage image, CameraDescription description) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final rotation = InputImageRotationValue.fromRawValue(
      description.sensorOrientation,
    );
    if (rotation == null) return null;

    if (Platform.isAndroid && format != InputImageFormat.nv21) {
      return null;
    }
    if (Platform.isIOS && format != InputImageFormat.bgra8888) {
      return null;
    }

    final bytes = image.planes.length == 1
        ? image.planes.first.bytes
        : _concatenatePlanes(image.planes);

    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final writeBuffer = WriteBuffer();
    for (final plane in planes) {
      writeBuffer.putUint8List(plane.bytes);
    }
    return writeBuffer.done().buffer.asUint8List();
  }

  Future<void> _handleLabels(List<ImageLabel> labels) async {
    final filtered =
        labels
            .where((label) => label.confidence >= 0.72)
            .map(
              (label) => (
                text: label.label.toLowerCase().trim(),
                confidence: label.confidence,
              ),
            )
            .where((item) => !_isIgnoredLabel(item.text))
            .toList()
          ..sort((a, b) => b.confidence.compareTo(a.confidence));

    if (filtered.isEmpty) {
      if (mounted) {
        setState(
          () => _status =
              'Not confident yet. Move closer, center object, add light.',
        );
      }
      return;
    }

    final best = filtered.first;
    final label = _normalizeLabel(best.text);
    final confidencePct = (best.confidence * 100).toStringAsFixed(0);
    final summary =
        'There is a $confidencePct percent chance that this is a $label';

    if (mounted) {
      setState(() => _status = summary);
    }

    if (label == _currentStableLabel) {
      _stableLabelCount += 1;
    } else {
      _currentStableLabel = label;
      _stableLabelCount = 1;
    }

    final canSpeak =
        DateTime.now().difference(_lastSpeechTime) > _speechCooldown;
    final changed = label != _lastSpokenLabel;
    final sameLabelDelayPassed =
        DateTime.now().difference(_lastSpeechTime) > _sameLabelRepeatCooldown;
    final shouldSpeak = _shouldSpeakLabel(label, best.confidence);

    if (_stableLabelCount >= 2 &&
        shouldSpeak &&
        canSpeak &&
        (changed || sameLabelDelayPassed)) {
      _lastSpeechTime = DateTime.now();
      _lastSpokenLabel = label;
      await _speak(summary);
    }
  }

  Future<void> _speak(String message) async {
    await _tts.stop();
    await _tts.speak(message);
  }

  Future<String?> _analyzeImageWithOpenAi(Uint8List imageBytes) async {
    final base64Image = base64Encode(imageBytes);
    final uri = Uri.parse('https://api.openai.com/v1/responses');
    final body = jsonEncode({
      'model': _openAiModel,
      'input': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'input_text',
              'text':
                  'Return exactly one concrete object noun (1-2 words). First describe what is clearly visible. If uncertain, prefer this shortlist: table fan, mobile phone, bracelet, necklace, heart, headphone, pen, redbull can, black headphones, water bottle, laptop, paper, poster. The object can still be something else if clearly visible. Do not return scene words (space/indoor/outdoor/background) or adjectives. If still uncertain, return unknown.',
            },
            {
              'type': 'input_image',
              'image_url': 'data:image/jpeg;base64,$base64Image',
            },
          ],
        },
      ],
      'max_output_tokens': 20,
    });

    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $_openAiApiKey',
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('OpenAI request failed: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final text = _sanitizeCloudLabel((decoded['output_text'] ?? '').toString());
    if (text != null) return text;

    final output = decoded['output'];
    if (output is List && output.isNotEmpty) {
      final first = output.first;
      final content = first['content'];
      if (content is List && content.isNotEmpty) {
        final firstContent = content.first;
        final fallback = _sanitizeCloudLabel(
          (firstContent['text'] ?? '').toString(),
        );
        if (fallback != null) return fallback;
      }
    }

    return null;
  }

  bool _isIgnoredLabel(String label) {
    if (_genericLabels.contains(label)) return true;
    for (final generic in _genericLabels) {
      if (label.contains(generic)) {
        return true;
      }
    }
    return false;
  }

  String _normalizeLabel(String raw) {
    final label = raw.toLowerCase().trim();
    if (label == 'phone' || label == 'cell phone' || label == 'smartphone') {
      return 'mobile phone';
    }
    if (label == 'bottle') {
      return 'water bottle';
    }
    if (label == 'headphone' || label == 'headphones' || label == 'headset') {
      return 'black headphones';
    }
    if (label == 'fan') {
      return 'green fan';
    }
    if (label == 'can') {
      return 'red bull can';
    }
    if (label == 'cable' || label == 'wire' || label == 'charger') {
      return 'charger cable';
    }
    return label;
  }

  bool _isInPriorityObjects(String label) {
    if (_priorityObjects.contains(label)) return true;
    for (final item in _priorityObjects) {
      if (label.contains(item) || item.contains(label)) {
        return true;
      }
    }
    return false;
  }

  bool _shouldSpeakLabel(String label, double confidence) {
    return _isInPriorityObjects(label) ||
        confidence >= _allowlistBypassConfidence;
  }

  String? _sanitizeCloudLabel(String raw) {
    var text = raw.toLowerCase().trim();
    if (text.isEmpty) return null;
    text = text
        .replaceAll(RegExp(r'[^a-z\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return null;
    if (text.split(' ').length > 2) {
      text = text.split(' ').take(2).join(' ');
    }
    if (_isIgnoredLabel(text) || text == 'unknown') return null;
    return text;
  }

  Future<(String, double)?> _bestLocalLabelFromFile(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final labels = await _labeler.processImage(inputImage);
    final filtered =
        labels
            .map(
              (label) => (
                text: label.label.toLowerCase().trim(),
                confidence: label.confidence,
              ),
            )
            .where(
              (item) => item.confidence >= 0.65 && !_isIgnoredLabel(item.text),
            )
            .toList()
          ..sort((a, b) => b.confidence.compareTo(a.confidence));

    if (filtered.isEmpty) return null;
    return (filtered.first.text, filtered.first.confidence);
  }

  String? _resolveBestLabel({
    required String? cloudLabel,
    required String? localLabel,
    required double localConfidence,
  }) {
    final cloud = cloudLabel?.toLowerCase().trim();
    final local = localLabel?.toLowerCase().trim();

    if (local != null && localConfidence >= 0.82) {
      return local;
    }

    if (cloud == null || cloud.isEmpty) {
      return local;
    }

    if (cloud == 'helmet' &&
        local != null &&
        (local.contains('headphone') || local.contains('headset'))) {
      return local;
    }

    if (cloud == 'space' && local != null) {
      return local;
    }

    if (_isIgnoredLabel(cloud)) {
      return local;
    }

    return cloud;
  }

  @override
  void dispose() {
    _speech.stop();
    _cameraController?.dispose();
    _labeler.close();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;
    final cameraReady = controller != null && controller.value.isInitialized;

    return Scaffold(
      appBar: AppBar(title: const Text('HandyEyes Labeling')),
      body: Column(
        children: [
          Expanded(
            child: cameraReady
                ? CameraPreview(controller)
                : const Center(child: CircularProgressIndicator()),
          ),
          Container(
            width: double.infinity,
            color: Colors.black87,
            padding: const EdgeInsets.all(16),
            child: Text(
              _status,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                height: 1.4,
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: cameraReady ? _toggleDetection : null,
                  child: Text(
                    _isDetecting ? 'Stop Detection' : 'Start Detection',
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
