// Package main starts the Little Man Computer CLI
package main

import (
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/sparrowTek/LittleManComputer-CLI/compiler"
)

var (
	// Flags for the CLI
	file = flag.String("file", "", "Include the name of a file with the assembly code")
	// state models.RAM
)

func main() {
	flag.Parse()

	if len(os.Args) <= 1 {
		// User needs to enter an argument
		fmt.Println("User needs to enter an argument")
		os.Exit(1)
	}

	arg := os.Args[1]
	parseArgs(arg)
}

func parseArgs(arg string) {
	switch strings.ToLower(arg) {
	case "compile":
		// state = compiler.Compile("test")
		// fmt.Println("RAM: %v", state)

		if *file == "" {
			fmt.Println("COMPILE from args")
		} else {
			fmt.Println("COMPILE from file")
			// compiler.CompileTerminalInput()
		}

		compiler.CompileTerminalInput()
	case "run":
		fmt.Println("RUN")
	case "step":
		fmt.Println("STEP")
	default:
		fmt.Println("ERROR: bad command \nShow HELP")
	}
}
