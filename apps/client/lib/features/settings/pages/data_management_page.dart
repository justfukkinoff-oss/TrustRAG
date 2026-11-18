import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/services/backend_manager.dart';
import '../../auth/providers/auth_provider.dart';

class DataManagementPage extends ConsumerStatefulWidget {
  const DataManagementPage({super.key});

  @override
  ConsumerState<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends ConsumerState<DataManagementPage> {
  Map<String, dynamic>? _dbInfo;
  bool _loading = false;
  String? _lastMessage;

  @override
  void initState() {
    super.initState();
    _loadDbInfo();
  }

  Future<void> _loadDbInfo() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get('/system/db-info');
      setState(() {
        _dbInfo = Map<String, dynamic>.from(resp.data);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _dbInfo = null;
        _loading = false;
        _lastMessage = 'Unable to obtain database information: $e';
      });
    }
  }

  Future<void> _backupDb() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.post('/system/backup-db');
      final path = resp.data['backup_path'] ?? 'unknown path';
      setState(() {
        _loading = false;
        _lastMessage = 'Backup successful: $path';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _lastMessage = 'Backup failed: $e';
      });
    }
  }

  Future<void> _resetDb() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red, size: 24),
            SizedBox(width: 8),
            Text('Confirm database reset'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This action will:', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('1. Automatically back up the current database'),
            Text('2. Delete existing database'),
            Text('3. Create a new empty database'),
            Text('4. Clear current login status'),
            SizedBox(height: 12),
            Text(
              'All workspaces, documents, conversation records, and model configurations will be lost. Backup files remain in the application data directory.',
              style: TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Confirm reset'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post('/system/reset-db');
      setState(() {
        _loading = false;
        _lastMessage = 'The database has been reset. Please log in again.';
      });
      if (mounted) {
        ref.read(authProvider.notifier).logout(clearData: true);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _lastMessage = 'Reset failed: $e';
      });
    }
  }

  Future<void> _resetLoginState() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset login status'),
        content: const Text('This will sign out all accounts.\nYour account data will not be changed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
            child: const Text('Confirm reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ApiClient.clearAllAccountData();
    final accounts = await ApiClient.getSavedAccounts();
    for (final email in accounts) {
      await ApiClient.removeAccount(email);
    }
    if (mounted) {
      ref.read(authProvider.notifier).logout();
      context.go('/login');
    }
  }

  Future<void> _clearAllAccounts() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red.shade900, size: 24),
            const SizedBox(width: 8),
            const Text('Clear all account data'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This action will:', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('1. Stop the local backend'),
            Text('2. Delete the local data directories of all accounts'),
            Text('3. Clear all login status and account records'),
            SizedBox(height: 12),
            Text(
              'All account documents, conversation records, and databases will be deleted and cannot be restored.',
              style: TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade900),
            child: const Text('Confirm clear all'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      if (BackendManager.shouldRunEmbedded) {
        await BackendManager().stop();
      }
      final accounts = await ApiClient.getSavedAccounts();
      for (final email in accounts) {
        if (BackendManager.shouldRunEmbedded) {
          await BackendManager().deleteAccountData(email);
        }
        await ApiClient.removeAccount(email);
      }
      await ApiClient.clearAllAccountData();
      setState(() {
        _loading = false;
        _lastMessage = 'All account data has been cleared.';
      });
      if (mounted) {
        ref.read(authProvider.notifier).logout();
        context.go('/login');
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _lastMessage = 'Clear failed: $e';
      });
    }
  }

  Future<void> _validateToken() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final resp = await api.dio.get('/system/validate-token');
      final valid = resp.data['valid'] == true;
      setState(() {
        _loading = false;
        _lastMessage = valid ? 'Token is valid and user status is normal' : 'The token is invalid or the user does not exist. It is recommended to log in again.';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _lastMessage = 'Token verification failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local data management'),
      ),
      body: _loading && _dbInfo == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_lastMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _lastMessage!.contains('failed') || _lastMessage!.contains('invalid')
                            ? Colors.red.shade50
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _lastMessage!.contains('failed') || _lastMessage!.contains('invalid')
                              ? Colors.red.shade200
                              : Colors.green.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              _lastMessage!,
                              style: TextStyle(
                                fontSize: 13,
                                color: _lastMessage!.contains('failed') || _lastMessage!.contains('invalid')
                                    ? Colors.red.shade800
                                    : Colors.green.shade800,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _lastMessage!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
                              );
                            },
                            tooltip: 'Copy information',
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(() => _lastMessage = null),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  Text('Database information', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  if (_dbInfo != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _infoRow('Schema version', '${_dbInfo!['schema_version'] ?? 'Unknown'}'),
                            _infoRow('Database path', '${_dbInfo!['db_path'] ?? 'Unknown'}'),
                            _infoRow('Number of users', '${_dbInfo!['user_count'] ?? '?'}'),
                            _infoRow('Number of work areas', '${_dbInfo!['workspace_count'] ?? '?'}'),
                            _infoRow('Number of documents', '${_dbInfo!['document_count'] ?? '?'}'),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _loadDbInfo,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Refresh'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Unable to connect to local backend or this feature is only available in desktop mode',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),
                  Text('diagnostic tools', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),

                  _actionCard(
                    icon: Icons.verified_user,
                    title: 'Verify login status',
                    subtitle: 'Check whether the current Token is consistent with the database user',
                    onTap: _validateToken,
                    color: Colors.blue,
                  ),

                  const SizedBox(height: 8),

                  _actionCard(
                    icon: Icons.backup,
                    title: 'Back up database',
                    subtitle: 'Create a backup copy of the current database',
                    onTap: _backupDb,
                    color: Colors.teal,
                  ),

                  const SizedBox(height: 24),
                  Text('Dangerous operation', style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold, color: Colors.red,
                  )),
                  const SizedBox(height: 12),

                  _actionCard(
                    icon: Icons.delete_forever,
                    title: 'Reset database',
                    subtitle: 'Clear all local data and re-initialize (it will be automatically backed up first)',
                    onTap: _resetDb,
                    color: Colors.red,
                  ),

                  if (BackendManager.shouldRunEmbedded) ...[
                    const SizedBox(height: 8),
                    _actionCard(
                      icon: Icons.restart_alt,
                      title: 'Reset login status',
                      subtitle: 'Clear all account login status and start over',
                      onTap: _resetLoginState,
                      color: Colors.deepOrange,
                    ),
                    const SizedBox(height: 8),
                    _actionCard(
                      icon: Icons.cleaning_services,
                      title: 'Clear all account data',
                      subtitle: 'Delete the local data directory and login information of all accounts',
                      onTap: _clearAllAccounts,
                      color: Colors.red.shade900,
                    ),
                  ],

                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: _loading ? null : onTap,
      ),
    );
  }
}
