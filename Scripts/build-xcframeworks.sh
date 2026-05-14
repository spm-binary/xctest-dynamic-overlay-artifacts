#!/usr/bin/env bash
set -euo pipefail

upstream_ref="${1:?usage: build-xcframeworks.sh <upstream-ref> <release-tag>}"
release_tag="${2:-$upstream_ref}"
upstream_url="${UPSTREAM_URL:-https://github.com/pointfreeco/xctest-dynamic-overlay.git}"

products=(
  IssueReportingPackageSupport
  IssueReporting
  IssueReportingTestSupport
  XCTestDynamicOverlay
)
platforms=(
  "ios|generic/platform=iOS"
  "ios-simulator|generic/platform=iOS Simulator"
  "macos|generic/platform=macOS"
  "tvos|generic/platform=tvOS"
  "tvos-simulator|generic/platform=tvOS Simulator"
  "watchos|generic/platform=watchOS"
  "watchos-simulator|generic/platform=watchOS Simulator"
)

work_dir="${RUNNER_TEMP:-/tmp}/xctest-dynamic-overlay-${release_tag}"
source_dir="${work_dir}/source"
archive_dir="${work_dir}/archives"
derived_data_dir="${work_dir}/DerivedData"
dist_dir="${PWD}/dist"

rm -rf "$work_dir" "$dist_dir"
mkdir -p "$archive_dir" "$dist_dir"

git clone --depth 1 --branch "$upstream_ref" "$upstream_url" "$source_dir"

checksums_file="${dist_dir}/checksums.txt"
: > "$checksums_file"

pushd "$source_dir" >/dev/null

for manifest in Package.swift Package@swift-5.9.swift; do
  if [[ -f "$manifest" ]]; then
    perl -0pi -e 's/\n#if os\(macOS\).*?\n#endif\n?/\n/s' "$manifest"
    perl -0pi -e 's/\.library\(name: "IssueReporting", targets: \["IssueReporting"\]\),/.library(name: "IssueReportingPackageSupport", type: .dynamic, targets: ["IssueReportingPackageSupport"]),\n    .library(name: "IssueReporting", type: .dynamic, targets: ["IssueReporting"]),/g' "$manifest"
    perl -0pi -e 's/\.library\(name: "XCTestDynamicOverlay", targets: \["XCTestDynamicOverlay"\]\),/.library(name: "XCTestDynamicOverlay", type: .dynamic, targets: ["XCTestDynamicOverlay"]),/g' "$manifest"
  fi
done

for product in "${products[@]}"; do
  frameworks=()

  for platform in "${platforms[@]}"; do
    IFS="|" read -r slug destination <<< "$platform"
    archive_path="${archive_dir}/${product}-${slug}.xcarchive"

    xcodebuild archive \
      -scheme "$product" \
      -destination "$destination" \
      -archivePath "$archive_path" \
      -derivedDataPath "$derived_data_dir" \
      SKIP_INSTALL=NO \
      BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
      OTHER_SWIFT_FLAGS="-no-verify-emitted-module-interface" \
      ONLY_ACTIVE_ARCH=NO

    framework_path="$(find "${derived_data_dir}/Build/Intermediates.noindex/ArchiveIntermediates/${product}/BuildProductsPath" -type d -path "*/PackageFrameworks/${product}.framework" -print -quit)"
    if [[ -z "$framework_path" ]]; then
      framework_path="$(find "${archive_path}/Products" -type d -name "${product}.framework" -print -quit)"
    fi
    if [[ -z "$framework_path" ]]; then
      echo "error: ${product}.framework not found in ${archive_path}" >&2
      find "$derived_data_dir" -maxdepth 8 -name "${product}.framework" -print >&2
      find "$archive_path" -maxdepth 5 -print >&2
      exit 1
    fi

    module_path="$(find "${derived_data_dir}/Build/Intermediates.noindex/ArchiveIntermediates/${product}/BuildProductsPath" -type d -name "${product}.swiftmodule" -print -quit)"
    if [[ -z "$module_path" ]]; then
      echo "error: ${product}.swiftmodule not found for ${archive_path}" >&2
      find "$derived_data_dir" -maxdepth 8 -name "${product}.swiftmodule" -print >&2
      exit 1
    fi

    slice_dir="${work_dir}/slices/${product}-${slug}"
    framework_copy="${slice_dir}/${product}.framework"
    rm -rf "$slice_dir"
    mkdir -p "$slice_dir"
    ditto "$framework_path" "$framework_copy"

    if [[ -d "${framework_copy}/Versions/A" ]]; then
      modules_root="${framework_copy}/Versions/A/Modules"
      mkdir -p "$modules_root"
      ditto "$module_path" "${modules_root}/${product}.swiftmodule"
      if [[ ! -e "${framework_copy}/Modules" ]]; then
        ln -s "Versions/Current/Modules" "${framework_copy}/Modules"
      fi
    else
      modules_root="${framework_copy}/Modules"
      mkdir -p "$modules_root"
      ditto "$module_path" "${modules_root}/${product}.swiftmodule"
    fi

    codesign --force --sign - "$framework_copy"
    frameworks+=("-framework" "$framework_copy")
  done

  xcframework_path="${dist_dir}/${product}.xcframework"
  zip_path="${dist_dir}/${product}.xcframework.zip"

  xcodebuild -create-xcframework "${frameworks[@]}" -output "$xcframework_path"
  ditto -c -k --sequesterRsrc --keepParent "$xcframework_path" "$zip_path"
  rm -rf "$xcframework_path"

  checksum="$(swift package compute-checksum "$zip_path")"
  printf "%s  %s\n" "$checksum" "$(basename "$zip_path")" >> "$checksums_file"
done

popd >/dev/null
