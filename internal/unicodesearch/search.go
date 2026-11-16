// Package unicodesearch looks up Unicode characters and emoji offline.
package unicodesearch

import (
	"bufio"
	"bytes"
	"compress/gzip"
	"embed"
	"encoding/xml"
	"fmt"
	"io"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

//go:embed data/*
var data embed.FS

type Result struct {
	Text       string   `json:"text"`
	CodePoints []string `json:"codePoints"`
	Name       string   `json:"name"`
	Matched    string   `json:"matched,omitempty"`
}

type entry struct {
	name    string
	aliases []string
}

func normalize(text string) string {
	return strings.Join(strings.FieldsFunc(strings.ToLower(text), func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsDigit(r)
	}), " ")
}

func codePoint(value rune) string { return fmt.Sprintf("U+%04X", value) }

func parseHex(hex string) (rune, error) {
	value, err := strconv.ParseUint(hex, 16, 32)
	if err != nil || value > unicode.MaxRune || (value >= 0xD800 && value <= 0xDFFF) {
		return 0, fmt.Errorf("invalid code point %q", hex)
	}
	return rune(value), nil
}

func openData(name string) (*gzip.Reader, error) {
	compressed, err := data.ReadFile("data/" + name + ".gz")
	if err != nil {
		return nil, err
	}
	return gzip.NewReader(bytes.NewReader(compressed))
}

func scanData(name string, visit func(string) error) error {
	file, err := openData(name)
	if err != nil {
		return err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line, _, _ := strings.Cut(scanner.Text(), "#")
		if line = strings.TrimSpace(line); line != "" {
			if err := visit(line); err != nil {
				return fmt.Errorf("%s: %w", name, err)
			}
		}
	}
	return scanner.Err()
}

func addAliases(entries map[string]*entry, text string, aliases ...string) {
	row := entries[text]
	if row == nil {
		row = &entry{}
		entries[text] = row
	}
	row.aliases = append(row.aliases, aliases...)
}

func loadEmoji(entries map[string]*entry) error {
	qualified := make(map[string]string)
	if err := scanData("emoji-test.txt", func(line string) error {
		codes, status, _ := strings.Cut(line, ";")
		if strings.TrimSpace(status) != "fully-qualified" {
			return nil
		}
		var text strings.Builder
		for _, hex := range strings.Fields(codes) {
			r, err := parseHex(hex)
			if err != nil {
				return err
			}
			text.WriteRune(r)
		}
		emoji := text.String()
		qualified[strings.ReplaceAll(emoji, "\uFE0F", "")] = emoji
		return nil
	}); err != nil {
		return err
	}

	for _, name := range []string{"annotations-en.xml", "annotationsDerived-en.xml"} {
		if err := readAnnotations(name, entries, qualified); err != nil {
			return err
		}
	}
	return nil
}

func readAnnotations(name string, entries map[string]*entry, qualified map[string]string) error {
	file, err := openData(name)
	if err != nil {
		return err
	}
	defer file.Close()
	decoder := xml.NewDecoder(file)
	for {
		token, err := decoder.Token()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		element, ok := token.(xml.StartElement)
		if !ok || element.Name.Local != "annotation" {
			continue
		}
		var annotation struct {
			Text  string `xml:"cp,attr"`
			Type  string `xml:"type,attr"`
			Value string `xml:",chardata"`
		}
		if err := decoder.DecodeElement(&annotation, &element); err != nil {
			return err
		}
		text := qualified[annotation.Text]
		if text == "" {
			continue
		}
		if annotation.Type == "tts" {
			addAliases(entries, text, annotation.Value)
			if entries[text].name == "" {
				entries[text].name = annotation.Value
			}
		} else {
			addAliases(entries, text, strings.Split(annotation.Value, "|")...)
		}
	}
}

const noMatch = 100

func match(query, label string) int {
	normalized := normalize(label)
	if normalized == "" {
		return noMatch
	}
	if normalized == query {
		return 0
	}
	if strings.HasPrefix(normalized, query) {
		return 2
	}
	words := strings.Fields(normalized)
	for _, term := range strings.Fields(query) {
		found := false
		for _, word := range words {
			if strings.HasPrefix(word, term) {
				found = true
				break
			}
		}
		if !found {
			return noMatch
		}
	}
	return 4
}

type ranked struct {
	Result
	score int
}

// Search returns up to limit results in relevance order.
func Search(query string, limit int) ([]Result, error) {
	raw := strings.TrimSpace(query)
	key := normalize(raw)
	if raw == "" || limit <= 0 {
		return []Result{}, nil
	}
	exact := raw
	if strings.HasPrefix(strings.ToUpper(raw), "U+") {
		var decoded strings.Builder
		for _, field := range strings.Fields(raw) {
			if !strings.HasPrefix(strings.ToUpper(field), "U+") {
				decoded.Reset()
				break
			}
			r, err := parseHex(field[2:])
			if err != nil {
				decoded.Reset()
				break
			}
			decoded.WriteRune(r)
		}
		if decoded.Len() != 0 {
			exact = decoded.String()
			key = ""
		}
	}
	entries := make(map[string]*entry)
	if err := loadEmoji(entries); err != nil {
		return nil, err
	}
	if err := scanData("NameAliases.txt", func(line string) error {
		fields := strings.Split(line, ";")
		r, err := parseHex(fields[0])
		if err != nil {
			return err
		}
		if !unicode.IsControl(r) {
			addAliases(entries, string(r), fields[1])
		}
		return nil
	}); err != nil {
		return nil, err
	}
	aliases, err := data.ReadFile("data/aliases.tsv")
	if err != nil {
		return nil, err
	}
	for _, line := range strings.Split(string(aliases), "\n") {
		if hex, keywords, ok := strings.Cut(line, "\t"); ok && !strings.HasPrefix(line, "#") {
			r, err := parseHex(hex)
			if err != nil {
				return nil, err
			}
			addAliases(entries, string(r), strings.Split(keywords, "|")...)
		}
	}

	var matches []ranked
	add := func(text, name string, row *entry) {
		score, matched := noMatch, ""
		switch {
		case exact == text:
			score = -1
		case key != "":
			score = match(key, name) + 1
			if row != nil {
				for _, alias := range row.aliases {
					if rank := match(key, alias); rank < score && rank < noMatch {
						score, matched = rank, strings.TrimSpace(alias)
					}
				}
			}
		}
		if score < noMatch {
			var codes []string
			for _, r := range text {
				codes = append(codes, codePoint(r))
			}
			matches = append(matches, ranked{Result{text, codes, name, matched}, score})
		}
	}
	if err := scanData("DerivedName.txt", func(line string) error {
		codes, name, _ := strings.Cut(line, ";")
		name = strings.TrimSpace(name)
		first, last, isRange := strings.Cut(strings.TrimSpace(codes), "..")
		start, err := parseHex(first)
		if err != nil {
			return err
		}
		end := start
		if isRange {
			end, err = parseHex(last)
			if err != nil {
				return err
			}
		}
		for r := start; r <= end; r++ {
			text := string(r)
			row := entries[text]
			label := name
			if isRange {
				label = strings.ReplaceAll(name, "*", fmt.Sprintf("%04X", r))
			}
			add(text, label, row)
			delete(entries, text)
		}
		return nil
	}); err != nil {
		return nil, err
	}
	for text, row := range entries {
		if row.name == "" && len(row.aliases) > 0 {
			row.name = strings.TrimSpace(row.aliases[0])
		}
		add(text, row.name, row)
	}

	sort.Slice(matches, func(i, j int) bool {
		a, b := matches[i], matches[j]
		if a.score != b.score {
			return a.score < b.score
		}
		if len(a.CodePoints) != len(b.CodePoints) {
			return len(a.CodePoints) < len(b.CodePoints)
		}
		return a.Text < b.Text
	})
	results := make([]Result, 0, min(limit, len(matches)))
	for _, row := range matches[:cap(results)] {
		results = append(results, row.Result)
	}
	return results, nil
}
