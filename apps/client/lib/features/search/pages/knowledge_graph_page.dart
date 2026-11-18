import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../dashboard/providers/workspace_provider.dart';
import '../providers/knowledge_graph_provider.dart';

class KnowledgeGraphPage extends ConsumerStatefulWidget {
  const KnowledgeGraphPage({super.key});

  @override
  ConsumerState<KnowledgeGraphPage> createState() => _KnowledgeGraphPageState();
}

class _KnowledgeGraphPageState extends ConsumerState<KnowledgeGraphPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _entityFilter = '';
  bool _isGenerating = false;
  int _generationProcessed = 0;
  int _generationTotal = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _generateAll() async {
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws == null) return;
    setState(() {
      _isGenerating = true;
      _generationProcessed = 0;
      _generationTotal = 0;
    });
    try {
      final service = ref.read(knowledgeGraphServiceProvider);
      final result = await service.generateForAll(ws.id);
      final taskId = result['task_id'] as String?;
      final total = result['total_documents'] as int? ?? 0;

      if (taskId == null || taskId.isEmpty || total == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] as String? ?? 'No documents to process')),
          );
        }
        return;
      }

      setState(() {
        _generationTotal = total;
      });

      await _pollGenerationStatus(ws.id, taskId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Graph generation failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() {
        _isGenerating = false;
      });
    }
  }

  Future<void> _pollGenerationStatus(String wsId, String taskId) async {
    final service = ref.read(knowledgeGraphServiceProvider);
    while (mounted) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      try {
        final status = await service.getGenerationStatus(wsId, taskId);
        final state = status['status'] as String? ?? '';
        final processed = status['processed_documents'] as int? ?? 0;
        final entities = status['entities_created'] as int? ?? 0;
        final relations = status['relations_created'] as int? ?? 0;

        if (mounted) {
          setState(() => _generationProcessed = processed);
        }

        if (state == 'completed') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Graph generated: $entities entities, $relations relationships')),
            );
            ref.invalidate(graphDataProvider);
            ref.invalidate(entityListProvider);
          }
          return;
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to query progress: $e'), backgroundColor: Colors.orange),
          );
        }
        return;
      }
    }
  }

  Future<void> _resetGraph() async {
    final ws = ref.read(selectedWorkspaceProvider);
    if (ws == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear the knowledge graph?'),
        content: const Text('This operation will delete all entity and relationship data in the current workspace and cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Confirm clearing'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final service = ref.read(knowledgeGraphServiceProvider);
      await service.resetGraph(ws.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Knowledge graph cleared')),
        );
        ref.invalidate(graphDataProvider);
        ref.invalidate(entityListProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Clear failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showGenerationHistory() {
    ref.invalidate(generationHistoryProvider);
    showDialog(
      context: context,
      builder: (ctx) => _GenerationHistoryDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final ws = ref.watch(selectedWorkspaceProvider);
    final theme = Theme.of(context);

    if (ws == null) {
      return Center(
        child: Text(s.selectWorkspaceFirst,
            style: TextStyle(color: Colors.grey.shade500)),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(s.knowledgeGraph,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (_isGenerating)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          if (_generationTotal > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '$_generationProcessed/$_generationTotal',
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'More actions',
                    onSelected: (value) {
                      switch (value) {
                        case 'generate':
                          _generateAll();
                          break;
                        case 'history':
                          _showGenerationHistory();
                          break;
                        case 'reset':
                          _resetGraph();
                          break;
                        case 'refresh':
                          ref.invalidate(graphDataProvider);
                          ref.invalidate(entityListProvider);
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'generate',
                        enabled: !_isGenerating,
                        child: const ListTile(
                          leading: Icon(Icons.auto_fix_high),
                          title: Text('Generate knowledge graph'),
                          subtitle: Text('Extract entities and relationships from all documents', style: TextStyle(fontSize: 11)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'history',
                        child: ListTile(
                          leading: Icon(Icons.history),
                          title: Text('Build history'),
                          subtitle: Text('View historical build records and diagnostic information', style: TextStyle(fontSize: 11)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'refresh',
                        child: ListTile(
                          leading: Icon(Icons.refresh),
                          title: Text('Refresh graph'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'reset',
                        child: ListTile(
                          leading: Icon(Icons.delete_forever, color: Colors.red),
                          title: Text('Clear graph', style: TextStyle(color: Colors.red)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(s.knowledgeGraphDesc(ws.name),
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
              const SizedBox(height: 12),
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: s.graphView),
                  Tab(text: s.entityList),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _GraphViewTab(isGenerating: _isGenerating, onGenerate: _generateAll),
              _EntityListTab(
                filter: _entityFilter,
                onFilterChanged: (v) => setState(() => _entityFilter = v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GraphViewTab extends ConsumerWidget {
  final bool isGenerating;
  final VoidCallback onGenerate;

  const _GraphViewTab({required this.isGenerating, required this.onGenerate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final graphAsync = ref.watch(graphDataProvider);
    final s = S.of(context);

    return graphAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(s.loadFailed(e.toString()),
                style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
      data: (data) {
        if (data == null || data.nodes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hub_outlined,
                    size: 80, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(s.noGraphData,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: Colors.grey)),
                const SizedBox(height: 8),
                Text(
                  'Click the button below to extract entities and relationships from the document and generate a knowledge graph',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: isGenerating ? null : onGenerate,
                  icon: isGenerating
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.auto_fix_high),
                  label: Text(isGenerating ? 'Generating...' : 'Generate knowledge graph'),
                ),
                const SizedBox(height: 12),
                Text(
                  'The LLM model needs to be configured, and entities and relationships will be extracted from document chunks through LLM',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
              ],
            ),
          );
        }

        return _InteractiveGraph(data: data);
      },
    );
  }
}

class _InteractiveGraph extends ConsumerStatefulWidget {
  final GraphData data;
  const _InteractiveGraph({required this.data});

  @override
  ConsumerState<_InteractiveGraph> createState() => _InteractiveGraphState();
}

class _InteractiveGraphState extends ConsumerState<_InteractiveGraph> {
  final TransformationController _transformCtrl = TransformationController();
  String? _selectedNodeId;
  String? _hoveredNodeId;
  GraphEdge? _selectedEdge;
  final Set<String> _hiddenTypes = {};
  String? _draggingNodeId;

  @override
  void dispose() {
    _transformCtrl.dispose();
    super.dispose();
  }

  Offset _screenToGraph(Offset screenPos) {
    final matrix = _transformCtrl.value;
    final inverted = Matrix4.inverted(matrix);
    return MatrixUtils.transformPoint(inverted, screenPos);
  }

  GraphNode? _hitTestNode(Offset graphPos, List<GraphNode> nodes) {
    for (final node in nodes) {
      if ((node.position - graphPos).distance < 20) return node;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    final visibleNodes = widget.data.nodes
        .where((n) => !_hiddenTypes.contains(n.entityType))
        .toList();
    final visibleNodeIds = visibleNodes.map((n) => n.id).toSet();
    final visibleEdges = widget.data.edges
        .where((e) => visibleNodeIds.contains(e.source) && visibleNodeIds.contains(e.target))
        .toList();

    if (visibleNodes.isEmpty && widget.data.nodes.isNotEmpty) {
      return Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.filter_alt_outlined, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text('There is no data under the current filter conditions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey)),
                const SizedBox(height: 8),
                Text('Try switching to "All Layers" or canceling type filtering',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _hiddenTypes.clear()),
                  icon: const Icon(Icons.visibility),
                  label: const Text('Show all types'),
                ),
              ],
            ),
          ),
          Positioned(
            left: 12, top: 12,
            child: _LayerToggleBar(),
          ),
          Positioned(
            right: 12, top: 12,
            child: _FilterableLegend(
              allNodes: widget.data.nodes,
              hiddenTypes: _hiddenTypes,
              onToggleType: (type) {
                setState(() {
                  if (_hiddenTypes.contains(type)) {
                    _hiddenTypes.remove(type);
                  } else {
                    _hiddenTypes.add(type);
                  }
                });
              },
            ),
          ),
        ],
      );
    }

    final selectedNode = _selectedNodeId != null
        ? visibleNodes
            .where((n) => n.id == _selectedNodeId)
            .firstOrNull
        : null;

    return Stack(
      children: [
        InteractiveViewer(
          transformationController: _transformCtrl,
          minScale: 0.1,
          maxScale: 4.0,
          boundaryMargin: const EdgeInsets.all(500),
          panEnabled: _draggingNodeId == null,
          child: GestureDetector(
            onTapUp: (details) => _handleTap(details.localPosition, visibleNodes),
            onPanStart: (details) {
              final graphPos = _screenToGraph(details.localPosition);
              final node = _hitTestNode(graphPos, visibleNodes);
              if (node != null) {
                setState(() {
                  _draggingNodeId = node.id;
                  _selectedNodeId = node.id;
                  _selectedEdge = null;
                });
              }
            },
            onPanUpdate: (details) {
              if (_draggingNodeId == null) return;
              final graphPos = _screenToGraph(details.localPosition);
              final node = visibleNodes.where((n) => n.id == _draggingNodeId).firstOrNull;
              if (node != null) {
                setState(() {
                  node.position = graphPos;
                  node.velocity = Offset.zero;
                });
              }
            },
            onPanEnd: (_) {
              setState(() => _draggingNodeId = null);
            },
            child: CustomPaint(
              size: const Size(800, 600),
              painter: _GraphPainter(
                nodes: visibleNodes,
                edges: visibleEdges,
                selectedNodeId: _selectedNodeId,
                hoveredNodeId: _hoveredNodeId,
                theme: Theme.of(context),
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: _LayerToggleBar(),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: _FilterableLegend(
            allNodes: widget.data.nodes,
            hiddenTypes: _hiddenTypes,
            onToggleType: (type) {
              setState(() {
                if (_hiddenTypes.contains(type)) {
                  _hiddenTypes.remove(type);
                } else {
                  _hiddenTypes.add(type);
                }
              });
            },
          ),
        ),
        if (selectedNode != null)
          Positioned(
            left: 12,
            bottom: 12,
            child: _NodeInfoCard(
              node: selectedNode,
              edges: visibleEdges,
              allNodes: visibleNodes,
              onClose: () => setState(() => _selectedNodeId = null),
              onEdit: () => _showEditEntityDialog(selectedNode),
              onDelete: () => _confirmDeleteEntity(selectedNode),
            ),
          ),
        if (_selectedEdge != null && selectedNode == null)
          Positioned(
            left: 12,
            bottom: 12,
            child: _EdgeInfoCard(
              edge: _selectedEdge!,
              allNodes: visibleNodes,
              onClose: () => setState(() => _selectedEdge = null),
              onEdit: () => _showEditRelationDialog(_selectedEdge!),
              onDelete: () => _confirmDeleteRelation(_selectedEdge!),
            ),
          ),
        Positioned(
          right: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              '${s.nodes}: ${visibleNodes.length}/${widget.data.nodes.length}  |  ${s.edges}: ${visibleEdges.length}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ),
      ],
    );
  }

  void _handleTap(Offset localPosition, List<GraphNode> visibleNodes) {
    final matrix = _transformCtrl.value;
    final inverted = Matrix4.inverted(matrix);
    final transformed = MatrixUtils.transformPoint(inverted, localPosition);

    String? tappedId;
    for (final node in visibleNodes) {
      if ((node.position - transformed).distance < 20) {
        tappedId = node.id;
        break;
      }
    }

    if (tappedId != null) {
      setState(() {
        _selectedNodeId = tappedId;
        _selectedEdge = null;
      });
      return;
    }

    final nodeMap = {for (final n in visibleNodes) n.id: n};
    final visibleNodeIds = visibleNodes.map((n) => n.id).toSet();
    final visibleEdges = widget.data.edges
        .where((e) => visibleNodeIds.contains(e.source) && visibleNodeIds.contains(e.target))
        .toList();
    GraphEdge? tappedEdge;
    for (final edge in visibleEdges) {
      final src = nodeMap[edge.source];
      final tgt = nodeMap[edge.target];
      if (src == null || tgt == null) continue;
      final dist = _pointToSegmentDistance(transformed, src.position, tgt.position);
      if (dist < 12) {
        tappedEdge = edge;
        break;
      }
    }

    setState(() {
      _selectedNodeId = null;
      _selectedEdge = tappedEdge;
    });
  }

  double _pointToSegmentDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final t = (ap.dx * ab.dx + ap.dy * ab.dy) / (ab.dx * ab.dx + ab.dy * ab.dy);
    final clamped = t.clamp(0.0, 1.0);
    final closest = Offset(a.dx + clamped * ab.dx, a.dy + clamped * ab.dy);
    return (p - closest).distance;
  }

  String? get _currentWorkspaceId {
    final ws = ref.read(selectedWorkspaceProvider);
    return ws?.id;
  }

  void _showEditEntityDialog(GraphNode node) {
    final nameCtl = TextEditingController(text: node.label);
    String selectedType = node.entityType;
    const entityTypes = ['person', 'organization', 'concept', 'technology', 'location', 'event', 'document', 'other'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit entity'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(labelText: 'Entity name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: entityTypes.contains(selectedType) ? selectedType : 'other',
                decoration: const InputDecoration(labelText: 'Entity type'),
                items: entityTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedType = v ?? 'other'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final wsId = _currentWorkspaceId;
                if (wsId == null) return;
                Navigator.pop(ctx);
                try {
                  final service = ref.read(knowledgeGraphServiceProvider);
                  await service.updateEntity(wsId, node.id,
                    name: nameCtl.text,
                    entityType: selectedType,
                  );
                  ref.invalidate(graphDataProvider);
                  ref.invalidate(entityListProvider);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteEntity(GraphNode node) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entity'),
        content: Text('Delete entity "${node.label}"?\nThis will also delete its relationships and cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final wsId = _currentWorkspaceId;
              if (wsId == null) return;
              Navigator.pop(ctx);
              try {
                final service = ref.read(knowledgeGraphServiceProvider);
                final result = await service.deleteEntity(wsId, node.id);
                setState(() {
                  _selectedNodeId = null;
                  _selectedEdge = null;
                });
                ref.invalidate(graphDataProvider);
                ref.invalidate(entityListProvider);
                if (mounted) {
                  final relCount = result['relations_removed'] ?? 0;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('The entity "${node.label}" and the relationship $relCount have been deleted')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Confirm deletion'),
          ),
        ],
      ),
    );
  }

  void _showEditRelationDialog(GraphEdge edge) {
    final typeCtl = TextEditingController(text: edge.relation);
    double weightValue = edge.weight;
    final descCtl = TextEditingController(text: edge.description ?? '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Editing relationships'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: typeCtl,
                decoration: const InputDecoration(labelText: 'Relationship type'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Confidence: ${(weightValue * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 13)),
                  Expanded(
                    child: Slider(
                      value: weightValue,
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      onChanged: (v) => setDialogState(() => weightValue = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descCtl,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'A short description of the relationship',
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final wsId = _currentWorkspaceId;
                if (wsId == null) return;
                Navigator.pop(ctx);
                try {
                  final service = ref.read(knowledgeGraphServiceProvider);
                  await service.updateRelation(wsId, edge.id,
                    relationType: typeCtl.text,
                    weight: weightValue,
                    description: descCtl.text.isEmpty ? null : descCtl.text,
                  );
                  setState(() => _selectedEdge = null);
                  ref.invalidate(graphDataProvider);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteRelation(GraphEdge edge) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete relationship'),
        content: Text('Are you sure you want to delete the relationship "${edge.relation}"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final wsId = _currentWorkspaceId;
              if (wsId == null) return;
              Navigator.pop(ctx);
              try {
                final service = ref.read(knowledgeGraphServiceProvider);
                await service.deleteRelation(wsId, edge.id);
                setState(() => _selectedEdge = null);
                ref.invalidate(graphDataProvider);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Relationship deleted')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Confirm deletion'),
          ),
        ],
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final String? selectedNodeId;
  final String? hoveredNodeId;
  final ThemeData theme;

  _GraphPainter({
    required this.nodes,
    required this.edges,
    this.selectedNodeId,
    this.hoveredNodeId,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nodeMap = {for (final n in nodes) n.id: n};

    for (final edge in edges) {
      final src = nodeMap[edge.source];
      final tgt = nodeMap[edge.target];
      if (src == null || tgt == null) continue;

      final isHighlighted = selectedNodeId != null &&
          (edge.source == selectedNodeId || edge.target == selectedNodeId);

      final edgePaint = Paint()
        ..color = isHighlighted
            ? theme.colorScheme.primary.withValues(alpha: 0.6)
            : Colors.grey.withValues(alpha: 0.25)
        ..strokeWidth = isHighlighted ? 2.0 : 1.0
        ..style = PaintingStyle.stroke;

      canvas.drawLine(src.position, tgt.position, edgePaint);

      final mid = Offset(
        (src.position.dx + tgt.position.dx) / 2,
        (src.position.dy + tgt.position.dy) / 2,
      );
      if (isHighlighted && edge.relation.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: edge.relation,
            style: TextStyle(
              fontSize: 9,
              color: theme.colorScheme.primary.withValues(alpha: 0.8),
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: mid, width: tp.width + 8, height: tp.height + 4),
            const Radius.circular(4),
          ),
          Paint()..color = theme.colorScheme.surface.withValues(alpha: 0.9),
        );
        tp.paint(canvas,
            mid - Offset(tp.width / 2, tp.height / 2));
      }
    }

    for (final node in nodes) {
      final isSelected = node.id == selectedNodeId;
      final radius = isSelected ? 16.0 : 12.0;

      if (isSelected) {
        canvas.drawCircle(
          node.position,
          radius + 4,
          Paint()
            ..color = node.color.withValues(alpha: 0.2)
            ..style = PaintingStyle.fill,
        );
      }

      canvas.drawCircle(
        node.position,
        radius,
        Paint()
          ..color = node.color
          ..style = PaintingStyle.fill,
      );

      canvas.drawCircle(
        node.position,
        radius,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.3)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: node.label.length > 15
              ? '${node.label.substring(0, 15)}...'
              : node.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: theme.brightness == Brightness.dark
                ? Colors.white
                : Colors.black87,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout(maxWidth: 120);

      final bgRect = Rect.fromCenter(
        center: node.position + Offset(0, radius + 10),
        width: tp.width + 6,
        height: tp.height + 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
        Paint()..color = theme.colorScheme.surface.withValues(alpha: 0.85),
      );

      tp.paint(
        canvas,
        node.position + Offset(-tp.width / 2, radius + 10 - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) => true;
}

class _LayerToggleBar extends ConsumerWidget {
  static const _layerConfig = <String, (String, Color, IconData)>{
    'document': ('document network', Colors.blue, Icons.description_outlined),
    'semantic': ('Semantic graph', Colors.green, Icons.hub_outlined),
    'knowledge': ('Knowledge graph', Colors.deepPurple, Icons.psychology_outlined),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedLayers = ref.watch(selectedGraphLayersProvider);
    final graphAsync = ref.watch(graphDataProvider);
    final theme = Theme.of(context);

    final layerCounts = <String, int>{};
    final data = graphAsync.valueOrNull;
    if (data != null) {
      for (final node in data.nodes) {
        final layer = node.graphLayer ?? 'knowledge';
        layerCounts[layer] = (layerCounts[layer] ?? 0) + 1;
      }
    }

    return Card(
      elevation: 2,
      color: theme.colorScheme.surface.withAlpha(240),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: _layerConfig.entries.map((entry) {
            final key = entry.key;
            final (label, color, icon) = entry.value;
            final isActive = selectedLayers.contains(key);
            final count = layerCounts[key] ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FilterChip(
                avatar: Icon(icon, size: 16, color: isActive ? color : Colors.grey),
                label: Text(
                  count > 0 ? '$label ($count)' : label,
                  style: const TextStyle(fontSize: 11),
                ),
                selected: isActive,
                selectedColor: color.withAlpha(40),
                checkmarkColor: color,
                onSelected: (selected) {
                  final current = Set<String>.from(ref.read(selectedGraphLayersProvider));
                  if (selected) {
                    current.add(key);
                  } else {
                    if (current.length > 1) current.remove(key);
                  }
                  ref.read(selectedGraphLayersProvider.notifier).state = current;
                },
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _FilterableLegend extends StatelessWidget {
  final List<GraphNode> allNodes;
  final Set<String> hiddenTypes;
  final ValueChanged<String> onToggleType;

  const _FilterableLegend({
    required this.allNodes,
    required this.hiddenTypes,
    required this.onToggleType,
  });

  @override
  Widget build(BuildContext context) {
    final typeCounts = <String, int>{};
    for (final n in allNodes) {
      typeCounts[n.entityType] = (typeCounts[n.entityType] ?? 0) + 1;
    }
    if (typeCounts.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Type filtering', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          ...typeCounts.entries.take(10).map((entry) {
            final type = entry.key;
            final count = entry.value;
            final sampleNode = allNodes.firstWhere((n) => n.entityType == type);
            final isHidden = hiddenTypes.contains(type);
            return InkWell(
              onTap: () => onToggleType(type),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isHidden ? Colors.grey.shade300 : sampleNode.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '$type ($count)',
                        style: TextStyle(
                          fontSize: 11,
                          color: isHidden ? Colors.grey.shade400 : null,
                          decoration: isHidden ? TextDecoration.lineThrough : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _NodeInfoCard extends StatelessWidget {
  final GraphNode node;
  final List<GraphEdge> edges;
  final List<GraphNode> allNodes;
  final VoidCallback onClose;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _NodeInfoCard({
    required this.node,
    required this.edges,
    required this.allNodes,
    required this.onClose,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final nodeMap = {for (final n in allNodes) n.id: n};
    final related = edges
        .where((e) => e.source == node.id || e.target == node.id)
        .toList();
    final incomingCount = related.where((e) => e.target == node.id).length;
    final outgoingCount = related.where((e) => e.source == node.id).length;

    return Container(
      width: 320,
      constraints: const BoxConstraints(maxHeight: 400),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12)
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: node.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(node.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              if (onEdit != null)
                InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.edit_outlined, size: 16, color: theme.colorScheme.primary),
                  ),
                ),
              if (onDelete != null)
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                  ),
                ),
              const SizedBox(width: 4),
              InkWell(onTap: onClose, child: const Icon(Icons.close, size: 18)),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: node.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(node.entityType,
                style: TextStyle(fontSize: 11, color: node.color, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.arrow_downward, size: 12, color: Colors.green.shade400),
              const SizedBox(width: 2),
              Text('Enter: $incomingCount', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              const SizedBox(width: 12),
              Icon(Icons.arrow_upward, size: 12, color: Colors.blue.shade400),
              const SizedBox(width: 2),
              Text('Out: $outgoingCount', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              const SizedBox(width: 12),
              Icon(Icons.link, size: 12, color: Colors.grey.shade500),
              const SizedBox(width: 2),
              Text('Total: ${related.length}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
          if (node.documentId != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.description_outlined, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('${s.document}: ${node.documentId!.substring(0, 8)}...',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ),
              ],
            ),
          ],
          if (related.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Text(s.relatedEntities,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: related.take(15).map((e) {
                    final isOutgoing = e.source == node.id;
                    final otherId = isOutgoing ? e.target : e.source;
                    final other = nodeMap[otherId];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        children: [
                          Icon(
                            isOutgoing ? Icons.arrow_forward : Icons.arrow_back,
                            size: 10,
                            color: isOutgoing ? Colors.blue.shade300 : Colors.green.shade300,
                          ),
                          const SizedBox(width: 4),
                          Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              color: other?.color ?? Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                  text: other?.label ?? otherId,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                                ),
                                TextSpan(
                                  text: ' — ${e.relation}',
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                                ),
                                if (e.weight != 1.0)
                                  TextSpan(
                                    text: ' (${(e.weight * 100).toStringAsFixed(0)}%)',
                                    style: TextStyle(fontSize: 10, color: Colors.orange.shade400),
                                  ),
                              ]),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            if (related.length > 15)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('There are ${related.length - 15} relationships...',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
              ),
          ],
        ],
      ),
    );
  }
}

class _EdgeInfoCard extends StatelessWidget {
  final GraphEdge edge;
  final List<GraphNode> allNodes;
  final VoidCallback onClose;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _EdgeInfoCard({
    required this.edge,
    required this.allNodes,
    required this.onClose,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nodeMap = {for (final n in allNodes) n.id: n};
    final srcNode = nodeMap[edge.source];
    final tgtNode = nodeMap[edge.target];

    return Container(
      width: 300,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12)
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.link, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Relationship details',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              if (onEdit != null)
                InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.edit_outlined, size: 16, color: theme.colorScheme.primary),
                  ),
                ),
              if (onDelete != null)
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                  ),
                ),
              const SizedBox(width: 4),
              InkWell(onTap: onClose, child: const Icon(Icons.close, size: 18)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                if (srcNode != null) ...[
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(color: srcNode.color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(srcNode.label,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  ),
                ] else
                  Expanded(child: Text(edge.source, style: const TextStyle(fontSize: 12))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    children: [
                      Icon(Icons.arrow_forward, size: 14, color: theme.colorScheme.primary),
                      Text(edge.relation,
                          style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: theme.colorScheme.primary)),
                    ],
                  ),
                ),
                if (tgtNode != null) ...[
                  Expanded(
                    child: Text(tgtNode.label,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(color: tgtNode.color, shape: BoxShape.circle),
                  ),
                ] else
                  Expanded(child: Text(edge.target, style: const TextStyle(fontSize: 12), textAlign: TextAlign.end)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Relationship type: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(edge.relation,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade700)),
              ),
            ],
          ),
          if (edge.weight != 1.0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Confidence: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: edge.weight.clamp(0.0, 1.0),
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(
                        edge.weight > 0.7 ? Colors.green : edge.weight > 0.4 ? Colors.orange : Colors.red,
                      ),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${(edge.weight * 100).toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              ],
            ),
          ],
          if (edge.description != null && edge.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Relationship description', style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      )),
                      const SizedBox(height: 2),
                      Text(edge.description!,
                        style: TextStyle(fontSize: 12, height: 1.5, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (edge.sourceDocumentId != null && edge.sourceDocumentId!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.description_outlined, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text('Source document: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                Expanded(
                  child: Text(
                    edge.sourceDocumentId!.length > 8
                        ? '${edge.sourceDocumentId!.substring(0, 8)}...'
                        : edge.sourceDocumentId!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (srcNode != null && tgtNode != null) ...[
            const SizedBox(height: 4),
            Text(
              '${srcNode.entityType} → ${tgtNode.entityType}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }
}

class _EntityListTab extends ConsumerWidget {
  final String filter;
  final ValueChanged<String> onFilterChanged;

  const _EntityListTab({
    required this.filter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitiesAsync = ref.watch(entityListProvider);
    final s = S.of(context);
    final theme = Theme.of(context);

    return entitiesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(s.loadFailed(e.toString()),
            style: TextStyle(color: Colors.grey.shade600)),
      ),
      data: (entities) {
        if (entities.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.category_outlined,
                    size: 80, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(s.noEntities,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(color: Colors.grey)),
              ],
            ),
          );
        }

        final filtered = filter.isEmpty
            ? entities
            : entities
                .where((e) =>
                    e.name.toLowerCase().contains(filter.toLowerCase()) ||
                    e.entityType.toLowerCase().contains(filter.toLowerCase()))
                .toList();

        final typeGroups = <String, List<EntityInfo>>{};
        for (final e in filtered) {
          typeGroups.putIfAbsent(e.entityType, () => []).add(e);
        }

        return Stack(
          children: [
            Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: s.searchEntities,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: onFilterChanged,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('${filtered.length} ${s.entitiesCount}',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600)),
                  const Spacer(),
                  Text('${typeGroups.length} ${s.typesCount}',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade600)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: typeGroups.entries.map((entry) {
                  final type = entry.key;
                  final items = entry.value;
                  final sampleNode = GraphNode(
                    id: '',
                    label: '',
                    entityType: type,
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: sampleNode.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('$type (${items.length})',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                          ],
                        ),
                      ),
                      ...items.map((entity) => Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            child: ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    sampleNode.color.withValues(alpha: 0.15),
                                child: Text(
                                  entity.name.isNotEmpty
                                      ? entity.name[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    color: sampleNode.color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              title: Text(entity.name,
                                  style: const TextStyle(fontSize: 13)),
                              subtitle: entity.documentId != null
                                  ? Text(
                                      '${s.document}: ${entity.documentId!.substring(0, min(8, entity.documentId!.length))}...',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade500),
                                    )
                                  : null,
                              trailing: Text(
                                _formatDate(entity.createdAt),
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade500),
                              ),
                            ),
                          )),
                      const SizedBox(height: 4),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                heroTag: 'addEntity',
                onPressed: () => _showCreateEntityDialog(context, ref),
                tooltip: 'Add new entity',
                child: const Icon(Icons.add),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showCreateEntityDialog(BuildContext context, WidgetRef ref) {
    final nameCtl = TextEditingController();
    String selectedType = 'concept';
    const entityTypes = ['person', 'organization', 'concept', 'technology', 'location', 'event', 'document', 'other'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add new entity'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(labelText: 'Entity name'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: const InputDecoration(labelText: 'Entity type'),
                items: entityTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedType = v ?? 'concept'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (nameCtl.text.trim().isEmpty) return;
                final ws = ref.read(selectedWorkspaceProvider);
                if (ws == null) return;
                Navigator.pop(ctx);
                try {
                  final service = ref.read(knowledgeGraphServiceProvider);
                  await service.createEntity(ws.id,
                    name: nameCtl.text.trim(),
                    entityType: selectedType,
                  );
                  ref.invalidate(entityListProvider);
                  ref.invalidate(graphDataProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('The entity "${nameCtl.text.trim()}" was created successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Creation failed: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('create'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }
}

class _GenerationHistoryDialog extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(generationHistoryProvider);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.history, size: 22),
          const SizedBox(width: 8),
          const Text('Knowledge graph generation history'),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(generationHistoryProvider),
          ),
        ],
      ),
      content: SizedBox(
        width: 680,
        height: 460,
        child: historyAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Loading failed: $e')),
          data: (entries) {
            if (entries.isEmpty) {
              return const Center(
                child: Text('No generation record yet', style: TextStyle(color: Colors.grey)),
              );
            }
            return ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final e = entries[i];
                return _GenerationHistoryTile(entry: e, theme: theme);
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('close'),
        ),
      ],
    );
  }
}

class _GenerationHistoryTile extends StatelessWidget {
  final GenerationLogEntry entry;
  final ThemeData theme;

  const _GenerationHistoryTile({required this.entry, required this.theme});

  @override
  Widget build(BuildContext context) {
    final statusIcon = switch (entry.status) {
      'completed' => const Icon(Icons.check_circle, color: Colors.green, size: 18),
      'failed' => const Icon(Icons.error, color: Colors.red, size: 18),
      'running' => const SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2)),
      _ => const Icon(Icons.help_outline, size: 18),
    };

    final triggerLabel = switch (entry.triggerType) {
      'manual_single' => 'single document',
      'manual_batch' => 'batch',
      'auto' => 'automatic',
      _ => entry.triggerType,
    };

    String elapsed = '';
    if (entry.elapsedMs != null) {
      final sec = entry.elapsedMs! / 1000.0;
      elapsed = sec < 60
          ? '${sec.toStringAsFixed(1)}s'
          : '${(sec / 60).toStringAsFixed(1)}min';
    }

    String timeStr = '';
    try {
      final dt = DateTime.parse(entry.startedAt).toLocal();
      timeStr = '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {}

    return ExpansionTile(
      leading: statusIcon,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(triggerLabel,
                style: TextStyle(fontSize: 11, color: Colors.blue.shade700)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${entry.entitiesCreated} entity / ${entry.relationsCreated} relationship',
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Text(timeStr,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
          if (elapsed.isNotEmpty) ...[
            const SizedBox(width: 8),
            Icon(Icons.timer_outlined, size: 12, color: Colors.grey.shade500),
            const SizedBox(width: 2),
            Text(elapsed,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
          ],
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Status', entry.status),
              _detailRow('Trigger mode', triggerLabel),
              if (entry.documentId != null)
                _detailRow('Document ID', entry.documentId!),
              if (entry.llmProvider != null || entry.llmModel != null)
                _detailRow('model',
                    '${entry.llmProvider ?? ""}/${entry.llmModel ?? ""}'),
              _detailRow('Number of documents',
                  '${entry.processedDocuments}/${entry.totalDocuments}'),
              _detailRow('Entity/Relationship',
                  '${entry.entitiesCreated} / ${entry.relationsCreated}'),
              if (elapsed.isNotEmpty)
                _detailRow('Time consuming', elapsed),
              if (entry.errors.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Error:', style: TextStyle(
                    fontSize: 12, color: Colors.red.shade700,
                    fontWeight: FontWeight.w600)),
                for (final err in entry.errors)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Text(err,
                        style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
