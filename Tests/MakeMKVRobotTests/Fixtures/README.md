# Fixtures

Three MakeMKV robot logs and the JSON TheDiscDb derived from each, copied unchanged from
https://github.com/TheDiscDb/data (MIT; see `LICENSE-thediscdb`).

| Files | Why this one |
| --- | --- |
| `daleks-in-colour-disc01-bluray.*` | Blu-ray; two playlists skipped as duplicates; 11 `HSH:` lines that are TheDiscDb's, not MakeMKV's |
| `daleks-in-colour-disc02-dvd.*` | DVD; titles identified by `OriginalTitleId` rather than a playlist name |
| `real-life-disc01-uhd.*` | UHD, which MakeMKV reports with the Blu-ray type code |

The logs were written by MakeMKV on Windows (`win(x64-release)`), which is what most of the corpus
is; the format does not differ by platform.
