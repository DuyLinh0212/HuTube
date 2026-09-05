using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace HuTube.Infrastructure.Persistence;

public sealed class HuTubeDbContextFactory : IDesignTimeDbContextFactory<HuTubeDbContext>
{
    public HuTubeDbContext CreateDbContext(string[] args)
    {
        var connection = Environment.GetEnvironmentVariable("ConnectionStrings__Database")
            ?? "Host=localhost;Database=hutube;Username=postgres";
        return new(new DbContextOptionsBuilder<HuTubeDbContext>().UseNpgsql(DatabaseConnectionString.Normalize(connection)).Options);
    }
}
