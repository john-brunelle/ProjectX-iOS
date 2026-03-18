# ProjectX-iOS — Claude Notes

## SwiftData Schema Migrations (CRITICAL)
When modifying any `@Model` class (adding, removing, or renaming properties), you MUST:
1. Create a new `VersionedSchema` in `ProjectX/SchemaVersions.swift` (e.g. `ProjectXSchemaV2`)
2. Add a `.lightweight(fromVersion:toVersion:)` stage to `ProjectXMigrationPlan.stages`
3. Update the `schemas` array to include the new version
4. Update `ProjectXApp.swift` to reference the new schema's `.models`

Never modify `@Model` properties without a corresponding migration. Failing to do this will wipe the user's local database (bots, indicators, logs, etc.).

## Rate Limits (Server-Enforced)
- Bars Feed: 50 requests / 30 seconds
- All Other Endpoints: 200 requests / 60 seconds
- Client-side `RateLimiter` governor is in place (toggle in Preferences)

## Risk Guards (Per Account)
- Max open positions and max daily loss are scoped per `accountId`, not global

## Developer Mode
- Hidden behind tapping the app version 5 times in Preferences > About
- Gates visibility of debug-only indicators (e.g. Timer Signal)
