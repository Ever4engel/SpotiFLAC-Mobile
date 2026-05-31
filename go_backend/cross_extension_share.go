package gobackend

import (
	"encoding/json"
	"strings"
	"sync"
)

type CrossExtensionShareResult struct {
	ExtensionID string `json:"extension_id"`
	DisplayName string `json:"display_name"`
	Found       bool   `json:"found"`
	URL         string `json:"url,omitempty"`
	ItemName    string `json:"item_name,omitempty"`
	ItemArtists string `json:"item_artists,omitempty"`
	Error       string `json:"error,omitempty"`
}

func FindCollectionAcrossExtensionsJSON(requestJSON string) (string, error) {
	var req struct {
		Name              string `json:"name"`
		Artists           string `json:"artists"`
		Type              string `json:"type"`
		SourceExtensionID string `json:"source_extension_id"`
	}
	if err := json.Unmarshal([]byte(requestJSON), &req); err != nil {
		return "", err
	}

	req.Name = strings.TrimSpace(req.Name)
	req.Artists = strings.TrimSpace(req.Artists)
	req.Type = strings.ToLower(strings.TrimSpace(req.Type))
	req.SourceExtensionID = strings.TrimSpace(req.SourceExtensionID)
	if req.Name == "" {
		return "[]", nil
	}
	if req.Type == "" {
		req.Type = "album"
	}

	providers := getExtensionManager().GetMetadataProviders()
	work := make([]*extensionProviderWrapper, 0, len(providers))
	for _, provider := range providers {
		if provider == nil || provider.extension == nil {
			continue
		}
		if provider.extension.ID == req.SourceExtensionID {
			continue
		}
		work = append(work, provider)
	}

	query := req.Name
	if req.Artists != "" {
		query += " " + req.Artists
	}

	results := make([]CrossExtensionShareResult, len(work))
	var wg sync.WaitGroup
	for i, provider := range work {
		wg.Add(1)
		go func(index int, p *extensionProviderWrapper) {
			defer wg.Done()
			results[index] = findCollectionForExtension(
				p,
				req.Type,
				req.Name,
				req.Artists,
				query,
			)
		}(i, provider)
	}
	wg.Wait()

	data, err := json.Marshal(results)
	if err != nil {
		return "[]", err
	}
	return string(data), nil
}

func findCollectionForExtension(
	provider *extensionProviderWrapper,
	itemType string,
	name string,
	artists string,
	query string,
) CrossExtensionShareResult {
	result := CrossExtensionShareResult{
		ExtensionID: provider.extension.ID,
	}
	if provider.extension.Manifest != nil {
		result.DisplayName = provider.extension.Manifest.DisplayName
	}
	if result.DisplayName == "" {
		result.DisplayName = provider.extension.ID
	}

	searchResult, err := provider.SearchTracks(query, 10)
	if err != nil {
		result.Error = err.Error()
		return result
	}
	if searchResult == nil || len(searchResult.Tracks) == 0 {
		result.Error = "no results"
		return result
	}

	var best *ExtTrackMetadata
	switch itemType {
	case "artist":
		best = bestArtistTrack(searchResult.Tracks, name)
	case "album":
		best = bestAlbumTrack(searchResult.Tracks, name, artists)
	default:
		result.Error = "unsupported collection type"
		return result
	}
	if best == nil {
		result.Error = itemType + " not found"
		return result
	}

	url := resolveCollectionShareURL(provider.extension, itemType, best)
	if url == "" {
		result.Error = itemType + " found without shareable link"
		return result
	}

	result.Found = true
	result.URL = url
	if itemType == "artist" {
		result.ItemName = best.Artists
	} else {
		result.ItemName = best.AlbumName
		result.ItemArtists = best.Artists
	}
	return result
}

func bestAlbumTrack(tracks []ExtTrackMetadata, albumName string, artists string) *ExtTrackMetadata {
	targetAlbum := normalizeLooseTitle(albumName)
	targetArtists := normalizeLooseArtistName(artists)
	bestScore := 0
	bestIndex := -1

	for i := range tracks {
		track := tracks[i]
		album := normalizeLooseTitle(track.AlbumName)
		trackArtists := normalizeLooseArtistName(track.Artists + " " + track.AlbumArtist)

		score := 0
		if album == targetAlbum {
			score += 100
		} else if album != "" && targetAlbum != "" && (strings.Contains(album, targetAlbum) || strings.Contains(targetAlbum, album)) {
			score += 50
		}
		if targetArtists != "" && (strings.Contains(trackArtists, targetArtists) || strings.Contains(targetArtists, trackArtists)) {
			score += 30
		}
		if score > bestScore {
			bestScore = score
			bestIndex = i
		}
	}

	if bestIndex < 0 || bestScore < 50 {
		return nil
	}
	return &tracks[bestIndex]
}

func bestArtistTrack(tracks []ExtTrackMetadata, artistName string) *ExtTrackMetadata {
	targetArtist := normalizeLooseArtistName(artistName)
	bestScore := 0
	bestIndex := -1

	for i := range tracks {
		artist := normalizeLooseArtistName(tracks[i].Artists)
		score := 0
		if artist == targetArtist {
			score += 100
		} else if artist != "" && targetArtist != "" && (strings.Contains(artist, targetArtist) || strings.Contains(targetArtist, artist)) {
			score += 60
		}
		if score > bestScore {
			bestScore = score
			bestIndex = i
		}
	}

	if bestIndex < 0 || bestScore < 60 {
		return nil
	}
	return &tracks[bestIndex]
}

func resolveCollectionShareURL(ext *loadedExtension, itemType string, track *ExtTrackMetadata) string {
	if track == nil {
		return ""
	}

	if itemType == "album" {
		if url := normalizeShareURL(track.AlbumURL); url != "" {
			return url
		}
		if url := urlFromExternalLinks(track.ExternalLinks, "album"); url != "" {
			return url
		}
		if url := templateShareURL(ext, "album", firstNonEmptyString(track.AlbumID, track.AlbumURL)); url != "" {
			return url
		}
		return ""
	}

	if url := normalizeShareURL(track.ArtistURL); url != "" {
		return url
	}
	if url := urlFromExternalLinks(track.ExternalLinks, "artist"); url != "" {
		return url
	}
	if url := templateShareURL(ext, "artist", track.ArtistID); url != "" {
		return url
	}
	return ""
}

func normalizeShareURL(value string) string {
	trimmed := strings.TrimSpace(value)
	if strings.HasPrefix(trimmed, "http://") || strings.HasPrefix(trimmed, "https://") {
		return trimmed
	}
	return ""
}

func urlFromExternalLinks(links map[string]string, preferredKey string) string {
	for key, value := range links {
		if strings.Contains(strings.ToLower(key), preferredKey) {
			if url := normalizeShareURL(value); url != "" {
				return url
			}
		}
	}
	return ""
}

func templateShareURL(ext *loadedExtension, itemType string, id string) string {
	if ext == nil || ext.Manifest == nil || ext.Manifest.Capabilities == nil {
		return ""
	}
	id = stripProviderPrefix(strings.TrimSpace(id))
	if id == "" {
		return ""
	}

	templates, ok := ext.Manifest.Capabilities["shareUrlTemplates"].(map[string]interface{})
	if !ok {
		return ""
	}
	rawTemplate, ok := templates[itemType].(string)
	if !ok {
		return ""
	}
	rawTemplate = strings.TrimSpace(rawTemplate)
	if rawTemplate == "" {
		return ""
	}
	return strings.ReplaceAll(rawTemplate, "{id}", id)
}

func stripProviderPrefix(id string) string {
	if index := strings.Index(id, ":"); index > 0 && index < len(id)-1 {
		return id[index+1:]
	}
	return id
}

func firstNonEmptyString(values ...string) string {
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed != "" {
			return trimmed
		}
	}
	return ""
}
