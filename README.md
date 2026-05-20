# playlist-rw.sh

A portable playlist path rewriter for Linux / Mac (Untested on Mac but should work). Replaces hardcoded local music paths in playlist and library files so they can be shared between users or machines without manual editing. **Assuming both users share the same music library**

## How it works

Music players store absolute paths to your files (e.g. `/home/alice/Music/...`). When you share a playlist with someone else, those paths break on their system because their username and directory structure are different.

`playlist-rw.sh` solves this with a two-step process:

- **Export** — replaces your local path with a neutral placeholder (`__MUSIC_PATH__`), producing a portable file safe to share
- **Import** — replaces the placeholder with the new user's local path, making it work on their system

The original file is never modified. All operations write to a separate output file.

## Supported formats

| Format | Path style | Method |
|--------|-----------|--------|
| `.pls` | `File1=file:///home/user/Music/...` | `sed` |
| `.xml` | `file:///home/user/Music/...` | `sed` |
| `.db` | stored in SQLite text columns | `sqlite3` |

## Requirements

- `bash` 3.2+
- `sed` (pre-installed on all Linux/macOS systems)
- `sqlite3` — only required for `.db` files (pre-installed on macOS)

## Installation

```bash
git clone https://github.com/yourname/playlist-rw
cd playlist-rw
chmod +x playlist-rw.sh
```

Or just download the script directly:

```bash
curl -O https://raw.githubusercontent.com/yourname/playlist-rw/main/playlist-rw.sh
chmod +x playlist-rw.sh
```

## Usage

```
./playlist-rw.sh --export -i <input>  -o <output>
./playlist-rw.sh --import -i <input>  -o <output>
```

| Flag | Description |
|------|-------------|
| `--export` | Replace your local music path with a portable placeholder |
| `--import` | Replace the placeholder with your local music path |
| `-i` | Path to the source file |
| `-o` | Path to write the rewritten file |

## Workflow

### Step 1 — Export (the person sharing the playlist)

```bash
./playlist-rw.sh --export -i playlist.pls -o playlist_portable.pls
```

The script will show a sample entry from your file and prompt for your music path:

```
=== EXPORT MODE (.pls) ===
Your local music path will be replaced with: __MUSIC_PATH__

Sample entry from your file:
  File1=file:///home/alice/Music/Artist/Album/track.flac

Enter your current music path to replace (e.g. /home/user/Music): /home/alice/Music

Done — portable file written.
  Input   : playlist.pls
  Replaced: /home/alice/Music
  With    : __MUSIC_PATH__
  Output  : playlist_portable.pls

Share 'playlist_portable.pls' and the recipient runs --import to set their own path.
```

Share the output file however you like — the paths in it are now machine-neutral.

### Step 2 — Import (the person receiving the playlist)

```bash
./playlist-rw.sh --import -i playlist_portable.pls -o playlist_local.pls
```

```
=== IMPORT MODE (.pls) ===
The placeholder '__MUSIC_PATH__' will be replaced with your local music path.

Enter your local music path (e.g. /home/yourname/Music): /home/bob/Music

Done — local file written.
  Input   : playlist_portable.pls
  Replaced: __MUSIC_PATH__
  With    : /home/bob/Music
  Output  : playlist_local.pls
```

## Examples by format

```bash
# .pls
./playlist-rw.sh --export -i playlist.pls          -o playlist_portable.pls
./playlist-rw.sh --import -i playlist_portable.pls -o playlist_local.pls

# .xml
./playlist-rw.sh --export -i library.xml           -o library_portable.xml
./playlist-rw.sh --import -i library_portable.xml  -o library_local.xml

# .db (SQLite)
./playlist-rw.sh --export -i collection.db         -o collection_portable.db
./playlist-rw.sh --import -i collection_portable.db -o collection_local.db
```

## Notes on .db files

SQLite databases are binary files — `sed` cannot safely modify them as changing string lengths corrupts the internal page structure. For `.db` files the script uses `sqlite3` instead, running `REPLACE()` via SQL across every text column in every table. This means no knowledge of the database schema is required and it works with any media player's database.

If `sqlite3` is not installed, the script will exit with instructions for your distro:

```
Ubuntu / Debian Based  : sudo apt install sqlite3
Fedora                 : sudo dnf install sqlite
Arch / Manjaro         : sudo pacman -S sqlite
openSUSE               : sudo zypper install sqlite3
Alpine                 : sudo apk add sqlite
macOS (Homebrew)       : brew install sqlite3
```

## Safety

- The input file is **never modified** — all changes go to the output path
- On export, the script shows a sample path entry from your file to help confirm the correct path to enter
- On export, the script warns if the path you entered is not found in the file before proceeding
- On import, the script validates that the placeholder exists in the file before prompting for a path, catching cases where a non-exported file is passed in by mistake
- Output directories are created automatically if they do not exist
