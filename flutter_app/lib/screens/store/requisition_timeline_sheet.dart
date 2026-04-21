import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/requisition.dart';
import '../../models/timeline_entry.dart';
import '../../services/api.dart';

/// Opens the immutable audit timeline for a requisition as a modal bottom sheet.
Future<void> showRequisitionTimeline(
  BuildContext context, {
  required Requisition req,
  required String currentUserName,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _RequisitionTimelineSheet(
      req:             req,
      currentUserName: currentUserName,
    ),
  );
}

class _RequisitionTimelineSheet extends StatefulWidget {
  final Requisition req;
  final String currentUserName;

  const _RequisitionTimelineSheet({
    required this.req,
    required this.currentUserName,
  });

  @override
  State<_RequisitionTimelineSheet> createState() => _RequisitionTimelineSheetState();
}

class _RequisitionTimelineSheetState extends State<_RequisitionTimelineSheet> {
  List<TimelineEntry> _entries = [];
  bool _loading = true;
  String? _error;

  final _commentCtrl   = TextEditingController();
  final _scrollCtrl    = ScrollController();
  bool  _sending       = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final entries = await ApiService.instance.getRequisitionTimeline(widget.req.id);
      if (!mounted) return;
      setState(() { _entries = entries; _loading = false; });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendComment() async {
    final msg = _commentCtrl.text.trim();
    if (msg.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ApiService.instance.addTimelineComment(
        widget.req.id,
        widget.currentUserName,
        msg,
      );
      _commentCtrl.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send: ${e.toString()}'),
          backgroundColor: AppTheme.debtRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.req;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Column(
        children: [
          // ── Handle & Header ──────────────────────────────────
          _SheetHandle(),
          _SheetHeader(req: req),
          const Divider(height: 1),

          // ── Timeline Body ────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorView(onRetry: _load)
                    : _entries.isEmpty
                        ? _EmptyTimeline()
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 20),
                            itemCount: _entries.length,
                            itemBuilder: (_, i) => _TimelineItem(
                              entry: _entries[i],
                              isCurrentUser: _entries[i].actorName ==
                                  widget.currentUserName,
                            ),
                          ),
          ),

          const Divider(height: 1),

          // ── Comment Input ────────────────────────────────────
          _CommentInput(
            controller: _commentCtrl,
            sending: _sending,
            onSend: _sendComment,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final Requisition req;
  const _SheetHeader({required this.req});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
      child: Row(
        children: [
          const Icon(Icons.history_edu_rounded, color: AppTheme.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  req.isNewItemRequest
                      ? (req.newItemName ?? 'New Item')
                      : req.itemName,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Requisition Activity Log  ·  ${req.requestedBy}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _EmptyTimeline extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline_rounded,
              size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'No activity yet',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 4),
          Text(
            'System events and comments will appear here.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 48, color: AppTheme.debtRed),
          const SizedBox(height: 12),
          const Text('Failed to load timeline'),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timeline entry — system event pill OR comment bubble
// ─────────────────────────────────────────────────────────────────────────────

class _TimelineItem extends StatelessWidget {
  final TimelineEntry entry;
  final bool isCurrentUser;

  const _TimelineItem({required this.entry, required this.isCurrentUser});

  @override
  Widget build(BuildContext context) {
    return entry.isSystem
        ? _SystemEventPill(entry: entry)
        : _CommentBubble(entry: entry, isCurrentUser: isCurrentUser);
  }
}

class _SystemEventPill extends StatelessWidget {
  final TimelineEntry entry;
  const _SystemEventPill({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.shade200, height: 1)),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt_rounded,
                    size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    entry.message,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  entry.formattedTime,
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: Colors.grey.shade200, height: 1)),
        ],
      ),
    );
  }
}

class _CommentBubble extends StatelessWidget {
  final TimelineEntry entry;
  final bool isCurrentUser;

  const _CommentBubble({required this.entry, required this.isCurrentUser});

  @override
  Widget build(BuildContext context) {
    final initial = (entry.actorName?.isNotEmpty == true)
        ? entry.actorName![0].toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isCurrentUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primary.withOpacity(0.15),
              child: Text(initial,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary)),
            ),
            const SizedBox(width: 10),
          ],

          Flexible(
            child: Column(
              crossAxisAlignment: isCurrentUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Name + time
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isCurrentUser) ...[
                      Text(
                        entry.actorName ?? 'Unknown',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      entry.formattedTime,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Bubble
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isCurrentUser
                        ? AppTheme.primary.withOpacity(0.12)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.only(
                      topLeft:     Radius.circular(isCurrentUser ? 14 : 4),
                      topRight:    Radius.circular(isCurrentUser ? 4 : 14),
                      bottomLeft:  const Radius.circular(14),
                      bottomRight: const Radius.circular(14),
                    ),
                    border: Border.all(
                      color: isCurrentUser
                          ? AppTheme.primary.withOpacity(0.25)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Text(
                    entry.message,
                    style: TextStyle(
                      fontSize: 13,
                      color: isCurrentUser
                          ? AppTheme.primary
                          : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (isCurrentUser) ...[
            const SizedBox(width: 10),
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.secondary.withOpacity(0.2),
              child: Text(initial,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.secondary)),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Comment input bar
// ─────────────────────────────────────────────────────────────────────────────

class _CommentInput extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const _CommentInput({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 10,
        bottom: 10 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Add a comment…',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
                filled: true,
                fillColor: AppTheme.scaffold,
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            height: 44,
            child: sending
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton.filled(
                    onPressed: onSend,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
