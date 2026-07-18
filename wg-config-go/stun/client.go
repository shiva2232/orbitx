package stun

import (
	"crypto/rand"
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"sync"
	"time"
)

const (
	BindingRequest   = 0x0001
	BindingResponse  = 0x0101
	MagicCookie      = 0x2112A442
	XorMappedAddress = 0x0020
)

type StunResult struct {
	Address net.IP
	Port    int
}

type StunClient struct {
	conn              *net.UDPConn
	publicAddress     net.IP
	publicPort        int
	onEndpointChanged func(addr net.IP, port int, changed bool)
	mu                sync.Mutex
	stopChan          chan struct{}
}

func NewStunClient() *StunClient {
	return &StunClient{
		stopChan: make(chan struct{}),
	}
}

func (c *StunClient) sendBindingRequest(addr *net.UDPAddr) error {
	tid := make([]byte, 12)
	if _, err := rand.Read(tid); err != nil {
		return err
	}

	buf := make([]byte, 20)
	binary.BigEndian.PutUint16(buf[0:2], BindingRequest)
	binary.BigEndian.PutUint16(buf[2:4], 0) // length
	binary.BigEndian.PutUint32(buf[4:8], MagicCookie)
	copy(buf[8:20], tid)

	_, err := c.conn.WriteToUDP(buf, addr)
	return err
}

func (c *StunClient) parse(buf []byte) (*StunResult, error) {
	if len(buf) < 20 {
		return nil, errors.New("short message")
	}

	cookie := buf[4:8]
	offset := 20
	for offset+4 <= len(buf) {
		attrType := binary.BigEndian.Uint16(buf[offset : offset+2])
		attrLen := int(binary.BigEndian.Uint16(buf[offset+2 : offset+4]))
		if offset+4+attrLen > len(buf) {
			break
		}

		if attrType == XorMappedAddress {
			if attrLen < 8 {
				return nil, errors.New("short XOR-MAPPED-ADDRESS")
			}
			family := buf[offset+5]
			if family != 0x01 { // IPv4
				return nil, fmt.Errorf("unsupported family: %d", family)
			}

			xPort := binary.BigEndian.Uint16(buf[offset+6 : offset+8])
			port := int(xPort ^ 0x2112)

			ip := make(net.IP, 4)
			for i := 0; i < 4; i++ {
				ip[i] = buf[offset+8+i] ^ cookie[i]
			}
			return &StunResult{Address: ip, Port: port}, nil
		}

		offset += 4 + attrLen
		for offset%4 != 0 {
			offset++
		}
	}
	return nil, errors.New("XOR-MAPPED-ADDRESS not found")
}

func (c *StunClient) listenLoop() {
	buf := make([]byte, 1024)
	for {
		select {
		case <-c.stopChan:
			return
		default:
			c.conn.SetReadDeadline(time.Now().Add(time.Second))
			n, _, err := c.conn.ReadFromUDP(buf)
			if err != nil {
				continue
			}

			res, err := c.parse(buf[:n])
			if err != nil {
				continue
			}

			c.mu.Lock()
			changed := c.publicAddress == nil || !c.publicAddress.Equal(res.Address) || c.publicPort != res.Port
			c.publicAddress = res.Address
			c.publicPort = res.Port
			cb := c.onEndpointChanged
			c.mu.Unlock()

			if cb != nil {
				cb(res.Address, res.Port, changed)
			}
		}
	}
}

func (c *StunClient) Start(host string, port int, callback func(net.IP, int, bool)) error {
	addr, err := net.ResolveUDPAddr("udp", fmt.Sprintf("%s:%d", host, port))
	if err != nil {
		return err
	}

	conn, err := net.ListenUDP("udp", nil)
	if err != nil {
		return err
	}
	c.conn = conn
	c.onEndpointChanged = callback

	go c.listenLoop()

	err = c.sendBindingRequest(addr)
	if err != nil {
		return err
	}

	go func() {
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				c.sendBindingRequest(addr)
			case <-c.stopChan:
				return
			}
		}
	}()

	return nil
}

func (c *StunClient) Stop() {
	close(c.stopChan)
	if c.conn != nil {
		c.conn.Close()
	}
}

func (c *StunClient) Conn() *net.UDPConn {
	return c.conn
}
