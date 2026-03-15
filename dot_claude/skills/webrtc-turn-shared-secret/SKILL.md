---
name: webrtc-turn-shared-secret
description: |
  Generate ephemeral TURN credentials from a shared secret for coturn (--use-auth-secret mode).
  Use when: (1) WebRTC ICE connection state goes to "failed" or stays at "checking",
  (2) STUN-only config can't establish media path through NAT/k8s,
  (3) coturn is configured with --use-auth-secret and you need time-limited credentials,
  (4) need to pass TURN credentials to both server-side (pion/webrtc) and client-side
  (browser RTCPeerConnection). Covers credential generation, Go implementation, and
  client-side WebRTC configuration.
author: Claude Code
version: 1.0.0
date: 2026-02-21
---

# WebRTC TURN Server with Shared Secret Credentials

## Problem
WebRTC connections fail with `ICE connection state: failed` when peers are behind NAT
(especially in Kubernetes pods). STUN alone can't establish a media path through
symmetric NAT. A TURN server is needed, and coturn's shared secret mode requires
generating ephemeral credentials.

## Context / Trigger Conditions
- `webrtc: ICE connection state: failed` in server logs
- `ICE connection state: failed` in browser console
- WebRTC signaling (offer/answer) succeeds but no media flows
- Server is in a k8s pod with private IP, client is behind NAT
- coturn configured with `--use-auth-secret` or `use-auth-secret` in turnserver.conf

## Solution

### Credential Generation (TURN REST API)

```
username = Unix timestamp of expiry (e.g., "1740200000")
password = Base64(HMAC-SHA1(username, shared_secret))
```

### Go Implementation

```go
import (
    "crypto/hmac"
    "crypto/sha1"
    "encoding/base64"
    "fmt"
    "time"
)

func GenerateTURNCredentials(turnURL, sharedSecret string, ttl time.Duration) (urls []string, username, credential string) {
    expiry := time.Now().Add(ttl).Unix()
    username = fmt.Sprintf("%d", expiry)
    mac := hmac.New(sha1.New, []byte(sharedSecret))
    mac.Write([]byte(username))
    credential = base64.StdEncoding.EncodeToString(mac.Sum(nil))
    return []string{turnURL}, username, credential
}
```

### Server-side (pion/webrtc)

```go
iceServers := []webrtc.ICEServer{
    {URLs: []string{"stun:stun.l.google.com:19302"}},
    {
        URLs:           []string{"turn:your-turn-server:3478"},
        Username:       username,
        Credential:     credential,
        CredentialType: webrtc.ICECredentialTypePassword,
    },
}
pc, _ := webrtc.NewPeerConnection(webrtc.Configuration{ICEServers: iceServers})
```

### Client-side (browser)

Send ICE config from server to client via signaling channel (WebSocket),
then create RTCPeerConnection with it:

```javascript
// Server sends: { type: "iceServers", iceServers: [...] }
socket.onmessage = (e) => {
    const msg = JSON.parse(e.data);
    if (msg.type === 'iceServers') {
        pc = new RTCPeerConnection({ iceServers: msg.iceServers });
    }
};
```

## Verification

1. Server logs should show `ICE connection state: connected` (not `failed`)
2. Browser console should show `ICE connection state: connected`
3. Test TURN connectivity: `turnutils_uclient -u username -w credential turn-server-ip`

## Notes
- Both server and client need the TURN credentials — the server uses them for its
  PeerConnection, and the client needs them for its RTCPeerConnection
- Credentials are time-limited (TTL); generate fresh ones per session
- If TURN server hostname doesn't resolve from k8s pods (CoreDNS custom zones),
  use the IP address directly: `turn:1.2.3.4:3478`
- STUN is still useful as a fallback for direct connections; keep it in the ICE
  servers list alongside TURN
- The shared secret must match coturn's `static-auth-secret` config
