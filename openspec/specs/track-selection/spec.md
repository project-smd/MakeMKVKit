# Track selection

## Purpose

Without a profile, `makemkvcon` keeps the tracks that this machine's saved selection rule says,
which is whatever the GUI last had. `SelectionRule` is MakeMKV's own selection language as a typed
value, and `ConversionProfile` is the `.mmcp.xml` document `--profile` takes, mirroring MakeMKV's
shipped default with the rule written in as a literal, so the same rip keeps the same tracks on any
machine. This spec covers the rule's text and the profile document. How a rip passes the profile is
the `makemkvcon-driver` spec's; how an engine session sets a rule is the `engine-session` spec's.

Documentation: [README](../../../README.md) ("Use" and "The format, as measured").

## Requirements

### Requirement: A rule is its actions joined by commas
`SelectionRule.description` SHALL be the text of each action, in order, joined by commas. An action
SHALL be written `+sel:<condition>` to select, `-sel:<condition>` to deselect, and `=<n>:`,
`+<n>:` or `-<n>:` followed by the condition to set, add or subtract a weight.

#### Scenario: selecting everything
- **WHEN** `SelectionRule.everything.description` is read
- **THEN** it is `+sel:all`

Pinned by: `Tests/MakeMKVTests/MakeMKVTests.swift` (`selectionRuleReproducesMakeMKVsDefault`).

### Requirement: Conditions are written in MakeMKV's vocabulary with `*` for and
A condition SHALL be written as its keyword for an attribute, the code for a language, the number
for an Nth-or-later condition, `!` before a negated condition, and a parenthesised list joined by
`*` for all-of and by `|` for any-of. `*` SHALL be used rather than `&`, MakeMKV's own alias, so the
rule needs no escaping inside an XML attribute. The attribute keywords SHALL be exactly MakeMKV's:
`all`, `video`, `audio`, `subtitle`, `favlang`, `nolang`, `single`, `special`, `mono`, `stereo`,
`multi`, `havemulti`, `lossy`, `lossless`, `havelossless`, `core`, `havecore`, `forced` and
`mvcvideo`.

#### Scenario: a composite rule
- **WHEN** a rule selects all, deselects `core`, deselects subtitle-and-forced, deselects not-English, and adds weight 5 to the second-or-later track
- **THEN** its text is `+sel:all,-sel:core,-sel:(subtitle*forced),-sel:!eng,+5:2`

Pinned by: `Tests/MakeMKVTests/MakeMKVTests.swift` (`selectionRuleReproducesMakeMKVsDefault`).

### Requirement: The default rule is MakeMKV's own, character for character
`SelectionRule.makeMKVDefault` SHALL produce exactly the `defaultSelection` string in the
`default.mmcp.xml` MakeMKV ships.

#### Scenario: the shipped default
- **WHEN** `SelectionRule.makeMKVDefault.description` is read
- **THEN** it is `-sel:all,+sel:(favlang|nolang|single),-sel:(havemulti|havecore),-sel:mvcvideo,=100:all,-10:favlang`

Pinned by: `Tests/MakeMKVTests/MakeMKVTests.swift` (`selectionRuleReproducesMakeMKVsDefault`).

### Requirement: The profile mirrors the shipped default with the rule inlined
`ConversionProfile.xml` SHALL be a well-formed profile document with the profile's name, MakeMKV's
default MKV settings, the three output settings of the shipped default (`copy` as direct copy,
`lpcm` as raw LPCM, `wavex` as LPCM in a WAV container), and three track settings — default input
copied, stereo LPCM as raw LPCM, multi-channel LPCM as WAVEX — each carrying the rule's text as its
`defaultSelection`. It SHALL NOT refer to the installed default selection preference. The name
defaults to `MakeMKVKit`.

#### Scenario: a profile's document
- **WHEN** the document of a profile whose rule is `+sel:all,-sel:core` is read
- **THEN** it has exactly three `defaultSelection` attributes, each with that rule, and no reference to the installed preference

Pinned by: `Tests/MakeMKVTests/MakeMKVTests.swift` (`conversionProfileInlinesTheRuleAndWrites`).

### Requirement: The profile's text is escaped for XML
The profile's name and rule SHALL be written with `&`, `<` and `"` replaced by their XML entities.

#### Scenario: a name with markup characters
- **WHEN** the document of a profile named `Test & <check>` is read
- **THEN** its name element holds `Test &amp; &lt;check>`, and the document parses as XML

Pinned by: `Tests/MakeMKVTests/MakeMKVTests.swift` (`conversionProfileInlinesTheRuleAndWrites`).

### Requirement: A profile is written to a file MakeMKV can be pointed at
`write(to:)` SHALL write the document as UTF-8, atomically. `writeToTemporaryFile()` SHALL write it
to a new file in the temporary directory named `makemkvkit-<uuid>.mmcp.xml` and return its URL; the
caller removes it.

#### Scenario: a temporary profile
- **WHEN** a profile is written to a temporary file
- **THEN** the file's extension is `xml` and its contents equal the profile's document

Pinned by: `Tests/MakeMKVTests/MakeMKVTests.swift` (`conversionProfileInlinesTheRuleAndWrites`).
