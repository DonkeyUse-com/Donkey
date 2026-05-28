# Music Media
id: music-media
description: Plan low-risk media playback in Apple Music or another supported media app.
tags: media, music, playback, local-app
tools: app.openOrFocus, app.observe, ui.focusSearch, ui.setText, ui.pressReturn, app.verifyVisibleText

Use this skill for play or listen requests when a supported media app or a `play_media` catalog capability is available.

First decide the playback source. Use `metadata.mediaSelection.source=local_library` only when the user explicitly asks for local, library, downloaded, or owned music. Otherwise use `metadata.mediaSelection.source=streaming`; Apple Music is normally a streaming catalog, so the workflow should search, find an actual playable streaming result, and play it.

For explicit songs, albums, or playlists, put the concrete playable title plus artist when known in `query`.

For vague artist, mood, or genre playback requests, choose one concrete representative song before returning task JSON. Do not choose a representative album, artist page, library item, station, or genre page when the user asks to play music. Do not use an artist-only query for playback unless the user explicitly asks to open an artist page, artist albums, artist radio, station, or another browsing surface. If you cannot choose one concrete representative song with high confidence, return clarification instead of a local app task.

Set `metadata.mediaSelection.kind` to `explicit_song`, `explicit_album`, `explicit_playlist`, or `representative_song`, and always set `metadata.mediaSelection.source` to `streaming` or `local_library`. For representative choices, also set `metadata.mediaSelection.seed`, `metadata.mediaSelection.selectedTitle`, and a short `metadata.mediaSelection.reason`. The `query` must include the selected song title and artist, not only the artist, album, genre, or mood seed.

Also return a bounded AppleScript artifact for Apple Music playback when the selected catalog entry has bundle identifier `com.apple.Music`. Put it in metadata, not in free text:

- `metadata.automationBackend=appleScript`
- `metadata.appleScript.action=music.playMediaBySearch`
- `metadata.appleScript.entityName=query`
- `metadata.appleScript.query` equal to the same structured `query`
- `metadata.appleScript.source` containing AppleScript that uses only the structured `query`, targets `application id "com.apple.Music"`, opens/focuses Music, searches for the query, activates a playable result, and returns compact status text

The AppleScript must be bounded and deterministic. It must not use raw user text, shell commands, files, deletion, quitting apps, network commands, or unrelated applications. Keep the UI plan below as the fallback path even when AppleScript metadata is present.

When planning generic `local_app_interaction`, use `targetAppName` and `entities.appName` from the supported catalog entry. Use `goal=play media`, `inputEntity=query`, `controlID=search`, `focusKey=Command+F`, and tools `app.openOrFocus`, `app.observe`, `ui.focusSearch`, `ui.setText`, `ui.pressReturn`, a second `ui.pressReturn`, and `app.verifyVisibleText`. The first Return submits the search; the second Return activates the top playable result. If visible results are present, prefer a playable song row matching the requested seed over artist, playlist, category, or unrelated rows.
