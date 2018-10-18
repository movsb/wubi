package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Trie is a trie retrieval tree.
type Trie struct {
	words map[string]struct{}
	nodes [26]*Trie
}

func (t *Trie) Insert(word string, codes string) {
	tt := t
	for _, c := range codes {
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
	if tt.words == nil {
		tt.words = make(map[string]struct{})
	}
	tt.words[word] = struct{}{}
}

func (t *Trie) Search(code string) []string {
	tt := t
	for _, c := range code {
		if !('a' <= c && c <= 'z') {
			fmt.Println("invalid code")
			return nil
		}
		tt = tt.nodes[c-'a']
		if tt == nil {
			return nil
		}
	}
	words := make([]string, 0, len(tt.words))
	for k := range tt.words {
		words = append(words, k)
	}
	return words
}

func readCodes(file string, callback func(word string, codes string)) {
	fp, err := os.Open(file)
	if err != nil {
		panic("error open")
	}
	defer fp.Close()
	scanner := bufio.NewScanner(fp)
	ellipsisFound := false
	for scanner.Scan() {
		line := scanner.Text()
		if !ellipsisFound {
			if line == `...` {
				ellipsisFound = true
			}
			continue
		}
		if len(line) <= 0 || line[0] == ' ' || line[0] == '#' {
			continue
		}
		tokens := strings.Split(line, "\t")
		if len(tokens) != 2 {
			panic("bad code")
		}
		callback(tokens[0], tokens[1])
	}
}

func main() {
	t := &Trie{}
	i := 0

	paths, _ := filepath.Glob(`*.dict.yaml`)
	for _, path := range paths {
		readCodes(path, func(word string, codes string) {
			t.Insert(word, codes)
			i++
		})
	}

	fmt.Println("Imported", i, "words")

	q := bufio.NewScanner(os.Stdin)
	prompt := func() {
		fmt.Print(`Input: `)
		os.Stdout.Sync()
	}
	prompt()
	for q.Scan() {
		words := t.Search(q.Text())
		fmt.Println(words)
		prompt()
	}
}
