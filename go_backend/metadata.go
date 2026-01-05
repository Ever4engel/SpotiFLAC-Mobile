package gobackend

import (
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/go-flac/flacpicture"
	"github.com/go-flac/flacvorbis"
	"github.com/go-flac/go-flac"
)

// Metadata represents track metadata for embedding
type Metadata struct {
	Title       string
	Artist      string
	Album       string
	AlbumArtist string
	Date        string
	TrackNumber int
	TotalTracks int
	DiscNumber  int
	ISRC        string
	Description string
	Lyrics      string
}

// EmbedMetadata embeds metadata into a FLAC file
func EmbedMetadata(filePath string, metadata Metadata, coverPath string) error {
	f, err := flac.ParseFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to parse FLAC file: %w", err)
	}

	// Find or create vorbis comment block
	var cmtIdx int = -1
	var cmt *flacvorbis.MetaDataBlockVorbisComment

	for idx, meta := range f.Meta {
		if meta.Type == flac.VorbisComment {
			cmtIdx = idx
			cmt, err = flacvorbis.ParseFromMetaDataBlock(*meta)
			if err != nil {
				return fmt.Errorf("failed to parse vorbis comment: %w", err)
			}
			break
		}
	}

	if cmt == nil {
		cmt = flacvorbis.New()
	}

	// Set metadata fields
	setComment(cmt, "TITLE", metadata.Title)
	setComment(cmt, "ARTIST", metadata.Artist)
	setComment(cmt, "ALBUM", metadata.Album)
	setComment(cmt, "ALBUMARTIST", metadata.AlbumArtist)
	setComment(cmt, "DATE", metadata.Date)
	
	if metadata.TrackNumber > 0 {
		if metadata.TotalTracks > 0 {
			setComment(cmt, "TRACKNUMBER", fmt.Sprintf("%d/%d", metadata.TrackNumber, metadata.TotalTracks))
		} else {
			setComment(cmt, "TRACKNUMBER", strconv.Itoa(metadata.TrackNumber))
		}
	}
	
	if metadata.DiscNumber > 0 {
		setComment(cmt, "DISCNUMBER", strconv.Itoa(metadata.DiscNumber))
	}
	
	if metadata.ISRC != "" {
		setComment(cmt, "ISRC", metadata.ISRC)
	}
	
	if metadata.Description != "" {
		setComment(cmt, "DESCRIPTION", metadata.Description)
	}

	if metadata.Lyrics != "" {
		setComment(cmt, "LYRICS", metadata.Lyrics)
		setComment(cmt, "UNSYNCEDLYRICS", metadata.Lyrics)
	}

	// Update or add vorbis comment block
	cmtBlock := cmt.Marshal()
	if cmtIdx >= 0 {
		f.Meta[cmtIdx] = &cmtBlock
	} else {
		f.Meta = append(f.Meta, &cmtBlock)
	}

	// Add cover art if provided
	if coverPath != "" {
		if fileExists(coverPath) {
			coverData, err := os.ReadFile(coverPath)
			if err != nil {
				fmt.Printf("[Metadata] Warning: Failed to read cover file %s: %v\n", coverPath, err)
			} else {
				// Remove existing picture blocks first (like PC version)
				for i := len(f.Meta) - 1; i >= 0; i-- {
					if f.Meta[i].Type == flac.Picture {
						f.Meta = append(f.Meta[:i], f.Meta[i+1:]...)
					}
				}
				
				picture, err := flacpicture.NewFromImageData(
					flacpicture.PictureTypeFrontCover,
					"Front Cover",
					coverData,
					"image/jpeg",
				)
				if err != nil {
					fmt.Printf("[Metadata] Warning: Failed to create picture block: %v\n", err)
				} else {
					picBlock := picture.Marshal()
					f.Meta = append(f.Meta, &picBlock)
					fmt.Printf("[Metadata] Cover art embedded successfully (%d bytes)\n", len(coverData))
				}
			}
		} else {
			fmt.Printf("[Metadata] Warning: Cover file does not exist: %s\n", coverPath)
		}
	}

	// Save file
	return f.Save(filePath)
}

// EmbedMetadataWithCoverData embeds metadata into a FLAC file with cover data as bytes
// This avoids file permission issues on Android by not requiring a temp file
func EmbedMetadataWithCoverData(filePath string, metadata Metadata, coverData []byte) error {
	f, err := flac.ParseFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to parse FLAC file: %w", err)
	}

	// Find or create vorbis comment block
	var cmtIdx int = -1
	var cmt *flacvorbis.MetaDataBlockVorbisComment

	for idx, meta := range f.Meta {
		if meta.Type == flac.VorbisComment {
			cmtIdx = idx
			cmt, err = flacvorbis.ParseFromMetaDataBlock(*meta)
			if err != nil {
				return fmt.Errorf("failed to parse vorbis comment: %w", err)
			}
			break
		}
	}

	if cmt == nil {
		cmt = flacvorbis.New()
	}

	// Set metadata fields
	setComment(cmt, "TITLE", metadata.Title)
	setComment(cmt, "ARTIST", metadata.Artist)
	setComment(cmt, "ALBUM", metadata.Album)
	setComment(cmt, "ALBUMARTIST", metadata.AlbumArtist)
	setComment(cmt, "DATE", metadata.Date)
	
	if metadata.TrackNumber > 0 {
		if metadata.TotalTracks > 0 {
			setComment(cmt, "TRACKNUMBER", fmt.Sprintf("%d/%d", metadata.TrackNumber, metadata.TotalTracks))
		} else {
			setComment(cmt, "TRACKNUMBER", strconv.Itoa(metadata.TrackNumber))
		}
	}
	
	if metadata.DiscNumber > 0 {
		setComment(cmt, "DISCNUMBER", strconv.Itoa(metadata.DiscNumber))
	}
	
	if metadata.ISRC != "" {
		setComment(cmt, "ISRC", metadata.ISRC)
	}
	
	if metadata.Description != "" {
		setComment(cmt, "DESCRIPTION", metadata.Description)
	}

	if metadata.Lyrics != "" {
		setComment(cmt, "LYRICS", metadata.Lyrics)
		setComment(cmt, "UNSYNCEDLYRICS", metadata.Lyrics)
	}

	// Update or add vorbis comment block
	cmtBlock := cmt.Marshal()
	if cmtIdx >= 0 {
		f.Meta[cmtIdx] = &cmtBlock
	} else {
		f.Meta = append(f.Meta, &cmtBlock)
	}

	// Add cover art if provided
	if len(coverData) > 0 {
		// Remove existing picture blocks first
		for i := len(f.Meta) - 1; i >= 0; i-- {
			if f.Meta[i].Type == flac.Picture {
				f.Meta = append(f.Meta[:i], f.Meta[i+1:]...)
			}
		}
		
		picture, err := flacpicture.NewFromImageData(
			flacpicture.PictureTypeFrontCover,
			"Front Cover",
			coverData,
			"image/jpeg",
		)
		if err != nil {
			fmt.Printf("[Metadata] Warning: Failed to create picture block: %v\n", err)
		} else {
			picBlock := picture.Marshal()
			f.Meta = append(f.Meta, &picBlock)
			fmt.Printf("[Metadata] Cover art embedded successfully (%d bytes)\n", len(coverData))
		}
	}

	// Save file
	return f.Save(filePath)
}

// ReadMetadata reads metadata from a FLAC file
func ReadMetadata(filePath string) (*Metadata, error) {
	f, err := flac.ParseFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to parse FLAC file: %w", err)
	}

	metadata := &Metadata{}

	for _, meta := range f.Meta {
		if meta.Type == flac.VorbisComment {
			cmt, err := flacvorbis.ParseFromMetaDataBlock(*meta)
			if err != nil {
				continue
			}

			metadata.Title = getComment(cmt, "TITLE")
			metadata.Artist = getComment(cmt, "ARTIST")
			metadata.Album = getComment(cmt, "ALBUM")
			metadata.AlbumArtist = getComment(cmt, "ALBUMARTIST")
			metadata.Date = getComment(cmt, "DATE")
			metadata.ISRC = getComment(cmt, "ISRC")
			metadata.Description = getComment(cmt, "DESCRIPTION")

			metadata.Lyrics = getComment(cmt, "LYRICS")
			if metadata.Lyrics == "" {
				metadata.Lyrics = getComment(cmt, "UNSYNCEDLYRICS")
			}

			trackNum := getComment(cmt, "TRACKNUMBER")
			if trackNum != "" {
				fmt.Sscanf(trackNum, "%d", &metadata.TrackNumber)
			}

			discNum := getComment(cmt, "DISCNUMBER")
			if discNum != "" {
				fmt.Sscanf(discNum, "%d", &metadata.DiscNumber)
			}

			break
		}
	}

	return metadata, nil
}

func setComment(cmt *flacvorbis.MetaDataBlockVorbisComment, key, value string) {
	if value == "" {
		return
	}
	// Remove existing (case-insensitive comparison for Vorbis comments)
	keyUpper := strings.ToUpper(key)
	for i := len(cmt.Comments) - 1; i >= 0; i-- {
		comment := cmt.Comments[i]
		eqIdx := strings.Index(comment, "=")
		if eqIdx > 0 {
			existingKey := strings.ToUpper(comment[:eqIdx])
			if existingKey == keyUpper {
				cmt.Comments = append(cmt.Comments[:i], cmt.Comments[i+1:]...)
			}
		}
	}
	// Add new
	cmt.Comments = append(cmt.Comments, key+"="+value)
}

func getComment(cmt *flacvorbis.MetaDataBlockVorbisComment, key string) string {
	for _, comment := range cmt.Comments {
		if len(comment) > len(key)+1 && comment[:len(key)+1] == key+"=" {
			return comment[len(key)+1:]
		}
	}
	return ""
}

// fileExists checks if a file exists
func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// EmbedLyrics embeds lyrics into a FLAC file as a separate operation
func EmbedLyrics(filePath string, lyrics string) error {
	f, err := flac.ParseFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to parse FLAC file: %w", err)
	}

	var cmtIdx int = -1
	var cmt *flacvorbis.MetaDataBlockVorbisComment

	for idx, meta := range f.Meta {
		if meta.Type == flac.VorbisComment {
			cmtIdx = idx
			cmt, err = flacvorbis.ParseFromMetaDataBlock(*meta)
			if err != nil {
				return fmt.Errorf("failed to parse vorbis comment: %w", err)
			}
			break
		}
	}

	if cmt == nil {
		cmt = flacvorbis.New()
	}

	setComment(cmt, "LYRICS", lyrics)
	setComment(cmt, "UNSYNCEDLYRICS", lyrics)

	cmtBlock := cmt.Marshal()
	if cmtIdx >= 0 {
		f.Meta[cmtIdx] = &cmtBlock
	} else {
		f.Meta = append(f.Meta, &cmtBlock)
	}

	return f.Save(filePath)
}

// ExtractLyrics extracts embedded lyrics from a FLAC file
func ExtractLyrics(filePath string) (string, error) {
	f, err := flac.ParseFile(filePath)
	if err != nil {
		return "", fmt.Errorf("failed to parse FLAC file: %w", err)
	}

	for _, meta := range f.Meta {
		if meta.Type == flac.VorbisComment {
			cmt, err := flacvorbis.ParseFromMetaDataBlock(*meta)
			if err != nil {
				continue
			}
			
			// Try LYRICS tag first
			lyrics, err := cmt.Get("LYRICS")
			if err == nil && len(lyrics) > 0 && lyrics[0] != "" {
				return lyrics[0], nil
			}
			
			// Fallback to UNSYNCEDLYRICS
			lyrics, err = cmt.Get("UNSYNCEDLYRICS")
			if err == nil && len(lyrics) > 0 && lyrics[0] != "" {
				return lyrics[0], nil
			}
		}
	}

	return "", fmt.Errorf("no lyrics found in file")
}

// AudioQuality represents audio quality info from a FLAC file
type AudioQuality struct {
	BitDepth   int `json:"bit_depth"`
	SampleRate int `json:"sample_rate"`
}

// GetAudioQuality reads bit depth and sample rate from a FLAC file's StreamInfo block
// FLAC StreamInfo is always the first metadata block after the 4-byte "fLaC" marker
func GetAudioQuality(filePath string) (AudioQuality, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return AudioQuality{}, fmt.Errorf("failed to open file: %w", err)
	}
	defer file.Close()

	// Read FLAC marker (4 bytes: "fLaC")
	marker := make([]byte, 4)
	if _, err := file.Read(marker); err != nil {
		return AudioQuality{}, fmt.Errorf("failed to read marker: %w", err)
	}
	if string(marker) != "fLaC" {
		return AudioQuality{}, fmt.Errorf("not a FLAC file")
	}

	// Read metadata block header (4 bytes)
	// Byte 0: bit 7 = last block flag, bits 0-6 = block type (0 = STREAMINFO)
	// Bytes 1-3: block length (24-bit big-endian)
	header := make([]byte, 4)
	if _, err := file.Read(header); err != nil {
		return AudioQuality{}, fmt.Errorf("failed to read header: %w", err)
	}

	blockType := header[0] & 0x7F
	if blockType != 0 {
		return AudioQuality{}, fmt.Errorf("first block is not STREAMINFO")
	}

	// Read STREAMINFO block (34 bytes minimum)
	// Bytes 10-13 contain sample rate (20 bits), channels (3 bits), bits per sample (5 bits)
	streamInfo := make([]byte, 34)
	if _, err := file.Read(streamInfo); err != nil {
		return AudioQuality{}, fmt.Errorf("failed to read STREAMINFO: %w", err)
	}

	// Parse sample rate (20 bits starting at byte 10)
	// Bytes 10-12: [SSSS SSSS] [SSSS SSSS] [SSSS CCCC] where S=sample rate, C=channels
	sampleRate := (int(streamInfo[10]) << 12) | (int(streamInfo[11]) << 4) | (int(streamInfo[12]) >> 4)

	// Parse bits per sample (5 bits)
	// Byte 12 bits 0-3 and byte 13 bit 7: [.... BBBB] [B...] where B=bits per sample - 1
	bitsPerSample := ((int(streamInfo[12]) & 0x01) << 4) | (int(streamInfo[13]) >> 4) + 1

	return AudioQuality{
		BitDepth:   bitsPerSample,
		SampleRate: sampleRate,
	}, nil
}
