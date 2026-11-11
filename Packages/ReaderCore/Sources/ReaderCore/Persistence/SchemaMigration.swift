// SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftData

/// First versioned schema for the local library.
///
/// Declaring a version is the prerequisite for adding migration stages in the
/// future. Without a `SchemaMigrationPlan`, any non-lightweight change would
/// make `ModelContainer` fail at launch.
public enum BlankGrimoireSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        [
            MangaEntity.self,
            ChapterEntity.self,
            PageEntity.self,
            ReadingProgressEntity.self,
            BookmarkEntity.self,
            SiteProfileEntity.self,
            TrustedRepositoryEntity.self,
            InstalledAdapterEntity.self,
        ]
    }
}

/// Migration plan for the local library.
///
/// There are no stages yet: version 1 is the initial schema. Future schema
/// changes append a new `VersionedSchema` and a `MigrationStage`.
public enum BlankGrimoireMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [BlankGrimoireSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}

/// Shared container factory for the app and its tests.
///
/// Keeping a single schema definition prevents the test store from drifting
/// from the app store and silently skipping entities.
public enum BlankGrimoireSchema {
    public static func makeContainer(
        isStoredInMemoryOnly: Bool = false,
        name: String? = nil
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: BlankGrimoireSchemaV1.self)
        let configuration: ModelConfiguration
        if let name {
            configuration = ModelConfiguration(
                name,
                schema: schema,
                isStoredInMemoryOnly: isStoredInMemoryOnly
            )
        } else {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: isStoredInMemoryOnly
            )
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: BlankGrimoireMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
