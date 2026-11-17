// WubiExternalQuery is a short-lived, platform-independent dictionary query helper.
// Usage: WubiExternalQuery RESOURCE_DIRECTORY USER_DIRECTORY CODE
// stdout: JSON object with words and character readings; stderr: diagnostic; nonzero exit: failed query.
package main

import (
	"bufio"
	"embed"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"math"
	"os"
	"path"
	"path/filepath"
	"slices"
	"sort"
	"strconv"
	"strings"

	"wubi/internal/unicodesearch"
)

//go:embed dictionaries
var bundledDictionaries embed.FS

type dictionaryPath struct {
	files fs.FS
	name  string
}

func (source dictionaryPath) scan(consume func(string)) error {
	f, err := source.files.Open(source.name)
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

// Match a prefix against single-character readings without enumerating complete
// pronunciation combinations. Positions track only the unconsumed query.
func matchReadings(word, code, separator string, readings map[string][]string) (match, exact bool) {
	positions := []int{0}
	var next []int
	first := true
	for _, char := range word {
		options := readings[string(char)]
		if len(options) == 0 {
			return false, false
		}
		next = next[:0]
		for _, pos := range positions {
			for _, option := range options {
				if !first {
					option = separator + option
				}
				if pos >= len(code) {
					end := len(code) + 1
					if !slices.Contains(next, end) {
						next = append(next, end)
					}
					break
				}
				remaining := code[pos:]
				end := pos + len(option)
				if strings.HasPrefix(option, remaining) && end > len(code) {
					end = len(code) + 1 // Prefix consumed, but the full spelling is longer.
				} else if !strings.HasPrefix(remaining, option) {
					continue
				}
				if !slices.Contains(next, end) {
					next = append(next, end)
				}
			}
		}
		if len(next) == 0 {
			return false, false
		}
		positions, next = next, positions
		first = false
	}
	return slices.Contains(positions, len(code)) || slices.Contains(positions, len(code)+1), slices.Contains(positions, len(code))
}

func query(resources, data, code string) ([]string, error) {
	result, err := queryDetailed(resources, data, code)
	return result.Words, err
}

func queryDetailed(resources, data, code string) (queryResponse, error) {
	return queryByMode(resources, data, code, false)
}

func queryByMode(resources, data, code string, pinyin bool) (queryResponse, error) {
	if pinyin {
		if strings.Trim(code, "'") == "" || strings.ContainsFunc(code, func(c rune) bool {
			return c != '\'' && (c < 'a' || c > 'z')
		}) {
			return queryResponse{}, fmt.Errorf("拼音编码只能包含小写字母和音节分隔符")
		}
	} else if !validCode(code) {
		return queryResponse{}, fmt.Errorf("编码必须为一至四个小写字母")
	}
	excluded := map[string]bool{}
	userFiles := os.DirFS(data)
	resourceFiles := os.DirFS(resources)
	err := (dictionaryPath{userFiles, "excluded.txt"}).scan(func(line string) {
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

	var wubiDirectories []dictionaryPath
	if !pinyin {
		wubiDirectories = []dictionaryPath{
			{resourceFiles, "."},
			{bundledDictionaries, "dictionaries/external"},
			{resourceFiles, "external"},
			{userFiles, "external"},
		}
	}
	for i, directory := range wubiDirectories {
		files, err := fs.ReadDir(directory.files, directory.name)
		if os.IsNotExist(err) && i > 0 {
			continue
		}
		if err != nil {
			return queryResponse{}, err
		}
		// fs.ReadDir returns entries sorted by name, preserving a stable source order.
		for _, file := range files {
			name := file.Name()
			if file.IsDir() || !strings.HasSuffix(name, ".txt") || (i == 0 && !strings.HasPrefix(name, "wubi")) {
				continue
			}
			source := dictionaryPath{directory.files, path.Join(directory.name, name)}
			err := source.scan(func(line string) {
				if strings.HasPrefix(line, "#") || strings.HasPrefix(line, " ") {
					return
				}
				fields := strings.Split(line, "\t")
				if len(fields) < 2 || fields[0] == "" || excluded[fields[0]] {
					return
				}
				spelling := strings.ToLower(fields[1])
				if excluded[fields[0]+"\t"+spelling] {
					return
				}
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
	separator := ""
	if pinyin && strings.Contains(code, "'") {
		separator = "'"
	}
	allReadings := map[string][]string{}
	var weightedDictionaries []dictionaryPath
	pinyinDirectories := []dictionaryPath{
		{bundledDictionaries, "dictionaries/cn_dicts"},
		{resourceFiles, "cn_dicts"},
		{userFiles, "cn_dicts"},
	}
	for _, directory := range pinyinDirectories {
		files, err := fs.ReadDir(directory.files, directory.name)
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
			source := dictionaryPath{directory.files, path.Join(directory.name, file.Name())}
			hasUnannotated := false
			err := source.scan(func(line string) {
				if strings.HasPrefix(line, "#") {
					return
				}
				fields := strings.Split(line, "\t")
				if len(fields) < 2 || fields[0] == "" || excluded[fields[0]] {
					return
				}
				if len(fields) == 2 {
					if _, err := strconv.ParseFloat(fields[1], 64); err == nil {
						hasUnannotated = true
						return
					}
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
				var spelling string
				if pinyin {
					spelling = strings.Join(syllables, separator)
				} else {
					spelling = phraseCode(fields[0], roots)
				}
				if strings.HasPrefix(spelling, code) && (pinyin || !excluded[fields[0]+"\t"+spelling]) {
					matches = append(matches, match{fields[0], spelling == code})
				}
			})
			if err != nil {
				return queryResponse{}, err
			}
			if hasUnannotated {
				weightedDictionaries = append(weightedDictionaries, source)
			}
		}
	}

	// Weight-only rows need the readings gathered from all dictionary files above.
	for _, source := range weightedDictionaries {
		err := source.scan(func(line string) {
			if strings.HasPrefix(line, "#") {
				return
			}
			word, weight, ok := strings.Cut(line, "\t")
			if !ok || word == "" || excluded[word] {
				return
			}
			if _, err := strconv.ParseFloat(weight, 64); err != nil {
				return
			}
			if pinyin {
				if matched, exact := matchReadings(word, code, separator, allReadings); matched {
					matches = append(matches, match{word, exact})
				}
			} else if spelling := phraseCode(word, roots); strings.HasPrefix(spelling, code) && !excluded[word+"\t"+spelling] {
				matches = append(matches, match{word, spelling == code})
			}
		})
		if err != nil {
			return queryResponse{}, err
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
	if len(os.Args) == 3 && os.Args[1] == "unicode" {
		results, err := unicodesearch.Search(os.Args[2], 50)
		if err == nil {
			err = json.NewEncoder(os.Stdout).Encode(results)
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
	args := os.Args[1:]
	pinyin := len(args) > 0 && args[0] == "pinyin"
	if pinyin {
		args = args[1:]
	}
	if len(args) != 3 && !(len(args) == 5 && args[3] == "--index-dir") {
		fmt.Fprintln(os.Stderr, "usage: WubiExternalQuery [pinyin] RESOURCE_DIRECTORY USER_DIRECTORY CODE [--index-dir DIRECTORY]")
		fmt.Fprintln(os.Stderr, "       WubiExternalQuery unicode QUERY")
		os.Exit(2)
	}
	words, err := queryByMode(args[0], args[1], args[2], pinyin)
	if err == nil {
		if len(args) == 5 {
			err = writeQueryIndices(args[4], words)
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
