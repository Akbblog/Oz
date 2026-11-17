import 'package:flutter_test/flutter_test.dart';
import 'package:business_scraper_app/core/admin_roles.dart';

Map<String, dynamic> u(int id, String role) => {'id': id, 'role': role};

void main() {
  final owner = u(1, 'owner');
  final owner2 = u(2, 'owner');
  final admin = u(3, 'admin');
  final admin2 = u(4, 'admin');
  final support = u(5, 'support');
  final user = u(6, 'user');

  test('admins cannot manage owners, peer admins or themselves', () {
    expect(AdminRoles.canManage(admin, owner), isFalse);
    expect(AdminRoles.canManage(admin, admin2), isFalse);
    expect(AdminRoles.canManage(admin, admin), isFalse);
    expect(AdminRoles.canManage(admin, support), isTrue);
    expect(AdminRoles.canManage(admin, user), isTrue);
  });

  test('owners manage admins but not peer owners', () {
    expect(AdminRoles.canManage(owner, admin), isTrue);
    expect(AdminRoles.canManage(owner, owner2), isFalse);
    expect(AdminRoles.canManage(owner, owner), isFalse);
  });

  test('support and users manage nobody', () {
    for (final viewer in [support, user]) {
      for (final target in [owner, admin, support, user, u(9, 'user')]) {
        expect(AdminRoles.canManage(viewer, target), isFalse);
      }
    }
  });

  test('profile edit allowed on lower ranks and on own account', () {
    expect(AdminRoles.canEditProfile(owner, owner), isTrue);
    expect(AdminRoles.canEditProfile(admin, admin), isTrue);
    expect(AdminRoles.canEditProfile(admin, owner), isFalse);
    expect(AdminRoles.canEditProfile(support, support), isFalse);
  });

  test('only owners change roles, never their own or another owner', () {
    expect(AdminRoles.canChangeRole(owner, admin), isTrue);
    expect(AdminRoles.canChangeRole(owner, user), isTrue);
    expect(AdminRoles.canChangeRole(owner, owner), isFalse);
    expect(AdminRoles.canChangeRole(owner, owner2), isFalse);
    expect(AdminRoles.canChangeRole(admin, user), isFalse);
  });

  test('legacy rows without a role fall back to is_admin', () {
    expect(AdminRoles.roleOf({'id': 7, 'is_admin': true}), 'admin');
    expect(AdminRoles.roleOf({'id': 7}), 'user');
    expect(AdminRoles.canManage(admin, {'id': 7, 'is_admin': true}), isFalse);
  });
}
