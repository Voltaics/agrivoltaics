import 'package:agrivoltaics_flutter_app/app_colors.dart';
import 'package:flutter/material.dart';
import '../../models/authorized_member_summary.dart';
import '../../services/member_directory_service.dart';
import 'dialogs/add_to_organization_dialog.dart';
import 'dialogs/edit_full_name_dialog.dart';

/// Single source of truth for "who is authorized and what's their org
/// status": one row per email in AUTHORIZED_EMAILS, showing whether they've
/// signed in yet and which organization(s) — if any — they belong to or
/// have a pending invite for. This is where full names are set/edited, and
/// where an admin can spot someone who's authorized but has never been
/// added to an organization (the "pending member" gap this page exists to
/// close).
class MemberDirectoryPage extends StatefulWidget {
  const MemberDirectoryPage({super.key});

  @override
  State<MemberDirectoryPage> createState() => _MemberDirectoryPageState();
}

class _MemberDirectoryPageState extends State<MemberDirectoryPage> {
  final _directoryService = MemberDirectoryService();
  Future<List<AuthorizedMemberSummary>>? _directoryFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _directoryFuture = _directoryService.loadDirectory();
    });
  }

  Future<void> _editName(AuthorizedMemberSummary member) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => EditFullNameDialog(
        userId: member.uid!,
        email: member.email,
        currentFullName: member.fullName,
      ),
    );
    if (changed == true) _refresh();
  }

  Future<void> _addToOrganization(AuthorizedMemberSummary member) async {
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AddToOrganizationDialog(member: member),
    );
    if (added == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${member.email} added to organization'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Member Directory'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: FutureBuilder<List<AuthorizedMemberSummary>>(
        future: _directoryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Error loading directory: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            );
          }

          final members = snapshot.data ?? [];

          if (members.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('No authorized emails configured.'),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: members.length,
              itemBuilder: (context, index) => _buildRow(members[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRow(AuthorizedMemberSummary member) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: member.hasSignedIn ? AppColors.primary : AppColors.textMuted,
        child: Text(
          member.resolvedName.isNotEmpty ? member.resolvedName[0].toUpperCase() : '?',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        member.resolvedName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            member.email,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            member.statusSummary,
            style: TextStyle(
              fontSize: 12,
              color: member.organizations.isEmpty ? AppColors.warning : AppColors.textMuted,
              fontWeight: member.organizations.isEmpty ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          if (member.pendingInvites.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Invited to: ${member.pendingInvites.map((o) => o.orgName).join(', ')}',
                style: const TextStyle(fontSize: 12, color: AppColors.info),
              ),
            ),
        ],
      ),
      isThreeLine: member.pendingInvites.isNotEmpty,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            color: AppColors.textMuted,
            onPressed: member.canEditName ? () => _editName(member) : null,
            tooltip: member.canEditName
                ? 'Edit full name'
                : 'This person needs to sign in or be invited before a name can be set',
          ),
          IconButton(
            icon: const Icon(Icons.group_add, size: 20),
            color: AppColors.primary,
            onPressed: () => _addToOrganization(member),
            tooltip: 'Add to organization',
          ),
        ],
      ),
    );
  }
}
