import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/ai_icon_helper.dart';
import '../providers/model_config_provider.dart';
import '../providers/embedding_config_provider.dart';
import '../providers/rerank_config_provider.dart';

class ModelConfigPage extends ConsumerStatefulWidget {
  const ModelConfigPage({super.key});

  @override
  ConsumerState<ModelConfigPage> createState() => _ModelConfigPageState();
}

class _ModelConfigPageState extends ConsumerState<ModelConfigPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    ref.read(modelConfigProvider.notifier).loadConfigs();
    ref.read(embeddingConfigProvider.notifier).load();
    ref.read(rerankConfigProvider.notifier).load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Model configuration'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.smart_toy), text: 'LLM model'),
            Tab(icon: Icon(Icons.data_array), text: 'Embedding model'),
            Tab(icon: Icon(Icons.sort), text: 'Rerank model'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          switch (_tabController.index) {
            case 0:
              _showLlmDialog();
              break;
            case 1:
              _showEmbeddingDialog();
              break;
            case 2:
              _showRerankDialog();
              break;
          }
        },
        child: const Icon(Icons.add),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLlmTab(),
          _buildEmbeddingTab(),
          _buildRerankTab(),
        ],
      ),
    );
  }

  // ── LLM Tab ──

  Widget _buildLlmTab() {
    final configs = ref.watch(modelConfigProvider);
    return configs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Loading failed: $e')),
      data: (list) {
        if (list.isEmpty) {
          return _buildEmptyState('LLM model', () => _showLlmDialog());
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (context, i) => _buildLlmCard(list[i]),
        );
      },
    );
  }

  Widget _buildLlmCard(ModelConfig cfg) {
    return Card(
      child: ListTile(
        leading: AIIconHelper.buildProviderAvatar(
          cfg.modelName.isNotEmpty ? cfg.modelName : cfg.provider,
          radius: 20,
          isDefault: cfg.isDefault,
        ),
        title: Row(children: [
          Text(cfg.modelName,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (cfg.isDefault) ...[
            const SizedBox(width: 8),
            _defaultBadge(),
          ],
        ]),
        subtitle: Text('${cfg.provider} · ${cfg.apiBaseUrl}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: 'Test connection',
              onPressed: () => _testLlmConnection(cfg),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _showLlmDialog(config: cfg),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () =>
                  ref.read(modelConfigProvider.notifier).deleteConfig(cfg.id),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testLlmConnection(ModelConfig cfg) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Testing connection...'), duration: Duration(seconds: 30)),
    );
    final result = await ref
        .read(modelConfigProvider.notifier)
        .testConnectionDetailed(cfg.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final success = result['success'] == true;
      final message = result['message'] ?? 'Unknown result';
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ));
      } else {
        _showErrorDialog('LLM connection test failed', message);
      }
    }
  }

  // ── Embedding Tab ──

  Widget _buildEmbeddingTab() {
    final configs = ref.watch(embeddingConfigProvider);
    return configs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Loading failed: $e')),
      data: (list) {
        if (list.isEmpty) {
          return _buildEmptyState('embedding model', () => _showEmbeddingDialog());
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (context, i) => _buildEmbeddingCard(list[i]),
        );
      },
    );
  }

  Widget _buildEmbeddingCard(EmbeddingConfig cfg) {
    return Card(
      child: ListTile(
        leading: AIIconHelper.buildProviderAvatar(
          cfg.modelName.isNotEmpty ? cfg.modelName : cfg.provider,
          radius: 20,
          isDefault: cfg.isDefault,
        ),
        title: Row(children: [
          Text(cfg.modelName,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (cfg.isDefault) ...[
            const SizedBox(width: 8),
            _defaultBadge(),
          ],
        ]),
        subtitle: Text(
            '${cfg.provider} · ${cfg.apiBaseUrl ?? ''} · dim: ${cfg.dimensions} · batch: ${cfg.batchSize}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: 'Test connection',
              onPressed: () => _testEmbeddingConnection(cfg),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _showEmbeddingDialog(config: cfg),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () =>
                  ref.read(embeddingConfigProvider.notifier).delete(cfg.id),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testEmbeddingConnection(EmbeddingConfig cfg) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Testing embedded connection...'),
          duration: Duration(seconds: 30)),
    );
    final result =
        await ref.read(embeddingConfigProvider.notifier).testConnection(cfg.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final success = result['success'] == true;
      final message = result['message'] ?? 'Unknown result';
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ));
      } else {
        _showErrorDialog('Embed model connection test failed', message);
      }
    }
  }

  // ── Rerank Tab ──

  Widget _buildRerankTab() {
    final configs = ref.watch(rerankConfigProvider);
    return configs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Loading failed: $e')),
      data: (list) {
        if (list.isEmpty) {
          return Column(
            children: [
              _buildRerankInfoCard(),
              Expanded(
                child: _buildEmptyState('Rerank model', () => _showRerankDialog()),
              ),
            ],
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) return _buildRerankInfoCard();
            return _buildRerankCard(list[i - 1]);
          },
        );
      },
    );
  }

  Widget _buildRerankInfoCard() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Card(
        elevation: 0,
        color: cs.primaryContainer.withAlpha(30),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.primaryContainer, width: 1),
        ),
        child: ExpansionTile(
          leading: Icon(Icons.info_outline, color: cs.primary, size: 20),
          title: Text(
            'What is the Rerank model?',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
          initiallyExpanded: false,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            _buildInfoSection(
              icon: Icons.architecture,
              title: 'Two-stage search architecture',
              content: 'TrustRAG searches in two stages: retrieval and reranking.\n'
                  '1. The embedding model quickly retrieves candidate documents from the knowledge base.\n'
                  '2. The reranking model (Rerank) rescores the candidate documents and ranks the most relevant results to the top.',
            ),
            const SizedBox(height: 12),
            _buildInfoSection(
              icon: Icons.compare_arrows,
              title: 'Difference Between Embedding vs Rerank Difference',
              content: 'Embedding model: Convert text into vectors and quickly retrieve them through vector similarity. The speed is fast but the accuracy is limited \n'
                  'Rerank model: compares the semantic relevance of queries and documents pairwise, with higher accuracy but slower speed \n'
                  'The best effect is achieved when the two are used together: quickly recall 30 articles first, and then fine-tune and retain the Top 5',
            ),
            const SizedBox(height: 12),
            _buildInfoSection(
              icon: Icons.lightbulb_outline,
              title: 'Recommended configuration',
              content: 'Jina Reranker v2: Good multilingual support, including Chinese.\n'
                  'Cohere Rerank v3.5: Excellent English effect, stable API \n'
                  'BAAI/bge-reranker-v2-m3: open source model, can be deployed locally\n\n'
                  'If no reranker is configured, search still works using the embedding model alone.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection({
    required IconData icon,
    required String title,
    required String content,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: cs.primary.withAlpha(180)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              )),
              const SizedBox(height: 4),
              Text(content, style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: cs.onSurface.withAlpha(180),
              )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRerankCard(RerankConfig cfg) {
    return Card(
      child: ListTile(
        leading: AIIconHelper.buildProviderAvatar(
          cfg.modelName.isNotEmpty ? cfg.modelName : cfg.provider,
          radius: 20,
          isDefault: cfg.isDefault,
        ),
        title: Row(children: [
          Text(cfg.modelName,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          if (cfg.isDefault) ...[
            const SizedBox(width: 8),
            _defaultBadge(),
          ],
        ]),
        subtitle: Text(
                      '${cfg.provider} · Retrieve ${cfg.initialRecallK} → Keep ${cfg.topN} · ${cfg.timeoutSecs}s${cfg.fallbackEnabled ? ' · Fallback enabled' : ''}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: 'Test connection',
              onPressed: () => _testRerankConnection(cfg),
            ),
            if (!cfg.isDefault)
              IconButton(
                icon: const Icon(Icons.star_outline, size: 20),
                tooltip: 'Set as default',
                onPressed: () => ref
                    .read(rerankConfigProvider.notifier)
                    .setDefault(cfg.id),
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _showRerankDialog(config: cfg),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () =>
                  ref.read(rerankConfigProvider.notifier).delete(cfg.id),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testRerankConnection(RerankConfig cfg) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Testing Rerank connection...'),
          duration: Duration(seconds: 30)),
    );
    final result =
        await ref.read(rerankConfigProvider.notifier).testConnection(cfg.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      final success = result['success'] == true;
      final message = result['message'] ?? 'Unknown result';
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ));
      } else {
        _showErrorDialog('Rerank model connection test failed', message);
      }
    }
  }

  // ── Error Dialog ──

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 24),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  message,
                  style: TextStyle(fontSize: 13, color: Colors.red.shade900, height: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Error message copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy error message'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('close'),
          ),
        ],
      ),
    );
  }

  // ── Shared Widgets ──

  Widget _defaultBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('Default',
          style: TextStyle(
              fontSize: 11,
              color: Colors.green,
              fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildEmptyState(String type, VoidCallback onAdd) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.model_training, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No $type configured yet',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: Colors.grey)),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text('Add$type'),
          ),
        ],
      ),
    );
  }

  // ── LLM Dialog ──

  String _endpointHint(String provider) {
    switch (provider) {
      case 'openai':
        return 'https://api.openai.com/v1';
      case 'anthropic':
        return 'https://api.anthropic.com/v1';
      case 'ollama':
        return 'http://localhost:11434/v1';
      default:
        return 'https://your-api.com/v1';
    }
  }

  void _showLlmDialog({ModelConfig? config}) {
    String selectedProvider = config?.provider ?? 'openai';
    final modelCtl = TextEditingController(text: config?.modelName ?? '');
    final endpointCtl =
        TextEditingController(text: config?.apiBaseUrl ?? '');
    final apiKeyCtl = TextEditingController();
    bool isDefault = config?.isDefault ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(config == null ? 'Add LLM model' : 'Edit LLM model'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedProvider,
                  decoration: const InputDecoration(labelText: 'Provider'),
                  items: ['openai', 'anthropic', 'ollama', 'custom']
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) {
                    setDialogState(() => selectedProvider = v ?? 'openai');
                    if (endpointCtl.text.isEmpty) {
                      endpointCtl.text = _endpointHint(selectedProvider);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: modelCtl,
                  decoration: InputDecoration(
                    labelText: 'Model name',
                    hintText: selectedProvider == 'openai'
                        ? 'Such as gpt-4o, gpt-4o-mini'
                        : selectedProvider == 'ollama'
                            ? 'Such as qwen2.5:7b'
                            : 'Such as claude-3-5-sonnet',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: endpointCtl,
                  decoration: InputDecoration(
                    labelText: 'API Endpoint',
                    hintText: _endpointHint(selectedProvider),
                    helperText: 'Just fill in /v1, no need to add /chat/completions',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiKeyCtl,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: config != null
                        ? 'Leave blank to make no changes'
                        : selectedProvider == 'ollama'
                            ? 'No need to fill in locally'
                            : 'sk-...',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Set as default'),
                  contentPadding: EdgeInsets.zero,
                  value: isDefault,
                  onChanged: (v) => setDialogState(() => isDefault = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final data = <String, dynamic>{
                  'name': '${modelCtl.text} ($selectedProvider)',
                  'provider': selectedProvider,
                  'model_name': modelCtl.text,
                  'api_base_url': endpointCtl.text,
                  'is_default': isDefault,
                };
                if (apiKeyCtl.text.isNotEmpty) {
                  data['api_key'] = apiKeyCtl.text;
                }
                bool ok;
                if (config == null) {
                  ok = await ref
                      .read(modelConfigProvider.notifier)
                      .createConfig(data);
                } else {
                  ok = await ref
                      .read(modelConfigProvider.notifier)
                      .updateConfig(config.id, data);
                }
                if (ok && ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(config == null ? 'create' : 'save'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Embedding Dialog ──

  void _showEmbeddingDialog({EmbeddingConfig? config}) {
    String selectedProvider = config?.provider ?? 'openai';
    final modelCtl = TextEditingController(text: config?.modelName ?? '');
    final endpointCtl =
        TextEditingController(text: config?.apiBaseUrl ?? '');
    final apiKeyCtl = TextEditingController();
    final dimensionsCtl = TextEditingController(
        text: config?.dimensions.toString() ?? '1536');
    final batchSizeCtl = TextEditingController(
        text: config?.batchSize.toString() ?? '10');
    bool isDefault = config?.isDefault ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(config == null ? 'Add embedding model' : 'Edit embedding model'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedProvider,
                  decoration: const InputDecoration(labelText: 'Provider'),
                  items: ['openai', 'ollama', 'local', 'custom']
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) {
                    setDialogState(() => selectedProvider = v ?? 'openai');
                    if (endpointCtl.text.isEmpty) {
                      endpointCtl.text = _endpointHint(selectedProvider);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: modelCtl,
                  decoration: InputDecoration(
                    labelText: 'Model name',
                    hintText: selectedProvider == 'openai'
                        ? 'Such as text-embedding-3-small'
                        : selectedProvider == 'ollama'
                            ? 'Such as nomic-embed-text'
                            : selectedProvider == 'local'
                                ? 'Such as nomic-embed-text'
                                : 'Such as Qwen3-Embedding-0.6B',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: endpointCtl,
                  decoration: InputDecoration(
                    labelText: 'API Endpoint',
                    hintText: _endpointHint(selectedProvider),
                    helperText: 'Compatible with the OpenAI /v1/embeddings interface',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiKeyCtl,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: config != null
                        ? 'Leave blank to make no changes'
                        : (selectedProvider == 'local' || selectedProvider == 'ollama')
                            ? 'No need to fill in locally'
                            : 'sk-...',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dimensionsCtl,
                  decoration: const InputDecoration(
                    labelText: 'vector dimensions',
                    helperText: 'OpenAI text-embedding-3-small is 1536',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: batchSizeCtl,
                  decoration: const InputDecoration(
                    labelText: 'batch size',
                    helperText: 'Maximum number of texts per request, default 10 (compatible with most APIs)',
                    helperMaxLines: 2,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Set as default'),
                  contentPadding: EdgeInsets.zero,
                  value: isDefault,
                  onChanged: (v) => setDialogState(() => isDefault = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final data = <String, dynamic>{
                  'name':
                      '${modelCtl.text} ($selectedProvider)',
                  'provider': selectedProvider,
                  'model_name': modelCtl.text,
                  'api_base_url': endpointCtl.text,
                  'dimensions':
                      int.tryParse(dimensionsCtl.text) ?? 1536,
                  'batch_size':
                      (int.tryParse(batchSizeCtl.text) ?? 10).clamp(1, 2048),
                  'is_default': isDefault,
                };
                if (apiKeyCtl.text.isNotEmpty) {
                  data['api_key'] = apiKeyCtl.text;
                }
                bool ok;
                if (config == null) {
                  ok = await ref
                      .read(embeddingConfigProvider.notifier)
                      .create(data);
                } else {
                  ok = await ref
                      .read(embeddingConfigProvider.notifier)
                      .update(config.id, data);
                }
                if (ok && ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(config == null ? 'create' : 'save'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Rerank Dialog ──

  String _rerankEndpointHint(String provider) {
    switch (provider) {
      case 'jina':
        return 'https://api.jina.ai/v1';
      case 'cohere':
        return 'https://api.cohere.ai/v1';
      case 'openai':
        return 'https://api.openai.com/v1';
      default:
        return 'https://your-rerank-api.com/v1';
    }
  }

  String _rerankModelHint(String provider) {
    switch (provider) {
      case 'jina':
        return 'Such as jina-reranker-v2-base-multilingual';
      case 'cohere':
        return 'Such as rerank-v3.5';
      case 'openai':
        return 'Such as gpt-4o-mini (chat-based rerank)';
      default:
        return 'Such as BAAI/bge-reranker-v2-m3';
    }
  }

  void _showRerankDialog({RerankConfig? config}) {
    String selectedProvider = config?.provider ?? 'jina';
    final modelCtl = TextEditingController(text: config?.modelName ?? '');
    final endpointCtl =
        TextEditingController(text: config?.apiBaseUrl ?? '');
    final apiKeyCtl = TextEditingController();
    final topNCtl = TextEditingController(
        text: config?.topN.toString() ?? '5');
    final recallKCtl = TextEditingController(
        text: config?.initialRecallK.toString() ?? '30');
    final timeoutCtl = TextEditingController(
        text: config?.timeoutSecs.toString() ?? '30');
    bool fallbackEnabled = config?.fallbackEnabled ?? true;
    bool isDefault = config?.isDefault ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(config == null ? 'Add Rerank model' : 'Edit the Rerank model'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedProvider,
                    decoration: const InputDecoration(labelText: 'Provider'),
                    items: ['jina', 'cohere', 'openai', 'custom']
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) {
                      setDialogState(() => selectedProvider = v ?? 'jina');
                      if (endpointCtl.text.isEmpty) {
                        endpointCtl.text =
                            _rerankEndpointHint(selectedProvider);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: modelCtl,
                    decoration: InputDecoration(
                      labelText: 'Model name',
                      hintText: _rerankModelHint(selectedProvider),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: endpointCtl,
                    decoration: InputDecoration(
                      labelText: 'API Endpoint',
                      hintText: _rerankEndpointHint(selectedProvider),
                      helperText: 'Compatible with /v1/rerank or /rerank interface',
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: apiKeyCtl,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: config != null ? 'Leave blank to make no changes' : 'your-api-key',
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('Retrieval parameters', style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    )),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: recallKCtl,
                          decoration: const InputDecoration(
                            labelText: 'Initial recall count',
                            helperText: 'Number of embedded search candidates (default 30)',
                            helperMaxLines: 2,
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: topNCtl,
                          decoration: const InputDecoration(
                            labelText: 'Number of rearranged reservations',
                            helperText: 'Keep Top N after rearrangement (default 5)',
                            helperMaxLines: 2,
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: timeoutCtl,
                    decoration: const InputDecoration(
                      labelText: 'Timeout (seconds)',
                      helperText: 'Rerank API request timeout (default 30 seconds)',
                      helperMaxLines: 2,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Automatic downgrade on failure'),
                    subtitle: const Text(
                      'Automatically fall back to embedded retrieval when Rerank call fails',
                      style: TextStyle(fontSize: 11),
                    ),
                    contentPadding: EdgeInsets.zero,
                    value: fallbackEnabled,
                    onChanged: (v) => setDialogState(() => fallbackEnabled = v),
                  ),
                  SwitchListTile(
                    title: const Text('Set as default'),
                    contentPadding: EdgeInsets.zero,
                    value: isDefault,
                    onChanged: (v) => setDialogState(() => isDefault = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final data = <String, dynamic>{
                  'name': '${modelCtl.text} ($selectedProvider)',
                  'provider': selectedProvider,
                  'model_name': modelCtl.text,
                  'api_base_url': endpointCtl.text,
                  'top_n': (int.tryParse(topNCtl.text) ?? 5).clamp(1, 100),
                  'initial_recall_k': (int.tryParse(recallKCtl.text) ?? 30).clamp(5, 200),
                  'timeout_secs': (int.tryParse(timeoutCtl.text) ?? 30).clamp(5, 300),
                  'fallback_enabled': fallbackEnabled,
                  'is_default': isDefault,
                };
                if (apiKeyCtl.text.isNotEmpty) {
                  data['api_key'] = apiKeyCtl.text;
                }
                final notifier = ref.read(rerankConfigProvider.notifier);
                bool ok;
                if (config == null) {
                  ok = await notifier.create(data);
                } else {
                  ok = await notifier.update(config.id, data);
                }
                if (ctx.mounted) {
                  if (ok) {
                    Navigator.pop(ctx);
                  } else {
                    final err = notifier.lastError ?? 'Save failed';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Rerank configuration failed to save: $err'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 5),
                      ),
                    );
                  }
                }
              },
              child: Text(config == null ? 'create' : 'save'),
            ),
          ],
        ),
      ),
    );
  }
}
