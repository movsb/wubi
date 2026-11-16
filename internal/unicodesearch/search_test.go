package unicodesearch

import "testing"

func TestSearch(t *testing.T) {
	for _, tc := range []struct {
		query, text, name string
	}{
		{"command", "⌘", "PLACE OF INTEREST SIGN"},
		{"CMD", "⌘", "PLACE OF INTEREST SIGN"},
		{"alt", "⌥", "OPTION KEY"},
		{"right arrow", "→", "RIGHTWARDS ARROW"},
		{"right arrow dashed", "⇢", "RIGHTWARDS DASHED ARROW"},
		{"U+4e00", "一", "CJK UNIFIED IDEOGRAPH-4E00"},
		{"⌘", "⌘", "PLACE OF INTEREST SIGN"},
		{"woman technologist", "👩‍💻", "woman technologist"},
		{"U+1F469 U+200D U+1F4BB", "👩‍💻", "woman technologist"},
	} {
		t.Run(tc.query, func(t *testing.T) {
			results, err := Search(tc.query, 1)
			if err != nil || len(results) != 1 || results[0].Text != tc.text || results[0].Name != tc.name {
				t.Fatalf("Search(%q) = %+v, %v", tc.query, results, err)
			}
		})
	}
	results, err := Search("no such unicode query xqzz", 50)
	if err != nil || len(results) != 0 {
		t.Fatalf("unexpected results %+v, %v", results, err)
	}
	results, err = Search("U+2318", 50)
	if err != nil || len(results) != 1 || results[0].Text != "⌘" {
		t.Fatalf("code point lookup = %+v, %v", results, err)
	}
}
