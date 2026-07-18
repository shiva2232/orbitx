package utils

import (
	"fmt"
	"orbitx/models"
	"strings"
)

type WireGuardConfigGenerator struct{}

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

	sb.WriteString("[Interface]\n")
	sb.WriteString(fmt.Sprintf("PrivateKey = %s\n", peer.MyPrivateKey))
	sb.WriteString(fmt.Sprintf("Address = %s\n", peer.MyAddress))

	if dns != "" {
		sb.WriteString(fmt.Sprintf("DNS = %s\n", dns))
	}

	sb.WriteString("\n")

	sb.WriteString("[Peer]\n")
	sb.WriteString(fmt.Sprintf("PublicKey = %s\n", peer.PeerPublicKey))
	sb.WriteString(fmt.Sprintf("Endpoint = %s:%d\n", peer.EndpointIP, peer.EndpointPort))
	sb.WriteString(fmt.Sprintf("AllowedIPs = %s\n", allowedIPs))
	sb.WriteString(fmt.Sprintf("PersistentKeepalive = %d\n", persistentKeepalive))

	return sb.String()
}
