package main

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"strings"
)

// Trie is a trie retrieval tree.
type Trie struct {
	words map[string]uint
	nodes [26]*Trie
}

func (t *Trie) Insert(word string, codes ...string) {
	for _, code := range codes {
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
		if tt.words == nil {
			tt.words = make(map[string]uint)
		}
		tt.words[word] = 1
	}
}

func (t *Trie) Search(code string) map[string]uint {
	tt := t
	for _, c := range code {
		if !('a' <= c && c <= 'z') {
			panic("invalid code")
		}
		tt = tt.nodes[c-'a']
		if tt == nil {
			return nil
		}
	}
	return tt.words
}

var reWord = regexp.MustCompile(`^([^a-z]+)(.+)$`)

func readCodes(file string, callback func(word string, codes ...string)) {
	fp, err := os.Open(file)
	if err != nil {
		panic("error open")
	}
	defer fp.Close()
	scanner := bufio.NewScanner(fp)
	for scanner.Scan() {
		line := scanner.Text()
		tokens := reWord.FindStringSubmatch(line)
		if len(tokens) < 3 {
			panic("bad code")
		}
		word := tokens[1]
		codes := strings.Split(tokens[2], " ")
		callback(word, codes...)
	}
}

func main() {
	t := &Trie{}
	readCodes("../86", func(word string, codes ...string) {
		t.Insert(word, codes...)
	})

	q := bufio.NewScanner(os.Stdin)
	for q.Scan() {
		words := t.Search(q.Text())
		fmt.Println(words)
	}
}
