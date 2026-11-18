import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/backend_manager.dart';
import '../../auth/providers/auth_provider.dart';
import '../../chat/providers/chat_provider.dart';
import '../../dashboard/providers/workspace_provider.dart';
import '../providers/document_provider.dart';
import 'document_viewer_page.dart';

const _desktopSupportedExtensions = {'txt', 'md', 'html', 'htm', 'pdf', 'docx'};

class DocumentsPage extends ConsumerStatefulWidget {
  const DocumentsPage({super.key});

  @override
  ConsumerState<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends ConsumerState<DocumentsPage> {
  Timer? _refreshTimer;
  final Set<String> _selectedIds = {};
  bool _selectionMode = false;
  String? _activeFolder;

  @override
  void initState() {
    super.initState();
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws != null) {
      ref.read(documentProvider.notifier).loadDocuments(ws.id);
      loadGraphStats(ref, ws.id);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh(List<Document> docs) {
    _refreshTimer?.cancel();
    final hasProcessing = docs.any((d) => d.isProcessing);
    if (hasProcessing) {
      _refreshTimer = Timer(const Duration(seconds: 3), () {
        final ws = ref.read(selectedWorkspaceProvider);
        if (ws != null && mounted) {
          ref.read(documentProvider.notifier).loadDocuments(ws.id);
        }
      });
    }
  }

  bool get _isDesktopEmbedded =>
      !kIsWeb && BackendManager.shouldRunEmbedded;

  Future<void> _uploadFile() async {
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws == null) return;

    final allowedExts = _isDesktopEmbedded
        ? _desktopSupportedExtensions.toList()
        : ['pdf', 'docx', 'txt', 'md', 'html'];

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExts,
      allowMultiple: true,
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      int successCount = 0;
      for (final file in result.files) {
        if (file.bytes != null) {
          final ok = await ref
              .read(documentProvider.notifier)
              .uploadDocument(ws.id, file.bytes!, file.name);
          if (ok) successCount++;
        }
      }
      if (mounted && successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully uploaded $successCount files')),
        );
      }
    }
  }

  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty) return;
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batch delete'),
        content: Text('Are you sure you want to delete ${_selectedIds.length} documents? This operation is irreversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    for (final id in _selectedIds.toList()) {
      await ref.read(documentProvider.notifier).deleteDocument(ws.id, id);
    }
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Batch deletion completed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(selectedWorkspaceProvider);
    final docs = ref.watch(documentProvider);
    final graphStats = ref.watch(graphStatsProvider);

    if (ws == null) {
      return Center(
        child: Text('Select a workspace first', style: TextStyle(color: Colors.grey.shade500)),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
          ),
          child: Row(
            children: [
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Knowledge base',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(ws.name,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(width: 8),
                  _buildWorkspaceSwitch(ws),
                ],
              ),
              const Spacer(),
              if (_selectionMode) ...[
                Text('${_selectedIds.length} item selected',
                    style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _batchDelete,
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  label: const Text('Batch delete', style: TextStyle(color: Colors.red)),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() {
                    _selectionMode = false;
                    _selectedIds.clear();
                  }),
                  child: const Text('Cancel'),
                ),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: () => setState(() => _selectionMode = true),
                  icon: const Icon(Icons.checklist, size: 18),
                  label: const Text('Choose'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _uploadFile,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Upload documents'),
                ),
                if (_isDesktopEmbedded) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Desktop mode supports PDF/TXT/MD/HTML/DOCX local parsing \n'
                        'Scanned PDF requires OCR support',
                    child: Icon(Icons.info_outline,
                        size: 18, color: Colors.blue.shade600),
                  ),
                ],
              ],
            ],
          ),
        ),
        Expanded(
          child: docs.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Loading failed: $e')),
            data: (allDocs) {
              _startAutoRefresh(allDocs);
              final folders = _extractFolders(allDocs);
              final list = _activeFolder == null
                  ? allDocs
                  : allDocs.where((d) => d.tags.contains(_activeFolder)).toList();
              if (allDocs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.upload_file,
                          size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('No document yet',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(color: Colors.grey)),
                      const SizedBox(height: 8),
                      Text(
                          _isDesktopEmbedded
                              ? 'Click "Upload Document" to add PDF, DOCX, TXT, MD or HTML files'
                              : 'Click "Upload Document" to add a PDF, DOCX or TXT file',
                          style: TextStyle(color: Colors.grey.shade500)),
                      if (_isDesktopEmbedded) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.blue.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.info_outline,
                                  size: 16,
                                  color: Colors.blue.shade700),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Desktop mode supports PDF/TXT/MD/HTML local parsing.'
                                  'Scanned PDF and image PDF temporarily require OCR support',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  if (folders.isNotEmpty) _buildFolderBar(folders, ws),
                  if (_activeFolder != null && list.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text('There are no documents in the folder "$_activeFolder"',
                            style: TextStyle(color: Colors.grey.shade500)),
                      ),
                    )
                  else
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                  final doc = list[index];
                  final isSelected = _selectedIds.contains(doc.id);
                  return Card(
                    child: ListTile(
                      onTap: _selectionMode
                          ? () => setState(() {
                                if (isSelected) {
                                  _selectedIds.remove(doc.id);
                                } else {
                                  _selectedIds.add(doc.id);
                                }
                              })
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DocumentViewerPage(
                                    document: doc,
                                    workspaceId: ws.id,
                                  ),
                                ),
                              );
                            },
                      onLongPress: () {
                        if (!_selectionMode) {
                          setState(() {
                            _selectionMode = true;
                            _selectedIds.add(doc.id);
                          });
                        }
                      },
                      selected: isSelected,
                      leading: _selectionMode
                          ? Checkbox(
                              value: isSelected,
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _selectedIds.add(doc.id);
                                } else {
                                  _selectedIds.remove(doc.id);
                                }
                              }),
                            )
                          : _fileIcon(doc.fileType),
                      title: Text(doc.originalFilename,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(doc.fileSizeFormatted),
                              const SizedBox(width: 12),
                              _statusChip(doc),
                              if (doc.processingElapsedMs != null && doc.processingStatus == 'ready') ...[
                                const SizedBox(width: 8),
                                Text(_formatElapsed(doc.processingElapsedMs!),
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                              ],
                              if (doc.chunkCount != null) ...[
                                const SizedBox(width: 12),
                                Text('${doc.chunkCount} chunking',
                                    style: TextStyle(
                                        color: Colors.grey.shade600, fontSize: 12)),
                              ],
                              _graphBadge(graphStats[doc.id]),
                            ],
                          ),
                          if (doc.tags.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: doc.tags
                                    .map((t) => Padding(
                                          padding: const EdgeInsets.only(right: 4),
                                          child: Chip(
                                            label: Text(t, style: const TextStyle(fontSize: 10)),
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                                            padding: EdgeInsets.zero,
                                            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ),
                          if (doc.processingStatus == 'embedding_failed')
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'The document text has been parsed, but vectorization failed and cannot be used for question and answer retrieval. ${doc.processingError != null ? "\n${doc.processingError}" : ""}',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                              ),
                            )
                          else if (doc.processingStatus == 'failed' && doc.processingError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                doc.processingError!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: Colors.red.shade400),
                              ),
                            )
                          else if (doc.isStale)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Processing time is long, the file may be too large, or the backend task may have been interrupted.'
                                'You can click "Reprocess" on the right menu to try again.',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                              ),
                            ),
                        ],
                      ),
                      trailing: PopupMenuButton(
                        itemBuilder: (ctx) => [
                          if (doc.processingStatus == 'ready')
                            const PopupMenuItem(
                                value: 'generate_graph', child: Text('Generate knowledge graph')),
                          if (doc.isStale || doc.processingStatus == 'failed' || doc.processingStatus == 'embedding_failed')
                            const PopupMenuItem(
                                value: 'reprocess',
                                child: Text('reprocess')),
                          if (doc.isProcessing)
                            const PopupMenuItem(
                                value: 'cancel',
                                child: Text('Cancel processing')),
                          const PopupMenuItem(
                              value: 'move_folder', child: Text('Move to folder')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('Delete')),
                        ],
                        onSelected: (value) async {
                          if (value == 'delete') {
                            await ref
                                .read(documentProvider.notifier)
                                .deleteDocument(ws.id, doc.id);
                          } else if (value == 'move_folder') {
                            _showMoveFolderDialog(doc, ws);
                          } else if (value == 'generate_graph') {
                            _generateGraphForDoc(ws.id, doc.id, doc.originalFilename);
                          } else if (value == 'reprocess') {
                            final ok = await ref
                                .read(documentProvider.notifier)
                                .reprocessDocument(ws.id, doc.id);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(ok
                                    ? 'Document processing retriggered: ${doc.originalFilename}'
                                    : 'Reprocessing failed, please try again later'),
                                backgroundColor: ok ? null : Colors.red,
                              ));
                            }
                          } else if (value == 'cancel') {
                            final ok = await ref
                                .read(documentProvider.notifier)
                                .reprocessDocument(ws.id, doc.id);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(ok ? 'Processing canceled' : 'Cancellation failed'),
                              ));
                            }
                          }
                        },
                      ),
                    ),
                  );
                },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceSwitch(dynamic ws) {
    final workspaces = ref.watch(workspaceProvider);
    return workspaces.when(
      data: (list) {
        if (list.length <= 1) return const SizedBox.shrink();
        return PopupMenuButton<String>(
          tooltip: 'Switch workspace/library',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_horiz, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 4),
                Text('switch', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
              ],
            ),
          ),
          onSelected: (id) {
            final target = list.firstWhere((w) => w.id == id);
            ref.read(selectedWorkspaceProvider.notifier).state = target;
            saveLastWorkspaceId(target.id);
            ref.read(documentProvider.notifier).loadDocuments(target.id);
            ref.read(conversationProvider.notifier).loadConversations(target.id);
            ref.read(selectedConversationProvider.notifier).state = null;
            ref.read(messagesProvider.notifier).state = [];
          },
          itemBuilder: (_) => list
              .map((w) => PopupMenuItem<String>(
                    value: w.id,
                    child: Row(
                      children: [
                        Icon(
                          w.id == ws.id ? Icons.check_circle : Icons.circle_outlined,
                          size: 16,
                          color: w.id == ws.id
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(w.name),
                        if (w.description != null) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              w.description!,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ))
              .toList(),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _fileIcon(String fileType) {
    IconData icon;
    Color color;
    switch (fileType.toLowerCase()) {
      case 'pdf':
        icon = Icons.picture_as_pdf;
        color = Colors.red;
        break;
      case 'docx':
        icon = Icons.description;
        color = Colors.blue;
        break;
      default:
        icon = Icons.insert_drive_file;
        color = Colors.grey;
    }
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.1),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Set<String> _extractFolders(List<Document> docs) {
    final folders = <String>{};
    for (final d in docs) {
      folders.addAll(d.tags);
    }
    return folders;
  }

  Widget _buildFolderBar(Set<String> folders, dynamic ws) {
    final sortedFolders = folders.toList()..sort();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _folderChip('All', null),
                  ...sortedFolders.map((f) => _folderChip(f, f)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            tooltip: 'Create new folder',
            onPressed: () => _showCreateFolderDialog(ws),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _folderChip(String label, String? folder) {
    final isActive = _activeFolder == folder;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: isActive,
        onSelected: (_) => setState(() => _activeFolder = folder),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Future<void> _showCreateFolderDialog(dynamic ws) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create new folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'folder name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) {
      setState(() => _activeFolder = name);
    }
  }

  Future<void> _generateGraphForDoc(String workspaceId, String docId, String filename) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Generating knowledge graph for "$filename"...'), duration: const Duration(seconds: 30)),
    );
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.post('/workspaces/$workspaceId/knowledge-graph/generate/$docId');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        final entities = resp.data['entities_created'] ?? 0;
        final relations = resp.data['relations_created'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Graph generated: $entities entities, $relations relationships'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Graph generation failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showMoveFolderDialog(Document doc, dynamic ws) async {
    final docs = ref.read(documentProvider).value ?? [];
    final existingFolders = _extractFolders(docs).toList()..sort();
    final controller = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to folder'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (doc.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Current folder: ${doc.tags.join(", ")}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ),
              if (existingFolders.isNotEmpty) ...[
                const Text('Select an existing folder:', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    ActionChip(
                      label: const Text('No folder'),
                      onPressed: () => Navigator.pop(ctx, '__none__'),
                    ),
                    ...existingFolders.map((f) => ActionChip(
                          label: Text(f),
                          onPressed: () => Navigator.pop(ctx, f),
                        )),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Or enter a new folder:', style: TextStyle(fontSize: 13)),
              ] else
                const Text('Enter the folder name:', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'New folder name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (result == null || result.isEmpty) return;

    final newTags = result == '__none__' ? <String>[] : [result];
    await ref.read(documentProvider.notifier).updateTags(ws.id, doc.id, newTags);
  }

  Widget _statusChip(Document doc) {
    Color color;
    final label = doc.progressDescription;
    final isLoading = doc.isProcessing;
    final progress = doc.progressPercent;

    switch (doc.processingStatus) {
      case 'ready':
        color = Colors.green;
        break;
      case 'processing':
      case 'chunking':
        color = Colors.orange;
        break;
      case 'embedding':
        color = Colors.blue;
        break;
      case 'failed':
        color = Colors.red;
        break;
      case 'embedding_failed':
        color = Colors.orange;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading && progress != null) ...[
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: color,
                value: progress,
              ),
            ),
            const SizedBox(width: 4),
          ] else if (isLoading) ...[
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _formatElapsed(int ms) {
    if (ms < 1000) return 'Processing time: ${ms}ms';
    final secs = ms / 1000.0;
    if (secs < 60) return 'Processing time: ${secs.toStringAsFixed(1)}s';
    final mins = secs / 60.0;
    return 'Processing time: ${mins.toStringAsFixed(1)}min';
  }

  Widget _graphBadge(GraphStat? stat) {
    if (stat == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hub, size: 11, color: Colors.teal.shade600),
            const SizedBox(width: 3),
            Text(
              '${stat.entitiesCount} entity/${stat.relationsCount} relationship',
              style: TextStyle(color: Colors.teal.shade700, fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
