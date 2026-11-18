import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/workspace_provider.dart';
import 'workspace_members_page.dart';

class TeamManagementPage extends ConsumerStatefulWidget {
  final Workspace workspace;

  const TeamManagementPage({super.key, required this.workspace});

  @override
  ConsumerState<TeamManagementPage> createState() => _TeamManagementPageState();
}

class _TeamManagementPageState extends ConsumerState<TeamManagementPage> {
  late Workspace _workspace;

  @override
  void initState() {
    super.initState();
    _workspace = widget.workspace;
  }

  Future<void> _regenerateInviteCode() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Regenerate invitation code'),
        content: const Text('After regeneration, the old invitation code will become invalid. Confirm to continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(S.of(context).cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final newCode = await ref.read(workspaceProvider.notifier).regenerateInviteCode(_workspace.id);
    if (newCode != null && mounted) {
      setState(() {
        _workspace = Workspace(
          id: _workspace.id,
          name: _workspace.name,
          description: _workspace.description,
          type: _workspace.type,
          inviteCode: newCode,
          createdAt: _workspace.createdAt,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('New invitation code: $newCode')),
      );
    }
  }

  void _copyInviteCode() {
    final code = _workspace.inviteCode;
    if (code == null) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invitation code has been copied'), duration: Duration(seconds: 2)),
    );
  }

  void _showTransferOwnershipDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('transfer administrator'),
        content: const Text('This function will select the new administrator in the members list. After the transfer you will become an administrator.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(context).cancel)),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WorkspaceMembersPage()),
              );
            },
            child: const Text('Go to member management'),
          ),
        ],
      ),
    );
  }

  void _showDisbandDialog() {
    final confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disband the team', style: TextStyle(color: Colors.red)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This action is irreversible! All documents, conversations, and review records in the team will be permanently deleted.'),
            const SizedBox(height: 16),
            Text('Please enter the team name "${_workspace.name}" to confirm:', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: confirmController,
              decoration: InputDecoration(
                hintText: _workspace.name,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(S.of(context).cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (confirmController.text.trim() != _workspace.name) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Team names don\'t match')),
                );
                return;
              }
              try {
                final api = ref.read(apiClientProvider);
                await api.dio.delete('/workspaces/${_workspace.id}');
                await ref.read(workspaceProvider.notifier).loadWorkspaces();
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('The team has been disbanded')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Dismissal failed: $e')),
                  );
                }
              }
            },
            child: const Text('Confirm dissolution'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${_workspace.name} — Team settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                        child: Icon(Icons.groups, size: 28, color: theme.colorScheme.primary),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_workspace.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                            if (_workspace.description != null)
                              Text(_workspace.description!, style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.vpn_key),
                  title: const Text('Invitation code'),
                  subtitle: Text(
                    _workspace.inviteCode ?? 'None',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: 'Copy invitation code',
                        onPressed: _workspace.inviteCode != null ? _copyInviteCode : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Regenerate',
                        onPressed: _regenerateInviteCode,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('share invitation'),
                  subtitle: const Text('Send invitation code to team members'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    final code = _workspace.inviteCode ?? '';
                    Clipboard.setData(ClipboardData(
                      text: 'Invite you to join the TrustRAG team "${_workspace.name}" \n invitation code: $code',
                    ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invitation information has been copied to the clipboard')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.group),
                  title: const Text('Member management'),
                  subtitle: const Text('View and manage team members'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WorkspaceMembersPage()),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            color: Colors.red.shade50,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.swap_horiz, color: Colors.orange.shade700),
                  title: Text('transfer administrator', style: TextStyle(color: Colors.orange.shade700)),
                  subtitle: const Text('Transfer team ownership to other members'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showTransferOwnershipDialog,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Disband the team', style: TextStyle(color: Colors.red)),
                  subtitle: const Text('Permanently delete the team and all data'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showDisbandDialog,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
