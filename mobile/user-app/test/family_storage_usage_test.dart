import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/localization/app_strings.dart';
import 'package:user_app/features/plans/family_storage_usage.dart';

void main() {
  const gb = 1024 * 1024 * 1024;
  setUp(() => AppStrings.currentLang.value = 'vi');

  test('allocation stays hidden until an invitation exists', () {
    expect(
      showPlanStorageAllocation({'maxMembers': 6, 'members': []}),
      isFalse,
    );
    expect(
      showPlanStorageAllocation({
        'maxMembers': 1,
        'members': [
          {'status': 'accepted'},
        ],
      }),
      isFalse,
    );
    expect(
      showPlanStorageAllocation({
        'maxMembers': 6,
        'members': [
          {'status': 'revoked'},
        ],
      }),
      isFalse,
    );
    expect(
      showPlanStorageAllocation({
        'maxMembers': 6,
        'members': [
          {'status': 'pending'},
        ],
      }),
      isTrue,
    );
    expect(
      showPlanStorageAllocation({
        'maxMembers': 6,
        'members': [
          {'status': 'accepted'},
        ],
      }),
      isTrue,
    );
    expect(
      showPlanStorageAllocation({
        'maxMembers': 6,
        'isSharedMember': true,
        'members': [
          {'status': 'accepted'},
        ],
      }),
      isFalse,
    );
  });

  test(
    'only owners see family usage, with accepted members or remaining billed media',
    () {
      final data = {
        'maxMembers': 6,
        'members': <Map>[],
        'storageUsageBreakdown': [
          {'userId': 'owner', 'isOwner': true, 'storageUsed': 2 * gb},
        ],
      };
      expect(showFamilyStorageUsage(data), isFalse);
      expect(
        showFamilyStorageUsage({
          ...data,
          'members': [
            {'status': 'accepted'},
          ],
        }),
        isTrue,
      );
      final former = {
        ...data,
        'storageUsageBreakdown': [
          {'userId': 'former', 'isOwner': false, 'storageUsed': gb},
        ],
      };
      expect(showFamilyStorageUsage(former), isTrue);
      expect(
        showFamilyStorageUsage({...former, 'isSharedMember': true}),
        isFalse,
      );
      expect(
        showFamilyStorageUsage({
          'members': [
            {'status': 'accepted'},
          ],
        }),
        isFalse,
      );
    },
  );

  testWidgets(
    'shows each person, zero usage and free space on a narrow dark surface',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: FamilyStorageUsage(
                totalBytes: 30 * gb,
                usedBytes: 5 * gb,
                onDark: true,
                usage: [
                  {'userId': 'owner', 'isOwner': true, 'storageUsed': 2 * gb},
                  {
                    'userId': 'alice',
                    'displayName': 'Alice with a long display name',
                    'isOwner': false,
                    'storageUsed': 3 * gb,
                  },
                  {
                    'userId': 'bob',
                    'displayName': 'Bob',
                    'isOwner': false,
                    'storageUsed': 0,
                  },
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Bạn (chủ gói)'), findsOneWidget);
      expect(find.text('Alice with a long display name'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('0 MB'), findsOneWidget);
      expect(find.text('Còn trống'), findsOneWidget);
      expect(find.text('25 GB'), findsOneWidget);
      final bar = tester.widget<SizedBox>(
        find.byKey(const ValueKey('family-storage-bar')),
      );
      final row = bar.child! as Row;
      final widths = row.children
          .cast<SizedBox>()
          .map((box) => box.width!)
          .toList();
      expect(widths.length, 3);
      expect(widths.reduce((a, b) => a + b), closeTo(328, 0.001));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reports over-capacity and former member usage without overflowing',
    (tester) async {
      AppStrings.currentLang.value = 'en';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FamilyStorageUsage(
              totalBytes: 2 * gb,
              usedBytes: 5 * gb,
              usage: [
                {'userId': 'owner', 'isOwner': true, 'storageUsed': gb},
                {
                  'userId': 'old',
                  'displayName': 'Former',
                  'isOwner': false,
                  'isFormerMember': true,
                  'storageUsed': 4 * gb,
                },
              ],
            ),
          ),
        ),
      );
      expect(find.text('You (plan owner)'), findsOneWidget);
      expect(find.text('Former (left the group)'), findsOneWidget);
      expect(find.text('Free space'), findsOneWidget);
      expect(find.text('0 MB'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
