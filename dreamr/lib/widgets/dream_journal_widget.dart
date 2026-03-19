// widgets/dream_journal_widget.dart
import 'dart:io';
import 'package:dreamr/models/dream.dart';
import 'package:dreamr/screens/dream_detail_screen.dart';
import 'package:dreamr/services/api_service.dart';
import 'package:dreamr/services/dio_client.dart';
import 'package:dreamr/services/image_store.dart';
import 'package:dreamr/theme/colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'package:mime/mime.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dreamr/data/dream_dao.dart';

// import 'package:provider/provider.dart';
// import 'package:dreamr/models/interpreter.dart'; // adjust path to your actual model file



class DreamJournalWidget extends StatefulWidget { 
  final VoidCallback? onDreamsLoaded;
  final List<Dream>? filteredDreams;
  final bool autoExpandSingle;
  final bool embeddedInScrollView;

  const DreamJournalWidget({
    super.key,
    this.onDreamsLoaded,
    this.filteredDreams,
    this.autoExpandSingle = false,
    this.embeddedInScrollView = true,
  });

  @override
  State<DreamJournalWidget> createState() => DreamJournalWidgetState();
}

// Kept for potential future use; card colors now come from AppColors
class ToneStyle {
  final Color background;
  final Color text;
  const ToneStyle(this.background, this.text);
}

class NotesSheet extends StatefulWidget {
  final int dreamId;
  const NotesSheet({super.key, required this.dreamId});

  @override
  State<NotesSheet> createState() => _NotesSheetState();
}

class _NotesSheetState extends State<NotesSheet> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _lastSeenIso;
  String? _error;
  Map<String, dynamic>? _serverCopy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.getDreamNotes(widget.dreamId);
      if (!mounted) return;
      _controller.text = (data['notes'] as String?) ?? '';
      _lastSeenIso = data['notes_updated_at'] as String?;
    } catch (_) {
      if (!mounted) return;
      _error = 'Failed to load notes';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save({bool overwrite = false}) async {
    setState(() { _saving = true; _error = null; _serverCopy = null; });
    try {
      final res = await ApiService.saveDreamNotes(
        dreamId: widget.dreamId,
        notes: _controller.text,
        lastSeen: overwrite ? null : _lastSeenIso,
      );
      if (!mounted) return;
      _lastSeenIso = res['notes_updated_at'] as String?;
      Navigator.of(context).pop(true); // close sheet
      return;
    } on NotesTooLarge {
      if (mounted) setState(() => _error = 'Keep it under 8000 characters.');
    } on NotesConflict catch (c) {
      if (!mounted) return;
      _serverCopy = c.current;
      setState(() {}); // show conflict UI

      final action = await showDialog<String>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('Notes changed elsewhere'),
          content: const Text('Load the latest from server or overwrite yours?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, 'load'), child: const Text('Load theirs')),
            TextButton(onPressed: () => Navigator.pop(dctx, 'overwrite'), child: const Text('Overwrite')),
            TextButton(onPressed: () => Navigator.pop(dctx, 'cancel'), child: const Text('Cancel')),
          ],
        ),
      );
      if (!mounted) return;

      if (action == 'load' && _serverCopy != null) {
        _controller.text = (_serverCopy!['notes'] as String?) ?? '';
        _lastSeenIso = _serverCopy!['notes_updated_at'] as String?;
        setState(() => _serverCopy = null);
      } else if (action == 'overwrite') {
        await _save(overwrite: true); // will pop
        return;
      }
    } on NotesHttp {
      if (mounted) setState(() => _error = 'Save failed');
    }
    if (mounted) setState(() => _saving = false); // only if we didn’t pop
  }

  Future<void> _clear() async {
    setState(() { _saving = true; _error = null; _serverCopy = null; });
    try {
      final res = await ApiService.saveDreamNotes(
        dreamId: widget.dreamId,
        notes: null,
        lastSeen: _lastSeenIso,
      );
      if (!mounted) return;
      _lastSeenIso = res['notes_updated_at'] as String?;
      _controller.clear();
      Navigator.of(context).pop(true);
      return;
    } on NotesConflict catch (c) {
      if (!mounted) return;
      _serverCopy = c.current;
      setState(() {});
      final action = await showDialog<String>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('Notes changed elsewhere'),
          content: const Text('Load latest or overwrite with clear?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, 'load'), child: const Text('Load theirs')),
            TextButton(onPressed: () => Navigator.pop(dctx, 'overwrite'), child: const Text('Overwrite')),
            TextButton(onPressed: () => Navigator.pop(dctx, 'cancel'), child: const Text('Cancel')),
          ],
        ),
      );
      if (!mounted) return;

      if (action == 'load' && _serverCopy != null) {
        _controller.text = (_serverCopy!['notes'] as String?) ?? '';
        _lastSeenIso = _serverCopy!['notes_updated_at'] as String?;
        setState(() => _serverCopy = null);
      } else if (action == 'overwrite') {
        await ApiService.saveDreamNotes(dreamId: widget.dreamId, notes: null, lastSeen: null);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
    } on NotesHttp {
      if (mounted) setState(() => _error = 'Failed to clear');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(child: Text('Notes (private)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white))),
              if (_saving) const SizedBox(height: 16, width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              TextField(
                controller: _controller,
                maxLines: null,
                maxLength: 8000,
                decoration: const InputDecoration(
                  hintText: 'Jot down anything about this dream…',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(),
                  filled: true,
                ),
                style: const TextStyle(color: Colors.black),
                enabled: !_saving,
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ),
              Row(children: [
                ElevatedButton(onPressed: _saving ? null : () => _save(overwrite: false), child: const Text('Save')),
                const SizedBox(width: 8),
                TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                const Spacer(),
                TextButton(onPressed: _saving ? null : _clear, child: const Text('Clear')),
              ]),
              if (_lastSeenIso != null) ...[
                const SizedBox(height: 6),
                Text('Last edited: $_lastSeenIso',
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}


class DreamJournalWidgetState extends State<DreamJournalWidget> {
  
  List<Dream> _dreams = [];
  // Return filtered dreams if available, otherwise return all dreams
  List<Dream> getDreams() => widget.filteredDreams ?? _dreams;
  List<Dream> getRawDreams() => _dreams;

  final Map<int, bool> _expanded = {};
  bool _loading = true;
  bool get _anyExpanded => _expanded.values.any((v) => v);

  final Map<int, List<Map<String, dynamic>>> _discussCache = {};
  final Set<int> _discussLoading = {};

  // Discuss is a Pro feature
  bool? _isPro;

  Future<void> _loadProStatus() async {
    // Load cached status first so it's available immediately offline
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getBool('sub_is_active');
      debugPrint('💳 Journal cached sub_is_active=$cached');
      if (cached != null && mounted) setState(() => _isPro = cached);
    } catch (e) {
      debugPrint('❌ Journal sub cache error: $e');
    }

    // Then try to get live status from server
    try {
      final status = await ApiService.getSubscriptionStatus();
      if (!mounted) return;
      setState(() => _isPro = status.isActive);
      // Update cache with fresh value
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sub_is_active', status.isActive);
    } catch (_) {
      // Offline — keep cached value already set above
    }
  }


  @override
  void initState() {
    super.initState();
    _loadProStatus();
    if (widget.filteredDreams != null) {
      _loading = false;
      widget.onDreamsLoaded?.call();
    } else {
      _loadDreams();
    }
  }

  
  // Tone symbol helper
  String toneSymbol(String tone) {
    final t = tone.toLowerCase();
    if (t.contains('peaceful')) return '☁️';             // soft cloud
    if (t.contains('epic')) return '⚔️';                 // sword/courage
    if (t.contains('whimsical')) return '✨';            // stars
    if (t.contains('nightmarish')) return '🕷️';          // spider
    if (t.contains('romantic')) return '🩷';             // flowers
    if (t.contains('ancient')) return '⚱️';              // urn / ancient relic
    if (t.contains('futuristic')) return '🔮';           // crystal ball
    // if (t.contains('elegant')) return '༻❁༺';           // ornate flower
    if (t.contains('elegant')) return '••࿐••';           // ornate flower
    return '✨';                                         // default separator
  }

  // Color dot next to tone symbol in collapsed header
  Color toneIndicatorColor(String tone) {
    final t = tone.toLowerCase();
    if (t.contains('peaceful'))    return Colors.blue.shade300;
    if (t.contains('epic'))        return Colors.orange.shade400;
    if (t.contains('whimsical'))   return Colors.purple.shade300;
    if (t.contains('nightmarish')) return Colors.red.shade400;
    if (t.contains('romantic'))    return Colors.pink.shade300;
    if (t.contains('ancient'))     return Colors.brown.shade300;
    if (t.contains('futuristic'))  return Colors.teal.shade300;
    if (t.contains('elegant'))     return Colors.indigo.shade300;
    return Colors.grey.shade400;
  }

  Future<void> _deleteDream(Dream dream) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Dream'),
        content: const Text('This will permanently delete this dream. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ApiService.deleteDream(dream.id);
      if (!mounted) return;
      setState(() {
        _dreams.removeWhere((d) => d.id == dream.id);
        _expanded.remove(dream.id);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete dream')),
      );
    }
  }

  Future<void> _hideDream(Dream dream) async {
    try {
      await ApiService.toggleHiddenDream(dream.id);
      if (!mounted) return;
      setState(() {
        _dreams.removeWhere((d) => d.id == dream.id);
        _expanded.remove(dream.id);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to hide dream')),
      );
    }
  }

// Compute origin rect for share sheets (iPad/macOS need an anchor).
  Rect _shareOrigin() {
    final size = MediaQuery.of(context).size;

    // Tiny 1×1 rect centered on screen – always valid:
    return Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 1,
      height: 1,
    );
  }

// Resolve dream image file for sharing
  Future<File?> _resolveDreamImageFile(Dream d) async {
    final url = d.imageFile;
    if (url == null || url.isEmpty) return null;

    // 1) local hit
    final hit = await ImageStore.localIfExists(d.id, DreamImageKind.file, url);
    if (hit != null) return hit;

    // 2) download once if missing
    try {
      final f = await ImageStore.download(d.id, DreamImageKind.file, url, dio: DioClient.dio);
      return f;
    } catch (_) {
      return null;
    }
  }

// Share dream with image and text
  Future<void> _shareDream(Dream d) async {
    final f = await _resolveDreamImageFile(d);
    if (f == null || !await f.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image not available to share')),
      );
      return;
    }

    String combinedDreamText(Dream d) {
      final parts = <String>[];
      if (d.summary.isNotEmpty) parts.add(d.summary.trim());
      if (d.text.isNotEmpty) parts.add(d.text.trim());
      if (d.analysis.isNotEmpty) parts.add(d.analysis.trim());
      if (parts.isEmpty) return '';
      return parts.join('\n\n────────────\n\n');
    }

    final shareText = combinedDreamText(d);
    final mime = lookupMimeType(f.path) ?? 'image/jpeg';
    // final origin = _originFromKey(_shareAnchorKey);
    final origin = _shareOrigin();

    await SharePlus.instance.share(
      ShareParams(
        title: d.summary.isNotEmpty ? d.summary : null,
        text: shareText.isNotEmpty ? shareText : null,
        files: [XFile(f.path, mimeType: mime, name: f.uri.pathSegments.last)],
        sharePositionOrigin: origin,
      ),
    );
  }

    // Share just the dream image
    Future<void> _shareDreamImage(Dream d) async {
      final f = await _resolveDreamImageFile(d);
      if (f == null || !await f.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image not available to share')),
        );
        return;
      }

      final mime = lookupMimeType(f.path) ?? 'image/jpeg';
      // final origin = _originFromKey(_shareAnchorKey);
      final origin = _shareOrigin();


      await SharePlus.instance.share(
        ShareParams(
          title: d.summary.isNotEmpty ? d.summary : null,
          files: [XFile(f.path, mimeType: mime, name: f.uri.pathSegments.last)],
          sharePositionOrigin: origin,
        ),
      );
    }
  
// Load dreams: show local cache immediately, then refresh from network
  Future<void> _loadDreams() async {
    // 1. Show local data right away so the screen is never blank
    try {
      final local = await DreamDao().getAll();
      debugPrint('📚 Journal DAO returned ${local.length} dreams');
      if (!mounted) return;
      if (local.isNotEmpty) {
        setState(() { _dreams = local; _loading = false; });
        widget.onDreamsLoaded?.call();
      }
    } catch (e) {
      debugPrint('❌ Journal DAO error: $e');
    }

    // 2. Fetch fresh data from network and update
    try {
      final dreams = await ApiService.fetchDreams();
      debugPrint('🌐 Journal API returned ${dreams.length} dreams');
      if (!mounted) return;
      setState(() { _dreams = dreams; _loading = false; });
      widget.onDreamsLoaded?.call();
      // Save to local DAO so the journal is available offline
      DreamDao().upsertMany(dreams).catchError((e) {
        debugPrint('⚠️ Journal DAO upsert error: $e');
        return null;
      });
    } catch (e) {
      debugPrint('⚠️ Journal API error (offline?): $e');
      // Offline — already showing local data; just make sure spinner is gone
      if (mounted) setState(() => _loading = false);
    }
  }

  void refresh() {
    setState(() => _loading = true);
    _loadDreams();
  }

  Future<void> _openNotesEditor(int dreamId) async {
    final changed = await showModalBottomSheet<bool>(
    // await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black87,
      builder: (_) => NotesSheet(dreamId: dreamId),
    );

    if (changed == true && mounted) {
      // Pull latest notes from server and update just this dream
      final data  = await ApiService.getDreamNotes(dreamId);
      final notes = (data['notes'] as String?)?.trim() ?? "";

      setState(() {
        final i = _dreams.indexWhere((d) => d.id == dreamId);
        if (i != -1) {
          _dreams[i] = _dreams[i].copyWith(notes: notes);
        }
      });
    }
  }

  // Post discussions
  Future<void> _openDiscussSheet(Dream dream) async {
    if (_isPro != true) {
      await _showDiscussProUpsell();
      return;
    }

    final controller = TextEditingController();
    final prefs = await SharedPreferences.getInstance();
    final selectedId = prefs.getInt('selected_interpreter_id');

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
                  dream.id,
                  text,
                  interpreterId: selectedId,
                );

                final reply = (res['response'] as String?)?.trim() ?? '';
                if (!mounted) return;

                _discussCache.remove(dream.id);
                await _loadDiscussIfNeeded(dream.id);

                Navigator.of(ctx).pop(); // close sheet first

                // Show reply (simple test UX)
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
              } catch (e) {
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
                  'Continue this conversation',
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

  PageRouteBuilder<void> _dreamFadeRoute(Widget page) => PageRouteBuilder(
        opaque: false,
        barrierColor: AppColors.purple950,
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      );

  // Get discussions
  Future<void> _loadDiscussIfNeeded(int dreamId) async {
    if (_isPro != true) return;
    if (_discussCache.containsKey(dreamId) || _discussLoading.contains(dreamId)) return;
    _discussLoading.add(dreamId);
    try {
      final items = await ApiService.fetchDiscuss(dreamId);
      if (!mounted) return;
      setState(() => _discussCache[dreamId] = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _discussCache[dreamId] = const []);
    } finally {
      _discussLoading.remove(dreamId);
    }
  }



  // Drop-in helper with fallback
  Widget netImageWithFallback(
    String? url, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    BorderRadius? radius,
    }) {
    final widget = (url == null || url.isEmpty)
        ? Image.asset('assets/images/missing.png', width: width, height: height, fit: fit)
        : Image.network(
            url,
            width: width,
            height: height,
            fit: fit,
            // Show placeholder while loading
            loadingBuilder: (ctx, child, prog) =>
                prog == null ? child : Image.asset('assets/images/missing.png', width: width, height: height, fit: fit),
            // Show placeholder on 404/any error
            errorBuilder: (ctx, err, stack) =>
                Image.asset('assets/images/missing.png', width: width, height: height, fit: fit),
          );

    if (radius != null) {
      return ClipRRect(borderRadius: radius, child: widget);
    }
    return widget;
  }

  // Local-first image with same ergonomics as netImageWithFallback
  Widget localFirstImage({
    required int dreamId,
    required String? url,
    required DreamImageKind kind, // DreamImageKind.tile or DreamImageKind.file
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    BorderRadius? radius,
  }) {
    Widget buildPlaceholder() =>
        Image.asset('assets/images/missing.png', width: width, height: height, fit: fit);

    return FutureBuilder<File?>(
      future: () async {
        if (url == null || url.isEmpty) return null;

        // 1) Try local
        final hit = await ImageStore.localIfExists(dreamId, kind, url);
        if (hit != null) return hit;

        // 2) Download once, then it lives on disk
        try {
          final f = await ImageStore.download(dreamId, kind, url, dio: DioClient.dio);
          return f;
        } catch (_) {
          return null;
        }
      }(),
      builder: (ctx, snap) {
        final file = snap.data;
        final w = (file != null)
            ? Image.file(file, width: width, height: height, fit: fit)
            : buildPlaceholder();

        if (radius != null) {
          return ClipRRect(borderRadius: radius, child: w);
        }
        return w;
      },
    );
  }

  String _sanitizeAnalysis(String raw) {
    return raw.replaceAll(RegExp(r'\n[-*_]{3,}\s*$'), '');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final dreamsToDisplay = getDreams();

    // If this widget is being used to show a single dream (e.g. in a detail page),
    // optionally auto-expand that dream so the full content is visible by default.
    if (widget.autoExpandSingle &&
        dreamsToDisplay.length == 1 &&
        !(_expanded[dreamsToDisplay.first.id] ?? false)) {
      _expanded[dreamsToDisplay.first.id] = true;
    }

    if (dreamsToDisplay.isEmpty) {
      return const Text("Your Dreams will appear here...");
    }

    final bool interceptBack = widget.embeddedInScrollView;

    return PopScope<Object?>(
      // In the journal screen we intercept back when a card is expanded;
      // in standalone views we let the route pop normally.
      canPop: !interceptBack || !_anyExpanded,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!interceptBack) return;
        // If the route actually popped, do nothing.
        if (didPop) return;

        // We intercepted back: collapse expanded cards instead of leaving.
        if (_anyExpanded) {
          setState(() {
            _expanded.updateAll((key, value) => false);
          });
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),              //  side gap (width)
        child: ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: widget.embeddedInScrollView,
          physics: widget.embeddedInScrollView
              ? const NeverScrollableScrollPhysics()
              : const AlwaysScrollableScrollPhysics(),
          itemCount: dreamsToDisplay.length,
          itemBuilder: (context, index) {
            final dream = dreamsToDisplay[index];
            final isExpanded = _expanded[dream.id] ?? false;
            final isIpadLike = Platform.isIOS &&
                MediaQuery.of(context).size.shortestSide >= 600;
            final double tileSize = isIpadLike ? 70 : 52;
            final formattedDate = DateFormat('EEE, MMM d, y h:mm a')
                .format(dream.createdAt.toLocal());
            final discussItems = _discussCache[dream.id] ?? const [];
            final discussLoading = _discussLoading.contains(dream.id);

            return Padding(
              key: Key('dream-${dream.id}'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Slidable(
                key: ValueKey(dream.id),
                enabled: !isExpanded,
                startActionPane: ActionPane(
                  motion: const DrawerMotion(),
                  extentRatio: 0.3,
                  children: [
                    SlidableAction(
                      onPressed: (_) => _hideDream(dream),
                      backgroundColor: Colors.indigo.shade700,
                      foregroundColor: Colors.white,
                      icon: Icons.visibility_off,
                      label: 'Hide',
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(6),
                        bottomLeft: Radius.circular(6),
                      ),
                    ),
                  ],
                ),
                endActionPane: ActionPane(
                  motion: const DrawerMotion(),
                  extentRatio: 0.3,
                  children: [
                    SlidableAction(
                      onPressed: (_) => _deleteDream(dream),
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      icon: Icons.delete,
                      label: 'Delete',
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(6),
                        bottomRight: Radius.circular(6),
                      ),
                    ),
                  ],
                ),
                child: GestureDetector(
                  onTap: widget.embeddedInScrollView
                      ? () {
                          Navigator.push(
                            context,
                            _dreamFadeRoute(DreamDetailScreen(dream: dream)),
                          ).then((_) => _loadDreams());
                        }
                      : (!isExpanded ? () {
                          setState(() => _expanded[dream.id] = true);
                          _loadDiscussIfNeeded(dream.id);
                        } : null),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.zero,
                    decoration: BoxDecoration(
                      color: AppColors.dreamCardBackground,                // Card background color
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: toneIndicatorColor(dream.tone).withValues(alpha: 0.5), width: .7),
                      boxShadow: [
                        BoxShadow(
                          color: toneIndicatorColor(dream.tone).withValues(alpha: 0.55),
                          blurRadius: 7,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // COLLAPSED ROW (image + title line)
                    GestureDetector(
                      onTap: widget.embeddedInScrollView
                          ? () {
                              Navigator.push(
                                context,
                                _dreamFadeRoute(DreamDetailScreen(dream: dream)),
                              ).then((_) => _loadDreams());
                            }
                          : () {
                              setState(() {
                                _expanded[dream.id] = !isExpanded;
                              });
                              if (!isExpanded) {
                                _loadDiscussIfNeeded(dream.id);
                              }
                            },
                      child: widget.embeddedInScrollView
                          // Main journal view: show tile image + text like before
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Always render the tile using localFirstImage;
                                // it will show missing.png when imageTile is
                                // NULL/empty, or the real tile when present.
                                ClipRRect(
                                  // image hugs the card’s left/top/bottom
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(6),
                                    bottomLeft: Radius.circular(6),
                                    topRight: Radius.circular(6),
                                    bottomRight: Radius.circular(6),
                                  ),
                                  child: localFirstImage(
                                    dreamId: dream.id,
                                    url: dream.imageTile,
                                    kind: DreamImageKind.tile,
                                    width: tileSize,                                  // ICON size
                                    height: tileSize,
                                    fit: BoxFit.cover,
                                    radius: BorderRadius.zero,
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    // padding only around text, not image
                                    padding: const EdgeInsets.all(6),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Date + tone indicator row
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                formattedDate,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.dreamCardText,
                                                ),
                                              ),
                                            ),
         // DOT                             // Container(
                                            //   width: 8, height: 8,
                                            //   decoration: BoxDecoration(
                                            //     color: toneIndicatorColor(dream.tone),
                                            //     shape: BoxShape.circle,
                                            //   ),
                                            // ),
                                            const SizedBox(width: 4),
                                            Text(
                                              toneSymbol(dream.tone),
                                              style: const TextStyle(fontSize: 13),
                                            ),
                                            const SizedBox(width: 4),
                                          ],
                                        ),
                                        Text(
                                          dream.summary,
                                          maxLines: 1,
                                          softWrap: false,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: AppColors.dreamCardText,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          // Detail view (My Dream page): text-only header
                          : Padding(
                              padding: const EdgeInsets.all(6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          formattedDate,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.dreamCardText,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 8, height: 8,
                                        decoration: BoxDecoration(
                                          color: toneIndicatorColor(dream.tone),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(toneSymbol(dream.tone), style: const TextStyle(fontSize: 13)),
                                      const SizedBox(width: 4),
                                    ],
                                  ),
                                  Text(
                                    dream.summary,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: AppColors.dreamCardText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),

                    // EXPANDED CONTENT
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: isExpanded
                          ? Padding(
                              padding: const EdgeInsets.all(6), // expanded area padding
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Divider row with tone symbol
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Divider(
                                          color: AppColors.dreamCardText
                                              .withValues(alpha: 0.25),
                                          thickness: 1,
                                          indent: 16,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        child: Text(
                                          toneSymbol(dream.tone), // 🕷️, 🌸, ☁️, etc.
                                          style: TextStyle(
                                            fontSize: 20,
                                            color: AppColors.dreamCardText
                                                .withValues(alpha: 0.7),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Divider(
                                          color: AppColors.dreamCardText
                                              .withValues(alpha: 0.25),
                                          thickness: 1,
                                          endIndent: 16,
                                        ),
                                      ),
                                    ],
                                  ),

                                  // Dream Text Header
                                  Row(
                                    children: [
                                      Text(
                                        "My Dream:",
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.dreamCardText,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        dream.tone,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontStyle: FontStyle.italic,
                                          color: AppColors.dreamCardText,
                                        ),
                                      ),
                                    ],
                                  ),

                                  // Dream Text
                                  if (dream.text.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    SelectableText(
                                      dream.text,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontStyle: FontStyle.italic,
                                        color: AppColors.dreamCardText,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],

                                  // Dream Image (full-size)
                                  if (dream.imageFile != null &&
                                      dream.imageFile!.isNotEmpty)
                                    localFirstImage(
                                      dreamId: dream.id,
                                      url: dream.imageFile,
                                      kind: DreamImageKind.file,
                                      fit: BoxFit.cover,
                                      radius: BorderRadius.circular(8),
                                    ),

                                  // Gradient Divider
                                  Container(
                                    height: 1,
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          AppColors.dreamCardText
                                              .withValues(alpha: 0.7),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Dream Analysis
                                  if (dream.analysis.isNotEmpty) ...[
                                    Text(
                                      "Analysis:",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.dreamCardText,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    MarkdownBody(
                                      // data: dream.analysis,
                                      data: _sanitizeAnalysis(dream.analysis),  // remove trailing divider
                                      styleSheet:
                                          MarkdownStyleSheet.fromTheme(
                                                  Theme.of(context))
                                              .copyWith(
                                        p: TextStyle(
                                          color: AppColors.dreamCardText,
                                          fontSize: 13,
                                        ),
                                        strong: TextStyle(
                                          color: AppColors.dreamCardText,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        em: TextStyle(
                                          color: AppColors.dreamCardText,
                                          fontStyle: FontStyle.italic,
                                        ),
                                        h1: TextStyle(
                                          color: AppColors.dreamCardText,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        h2: TextStyle(
                                          color: AppColors.dreamCardText,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                  ],

                                  // Discussion (Pro only)
                                  if (_isPro == true && discussLoading) ...[
                                    const SizedBox(height: 6),
                                    const Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                                    const SizedBox(height: 6),
                                  ] else if (_isPro == true && discussItems.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      "Discussion:",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.dreamCardText,
                                      ),
                                    ),
                                    const SizedBox(height: 4),

                                    ...discussItems.map((it) {
                                      final userTxt = (it['text'] ?? '').toString().trim();
                                      final aiTxt   = (it['response'] ?? '').toString().trim();

                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 10),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (userTxt.isNotEmpty) ...[
                                              Text("You:", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.dreamCardText, fontSize: 12)),
                                              const SizedBox(height: 2),
                                              SelectableText(userTxt, style: TextStyle(color: AppColors.dreamCardText, fontSize: 13)),
                                              const SizedBox(height: 6),
                                            ],
                                            if (aiTxt.isNotEmpty) ...[
                                              Text("Dreamr:", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.dreamCardText, fontSize: 12)),
                                              const SizedBox(height: 2),
                                              MarkdownBody(
                                                data: aiTxt,
                                                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                                  p: TextStyle(color: AppColors.dreamCardText, fontSize: 13),
                                                  strong: TextStyle(color: AppColors.dreamCardText, fontWeight: FontWeight.bold),
                                                  em: TextStyle(color: AppColors.dreamCardText, fontStyle: FontStyle.italic),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    }),

                                    const SizedBox(height: 6),
                                  ],


                                  // Dream Notes
                                  if (dream.notes.isNotEmpty) ...[
                                    Text(
                                      "Personal Notes:",
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.dreamCardText,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    MarkdownBody(
                                      data: dream.notes,
                                      styleSheet:
                                          MarkdownStyleSheet.fromTheme(
                                                  Theme.of(context))
                                              .copyWith(
                                        p: TextStyle(
                                          color: AppColors.dreamCardText,
                                          fontSize: 12,
                                        ),
                                        strong: TextStyle(
                                          color: AppColors.dreamCardText,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        em: TextStyle(
                                          color: AppColors.dreamCardText,
                                          fontStyle: FontStyle.italic,
                                        ),
                                        h1: TextStyle(
                                          color: AppColors.dreamCardText,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        h2: TextStyle(
                                          color: AppColors.dreamCardText,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                  ],

                                  // Notes + Share buttons
                                  Row(
                                    children: [
                                      // Notes button
                                      ElevatedButton.icon(
                                        onPressed: () =>
                                            _openNotesEditor(dream.id),
                                        icon: const Icon(Icons.edit_note,
                                            size: 16),
                                        label: Text(
                                          (dream.notes.trim().isNotEmpty)
                                              ? 'Edit notes'
                                              : 'Add notes',
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color.fromARGB(
                                                  255, 75, 3, 143),          // Notes button color
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 8),
                                          minimumSize: const Size(0, 0),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          textStyle: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          elevation: 0,
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Discuss button (no Pro pill here; row is space-constrained)
                                      ElevatedButton.icon(
                                        onPressed: () => _openDiscussSheet(dream),
                                        icon: const Icon(Icons.forum, size: 16),
                                        label: const Text('Discuss'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color.fromARGB(255, 75, 3, 143),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          minimumSize: const Size(0, 0),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          textStyle: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          elevation: 0,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      

                                      // Share button with popup menu
                                      Material(
                                        // key: _shareAnchorKey,
                                        color: const Color.fromARGB(
                                            255, 75, 3, 143),
                                        borderRadius: BorderRadius.circular(10),
                                        elevation: 0,
                                        child: PopupMenuButton<String>(
                                          tooltip: 'Share',
                                          offset: const Offset(0, 30),
                                          onSelected: (v) {
                                            if (v == 'with_text') {
                                              _shareDream(dream);
                                            } else if (v == 'image_only') {
                                              _shareDreamImage(dream);
                                            }
                                          },
                                          itemBuilder: (ctx) => const [
                                            PopupMenuItem(
                                              value: 'with_text',
                                              child: Text(
                                                  'Share dream + image'),
                                            ),
                                            PopupMenuItem(
                                              value: 'image_only',
                                              child:
                                                  Text('Share image only'),
                                            ),
                                          ],
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 8),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: const [
                                                Icon(Icons.share,
                                                    size: 16,
                                                    color: Colors.white),
                                                // SizedBox(width: 6),
                                                // Text(
                                                //   'Share ✨',
                                                //   style: TextStyle(
                                                //     fontSize: 13,
                                                //     fontWeight:
                                                //         FontWeight.w600,
                                                //     color: Colors.white,
                                                //   ),
                                                // ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),

                                      const Spacer(),
                                      // Caret ^ close icon (only needed in main journal view)
                                      if (widget.embeddedInScrollView)
                                        IconButton(
                                          icon: Icon(
                                            // Icons.keyboard_arrow_up, // or Icons.expand_less
                                            Icons.expand_less,
                                            size: 32,
                                            color: AppColors.dreamCardText,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () {
                                            setState(() {
                                              _expanded[dream.id] = false;
                                            });
                                          },
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
                ),  // Container
              ),    // GestureDetector
            ),      // Slidable
            );
          },
        ),
      )
    );
  }
}
