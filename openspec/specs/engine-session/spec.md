# Engine session

## Purpose

`EngineSession` keeps one MakeMKV engine alive across operations, the way MakeMKV's GUI does: it
spawns `makemkvcon guiserver`, speaks the GUI's protocol over the engine's standard input and
output, opens a disc once, ticks titles and tracks individually, and writes every ticked title in
one job. The protocol is unpublished and read from the open-source half of MakeMKV 1.18.4. This
spec covers the frame format, the launch and its handshakes, the call and callback loop, and the
session's operations. Nothing here but the frame format has an automated test; the rest needs a
drive with a disc in it and is exercised by hand.

Documentation: [README](../../../README.md) ("Keeping the engine open").

## Requirements

### Requirement: A frame is a command, numeric arguments and a string buffer
`EngineProtocol.Frame.encoded` SHALL be the single byte `0xf0 | command` when the frame has no
arguments and no data and the command's value is below 16. Otherwise it SHALL be a little-endian
32-bit header holding the command in the top byte, the argument count in the next, and the data
size in the low sixteen bits, followed by each argument as a little-endian 32-bit word, followed by
the data. A frame built from a string SHALL carry its UTF-8 bytes and a terminating NUL, and none
for a nil string. `handle(at:)` SHALL join arguments `i` and `i+1` as the low and high halves of a
64-bit handle; `string` SHALL be the data up to its first NUL, and `strings` the data split at every
NUL.

#### Scenario: a call with nothing to carry
- **WHEN** a frame for the idle call is encoded
- **THEN** it is the single byte `0xf4`

#### Scenario: a call with two arguments
- **WHEN** a frame opening drive 1, with arguments 1 and 0, is encoded
- **THEN** it is a four-byte header naming the command, two arguments and no data, then the two arguments as little-endian words

#### Scenario: a call carrying a string
- **WHEN** a frame setting the output folder to `/tmp` is encoded
- **THEN** its header counts five bytes of data, and the data is `/tmp` followed by a NUL

#### Scenario: a handle across two arguments
- **WHEN** a title-info frame's arguments 1 and 2 are `0x89abcdef` and `0x01234567`
- **THEN** `handle(at: 1)` is `0x0123456789abcdef`

Pinned by: `Tests/MakeMKVTests/MakeMKVTests.swift` (`engineFramesEncodeAsTheEngineExpects`).

### Requirement: The size field does not check the data fits
The encoder SHALL take the data size modulo 65536 for the header and SHALL send the whole buffer,
so a frame carrying more than 65535 bytes of data is sent with a header that disagrees with it and
is not refused, which is tracked as a defect in
https://github.com/project-smd/MakeMKVKit/issues/12.

#### Scenario: an oversized string
- **WHEN** a frame carrying a 70,000-byte string is encoded
- **THEN** the header's size field is the length modulo 65536 and all the bytes follow it

Pinned by: nothing yet.

### Requirement: The engine is launched with the ABI tag and both handshakes
Starting SHALL run the executable as `guiserver A0001+std` with the session's pipes on its standard
input and output, and SHALL drain its standard error continuously into the text that `diagnostics`
reports. It SHALL read the engine's reply up to `$` and fail with an ABI mismatch unless the part
before its first colon is `A0001`, failing too if the reply runs past 512 bytes. It SHALL then wait
for the byte `0xaa` and answer `0xbb`, after which every exchange is one frame each way. A failed
start SHALL NOT terminate the process it launched, so after an ABI mismatch the engine is left
running until `quit()` is called, which is tracked as a defect in
https://github.com/project-smd/MakeMKVKit/issues/9.

#### Scenario: an engine with a different ABI
- **WHEN** the engine answers with an ABI tag other than `A0001`
- **THEN** `start()` throws, naming both tags, the session is not started, and the engine process is still running

Pinned by: nothing yet.

### Requirement: Every read waits at most ten minutes
Each blocking read from the engine SHALL wait up to 600 seconds for data and fail with a read
timeout when none arrives, and SHALL fail with a lost connection when the pipe is closed or polling
fails. The errors thrown by the connection SHALL be of a type internal to the package, so a caller
can see but not match them.

Writing to an engine that has exited does not fail with a lost connection: the write raises
`SIGPIPE`, which is not ignored, and the host process is killed. This is tracked as a defect in
https://github.com/project-smd/MakeMKVKit/issues/5.

#### Scenario: an engine that has exited
- **WHEN** the engine exits after the handshake and the session then makes a call
- **THEN** the host process is terminated by `SIGPIPE`

#### Scenario: an engine that falls silent
- **WHEN** the engine sends nothing for 600 seconds during a call
- **THEN** the call throws the connection's read-timeout failure

Pinned by: nothing yet.

### Requirement: A call services callbacks until the engine returns
An engine call made when the session has not started SHALL throw `notStarted`; an operation's own
guards run first, so an unknown title still throws `unknownTitle` and saving with no disc
`noDiscOpen`. Otherwise a call SHALL send its
frame and service every frame the engine sends back, answering each with `clientDone`, until the
engine sends `return`, whose frame is the call's result. When the engine sends exit, fatal
communication error or out of memory, the call SHALL mark the session not started and throw
`engineExited`.

#### Scenario: the engine exits during a call
- **WHEN** the engine sends its exit callback in reply to a call
- **THEN** the call throws `engineExited` and later calls throw `notStarted`

Pinned by: nothing yet.

### Requirement: Messages and questions become events, and questions go unanswered
A UI message callback SHALL emit a message event with its code, flags and text and be answered
`clientDone` with argument 0. A dialog callback SHALL emit a message event whose text begins
`Engine asked: ` followed by the dialog's strings, and SHALL be answered with −1, "no answer", so
the engine takes its default. Enter and leave job mode SHALL emit job-started and job-finished
events, and each progress-bar callback SHALL emit a progress event whose captions are the texts of
the latest total and current caption codes and whose maximum is 65536. Events go to the handler set
with `setEventHandler(_:)`, and are dropped when none is set.

#### Scenario: the engine asks a question
- **WHEN** the engine raises a dialog while opening a disc
- **THEN** the handler receives a message event beginning `Engine asked: `, and the open continues with the engine's default

Pinned by: nothing yet.

### Requirement: A job-starting call returns only when the job has finished
An operation that starts an engine job — listing drives, opening, closing and saving — SHALL record
how many jobs have finished, make its call, and then poll the engine's idle call every 25
milliseconds until the finished count moves past the recorded one, whether the job completed inside
the call's own callback loop or started after it returned, and then poll once more. It SHALL wait
this way even when the engine answered the call with a refusal and started no job. After 72,001
polls, about half an hour, it SHALL stop waiting and return as though the job had finished, without
an error, so a refused open or save is reported as `openFailed` or `saveRefused` only after that
half hour. This is tracked as a defect in
https://github.com/project-smd/MakeMKVKit/issues/8.

#### Scenario: a disc open whose job starts after the call returns
- **WHEN** the engine returns from the open call and only then enters and leaves job mode
- **THEN** `open` waits for the job to finish before reading the title tree

#### Scenario: an open the engine refuses
- **WHEN** the engine answers the open call with zero and never enters job mode
- **THEN** `open` keeps polling for about half an hour before throwing `openFailed`

Pinned by: nothing yet.

### Requirement: Opening a disc reads the whole title tree into a DiscInfo
`open(_:minimumTitleLength:)` SHALL first set the engine's minimum title length in its memory when
one is given, then open a drive by index, a device through a `dev:` title collection, or an image
or folder by path, and SHALL throw `openFailed` when the engine refuses or reports no disc. It SHALL
then read attributes 1 to 50 of the disc, each title and each track, resolving a coded value to its
text through the engine's message strings (cached per code) and keeping the code, so the result
carries the codes robot mode prints. A track whose type code is the cover-art attachment code 6214
SHALL be left out of the title's tracks and unticked. The result SHALL be a `DiscInfo` with the
title count the engine announced and the titles in index order. The disc stays open until `close()`
or the next `open`.

#### Scenario: a Blu-ray with cover art
- **WHEN** a disc whose engine tree lists cover art beside a title's tracks is opened
- **THEN** the title's tracks do not include it and the engine no longer has it ticked

Pinned by: nothing yet.

### Requirement: Selection changes the engine's ticks and never the user's settings
`setSelectionRule(_:)` SHALL set the engine's default selection string to the rule's text in its
memory, and no call in the session SHALL save the engine's settings, so the user's preferences on
disk are untouched. `isSelected` and `setSelected` for a title, or for a track of a title, SHALL
read or change that item's enabled bit, changing nothing when it is already as wanted, and SHALL
throw `unknownTitle` with the title index when the open disc has no such title or no such track.

#### Scenario: a track the title does not have
- **WHEN** `setSelected(_:title:track:)` names a track index the title does not have
- **THEN** it throws `unknownTitle` with the title's index

Pinned by: nothing yet.

### Requirement: Saving writes every ticked title in one job
`saveSelectedTitles(to:)` SHALL throw `noDiscOpen` when no disc is open, create the destination
folder, set it as the engine's output folder, run the save job to its end, and throw `saveRefused`
when the engine answers the save call with zero. Each file is named by its title's output file
name. `cancel()` SHALL ask the engine to cancel every job.

#### Scenario: saving with no disc open
- **WHEN** `saveSelectedTitles(to:)` is called before any disc is opened
- **THEN** it throws `noDiscOpen` and creates nothing

Pinned by: nothing yet.

### Requirement: Closing ejects nothing and quitting stops the engine
`close()` SHALL close the open disc, passing the drive count so that nothing is ejected, and forget
the disc's collection, title and track handles. `quit()` SHALL, when the session is started and the
engine running, ask the engine to exit, ignoring any error, then terminate the process if it is
still running and mark the session not started.

#### Scenario: closing the disc
- **WHEN** `close()` is called after a disc was opened
- **THEN** title selection calls throw `unknownTitle` and saving throws `noDiscOpen`

Pinned by: nothing yet.

### Requirement: Calls on one session are not serialised
`EngineSession` SHALL be an actor, but a call's callback loop suspends at every frame, so a second
call made on the same session while one is in progress SHALL be able to send its frames between the
first call's frames, and the engine's replies are then read by whichever call is waiting. A session
is therefore safe only when its caller awaits each call before making the next. Nothing in the type
says so, which is tracked in https://github.com/project-smd/MakeMKVKit/issues/7.

#### Scenario: two calls at once
- **WHEN** a caller starts `drives()` and, before it returns, calls `isSelected(title:)` on the same session
- **THEN** the second call's frame can be sent while the first is still servicing callbacks

Pinned by: nothing yet.
