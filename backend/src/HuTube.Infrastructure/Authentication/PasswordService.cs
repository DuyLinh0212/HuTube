using HuTube.Application.Auth;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Options;

namespace HuTube.Infrastructure.Authentication;

public sealed class PasswordService : IPasswordService
{
    private readonly PasswordHasher<string> _hasher = new(Options.Create(new PasswordHasherOptions { IterationCount = 210_000 }));
    public string Hash(string password) => _hasher.HashPassword("", password);
    public bool Verify(string password, string hash)
    {
        try { return _hasher.VerifyHashedPassword("", hash, password) != PasswordVerificationResult.Failed; }
        catch (FormatException) { return false; }
    }
}
