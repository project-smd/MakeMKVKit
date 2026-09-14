// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 the MakeMKVKit project authors

import Foundation

/// What `makemkvcon` should open — the `<source>` in its usage text.
public enum Source: Hashable, Sendable {
    /// `disc:N`, MakeMKV's own drive index, the `index` of a `Drive` line.
    case disc(Int)
    /// `dev:PATH`, the operating system's device name.
    case device(String)
    /// `iso:PATH`
    case iso(URL)
    /// `file:PATH`, a folder holding a `BDMV` or `VIDEO_TS` tree, such as a MakeMKV backup.
    case folder(URL)

    public var argument: String {
        switch self {
        case .disc(let index): "disc:\(index)"
        case .device(let name): "dev:\(name)"
        case .iso(let url): "iso:\(url.path)"
        case .folder(let url): "file:\(url.path)"
        }
    }
}
