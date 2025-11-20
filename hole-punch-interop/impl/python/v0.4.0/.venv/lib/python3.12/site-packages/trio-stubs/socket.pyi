from typing import (
    Union,
    Optional,
    Iterable,
    Tuple,
    List,
    Any,
    TypeVar,
    overload,
)
import sys
import trio
from _typeshed import ReadableBuffer, WriteableBuffer

_T = TypeVar("_T")

import socket as _stdlib_socket
from socket import (
    AF_UNIX as AF_UNIX,
    AF_INET as AF_INET,
    AF_INET6 as AF_INET6,
    SOCK_STREAM as SOCK_STREAM,
    SOCK_DGRAM as SOCK_DGRAM,
    SOCK_RAW as SOCK_RAW,
    SOCK_RDM as SOCK_RDM,
    SOCK_SEQPACKET as SOCK_SEQPACKET,
    SOCK_CLOEXEC as SOCK_CLOEXEC,
    SOCK_NONBLOCK as SOCK_NONBLOCK,
    SOMAXCONN as SOMAXCONN,
    AF_AAL5 as AF_AAL5,
    AF_APPLETALK as AF_APPLETALK,
    AF_ASH as AF_ASH,
    AF_ATMPVC as AF_ATMPVC,
    AF_ATMSVC as AF_ATMSVC,
    AF_AX25 as AF_AX25,
    AF_BLUETOOTH as AF_BLUETOOTH,
    AF_BRIDGE as AF_BRIDGE,
    AF_CAN as AF_CAN,
    AF_DECnet as AF_DECnet,
    AF_ECONET as AF_ECONET,
    AF_IPX as AF_IPX,
    AF_IRDA as AF_IRDA,
    AF_KEY as AF_KEY,
    AF_LLC as AF_LLC,
    AF_NETBEUI as AF_NETBEUI,
    AF_NETLINK as AF_NETLINK,
    AF_NETROM as AF_NETROM,
    AF_PACKET as AF_PACKET,
    AF_PPPOX as AF_PPPOX,
    AF_RDS as AF_RDS,
    AF_ROSE as AF_ROSE,
    AF_ROUTE as AF_ROUTE,
    AF_SECURITY as AF_SECURITY,
    AF_SNA as AF_SNA,
    AF_SYSTEM as AF_SYSTEM,
    AF_TIPC as AF_TIPC,
    AF_UNSPEC as AF_UNSPEC,
    AF_WANPIPE as AF_WANPIPE,
    AF_X25 as AF_X25,
    AI_ADDRCONFIG as AI_ADDRCONFIG,
    AI_ALL as AI_ALL,
    AI_CANONNAME as AI_CANONNAME,
    AI_DEFAULT as AI_DEFAULT,
    AI_MASK as AI_MASK,
    AI_NUMERICHOST as AI_NUMERICHOST,
    AI_NUMERICSERV as AI_NUMERICSERV,
    AI_PASSIVE as AI_PASSIVE,
    AI_V4MAPPED as AI_V4MAPPED,
    AI_V4MAPPED_CFG as AI_V4MAPPED_CFG,
    CAN_EFF_FLAG as CAN_EFF_FLAG,
    CAN_EFF_MASK as CAN_EFF_MASK,
    CAN_ERR_FLAG as CAN_ERR_FLAG,
    CAN_ERR_MASK as CAN_ERR_MASK,
    CAN_RAW as CAN_RAW,
    CAN_RAW_ERR_FILTER as CAN_RAW_ERR_FILTER,
    CAN_RAW_FILTER as CAN_RAW_FILTER,
    CAN_RAW_LOOPBACK as CAN_RAW_LOOPBACK,
    CAN_RAW_RECV_OWN_MSGS as CAN_RAW_RECV_OWN_MSGS,
    CAN_RTR_FLAG as CAN_RTR_FLAG,
    CAN_SFF_MASK as CAN_SFF_MASK,
    EAGAIN as EAGAIN,
    EAI_ADDRFAMILY as EAI_ADDRFAMILY,
    EAI_AGAIN as EAI_AGAIN,
    EAI_BADFLAGS as EAI_BADFLAGS,
    EAI_BADHINTS as EAI_BADHINTS,
    EAI_FAIL as EAI_FAIL,
    EAI_FAMILY as EAI_FAMILY,
    EAI_MAX as EAI_MAX,
    EAI_MEMORY as EAI_MEMORY,
    EAI_NODATA as EAI_NODATA,
    EAI_NONAME as EAI_NONAME,
    EAI_OVERFLOW as EAI_OVERFLOW,
    EAI_PROTOCOL as EAI_PROTOCOL,
    EAI_SERVICE as EAI_SERVICE,
    EAI_SOCKTYPE as EAI_SOCKTYPE,
    EAI_SYSTEM as EAI_SYSTEM,
    INADDR_ALLHOSTS_GROUP as INADDR_ALLHOSTS_GROUP,
    INADDR_ANY as INADDR_ANY,
    INADDR_BROADCAST as INADDR_BROADCAST,
    INADDR_LOOPBACK as INADDR_LOOPBACK,
    INADDR_MAX_LOCAL_GROUP as INADDR_MAX_LOCAL_GROUP,
    INADDR_NONE as INADDR_NONE,
    INADDR_UNSPEC_GROUP as INADDR_UNSPEC_GROUP,
    IPPORT_RESERVED as IPPORT_RESERVED,
    IPPORT_USERRESERVED as IPPORT_USERRESERVED,
    IPPROTO_AH as IPPROTO_AH,
    IPPROTO_BIP as IPPROTO_BIP,
    IPPROTO_DSTOPTS as IPPROTO_DSTOPTS,
    IPPROTO_EGP as IPPROTO_EGP,
    IPPROTO_EON as IPPROTO_EON,
    IPPROTO_ESP as IPPROTO_ESP,
    IPPROTO_FRAGMENT as IPPROTO_FRAGMENT,
    IPPROTO_GGP as IPPROTO_GGP,
    IPPROTO_GRE as IPPROTO_GRE,
    IPPROTO_HELLO as IPPROTO_HELLO,
    IPPROTO_HOPOPTS as IPPROTO_HOPOPTS,
    IPPROTO_ICMP as IPPROTO_ICMP,
    IPPROTO_ICMPV6 as IPPROTO_ICMPV6,
    IPPROTO_IDP as IPPROTO_IDP,
    IPPROTO_IGMP as IPPROTO_IGMP,
    IPPROTO_IP as IPPROTO_IP,
    IPPROTO_IPCOMP as IPPROTO_IPCOMP,
    IPPROTO_IPIP as IPPROTO_IPIP,
    IPPROTO_IPV4 as IPPROTO_IPV4,
    IPPROTO_IPV6 as IPPROTO_IPV6,
    IPPROTO_MAX as IPPROTO_MAX,
    IPPROTO_MOBILE as IPPROTO_MOBILE,
    IPPROTO_ND as IPPROTO_ND,
    IPPROTO_NONE as IPPROTO_NONE,
    IPPROTO_PIM as IPPROTO_PIM,
    IPPROTO_PUP as IPPROTO_PUP,
    IPPROTO_RAW as IPPROTO_RAW,
    IPPROTO_ROUTING as IPPROTO_ROUTING,
    IPPROTO_RSVP as IPPROTO_RSVP,
    IPPROTO_SCTP as IPPROTO_SCTP,
    IPPROTO_TCP as IPPROTO_TCP,
    IPPROTO_TP as IPPROTO_TP,
    IPPROTO_UDP as IPPROTO_UDP,
    IPPROTO_VRRP as IPPROTO_VRRP,
    IPPROTO_XTP as IPPROTO_XTP,
    IPV6_CHECKSUM as IPV6_CHECKSUM,
    IPV6_DONTFRAG as IPV6_DONTFRAG,
    IPV6_DSTOPTS as IPV6_DSTOPTS,
    IPV6_HOPLIMIT as IPV6_HOPLIMIT,
    IPV6_HOPOPTS as IPV6_HOPOPTS,
    IPV6_JOIN_GROUP as IPV6_JOIN_GROUP,
    IPV6_LEAVE_GROUP as IPV6_LEAVE_GROUP,
    IPV6_MULTICAST_HOPS as IPV6_MULTICAST_HOPS,
    IPV6_MULTICAST_IF as IPV6_MULTICAST_IF,
    IPV6_MULTICAST_LOOP as IPV6_MULTICAST_LOOP,
    IPV6_NEXTHOP as IPV6_NEXTHOP,
    IPV6_PATHMTU as IPV6_PATHMTU,
    IPV6_PKTINFO as IPV6_PKTINFO,
    IPV6_RECVDSTOPTS as IPV6_RECVDSTOPTS,
    IPV6_RECVHOPLIMIT as IPV6_RECVHOPLIMIT,
    IPV6_RECVHOPOPTS as IPV6_RECVHOPOPTS,
    IPV6_RECVPATHMTU as IPV6_RECVPATHMTU,
    IPV6_RECVPKTINFO as IPV6_RECVPKTINFO,
    IPV6_RECVRTHDR as IPV6_RECVRTHDR,
    IPV6_RECVTCLASS as IPV6_RECVTCLASS,
    IPV6_RTHDR as IPV6_RTHDR,
    IPV6_RTHDR_TYPE_0 as IPV6_RTHDR_TYPE_0,
    IPV6_RTHDRDSTOPTS as IPV6_RTHDRDSTOPTS,
    IPV6_TCLASS as IPV6_TCLASS,
    IPV6_UNICAST_HOPS as IPV6_UNICAST_HOPS,
    IPV6_USE_MIN_MTU as IPV6_USE_MIN_MTU,
    IPV6_V6ONLY as IPV6_V6ONLY,
    IP_ADD_MEMBERSHIP as IP_ADD_MEMBERSHIP,
    IP_DEFAULT_MULTICAST_LOOP as IP_DEFAULT_MULTICAST_LOOP,
    IP_DEFAULT_MULTICAST_TTL as IP_DEFAULT_MULTICAST_TTL,
    IP_DROP_MEMBERSHIP as IP_DROP_MEMBERSHIP,
    IP_HDRINCL as IP_HDRINCL,
    IP_MAX_MEMBERSHIPS as IP_MAX_MEMBERSHIPS,
    IP_MULTICAST_IF as IP_MULTICAST_IF,
    IP_MULTICAST_LOOP as IP_MULTICAST_LOOP,
    IP_MULTICAST_TTL as IP_MULTICAST_TTL,
    IP_OPTIONS as IP_OPTIONS,
    IP_RECVDSTADDR as IP_RECVDSTADDR,
    IP_RECVOPTS as IP_RECVOPTS,
    IP_RECVRETOPTS as IP_RECVRETOPTS,
    IP_RETOPTS as IP_RETOPTS,
    IP_TOS as IP_TOS,
    IP_TRANSPARENT as IP_TRANSPARENT,
    IP_TTL as IP_TTL,
    IPX_TYPE as IPX_TYPE,
    LOCAL_PEERCRED as LOCAL_PEERCRED,
    MSG_BCAST as MSG_BCAST,
    MSG_BTAG as MSG_BTAG,
    MSG_CMSG_CLOEXEC as MSG_CMSG_CLOEXEC,
    MSG_CONFIRM as MSG_CONFIRM,
    MSG_CTRUNC as MSG_CTRUNC,
    MSG_DONTROUTE as MSG_DONTROUTE,
    MSG_DONTWAIT as MSG_DONTWAIT,
    MSG_EOF as MSG_EOF,
    MSG_EOR as MSG_EOR,
    MSG_ERRQUEUE as MSG_ERRQUEUE,
    MSG_ETAG as MSG_ETAG,
    MSG_FASTOPEN as MSG_FASTOPEN,
    MSG_MCAST as MSG_MCAST,
    MSG_MORE as MSG_MORE,
    MSG_NOSIGNAL as MSG_NOSIGNAL,
    MSG_NOTIFICATION as MSG_NOTIFICATION,
    MSG_OOB as MSG_OOB,
    MSG_PEEK as MSG_PEEK,
    MSG_TRUNC as MSG_TRUNC,
    MSG_WAITALL as MSG_WAITALL,
    NI_DGRAM as NI_DGRAM,
    NI_MAXHOST as NI_MAXHOST,
    NI_MAXSERV as NI_MAXSERV,
    NI_NAMEREQD as NI_NAMEREQD,
    NI_NOFQDN as NI_NOFQDN,
    NI_NUMERICHOST as NI_NUMERICHOST,
    NI_NUMERICSERV as NI_NUMERICSERV,
    PACKET_BROADCAST as PACKET_BROADCAST,
    PACKET_FASTROUTE as PACKET_FASTROUTE,
    PACKET_HOST as PACKET_HOST,
    PACKET_LOOPBACK as PACKET_LOOPBACK,
    PACKET_MULTICAST as PACKET_MULTICAST,
    PACKET_OTHERHOST as PACKET_OTHERHOST,
    PACKET_OUTGOING as PACKET_OUTGOING,
    PF_CAN as PF_CAN,
    PF_PACKET as PF_PACKET,
    PF_RDS as PF_RDS,
    SCM_CREDENTIALS as SCM_CREDENTIALS,
    SCM_CREDS as SCM_CREDS,
    SCM_RIGHTS as SCM_RIGHTS,
    SHUT_RD as SHUT_RD,
    SHUT_RDWR as SHUT_RDWR,
    SHUT_WR as SHUT_WR,
    SOL_ATALK as SOL_ATALK,
    SOL_AX25 as SOL_AX25,
    SOL_CAN_BASE as SOL_CAN_BASE,
    SOL_CAN_RAW as SOL_CAN_RAW,
    SOL_HCI as SOL_HCI,
    SOL_IP as SOL_IP,
    SOL_IPX as SOL_IPX,
    SOL_NETROM as SOL_NETROM,
    SOL_RDS as SOL_RDS,
    SOL_ROSE as SOL_ROSE,
    SOL_SOCKET as SOL_SOCKET,
    SOL_TCP as SOL_TCP,
    SOL_TIPC as SOL_TIPC,
    SOL_UDP as SOL_UDP,
    SO_ACCEPTCONN as SO_ACCEPTCONN,
    SO_BINDTODEVICE as SO_BINDTODEVICE,
    SO_BROADCAST as SO_BROADCAST,
    SO_DEBUG as SO_DEBUG,
    SO_DONTROUTE as SO_DONTROUTE,
    SO_ERROR as SO_ERROR,
    SO_EXCLUSIVEADDRUSE as SO_EXCLUSIVEADDRUSE,
    SO_KEEPALIVE as SO_KEEPALIVE,
    SO_LINGER as SO_LINGER,
    SO_MARK as SO_MARK,
    SO_OOBINLINE as SO_OOBINLINE,
    SO_PASSCRED as SO_PASSCRED,
    SO_PEERCRED as SO_PEERCRED,
    SO_PRIORITY as SO_PRIORITY,
    SO_RCVBUF as SO_RCVBUF,
    SO_RCVLOWAT as SO_RCVLOWAT,
    SO_RCVTIMEO as SO_RCVTIMEO,
    SO_REUSEADDR as SO_REUSEADDR,
    SO_REUSEPORT as SO_REUSEPORT,
    SO_SETFIB as SO_SETFIB,
    SO_SNDBUF as SO_SNDBUF,
    SO_SNDLOWAT as SO_SNDLOWAT,
    SO_SNDTIMEO as SO_SNDTIMEO,
    SO_TYPE as SO_TYPE,
    SO_USELOOPBACK as SO_USELOOPBACK,
    TCP_CORK as TCP_CORK,
    TCP_DEFER_ACCEPT as TCP_DEFER_ACCEPT,
    TCP_FASTOPEN as TCP_FASTOPEN,
    TCP_INFO as TCP_INFO,
    TCP_KEEPCNT as TCP_KEEPCNT,
    TCP_KEEPIDLE as TCP_KEEPIDLE,
    TCP_KEEPINTVL as TCP_KEEPINTVL,
    TCP_LINGER2 as TCP_LINGER2,
    TCP_MAXSEG as TCP_MAXSEG,
    TCP_NODELAY as TCP_NODELAY,
    TCP_NOTSENT_LOWAT as TCP_NOTSENT_LOWAT,
    TCP_QUICKACK as TCP_QUICKACK,
    TCP_SYNCNT as TCP_SYNCNT,
    TCP_WINDOW_CLAMP as TCP_WINDOW_CLAMP,
    TIPC_ADDR_ID as TIPC_ADDR_ID,
    TIPC_ADDR_NAME as TIPC_ADDR_NAME,
    TIPC_ADDR_NAMESEQ as TIPC_ADDR_NAMESEQ,
    TIPC_CFG_SRV as TIPC_CFG_SRV,
    TIPC_CLUSTER_SCOPE as TIPC_CLUSTER_SCOPE,
    TIPC_CONN_TIMEOUT as TIPC_CONN_TIMEOUT,
    TIPC_CRITICAL_IMPORTANCE as TIPC_CRITICAL_IMPORTANCE,
    TIPC_DEST_DROPPABLE as TIPC_DEST_DROPPABLE,
    TIPC_HIGH_IMPORTANCE as TIPC_HIGH_IMPORTANCE,
    TIPC_IMPORTANCE as TIPC_IMPORTANCE,
    TIPC_LOW_IMPORTANCE as TIPC_LOW_IMPORTANCE,
    TIPC_MEDIUM_IMPORTANCE as TIPC_MEDIUM_IMPORTANCE,
    TIPC_NODE_SCOPE as TIPC_NODE_SCOPE,
    TIPC_PUBLISHED as TIPC_PUBLISHED,
    TIPC_SRC_DROPPABLE as TIPC_SRC_DROPPABLE,
    TIPC_SUB_CANCEL as TIPC_SUB_CANCEL,
    TIPC_SUB_PORTS as TIPC_SUB_PORTS,
    TIPC_SUB_SERVICE as TIPC_SUB_SERVICE,
    TIPC_SUBSCR_TIMEOUT as TIPC_SUBSCR_TIMEOUT,
    TIPC_TOP_SRV as TIPC_TOP_SRV,
    TIPC_WAIT_FOREVER as TIPC_WAIT_FOREVER,
    TIPC_WITHDRAWN as TIPC_WITHDRAWN,
    TIPC_ZONE_SCOPE as TIPC_ZONE_SCOPE,
    RDS_CANCEL_SENT_TO as RDS_CANCEL_SENT_TO,
    RDS_CMSG_RDMA_ARGS as RDS_CMSG_RDMA_ARGS,
    RDS_CMSG_RDMA_DEST as RDS_CMSG_RDMA_DEST,
    RDS_CMSG_RDMA_MAP as RDS_CMSG_RDMA_MAP,
    RDS_CMSG_RDMA_STATUS as RDS_CMSG_RDMA_STATUS,
    RDS_CMSG_RDMA_UPDATE as RDS_CMSG_RDMA_UPDATE,
    RDS_CONG_MONITOR as RDS_CONG_MONITOR,
    RDS_FREE_MR as RDS_FREE_MR,
    RDS_GET_MR as RDS_GET_MR,
    RDS_GET_MR_FOR_DEST as RDS_GET_MR_FOR_DEST,
    RDS_RDMA_DONTWAIT as RDS_RDMA_DONTWAIT,
    RDS_RDMA_FENCE as RDS_RDMA_FENCE,
    RDS_RDMA_INVALIDATE as RDS_RDMA_INVALIDATE,
    RDS_RDMA_NOTIFY_ME as RDS_RDMA_NOTIFY_ME,
    RDS_RDMA_READWRITE as RDS_RDMA_READWRITE,
    RDS_RDMA_SILENT as RDS_RDMA_SILENT,
    RDS_RDMA_USE_ONCE as RDS_RDMA_USE_ONCE,
    RDS_RECVERR as RDS_RECVERR,
    CAN_BCM as CAN_BCM,
    CAN_BCM_TX_SETUP as CAN_BCM_TX_SETUP,
    CAN_BCM_TX_DELETE as CAN_BCM_TX_DELETE,
    CAN_BCM_TX_READ as CAN_BCM_TX_READ,
    CAN_BCM_TX_SEND as CAN_BCM_TX_SEND,
    CAN_BCM_RX_SETUP as CAN_BCM_RX_SETUP,
    CAN_BCM_RX_DELETE as CAN_BCM_RX_DELETE,
    CAN_BCM_RX_READ as CAN_BCM_RX_READ,
    CAN_BCM_TX_STATUS as CAN_BCM_TX_STATUS,
    CAN_BCM_TX_EXPIRED as CAN_BCM_TX_EXPIRED,
    CAN_BCM_RX_STATUS as CAN_BCM_RX_STATUS,
    CAN_BCM_RX_TIMEOUT as CAN_BCM_RX_TIMEOUT,
    CAN_BCM_RX_CHANGED as CAN_BCM_RX_CHANGED,
    AF_LINK as AF_LINK,
    CAN_RAW_FD_FRAMES as CAN_RAW_FD_FRAMES,
    AddressFamily,
    SocketKind,
)

IP_BIND_ADDRESS_NO_PORT: int

if sys.version_info >= (3, 6):
    from socket import (
        AF_ALG as AF_ALG,
        SOL_ALG as SOL_ALG,
        ALG_SET_KEY as ALG_SET_KEY,
        ALG_SET_IV as ALG_SET_IV,
        ALG_SET_OP as ALG_SET_OP,
        ALG_SET_AEAD_ASSOCLEN as ALG_SET_AEAD_ASSOCLEN,
        ALG_SET_AEAD_AUTHSIZE as ALG_SET_AEAD_AUTHSIZE,
        ALG_SET_PUBKEY as ALG_SET_PUBKEY,
        ALG_OP_DECRYPT as ALG_OP_DECRYPT,
        ALG_OP_ENCRYPT as ALG_OP_ENCRYPT,
        ALG_OP_SIGN as ALG_OP_SIGN,
        ALG_OP_VERIFY as ALG_OP_VERIFY,
    )

from socket import (
    gaierror as gaierror,
    herror as herror,
    gethostname as gethostname,
    ntohl as ntohl,
    ntohs as ntohs,
    htonl as htonl,
    htons as htons,
    inet_aton as inet_aton,
    inet_ntoa as inet_ntoa,
    inet_pton as inet_pton,
    inet_ntop as inet_ntop,
    sethostname as sethostname,
    if_nameindex as if_nameindex,
    if_nametoindex as if_nametoindex,
    if_indextoname as if_indextoname,
)

def set_custom_hostname_resolver(
    hostname_resolver: Optional[trio.abc.HostnameResolver],
) -> Optional[trio.abc.HostnameResolver]: ...
def set_custom_socket_factory(
    socket_factory: Optional[trio.abc.SocketFactory],
) -> Optional[trio.abc.SocketFactory]: ...
async def getnameinfo(sockaddr: Tuple[Any, ...], flags: int) -> Tuple[str, str]: ...
async def getprotobyname(name: str) -> int: ...
async def getaddrinfo(
    host: Union[bytes, str, None],
    port: Union[str, int, None],
    family: int = ...,
    type: int = ...,
    proto: int = ...,
    flags: int = ...,
) -> List[
    Tuple[
        AddressFamily,
        SocketKind,
        int,
        str,
        Union[Tuple[str, int], Tuple[str, int, int, int]],
    ]
]: ...

class SocketType:
    def __enter__(self: _T) -> _T: ...
    def __exit__(self, *args: Any) -> None: ...
    @property
    def did_shutdown_SHUT_WR(self) -> bool: ...
    @property
    def family(self) -> int: ...
    @property
    def type(self) -> int: ...
    @property
    def proto(self) -> int: ...
    def dup(self) -> SocketType: ...
    def close(self) -> None: ...
    async def bind(self, address: Union[Tuple[Any, ...], str, bytes]) -> None: ...
    def shutdown(self, flag: int) -> None: ...
    def is_readable(self) -> bool: ...
    async def wait_writable(self) -> None: ...
    async def accept(self) -> Tuple[SocketType, Any]: ...
    async def connect(self, address: Union[Tuple[Any, ...], str, bytes]) -> None: ...
    async def recv(self, bufsize: int, flags: int = ...) -> bytes: ...
    async def recv_into(
        self, buffer: WriteableBuffer, nbytes: int = ..., flags: int = ...
    ) -> int: ...
    async def recvfrom(self, bufsize: int, flags: int = ...) -> Tuple[bytes, Any]: ...
    async def recvfrom_into(
        self, buffer: WriteableBuffer, nbytes: int = ..., flags: int = ...
    ) -> Tuple[int, Any]: ...
    async def recvmsg(
        self, bufsize: int, ancbufsize: int = ..., flags: int = ...
    ) -> Tuple[bytes, List[Tuple[int, int, bytes]], int, Any]: ...
    async def recvmsg_into(
        self,
        buffers: Iterable[WriteableBuffer],
        ancbufsize: int = ...,
        flags: int = ...,
    ) -> Tuple[int, List[Tuple[int, int, bytes]], int, Any]: ...
    async def send(self, data: ReadableBuffer, flags: int = ...) -> int: ...
    async def sendmsg(
        self,
        buffers: Iterable[ReadableBuffer],
        ancdata: Iterable[Tuple[int, int, Union[bytes, memoryview]]] = ...,
        flags: int = ...,
        address: Union[Tuple[Any, ...], str] = ...,
    ) -> int: ...
    @overload
    async def sendto(
        self, data: ReadableBuffer, address: Union[Tuple[Any, ...], str]
    ) -> int: ...
    @overload
    async def sendto(
        self, data: ReadableBuffer, flags: int, address: Union[Tuple[Any, ...], str]
    ) -> int: ...
    def detach(self) -> int: ...
    def get_inheritable(self) -> bool: ...
    def set_inheritable(self, inheritable: bool) -> None: ...
    def fileno(self) -> int: ...
    def getpeername(self) -> Any: ...
    def getsockname(self) -> Any: ...
    @overload
    def getsockopt(self, level: int, optname: int) -> int: ...
    @overload
    def getsockopt(self, level: int, optname: int, buflen: int) -> bytes: ...
    def setsockopt(
        self, level: int, optname: int, value: Union[int, bytes]
    ) -> None: ...
    def listen(self, backlog: int = ...) -> None: ...
    def share(self, process_id: int) -> bytes: ...

def fromfd(fd: int, family: int, type: int, proto: int = ...) -> SocketType: ...
def fromshare(data: bytes) -> SocketType: ...
def from_stdlib_socket(sock: _stdlib_socket.socket) -> SocketType: ...

# https://github.com/python/typeshed/blob/4ca5ee98df5654d0db7f5b24cd2bd3b3fe54f313/stdlib/socket.pyi#L750
def socketpair(
    family: int | None = ..., type: int = ..., proto: int = ...
) -> Tuple[SocketType, SocketType]: ...
def socket(
    family: int = ..., type: int = ..., proto: int = ..., fileno: Optional[int] = ...
) -> SocketType: ...
