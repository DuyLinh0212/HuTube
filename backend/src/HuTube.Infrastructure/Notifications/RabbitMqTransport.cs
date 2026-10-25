using System.Text;
using HuTube.Domain.Videos;
using RabbitMQ.Client;

namespace HuTube.Infrastructure.Notifications;

public sealed class RabbitMqOptions
{
    public bool Enabled { get; set; }
    public string HostName { get; set; } = "127.0.0.1";
    public int Port { get; set; } = 5672;
    public string UserName { get; set; } = "dalitu";
    public string Password { get; set; } = "";
    public string VirtualHost { get; set; } = "dalitu";
    public bool UseTls { get; set; }
    public int FanoutBatchSize { get; set; } = 250;
    public int MaxConsumerRetries { get; set; } = 10;
    public string Exchange { get; set; } = "dalitu.video.events";
    public string Queue { get; set; } = "dalitu.video.notifications";
}

public interface IModerationEventPublisher
{
    Task PublishAsync(ModerationOutboxEvent message, CancellationToken ct);
}

public sealed class RabbitMqTransport(RabbitMqOptions options) : IModerationEventPublisher, IAsyncDisposable
{
    private readonly SemaphoreSlim gate = new(1, 1);
    private IConnection? connection;
    private IChannel? publisher;

    public ConnectionFactory CreateFactory() => new() {
        HostName = options.HostName, Port = options.Port, UserName = options.UserName,
        Password = options.Password, VirtualHost = options.VirtualHost,
        AutomaticRecoveryEnabled = true, NetworkRecoveryInterval = TimeSpan.FromSeconds(5),
        RequestedConnectionTimeout = TimeSpan.FromSeconds(5), ContinuationTimeout = TimeSpan.FromSeconds(10),
        Ssl = new SslOption { Enabled = options.UseTls, ServerName = options.HostName }
    };

    public async Task DeclareAsync(IChannel channel, CancellationToken ct)
    {
        await channel.ExchangeDeclareAsync(options.Exchange, ExchangeType.Topic, durable: true, cancellationToken: ct);
        await channel.ExchangeDeclareAsync(options.Exchange + ".dead", ExchangeType.Direct, durable: true, cancellationToken: ct);
        await channel.QueueDeclareAsync(options.Queue + ".dead", durable: true, exclusive: false, autoDelete: false,
            arguments: new Dictionary<string, object?> { ["x-queue-type"] = "quorum" }, cancellationToken: ct);
        await channel.QueueBindAsync(options.Queue + ".dead", options.Exchange + ".dead", "dead", cancellationToken: ct);
        await channel.QueueDeclareAsync(options.Queue, durable: true, exclusive: false, autoDelete: false,
            arguments: new Dictionary<string, object?> {
                ["x-queue-type"] = "quorum", ["x-overflow"] = "reject-publish", ["x-dead-letter-strategy"] = "at-least-once",
                ["x-dead-letter-exchange"] = options.Exchange + ".dead", ["x-dead-letter-routing-key"] = "dead"
            }, cancellationToken: ct);
        await channel.QueueBindAsync(options.Queue, options.Exchange, "video.*.v1", cancellationToken: ct);
        await channel.QueueDeclareAsync(options.Queue + ".retry", durable: true, exclusive: false, autoDelete: false,
            arguments: new Dictionary<string, object?> {
                ["x-queue-type"] = "quorum", ["x-overflow"] = "reject-publish", ["x-dead-letter-strategy"] = "at-least-once",
                ["x-message-ttl"] = 30000, ["x-dead-letter-exchange"] = options.Exchange,
                ["x-dead-letter-routing-key"] = "video.retry.v1"
            }, cancellationToken: ct);
    }

    public async Task PublishAsync(ModerationOutboxEvent message, CancellationToken ct)
    {
        await gate.WaitAsync(ct);
        try
        {
            if (publisher?.IsOpen != true)
            {
                if (publisher != null) await publisher.DisposeAsync();
                if (connection?.IsOpen != true)
                {
                    if (connection != null) await connection.DisposeAsync();
                    connection = await CreateFactory().CreateConnectionAsync("dalitu-outbox", ct);
                }
                publisher = await connection.CreateChannelAsync(new CreateChannelOptions(publisherConfirmationsEnabled: true, publisherConfirmationTrackingEnabled: true), ct);
                await DeclareAsync(publisher, ct);
            }
            // Awaiting with confirmations enabled includes broker ack/nack and
            // mandatory returns. Do not mark the outbox row sent before this.
            await publisher.BasicPublishAsync(options.Exchange, message.EventType, mandatory: true,
                new BasicProperties { Persistent = true, ContentType = "application/json", Type = message.EventType,
                    MessageId = message.EventId.ToString(), Timestamp = new AmqpTimestamp(message.OccurredAt.ToUnixTimeSeconds()) },
                Encoding.UTF8.GetBytes(message.Payload), ct);
        }
        finally { gate.Release(); }
    }

    public async ValueTask DisposeAsync()
    {
        if (publisher != null) await publisher.DisposeAsync();
        if (connection != null) await connection.DisposeAsync();
        gate.Dispose();
    }
}
