// Package models has all the models
package models

// Register ...
type Register int

// RAM ...
type RAM map[int]Register

// Opcode is a string but calling it opcode will make code easier to understand
type Opcode string
