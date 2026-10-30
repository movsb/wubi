package main

import (
	"encoding/binary"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func writeFixture(t *testing.T, dir, name, contents string) {
	t.Helper()
	if err := os.MkdirAll(dir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, name), []byte(contents), 0644); err != nil {
		t.Fatal(err)
	}
}

func TestQuery(t *testing.T) {
	root := t.TempDir()
	resources, data := filepath.Join(root, "resources"), filepath.Join(root, "user")
	writeFixture(t, resources, "wubi86_jidian.txt", "补全\tabcd\n重复\tabcd\n")
	writeFixture(t, resources, "pinyin_simp.txt", "忽略\tab\n")
	writeFixture(t, filepath.Join(resources, "external"), "extra.txt", "精确\tab\r\n重复\tab\r\n排除\tab\n非法\tabcde\n")
	writeFixture(t, filepath.Join(data, "external"), "custom.txt", "自选\tAB\n精确\tab\n")
	writeFixture(t, data, "excluded.txt", "# comment\n排除 # comment\n")
	got, err := query(resources, data, "ab")
	want := []string{"精确", "重复", "自选", "补全"}
	if err != nil || !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, %v; want %v", got, err, want)
	}
	got, err = query(resources, data, "zz")
	if err != nil || got == nil || len(got) != 0 {
		t.Fatalf("empty results should encode as []: %v, %v", got, err)
	}
	for _, code := range []string{"", "abcde", "a?", "AB", "../"} {
		if _, err := query(resources, data, code); err == nil {
			t.Fatalf("accepted invalid code %q", code)
		}
	}
}

func TestMissingOptionalDirectories(t *testing.T) {
	resources := t.TempDir()
	got, err := query(resources, filepath.Join(t.TempDir(), "absent"), "a")
	if err != nil || len(got) != 0 {
		t.Fatalf("%v, %v", got, err)
	}
	if _, err := query(filepath.Join(resources, "absent"), t.TempDir(), "a"); err == nil {
		t.Fatal("missing resources should fail")
	}
}

func TestIceDictionaries(t *testing.T) {
	root := t.TempDir()
	resources, data := filepath.Join(root, "resources"), filepath.Join(root, "user")
	// Longest normal code, weight as tie-breaker, and the first equal-weight row win.
	writeFixture(t, resources, "wubi86_jidian.txt", "重\ttg\n重\ttgjf\t10\n重\tzzzz\t999\n重\tagjf\t1\n中\tkhk\t1\n中\tkhkk\t2\n国\tlgyi\n人\twwww\n")
	writeFixture(t, filepath.Join(resources, "cn_dicts"), "8105.txt", "重\tzhong\n重\tchong\n中\tzhong\n国\tguo\n人\tren\n")
	writeFixture(t, filepath.Join(resources, "cn_dicts"), "base.txt", "重中\tchong zhong\n重中国\tzhong zhong guo\n重中国人\tzhong zhong guo ren\n重中国中人\tzhong zhong guo zhong ren\n未知\twei zhi\n重A\tzhong a\n错误格式\tcuo\n")
	writeFixture(t, filepath.Join(data, "cn_dicts"), "custom.txt", "重中\tzhong zhong\n中重\tzhong chong\n")
	result, err := queryDetailed(resources, data, "tgkh")
	if err != nil || !reflect.DeepEqual(result.Words, []string{"重中"}) {
		t.Fatalf("%+v, %v", result, err)
	}
	if !reflect.DeepEqual(result.Readings["重"], []string{"zhong", "chong"}) {
		t.Fatalf("missing polyphonic readings: %+v", result.Readings)
	}
	if _, ok := result.Readings["人"]; ok {
		t.Fatal("unrelated readings leaked into response")
	}
	for code, want := range map[string][]string{
		"tklg": {"重中国"}, "tklw": {"重中国人", "重中国中人"}, "khtg": {"中重"},
	} {
		got, err := query(resources, data, code)
		if err != nil || !reflect.DeepEqual(got, want) {
			t.Fatalf("%s: %v, %v; want %v", code, got, err, want)
		}
	}
	writeFixture(t, data, "excluded.txt", "重中\n")
	result, err = queryDetailed(resources, data, "tgkh")
	if err != nil || len(result.Words) != 0 {
		t.Fatalf("excluded ICE word returned: %+v, %v", result, err)
	}
}

func TestQueryIndices(t *testing.T) {
	directory := t.TempDir()
	response := queryResponse{Words: []string{"甲乙", "新词"}, Readings: map[string][]string{"乙": {"yi"}, "甲": {"jia", "ga"}}}
	if err := writeQueryIndices(directory, response); err != nil {
		t.Fatal(err)
	}
	for name, want := range map[string][]indexItem{
		"words.index":    {{text: "甲乙"}, {text: "新词"}},
		"readings.index": {{text: "yi", code: "乙"}, {text: "jia", code: "甲"}, {text: "ga", code: "甲"}},
	} {
		data, err := os.ReadFile(filepath.Join(directory, name))
		if err != nil {
			t.Fatal(err)
		}
		count := binary.LittleEndian.Uint64(data[8:16])
		size := binary.LittleEndian.Uint64(data[16:24])
		if string(data[:8]) != "WUBIIDX1" || count != uint64(len(want)) || uint64(len(data)) != 24+count*24+size {
			t.Fatalf("invalid index header for %s", name)
		}
		blob := data[24+count*24:]
		for i, expected := range want {
			row := data[24+i*24:]
			textStart, textLength := binary.LittleEndian.Uint32(row), binary.LittleEndian.Uint32(row[4:])
			codeStart, codeLength := binary.LittleEndian.Uint32(row[8:]), binary.LittleEndian.Uint32(row[12:])
			got := indexItem{string(blob[textStart : textStart+textLength]), string(blob[codeStart : codeStart+codeLength])}
			if got != expected {
				t.Fatalf("%s row %d: %+v; want %+v", name, i, got, expected)
			}
		}
	}
	if err := writeQueryIndices(directory, queryResponse{}); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(filepath.Join(directory, "words.index"))
	if len(data) != 24 {
		t.Fatal("empty query must produce a valid empty index")
	}
}
