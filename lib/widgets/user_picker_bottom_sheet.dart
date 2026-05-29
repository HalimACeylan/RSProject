import 'package:flutter/material.dart';
import 'package:fridge_app/models/user_profile.dart';
import 'package:fridge_app/routes.dart';
import 'package:fridge_app/services/user_profile_service.dart';

/// Lists every saved profile in `users` and lets the user pick one to make
/// active. Opened from the welcome screen's "I have an account" button.
class UserPickerBottomSheet extends StatefulWidget {
  const UserPickerBottomSheet({super.key});

  @override
  State<UserPickerBottomSheet> createState() => _UserPickerBottomSheetState();
}

class _UserPickerBottomSheetState extends State<UserPickerBottomSheet> {
  static const Color _accent = Color(0xFF13EC13);

  bool _loading = true;
  List<UserProfile> _users = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final users = await UserProfileService.instance.listAll();
    if (!mounted) return;
    setState(() {
      _users = users;
      _loading = false;
    });
  }

  Future<void> _pick(UserProfile user) async {
    final id = user.id;
    if (id == null) return;
    final ok = await UserProfileService.instance.selectById(id);
    if (!mounted || !ok) return;
    Navigator.pop(context);
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.insideFridge,
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 48,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 4, 24, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Choose a profile',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Every completed setup is saved as a profile. Pick one to switch to it.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ),
          ),
          Flexible(child: _body()),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }
    if (_users.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Text(
              'No saved profiles yet.',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              "Tap Get Started on the welcome screen to set up your first profile.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      );
    }
    final activeId = UserProfileService.instance.current?.id;
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _users.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final u = _users[i];
        final isActive = u.id == activeId;
        return _UserTile(
          user: u,
          isActive: isActive,
          onTap: () => _pick(u),
        );
      },
    );
  }
}

class _UserTile extends StatelessWidget {
  final UserProfile user;
  final bool isActive;
  final VoidCallback onTap;

  const _UserTile({
    required this.user,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFF13EC13);
    final restrictionLabels = user.dietaryRestrictions
        .map((r) => r.label)
        .toList();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isActive ? accent.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? accent : Colors.grey.shade300,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: accent.withValues(alpha: 0.2),
                  child: Text(
                    user.sex == Sex.female ? '♀' : '♂',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.profileKey.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '${user.age} years • ${user.sex.label} • ${_relativeCreated(user.createdAt)}',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (isActive)
                  Icon(Icons.check_circle, color: accent, size: 22),
              ],
            ),
            if (restrictionLabels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: restrictionLabels
                    .map((l) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            l,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _relativeCreated(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    final months = (diff.inDays / 30).floor();
    return '${months}mo ago';
  }
}
