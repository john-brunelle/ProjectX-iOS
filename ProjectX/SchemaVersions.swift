import Foundation
import SwiftData

// ─────────────────────────────────────────────
// Schema Versioning & Migration Plan
//
// Tracks SwiftData model versions so that
// schema changes migrate data in place rather
// than wiping the store.
//
// When adding new fields to any @Model class:
//  1. Copy the current schema enum as a new version
//  2. Update the model classes in the new version
//  3. Add a migration stage to ProjectXMigrationPlan
//  4. Update `schemas` and `stages` arrays
// ─────────────────────────────────────────────

// MARK: - V1 (baseline — current schema snapshot)

enum ProjectXSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] = [
        IndicatorConfig.self,
        BotConfig.self,
        BotLogEntryRecord.self,
        AccountProfile.self,
        AccountBotAssignment.self,
        BotRunRecord.self,
        NetworkLogRecord.self
    ]
}

// MARK: - Migration Plan

enum ProjectXMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [
        ProjectXSchemaV1.self
    ]

    static var stages: [MigrationStage] = [
        // Future migrations go here, e.g.:
        // .lightweight(fromVersion: ProjectXSchemaV1.self, toVersion: ProjectXSchemaV2.self)
    ]
}
