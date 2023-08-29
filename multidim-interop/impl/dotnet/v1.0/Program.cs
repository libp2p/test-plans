// SPDX-FileCopyrightText: 2023 Demerzel Solutions Limited
// SPDX-License-Identifier: MIT

using Microsoft.Extensions.DependencyInjection;
using Nethermind.Libp2p.Core;
using Nethermind.Libp2p.Protocols;
using StackExchange.Redis;
using System.Diagnostics;
using System.Net.NetworkInformation;
using Microsoft.Extensions.Logging;

try
{
    string transport = Environment.GetEnvironmentVariable("transport")!;
    string muxer = Environment.GetEnvironmentVariable("muxer")!;
    string security = Environment.GetEnvironmentVariable("security")!;

    bool isDialer = bool.Parse(Environment.GetEnvironmentVariable("is_dialer")!);
    string ip = Environment.GetEnvironmentVariable("ip") ?? "0.0.0.0";

    string redisAddr = Environment.GetEnvironmentVariable("redis_addr") ?? "redis:6379";

    int testTimeoutSeconds = int.Parse(Environment.GetEnvironmentVariable("test_timeout_seconds") ?? "180");

    IPeerFactory peerFactory = new TestPlansPeerFactoryBuilder(transport, muxer, security).Build();

    Log($"Connecting to redis at {redisAddr}...");
    ConnectionMultiplexer redis = ConnectionMultiplexer.Connect(redisAddr);
    IDatabase db = redis.GetDatabase();

    if (isDialer)
    {
        ILocalPeer localPeer = peerFactory.Create(localAddr: $"/ip4/0.0.0.0/tcp/0");
        string? listenerAddr = null;
        while ((listenerAddr = db.ListRightPop("listenerAddr")) is null)
        {
            await Task.Delay(20);
        }

        Log($"Dialing {listenerAddr}...");
        Stopwatch handshakeStartInstant = Stopwatch.StartNew();
        IRemotePeer remotePeer = await localPeer.DialAsync(listenerAddr);

        Stopwatch pingIstant = Stopwatch.StartNew();
        await remotePeer.DialAsync<PingProtocol>();
        long pingRTT = pingIstant.ElapsedMilliseconds;

        long handshakePlusOneRTT = handshakeStartInstant.ElapsedMilliseconds;

        PrintResult($"{{\"handshakePlusOneRTTMillis\": {handshakePlusOneRTT}, \"pingRTTMilllis\": {pingRTT}}}");
        Log("Done");
        return 0;
    }
    else
    {
        if (ip == "0.0.0.0")
        {
            IEnumerable<UnicastIPAddressInformation> addresses = NetworkInterface.GetAllNetworkInterfaces()!
                 .FirstOrDefault(i => i.Name == "eth0")!
                 .GetIPProperties()
                 .UnicastAddresses
                 .Where(a => a.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork);

            Log("Available addresses detected, picking the first: " + string.Join(",", addresses.Select(a => a.Address)));
            ip = addresses.First().Address.ToString()!;
        }
        Log("Starting to listen...");
        ILocalPeer localPeer = peerFactory.Create(localAddr: $"/ip4/{ip}/tcp/0");
        IListener listener = await localPeer.ListenAsync(localPeer.Address);
        listener.OnConnection += async (peer) => Log($"Connected {peer.Address}");
        Log($"Listening on {listener.Address}");
        db.ListRightPush(new RedisKey("listenerAddr"), new RedisValue(localPeer.Address.ToString()));
        await Task.Delay(testTimeoutSeconds * 1000);
        await listener.DisconnectAsync();
        return -1;
    }
}
catch (Exception ex)
{
    Log(ex.Message);
    return -1;
}

static void Log(string info) => Console.Error.WriteLine(info);
static void PrintResult(string info) => Console.WriteLine(info);

class TestPlansPeerFactoryBuilder : PeerFactoryBuilderBase<TestPlansPeerFactoryBuilder, PeerFactory>
{
    private readonly string transport;
    private readonly string? muxer;
    private readonly string? security;
    private static IPeerFactoryBuilder? defaultPeerFactoryBuilder;

    public TestPlansPeerFactoryBuilder(string transport, string? muxer, string? security)
        : base(new ServiceCollection()
              .AddLogging(builder =>
                  builder.SetMinimumLevel(LogLevel.Trace)
                      .AddSimpleConsole(l =>
                      {
                          l.SingleLine = true;
                          l.TimestampFormat = "[HH:mm:ss.FFF]";
                      }))
              .AddScoped(_ => defaultPeerFactoryBuilder!)
              .BuildServiceProvider())
    {
        defaultPeerFactoryBuilder = this;
        this.transport = transport;
        this.muxer = muxer;
        this.security = security;
    }

    private static readonly string[] stacklessProtocols = new[] { "quic", "quic-v1", "webtransport" };

    protected override ProtocolStack BuildStack()
    {
        ProtocolStack stack = transport switch
        {
            "tcp" => Over<IpTcpProtocol>(),
            _ => throw new NotImplementedException(),
        };

        if (!stacklessProtocols.Contains(transport))
        {
            stack = stack.Over<MultistreamProtocol>();
            stack = security switch
            {
                "noise" => stack.Over<NoiseProtocol>(),
                _ => throw new NotImplementedException(),
            };
            stack = stack.Over<MultistreamProtocol>();
            stack = muxer switch
            {
                "yamux" => stack.Over<YamuxProtocol>(),
                _ => throw new NotImplementedException(),
            };
            stack = stack.Over<MultistreamProtocol>();
        }

        return stack.AddAppLayerProtocol<IdentifyProtocol>()
                    .AddAppLayerProtocol<PingProtocol>();
    }
}
