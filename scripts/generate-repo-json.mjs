#!/usr/bin/env node
// SPDX-License-Identifier: MPL-2.0
//
// Regenerates repo.json, the AltStore/SideStore source that points at the
// unsigned IPA published with every GitHub release. SideStore reads the file
// over plain HTTPS, compares `versions[].version` with the installed build and
// offers an in-app update.
//
// Usage: node scripts/generate-repo-json.mjs <version> <ipa-path>

import { existsSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const REPOSITORY = "BlankGrimoire/BlankGrimoire-iOS";
const SOURCE_FILE = join(ROOT, "repo.json");
const DEFAULT_BUNDLE_ID = "com.blankgrimoire.app";
const TINT_COLOR = "#6C4AB6";

const [version, ipaArgument] = process.argv.slice(2);
if (!version || !ipaArgument) {
  console.error("usage: generate-repo-json.mjs <version> <ipa-path>");
  process.exit(1);
}

const ipaPath = resolve(process.cwd(), ipaArgument);
if (!existsSync(ipaPath)) {
  console.error(`IPA not found: ${ipaPath}`);
  process.exit(1);
}

const ipaName = basename(ipaPath);
const ipaSize = statSync(ipaPath).size;
const project = readFileSync(join(ROOT, "project.yml"), "utf8");
const infoPlist = readFileSync(join(ROOT, "BlankGrimoire/Info.plist"), "utf8");
const bundleIdentifier =
  /PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)/.exec(project)?.[1] ?? DEFAULT_BUNDLE_ID;
const minOSVersion = /deploymentTarget:\s*"([0-9.]+)"/.exec(project)?.[1] ?? "17.0";
const buildVersion = /CURRENT_PROJECT_VERSION:\s*([0-9]+)/.exec(project)?.[1] ?? "1";

// AltStore checks that the declared permissions match the IPA. The app declares
// no entitlements and no usage descriptions today; parse the plist so a future
// search/location prompt cannot make installs fail silently.
function usageDescriptions() {
  const privacy = {};
  const pattern = /<key>(NS[A-Za-z]+UsageDescription)<\/key>\s*<string>([\s\S]*?)<\/string>/g;
  for (const [, key, value] of infoPlist.matchAll(pattern)) {
    privacy[key] = value
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'");
  }
  return privacy;
}

const releaseURL = `https://github.com/${REPOSITORY}/releases/tag/v${version}`;
const rawURL = `https://raw.githubusercontent.com/${REPOSITORY}/main`;
const downloadURL = `https://github.com/${REPOSITORY}/releases/download/v${version}/${ipaName}`;
const iconURL = `${rawURL}/BlankGrimoire/Assets.xcassets/AppIcon.appiconset/AppIcon.png`;
const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
const notes =
  process.env.RELEASE_NOTES?.trim() || `Blank Grimoire ${version}. Release notes: ${releaseURL}`;

function readPreviousVersionEntries() {
  if (!existsSync(SOURCE_FILE)) {
    return [];
  }

  try {
    const previous = JSON.parse(readFileSync(SOURCE_FILE, "utf8"));
    const apps = Array.isArray(previous.apps) ? previous.apps : [];
    const app = apps.find((entry) => entry?.bundleIdentifier === bundleIdentifier);
    return Array.isArray(app?.versions) ? app.versions : [];
  } catch (error) {
    console.warn(`warning: existing repo.json is not readable (${error.message})`);
    return [];
  }
}

const versions = [
  {
    version,
    buildVersion,
    date,
    localizedDescription: notes,
    downloadURL,
    size: ipaSize,
    minOSVersion,
  },
  ...readPreviousVersionEntries().filter((entry) => entry?.version !== version),
];

const source = {
  name: "Blank Grimoire",
  identifier: "com.blankgrimoire.source",
  subtitle: "A themeable reader for the content you bring.",
  description:
    "BlankGrimoire is an empty container: no content, no bundled sources. " +
    "Add the sites you already visit and read them through theme adapters.",
  iconURL,
  website: `https://github.com/${REPOSITORY}`,
  tintColor: TINT_COLOR,
  nsfw: false,
  featuredApps: [bundleIdentifier],
  apps: [
    {
      name: "Blank Grimoire",
      bundleIdentifier,
      developerName: "BlankGrimoire contributors",
      subtitle: "Themeable reader",
      localizedDescription:
        "A native, ad-free reader and personal library for the content you bring. " +
        "Requires a site adapter; no content or sources are bundled.",
      iconURL,
      tintColor: TINT_COLOR,
      category: "entertainment",
      screenshots: [],
      versions,
      // AltStore refuses to install an app whose declared permissions differ
      // from the IPA, so these must stay in sync with Info.plist.
      appPermissions: {
        entitlements: [],
        privacy: usageDescriptions(),
      },
      // Legacy fields read by older AltStore clients.
      version,
      versionDate: date,
      versionDescription: notes,
      downloadURL,
      size: ipaSize,
      minOSVersion,
    },
  ],
  news: [],
};

writeFileSync(SOURCE_FILE, `${JSON.stringify(source, null, 2)}\n`);
console.log(
  `repo.json: ${bundleIdentifier} ${version} (${ipaSize} bytes, ${versions.length} versions)`
);
