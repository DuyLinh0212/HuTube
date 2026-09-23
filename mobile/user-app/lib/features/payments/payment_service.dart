import '../../auth.dart';

class PaymentService {
  PaymentService(this.auth);
  final AuthController auth;

  Future<Map<String, dynamic>> initiate(
    String planId, {
    bool autoRenew = false,
  }) => auth.protected(
    'POST',
    '/payments',
    body: {'planId': planId, 'autoRenew': autoRenew},
  );

  Future<List<Map<String, dynamic>>> mine() async => (await auth.protectedList(
    '/payments',
  )).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();

  Future<Map<String, dynamic>> get(String paymentId) =>
      auth.protected('GET', '/payments/${Uri.encodeComponent(paymentId)}');
}
