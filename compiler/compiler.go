// Package compiler CLI
package compiler

import (
	"fmt"

	"github.com/sparrowTek/LittleManComputer-CLI/models"
)

// Compile the assembly code for the given file
func Compile(filePath string) models.RAM {
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
