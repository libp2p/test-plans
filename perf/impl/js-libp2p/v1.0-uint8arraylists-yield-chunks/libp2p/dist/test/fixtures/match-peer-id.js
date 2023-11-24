import Sinon from 'sinon';
export function matchPeerId(peerId) {
    return Sinon.match(p => p.toString() === peerId.toString());
}
//# sourceMappingURL=match-peer-id.js.map