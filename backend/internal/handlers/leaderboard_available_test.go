package handlers

import (
	"testing"
)

func TestFilterAvailableLeaderboards_EmptyInput(t *testing.T) {
	got := filterAvailableLeaderboards("__nope__", nil)
	if len(got) != 0 {
		t.Fatalf("empty input should stay empty, got %d", len(got))
	}
}

func TestNeteasePlaylistHasTracks_EmptyID(t *testing.T) {
	if neteasePlaylistHasTracks("") {
		t.Fatal("empty id must not be treated as available")
	}
}

func TestNeteasePlaylistHasTracks_BadID(t *testing.T) {
	if neteasePlaylistHasTracks("999999999999") {
		t.Fatal("nonexistent playlist must not be treated as available")
	}
}
