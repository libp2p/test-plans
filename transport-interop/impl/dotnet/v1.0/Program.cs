// SPDX-FileCopyrightText: 2023 Demerzel Solutions Limited
// SPDX-License-Identifier: MIT

using Microsoft.Extensions.DependencyInjection;
using Nethermind.Libp2p.Core;
using Nethermind.Libp2p.Protocols;
using StackExchange.Redis;
using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Buffers;
using System.Net;
using System.Net.Sockets;
using MultiaddrEnum = Nethermind.Libp2p.Core.Enums.Multiaddr;
using Microsoft.Extensions.Logging;
using System.Net.Quic;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
using Nethermind.Libp2p.Protocols.Quic;
using System.Security.Cryptography;


try
{
    string transport = Environment.GetEnvironmentVariable("transport")!;
    string muxer = Environment.GetEnvironmentVariable("muxer")!;
    string security = Environment.GetEnvironmentVariable("security")!;

    bool isDialer = bool.Parse(Environment.GetEnvironmentVariable("is_dialer")!);
    string ip = Environment.GetEnvironmentVariable("ip") ?? "0.0.0.0";

    string redisAddr = Environment.GetEnvironmentVariable("redis_addr") ?? "redis:6379";

    int testTimeoutSeconds = int.Parse(Environment.GetEnvironmentVariable("test_timeout_seconds") ?? "180");

    TestPlansPeerFactoryBuilder builder = new TestPlansPeerFactoryBuilder(transport, muxer, security);
    IPeerFactory peerFactory = builder.Build();

    Log($"Connecting to redis at {redisAddr}...");
    ConnectionMultiplexer redis = ConnectionMultiplexer.Connect(redisAddr);
    IDatabase db = redis.GetDatabase();

    if (isDialer)
    {
        ILocalPeer localPeer = peerFactory.Create(localAddr: builder.MakeAddress());
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
        ILocalPeer localPeer = peerFactory.Create(localAddr: builder.MakeAddress(ip));
        IListener listener = await localPeer.ListenAsync(localPeer.Address);
        listener.OnConnection += (peer) => { Log($"Connected {peer.Address}"); return Task.CompletedTask; };
        Log($"Listening on {listener.Address}");
        db.ListRightPush(new RedisKey("listenerAddr"), new RedisValue(listener.Address.ToString()));
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
            "quic-v1" => Over<QuicProtocol>(),
            _ => throw new NotImplementedException(),
        };

        stack = stack.Over<MultistreamProtocol>();

        if (!stacklessProtocols.Contains(transport))
        {
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

    public string MakeAddress(string ip = "0.0.0.0", string port = "0") => transport switch
    {
        "tcp" => $"/ip4/{ip}/tcp/{port}",
        "quic-v1" => $"/ip4/{ip}/udp/{port}/quic-v1",
        _ => throw new NotImplementedException(),
    };
}



// #pragma warning disable CA1416 // Do not inform about platform compatibility
// #pragma warning disable CA2252 // EnablePreviewFeatures is set in the project, but build still fails
// public class QuicProtocol : IProtocol
// {
//     private readonly ILogger? _logger;
//     private readonly ECDsa _sessionKey;

//     public QuicProtocol(ILoggerFactory? loggerFactory = null)
//     {
//         _logger = loggerFactory?.CreateLogger<QuicProtocol>();
//         _sessionKey = ECDsa.Create();
//     }

//     private static readonly List<SslApplicationProtocol> protocols = new()
//     {
//         new SslApplicationProtocol("libp2p"),
//         // SslApplicationProtocol.Http3, // webtransport
//     };

//     public string Id => "quic";

//     public async Task ListenAsync(IChannel channel, IChannelFactory? channelFactory, IPeerContext context)
//     {
//         try{
//         if (channelFactory is null)
//         {
//             throw new ArgumentException($"The protocol requires {nameof(channelFactory)}");
//         }

//         if (!QuicListener.IsSupported)
//         {
//             throw new NotSupportedException("QUIC is not supported, check for presence of libmsquic and support of TLS 1.3.");
//         }

//         Multiaddr addr = context.LocalPeer.Address;
//         MultiaddrEnum ipProtocol = addr.Has(MultiaddrEnum.Ip4) ? MultiaddrEnum.Ip4 : MultiaddrEnum.Ip6;
//         IPAddress ipAddress = IPAddress.Parse(addr.At(ipProtocol)!);
//         int udpPort = int.Parse(addr.At(MultiaddrEnum.Udp)!);

//         IPEndPoint localEndpoint = new(ipAddress, udpPort);

//         QuicServerConnectionOptions serverConnectionOptions = new()
//         {
//             DefaultStreamErrorCode = 0, // Protocol-dependent error code.
//             DefaultCloseErrorCode = 1, // Protocol-dependent error code.

//             ServerAuthenticationOptions = new SslServerAuthenticationOptions
//             {
//                 ApplicationProtocols = protocols,
//                 RemoteCertificateValidationCallback = (_, c, _, _) => VerifyRemoteCertificate(context.RemotePeer, c),
//                 ServerCertificate = CertificateHelper.CertificateFromIdentity(_sessionKey, context.LocalPeer.Identity)
//             },
//         };

//         QuicListener listener = await QuicListener.ListenAsync(new QuicListenerOptions
//         {
//             ListenEndPoint = localEndpoint,
//             ApplicationProtocols = protocols,
//             ConnectionOptionsCallback = (_, _, _) => ValueTask.FromResult(serverConnectionOptions)
//         });

//         Console.Error.WriteLine("QUIC IP: {0}", listener.LocalEndPoint);
//         context.LocalEndpoint = Multiaddr.From(
//             ipProtocol, listener.LocalEndPoint.Address.ToString(),
//             MultiaddrEnum.Udp, listener.LocalEndPoint.Port);

//         context.LocalPeer.Address = context.LocalPeer.Address
//             .Replace(ipProtocol, listener.LocalEndPoint.Address.ToString())
//             .Replace(MultiaddrEnum.Udp, listener.LocalEndPoint.Port.ToString());

//         channel.OnClose(async () =>
//         {
//             await listener.DisposeAsync();
//         });

//         while (!channel.IsClosed)
//         {
//             QuicConnection connection = await listener.AcceptConnectionAsync(channel.Token);
//             _ = ProcessStreams(connection, context.Fork(), channelFactory, channel.Token);
//         }}
//         catch(Exception e){
//         Console.Error.WriteLine("error: {0}", e);
//         }
//     }

//     public async Task DialAsync(IChannel channel, IChannelFactory? channelFactory, IPeerContext context)
//     {
//         try{
//         if (channelFactory is null)
//         {
//             throw new ArgumentException($"The protocol requires {nameof(channelFactory)}");
//         }

//         if (!QuicConnection.IsSupported)
//         {
//             throw new NotSupportedException("QUIC is not supported, check for presence of libmsquic and support of TLS 1.3.");
//         }

//         Multiaddr addr = context.LocalPeer.Address;
//         MultiaddrEnum ipProtocol = addr.Has(MultiaddrEnum.Ip4) ? MultiaddrEnum.Ip4 : MultiaddrEnum.Ip6;
//         IPAddress ipAddress = IPAddress.Parse(addr.At(ipProtocol)!);
//         int udpPort = int.Parse(addr.At(MultiaddrEnum.Udp)!);

//         IPEndPoint localEndpoint = new(ipAddress, udpPort);


//         addr = context.RemotePeer.Address;
//         ipProtocol = addr.Has(MultiaddrEnum.Ip4) ? MultiaddrEnum.Ip4 : MultiaddrEnum.Ip6;
//         ipAddress = IPAddress.Parse(addr.At(ipProtocol)!);
//         udpPort = int.Parse(addr.At(MultiaddrEnum.Udp)!);

//         IPEndPoint remoteEndpoint = new(ipAddress, udpPort);

//         QuicClientConnectionOptions clientConnectionOptions = new()
//         {
//             LocalEndPoint = localEndpoint,
//             DefaultStreamErrorCode = 0, // Protocol-dependent error code.
//             DefaultCloseErrorCode = 1, // Protocol-dependent error code.
//             MaxInboundUnidirectionalStreams = 100,
//             MaxInboundBidirectionalStreams = 100,
//             ClientAuthenticationOptions = new SslClientAuthenticationOptions
//             {
//                 ApplicationProtocols = protocols,
//                 RemoteCertificateValidationCallback = (_, c, _, _) => VerifyRemoteCertificate(context.RemotePeer, c),
//                 ClientCertificates = new X509CertificateCollection { CertificateHelper.CertificateFromIdentity(_sessionKey, context.LocalPeer.Identity) },
//             },
//             RemoteEndPoint = remoteEndpoint,
//         };

//         QuicConnection connection = await QuicConnection.ConnectAsync(clientConnectionOptions);

//         channel.OnClose(async () =>
//         {
//             await connection.CloseAsync(0);
//             await connection.DisposeAsync();
//         });

//         _logger?.LogDebug($"Connected {connection.LocalEndPoint} --> {connection.RemoteEndPoint}");

//         await ProcessStreams(connection, context, channelFactory, channel.Token);
//         }
//         catch(Exception e){
//                _logger.LogDebug("error: {0}", e);
//         }
//     }

//     private static bool VerifyRemoteCertificate(IPeer? remotePeer, X509Certificate certificate) =>
//          CertificateHelper.ValidateCertificate(certificate as X509Certificate2, remotePeer?.Address.At(MultiaddrEnum.P2p));

//     private async Task ProcessStreams(QuicConnection connection, IPeerContext context, IChannelFactory channelFactory, CancellationToken token)
//     {
//         MultiaddrEnum newIpProtocol = connection.LocalEndPoint.AddressFamily == AddressFamily.InterNetwork
//            ? MultiaddrEnum.Ip4
//            : MultiaddrEnum.Ip6;

//         context.LocalEndpoint = Multiaddr.From(
//             newIpProtocol,
//             connection.LocalEndPoint.Address.ToString(),
//             MultiaddrEnum.Udp,
//             connection.LocalEndPoint.Port);

//         context.LocalPeer.Address = context.LocalPeer.Address.Replace(
//                 context.LocalEndpoint.Has(MultiaddrEnum.Ip4) ? MultiaddrEnum.Ip4 : MultiaddrEnum.Ip6, newIpProtocol,
//                 connection.LocalEndPoint.Address.ToString())
//             .Replace(
//                 MultiaddrEnum.Udp,
//                 connection.LocalEndPoint.Port.ToString());

//         IPEndPoint remoteIpEndpoint = connection.RemoteEndPoint!;
//         newIpProtocol = remoteIpEndpoint.AddressFamily == AddressFamily.InterNetwork
//            ? MultiaddrEnum.Ip4
//            : MultiaddrEnum.Ip6;

//         context.RemoteEndpoint = Multiaddr.From(
//             newIpProtocol,
//             remoteIpEndpoint.Address.ToString(),
//             MultiaddrEnum.Udp,
//             remoteIpEndpoint.Port);

//         context.Connected(context.RemotePeer);

//         _ = Task.Run(async () =>
//         {
//             foreach (IChannelRequest request in context.SubDialRequests.GetConsumingEnumerable())
//             {
//                 QuicStream stream = await connection.OpenOutboundStreamAsync(QuicStreamType.Bidirectional);
//                 IPeerContext dialContext = context.Fork();
//                 dialContext.SpecificProtocolRequest = request;
//                 IChannel upChannel = channelFactory.SubDial(dialContext);
//                 ExchangeData(stream, upChannel, request.CompletionSource);
//             }
//         }, token);

//         while (!token.IsCancellationRequested)
//         {
//             QuicStream inboundStream = await connection.AcceptInboundStreamAsync(token);
//             IChannel upChannel = channelFactory.SubListen(context);
//             ExchangeData(inboundStream, upChannel, null);
//         }
//     }

//     private void ExchangeData(QuicStream stream, IChannel upChannel, TaskCompletionSource? tcs)
//     {
//         upChannel.OnClose(async () =>
//         {
//             tcs?.SetResult();
//             stream.Close();
//         });

//         _ = Task.Run(async () =>
//         {
//             try
//             {
//                 await foreach (ReadOnlySequence<byte> data in upChannel.ReadAllAsync())
//                 {
//                     await stream.WriteAsync(data.ToArray(), upChannel.Token);
//                 }
//             }
//             catch (SocketException)
//             {
//                 _logger?.LogInformation("Disconnected due to a socket exception");
//                 await upChannel.CloseAsync(false);
//             }
//         }, upChannel.Token);

//         _ = Task.Run(async () =>
//         {
//             try
//             {
//                 while (!upChannel.IsClosed)
//                 {
//                     byte[] buf = new byte[1024];
//                     int len = await stream.ReadAtLeastAsync(buf, 1, false, upChannel.Token);
//                     if (len != 0)
//                     {
//                         await upChannel.WriteAsync(new ReadOnlySequence<byte>(buf.AsMemory()[..len]));
//                     }
//                 }
//             }
//             catch (SocketException)
//             {
//                 _logger?.LogInformation("Disconnected due to a socket exception");
//                 await upChannel.CloseAsync(false);
//             }
//         });
//     }
// }
