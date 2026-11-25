import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/admin_roles.dart';
import '../../services/api_service.dart';
import '../admin_kit.dart';

/// Account state used across the admin: pending / approved / suspended / denied.
String userState(Map<String, dynamic> user) {
  final state = user['account_state'] ?? user['approval_state'];
  if (state is String && state.trim().isNotEmpty) {
    return state.trim().toLowerCase();
  }
  if (user['is_suspended'] == true) return 'suspended';
  if (user['is_denied'] == true) return 'denied';
  return user['is_approved'] == true ? 'approved' : 'pending';
}

String userStateLabel(String state) => switch (state) {
      'approved' => 'Active',
      'denied' => 'Denied',
      'suspended' => 'Suspended',
      _ => 'Pending',
    };

Color userStateColor(String state) => switch (state) {
      'approved' => AC.green,
      'denied' => AC.red,
      'suspended' => AC.amber,
      _ => AC.yellow,
    };

Color roleColor(String role) => switch (role) {
      'owner' => AC.purple,
      'admin' => AC.accent,
      'support' => AC.blue,
      _ => AC.grey,
    };

String cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Every account action an admin can take. Each method returns true when the
/// account changed, so the caller knows to reload.
class UserActions {
  final BuildContext context;
  final ApiService api;
  final Map<String, dynamic>? viewer;

  UserActions(this.context, this.api, this.viewer);

  int _id(Map<String, dynamic> u) => (u['id'] as num).toInt();

  Future<bool> _run(Future<void> Function() call, String ok) async {
    try {
      await call();
      if (context.mounted) aToast(context, ok);
      return true;
    } catch (e) {
      if (context.mounted) aToast(context, cleanError(e), error: true);
      return false;
    }
  }

  Future<bool> approve(Map<String, dynamic> u) =>
      _run(() => api.approveUser(_id(u)), '${u['username']} approved');

  Future<bool> deny(Map<String, dynamic> u) async {
    final r = await aConfirm(
      context,
      title: 'Deny ${u['username']}?',
      message:
          'The account is marked as denied and the user may be emailed, depending on Settings.',
      confirmLabel: 'Deny',
      danger: true,
      noteHint: 'Optional note for the record',
    );
    if (r == null) return false;
    return _run(
        () => api.denyUser(_id(u), adminNote: r.note.isEmpty ? null : r.note),
        'Account denied');
  }

  Future<bool> restore(Map<String, dynamic> u) => _run(
      () => api.restoreUser(_id(u)), 'Account moved back to pending approval');

  Future<bool> suspend(Map<String, dynamic> u) async {
    final r = await aConfirm(
      context,
      title: 'Suspend ${u['username']}?',
      message:
          'Sign-in and API access stop immediately. You can lift the suspension later.',
      confirmLabel: 'Suspend',
      danger: true,
      noteHint: 'Reason (optional)',
    );
    if (r == null) return false;
    return _run(
        () => api.suspendUser(_id(u), reason: r.note.isEmpty ? null : r.note),
        'Account suspended');
  }

  Future<bool> unsuspend(Map<String, dynamic> u) =>
      _run(() => api.unsuspendUser(_id(u)), 'Suspension lifted');

  Future<bool> delete(Map<String, dynamic> u) async {
    final r = await aConfirm(
      context,
      title: 'Delete ${u['username']} permanently?',
      message:
          'This removes the account and cannot be undone. Their searches and credit history are affected too.',
      confirmLabel: 'Delete permanently',
      danger: true,
    );
    if (r == null) return false;
    return _run(() => api.deleteUser(_id(u)), 'Account deleted');
  }

  Future<bool> grantCredits(Map<String, dynamic> u) async {
    final amount = TextEditingController();
    final reason = TextEditingController();
    String? error;
    var busy = false;
    final ok = await showADialog<bool>(
      context,
      title: 'Grant credits',
      subtitle:
          'To ${u['username']} · current balance ${fmtInt(u['credit_balance'] ?? 0)}',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: AT.body,
              cursorColor: AC.accent,
              decoration: aInput(label: 'Credits to add'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reason,
              style: AT.body,
              cursorColor: AC.accent,
              decoration: aInput(label: 'Reason (saved in the credit ledger)'),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: AT.small.copyWith(color: AC.red)),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AButton('Cancel',
                    kind: AButtonKind.ghost,
                    onPressed: busy ? null : () => Navigator.pop(ctx, false)),
                const SizedBox(width: 8),
                AButton(
                  'Grant credits',
                  kind: AButtonKind.success,
                  busy: busy,
                  onPressed: () async {
                    final n = int.tryParse(amount.text.trim());
                    if (n == null || n <= 0) {
                      setS(() => error = 'Enter a whole number above 0.');
                      return;
                    }
                    if (reason.text.trim().isEmpty) {
                      setS(() => error = 'A reason is required.');
                      return;
                    }
                    setS(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await api.grantCredits(
                          userId: _id(u),
                          amount: n,
                          reason: reason.text.trim());
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) {
                        setS(() {
                          busy = false;
                          error = cleanError(e);
                        });
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    reason.dispose();
    if (ok == true && context.mounted) aToast(context, 'Credits granted');
    return ok == true;
  }

  Future<bool> editProfile(Map<String, dynamic> u) async {
    final o = {
      'username': '${u['username'] ?? ''}',
      'email': '${u['email'] ?? ''}',
      'phone': '${u['phone'] ?? ''}',
    };
    final username = TextEditingController(text: o['username']);
    final email = TextEditingController(text: o['email']);
    final phone = TextEditingController(text: o['phone']);
    String? error;
    var busy = false;
    final ok = await showADialog<bool>(
      context,
      title: 'Edit profile',
      subtitle: 'User #${u['id']} · saving never changes the role',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: username,
                style: AT.body,
                cursorColor: AC.accent,
                decoration: aInput(label: 'Username')),
            const SizedBox(height: 10),
            TextField(
                controller: email,
                style: AT.body,
                cursorColor: AC.accent,
                decoration: aInput(label: 'Email')),
            const SizedBox(height: 10),
            TextField(
                controller: phone,
                style: AT.body,
                cursorColor: AC.accent,
                decoration: aInput(label: 'Phone')),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: AT.small.copyWith(color: AC.red)),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AButton('Cancel',
                    kind: AButtonKind.ghost,
                    onPressed: busy ? null : () => Navigator.pop(ctx, false)),
                const SizedBox(width: 8),
                AButton(
                  'Save',
                  kind: AButtonKind.primary,
                  busy: busy,
                  onPressed: () async {
                    final un = username.text.trim();
                    final em = email.text.trim();
                    final ph = phone.text.trim();
                    if (un.length < 3) {
                      setS(() =>
                          error = 'Username needs at least 3 characters.');
                      return;
                    }
                    if (!em.contains('@')) {
                      setS(() => error = 'Enter a valid email address.');
                      return;
                    }
                    if (un == o['username'] &&
                        em == o['email'] &&
                        ph == o['phone']) {
                      Navigator.pop(ctx, false);
                      return;
                    }
                    setS(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      await api.updateUserProfileAdmin(
                        _id(u),
                        username: un != o['username'] ? un : null,
                        email: em != o['email'] ? em : null,
                        phone: ph != o['phone'] ? ph : null,
                      );
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) {
                        setS(() {
                          busy = false;
                          error = cleanError(e);
                        });
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
    username.dispose();
    email.dispose();
    phone.dispose();
    if (ok == true && context.mounted) aToast(context, 'Profile updated');
    return ok == true;
  }

  /// Owner-only, explicit and confirmed; the reason goes to the audit log.
  Future<bool> changeRole(Map<String, dynamic> u) async {
    final current = AdminRoles.roleOf(u);
    var selected = current;
    final reason = TextEditingController();
    String? error;
    var busy = false;
    const descriptions = {
      'user': 'Searches and downloads only',
      'support': 'Read-only admin access',
      'admin': 'Manages accounts ranked below admin',
      'owner': 'Full control, including roles',
    };
    final ok = await showADialog<bool>(
      context,
      title: 'Change role',
      subtitle: '${u['username']} is currently ${cap(current)}',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final role in const ['user', 'support', 'admin', 'owner'])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: selected == role ? AC.selected : AC.bg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                        color: selected == role ? AC.accent : AC.border),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setS(() => selected = role),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      child: Row(
                        children: [
                          Icon(
                              selected == role
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              size: 17,
                              color:
                                  selected == role ? AC.accent : AC.textMute),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(cap(role),
                                    style: AT.body
                                        .copyWith(fontWeight: FontWeight.w600)),
                                Text(descriptions[role]!, style: AT.mute),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            TextField(
              controller: reason,
              style: AT.body,
              cursorColor: AC.accent,
              decoration: aInput(label: 'Reason (saved in the audit log)'),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: AT.small.copyWith(color: AC.red)),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AButton('Cancel',
                    kind: AButtonKind.ghost,
                    onPressed: busy ? null : () => Navigator.pop(ctx, false)),
                const SizedBox(width: 8),
                AButton(
                  'Change role',
                  kind: AButtonKind.primary,
                  busy: busy,
                  onPressed: selected == current
                      ? null
                      : () async {
                          setS(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            await api.updateUserRole(_id(u), selected,
                                reason: reason.text);
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } catch (e) {
                            if (ctx.mounted) {
                              setS(() {
                                busy = false;
                                error = cleanError(e);
                              });
                            }
                          }
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    if (ok == true && context.mounted) {
      aToast(context, 'Role changed to ${cap(selected)}');
    }
    return ok == true;
  }
}
