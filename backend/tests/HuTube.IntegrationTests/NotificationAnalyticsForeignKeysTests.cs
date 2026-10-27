using Npgsql;

namespace HuTube.IntegrationTests;

public sealed class NotificationAnalyticsForeignKeysTests(AuthApiFactory factory) : IClassFixture<AuthApiFactory>
{
    [Fact]
    public async Task Migration_RejectsMissingUsersAndChannelsAtCommit()
    {
        await using var connection = new NpgsqlConnection(factory.Connection);
        await connection.OpenAsync();
        string[] inserts =
        [
            "INSERT INTO public.notification_deliveries (delivery_id, event_id, user_id, type, payload, available_at) VALUES (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'test', '{}', now())",
            "INSERT INTO public.channel_analytics_events (event_id, channel_id, occurred_at, metric, value) VALUES (gen_random_uuid(), gen_random_uuid(), now(), 'views', 1)"
        ];
        foreach (var sql in inserts)
        {
            await using var transaction = await connection.BeginTransactionAsync();
            await using var command = new NpgsqlCommand(sql, connection, transaction);
            await command.ExecuteNonQueryAsync();
            var error = await Assert.ThrowsAsync<PostgresException>(() => transaction.CommitAsync());
            Assert.Equal(PostgresErrorCodes.ForeignKeyViolation, error.SqlState);
        }
    }
}
