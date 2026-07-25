package shared

type VpnConfig struct {
	IsHost     bool
	DeviceName string
	Uuid       string
	Callback   func(string)
}

var config VpnConfig

func SetConfig(cnfg VpnConfig) {
	config = cnfg
}

func GetConfig() VpnConfig {
	return config
}
