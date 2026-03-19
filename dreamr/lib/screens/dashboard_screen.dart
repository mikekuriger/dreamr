// screens/dashboard_screen.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';  // Added for rootBundle
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:dreamr/constants.dart';
import 'package:dreamr/theme/colors.dart';
import 'package:dreamr/services/image_store.dart';
import 'package:dreamr/services/dio_client.dart';
// import 'package:dreamr/services/notification_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mime/mime.dart';
import 'package:dreamr/models/interpreter.dart';  // For Interpreter class
import 'package:provider/provider.dart';
import 'package:dreamr/state/selected_interpreter_model.dart';
import 'package:dreamr/screens/interpreters_screen.dart';  // For InterpreterHelper
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:permission_handler/permission_handler.dart';
import 'package:google_speech/google_speech.dart';
import 'package:flutter_sound/flutter_sound.dart';


class DashboardScreen extends StatefulWidget {
  final ValueNotifier<int> refreshTrigger;
  final ValueNotifier<bool>? tabActiveNotifier;
  final ValueChanged<bool>? onAnalyzingChange;

  const DashboardScreen({
    super.key,
    required this.refreshTrigger,
    this.tabActiveNotifier,
    this.onAnalyzingChange,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final AudioPlayer _player = AudioPlayer();

  late final AnimationController _micAnim;
  late final Animation<double> _micScale;
  late final Animation<double> _micOpacity;

  // Compute RMS of 16-bit little-endian PCM audio data
  double _rmsInt16Le(Uint8List bytes) {
    if (bytes.length < 2) return 0.0;
    final bd = ByteData.sublistView(bytes);
    double acc = 0.0;
    int n = 0;
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      final s = bd.getInt16(i, Endian.little); // -32768..32767
      acc += (s * s).toDouble();
      n++;
    }
    if (n == 0) return 0.0;
    return math.sqrt(acc / n);
  }

  // Speech recognition variables
  late SpeechToText _speech;

  // Auto-stop on silence
  Timer? _silenceTimer;
  DateTime _lastHeard = DateTime.now();
  final Duration _silenceTimeout = const Duration(seconds: 3);

  // Simple VAD (noise calibration)
  bool _vadCalibrating = false;
  int _vadCalibFrames = 0;
  double _noiseFloor = 0.0;

  // Audio recording variables
  FlutterSoundRecorder? _audioRecorder;
  StreamController<List<int>>? _googleAudioCtl; 
  StreamController<Uint8List>? _micCtl;
  
  StreamSubscription? _recognitionSub;

  bool _isRecording = false;
  String _committedText = '';
  String _interimText = '';
  DateTime _lastInterimAt = DateTime.fromMillisecondsSinceEpoch(0);

  String _applySpokenPunctuation(String input) {
    var s = ' $input ';

    final rules = <RegExp, String>{
      RegExp(r'\b(ellipsis|dot dot dot)\b', caseSensitive: false): ' … ',
      RegExp(r'\b(question mark)\b',        caseSensitive: false): ' ? ',
      RegExp(r'\b(exclamation (?:point|mark))\b', caseSensitive: false): ' ! ',
      RegExp(r'\b(semicolon)\b',            caseSensitive: false): ' ; ',
      RegExp(r'\b(colon)\b',                caseSensitive: false): ' : ',
      RegExp(r'\b(dash|hyphen)\b',          caseSensitive: false): ' - ',
      RegExp(r'\b(comma)\b',                caseSensitive: false): ' , ',
      RegExp(r'\b(period|full stop)\b',     caseSensitive: false): ' . ',
      RegExp(r'\b(new line)\b',             caseSensitive: false): '\n',
      RegExp(r'\b(new paragraph)\b',        caseSensitive: false): '\n\n',
      RegExp(r'\b(open quote)\b',           caseSensitive: false): ' “',
      RegExp(r'\b(close quote)\b',          caseSensitive: false): '” ',
    };
    rules.forEach((re, sym) => s = s.replaceAll(re, sym));

    // Use replaceAllMapped for “$1”-style fixes
    s = s.replaceAllMapped(RegExp(r'\s+([,.;:!?…])'), (m) => '${m[1]} ');
    s = s.replaceAllMapped(RegExp(r'\s+([”“])'),      (m) => '${m[1]}');
    s = s.replaceAllMapped(RegExp(r'([\(])\s+'),       (m) => '${m[1]}');
    s = s.replaceAllMapped(RegExp(r'\s+([\)])'),       (m) => '${m[1]}');

    s = s.replaceAll(RegExp(r'\s+\n'), '\n');
    s = s.replaceAll(RegExp(r'\n\s+'), '\n');
    s = s.replaceAll(RegExp(r' {2,}'), ' ');
    s = s.trim();

    // Optional capitalization
    s = s.replaceAllMapped(RegExp(r'(^|[.!?\n]\s+)([a-z])'), (m) => '${m[1]}${m[2]!.toUpperCase()}');

    return s;
  }

  void _renderTextField() {
    final committed = _committedText.trimRight();
    final interim   = _interimText.trimLeft();
    final shown     = (interim.isEmpty ? committed : '$committed $interim'.trim());

    // Mark only the interim as "composing" so platforms visually hint it's provisional.
    final start = committed.length + (committed.isEmpty || interim.isEmpty ? 0 : 1);
    final end   = shown.length;

    final value = TextEditingValue(
      text: shown,
      selection: TextSelection.collapsed(offset: shown.length),
      composing: (interim.isEmpty || end <= start)
          ? TextRange.empty
          : TextRange(start: start, end: end),
    );

    if (_controller.value.text != value.text ||
        _controller.value.selection.baseOffset != value.selection.baseOffset) {
      _controller.value = value;
    }
  }


  String? _userName;
  bool _enableAudio = false;
  bool _hasPlayedIntroAudio = false;

  bool _loading = false;
  bool _imageGenerating = false;
  String? _message;
  String? _dreamImagePath;
  String? _lastDreamText;
  int? _lastDreamId;

  // Discussion thread for the last analyzed dream (shown on Dashboard under analysis)
  List<Map<String, dynamic>> _lastDiscussItems = const [];
  bool _lastDiscussLoading = false;

  // Selected interpreter
  Interpreter? _selectedInterpreter;

  // One-time interpreter tip overlay
  final GlobalKey _interpreterButtonKey = GlobalKey();
  OverlayEntry? _tipOverlay;
  bool _tipSeenPermanently = false;
  bool _tipHasBeenShown = false;   // true after first successful show

  int? _textRemainingWeek; // track # of free dreams left
  bool? _isPro;
  
  @override
  void initState() {
    super.initState();
    _loadUserName();
    _loadDraftText();
    _initSpeechApi();
    _loadQuota();
    _loadInitialSelectedInterpreter();
    _checkInterpreterTip();

    // Listen to changes in selected interpreter
    final interpreterModel = Provider.of<SelectedInterpreterModel>(context, listen: false);
    interpreterModel.addListener(_onInterpreterChanged);

    _micAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _micScale = Tween<double>(begin: 1.0, end: 1.25)
        .chain(CurveTween(curve: Curves.easeInOutCubic))
        .animate(_micAnim);
    _micOpacity = Tween<double>(begin: 0.5, end: 1.0)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_micAnim);

    _controller.addListener(() {
      if (_controller.text.trim().isNotEmpty) {
        _saveDraft(_controller.text);
      }
    });

    widget.refreshTrigger.addListener(_refreshFromTrigger);
    widget.tabActiveNotifier?.addListener(_onTabActiveChanged);
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh quota data when screen becomes visible again
    _loadQuota();
    debugPrint('DashboardScreen: refreshing subscription data in didChangeDependencies');

    // Listen to selected interpreter changes
    final interpreterModel = Provider.of<SelectedInterpreterModel>(context, listen: false);
    interpreterModel.addListener(_onInterpreterChanged);
    // Initialize with current value
    _onInterpreterChanged();

  }

  @override
  void dispose() {
    _player.dispose();
    _audioRecorder?.closeRecorder();
    _googleAudioCtl?.close();
    _micCtl?.close();
    widget.refreshTrigger.removeListener(_refreshFromTrigger);
    widget.tabActiveNotifier?.removeListener(_onTabActiveChanged);
    _stopRecording();
    _micAnim.dispose();
    _tipOverlay?.remove();

    // Remove interpreter listener
    final interpreterModel = Provider.of<SelectedInterpreterModel>(context, listen: false);
    interpreterModel.removeListener(_onInterpreterChanged);

    super.dispose();
  }

  // Load user's subscription quota
  Future<void> _loadQuota() async {
  try {
    final status = await ApiService.getSubscriptionStatus();
    if (!mounted) return;
    setState(() {
      _isPro = status.isActive;
      _textRemainingWeek = status.textRemainingWeek;
    });
  } catch (_) {
    // optional: ignore or snackbar
  }
}
  
  // Initialize speech recognition with Google Cloud Speech API
  Future<void> _initSpeechApi() async {
    try {
      _audioRecorder = FlutterSoundRecorder();
      await _audioRecorder!.openRecorder();
      // iOS stability tweaks
      try {
        await _audioRecorder!.setSubscriptionDuration(const Duration(milliseconds: 50));
      } catch (_) {}

      final raw = await rootBundle.loadString('assets/gcloud-key.json');
      final sa  = ServiceAccount.fromString(raw);
      _speech   = SpeechToText.viaServiceAccount(sa);

      debugPrint('STT init ok');
    } catch (e) {
      debugPrint('STT init failed: $e');
      _showErrorSnackBar('Failed to initialize speech recognition');
    }
  }

  
  // Stop recording and clean up
  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    try {
      debugPrint('stopping recorder…');
      if (_audioRecorder?.isRecording == true) {
        await _audioRecorder!.stopRecorder();
      }
      debugPrint('recorder stopped');

      await _recognitionSub?.cancel();
      _recognitionSub = null;

      if (_googleAudioCtl != null && !_googleAudioCtl!.isClosed) {
        await _googleAudioCtl!.close();
      }
      if (_micCtl != null && !_micCtl!.isClosed) {
        await _micCtl!.close();
      }
      _googleAudioCtl = null;
      _micCtl = null;
    } catch (e, st) {
      debugPrint('stop error: $e\n$st');
    } finally {
      if (mounted) setState(() => _isRecording = false);
      _silenceTimer?.cancel();
      _silenceTimer = null;
      _micAnim.stop();
      _micAnim.value = 0.0;
    }
  }
  
  // Request microphone permission
  Future<bool> _requestMicPermission() async {
    var status = await Permission.microphone.status;
    
    if (status.isDenied) {
      status = await Permission.microphone.request();
    }
    
    if (status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Microphone permission is required for voice recording. Please enable it in app settings."),
          duration: Duration(seconds: 4),
        ),
      );
      return false;
    }
    
    return status.isGranted;
  }

  void _refreshFromTrigger() async {
    // clear old results
    setState(() {
      _message = null;
      _dreamImagePath = null;
    });

    _loadUserName();
    final prefs = await SharedPreferences.getInstance();
    final savedText = prefs.getString('draft_text');
    if (savedText != null && savedText.isNotEmpty) {
      setState(() {
        _controller.text = savedText;
      });
    }
  }

  Future<void> _playIntroAudioOnce() async {
    if (_hasPlayedIntroAudio || !_enableAudio) return;
    _hasPlayedIntroAudio = true;
    try {
      await _player.setAsset('assets/sound/tell_me_about.mp3');
      await _player.play();
    } catch (_) {}
  }

  void _onInterpreterChanged() {
    final interpreterModel = Provider.of<SelectedInterpreterModel>(context, listen: false);
    setState(() {
      _selectedInterpreter = interpreterModel.selectedInterpreter;
    });
  }

  Future<void> _loadUserName() async {
    try {
      final authData = await ApiService.checkAuth();
      if (authData['authenticated'] == true) {
        setState(() {
          _userName = authData['first_name'];
          _enableAudio = authData['enable_audio'] == true || authData['enable_audio'] == '1';
        });
        _playIntroAudioOnce();
      }
    } catch (_) {}
  }

  void _onTabActiveChanged() {
    final isActive = widget.tabActiveNotifier?.value ?? true;
    if (!isActive && _tipOverlay != null) {
      _tipOverlay!.remove();
      _tipOverlay = null;
    } else if (isActive && _tipHasBeenShown && !_tipSeenPermanently && _tipOverlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_tipSeenPermanently && _tipOverlay == null) _showTipOverlay();
      });
    }
  }

  Future<void> _checkInterpreterTip() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('interpreter_tip_seen') ?? false;
    if (seen || !mounted) return;
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) _showTipOverlay();
  }

  void _showTipOverlay() {
    final ctx = _interpreterButtonKey.currentContext;
    if (ctx == null) return;
    final renderBox = ctx.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.of(context).size;

    _tipHasBeenShown = true;
    _tipOverlay = OverlayEntry(
      builder: (_) => Positioned(
        left: offset.dx + 4,
        bottom: screenSize.height - offset.dy,
        width: 250,
        child: Material(
          color: Colors.transparent,
          child: _InterpreterTipBubble(onDismiss: _dismissInterpreterTip),
        ),
      ),
    );
    Overlay.of(context).insert(_tipOverlay!);
  }

  Future<void> _dismissInterpreterTip() async {
    _tipSeenPermanently = true;
    _tipOverlay?.remove();
    _tipOverlay = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('interpreter_tip_seen', true);
  }

  Future<void> _loadInitialSelectedInterpreter() async {
    try {
      final interpreters = await ApiService.fetchInterpreters();
      final selectedInterpreter = await InterpreterHelper.getSelectedInterpreter(interpreters);
      
      Interpreter? interpreterToSet = selectedInterpreter;
      
      // If no interpreter is selected, set default to Dreamr ✨ (id: 26)
      // DEFAULT_INTERPRETER_ID: 26 - Dreamr ✨
      if (interpreterToSet == null) {
        const int defaultInterpreterId = 26; // Dreamr ✨
        interpreterToSet = interpreters.cast<Interpreter?>().firstWhere(
          (interpreter) => interpreter?.id == defaultInterpreterId,
          orElse: () => interpreters.isNotEmpty ? interpreters.first : null,
        );
        
        // Save the default selection
        if (interpreterToSet != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('selected_interpreter_id', interpreterToSet.id);
        }
      }
      
      if (interpreterToSet != null && mounted) {
        final interpreterModel = Provider.of<SelectedInterpreterModel>(context, listen: false);
        interpreterModel.setSelectedInterpreter(interpreterToSet);
      }
    } catch (e) {
      debugPrint('Failed to load initial selected interpreter: $e');
    }
  }

  Future<void> _loadDraftText() async {
    final prefs = await SharedPreferences.getInstance();
    final savedText = prefs.getString('draft_text');
    if (savedText != null && savedText.isNotEmpty) {
      _controller.text = savedText;
    }
  }

  Future<void> _saveDraft(String text) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      await prefs.remove('draft_text');
    } else {
      await prefs.setString('draft_text', trimmed);
    }
  }

  Future<void> _submitDream() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _loading = true;
      _imageGenerating = false;
      _message = null;
      _dreamImagePath = null;
      _lastDreamText = text;
    });

    widget.onAnalyzingChange?.call(true); // 👈 disable/hide nav

    try {
      final prefs = await SharedPreferences.getInstance();
      final imageStyle = prefs.getString('selected_image_style');

      final result = await ApiService.submitDream(
        text,
        interpreterId: _selectedInterpreter?.id,
      );
      final analysis = result['analysis'] as String;
      final dreamId = int.parse(result['dream_id'].toString());
      setState(() { _lastDreamId = dreamId; });
      _loadLastDiscuss(); // start fresh / pull any existing discuss history

      final shouldGen = (result['should_generate_image'] as bool?) ?? false;
      final isQuestion  = result['is_question'] == true; // optional: for copy/UX only
      final String? tone = (result['tone'] is String) ? (result['tone'] as String).trim() : null;
      final String? placeholderUrl = result['image_url'] as String?;

      // Build message: never show tone for questions
      final toneLine = (!isQuestion && tone != null && tone.isNotEmpty)
          ? "\n\nThis dream feels *$tone*."
          : "";

      setState(() {
        _message = "$analysis$toneLine";
        _imageGenerating = shouldGen;
      });

      await prefs.remove('draft_text');
      dreamDataChanged.value = true;
      _loadQuota(); // refresh quota after submission
      _controller.clear();

      if (shouldGen) {
        await _generateDreamImage(dreamId, imageStyle: imageStyle);
      } else {
        if (placeholderUrl != null && placeholderUrl.isNotEmpty) {
          setState(() => _dreamImagePath = placeholderUrl);
        }
        // ensure spinner is off
        setState(() => _imageGenerating = false);
      }

    } catch (e) {
      setState(() {
        _message = "Dream submission failed.";
        _imageGenerating = false; // make sure spinner is off on error
      });
    } finally {
      setState(() {
        _loading = false;
      });
      widget.onAnalyzingChange?.call(false); 
    }
  }

  Future<void> _generateDreamImage(int dreamId, {String? imageStyle}) async {
    try {
      final imagePath = await ApiService.generateDreamImage(dreamId, imageStyle: imageStyle);
      setState(() {
        _dreamImagePath = imagePath;
        _imageGenerating = false;
      });
    } catch (_) {
      setState(() => _imageGenerating = false);
    }
  }

  Future<void> _loadLastDiscuss() async {
    if (_isPro != true) {
      // Discuss is a Pro feature; don't load/show discussion for free users.
      if (mounted) {
        setState(() {
          _lastDiscussItems = const [];
          _lastDiscussLoading = false;
        });
      }
      return;
    }

    final dreamId = _lastDreamId;
    if (dreamId == null) return;

    setState(() => _lastDiscussLoading = true);
    try {
      final items = await ApiService.fetchDiscuss(dreamId);
      if (!mounted) return;
      setState(() {
        _lastDiscussItems = items;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lastDiscussItems = const [];
      });
    } finally {
      if (mounted) setState(() => _lastDiscussLoading = false);
    }
  }

  // Open a popup text box to discuss the last analyzed dream.
  Future<void> _openDiscussSheet() async {
    if (_isPro != true) {
      await _showDiscussProUpsell();
      return;
    }

    final dreamId = _lastDreamId;
    if (dreamId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Analyze a dream first to discuss it.')),
      );
      return;
    }

    final controller = TextEditingController();
    bool sending = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black87,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> send() async {
              final text = controller.text.trim();
              if (text.isEmpty || sending) return;

              setModalState(() => sending = true);
              try {
                final res = await ApiService.discussDream(
                  dreamId,
                  text,
                  interpreterId: _selectedInterpreter?.id,
                );

                final reply = (res['response'] as String?)?.trim() ?? '';
                if (!mounted) return;

                dreamDataChanged.value = true; // so journal refresh picks it up
                controller.clear();

                // Refresh Dashboard discussion section with the latest thread.
                await _loadLastDiscuss();

                Navigator.of(ctx).pop();

                await showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Dreamr'),
                    content: SingleChildScrollView(
                      child: SelectableText(reply.isEmpty ? '(empty response)' : reply),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Discussion submission failed')),
                );
              } finally {
                if (mounted) setModalState(() => sending = false);
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Discuss this dream',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (sending)
                          const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      maxLines: null,
                      decoration: const InputDecoration(
                        hintText: 'Ask a question or add context…',
                        hintStyle: TextStyle(color: Colors.grey),
                        border: OutlineInputBorder(),
                        filled: true,
                      ),
                      style: const TextStyle(color: Colors.black),
                      enabled: !sending,
                      onSubmitted: (_) => send(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: sending ? null : send,
                          child: const Text('Send'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: sending ? null : () => Navigator.of(ctx).pop(),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Future<void> _showDiscussProUpsell() async {
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black87,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Explore this dream further',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'To discuss this dream further, you’ll need Dreamr Pro.',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          Navigator.pushNamed(context, '/subscription');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color.fromARGB(255, 75, 3, 143),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        child: const Text('Go deeper'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Not now'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  
  // Show error snackbar - only for critical errors
  void _showErrorSnackBar(String message) {
    if (mounted) {
      // Only show errors that would prevent recording
      if (message.contains('initialize') || message.contains('permission')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red.shade700,
          ),
        );
      } else {
        // Just log other errors without showing popup
        debugPrint('Speech error (no popup): $message');
      }
    }
  }

  // Start voice recording and transcription
  Future<void> _startVoiceRecording() async {
    // toggle
    if (_isRecording) {
      await _stopRecording();
      return;
    }

    // mic permission once
    final granted = await _requestMicPermission();
    if (!granted) return;

    // client ready
    if (_audioRecorder == null) await _initSpeechApi();

    // stop any audio that may hold session
    try { await _player.stop(); } catch (_) {}

    // state
    _committedText = _controller.text;
    _interimText = '';
    _micAnim.repeat(reverse: true);
    setState(() => _isRecording = true);

    // controllers
    _googleAudioCtl?.close();
    _micCtl?.close();
    _googleAudioCtl = StreamController<List<int>>();
    _micCtl = StreamController<Uint8List>.broadcast();

    // bridge mic → chunk → Google
    _micCtl!.stream.listen((Uint8List data) {
      if (data.isEmpty) return;

      // --- VAD: compute RMS on 16-bit little-endian PCM
      final rms = _rmsInt16Le(data);
      if (_vadCalibrating) {
        // ≈ first 1s: learn noise floor using your 50ms subscription duration
        _vadCalibFrames++;
        _noiseFloor += rms;
        if (_vadCalibFrames >= 20) {
          _noiseFloor /= _vadCalibFrames;
          _vadCalibrating = false;
          debugPrint('VAD noiseFloor=${_noiseFloor.toStringAsFixed(1)}');
        }
      } else {
        // Dynamic threshold a bit above ambient
        final threshold = (_noiseFloor * 2.5).clamp(150.0, 800.0);
        if (rms > threshold) _lastHeard = DateTime.now();
      }

      // --- Forward to Google in ≤24 KB chunks
      const max = 24 * 1024;
      for (var i = 0; i < data.length; i += max) {
        final end = (i + max > data.length) ? data.length : i + max;
        _googleAudioCtl?.add(data.sublist(i, end));
      }
    }, onError: (e) {
      debugPrint('mic stream error: $e');
    });


    // recognition config
    final cfg = RecognitionConfig(
      encoding: AudioEncoding.LINEAR16,
      sampleRateHertz: 16000,
      audioChannelCount: 1,
      languageCode: 'en-US',
      // enableAutomaticPunctuation: true,
      enableAutomaticPunctuation: false,
      maxAlternatives: 1,
      model: RecognitionModel.basic,
      speechContexts: [
        SpeechContext([
          'period', 'full stop', 'comma', 'question mark',
          'exclamation point', 'exclamation mark',
          'semicolon', 'colon',
          'dash', 'hyphen', 'ellipsis', 'dot dot dot',
          'quote', 'open quote', 'close quote',
          'new line', 'new paragraph',
        ]),
      ],
    );

    // streaming config
    final scfg = StreamingRecognitionConfig(
      config: cfg,
      interimResults: true,
      singleUtterance: false,
    );

    // start Google stream
    debugPrint('creating google stream…');
    final responses = _speech.streamingRecognize(scfg, _googleAudioCtl!.stream);
    _recognitionSub = responses.listen((resp) {
      for (final r in resp.results) {
        if (r.alternatives.isEmpty) continue;
        var t = r.alternatives.first.transcript;
        if (t.isEmpty) continue;

        if (r.isFinal) {
          // Map punctuation ONLY on finals
          t = _applySpokenPunctuation(t);

          _committedText = _committedText.isEmpty ? t : '$_committedText $t';
          _interimText = '';
          _renderTextField();
        } else {
          // Interim: debounce + optional stability filter to reduce churn
          final now = DateTime.now();
          final debounceOk = now.difference(_lastInterimAt).inMilliseconds >= 120;
          final stabilityOk = (r.stability >= 0.7); // if field present; otherwise ignore
          if (debounceOk && stabilityOk) {
            _interimText = t;
            _lastInterimAt = now;
            _renderTextField();
          }
        }
      }
    }, onError: (e, st) {
      _interimText = '';
      _renderTextField();
      _showErrorSnackBar('Speech recognition error');
      _stopRecording();
    });

    // start mic AFTER stream exists
    await _audioRecorder!.startRecorder(
      codec: Codec.pcm16,
      sampleRate: 16000,
      numChannels: 1,
      toStream: _micCtl!.sink, // required StreamSink<Uint8List>
    );
    debugPrint('recorder started: ${_audioRecorder!.isRecording}');

    // --- Reset silence/VAD state
    _lastHeard = DateTime.now();
    _vadCalibrating = true;
    _vadCalibFrames = 0;
    _noiseFloor = 0.0;

    // --- Kick off periodic silence check
    _silenceTimer?.cancel();
    _silenceTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!_isRecording) return;
      final idle = DateTime.now().difference(_lastHeard) > _silenceTimeout;
      if (idle) {
        debugPrint('auto-stop: silence > ${_silenceTimeout.inSeconds}s');
        await _stopRecording();
      }
    });
  }


// sharing
// Anchor key for share button
  final GlobalKey _shareAnchorKey = GlobalKey();

// Get origin Rect from GlobalKey
  Rect _originFromKey(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return const Rect.fromLTWH(100, 100, 1, 1); // safe fallback
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) {
      return const Rect.fromLTWH(100, 100, 1, 1);
    }
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  }

// Build shareable text content
  String _buildShareText() {
    final userText   = (_lastDreamText ?? '').trim();     // what user typed
    final analysisMd = (_message ?? '').trim();     // AI analysis (markdown)
    final parts = <String>[];
    if (userText.isNotEmpty) parts.add(userText);
    if (analysisMd.isNotEmpty) parts.add(analysisMd);
    return parts.join('\n\n-- Dreamr ✨ Analysis\n\n');               // separator
  }

// Resolve image file for sharing
  Future<File?> _resolveImageFileForShare() async {
    if (_dreamImagePath == null || _dreamImagePath!.isEmpty) return null;
    final id = _lastDreamId;
    if (id == null) return null;

    // Local-first; download once if missing
    final hit = await ImageStore.localIfExists(id, DreamImageKind.file, _dreamImagePath!);
    if (hit != null) return hit;
    try {
      return await ImageStore.download(id, DreamImageKind.file, _dreamImagePath!, dio: DioClient.dio);
    } catch (_) {
      return null;
    }
  }

// Share dream image (with optional text)
  Future<void> _shareDreamImage({required Rect origin, bool includeText = true}) async {
    final f = await _resolveImageFileForShare();
    final shareText = includeText ? _buildShareText() : '';

    if (f == null || !await f.exists()) {
      if (shareText.isNotEmpty) {
        await SharePlus.instance.share(
          ShareParams(text: shareText, sharePositionOrigin: origin),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to share yet')),
      );
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path, mimeType: lookupMimeType(f.path) ?? 'image/jpeg')],
        text: shareText.isNotEmpty ? shareText : null,
        sharePositionOrigin: origin, // required on iPad/macOS
      ),
    );
  }


  
  @override
  Widget build(BuildContext context) {
    // final bool canAnalyze = !(_loading || _imageGenerating) &&
    //     (
    //       _isPro == null
    //         ? true                                  // while unknown, don't block the user
    //         : (_isPro! || ((_textRemainingWeek ?? 0) > 0))
    //     );
    final bool isOutOfCredits = (_isPro == false) && ((_textRemainingWeek ?? 0) <= 0);
    final bool canAnalyze = !(_loading || _imageGenerating) && !isOutOfCredits;

    return SafeArea(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 👋 Greeting
                Text(
                  "Hello, ${_userName ?? ""}",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),

                // 📜 Intro - Show different text for users out of credits
                Text(
                  isOutOfCredits
                    ? "You've reached your free dream credits for this week. 🌙 "
                      "New credits arrive every Sunday, but why wait? "
                      "Upgrade to Dreamr Pro for unlimited dream analysis, high-resolution dream images, "
                      "and the ability to share your dreams and images with others. "
                      "Unlock the full dream experience ✨"
                    : "Tell me about your dream in as much detail as you remember — characters, settings, emotions, anything that stood out. "
                      "After submitting, I will analyze your dream and generate a personalized interpretation. "
                      "Your dream interpretation takes a few moments, but your dream image will take me a minute or so to create.\n"
                      "So sit tight while the magic happens ✨",
                  style: const TextStyle(fontSize: 13, color: Colors.white),
                ),
                const SizedBox(height: 16),

                // ✏️ Dream entry (locked while analyzing)
                TextField(
                  enabled: !_loading && !_imageGenerating, // ✅ disable typing while analyzing
                  controller: _controller,
                  keyboardType: TextInputType.multiline,
                  minLines: 9,
                  maxLines: null,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                  ),
                  decoration: const InputDecoration(
                    hintText: "Describe your dream...",
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                // Button row with mic and analyze
                Row(
                  children: [
                    // Voice recording button - COMMENTED OUT
                    /*
                    SizedBox(
                      // height: 56,         // match Analyze button height
                      // width: 56,          // square mic button
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // glow while recording
                          if (_isRecording)
                            FadeTransition(
                              opacity: _micOpacity,
                              child: Container(
                                // width: 56, height: 56,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      blurRadius: 18,
                                      spreadRadius: 2,
                                      color: Colors.redAccent.withValues(alpha: 0.45),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              fixedSize: const Size(55, 54),  // enforce size
                              backgroundColor: _isRecording ? Colors.redAccent : AppColors.purple600,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: (_loading || _imageGenerating) ? null : _startVoiceRecording,
                            child: ScaleTransition(
                              scale: _isRecording ? _micScale : AlwaysStoppedAnimation(1.0),
                              child: Icon(_isRecording ? Icons.stop : Icons.mic, size: 24, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    */

                    // Interpreter icon
                    if (_selectedInterpreter != null)
                      GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(context, '/interpreters');
                        },
                        child: Container(
                          key: _interpreterButtonKey,
                          width: 55,
                          height: 54,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.purple600.withValues(alpha: 0.5),
                              width: 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: CachedNetworkImage(
                              imageUrl: 'https://dreamr-us-west-01.zentha.me${_selectedInterpreter!.iconFile}',
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: AppColors.purple950,
                                child: const Icon(
                                  Icons.person,
                                  color: Color(0xFF82D9FF),
                                  size: 24,
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: AppColors.purple950,
                                child: const Icon(
                                  Icons.person,
                                  color: Color(0xFF82D9FF),
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),


                    const SizedBox(width: 12), // Spacing between buttons
                    
                    // Analyze button
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          // backgroundColor: AppColors.purple600,
                          backgroundColor: isOutOfCredits ? Colors.orange.shade700 : AppColors.purple600,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.purple600.withValues(alpha: 0.5),
                          disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          overlayColor: Colors.white.withValues(alpha: 0.1),
                        ),
                        // onPressed: (_loading || _imageGenerating) ? null : _submitDream,
                        onPressed: (_loading || _imageGenerating)
                          ? null
                          : (canAnalyze
                              ? _submitDream
                              : () => Navigator.pushNamed(context, '/subscription')),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_loading || _imageGenerating)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            if (_loading || _imageGenerating)
                              const SizedBox(width: 8),
                            Text(
                              _imageGenerating
                                  ? "Generating Image"
                                  : _loading
                                      ? "Analyzing..."
                                      : canAnalyze ? "Analyze my dream" : "Upgrade to Pro",
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // 🖼️ Results
                if (_message != null)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarkdownBody(
                          data: _message!,
                          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                            p: const TextStyle(color: Colors.black87),
                          ),
                        ),

                        if (_isPro == true && _lastDiscussLoading) ...[
                          const SizedBox(height: 12),
                          const Center(
                            child: SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ] else if (_isPro == true && _lastDiscussItems.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Discussion:',
                            style: TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ..._lastDiscussItems.map((it) {
                            final userTxt = (it['text'] ?? '').toString().trim();
                            final aiTxt = (it['response'] ?? '').toString().trim();

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (userTxt.isNotEmpty) ...[
                                    const Text(
                                      'You:',
                                      style: TextStyle(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SelectableText(
                                      userTxt,
                                      style: const TextStyle(color: Colors.black87),
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  if (aiTxt.isNotEmpty) ...[
                                    const Text(
                                      'Dreamr:',
                                      style: TextStyle(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SelectableText(
                                      aiTxt,
                                      style: const TextStyle(color: Colors.black87),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                        if (_imageGenerating) ...[
                          const SizedBox(height: 12),
                          const Text(
                            "Hang tight — your dream image is being drawn...",
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Color.fromARGB(136, 246, 24, 24),
                            ),
                          ),
                        ],
                        if (_dreamImagePath != null && _dreamImagePath!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: _dreamImagePath!,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              placeholder: (context, url) =>
                                  const Center(child: CircularProgressIndicator()),
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.broken_image, size: 48),
                            ),
                          ),
                        ],

                        // Discuss + Share actions (hide while image is generating)
                        if (!_imageGenerating) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: (_loading || _imageGenerating || _lastDreamId == null)
                                    ? null
                                    : (_isPro == true ? _openDiscussSheet : _showDiscussProUpsell),
                                icon: const Icon(Icons.forum, size: 16),
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Discuss'),
                                    if (_isPro != true) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.18),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                                        ),
                                        child: const Text(
                                          'Pro',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color.fromARGB(255, 75, 3, 143),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  elevation: 0,
                                ),
                              ),
                              const Spacer(),
                              PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                offset: const Offset(0, 32),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                onSelected: (v) {
                                  final origin = _originFromKey(_shareAnchorKey);
                                  _shareDreamImage(includeText: v == 'with_text', origin: origin);
                                },
                                itemBuilder: (ctx) => const [
                                  PopupMenuItem(value: 'image_only', child: Text('Share image')),
                                  PopupMenuItem(value: 'with_text',  child: Text('Share image + dream')),
                                ],
                                child: Container(
                                  key: _shareAnchorKey,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color.fromARGB(255, 75, 3, 143),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.share, size: 18, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
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

class _InterpreterTipBubble extends StatefulWidget {
  final VoidCallback onDismiss;
  const _InterpreterTipBubble({required this.onDismiss});

  @override
  State<_InterpreterTipBubble> createState() => _InterpreterTipBubbleState();
}

class _InterpreterTipBubbleState extends State<_InterpreterTipBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _opacity = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutBack));
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _anim.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: GestureDetector(
          onTap: _dismiss,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 255, 86, 86),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color.fromARGB(255, 255, 0, 0), width: 1,),
                  // boxShadow: [
                  //   BoxShadow(
                  //     color: Colors.purpleAccent.withValues(alpha: 0.4),
                  //     blurRadius: 16,
                  //     offset: const Offset(0, 4),
                  //   ),
                  // ],
                ),
                child: Row(
                  children: [
                    const Text('💬', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Tap here to customize your dream interpreter!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _dismiss,
                      child: const Icon(Icons.close, color: Colors.white54, size: 16),
                    ),
                  ],
                ),
              ),
              // Down-arrow pointing at interpreter button
              const Padding(
                padding: EdgeInsets.only(left: 20),
                child: CustomPaint(
                  size: Size(22, 10),
                  painter: _DownArrowPainter(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownArrowPainter extends CustomPainter {
  const _DownArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color.fromARGB(255, 255, 0, 0)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(10, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_DownArrowPainter oldDelegate) => false;
}