#!/bin/sh

# Xcode Cloud post-clone script
# Allows SPM package plugins (SwiftLint in CodeEditSourceEditor) to run without
# the -skipPackagePluginValidation flag that Xcode Cloud doesn't pass by default.

defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
