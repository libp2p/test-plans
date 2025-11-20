"""DNS resolution support for multiaddr."""

from .base import Resolver
from .dns import DNSResolver

__all__ = ["DNSResolver", "Resolver"]
