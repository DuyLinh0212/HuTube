using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261020080000_RebrandPlatformPoliciesToDalitu")]
public sealed class RebrandPlatformPoliciesToDalitu : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        UPDATE public.policies
        SET name = replace(replace(name, 'HuTube', 'Dalitu'), 'HUTUBE', 'DALITU'),
            content = replace(replace(content, 'HuTube', 'Dalitu'), 'HUTUBE', 'DALITU')
        WHERE name LIKE '%HuTube%' OR content LIKE '%HuTube%'
           OR name LIKE '%HUTUBE%' OR content LIKE '%HUTUBE%';

        UPDATE public.roles
        SET description = replace(description, 'HuTube', 'Dalitu')
        WHERE code IN ('user', 'admin') AND description LIKE '%HuTube%';
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        UPDATE public.policies
        SET name = replace(replace(name, 'Dalitu', 'HuTube'), 'DALITU', 'HUTUBE'),
            content = replace(replace(content, 'Dalitu', 'HuTube'), 'DALITU', 'HUTUBE')
        WHERE name LIKE '%Dalitu%' OR content LIKE '%Dalitu%'
           OR name LIKE '%DALITU%' OR content LIKE '%DALITU%';

        UPDATE public.roles
        SET description = replace(description, 'Dalitu', 'HuTube')
        WHERE code IN ('user', 'admin') AND description LIKE '%Dalitu%';
        """);
}
