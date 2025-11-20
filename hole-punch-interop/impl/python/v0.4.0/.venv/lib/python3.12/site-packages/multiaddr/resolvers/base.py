"""Base resolver interface for multiaddr."""

from typing import Protocol as TypeProtocol

from ..multiaddr import Multiaddr


class Resolver(TypeProtocol):
    """Protocol for multiaddr resolvers."""

    async def resolve(self, maddr: Multiaddr) -> list[Multiaddr]:
        """Resolve a multiaddr to its final form.

        Parameters
        ----------
        maddr : ~multiaddr.multiaddr.Multiaddr
            The multiaddr to resolve.

        Returns
        -------
        list[~multiaddr.multiaddr.Multiaddr]
            The resolved multiaddrs.

        Raises
        ------
        ~multiaddr.exceptions.ResolveError
            If the multiaddr cannot be resolved.
        """
        ...
