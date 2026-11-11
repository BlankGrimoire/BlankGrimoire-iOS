// SPDX-License-Identifier: MPL-2.0

import Foundation

/// The resource bundle that ships with ReaderCore.
///
/// Exposed so tests can inspect the compiled localization catalog instead of
/// relying on the process language, which is fixed at launch.
enum ReaderCoreResources {
    static var bundle: Bundle { .module }
}
