# Changelog
All notable changes to the OATH Tokens module will be documented in this file.

## [0.3.0] - 2025-03-24
### Changed
- Modified permission handling in Graph connections to continue with warnings instead of throwing errors
- Improved module loading with organized dependency management
- Standardized alias creation across all module files for consistency
- Removed redundant code

### Fixed
- Resolved conflict with Convert-Base32 function being loaded twice
- Fixed module import warnings related to alias creation

## [0.2.0] - 2025-03-24
### Changed
- During the check for connection to Graph an error was thrown if scopes not found
- Now warns on missing scopes but doesn't throw error


## [0.1.0] - 2025-03-23
### Added
- Initial release of the OATH Token Management module
