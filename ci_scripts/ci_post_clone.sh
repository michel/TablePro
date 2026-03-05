#!/bin/sh

# Xcode Cloud post-clone script

# Create empty Secrets.xcconfig (gitignored, not available in CI)
touch "$CI_PRIMARY_REPOSITORY_PATH/Secrets.xcconfig"

# Allow SPM package plugins (SwiftLint in CodeEditSourceEditor) to run
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
