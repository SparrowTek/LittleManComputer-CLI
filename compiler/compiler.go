// Package compiler CLI
package compiler

import (
	"bufio"
	"fmt"
	"os"

	"github.com/sparrowTek/LittleManComputer-CLI/models"
)

// CompileFromFile compiles the assembly code for the given file
func CompileFromFile(filePath string) models.RAM {
	// file, err := os.Open(filePath)
	// defer file.Close()

	// if err != nil {
	// 	// Handle open file error
	// 	fmt.Fprintf(os.Stderr, "compile error: %v\n", err)
	// }

	// parse the assembly code in the file
	// b, err := ioutil.ReadAll(file)
	// fmt.Print(b)

	printRegisters()

	return make(map[int]models.Register)
}

// CompileTerminalInput compiles the assembly code entered by the user in their terminal emulator
func CompileTerminalInput() {
	buf := bufio.NewReader(os.Stdin)
	fmt.Print("> ")
	sentence, err := buf.ReadBytes('\n')
	if err != nil {
		fmt.Println(err)
	} else {
		fmt.Println(string(sentence))
	}

	printRegisters()
}

func printRegisters() {
	fmt.Println("Memory Registers")
	fmt.Println("")
	fmt.Println("   0       1       2       3       4       5       6       7       8       9")
	fmt.Println("-------------------------------------------------------------------------------")
	fmt.Println("  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  ")
	fmt.Println("-------------------------------------------------------------------------------")
	fmt.Println("  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  ")
	fmt.Println("-------------------------------------------------------------------------------")
	fmt.Println("  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  ")
	fmt.Println("-------------------------------------------------------------------------------")
	fmt.Println("  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  ")
	fmt.Println("-------------------------------------------------------------------------------")
	fmt.Println("  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  ")
	fmt.Println("-------------------------------------------------------------------------------")
	fmt.Println("  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  ")
	fmt.Println("-------------------------------------------------------------------------------")
	fmt.Println("  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  ")
	fmt.Println("-------------------------------------------------------------------------------")
	fmt.Println("  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  ")
	fmt.Println("-------------------------------------------------------------------------------")
	fmt.Println("  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  ")
	fmt.Println("-------------------------------------------------------------------------------")
	fmt.Println("  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  ")
}
