package gossipsub.interop

import io.libp2p.core.dsl.host
import io.libp2p.core.mux.StreamMuxerProtocol
import io.libp2p.protocol.Identify
import io.libp2p.pubsub.NOP_ROUTER_VALIDATOR
import io.libp2p.pubsub.PubsubProtocol
import io.libp2p.pubsub.gossip.Gossip
import io.libp2p.pubsub.gossip.GossipParams
import io.libp2p.pubsub.gossip.builders.GossipRouterBuilder
import io.libp2p.security.noise.NoiseXXSecureChannel
import io.libp2p.transport.tcp.TcpTransport
import java.net.InetAddress
import java.util.concurrent.TimeUnit

fun main(args: Array<String>) {
    val startTimeMillis = System.currentTimeMillis()

    // Parse --params argument
    val paramsIndex = args.indexOf("--params")
    if (paramsIndex == -1 || paramsIndex + 1 >= args.size) {
        System.err.println("Usage: --params <params.json>")
        System.exit(1)
    }
    val paramsFile = args[paramsIndex + 1]

    // Read params
    val params = ExperimentParams.fromJsonFile(paramsFile)

    // Get node ID from hostname
    val hostname = InetAddress.getLocalHost().hostName
    val nodeId = hostname.removePrefix("node").toInt()
    JsonLogger.logStderr("Node ID: $nodeId, Hostname: $hostname")

    // Generate deterministic key
    val privKey = nodePrivKey(nodeId)

    // Extract GossipSub params from script
    val gossipParams = extractGossipSubParams(params.script, nodeId) ?: GossipParams()

    // Create GossipSub router with custom message ID function
    val tracer = MessageTracer()
    val routerBuilder = GossipRouterBuilder(
        params = gossipParams,
        protocol = PubsubProtocol.Gossip_V_1_2,
        messageFactory = ::customIdMessageFactory,
        messageValidator = NOP_ROUTER_VALIDATOR,
    )
    routerBuilder.gossipRouterEventListeners.add(tracer)
    val router = routerBuilder.build()
    val gossip = Gossip(router)

    // Create host
    val libp2pHost = host {
        identity {
            factory = { privKey }
        }
        transports {
            add(::TcpTransport)
        }
        secureChannels {
            add(::NoiseXXSecureChannel)
        }
        muxers {
            +StreamMuxerProtocol.getYamux()
            +StreamMuxerProtocol.Mplex
        }
        network {
            listen("/ip4/0.0.0.0/tcp/9000")
        }
        protocols {
            +Identify()
            +gossip
        }
    }

    libp2pHost.start().get(30, TimeUnit.SECONDS)
    JsonLogger.logStderr("Host started, PeerId: ${libp2pHost.peerId}")

    // Log PeerID to stdout (required by analysis)
    JsonLogger.logStdout("PeerID",
        "id" to libp2pHost.peerId.toBase58(),
        "node_id" to nodeId,
    )

    // Run the experiment
    runExperiment(startTimeMillis, libp2pHost, gossip, nodeId, params)

    // Exit explicitly since Netty's non-daemon threads would keep the JVM alive
    System.exit(0)
}
