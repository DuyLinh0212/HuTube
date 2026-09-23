import '../../auth.dart';

class PlanService {
  PlanService(this.auth);
  final AuthController auth;

  Future<List<Map<String, dynamic>>> catalogue() async =>
      (await auth.api.requestList('GET', '/plans'))
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  Future<Map<String, dynamic>?> myPlan() async {
    final value = await auth.protected('GET', '/plans/my-plan');
    return value.isEmpty ? null : value;
  }

  Future<Map<String, dynamic>> share(String planId) =>
      auth.api.request('GET', '/plans/${Uri.encodeComponent(planId)}/share');

  Future<Map<String, dynamic>> get(String planId) =>
      auth.api.request('GET', '/plans/${Uri.encodeComponent(planId)}');

  Future<Map<String, dynamic>> subscribe(
    String planId, {
    bool autoRenew = false,
  }) => auth.protected(
    'POST',
    '/plans/${Uri.encodeComponent(planId)}/subscribe',
    body: {'autoRenew': autoRenew},
  );

  Future<Map<String, dynamic>> invite(String email, {int? allocatedStorage}) =>
      auth.protected(
        'POST',
        '/plans/members/invite',
        body: {
          'email': email.trim(),
          if (allocatedStorage != null) 'allocatedStorage': allocatedStorage,
        },
      );

  Future<Map<String, dynamic>> acceptInvitation(
    String memberId,
    String token,
  ) => auth.protected(
    'POST',
    '/plans/members/${Uri.encodeComponent(memberId)}/accept',
    body: {'token': token},
  );

  Future<void> removeMember(String memberId) async {
    await auth.protected(
      'DELETE',
      '/plans/members/${Uri.encodeComponent(memberId)}',
    );
  }

  Future<Map<String, dynamic>> updateMemberStorage(
    String memberId,
    int? allocatedStorage,
  ) => auth.protected(
    'PATCH',
    '/plans/members/${Uri.encodeComponent(memberId)}/storage',
    body: {'allocatedStorage': allocatedStorage},
  );

  Future<void> updateOwnerStorage(int? allocatedStorage) async {
    await auth.protected(
      'PATCH',
      '/plans/my-subscription/owner-storage',
      body: {'allocatedStorage': allocatedStorage},
    );
  }
}
