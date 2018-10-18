package main

import (
	"fmt"
)

// Trie is a trie retrieval tree.
type Trie struct {
	chars map[rune]uint
	nodes [26]*Trie
}

func (t *Trie) Insert(char rune, code string) {
	tt := t
	for _, c := range code {
		if 'A' <= c && c <= 'Z' {
			c += 32
		}
		if !('a' <= c && c <= 'z') {
			panic("invalid code")
		}
		index := c - 'a'
		if tt.nodes[index] == nil {
			tt.nodes[index] = &Trie{}
		}
		tt = tt.nodes[index]
	}
	if tt.chars == nil {
		tt.chars = make(map[rune]uint)
	}
	tt.chars[char] = 1
}

func (t *Trie) Search(code string) map[rune]uint {
	tt := t
	for _, c := range code {
		if !('a' <= c && c <= 'z') {
			panic("invalid code")
		}
		tt = tt.nodes[c-'a']
		if tt == nil {
			panic("no such code")
		}
	}
	return tt.chars
}

func main() {
	t := &Trie{}
	t.Insert('我', "q")
	t.Insert('人', "w")
	t.Insert('多', "qq")
	fmt.Println(t.Search("w"))
}
