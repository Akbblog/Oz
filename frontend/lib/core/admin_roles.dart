/// Client-side mirror of the backend's staff rank rules
/// (`ROLE_HIERARCHY` / `_require_outranks` in backend/main.py).
///
/// The backend is the authority; these helpers only decide which admin
/// controls to show so nobody is offered an action whose only outcome is 403.
class AdminRoles {
  AdminRoles._();

  static const Map<String, int> rank = {
    'owner': 3,
    'admin': 2,
    'support': 1,
    'user': 0,
  };

  /// Effective role of a user map (legacy rows may only carry `is_admin`).
  static String roleOf(Map<String, dynamic>? user) {
    final role = (user?['role'] ?? '').toString().toLowerCase();
    if (rank.containsKey(role)) return role;
    return user?['is_admin'] == true ? 'admin' : 'user';
  }

  static bool isSelf(Map<String, dynamic>? viewer, Map<String, dynamic> user) =>
      viewer != null && '${viewer['id']}' == '${user['id']}';

  /// Suspend / unsuspend / deny / restore / delete / edit someone else:
  /// viewer must be admin+ and rank strictly above the target.
  static bool canManage(
      Map<String, dynamic>? viewer, Map<String, dynamic> user) {
    final mine = rank[roleOf(viewer)]!;
    if (mine < rank['admin']! || isSelf(viewer, user)) return false;
    return mine > rank[roleOf(user)]!;
  }

  /// Profile fields (never the role): lower ranks, or your own account.
  static bool canEditProfile(
          Map<String, dynamic>? viewer, Map<String, dynamic> user) =>
      canManage(viewer, user) ||
      (isSelf(viewer, user) && rank[roleOf(viewer)]! >= rank['admin']!);

  /// Explicit role change: owners only, never self or another owner.
  static bool canChangeRole(
          Map<String, dynamic>? viewer, Map<String, dynamic> user) =>
      roleOf(viewer) == 'owner' && canManage(viewer, user);

  static String protectedNote(
      Map<String, dynamic>? viewer, Map<String, dynamic> user) {
    if (isSelf(viewer, user)) return 'This is your account';
    final role = roleOf(user);
    if (role == 'owner') return 'Owner account: protected';
    if (role == 'admin') return 'Only an owner can manage admins';
    return "Your role can't manage this account";
  }
}
