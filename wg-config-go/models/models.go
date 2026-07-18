package models

type SignalingPeer struct {
	UID                string `json:"uid"`
	PublicIP           string `json:"publicIp"`
	PublicPort         int    `json:"publicPort"`
	WireguardPublicKey string `json:"wireguardPublicKey"`
	DeviceName         string `json:"deviceName"`
	Online             bool   `json:"online"`
	NetworkType        string `json:"networkType"`
	UpdatedAt          int64  `json:"updatedAt"`
	LastSeen           int64  `json:"lastSeen"`
	ProtocolVersion    int    `json:"protocolVersion"`
}

func (p *SignalingPeer) ToMap() map[string]interface{} {
	return map[string]interface{}{
		"uid":                p.UID,
		"publicIp":           p.PublicIP,
		"publicPort":         p.PublicPort,
		"wireguardPublicKey": p.WireguardPublicKey,
		"deviceName":         p.DeviceName,
		"online":             p.Online,
		"networkType":        p.NetworkType,
		"updatedAt":          p.UpdatedAt,
		"lastSeen":           p.LastSeen,
		"protocolVersion":    p.ProtocolVersion,
	}
}

type WireGuardPeer struct {
	EndpointIP    string
	EndpointPort  int
	PeerPublicKey string
	MyPrivateKey  string
	MyAddress     string
}
