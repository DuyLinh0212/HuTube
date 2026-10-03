import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/widgets/scrollable_sheet.dart';
import 'package:user_app/core/widgets/hutube_widgets.dart';

void main() {
  testWidgets(
    'sheet form submit stays reachable with landscape keyboard and large text',
    (tester) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var submitted = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(640, 360),
              viewInsets: EdgeInsets.only(bottom: 160),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ScrollableSheet(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 6; i++)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Form field and description'),
                        ),
                      FilledButton(
                        onPressed: () => submitted = true,
                        child: const Text('Submit'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Submit'), 100);
      await tester.tap(find.text('Submit'));
      expect(submitted, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('state view recovery button scrolls into a short viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var recovered = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HuTubeStateView(
            icon: Icons.error_outline,
            title: 'Unable to load content',
            message: 'Retry to recover this page',
            actionLabel: 'Retry',
            onAction: () => recovered = true,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Retry'), 100);
    await tester.tap(find.text('Retry'));
    expect(recovered, isTrue);
    expect(tester.takeException(), isNull);
  });
}
