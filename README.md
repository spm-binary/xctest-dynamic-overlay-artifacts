# xctest-dynamic-overlay-artifacts

Build-and-release automation for `xctest-dynamic-overlay` XCFramework
artifacts.

Upstream package:
`https://github.com/pointfreeco/xctest-dynamic-overlay`

Artifacts produced by this repository are consumed by:
`https://github.com/spm-binary/xctest-dynamic-overlay.git`

## Release Flow

Run the `Build release` workflow with:

- `upstream_ref`: upstream tag or branch to build, such as `1.9.0`
- `release_tag`: release tag to create in this repository, usually the same
  semantic version

The workflow builds `IssueReportingPackageSupport`, `IssueReporting`,
`IssueReportingTestSupport`, and `XCTestDynamicOverlay` as XCFramework zip
assets and uploads a `checksums.txt` file containing SwiftPM checksums.
