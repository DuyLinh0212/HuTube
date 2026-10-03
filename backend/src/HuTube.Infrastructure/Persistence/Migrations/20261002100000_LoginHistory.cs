using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261002100000_LoginHistory")]
public sealed class LoginHistory : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        CREATE TABLE public.login_history (
            login_history_id uuid NOT NULL,
            user_id uuid NOT NULL,
            device_id character varying(128) NOT NULL DEFAULT '',
            device_name character varying(200) NOT NULL,
            platform character varying(20) NOT NULL,
            ip_address character varying(45),
            login_at timestamp with time zone NOT NULL,
            CONSTRAINT "PK_login_history" PRIMARY KEY (login_history_id),
            CONSTRAINT "FK_login_history_users_user_id" FOREIGN KEY (user_id)
                REFERENCES public.users(user_id) ON DELETE CASCADE
        );

        INSERT INTO public.login_history (
            login_history_id, user_id, device_id, device_name, platform, ip_address, login_at
        )
        SELECT refresh_token_id, user_id, COALESCE(device_id, ''),
               COALESCE(NULLIF(device_name, ''), 'Unknown device'),
               COALESCE(platform, 'web'), ip_address, issued_at
        FROM public.refresh_tokens;

        CREATE INDEX ix_login_history_user_id_login_at
            ON public.login_history (user_id, login_at DESC);
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DROP TABLE IF EXISTS public.login_history;
        """);
}
