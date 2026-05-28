set mediaQuery to {query}
set trimmedQuery to mediaQuery as text

if trimmedQuery is "" then
    return "status=not_found" & linefeed & "clarification.required=true" & linefeed & "clarification.question=What would you like me to play?"
end if

tell application id "com.apple.Music"
    activate
end tell

delay 0.4

tell application "System Events"
    if not (exists process "Music") then
        return "status=failed" & linefeed & "failureReason=music_process_unavailable"
    end if

    tell process "Music"
        set frontmost to true
    end tell

    keystroke "f" using command down
    delay 0.2
    keystroke trimmedQuery
    delay 0.2
    key code 36
    delay 1.0
    key code 36
end tell

return "status=played" & linefeed & "query=" & trimmedQuery & linefeed & "playedTitle=" & trimmedQuery
