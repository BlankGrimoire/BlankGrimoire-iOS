// SPDX-License-Identifier: MPL-2.0

// ReaderCore - Public API
//
// ReaderCore is a single Swift module. Its folders (Domain, Persistence,
// PluginEngine, ImagePipeline, Features, DesignSystem) are conventions, not
// compiler-enforced targets: everything declared `public` here is the App's
// import surface. Keep persistence types out of Domain and UI code out of the
// engine folders so the conventions stay useful.
