using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;

namespace HuTube.Infrastructure.Persistence.Migrations;

[DbContext(typeof(HuTubeDbContext))]
[Migration("20261031130000_DatabaseBackups")]
public sealed class DatabaseBackups : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        CREATE TABLE public.database_backup_schedules (
            id integer PRIMARY KEY CHECK (id = 1),
            enabled boolean NOT NULL DEFAULT FALSE,
            frequency varchar(16) NOT NULL DEFAULT 'daily'
                CHECK (frequency IN ('daily', 'weekly')),
            day_of_week integer NULL CHECK (day_of_week BETWEEN 0 AND 6),
            hour integer NOT NULL DEFAULT 2 CHECK (hour BETWEEN 0 AND 23),
            minute integer NOT NULL DEFAULT 0 CHECK (minute BETWEEN 0 AND 59),
            time_zone_id varchar(64) NOT NULL DEFAULT 'Asia/Ho_Chi_Minh',
            next_run_at timestamptz NULL,
            last_run_at timestamptz NULL,
            updated_at timestamptz NOT NULL DEFAULT now(),
            updated_by_user_id uuid NULL,
            CONSTRAINT ck_database_backup_schedules_frequency_day
                CHECK ((frequency = 'daily' AND day_of_week IS NULL)
                    OR (frequency = 'weekly' AND day_of_week IS NOT NULL AND day_of_week BETWEEN 0 AND 6)),
            CONSTRAINT fk_database_backup_schedules_updated_by_user
                FOREIGN KEY (updated_by_user_id) REFERENCES public.users(user_id) ON DELETE SET NULL
        );

        INSERT INTO public.database_backup_schedules (id)
        VALUES (1)
        ON CONFLICT (id) DO NOTHING;

        CREATE INDEX ix_database_backup_schedules_updated_by_user_id
            ON public.database_backup_schedules (updated_by_user_id);

        CREATE TABLE public.database_backup_runs (
            run_id uuid PRIMARY KEY,
            trigger varchar(16) NOT NULL CHECK (trigger IN ('manual', 'schedule')),
            status varchar(16) NOT NULL CHECK (status IN ('queued', 'running', 'succeeded', 'failed')),
            created_at timestamptz NOT NULL DEFAULT now(),
            started_at timestamptz NULL,
            completed_at timestamptz NULL,
            initiated_by_user_id uuid NULL,
            object_key text NULL,
            file_name varchar(255) NULL,
            size_bytes bigint NULL CHECK (size_bytes IS NULL OR size_bytes >= 0),
            error_message varchar(1000) NULL,
            CONSTRAINT fk_database_backup_runs_initiated_by_user
                FOREIGN KEY (initiated_by_user_id) REFERENCES public.users(user_id) ON DELETE SET NULL
        );

        CREATE INDEX ix_database_backup_runs_created_at
            ON public.database_backup_runs (created_at DESC);
        CREATE INDEX ix_database_backup_runs_initiated_by_user_id
            ON public.database_backup_runs (initiated_by_user_id);
        CREATE UNIQUE INDEX ux_database_backup_runs_active_status
            ON public.database_backup_runs (status)
            WHERE status IN ('queued', 'running');

        INSERT INTO public.permissions (permission_id, code, name, description, status)
        VALUES
          ('00000000-0000-0001-0000-000000000051', 'backup.view', 'Xem và tải bản sao lưu', 'Xem lịch sử và tải xuống bản sao lưu PostgreSQL.', 'active'),
          ('00000000-0000-0001-0000-000000000052', 'backup.manage', 'Quản lý lịch sao lưu', 'Cấu hình lịch và chạy bản sao lưu PostgreSQL.', 'active')
        ON CONFLICT (permission_id) DO UPDATE
        SET code = EXCLUDED.code, name = EXCLUDED.name, description = EXCLUDED.description, status = EXCLUDED.status;

        INSERT INTO public.role_permissions (role_id, permission_id)
        SELECT role.role_id, permission.permission_id
        FROM public.roles AS role
        CROSS JOIN public.permissions AS permission
        WHERE role.code IN ('admin', 'super_admin')
          AND permission.code IN ('backup.view', 'backup.manage')
        ON CONFLICT (role_id, permission_id) DO NOTHING;
        """);

    protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql("""
        DELETE FROM public.role_permissions
        WHERE permission_id IN (
            '00000000-0000-0001-0000-000000000051'::uuid,
            '00000000-0000-0001-0000-000000000052'::uuid);
        DELETE FROM public.permissions
        WHERE permission_id IN (
            '00000000-0000-0001-0000-000000000051'::uuid,
            '00000000-0000-0001-0000-000000000052'::uuid);
        DROP TABLE public.database_backup_runs;
        DROP TABLE public.database_backup_schedules;
        """);
}
