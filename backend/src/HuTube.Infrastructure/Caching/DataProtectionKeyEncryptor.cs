using System.Security.Cryptography;
using System.Text;
using System.Xml.Linq;
using Microsoft.AspNetCore.DataProtection.XmlEncryption;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace HuTube.Infrastructure.Caching;

public sealed class DataProtectionKeyEncryptor : IXmlEncryptor, IXmlDecryptor
{
    private static readonly byte[] Purpose = Encoding.UTF8.GetBytes("Dalitu.DataProtection.KeyEncryption.v1");
    private readonly byte[] key;

    public DataProtectionKeyEncryptor(IConfiguration configuration)
    {
        var secret = configuration["DataProtection:EncryptionKey"];
        if (string.IsNullOrWhiteSpace(secret)) secret = configuration["Jwt:SigningKey"];
        if (string.IsNullOrWhiteSpace(secret) || secret.Length < 32)
            throw new InvalidOperationException("A stable secret of at least 32 characters is required for key encryption.");
        var material = Encoding.UTF8.GetBytes(secret);
        try { key = HKDF.DeriveKey(HashAlgorithmName.SHA256, material, 32, info: Purpose); }
        finally { CryptographicOperations.ZeroMemory(material); }
    }

    public EncryptedXmlInfo Encrypt(XElement plaintextElement)
    {
        var plaintext = Encoding.UTF8.GetBytes(plaintextElement.ToString(SaveOptions.DisableFormatting));
        var nonce = RandomNumberGenerator.GetBytes(12);
        var ciphertext = new byte[plaintext.Length];
        var tag = new byte[16];
        try
        {
            using var cipher = new AesGcm(key, 16);
            cipher.Encrypt(nonce, plaintext, ciphertext, tag, Purpose);
        }
        finally { CryptographicOperations.ZeroMemory(plaintext); }
        return new(new XElement("dalituEncryptedKey", new XAttribute("version", "1"),
            new XElement("nonce", Convert.ToBase64String(nonce)),
            new XElement("ciphertext", Convert.ToBase64String(ciphertext)),
            new XElement("tag", Convert.ToBase64String(tag))), typeof(DataProtectionKeyDecryptor));
    }

    public XElement Decrypt(XElement encryptedElement)
    {
        if ((string?)encryptedElement.Attribute("version") != "1") throw new CryptographicException("Unknown key encryption version.");
        var ciphertext = Convert.FromBase64String(encryptedElement.Element("ciphertext")!.Value);
        var plaintext = new byte[ciphertext.Length];
        try
        {
            using var cipher = new AesGcm(key, 16);
            cipher.Decrypt(Convert.FromBase64String(encryptedElement.Element("nonce")!.Value), ciphertext,
                Convert.FromBase64String(encryptedElement.Element("tag")!.Value), plaintext, Purpose);
            return XElement.Parse(Encoding.UTF8.GetString(plaintext));
        }
        finally { CryptographicOperations.ZeroMemory(plaintext); }
    }
}

// Data Protection activates persisted decryptors through an IServiceProvider constructor.
public sealed class DataProtectionKeyDecryptor(IServiceProvider services) : IXmlDecryptor
{
    public XElement Decrypt(XElement encryptedElement) =>
        services.GetRequiredService<DataProtectionKeyEncryptor>().Decrypt(encryptedElement);
}
