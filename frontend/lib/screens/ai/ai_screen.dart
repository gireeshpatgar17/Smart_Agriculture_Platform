import 'dart:io';

import '../../services/disease_service.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../chat/chat_screen.dart';


class AIScreen extends StatefulWidget {
  const AIScreen({super.key});

  @override
  State<AIScreen> createState() => _AIScreenState();
}

class _AIScreenState extends State<AIScreen> {
  // ==========================================================
  // IMAGE
  // ==========================================================

  XFile? selectedImage;

  final ImagePicker _picker = ImagePicker();

  // ==========================================================
  // AI STATE
  // ==========================================================

  bool isAnalyzing = false;
  bool hasResult = false;

  // Temporary demo result.
  // Later these values will come from your AI model/API.
  String diseaseName = 'Healthy Paddy';
  double confidence = 0.94;
  Map<String, dynamic>? diseaseResult;
  // ==========================================================
  // TAKE PHOTO
  // ==========================================================

  Future<void> takePhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (image == null) {
        return;
      }

      setState(() {
        selectedImage = image;
        hasResult = false;
      });
    } catch (e) {
      _showError('Unable to open camera.\n$e');
    }
  }

  // ==========================================================
  // UPLOAD FROM GALLERY
  // ==========================================================

  Future<void> uploadImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image == null) {
        return;
      }

      setState(() {
        selectedImage = image;
        hasResult = false;
      });
    } catch (e) {
      _showError('Unable to select image.\n$e');
    }
  }

  // ==========================================================
  // ANALYZE IMAGE
  // ==========================================================

  Future<void> analyzeImage() async {
    if (selectedImage == null) {
      return;
    }

    setState(() {
      isAnalyzing = true;
    });

    try {
      final result = await DiseaseService.predictCropDisease(
        selectedImage!,
        farmId: 1,
      );

      setState(() {
        diseaseResult = result;

        diseaseName = result['disease']?.toString() ?? 'Unknown';

        confidence = result['confidence'] is num
            ? (result['confidence'] as num).toDouble()
            : 0.0;

        hasResult = true;
        isAnalyzing = false;
      });
    } catch (e) {
      setState(() {
        isAnalyzing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Disease analysis failed: $e')));
      }
    }
  }

  // ==========================================================
  // RESET
  // ==========================================================

  void chooseAnotherImage() {
    setState(() {
      selectedImage = null;
      hasResult = false;
      isAnalyzing = false;
    });
  }

  // ==========================================================
  // ERROR MESSAGE
  // ==========================================================

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9F3),

      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F9F3),
        elevation: 0,

        title: const Text(
          'AI Crop Doctor',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Chat with AI Assistant',
            icon: const Icon(Icons.forum_rounded, color: Color(0xFF2E7D32)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatScreen()),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),


      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            // ==================================================
            // INTRO
            // ==================================================

            _buildIntroCard(),

            const SizedBox(height: 22),

            const Text(
              'Crop Disease Detection',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            // ==================================================
            // IMAGE
            // ==================================================
            _buildImageSection(),

            // ==================================================
            // ANALYZE
            // ==================================================
            if (selectedImage != null) ...[
              const SizedBox(height: 16),

              _buildAnalyzeButton(),
            ],

            // ==================================================
            // ANALYZING
            // ==================================================
            if (isAnalyzing) ...[
              const SizedBox(height: 18),

              _buildAnalyzingCard(),
            ],

            // ==================================================
            // RESULT
            // ==================================================
            if (hasResult) ...[
              const SizedBox(height: 24),

              const Text(
                'Detection Result',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              _buildResultCard(),

              const SizedBox(height: 14),

              _buildRecommendationCard(),

              const SizedBox(height: 16),

              _buildAnotherImageButton(),
            ],

            // ==================================================
            // TIPS
            // ==================================================
            if (selectedImage == null) ...[
              const SizedBox(height: 24),

              _buildImageTips(),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // INTRO CARD
  // ==========================================================

  Widget _buildIntroCard() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,

          colors: [Colors.green.shade50, Colors.white],
        ),

        borderRadius: BorderRadius.circular(24),

        border: Border.all(color: Colors.green.shade100),
      ),

      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,

            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.shade100,
            ),

            child: Icon(
              Icons.eco_rounded,
              size: 30,
              color: Colors.green.shade700,
            ),
          ),

          const SizedBox(width: 15),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                const Text(
                  'Check your crop health',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 5),

                Text(
                  'Take or upload a clear leaf photo '
                  'to detect possible crop diseases.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // IMAGE SECTION
  // ==========================================================

  Widget _buildImageSection() {
    // --------------------------------------------------------
    // NO IMAGE
    // --------------------------------------------------------

    if (selectedImage == null) {
      return Container(
        width: double.infinity,

        padding: const EdgeInsets.all(18),

        decoration: BoxDecoration(
          color: Colors.white,

          borderRadius: BorderRadius.circular(22),

          border: Border.all(color: Colors.grey.shade200),
        ),

        child: Column(
          children: [
            Container(
              width: 78,
              height: 78,

              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.shade50,
              ),

              child: Icon(
                Icons.add_a_photo_rounded,
                size: 38,
                color: Colors.green.shade700,
              ),
            ),

            const SizedBox(height: 15),

            const Text(
              'Add a photo of the crop leaf',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 5),

            Text(
              'Use a clear, well-lit image',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),

            const SizedBox(height: 18),

            Row(
              children: [
                // CAMERA
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: takePhoto,

                    icon: const Icon(Icons.camera_alt_rounded),

                    label: const Text('Take Photo'),

                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),

                      side: BorderSide(color: Colors.green.shade300),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // GALLERY
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: uploadImage,

                    icon: const Icon(Icons.photo_library_rounded),

                    label: const Text('Upload'),

                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,

                      foregroundColor: Colors.white,

                      padding: const EdgeInsets.symmetric(vertical: 14),

                      elevation: 0,

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // --------------------------------------------------------
    // IMAGE SELECTED
    // --------------------------------------------------------

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(12),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(22),

        border: Border.all(color: Colors.grey.shade200),
      ),

      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(17),

            child: Image.file(
              File(selectedImage!.path),

              width: double.infinity,

              height: 250,

              fit: BoxFit.cover,
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                size: 20,
                color: Colors.green,
              ),

              const SizedBox(width: 7),

              const Expanded(
                child: Text(
                  'Image ready for analysis',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),

              TextButton(
                onPressed: chooseAnotherImage,

                child: const Text('Change'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ANALYZE BUTTON
  // ==========================================================

  Widget _buildAnalyzeButton() {
    return SizedBox(
      width: double.infinity,

      child: ElevatedButton.icon(
        onPressed: isAnalyzing ? null : analyzeImage,

        icon: Icon(
          isAnalyzing
              ? Icons.hourglass_top_rounded
              : Icons.auto_awesome_rounded,
        ),

        label: Text(isAnalyzing ? 'Analyzing...' : 'Analyze Crop'),

        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green.shade700,

          foregroundColor: Colors.white,

          disabledBackgroundColor: Colors.grey.shade300,

          disabledForegroundColor: Colors.grey.shade600,

          padding: const EdgeInsets.symmetric(vertical: 16),

          elevation: 0,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // ANALYZING
  // ==========================================================

  Widget _buildAnalyzingCard() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: Colors.grey.shade200),
      ),

      child: Column(
        children: [
          const SizedBox(
            width: 35,
            height: 35,

            child: CircularProgressIndicator(strokeWidth: 3),
          ),

          const SizedBox(height: 14),

          const Text(
            'Analyzing your crop...',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 5),

          Text(
            'AI is checking the leaf image',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // RESULT
  // ==========================================================

  Widget _buildResultCard() {
    final int confidencePercent = (confidence * 100).round();

    final String status =
        diseaseResult?['status']?.toString() ??
        (diseaseName.toLowerCase() == 'healthy'
            ? 'Healthy'
            : 'Disease Detected');

    final bool isHealthy =
        diseaseName.toLowerCase() == 'healthy' ||
        status.toLowerCase() == 'healthy';

    final double scale = diseaseResult?['scale'] is num
        ? (diseaseResult!['scale'] as num).toDouble()
        : 0.0;

    final Color statusColor = isHealthy ? Colors.green : Colors.red.shade600;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isHealthy ? Colors.green.shade200 : Colors.red.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ----------------------------------------------------
          // DISEASE + STATUS
          // ----------------------------------------------------

          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isHealthy ? Colors.green.shade50 : Colors.red.shade50,
                ),
                child: Icon(
                  isHealthy
                      ? Icons.health_and_safety_rounded
                      : Icons.coronavirus_rounded,
                  color: statusColor,
                  size: 27,
                ),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Detected condition',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      diseaseName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              _statusBadge(isHealthy ? 'Healthy' : 'Diseased', statusColor),
            ],
          ),

          const SizedBox(height: 22),

          // ----------------------------------------------------
          // CONFIDENCE
          // ----------------------------------------------------
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'AI Confidence',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),

              Text(
                '$confidencePercent%',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),

          const SizedBox(height: 9),

          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: confidence.clamp(0.0, 1.0),
              minHeight: 9,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),

          const SizedBox(height: 20),

          // ----------------------------------------------------
          // SEVERITY SCALE
          // ----------------------------------------------------
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Severity Scale',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isHealthy
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isHealthy
                        ? Colors.green.shade200
                        : Colors.orange.shade200,
                  ),
                ),
                child: Text(
                  isHealthy ? 'Healthy' : 'Level ${scale.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isHealthy
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // RECOMMENDATION
  // ==========================================================

  Widget _buildRecommendationCard() {
    final String recommendation =
        diseaseResult?['recommendation']?.toString() ??
        'No recommendation available.';

    final String symptoms =
        diseaseResult?['symptoms']?.toString() ??
        'No symptom information available.';

    final String cause =
        diseaseResult?['cause']?.toString() ??
        'No cause information available.';

    final String treatment =
        diseaseResult?['treatment']?.toString() ??
        'No treatment information available.';

    final String prevention =
        diseaseResult?['prevention']?.toString() ??
        'No prevention information available.';

    final bool isHealthy = diseaseName.toLowerCase() == 'healthy';

    final Color accentColor = isHealthy ? Colors.green : Colors.orange.shade700;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ----------------------------------------------------
          // TITLE
          // ----------------------------------------------------

          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isHealthy
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                ),
                child: Icon(
                  Icons.lightbulb_rounded,
                  color: accentColor,
                  size: 23,
                ),
              ),

              const SizedBox(width: 11),

              const Text(
                'Recommendation',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ],
          ),

          const SizedBox(height: 15),

          // ----------------------------------------------------
          // MAIN RECOMMENDATION
          // ----------------------------------------------------
          Text(
            recommendation,
            style: TextStyle(
              fontSize: 14,
              height: 1.55,
              color: Colors.grey.shade700,
            ),
          ),

          const SizedBox(height: 20),

          // ----------------------------------------------------
          // SYMPTOMS
          // ----------------------------------------------------
          _infoSection('Symptoms', symptoms, Icons.visibility_rounded),

          const SizedBox(height: 15),

          // ----------------------------------------------------
          // CAUSE
          // ----------------------------------------------------
          _infoSection('Cause', cause, Icons.help_outline_rounded),

          const SizedBox(height: 15),

          // ----------------------------------------------------
          // TREATMENT
          // ----------------------------------------------------
          _infoSection('Treatment', treatment, Icons.medical_services_outlined),

          const SizedBox(height: 15),

          // ----------------------------------------------------
          // PREVENTION
          // ----------------------------------------------------
          _infoSection('Prevention', prevention, Icons.shield_outlined),

          const SizedBox(height: 18),

          // ----------------------------------------------------
          // DISCLAIMER
          // ----------------------------------------------------
          Text(
            'Note: AI results are advisory. Confirm serious '
            'disease symptoms with an agricultural expert.',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoSection(String title, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.green.shade700),

        const SizedBox(width: 10),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // ANOTHER IMAGE
  // ==========================================================

  Widget _buildAnotherImageButton() {
    return SizedBox(
      width: double.infinity,

      child: OutlinedButton.icon(
        onPressed: chooseAnotherImage,

        icon: const Icon(Icons.add_a_photo_rounded),

        label: const Text('Analyze Another Image'),

        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // IMAGE TIPS
  // ==========================================================

  Widget _buildImageTips() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(17),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: Colors.grey.shade200),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          const Text(
            'For better detection',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 12),

          _tipRow(Icons.wb_sunny_rounded, 'Use good natural lighting'),

          _tipRow(
            Icons.center_focus_strong_rounded,
            'Keep the leaf clearly visible',
          ),

          _tipRow(Icons.image_rounded, 'Avoid blurry or dark photos'),

          _tipRow(Icons.crop_free_rounded, 'Capture the affected area closely'),
        ],
      ),
    );
  }

  Widget _tipRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),

      child: Row(
        children: [
          Icon(icon, size: 19, color: Colors.green.shade700),

          const SizedBox(width: 9),

          Expanded(
            child: Text(
              text,

              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // STATUS BADGE
  // ==========================================================

  Widget _statusBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),

      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),

        borderRadius: BorderRadius.circular(30),
      ),

      child: Text(
        text,

        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11,
          color: color,
        ),
      ),
    );
  }
}
