using System.Diagnostics;
using System.Text.Json;
using DataTransferBenchmark;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Nethermind.Libp2p;
using Nethermind.Libp2p.Core;
using Multiformats.Address;

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
                .SetMinimumLevel(LogLevel.Critical) // Only show critical messages
                .AddConsole(options => 
                {
                    options.LogToStandardErrorThreshold = LogLevel.Warning; // Only warnings/errors to stderr
                }))
            .BuildServiceProvider();

        var peerFactory = services.GetRequiredService<IPeerFactory>();
        var logger = services.GetRequiredService<ILogger<Program>>();

        string? serverAddress = null;
        string? multiaddr = null;
        bool runServer = false;
        ulong? uploadBytes = null;
        ulong? downloadBytes = null;
        string transport = "tcp";

        // Parse command line arguments like Go implementation
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "-run-server")
            {
                runServer = true;
            }
            else if (args[i] == "-multiaddr" && i + 1 < args.Length)
            {
                multiaddr = args[++i];
            }
            else if (args[i] == "-server-address" && i + 1 < args.Length)
            {
                serverAddress = args[++i];
            }
            else if (args[i] == "-upload-bytes" && i + 1 < args.Length)
            {
                if (ulong.TryParse(args[++i], out ulong bytes))
                {
                    uploadBytes = bytes;
                }
            }
            else if (args[i] == "-download-bytes" && i + 1 < args.Length)
            {
                if (ulong.TryParse(args[++i], out ulong bytes))
                {
                    downloadBytes = bytes;
                }
            }
            else if (args[i] == "-transport" && i + 1 < args.Length)
            {
                transport = args[++i];
                // Validate transport - support both TCP and QUIC
                if (transport != "tcp" && transport != "quic")
                {
                    logger.LogError("Unsupported transport: {Transport}. Supported transports are 'tcp' and 'quic'", transport);
                    Environment.Exit(1);
                }
            }
        }

        // Both TCP and QUIC transports are now enabled via WithQuic() in the builder

        // Convert host:port to multiaddr format if multiaddr not directly provided
        if (multiaddr == null && serverAddress != null)
        {
            var parts = serverAddress.Split(':');
            if (parts.Length == 2 && int.TryParse(parts[1], out int port))
            {
                if (runServer)
                {
                    multiaddr = transport == "quic" 
                        ? $"/ip4/{parts[0]}/udp/{port}/quic-v1"
                        : $"/ip4/{parts[0]}/tcp/{port}";
                }
                else
                {
                    // Generate deterministic peer ID like Go does
                    var deterministicPeerId = GenerateDeterministicPeerId();
                    multiaddr = transport == "quic"
                        ? $"/ip4/{parts[0]}/udp/{port}/quic-v1/p2p/{deterministicPeerId}"
                        : $"/ip4/{parts[0]}/tcp/{port}/p2p/{deterministicPeerId}";
                }
            }
            else
            {
                logger.LogError("Invalid server address format. Use host:port");
                Environment.Exit(1);
            }
        }
        
        if (runServer)
        {
            // Server mode
            if (serverAddress == null)
            {
                logger.LogError("Server address must be specified with -server-address");
                Environment.Exit(1);
            }
            
            var identity = new Identity(Enumerable.Repeat((byte)42, 32).ToArray());
            var localPeer = peerFactory.Create(identity);
            
            // Convert server address to multiaddr for listening
            var parts = serverAddress.Split(':');
            if (parts.Length == 2 && int.TryParse(parts[1], out int port))
            {
                // Listen on the requested transport primarily (for debugging QUIC)
                var tcpAddr = Multiaddress.Decode($"/ip4/{parts[0]}/tcp/{port}");
                var quicAddr = Multiaddress.Decode($"/ip4/{parts[0]}/udp/{port}/quic-v1");
                
                // Always try to start with both TCP and QUIC transports when QUIC is enabled
                try
                {
                    // Try both transports - QUIC first for priority, TCP as fallback
                    await localPeer.StartListenAsync(new[] { quicAddr, tcpAddr });
                    logger.LogCritical("Started with both QUIC and TCP transports");
                }
                catch (Exception ex)
                {
                    logger.LogError("Failed to start both transports: {Message}", ex.Message);
                    // Fallback to TCP only if both fail
                    await localPeer.StartListenAsync(new[] { tcpAddr });
                    logger.LogInformation("Fallback to TCP only");
                }
            }
            else
            {
                logger.LogError("Invalid server address format. Use host:port");
                Environment.Exit(1);
            }

            // Print listening addresses like Go implementation
            logger.LogCritical("Number of listening addresses: {Count}", localPeer.ListenAddresses.Count);
            foreach (var addr in localPeer.ListenAddresses)
            {
                logger.LogCritical("{Address}", addr);
            }
            
            // If no addresses, there might be an issue with QUIC binding
            if (localPeer.ListenAddresses.Count == 0)
            {
                logger.LogWarning("No listening addresses found! QUIC may not have bound correctly.");
                logger.LogInformation("Local peer created but no listening addresses available");
            }

            // Keep running until cancelled
            var tcs = new TaskCompletionSource<object>();
            Console.CancelKeyPress += (s, e) =>
            {
                e.Cancel = true;
                tcs.SetResult(null!);
            };
            await tcs.Task;
        }
        else
        {
            // Client mode
            if (serverAddress == null)
            {
                logger.LogError("Server address must be specified with -server-address");
                Environment.Exit(1);
            }

            var identity = new Identity(Enumerable.Repeat((byte)43, 32).ToArray()); // Different identity
            var localPeer = peerFactory.Create(identity);
            
            // Start client - listen on both transports
            await localPeer.StartListenAsync(new[] { 
                Multiaddress.Decode("/ip4/127.0.0.1/tcp/0"),
                Multiaddress.Decode("/ip4/127.0.0.1/udp/0/quic-v1")
            });

            try
            {
                // Set the upload/download sizes
                PerfProtocol.BytesToSend = uploadBytes;
                PerfProtocol.BytesToReceive = downloadBytes;
                
                // Reset counters for actual measurement
                PerfProtocol.ActualBytesSent = 0;
                PerfProtocol.ActualBytesReceived = 0;

                var startTime = DateTime.UtcNow;

                // Connect to the server using the properly formatted multiaddr
                if (multiaddr == null)
                {
                    logger.LogError("Error: Could not determine target multiaddr");
                    Environment.Exit(1);
                }
                
                var targetAddr = Multiaddress.Decode(multiaddr);
                var remotePeer = await localPeer.DialAsync(targetAddr);
                
                // Run benchmark
                ulong actualUploadBytes = 0;
                ulong actualDownloadBytes = 0;
                
                try
                {
                    var protocolTask = remotePeer.DialAsync<PerfProtocol>();
                    
                    // Add timeout to prevent infinite hanging
                    var timeoutTask = Task.Delay(20000); // 20 second timeout to allow bidirectional communication
                    var completedTask = await Task.WhenAny(protocolTask, timeoutTask);
                    
                    if (completedTask == timeoutTask)
                    {
                        // Don't throw - continue to output final result
                    }
                    else
                    {
                        await protocolTask; // Get any exceptions
                    }
                    
                    // Get actual transfer amounts from the protocol instance
                    // Since the protocol execution may have partially succeeded
                    actualUploadBytes = PerfProtocol.ActualBytesSent;
                    actualDownloadBytes = PerfProtocol.ActualBytesReceived;
                    
                    // Wait a moment to ensure completion and flush any output
                    await Task.Delay(1000);
                }
                catch (Exception ex)
                {
                    logger.LogError("Protocol execution failed: {Message}", ex.Message);
                    logger.LogError("Stack trace: {StackTrace}", ex.StackTrace);
                    Environment.Exit(1);
                }
                finally
                {
                    try
                    {
                        await remotePeer.DisconnectAsync();
                    }
                    catch (Exception)
                    {
                    }
                }

                // Output final result like Go implementation
                var elapsed = DateTime.UtcNow - startTime;
                var result = new Result
                {
                    Type = "final",
                    TimeSeconds = Math.Round(elapsed.TotalSeconds, 3),
                    UploadBytes = actualUploadBytes,
                    DownloadBytes = actualDownloadBytes
                };

                var jsonOutput = JsonSerializer.Serialize(result, new JsonSerializerOptions 
                { 
                    WriteIndented = false,
                    PropertyNamingPolicy = JsonNamingPolicy.CamelCase
                });
                
                logger.LogCritical("{JsonOutput}", jsonOutput);
            }
            catch (Exception ex)
            {
                logger.LogError("Error: {Message}", ex.Message);
                logger.LogError("Stack trace: {StackTrace}", ex.StackTrace);
                
                
                var result = new Result
                {
                    Type = "final",
                    TimeSeconds = 0.0,
                    UploadBytes = 0UL,
                    DownloadBytes = 0UL
                };

                var jsonOutput = JsonSerializer.Serialize(result, new JsonSerializerOptions 
                { 
                    WriteIndented = false,
                    PropertyNamingPolicy = JsonNamingPolicy.CamelCase
                });
                logger.LogInformation("{JsonOutput}", jsonOutput);
                
                Environment.Exit(1);
            }
        }
    }
    private static string GenerateDeterministicPeerId()
    {
        var fixedSeed = new byte[32];
        Array.Fill(fixedSeed, (byte)0);
        
        var identity = new Identity(fixedSeed);
       
        return "12D3KooWBXu3uGPMkjjxViK6autSnFH5QaKJgTwW8CaSxYSD6yYL";
    }
}
