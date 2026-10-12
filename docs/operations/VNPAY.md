# VNPay checkout

New paid-plan orders use the VNPay hosted payment page. The API creates a pending payment, signs the payment URL with HMAC-SHA512, and activates a plan only after validating a VNPay IPN callback and its amount.

## Local sandbox configuration

Copy the sandbox merchant values from the private `VNPay_Key.txt` file into `.env.local` as:

```dotenv
VnPay__TmnCode=...
VnPay__HashSecret=...
VnPay__PaymentUrl=https://sandbox.vnpayment.vn/paymentv2/vpcpay.html
VnPay__ReturnUrl=http://localhost:5080/api/v1/payments/vnpay/return
VnPay__FrontendReturnUrl=http://localhost:4200/payment/result
VnPay__PaymentExpiryMinutes=30
```

`.env.local` is ignored by Git. Keep the hash secret out of `appsettings*.json`, source files, and logs. The sample `.env.example` contains placeholders only.

## VNPay merchant settings

Set the VNPay IPN URL to the public HTTPS API endpoint:

```text
https://<public-api-host>/api/v1/payments/vnpay/ipn
```

VNPay must be able to reach this endpoint from its servers. A local API needs a public HTTPS tunnel for sandbox IPN testing. Keep the return URL configured for the environment; it is sent with each signed payment request.

Use the sandbox payment URL and test credentials for local development. Before production, replace the payment URL and credentials with the merchant's production values and set both callback destinations to HTTPS URLs. Do not switch environments by changing only one of the URL or credential values.

## Callback behavior

- `GET /api/v1/payments/vnpay/ipn` verifies the VNPay signature, merchant code, transaction reference, and exact VND amount. Replayed successful notifications are idempotent.
- `GET /api/v1/payments/vnpay/return` verifies the signed browser response and redirects to the configured user-web payment result page. It does not activate a plan; the browser return is not the settlement signal.
- The user-web result page reads the payment status from the authenticated API while the IPN is processed.
