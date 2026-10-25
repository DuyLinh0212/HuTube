import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:user_app/auth.dart';
import 'package:user_app/features/payments/payment_service.dart';
import 'package:user_app/features/plans/plan_service.dart';
import 'package:user_app/features/moderation/moderation_service.dart';
import 'package:user_app/features/playlists/playlist_service.dart';
import 'auth_test.dart' show MemoryStore, jsonResponse, session;

void main() {
  final scenarios =
      <
        (
          String,
          String,
          String,
          Map<String, dynamic>?,
          Future<void> Function(AuthController),
        )
      >[
        (
          'payment initiation preserves renewal choice',
          'POST',
          '/payments',
          {'planId': 'plan-1', 'autoRenew': true},
          (a) async {
            await PaymentService(a).initiate('plan-1', autoRenew: true);
          },
        ),
        (
          'payment cancellation',
          'POST',
          '/payments/payment-1/cancel',
          {},
          (a) async {
            await PaymentService(a).cancelPayment('payment-1');
          },
        ),
        (
          'plan subscription',
          'POST',
          '/plans/plan-1/subscribe',
          {'autoRenew': false},
          (a) async {
            await PlanService(a).subscribe('plan-1');
          },
        ),
        (
          'shared plan invite trims email',
          'POST',
          '/plans/members/invite',
          {'email': 'user@example.com', 'allocatedStorage': 1024},
          (a) async {
            await PlanService(
              a,
            ).invite(' user@example.com ', allocatedStorage: 1024);
          },
        ),
        (
          'shared plan acceptance preserves paid cancellation confirmation',
          'POST',
          '/plans/members/member-1/accept',
          {'token': 'invite', 'confirmCancelPaidPlan': true},
          (a) async {
            await PlanService(a).acceptInvitation(
              'member-1',
              'invite',
              confirmCancelPaidPlan: true,
            );
          },
        ),
        (
          'leave shared plan',
          'POST',
          '/plans/members/leave',
          {},
          (a) async {
            await PlanService(a).leaveSharedPlan();
          },
        ),
        (
          'member storage can be reset',
          'PATCH',
          '/plans/members/member-1/storage',
          {'allocatedStorage': null},
          (a) async {
            await PlanService(a).updateMemberStorage('member-1', null);
          },
        ),
        (
          'video report trims description',
          'POST',
          '/videos/video-1/report',
          {'violationTypeId': 'spam', 'description': 'report'},
          (a) async {
            await ModerationService(a).reportVideo(
              videoId: 'video-1',
              violationTypeId: 'spam',
              description: ' report ',
            );
          },
        ),
        (
          'comment report',
          'POST',
          '/comments/comment-1/report',
          {'violationTypeId': 'spam', 'description': 'report'},
          (a) async {
            await ModerationService(a).reportComment(
              commentId: 'comment-1',
              violationTypeId: 'spam',
              description: 'report',
            );
          },
        ),
        (
          'playlist creation trims metadata',
          'POST',
          '/playlists',
          {
            'name': 'My playlist',
            'description': 'Notes',
            'visibility': 'private',
          },
          (a) async {
            await PlaylistService(
              a,
            ).create(name: ' My playlist ', description: ' Notes ');
          },
        ),
        (
          'playlist delete',
          'DELETE',
          '/playlists/list-1',
          null,
          (a) async {
            await PlaylistService(a).delete('list-1');
          },
        ),
      ];
  for (final scenario in scenarios) {
    for (final fail in [false, true]) {
      test(
        '${scenario.$1}: ${fail ? 'server failure surfaces' : 'authenticated contract'}',
        () async {
          var calls = 0;
          final client = MockClient((request) async {
            if (request.url.path.endsWith('/auth/refresh')) {
              return jsonResponse(session());
            }
            calls++;
            expect(request.method, scenario.$2);
            expect(request.url.path, '/api/v1${scenario.$3}');
            expect(request.headers['Authorization'], startsWith('Bearer '));
            if (scenario.$4 != null) {
              expect(jsonDecode(request.body), scenario.$4);
            }
            return fail
                ? jsonResponse({'code': 'FAILED'}, 503)
                : jsonResponse({});
          });
          final auth = AuthController(
            ApiClient(baseUrl: 'https://mobile.test/api/v1', client: client),
            MemoryStore('refresh'),
          );
          await auth.restore();
          if (fail) {
            await expectLater(
              scenario.$5(auth),
              throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 503)),
            );
          } else {
            await scenario.$5(auth);
          }
          expect(calls, 1, reason: 'Writes must not be retried automatically');
          auth.dispose();
          client.close();
        },
      );
    }
  }
}
