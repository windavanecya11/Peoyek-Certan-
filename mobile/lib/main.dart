import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chicken Diagnosis',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00796B),
          brightness: Brightness.light,
        ),
        brightness: Brightness.light,
        fontFamily: 'Roboto',
      ),
      debugShowCheckedModeBanner: false,
      home: const DiagnosisPage(),
    );
  }
}

class DiagnosisPage extends StatefulWidget {
  const DiagnosisPage({super.key});
  @override
  State<DiagnosisPage> createState() => _DiagnosisPageState();
}

class _DiagnosisPageState extends State<DiagnosisPage> {
  final _picker = ImagePicker();
  File? _imageFile;
  bool _loading = false;
  String? _label;
  double? _confidence;
  String? _error;

  // GANTI ini sesuai alamat backend kamu
  final String baseUrl = 'http://172.20.10.6:5000';
  final String _predictPath = '/predict';

  // Stricter client defaults (should match backend or be stricter)
  final double _threshold = 0.96;
  final double _entropyMax = 0.50;
  final double _marginMin = 0.25;
  final double _likeMin = 0.25;

  Future<void> _pick(ImageSource src) async {
    setState(() {
      _error = null;
      _label = null;
      _confidence = null;
    });
    final picked = await _picker.pickImage(source: src, imageQuality: 80);
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<http.Response> _uploadImage() async {
    final uri = Uri.parse(
      '$baseUrl$_predictPath'
      '?threshold=${_threshold.toStringAsFixed(2)}'
      '&entropy_max=${_entropyMax.toStringAsFixed(2)}'
      '&margin_min=${_marginMin.toStringAsFixed(2)}'
      '&like_min=${_likeMin.toStringAsFixed(2)}'
      '&top3=1',
    );

    final request = http.MultipartRequest('POST', uri)
      ..headers['Accept'] = 'application/json'
      ..files.add(await http.MultipartFile.fromPath('image', _imageFile!.path));

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    return http.Response.fromStream(streamed);
  }

  String _shortBody(String body) {
    final trimmed = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return '';
    return ' — ${trimmed.length > 180 ? '${trimmed.substring(0, 180)}…' : trimmed}';
  }

  String? _pickLabel(Map<String, dynamic> data) {
    for (final k in [
      'label',
      'class',
      'prediction',
      'predicted_class',
      'penyakit'
    ]) {
      final v = data[k];
      if (v != null) return v.toString();
    }
    return null;
  }

  double? _pickConfidence(Map<String, dynamic> data) {
    for (final k in [
      'confidence',
      'probability',
      'score',
      'predicted_confidence'
    ]) {
      final v = data[k];
      if (v is num) return v.toDouble();
      if (v is String) {
        final d = double.tryParse(v);
        if (d != null) return d;
      }
    }
    return null;
  }

  void _handleSuccessBody(String body) {
    try {
      final Map<String, dynamic> data = json.decode(body);
      final status = data['status']?.toString().toUpperCase();
      final conf = _pickConfidence(data);
      final label = _pickLabel(data);

      // Read backend metrics (optional fields)
      final thr = (data['threshold'] is num)
          ? (data['threshold'] as num).toDouble()
          : _threshold;
      final entropy =
          (data['entropy'] is num) ? (data['entropy'] as num).toDouble() : null;
      final margin =
          (data['margin'] is num) ? (data['margin'] as num).toDouble() : null;
      final likeScore = (data['like_score'] is num)
          ? (data['like_score'] as num).toDouble()
          : null;

      // If server decided NOT_FECES, show a clean negative
      if (status != null && status != 'SUCCESS') {
        final confPct = conf != null ? (conf * 100).toStringAsFixed(2) : null;
        final reason = [
          if (confPct != null) 'Confidence: $confPct%',
          if (entropy != null) 'Entropy: ${entropy.toStringAsFixed(2)}',
          if (margin != null) 'Margin: ${margin.toStringAsFixed(2)}',
          if (likeScore != null) 'Like score: ${likeScore.toStringAsFixed(2)}',
          'Threshold: ${thr.toStringAsFixed(2)}',
        ].join(' • ');

        setState(() {
          _error = 'Bukan kotoran ayam.\n$reason';
          _label = null;
          _confidence = conf;
        });
        return;
      }

      // Client-side safety gate: reject borderline even if status SUCCESS
      final rejectByConf = (conf != null && conf < thr);
      final rejectByEntropy = (entropy != null && entropy > _entropyMax);
      final rejectByMargin = (margin != null && margin < _marginMin);
      final rejectByLike = (likeScore != null && likeScore < _likeMin);

      if (rejectByConf || rejectByEntropy || rejectByMargin || rejectByLike) {
        final confPct = conf != null ? (conf * 100).toStringAsFixed(2) : '-';
        final reason = [
          'Confidence: $confPct%',
          if (entropy != null) 'Entropy: ${entropy.toStringAsFixed(2)}',
          if (margin != null) 'Margin: ${margin.toStringAsFixed(2)}',
          if (likeScore != null) 'Like score: ${likeScore.toStringAsFixed(2)}',
          'Threshold: ${thr.toStringAsFixed(2)}',
        ].join(' • ');

        setState(() {
          _error = 'Bukan kotoran ayam.\n$reason';
          _label = null;
          _confidence = conf;
        });
        return;
      }

      // Accepted: show result
      setState(() {
        _label = label ?? '-';
        _confidence = conf;
      });
    } catch (_) {
      // Fallback if server returns plain text
      setState(() {
        _label = body.isNotEmpty ? body : '-';
        _confidence = null;
      });
    }
  }

  Future<void> _predict() async {
    if (_imageFile == null) {
      setState(() => _error = 'Pilih gambar dulu.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _label = null;
      _confidence = null;
    });

    http.Response? resp;
    Object? lastErr;

    try {
      resp = await _uploadImage();
      if (resp.statusCode == 200) {
        _handleSuccessBody(resp.body);
        return;
      }

      final phrase = resp.reasonPhrase;
      final msg =
          'Server error: ${resp.statusCode} ${phrase ?? ''}${_shortBody(resp.body)}';
      setState(() => _error = msg);
    } catch (e) {
      lastErr = e;
      setState(() => _error = 'Gagal konek: $lastErr');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultBox = (_label != null || _error != null)
        ? TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 600),
            tween: Tween(begin: 0.0, end: 1.0),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value.clamp(0.0, 1.0),
                child: Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: child,
                ),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                gradient: _error != null
                    ? LinearGradient(
                        colors: [
                          const Color(0xFFFFEBEE),
                          const Color(0xFFFFCDD2),
                          const Color(0xFFEF9A9A),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : LinearGradient(
                        colors: [
                          const Color(0xFFE0F2F1),
                          const Color(0xFFB2DFDB),
                          const Color(0xFF80CBC4),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: (_error != null
                            ? const Color(0xFFE57373)
                            : const Color(0xFF4DB6AC))
                        .withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _error != null
                      ? Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.block_rounded,
                                color: Colors.red.shade700,
                                size: 56,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Gambar Ditolak',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade900,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.5),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.verified_rounded,
                                color: Colors.teal.shade700,
                                size: 56,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Hasil Diagnosis',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.teal.shade700,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                _label ?? '-',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal.shade900,
                                  letterSpacing: 0.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.teal.shade600,
                                    Colors.teal.shade700,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        Colors.teal.shade400.withOpacity(0.5),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.analytics_rounded,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Confidence: ${_confidence != null ? (_confidence! * 100).toStringAsFixed(1) : '-'}%',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          )
        : const SizedBox();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.pets_rounded, size: 28),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Smart Diagnosis',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  'Chicken Health AI',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
        centerTitle: true,
        elevation: 0,
        toolbarHeight: 70,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF00897B),
                Color(0xFF00695C),
                Color(0xFF004D40),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.teal.shade50.withOpacity(0.3), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Hero(
              tag: 'image_preview',
              child: AspectRatio(
                aspectRatio: 1.4,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF80CBC4),
                        const Color(0xFF4DB6AC),
                        const Color(0xFF26A69A),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00897B).withOpacity(0.4),
                        blurRadius: 24,
                        spreadRadius: 2,
                        offset: const Offset(0, 10),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: _imageFile == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                size: 72,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Pilih atau Ambil Gambar',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Kotoran Ayam',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(_imageFile!, fit: BoxFit.cover),
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        color: Colors.greenAccent,
                                        size: 16,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Siap',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white,
                          const Color(0xFFF5F5F5),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.teal.shade200.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () => _pick(ImageSource.gallery),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        backgroundColor: Colors.transparent,
                        foregroundColor: const Color(0xFF00695C),
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_library_rounded, size: 32),
                          SizedBox(height: 6),
                          Text(
                            'Galeri',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white,
                          const Color(0xFFF5F5F5),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.teal.shade200.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () => _pick(ImageSource.camera),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        backgroundColor: Colors.transparent,
                        foregroundColor: const Color(0xFF00695C),
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.camera_alt_rounded, size: 32),
                          SizedBox(height: 6),
                          Text(
                            'Kamera',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF00897B),
                    Color(0xFF00695C),
                    Color(0xFF004D40),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00897B).withOpacity(0.5),
                    blurRadius: 16,
                    spreadRadius: 1,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _loading ? null : _predict,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_loading)
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.science_rounded,
                              size: 28,
                              color: Colors.white,
                            ),
                          ),
                        const SizedBox(width: 12),
                        Text(
                          _loading ? 'Menganalisis...' : 'Mulai Diagnosis',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            resultBox,
          ],
        ),
      ),
    );
  }
}
