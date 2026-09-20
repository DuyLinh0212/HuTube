using HuTube.Application.Payments;
using HuTube.Domain.Payments;
using HuTube.Domain.Videos;
using HuTube.Infrastructure.Payments;
using HuTube.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace HuTube.UnitTests;

public sealed class PaymentServiceTests : IDisposable
{
    private readonly HuTubeDbContext _db;
    private readonly PaymentService _service;
    private readonly SepayOptions _options;

    private sealed class MockPlanService : HuTube.Application.Plans.IPlanService
    {
        public Guid ActivatedPaymentId { get; private set; }
        public Guid ActivatedUserId { get; private set; }
        public Guid ActivatedPlanId { get; private set; }
        public bool ActivatePaidPlanAsyncCalled { get; private set; }

        public Task<Guid> ActivatePaidPlanAsync(Guid userId, Guid planId, Guid paymentId, bool autoRenew, CancellationToken ct = default)
        {
            ActivatePaidPlanAsyncCalled = true;
            ActivatedUserId = userId;
            ActivatedPlanId = planId;
            ActivatedPaymentId = paymentId;
            return Task.FromResult(Guid.NewGuid());
        }

        public Task<IReadOnlyList<HuTube.Application.Plans.PlanResponse>> GetPlansAsync(CancellationToken ct = default) => throw new NotImplementedException();
        public Task<IReadOnlyList<HuTube.Application.Plans.PlanResponse>> GetAdminPlansAsync(CancellationToken ct = default) => throw new NotImplementedException();
        public Task<HuTube.Application.Plans.PlanResponse> CreatePlanAsync(Guid actorUserId, HuTube.Application.Plans.CreatePlanRequest request, CancellationToken ct = default) => throw new NotImplementedException();
        public Task<HuTube.Application.Plans.PlanResponse> UpdatePlanAsync(Guid actorUserId, Guid planId, HuTube.Application.Plans.UpdatePlanRequest request, CancellationToken ct = default) => throw new NotImplementedException();
        public Task ArchivePlanAsync(Guid actorUserId, Guid planId, CancellationToken ct = default) => throw new NotImplementedException();
        public Task<HuTube.Application.Plans.PlanResponse> GetPlanByIdAsync(Guid planId, CancellationToken ct = default) => throw new NotImplementedException();
        public Task<HuTube.Application.Plans.PlanShareResponse> GetPlanShareAsync(Guid planId, CancellationToken ct = default) => throw new NotImplementedException();
        public Task<HuTube.Application.Plans.PlanDetailResponse?> GetMyPlanAsync(Guid userId, CancellationToken ct = default) => throw new NotImplementedException();
        public Task<long?> GetEffectiveStorageLimitAsync(Guid userId, CancellationToken ct = default) => throw new NotImplementedException();
        public Task<HuTube.Application.Plans.PlanResponse> SubscribeAsync(Guid userId, Guid planId, HuTube.Application.Plans.PlanSubscriptionRequest request, CancellationToken ct = default) => throw new NotImplementedException();
        public Task<HuTube.Application.Plans.PlanMemberResponse> InviteMemberAsync(Guid ownerUserId, string email, long? allocatedStorage, CancellationToken ct = default) => throw new NotImplementedException();
        public Task<HuTube.Application.Plans.PlanMemberResponse> AcceptInvitationAsync(Guid userId, Guid memberId, string token, CancellationToken ct = default) => throw new NotImplementedException();
        public Task RemoveMemberAsync(Guid ownerUserId, Guid memberId, CancellationToken ct = default) => throw new NotImplementedException();
        public Task<HuTube.Application.Plans.PlanMemberResponse> UpdateMemberStorageAsync(Guid ownerUserId, Guid memberId, long? allocatedStorage, CancellationToken ct = default) => throw new NotImplementedException();
        public Task UpdateOwnerStorageAsync(Guid ownerUserId, long? allocatedStorage, CancellationToken ct = default) => throw new NotImplementedException();
    }

    private readonly MockPlanService _mockPlanService = new();

    public PaymentServiceTests()
    {
        var options = new DbContextOptionsBuilder<HuTubeDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;
        _db = new HuTubeDbContext(options);

        _options = new SepayOptions
        {
            SecretKey = "test-secret",
            AccountNumber = "1017588888",
            BankCode = "Vietcombank",
            PaymentExpiryMinutes = 30,
            TransactionCodePrefix = "HUTUBE"
        };

        _service = new PaymentService(_db, _mockPlanService, _options, TimeProvider.System);
    }

    public void Dispose()
    {
        _db.Database.EnsureDeleted();
        _db.Dispose();
    }

    [Fact]
    public async Task InitiateAsync_WhenPaidPlan_CreatesPendingPaymentWithQr()
    {
        var plan = new Plan
        {
            PlanId = Guid.NewGuid(),
            Code = "creator",
            Name = "Creator Plan",
            Price = 99000,
            DurationDays = 30,
            Status = "active"
        };
        _db.Plans.Add(plan);
        await _db.SaveChangesAsync();

        var userId = Guid.NewGuid();
        var request = new CreatePaymentRequest(plan.PlanId);

        var result = await _service.InitiateAsync(userId, request);

        Assert.NotNull(result);
        Assert.Equal(plan.Price, result.Amount);
        Assert.StartsWith("HUTUBE-", result.TransactionCode);
        Assert.Contains("vietqr.app/img", result.QrCodeUrl);
        Assert.Contains("1017588888", result.QrCodeUrl);

        var saved = await _db.Payments.FirstOrDefaultAsync(x => x.PaymentId == result.PaymentId);
        Assert.NotNull(saved);
        Assert.Equal("pending", saved.Status);
    }

    [Fact]
    public async Task InitiateAsync_WhenFreePlan_ThrowsBadRequest()
    {
        var plan = new Plan
        {
            PlanId = Guid.NewGuid(),
            Code = "free",
            Name = "Free Plan",
            Price = 0,
            DurationDays = 3650,
            Status = "active"
        };
        _db.Plans.Add(plan);
        await _db.SaveChangesAsync();

        var userId = Guid.NewGuid();
        var request = new CreatePaymentRequest(plan.PlanId);

        var ex = await Assert.ThrowsAsync<PaymentException>(() => _service.InitiateAsync(userId, request));
        Assert.Equal(400, ex.Status);
        Assert.Equal("FREE_PLAN_NO_PAYMENT", ex.Code);
    }

    [Fact]
    public async Task HandleSepayWebhookAsync_WhenValidPayment_ActivatesPlanAndMarksPaid()
    {
        var userId = Guid.NewGuid();
        var planId = Guid.NewGuid();
        var code = "HUTUBE-XYZ12345";

        var payment = new Payment
        {
            PaymentId = Guid.NewGuid(),
            UserId = userId,
            PlanId = planId,
            Amount = 99000,
            Status = "pending",
            TransactionCode = code,
            ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(30)
        };
        _db.Payments.Add(payment);
        await _db.SaveChangesAsync();

        var payload = new SepayWebhookPayload(
            Id: 10001,
            Gateway: "Vietcombank",
            TransactionDate: "2026-09-20 22:00:00",
            AccountNumber: "1017588888",
            SubAccount: null,
            Code: code,
            Content: $"{code} chuyen tien dang ky goi",
            TransferType: "in",
            TransferAmount: 99000,
            Accumulated: 99000,
            ReferenceCode: "FT123456"
        );

        var processed = await _service.HandleSepayWebhookAsync(payload);

        Assert.True(processed);
        Assert.True(_mockPlanService.ActivatePaidPlanAsyncCalled);
        Assert.Equal(userId, _mockPlanService.ActivatedUserId);
        Assert.Equal(planId, _mockPlanService.ActivatedPlanId);

        var updated = await _db.Payments.FindAsync(payment.PaymentId);
        Assert.NotNull(updated);
        Assert.Equal("paid", updated.Status);
        Assert.NotNull(updated.PaidAt);
        Assert.Equal(10001, updated.SepayTransactionId);
    }

    [Fact]
    public async Task HandleSepayWebhookAsync_WhenDuplicateTransactionId_IgnoresSilently()
    {
        var payment = new Payment
        {
            PaymentId = Guid.NewGuid(),
            UserId = Guid.NewGuid(),
            PlanId = Guid.NewGuid(),
            Amount = 99000,
            Status = "paid",
            SepayTransactionId = 99999,
            TransactionCode = "HUTUBE-ABCDEF12",
            ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(30)
        };
        _db.Payments.Add(payment);
        await _db.SaveChangesAsync();

        var payload = new SepayWebhookPayload(
            Id: 99999,
            Gateway: "Vietcombank",
            TransactionDate: "2026-09-20 22:00:00",
            AccountNumber: "1017588888",
            SubAccount: null,
            Code: "HUTUBE-ABCDEF12",
            Content: "HUTUBE-ABCDEF12 duplicate",
            TransferType: "in",
            TransferAmount: 99000,
            Accumulated: 99000,
            ReferenceCode: "FT99999"
        );

        var result = await _service.HandleSepayWebhookAsync(payload);

        Assert.True(result);
        Assert.False(_mockPlanService.ActivatePaidPlanAsyncCalled);
    }

    [Fact]
    public async Task HandleSepayWebhookAsync_WhenAmountLessThanRequired_DoesNotActivatePlan()
    {
        var payment = new Payment
        {
            PaymentId = Guid.NewGuid(),
            UserId = Guid.NewGuid(),
            PlanId = Guid.NewGuid(),
            Amount = 99000,
            Status = "pending",
            TransactionCode = "HUTUBE-LESS1234",
            ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(30)
        };
        _db.Payments.Add(payment);
        await _db.SaveChangesAsync();

        var payload = new SepayWebhookPayload(
            Id: 10002,
            Gateway: "Vietcombank",
            TransactionDate: "2026-09-20 22:00:00",
            AccountNumber: "1017588888",
            SubAccount: null,
            Code: "HUTUBE-LESS1234",
            Content: "HUTUBE-LESS1234 thiếu tiền",
            TransferType: "in",
            TransferAmount: 50000, // Nhỏ hơn 99000
            Accumulated: 50000,
            ReferenceCode: "FT10002"
        );

        var result = await _service.HandleSepayWebhookAsync(payload);

        Assert.True(result);
        Assert.False(_mockPlanService.ActivatePaidPlanAsyncCalled);

        var updated = await _db.Payments.FindAsync(payment.PaymentId);
        Assert.Equal("pending", updated!.Status);
    }

    [Fact]
    public async Task HandleSepayWebhookAsync_WhenPaymentExpired_CancelsPayment()
    {
        var payment = new Payment
        {
            PaymentId = Guid.NewGuid(),
            UserId = Guid.NewGuid(),
            PlanId = Guid.NewGuid(),
            Amount = 99000,
            Status = "pending",
            TransactionCode = "HUTUBE-EXPIRED1",
            ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(-5) // Đã hết hạn
        };
        _db.Payments.Add(payment);
        await _db.SaveChangesAsync();

        var payload = new SepayWebhookPayload(
            Id: 10003,
            Gateway: "Vietcombank",
            TransactionDate: "2026-09-20 22:00:00",
            AccountNumber: "1017588888",
            SubAccount: null,
            Code: "HUTUBE-EXPIRED1",
            Content: "HUTUBE-EXPIRED1 qua han",
            TransferType: "in",
            TransferAmount: 99000,
            Accumulated: 99000,
            ReferenceCode: "FT10003"
        );

        var result = await _service.HandleSepayWebhookAsync(payload);

        Assert.True(result);
        Assert.False(_mockPlanService.ActivatePaidPlanAsyncCalled);

        var updated = await _db.Payments.FindAsync(payment.PaymentId);
        Assert.Equal("cancelled", updated!.Status);
    }

    [Fact]
    public async Task GetPaymentAsync_ReturnsCorrectPaymentDetails()
    {
        var userId = Guid.NewGuid();
        var plan = new Plan
        {
            PlanId = Guid.NewGuid(),
            Code = "pro",
            Name = "Pro Plan",
            Price = 199000,
            Status = "active"
        };
        _db.Plans.Add(plan);

        var payment = new Payment
        {
            PaymentId = Guid.NewGuid(),
            UserId = userId,
            PlanId = plan.PlanId,
            Amount = 199000,
            Status = "pending",
            TransactionCode = "HUTUBE-DETAIL01",
            ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(30)
        };
        _db.Payments.Add(payment);
        await _db.SaveChangesAsync();

        var result = await _service.GetPaymentAsync(userId, payment.PaymentId);

        Assert.NotNull(result);
        Assert.Equal(payment.PaymentId, result.PaymentId);
        Assert.Equal("Pro Plan", result.PlanName);
        Assert.Equal("HUTUBE-DETAIL01", result.TransactionCode);
        Assert.Equal(199000, result.Amount);
    }
}
