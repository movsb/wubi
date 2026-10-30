// WubiExternalQuery is a short-lived, platform-independent dictionary query helper.
// Usage: WubiExternalQuery RESOURCE_DIRECTORY USER_DIRECTORY CODE
// stdout: JSON object with words and character readings; stderr: diagnostic; nonzero exit: failed query.
package main

import (
	"bufio"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

func scan(path string, consume func(string)) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	// ReadString has no fixed line-size limit, including for user-supplied dictionaries.
	reader := bufio.NewReader(f)
	for {
		line, err := reader.ReadString('\n')
		if len(line) > 0 {
			consume(strings.TrimRight(line, "\r\n"))
		}
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
	}
}

func validCode(code string) bool {
	if len(code) < 1 || len(code) > 4 {
		return false
	}
	for _, c := range code {
		if c < 'a' || c > 'z' {
			return false
		}
	}
	return true
}

type queryResponse struct {
	Words    []string            `json:"words"`
	Readings map[string][]string `json:"readings"`
}

func isHanzi(c rune) bool {
	return c >= 0x3400 && c <= 0x4dbf || c >= 0x4e00 && c <= 0x9fff ||
		c >= 0xf900 && c <= 0xfaff || c >= 0x20000 && c <= 0x2fa1f || c >= 0x30000 && c <= 0x323af
}

// Match DictionaryMerger.phraseCode so collected words retain their generated code.
func phraseCode(word string, roots map[rune]string) string {
	chars := []rune(word)
	if len(chars) == 0 {
		return ""
	}
	for _, c := range chars {
		if !isHanzi(c) || len(roots[c]) < 2 {
			return ""
		}
	}
	if len(chars) == 1 {
		return roots[chars[0]]
	}
	if len(chars) == 2 {
		return roots[chars[0]][:2] + roots[chars[1]][:2]
	}
	if len(chars) == 3 {
		return roots[chars[0]][:1] + roots[chars[1]][:1] + roots[chars[2]][:2]
	}
	return roots[chars[0]][:1] + roots[chars[1]][:1] + roots[chars[2]][:1] + roots[chars[len(chars)-1]][:1]
}

func query(resources, data, code string) ([]string, error) {
	result, err := queryDetailed(resources, data, code)
	return result.Words, err
}

func queryDetailed(resources, data, code string) (queryResponse, error) {
	if !validCode(code) {
		return queryResponse{}, fmt.Errorf("编码必须为一至四个小写字母")
	}
	excluded := map[string]bool{}
	err := scan(filepath.Join(data, "excluded.txt"), func(line string) {
		word := strings.Trim(strings.TrimSpace(strings.SplitN(line, "#", 2)[0]), "\ufeff")
		if word != "" {
			excluded[word] = true
		}
	})
	if err != nil && !os.IsNotExist(err) {
		return queryResponse{}, err
	}
	type match struct {
		word  string
		exact bool
	}
	matches := []match{}
	roots := map[rune]string{}
	weights := map[rune]float64{}
	rootSeen := map[string]bool{}
	// Only resident Wubi roots determine generated codes, as in the Swift merger.

	for i, directory := range []string{resources, filepath.Join(resources, "external"), filepath.Join(data, "external")} {
		files, err := os.ReadDir(directory)
		if os.IsNotExist(err) && i > 0 {
			continue
		}
		if err != nil {
			return queryResponse{}, err
		}
		// os.ReadDir returns entries sorted by name, preserving a stable source order.
		for _, file := range files {
			name := file.Name()
			if file.IsDir() || !strings.HasSuffix(name, ".txt") || (i == 0 && !strings.HasPrefix(name, "wubi")) {
				continue
			}
			err := scan(filepath.Join(directory, name), func(line string) {
				if strings.HasPrefix(line, "#") || strings.HasPrefix(line, " ") {
					return
				}
				fields := strings.Split(line, "\t")
				if len(fields) < 2 || fields[0] == "" || excluded[fields[0]] {
					return
				}
				spelling := strings.ToLower(fields[1])
				chars := []rune(fields[0])
				if i == 0 && len(chars) == 1 && validCode(spelling) && len(spelling) >= 2 && !strings.HasPrefix(spelling, "z") {
					key := fields[0] + "\t" + spelling
					if !rootSeen[key] {
						rootSeen[key] = true
						weight := 0.0
						if len(fields) > 2 {
							weight, _ = strconv.ParseFloat(strings.ReplaceAll(fields[2], "%", ""), 64)
						}
						if math.IsNaN(weight) || math.IsInf(weight, 0) {
							weight = 0
						}
						c := chars[0]
						if len(spelling) > len(roots[c]) || len(spelling) == len(roots[c]) && weight > weights[c] {
							roots[c] = spelling
							weights[c] = weight
						}
					}
				}
				if validCode(spelling) && strings.HasPrefix(spelling, code) {
					matches = append(matches, match{fields[0], spelling == code})
				}
			})
			if err != nil {
				return queryResponse{}, err
			}
		}
	}
	// Stream the large pinyin dictionaries; retain only matching words and single-character readings.
	allReadings := map[string][]string{}
	for _, directory := range []string{filepath.Join(resources, "cn_dicts"), filepath.Join(data, "cn_dicts")} {
		files, err := os.ReadDir(directory)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return queryResponse{}, err
		}
		for _, file := range files {
			if file.IsDir() || !strings.HasSuffix(file.Name(), ".txt") {
				continue
			}
			err := scan(filepath.Join(directory, file.Name()), func(line string) {
				if strings.HasPrefix(line, "#") {
					return
				}
				fields := strings.Split(line, "\t")
				if len(fields) < 2 || fields[0] == "" || excluded[fields[0]] {
					return
				}
				syllables := strings.Fields(strings.ReplaceAll(fields[1], "'", " "))
				if len(syllables) != len([]rune(fields[0])) {
					return
				}
				for _, syllable := range syllables {
					for _, c := range syllable {
						if c < 'a' || c > 'z' {
							return
						}
					}
				}
				if len(syllables) == 1 {
					values := allReadings[fields[0]]
					found := false
					for _, value := range values {
						if value == syllables[0] {
							found = true
							break
						}
					}
					if !found {
						allReadings[fields[0]] = append(values, syllables[0])
					}
				}
				spelling := phraseCode(fields[0], roots)
				if spelling != "" && strings.HasPrefix(spelling, code) {
					matches = append(matches, match{fields[0], spelling == code})
				}
			})
			if err != nil {
				return queryResponse{}, err
			}
		}
	}

	sort.SliceStable(matches, func(i, j int) bool { return matches[i].exact && !matches[j].exact })
	words := []string{}
	seen := map[string]bool{}
	for _, m := range matches {
		if !seen[m.word] {
			seen[m.word] = true
			words = append(words, m.word)
		}
	}
	readings := map[string][]string{}
	for _, word := range words {
		for _, c := range word {
			key := string(c)
			if values := allReadings[key]; len(values) > 0 {
				readings[key] = values
			}
		}
	}
	return queryResponse{words, readings}, nil
}

func main() {
	if len(os.Args) != 4 && !(len(os.Args) == 6 && os.Args[4] == "--index-dir") {
		fmt.Fprintln(os.Stderr, "usage: WubiExternalQuery RESOURCE_DIRECTORY USER_DIRECTORY CODE [--index-dir DIRECTORY]")
		os.Exit(2)
	}
	words, err := queryDetailed(os.Args[1], os.Args[2], os.Args[3])
	if err == nil {
		if len(os.Args) == 6 {
			err = writeQueryIndices(os.Args[5], words)
		} else {
			err = json.NewEncoder(os.Stdout).Encode(words)
		}
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

// WUBIIDX1 is shared with CandidateIndex.swift: a 24-byte header, 24-byte
// little-endian records, then UTF-8 text/code bytes. Consumers map it read-only.
type indexItem struct{ text, code string }

func writeIndex(path string, items []indexItem) (err error) {
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer func() {
		if closeErr := file.Close(); err == nil {
			err = closeErr
		}
	}()
	writer := bufio.NewWriter(file)
	var size uint64
	for _, item := range items {
		size += uint64(len(item.text) + len(item.code))
	}
	if size > math.MaxUint32 {
		return fmt.Errorf("查询结果超过索引大小限制")
	}
	if _, err = writer.WriteString("WUBIIDX1"); err != nil {
		return err
	}
	if err = binary.Write(writer, binary.LittleEndian, uint64(len(items))); err != nil {
		return err
	}
	if err = binary.Write(writer, binary.LittleEndian, size); err != nil {
		return err
	}
	var offset uint32
	for _, item := range items {
		record := [6]uint32{offset, uint32(len(item.text)), offset + uint32(len(item.text)), uint32(len(item.code)), 0, 0}
		if err = binary.Write(writer, binary.LittleEndian, record); err != nil {
			return err
		}
		offset += uint32(len(item.text) + len(item.code))
	}
	for _, item := range items {
		if _, err = writer.WriteString(item.text); err != nil {
			return err
		}
		if _, err = writer.WriteString(item.code); err != nil {
			return err
		}
	}
	return writer.Flush()
}

func writeQueryIndices(directory string, response queryResponse) error {
	if err := os.MkdirAll(directory, 0700); err != nil {
		return err
	}
	words := make([]indexItem, 0, len(response.Words))
	for _, word := range response.Words {
		words = append(words, indexItem{text: word})
	}
	if err := writeIndex(filepath.Join(directory, "words.index"), words); err != nil {
		return err
	}
	keys := make([]string, 0, len(response.Readings))
	for key := range response.Readings {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	readings := []indexItem{}
	for _, key := range keys {
		for _, value := range response.Readings[key] {
			readings = append(readings, indexItem{text: value, code: key})
		}
	}
	return writeIndex(filepath.Join(directory, "readings.index"), readings)
}
