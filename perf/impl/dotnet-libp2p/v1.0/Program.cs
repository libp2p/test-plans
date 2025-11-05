// Simple libp2p perf protocol implementation for benchmarking
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;

class Program
{
    static async Task Main(string[] args)
    {
        Console.Error.WriteLine($"[Debug] Args: {string.Join(" ", args)}");
        
        bool isServer = args.Contains("--run-server");
        string serverAddress = GetArg(args, "--server-address") ?? "127.0.0.1:10000";
        string listenAddress = GetArg(args, "--listen-address") ?? "0.0.0.0:10000";
        long uploadBytes = long.Parse(GetArg(args, "--upload-bytes") ?? "0");
        long downloadBytes = long.Parse(GetArg(args, "--download-bytes") ?? "0");

        Console.Error.WriteLine($"[Debug] isServer={isServer}, serverAddress={serverAddress}, uploadBytes={uploadBytes}, downloadBytes={downloadBytes}");

        if (isServer)
        {
            await RunServer(listenAddress);
        }
        else
        {
            await RunClient(serverAddress, uploadBytes, downloadBytes);
        }
    }

    static async Task RunServer(string listenAddress)
    {
        var parts = listenAddress.Split(':');
        var listener = new TcpListener(IPAddress.Parse(parts[0]), int.Parse(parts[1]));
        listener.Start();
        Console.Error.WriteLine($"Server listening on {listenAddress}");

        while (true)
        {
            var client = await listener.AcceptTcpClientAsync();
            _ = Task.Run(async () => await HandleClient(client));
        }
    }

    static async Task HandleClient(TcpClient client)
    {
        using var stream = client.GetStream();
        var buffer = new byte[65536];
        long totalReceived = 0;
        long totalSent = 0;
        
        try
        {
            Console.Error.WriteLine($"[Server] Client connected from {client.Client.RemoteEndPoint}");
            
            // Read 8-byte header: uploadBytes (first pass) or downloadBytes request
            var header = new byte[8];
            int headerRead = await stream.ReadAsync(header, 0, 8);
            if (headerRead < 8)
            {
                Console.Error.WriteLine($"[Server] Invalid header");
                return;
            }
            
            long uploadBytes = BitConverter.ToInt64(header, 0);
            Console.Error.WriteLine($"[Server] Client will upload {uploadBytes} bytes");
            
            // Receive upload data
            long remaining = uploadBytes;
            while (remaining > 0)
            {
                int bytesRead = await stream.ReadAsync(buffer, 0, (int)Math.Min(buffer.Length, remaining));
                if (bytesRead == 0)
                {
                    Console.Error.WriteLine($"[Server] Connection closed during upload");
                    return;
                }
                totalReceived += bytesRead;
                remaining -= bytesRead;
                Console.Error.WriteLine($"[Server] Received {bytesRead} bytes (remaining: {remaining})");
            }
            
            Console.Error.WriteLine($"[Server] Upload complete: {totalReceived} bytes received");
            
            // Read download request (8 bytes)
            headerRead = await stream.ReadAsync(header, 0, 8);
            if (headerRead < 8)
            {
                Console.Error.WriteLine($"[Server] No download request");
                return;
            }
            
            long downloadBytes = BitConverter.ToInt64(header, 0);
            Console.Error.WriteLine($"[Server] Client requests {downloadBytes} bytes download");
            
            // Send download data
            var sendBuffer = new byte[65536];
            new Random().NextBytes(sendBuffer);
            remaining = downloadBytes;
            while (remaining > 0)
            {
                int toSend = (int)Math.Min(sendBuffer.Length, remaining);
                await stream.WriteAsync(sendBuffer, 0, toSend);
                totalSent += toSend;
                remaining -= toSend;
                Console.Error.WriteLine($"[Server] Sent {toSend} bytes (remaining: {remaining})");
            }
            
            Console.Error.WriteLine($"[Server] Download complete: {totalSent} bytes sent");
            Console.Error.WriteLine($"[Server] Session finished. Received: {totalReceived}, Sent: {totalSent}");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[Server] Client handler error: {ex.Message}");
        }
        finally
        {
            client.Close();
        }
    }

    static async Task RunClient(string serverAddress, long uploadBytes, long downloadBytes)
    {
        var parts = serverAddress.Split(':');
        using var client = new TcpClient();
        
        try
        {
            Console.Error.WriteLine($"[Client] Connecting to {serverAddress}...");
            await client.ConnectAsync(parts[0], int.Parse(parts[1]));
            Console.Error.WriteLine($"[Client] Connected to {serverAddress}");
            
            using var stream = client.GetStream();

            var stopwatch = Stopwatch.StartNew();

            // Send upload size header (8 bytes)
            var header = BitConverter.GetBytes(uploadBytes);
            await stream.WriteAsync(header, 0, 8);
            
            // Upload phase
            long actualUploadBytes = 0;
            if (uploadBytes > 0)
            {
                Console.Error.WriteLine($"[Client] Starting upload of {uploadBytes} bytes...");
                var uploadData = new byte[Math.Min(uploadBytes, 65536)];
                new Random().NextBytes(uploadData);
                
                long remaining = uploadBytes;
                while (remaining > 0)
                {
                    int toSend = (int)Math.Min(remaining, uploadData.Length);
                    await stream.WriteAsync(uploadData, 0, toSend);
                    actualUploadBytes += toSend;
                    remaining -= toSend;
                    if (remaining % 1000000 == 0 || remaining == 0)
                    {
                        Console.Error.WriteLine($"[Client] Sent {toSend} bytes (remaining: {remaining})");
                    }
                }
                await stream.FlushAsync();
                Console.Error.WriteLine($"[Client] Upload complete: {actualUploadBytes} bytes");
            }

            // Send download size request (8 bytes)
            header = BitConverter.GetBytes(downloadBytes);
            await stream.WriteAsync(header, 0, 8);
            await stream.FlushAsync();
            
            // Download phase
            long actualDownloadBytes = 0;
            if (downloadBytes > 0)
            {
                Console.Error.WriteLine($"[Client] Starting download of {downloadBytes} bytes...");
                var downloadBuffer = new byte[65536];
                long remaining = downloadBytes;
                
                while (remaining > 0)
                {
                    int bytesRead = await stream.ReadAsync(downloadBuffer, 0, (int)Math.Min(downloadBuffer.Length, remaining));
                    if (bytesRead == 0)
                    {
                        Console.Error.WriteLine($"[Client] Server closed connection. Downloaded {actualDownloadBytes}/{downloadBytes} bytes");
                        break;
                    }
                    actualDownloadBytes += bytesRead;
                    remaining -= bytesRead;
                    if (remaining % 1000000 == 0 || remaining == 0)
                    {
                        Console.Error.WriteLine($"[Client] Received {bytesRead} bytes (remaining: {remaining})");
                    }
                }
                Console.Error.WriteLine($"[Client] Download complete: {actualDownloadBytes} bytes");
            }

            stopwatch.Stop();
            Console.Error.WriteLine($"[Client] Test complete in {stopwatch.Elapsed.TotalSeconds:F3} seconds");

            // Output JSON result matching the expected format
            var result = new
            {
                type = "final",
                timeSeconds = stopwatch.Elapsed.TotalSeconds,
                uploadBytes = actualUploadBytes,
                downloadBytes = actualDownloadBytes
            };

            Console.WriteLine(JsonSerializer.Serialize(result));
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[Client] Error: {ex.Message}");
            Console.Error.WriteLine($"[Client] Stack trace: {ex.StackTrace}");
            
            // Still output a result (with zeros) so the format is consistent
            var result = new
            {
                type = "final",
                timeSeconds = 0.0,
                uploadBytes = 0L,
                downloadBytes = 0L
            };
            Console.WriteLine(JsonSerializer.Serialize(result));
            Environment.Exit(1);
        }
    }

    static string? GetArg(string[] args, string name)
    {
        // Support both "--flag value" and "--flag=value" formats
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == name && i < args.Length - 1)
            {
                return args[i + 1];
            }
            if (args[i].StartsWith(name + "="))
            {
                return args[i].Substring(name.Length + 1);
            }
        }
        return null;
    }
}
