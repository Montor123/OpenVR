package openvr

import (
	"embed"
	"io/fs"
)

//go:embed web/*
var assets embed.FS

func Web() fs.FS {
	files, err := fs.Sub(assets, "web")
	if err != nil {
		panic(err)
	}
	return files
}
