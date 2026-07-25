package utils

import (
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"strings"

	"golang.zx2c4.com/wireguard/z/models"
)

type WireGuardConfigGenerator struct{}

func base64ToHex(s string) (string, error) {
	b, err := base64.StdEncoding.DecodeString(s)
	if err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func (g *WireGuardConfigGenerator) Generate(
	peer models.WireGuardPeer,
	dns string,
	allowedIPs string,
	persistentKeepalive int,
) string {
	if allowedIPs == "" {
		allowedIPs = "0.0.0.0/0"
	}
	if persistentKeepalive == 0 {
		persistentKeepalive = 5
	}

	var sb strings.Builder

	// sb.WriteString("[Interface]\n")
	// sb.WriteString(fmt.Sprintf("PrivateKey = %s\n", peer.MyPrivateKey))
	// sb.WriteString(fmt.Sprintf("Address = %s\n", peer.MyAddress))

	// if dns != "" {
	// 	sb.WriteString(fmt.Sprintf("DNS = %s\n", dns))
	// }

	// sb.WriteString("\n")

	// sb.WriteString("[Peer]\n")
	// sb.WriteString(fmt.Sprintf("PublicKey = %s\n", peer.PeerPublicKey))
	// sb.WriteString(fmt.Sprintf("Endpoint = %s:%d\n", peer.EndpointIP, peer.EndpointPort))
	// sb.WriteString(fmt.Sprintf("AllowedIPs = %s\n", allowedIPs))
	// sb.WriteString(fmt.Sprintf("PersistentKeepalive = %d\n", persistentKeepalive))

	priv, err := base64ToHex(peer.MyPrivateKey)
	if err != nil {
		return ""
	}

	pub, err := base64ToHex(peer.PeerPublicKey)
	if err != nil {
		return ""
	}

	sb.WriteString(fmt.Sprintf("private_key=%s\n", priv))
	sb.WriteString("replace_peers=true\n\n")

	sb.WriteString(fmt.Sprintf("public_key=%s\n", pub))
	sb.WriteString(fmt.Sprintf("endpoint=%s:%d\n", peer.EndpointIP, peer.EndpointPort))
	sb.WriteString("replace_allowed_ips=true\n")
	sb.WriteString(fmt.Sprintf("allowed_ip=%s\n", allowedIPs))
	sb.WriteString(fmt.Sprintf("persistent_keepalive_interval=%d\n", 15))
	return sb.String()
}
