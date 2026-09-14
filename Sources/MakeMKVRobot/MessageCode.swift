// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

/// Message codes a caller is likely to branch on.
///
/// Two sources, kept separate so a reader knows how much to trust each. The first group is verified
/// against `apdefs.h` in makemkv-oss. The second is observed in saved logs — the code and the text
/// it came with — and is not named upstream anywhere this package could check.
public enum MessageCode {
    // From apdefs.h.
    public static let dumpDonePartial = 5004
    public static let dumpDone = 5005
    public static let initFailed = 5009
    public static let backupFailed = 5069
    public static let backupCompleted = 5070
    public static let backupCompletedHashFail = 5079

    // Observed. The comment is the format string the code arrived with.
    public static let started = 1005                  // "%1 started"
    public static let directDiscAccess = 3007         // "Using direct disc access mode"
    public static let titleSkippedShort = 3025        // "Title #%1 has length of %2 seconds which is less than minimum title length of %3 seconds and was therefore skipped"
    public static let titleAdded = 3307               // "File %1 was added as title #%2"
    public static let titleSkippedDuplicate = 3309    // "Title %1 is equal to title %2 and was skipped"
    public static let failedToOpenDisc = 5010         // "Failed to open disc"
    public static let operationCompleted = 5011       // "Operation successfully completed"
    public static let noUsableDrives = 5042           // "The program can't find any usable optical drives."
}
