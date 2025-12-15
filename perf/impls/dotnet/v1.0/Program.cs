using System.Diagnostics;
using System.Text.Json;
using DataTransferBenchmark;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Nethermind.Libp2p;
using Nethermind.Libp2p.Core;
using Multiformats.Address;
using StackExchange.Redis;

class Program
{
    static async Task Main(string[] args)
    {
        var services = new ServiceCollection()
            .AddLibp2p(builder =>
            {
                // Enable both TCP and QUIC transports
                return builder
                    .WithQuic()  // Enable QUIC transport
                    .AddProtocol<PerfProtocol>();
            })
            .AddLogging(builder => builder
                .SetMinimumLevel(LogLevel.Information) // Show information and above
                .AddConsole(options =>
                {
                    options.LogToStandardErrorThreshold = LogLevel.Warning; // Only warnings/errors to stderr
                }))
            .BuildServiceProvider();

        var peerFactory = services.GetRequiredService<IPeerFactory>();
        var logger = services.GetRequiredService<ILogger<Program>>();

        // Read configuration from environment variables (following WRITE_A_PERF_TEST.md)
        var isDialer = Environment.GetEnvironmentVariable("IS_DIALER") == "true";
        var redisAddr = Environment.GetEnvironmentVariable("REDIS_ADDR") ?? "redis:6379";
        var transport = Environment.GetEnvironmentVariable("TRANSPORT") ?? "tcp";
        var secureChannel = Environment.GetEnvironmentVariable("SECURE_CHANNEL");
        var muxer = Environment.GetEnvironmentVariable("MUXER");

        logger.LogInformation("Configuration:");
        logger.LogInformation("  IS_DIALER: {IsDialer}", isDialer);
        logger.LogInformation("  REDIS_ADDR: {RedisAddr}", redisAddr);
        logger.LogInformation("  TRANSPORT: {Transport}", transport);
        logger.LogInformation("  SECURE_CHANNEL: {Secure}", secureChannel ?? "none");
        logger.LogInformation("  MUXER: {Muxer}", muxer ?? "none");

        // Validate transport
        if (transport != "tcp" && transport != "quic" && transport != "quic-v1")
        {
            logger.LogError("Unsupported transport: {Transport}. Supported: tcp, quic, quic-v1", transport);
            Environment.Exit(1);
        }

        // Dialer-specific parameters
        ulong uploadBytes = 1073741824;  // Default 1GB
        ulong downloadBytes = 1073741824;
        int uploadIterations = 10;
        int downloadIterations = 10;
        int latencyIterations = 100;

        if (isDialer)
        {
            // Read test parameters from environment
            if (ulong.TryParse(Environment.GetEnvironmentVariable("UPLOAD_BYTES"), out var ub))
                uploadBytes = ub;
            if (ulong.TryParse(Environment.GetEnvironmentVariable("DOWNLOAD_BYTES"), out var db))
                downloadBytes = db;
            if (int.TryParse(Environment.GetEnvironmentVariable("UPLOAD_ITERATIONS"), out var ui))
                uploadIterations = ui;
            if (int.TryParse(Environment.GetEnvironmentVariable("DOWNLOAD_ITERATIONS"), out var di))
                downloadIterations = di;
            if (int.TryParse(Environment.GetEnvironmentVariable("LATENCY_ITERATIONS"), out var li))
                latencyIterations = li;

            logger.LogInformation("Test Parameters:");
            logger.LogInformation("  UPLOAD_BYTES: {Bytes}", uploadBytes);
            logger.LogInformation("  DOWNLOAD_BYTES: {Bytes}", downloadBytes);
            logger.LogInformation("  UPLOAD_ITERATIONS: {Iters}", uploadIterations);
            logger.LogInformation("  DOWNLOAD_ITERATIONS: {Iters}", downloadIterations);
            logger.LogInformation("  LATENCY_ITERATIONS: {Iters}", latencyIterations);
        }

        // Route to listener or dialer based on IS_DIALER
        if (isDialer)
        {
            await RunDialer(peerFactory, logger, redisAddr, transport, uploadBytes, downloadBytes,
                uploadIterations, downloadIterations, latencyIterations);
        }
        else
        {
            await RunListener(peerFactory, logger, redisAddr, transport);
        }
    }

    static async Task RunListener(IPeerFactory peerFactory, ILogger<Program> logger, string redisAddr, string transport)
    {
        logger.LogInformation("Starting perf listener...");

        // Get listener IP from environment
        var listenerIp = Environment.GetEnvironmentVariable("LISTENER_IP");
        if (string.IsNullOrEmpty(listenerIp))
        {
            logger.LogError("LISTENER_IP environment variable not set");
            Environment.Exit(1);
        }
        logger.LogInformation("Listener IP: {ListenerIp}", listenerIp);

        // Connect to Redis
        var redis = await ConnectionMultiplexer.ConnectAsync(redisAddr);
        var db = redis.GetDatabase();
        logger.LogInformation("Connected to Redis at {RedisAddr}", redisAddr);

        // Create libp2p host
        var localPeer = peerFactory.Create();

        // Get peer ID for constructing multiaddr
        var peerId = localPeer.Identity.PeerId.ToString();
        logger.LogInformation("Peer ID: {PeerId}", peerId);

        // Construct listen multiaddr using LISTENER_IP (not 0.0.0.0)
        string listenMultiaddr;
        if (transport == "quic" || transport == "quic-v1")
        {
            listenMultiaddr = $"/ip4/{listenerIp}/udp/4001/quic-v1";
        }
        else
        {
            listenMultiaddr = $"/ip4/{listenerIp}/tcp/4001";
        }

        logger.LogInformation("Will listen on: {Multiaddr}", listenMultiaddr);

        // Parse multiaddr and start listening
        var listenAddr = Multiaddress.Decode(listenMultiaddr);
        await localPeer.StartListenAsync(new[] { listenAddr });
        logger.LogInformation("Listener started");

        // Publish the same multiaddr to Redis (what we're actually listening on)
        await db.StringSetAsync("listener_multiaddr", listenMultiaddr);
        logger.LogInformation("Published multiaddr to Redis: {Multiaddr}", listenMultiaddr);

        logger.LogInformation("Listener ready, waiting for connections...");

        // Keep running indefinitely
        await Task.Delay(Timeout.Infinite);
    }

    static async Task<string> WaitForListener(IDatabase db, ILogger<Program> logger)
    {
        logger.LogInformation("Waiting for listener multiaddr...");

        for (int i = 0; i < 30; i++)
        {
            var addr = await db.StringGetAsync("listener_multiaddr");
            if (!addr.IsNullOrEmpty)
            {
                return addr.ToString()!;
            }
            await Task.Delay(500);
        }

        throw new TimeoutException("Timeout waiting for listener multiaddr");
    }

    static async Task RunDialer(IPeerFactory peerFactory, ILogger<Program> logger, string redisAddr,
        string transport, ulong uploadBytes, ulong downloadBytes,
        int uploadIterations, int downloadIterations, int latencyIterations)
    {
        logger.LogInformation("Starting perf dialer...");

        // Connect to Redis
        var redis = await ConnectionMultiplexer.ConnectAsync(redisAddr);
        var db = redis.GetDatabase();
        logger.LogInformation("Connected to Redis at {RedisAddr}", redisAddr);

        // Wait for listener multiaddr
        var listenerAddr = await WaitForListener(db, logger);
        logger.LogInformation("Got listener multiaddr: {Addr}", listenerAddr);

        // Give listener a moment to be fully ready
        await Task.Delay(2000);

        // Create libp2p host
        var localPeer = peerFactory.Create();
        logger.LogInformation("Client peer created");

        try
        {
            // Connect to listener
            var targetAddr = Multiaddress.Decode(listenerAddr);
            logger.LogInformation("Connecting to listener at: {Addr}", targetAddr);
            var remotePeer = await localPeer.DialAsync(targetAddr);
            logger.LogInformation("Successfully connected to listener");

            // Run three measurements sequentially
            var uploadStats = await RunMeasurement(remotePeer, logger, uploadBytes, 0, uploadIterations, "upload");
            var downloadStats = await RunMeasurement(remotePeer, logger, 0, downloadBytes, downloadIterations, "download");
            var latencyStats = await RunMeasurement(remotePeer, logger, 1, 1, latencyIterations, "latency");

            logger.LogInformation("All measurements complete!");

            // Output results as YAML to stdout
            Console.WriteLine("# Upload measurement");
            Console.WriteLine("upload:");
            Console.WriteLine($"  iterations: {uploadIterations}");
            Console.WriteLine($"  min: {uploadStats.Min:F2}");
            Console.WriteLine($"  q1: {uploadStats.Q1:F2}");
            Console.WriteLine($"  median: {uploadStats.Median:F2}");
            Console.WriteLine($"  q3: {uploadStats.Q3:F2}");
            Console.WriteLine($"  max: {uploadStats.Max:F2}");
            if (uploadStats.Outliers.Any())
            {
                var outliers = string.Join(", ", uploadStats.Outliers.Select(v => v.ToString("F2")));
                Console.WriteLine($"  outliers: [{outliers}]");
            }
            else
            {
                Console.WriteLine("  outliers: []");
            }
            Console.WriteLine("  unit: Gbps");
            Console.WriteLine();

            Console.WriteLine("# Download measurement");
            Console.WriteLine("download:");
            Console.WriteLine($"  iterations: {downloadIterations}");
            Console.WriteLine($"  min: {downloadStats.Min:F2}");
            Console.WriteLine($"  q1: {downloadStats.Q1:F2}");
            Console.WriteLine($"  median: {downloadStats.Median:F2}");
            Console.WriteLine($"  q3: {downloadStats.Q3:F2}");
            Console.WriteLine($"  max: {downloadStats.Max:F2}");
            if (downloadStats.Outliers.Any())
            {
                var outliers = string.Join(", ", downloadStats.Outliers.Select(v => v.ToString("F2")));
                Console.WriteLine($"  outliers: [{outliers}]");
            }
            else
            {
                Console.WriteLine("  outliers: []");
            }
            Console.WriteLine("  unit: Gbps");
            Console.WriteLine();

            Console.WriteLine("# Latency measurement");
            Console.WriteLine("latency:");
            Console.WriteLine($"  iterations: {latencyIterations}");
            Console.WriteLine($"  min: {latencyStats.Min:F3}");
            Console.WriteLine($"  q1: {latencyStats.Q1:F3}");
            Console.WriteLine($"  median: {latencyStats.Median:F3}");
            Console.WriteLine($"  q3: {latencyStats.Q3:F3}");
            Console.WriteLine($"  max: {latencyStats.Max:F3}");
            if (latencyStats.Outliers.Any())
            {
                var outliers = string.Join(", ", latencyStats.Outliers.Select(v => v.ToString("F3")));
                Console.WriteLine($"  outliers: [{outliers}]");
            }
            else
            {
                Console.WriteLine("  outliers: []");
            }
            Console.WriteLine("  unit: ms");

            logger.LogInformation("Results output complete");
        }
        catch (Exception ex)
        {
            logger.LogError("Dialer failed: {Message}", ex.Message);
            logger.LogError("Stack trace: {StackTrace}", ex.StackTrace);
            Environment.Exit(1);
        }
    }

    private static Identity GenerateDeterministicIdentity(byte seed)
    {
        var fixedSeed = new byte[32];
        Array.Fill(fixedSeed, seed);
        return new Identity(fixedSeed);
    }

    // Box plot statistics
    class Stats
    {
        public double Min { get; set; }
        public double Q1 { get; set; }
        public double Median { get; set; }
        public double Q3 { get; set; }
        public double Max { get; set; }
        public List<double> Outliers { get; set; } = new();
    }

    static Stats CalculateStats(List<double> values)
    {
        values.Sort();

        var n = values.Count;
        var min = values[0];
        var max = values[n - 1];

        // Calculate percentiles
        var q1 = Percentile(values, 25.0);
        var median = Percentile(values, 50.0);
        var q3 = Percentile(values, 75.0);

        // Calculate IQR and identify outliers
        var iqr = q3 - q1;
        var lowerFence = q1 - 1.5 * iqr;
        var upperFence = q3 + 1.5 * iqr;

        var outliers = values.Where(v => v < lowerFence || v > upperFence).ToList();

        return new Stats
        {
            Min = min,
            Q1 = q1,
            Median = median,
            Q3 = q3,
            Max = max,
            Outliers = outliers
        };
    }

    static double Percentile(List<double> sortedValues, double p)
    {
        var n = sortedValues.Count;
        var index = (p / 100.0) * (n - 1);
        var lower = (int)Math.Floor(index);
        var upper = (int)Math.Ceiling(index);

        if (lower == upper)
        {
            return sortedValues[lower];
        }

        var weight = index - lower;
        return sortedValues[lower] * (1.0 - weight) + sortedValues[upper] * weight;
    }

    static async Task<Stats> RunMeasurement(dynamic remotePeer, ILogger<Program> logger,
        ulong uploadBytes, ulong downloadBytes, int iterations, string measurementType)
    {
        var values = new List<double>();

        logger.LogInformation("Running {Type} test ({Iterations} iterations)...", measurementType, iterations);

        for (int i = 0; i < iterations; i++)
        {
            // Reset counters for this iteration
            PerfProtocol.BytesToSend = uploadBytes;
            PerfProtocol.BytesToReceive = downloadBytes;
            PerfProtocol.ActualBytesSent = 0;
            PerfProtocol.ActualBytesReceived = 0;

            var start = DateTime.UtcNow;

            try
            {
                // Run perf protocol
                await remotePeer.DialAsync<PerfProtocol>();
            }
            catch (Exception ex)
            {
                logger.LogWarning("Iteration {Iter} failed: {Message}", i + 1, ex.Message);
                continue; // Skip this iteration
            }

            var elapsed = (DateTime.UtcNow - start).TotalSeconds;

            // Calculate throughput (Gbps) or latency (seconds)
            double value;
            if (uploadBytes > 100 || downloadBytes > 100)
            {
                // Throughput test
                var bytes = Math.Max(uploadBytes, downloadBytes);
                value = (bytes * 8.0) / elapsed / 1_000_000_000.0;  // Gbps
            }
            else
            {
                // Latency test
                value = elapsed * 1000;  // Milliseconds
            }

            values.Add(value);
            logger.LogInformation("  Iteration {Iter}/{Total}: {Value}", i + 1, iterations,
                uploadBytes > 100 ? $"{value:F2} Gbps" : $"{value:F6} s");
        }

        if (values.Count == 0)
        {
            logger.LogError("All iterations failed for {Type} test", measurementType);
            throw new Exception($"All iterations failed for {measurementType} test");
        }

        return CalculateStats(values);
    }
}
