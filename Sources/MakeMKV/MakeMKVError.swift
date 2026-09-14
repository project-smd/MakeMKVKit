// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import Foundation
import MakeMKVRobot

public enum MakeMKVError: Error, Sendable {
    /// No `makemkvcon` at any of the places looked.
    case executableNotFound(searched: [URL])
    /// The process exited non-zero. The messages are what it said on the way.
    case processFailed(status: Int32, messages: [Message])
    /// The run completed but never reached a disc: no usable drive, no medium, or the open failed.
    case discUnavailable(messages: [Message])
    /// The title is not one the given scan listed, so its index cannot be trusted.
    case titleNotInScan(index: Int)
    /// MakeMKV exited cleanly but the expected file is not there.
    case outputMissing(URL, messages: [Message])
    /// The title has no `OutputFileName` attribute, so the result cannot be located.
    case titleHasNoOutputName(index: Int)
}
