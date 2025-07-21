# Change Log

All notable changes to this project will be documented in this file. The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

## [3.0.0] - 21-07-2025

### ⚠️ BREAKING CHANGE

- Departments are now mapped using the `shortName` field by default instead of the `id`. This may require updates to your configuration or business rules.

### Added

- Script variable clearing added at the top of scripts to support multiple executions in the same session.
- Logging now includes the filtered count of unarchived assignments by default.
- **Changelog file (`CHANGELOG.md`) added** to document all notable changes going forward.

### Changed

- `Department.ExternalId` now uses `shortName` instead of `id`.
- `Details.HoursPerWeek` changed to a complex mapping to include only if value is greater than 0.
- Formatting improvements for `Name.Convention`.
- Version bumped to `3.0.0`.

### Removed

- Removed `mapping.assignments.json` (duplicate of `mapping.json`).
- Removed unnecessary empty line at the end of script.

## [2.3.0] - 16-04-2025

### Changed

- Fixed typo in mapping.
- Resolved mapping issues as reported in issue #34.

## [2.2.5] - 28-05-2024

### Changed
- Fix for mapping errors.
- Implemented and tested mapping changes proposed in issue #24.

## [2.2.4] - 21-03-2024

### Changed

- Fixed upper OU variables.

## [2.2.3] - 21-03-2024

### Changed

- Fixed lowercase `nameAssembleOrder`.

## [2.2.2] - 15-03-2024

### Changed

- Updated `persons.ps1`.

## [2.2.1] - 22-08-2023

_No changelog provided._

## [2.2.0] - 21-08-2023

### Added

- Added possibility to exclude extensions.
- Flattened person object where necessary.
- Fixed issue where no data was returned.
- Formatting and logging enhancements.
- Improved extension support.

## [2.1.0] - 20-04-2023

### Changed

- Updated to output person object flat (where necessary).

## [2.0.0] - 14-12-2022

### Changed

- Updated to use new endpoints and support extensions.

## [1.1.1] - 19-09-2022

### Changed

- Updated to handle too many request errors.

## [1.1.0] - 24-05-2022

### Changed

- Improved performance and logging.

## [1.0.0] - 18-08-2020

### Added

- Initial release of _HelloID-Conn-Prov-Source-Raet-Beaufort-IAM-API_.
