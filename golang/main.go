package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"os/exec"
)

type Packet struct {
	Command  string `json:"command"`
	Output   string `json:"output"`
	Success  string `json:"success"`
	Callback string `json:"callback"`
	Error    string `json:"error"`
	Failure  string `json:"failure"`
}

func runBash(cmdStr string) (string, error) {
	cmd := exec.Command("bash", "-c", cmdStr)
	output, err := cmd.CombinedOutput()

	fmt.Println("---- OUTPUT ----")
	fmt.Println(string(output))

	return string(output), err
}

func handleConnection(conn net.Conn) {
	defer conn.Close()

	reader := bufio.NewReader(conn)

	for {
		out := ""
		line, err := reader.ReadString('\n')
		if err != nil {
			return
		}

		var packet Packet
		err = json.Unmarshal([]byte(line), &packet)
		if err != nil {
			fmt.Println("Invalid packet:", err)
			continue
		}

		fmt.Println("Received command:", packet.Command)

		// ✅ Run main command
		out, err = runBash(packet.Command)
		var opacket Packet
		opacket.Output = out

		// 🔥 Decide next step
		if err == nil {
			fmt.Println("Command SUCCESS → running success script")
			if packet.Success != "" {
				runBash(packet.Success)
			}
			if packet.Callback != "" {
				opacket.Success = packet.Callback
			}
		} else {
			fmt.Println("Command FAILED → running failure script")
			if packet.Failure != "" {
				runBash(packet.Failure)
			}
			if packet.Error != "" {
				opacket.Failure = packet.Error
			}
		}
		response, _ := json.Marshal(opacket)
		_, _ = conn.Write(append(response, '\n'))
	}
}

func main() {
	listener, err := net.Listen("tcp", "127.0.0.1:54321")
	if err != nil {
		panic(err)
	}

	fmt.Println("TCP workflow server running on 127.0.0.1:54321")

	for {
		conn, err := listener.Accept()
		if err != nil {
			continue
		}

		go handleConnection(conn)
	}
}
