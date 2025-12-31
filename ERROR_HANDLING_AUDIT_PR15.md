# Error Handling Audit - PR #15: Import SQL Files Feature

**Date:** 2025-12-31
**Auditor:** Claude Code (Error Handling Specialist)
**Scope:** Import Service, SQL Parser, Decompression Logic, UI Integration

---

## Executive Summary

This audit identified **11 CRITICAL** and **8 HIGH** severity issues related to silent failures, inadequate error handling, and missing user feedback. The import feature lacks proper logging infrastructure and has multiple locations where errors are silently suppressed, which will create severe debugging challenges and poor user experience.

**CRITICAL FINDING:** The codebase lacks the logging infrastructure mentioned in CLAUDE.md (`logError`, `logForDebugging`, error IDs from `constants/errorIds.ts`). This is a foundational gap that affects all error handling.

---

## CRITICAL Issues (Silent Failures)

### 1. SQLFileParser.swift - Lines 207-209: Silent Parse Failure

**Location:** `/Users/ngoquocdat/Workspace/TablePro/TablePro/Core/Utilities/SQLFileParser.swift:207-209`

**Severity:** CRITICAL

**Issue Description:**
The catch block silently finishes the stream without logging or notifying the user when file parsing fails.

```swift
} catch {
    continuation.finish()
}
```

**Hidden Errors:**
This catch block could hide:
- File permission errors (EACCES)
- Disk I/O errors (EIO, ENOENT)
- Memory allocation failures
- File handle creation failures (corrupted file descriptor table)
- Out-of-memory errors during large file parsing
- Encoding errors for malformed UTF-8/UTF-16 sequences
- Interrupted system calls (EINTR)

**User Impact:**
When a file fails to parse due to any of these errors, the user sees:
- Zero statements imported (looks like an empty file)
- No error message explaining what went wrong
- No way to diagnose if the issue is permissions, encoding, corruption, or system resource exhaustion
- Potentially hours wasted trying different files or restarting the app

**Recommendation:**
```swift
} catch {
    // CRITICAL: Never silently finish on parse errors
    print("ERROR: Failed to parse SQL file at \(url.path): \(error.localizedDescription)")
    // TODO: Use proper logging once available: logError("sql_parse_failed", context: ["url": url.path, "error": error])
    continuation.finish()
    // Consider: Should we throw here instead of silently finishing?
    // The caller (ImportService) expects a stream and won't know parsing failed
}
```

**Additional Problem:**
The `parseFile` method signature returns `AsyncStream` which cannot communicate errors. The caller receives a stream that may be empty due to:
1. Empty file (legitimate)
2. Parse error (critical failure - silently hidden)

These two cases are indistinguishable to the caller.

---

### 2. SQLFileParser.swift - Lines 56-59: Silent Encoding Failure

**Location:** `/Users/ngoquocdat/Workspace/TablePro/TablePro/Core/Utilities/SQLFileParser.swift:56-59`

**Severity:** CRITICAL

**Issue Description:**
If the file cannot be decoded with the selected encoding, the parser silently stops processing.

```swift
guard let chunk = String(data: data, encoding: encoding) else {
    continuation.finish()
    return
}
```

**Hidden Errors:**
- Invalid encoding for file content (user selected UTF-8 but file is Latin1)
- Malformed byte sequences
- Binary file accidentally selected as SQL
- Partially corrupted file with invalid byte sequences

**User Impact:**
User sees partial import or zero statements with no explanation. They won't know:
- Which encoding to try
- If the file is corrupted
- At what byte offset the problem occurred
- If only part of the file was processed

**Recommendation:**
```swift
guard let chunk = String(data: data, encoding: encoding) else {
    print("ERROR: Failed to decode file chunk with encoding \(encoding). File may use different encoding or be corrupted.")
    // TODO: logError("sql_file_decode_failed", context: ["encoding": "\(encoding)", "url": url.path])
    continuation.finish()
    return
}
```

---

### 3. ImportService.swift - Lines 86-88: Silent Temp File Cleanup Failure

**Location:** `/Users/ngoquocdat/Workspace/TablePro/TablePro/Core/Services/ImportService.swift:86-88`

**Severity:** HIGH (could become CRITICAL over time)

**Issue Description:**
Decompressed temporary files are cleaned up with `try?`, silently ignoring cleanup failures.

```swift
defer {
    if needsCleanup {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
```

**Hidden Errors:**
- Insufficient permissions to delete temp file
- File still open (file descriptor leak)
- Disk full preventing deletion metadata update
- Temp directory deleted by system cleanup
- Network drive disconnection (if temp directory is network-mounted)

**User Impact:**
Over time, failed cleanups will:
- Fill the temp directory with .sql files
- Consume disk space (potentially gigabytes for large imports)
- No visibility to user that cleanup is failing
- Could eventually cause disk full errors in unrelated operations

**Recommendation:**
```swift
defer {
    if needsCleanup {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            print("WARNING: Failed to clean up temporary file at \(fileURL.path): \(error.localizedDescription)")
            // TODO: logForDebugging("temp_file_cleanup_failed", context: ["path": fileURL.path, "error": error])
            // Non-fatal but should be tracked for disk space monitoring
        }
    }
}
```

---

### 4. ImportService.swift - Lines 207-209: Silent Rollback Failure

**Location:** `/Users/ngoquocdat/Workspace/TablePro/TablePro/Core/Services/ImportService.swift:207-209`

**Severity:** CRITICAL

**Issue Description:**
Transaction rollback failure is silently ignored, potentially leaving database in inconsistent state.

```swift
if config.wrapInTransaction {
    try? await driver.execute(query: "ROLLBACK")
}
```

**Hidden Errors:**
- Connection lost before rollback (transaction left open on server)
- Database crashed during rollback
- Network timeout
- Deadlock during rollback
- Transaction already rolled back by database (error state mismatch)
- Database driver bug causing rollback to fail

**User Impact:**
This is EXTREMELY dangerous because:
- User thinks transaction was rolled back (sees error message)
- Partial changes may be committed if connection drops before rollback
- Database may have open transactions consuming locks
- Subsequent operations may fail with cryptic "already in transaction" errors
- Data corruption if partial statements were committed
- No way for user to know database is in inconsistent state

**Recommendation:**
```swift
if config.wrapInTransaction {
    do {
        try await driver.execute(query: "ROLLBACK")
        print("INFO: Successfully rolled back transaction after import error")
    } catch {
        print("CRITICAL: ROLLBACK FAILED after import error. Database may be in inconsistent state: \(error.localizedDescription)")
        // TODO: logError("import_rollback_failed", context: ["connection": connection.id.uuidString, "error": error])
        // This is critical - user MUST be notified
        // Consider: Should we append to the thrown error message to warn user?
    }
}
```

**Better Approach:**
Create a compound error that includes both the original import failure AND the rollback failure:

```swift
if config.wrapInTransaction {
    do {
        try await driver.execute(query: "ROLLBACK")
    } catch let rollbackError {
        print("CRITICAL: ROLLBACK FAILED: \(rollbackError)")
        // Throw compound error
        throw ImportError.rollbackFailed(
            originalError: error.localizedDescription,
            rollbackError: rollbackError.localizedDescription
        )
    }
}
```

---

### 5. ImportService.swift - Lines 212-217: Silent FK Re-enable Failure

**Location:** `/Users/ngoquocdat/Workspace/TablePro/TablePro/Core/Services/ImportService.swift:212-217`

**Severity:** CRITICAL

**Issue Description:**
Failure to re-enable foreign key checks is silently ignored, leaving database in unexpected state.

```swift
if config.disableForeignKeyChecks {
    let fkEnableStmts = fkEnableStatements(for: connection.type)
    for stmt in fkEnableStmts {
        try? await driver.execute(query: stmt)
    }
}
```

**Hidden Errors:**
- Connection lost before re-enabling FKs
- Insufficient privileges to modify FK settings
- Database crashed
- Session settings lost due to connection pool rotation

**User Impact:**
Foreign keys remain disabled for the session, causing:
- Future inserts bypass FK constraints (data integrity violations)
- User expects FK validation but doesn't get it
- Silent data corruption in subsequent operations
- Confusing behavior where invalid data is accepted
- No warning that database session is in degraded state
- Could affect other operations in the same session

**Recommendation:**
```swift
if config.disableForeignKeyChecks {
    let fkEnableStmts = fkEnableStatements(for: connection.type)
    var fkEnableErrors: [String] = []

    for stmt in fkEnableStmts {
        do {
            try await driver.execute(query: stmt)
        } catch {
            let errorMsg = "Failed to re-enable FK checks: \(error.localizedDescription)"
            print("CRITICAL: \(errorMsg)")
            fkEnableErrors.append(errorMsg)
            // TODO: logError("fk_reenable_failed", context: ["statement": stmt, "error": error])
        }
    }

    if !fkEnableErrors.isEmpty {
        // Append warning to the main error
        throw ImportError.fkReenableFailed(
            originalError: error.localizedDescription,
            fkErrors: fkEnableErrors
        )
    }
}
```

---

### 6. ImportService.swift - Lines 114-118: Silent FK Disable Failure

**Location:** `/Users/ngoquocdat/Workspace/TablePro/TablePro/Core/Services/ImportService.swift:114-118`

**Severity:** HIGH

**Issue Description:**
If disabling FK checks fails, the import proceeds anyway, potentially causing FK violations.

```swift
if config.disableForeignKeyChecks {
    let fkDisableStmts = fkDisableStatements(for: connection.type)
    for stmt in fkDisableStmts {
        _ = try await driver.execute(query: stmt)  // Result discarded
    }
}
```

**Hidden Errors:**
While this code does throw on error (good), it:
- Discards the result without checking if FK disable was successful
- Doesn't log that FK disable was attempted
- Doesn't verify FK state before proceeding

**User Impact:**
- If FK disable silently fails (returns success but doesn't actually disable), import will fail with FK violations
- No visibility into whether FK checks are actually disabled
- Confusing error messages (FK violations when user expected FKs to be disabled)

**Recommendation:**
```swift
if config.disableForeignKeyChecks {
    let fkDisableStmts = fkDisableStatements(for: connection.type)
    print("INFO: Disabling foreign key checks for import")
    for stmt in fkDisableStmts {
        do {
            try await driver.execute(query: stmt)
            print("INFO: Successfully executed: \(stmt)")
        } catch {
            print("ERROR: Failed to disable foreign key checks: \(error.localizedDescription)")
            throw ImportError.foreignKeyDisableFailed(error.localizedDescription)
        }
    }
}
```

---

### 7. ImportDialog.swift - Lines 318-322: Silent Statement Count Failure

**Location:** `/Users/ngoquocdat/Workspace/TablePro/TablePro/Views/Import/ImportDialog.swift:318-322`

**Severity:** HIGH

**Issue Description:**
Statement counting failure is silently ignored, showing count as 0.

```swift
do {
    let parser = SQLFileParser()
    let count = try await parser.countStatements(url: url, encoding: config.encoding)
    statementCount = count
} catch {
    // If counting fails, just don't show count
    statementCount = 0
}
```

**Hidden Errors:**
- File permission errors
- Encoding errors
- File corruption
- Out of memory
- I/O errors

**User Impact:**
- User sees "0 statements" which looks like an empty file
- User may not attempt import thinking file is empty
- No indication that counting failed vs. file is actually empty
- Wastes user time investigating wrong file instead of checking encoding/permissions

**Recommendation:**
```swift
do {
    let parser = SQLFileParser()
    let count = try await parser.countStatements(url: url, encoding: config.encoding)
    statementCount = count
} catch {
    print("WARNING: Failed to count statements: \(error.localizedDescription)")
    // TODO: logForDebugging("statement_count_failed", context: ["url": url.path, "error": error])
    statementCount = -1  // Use -1 to indicate count failed (vs 0 for empty file)
    // Update UI to show "Unable to count statements" instead of "0 statements"
}
```

---

### 8. ImportDialog.swift - Lines 271: Silent File Decompression Failure (No Cleanup)

**Location:** `/Users/ngoquocdat/Workspace/TablePro/TablePro/Views/Import/ImportDialog.swift:280-284`

**Severity:** HIGH

**Issue Description:**
When decompression fails in the preview loading, the error is caught and shown, but there's no cleanup of any partial temp files.

```swift
do {
    urlToRead = try await decompressIfNeeded(url)
} catch {
    filePreview = "Failed to decompress file: \(error.localizedDescription)"
    return
}
```

**Hidden Issue:**
The `decompressIfNeeded` function may create a temp file before failing. If it fails after creating the file but before writing to it, the temp file is orphaned.

**User Impact:**
- Temp directory fills with orphaned files over time
- No visibility to user

**Recommendation:**
Track temp files and ensure cleanup even on failure.

---

### 9. ImportDialog.swift - Line 271: FileHandle Close Failure in Preview

**Location:** `/Users/ngoquocdat/Workspace/TablePro/TablePro/Views/Import/ImportDialog.swift:288-302`

**Severity:** MEDIUM

**Issue Description:**
File handle close failure is silently ignored in preview loading.

```swift
let handle = try FileHandle(forReadingFrom: urlToRead)
defer { try? handle.close() }
```

**Hidden Errors:**
- File descriptor leak if close fails
- Could exhaust file descriptor limit over time

**Recommendation:**
```swift
defer {
    do {
        try handle.close()
    } catch {
        print("WARNING: Failed to close file handle for \(urlToRead.path): \(error)")
    }
}
```

---

### 10. ImportService.swift & ImportDialog.swift: Duplicate Decompression Code

**Location:**
- `/Users/ngoquocdat/Workspace/TablePro/TablePro/Core/Services/ImportService.swift:246-290`
- `/Users/ngoquocdat/Workspace/TablePro/TablePro/Views/Import/ImportDialog.swift:374-415`

**Severity:** HIGH (code duplication, maintenance hazard)

**Issue Description:**
The decompression logic is duplicated between ImportService and ImportDialog. This means:
1. Bug fixes must be applied in two places
2. Error handling improvements must be duplicated
3. High risk of divergence

**Recommendation:**
Extract to a shared utility:
```swift
// Create: TablePro/Core/Utilities/FileDecompressor.swift
final class FileDecompressor {
    static func decompressIfNeeded(_ url: URL) async throws -> (url: URL, needsCleanup: Bool) {
        // Single implementation
    }
}
```

---

### 11. ImportService.swift - Lines 267-269: Decompression Temp File Creation Failure

**Location:** `/Users/ngoquocdat/Workspace/TablePro/TablePro/Core/Services/ImportService.swift:267-269`

**Severity:** CRITICAL

**Issue Description:**
If temp file creation fails, the code throws a generic `decompressFailed` error, losing the specific reason.

```swift
guard fileManager.createFile(atPath: tempURL.path, contents: nil, attributes: nil) else {
    throw ImportError.decompressFailed
}
```

**Hidden Errors:**
- Disk full (ENOSPC)
- Permission denied (EACCES)
- Temp directory doesn't exist
- Path too long
- Filesystem read-only

**User Impact:**
User sees "Failed to decompress .gz file" with no indication of:
- Disk space issue
- Permission problem
- System configuration issue

**Recommendation:**
```swift
guard fileManager.createFile(atPath: tempURL.path, contents: nil, attributes: nil) else {
    // Get more specific error by attempting to write a test file
    let reason: String
    do {
        try "test".write(to: tempURL, atomically: false, encoding: .utf8)
        reason = "Unknown reason (createFile returned false)"
    } catch {
        reason = error.localizedDescription
    }
    throw ImportError.fileReadFailed("Failed to create temporary file for decompression: \(reason)")
}
```

---

## HIGH Severity Issues (Inadequate Error Handling)

### 12. ImportDialog.swift - Lines 300-302: Generic Preview Error Message

**Location:** `/Users/ngoquocdat/Workspace/TablePro/TablePro/Views/Import/ImportDialog.swift:300-302`

**Severity:** HIGH

**Issue Description:**
Preview loading errors provide minimal context.

```swift
} catch {
    filePreview = "Failed to load preview: \(error.localizedDescription)"
}
```

**Missing Context:**
- File path
- Encoding tried
- File size
- Whether error is from decompression or file reading

**User Impact:**
User can't distinguish between:
- Encoding problem (try different encoding)
- Permission problem (check file permissions)
- Corruption problem (file is corrupt)
- Resource problem (out of memory)

**Recommendation:**
```swift
} catch {
    print("ERROR: Failed to load preview for \(urlToRead.path): \(error.localizedDescription)")
    filePreview = "Failed to load preview: \(error.localizedDescription)\n\nFile: \(urlToRead.lastPathComponent)\nEncoding: \(config.encoding)\n\nTry selecting a different encoding if the file uses a different character set."
}
```

---

### 13. ImportDialog.swift - Lines 295-299: Silent Encoding Failure in Preview

**Location:** `/Users/ngoquocdat/Workspace/TablePro/TablePro/Views/Import/ImportDialog.swift:295-299`

**Severity:** HIGH

**Issue Description:**
Preview encoding failure shows generic message without suggesting solution.

```swift
if let preview = String(data: previewData, encoding: config.encoding) {
    filePreview = preview
} else {
    filePreview = "Failed to load preview with selected encoding"
}
```

**User Impact:**
Message doesn't tell user:
- Which encoding was tried
- What encodings are available
- How to fix the issue

**Recommendation:**
```swift
if let preview = String(data: previewData, encoding: config.encoding) {
    filePreview = preview
} else {
    filePreview = """
    Failed to decode file with \(selectedEncoding.rawValue) encoding.

    This usually means the file uses a different character encoding.
    Try selecting a different encoding from the options below:
    • UTF-8 (most common)
    • UTF-16 (Windows files)
    • Latin1 (ISO-8859-1)
    • ASCII (basic English)
    """
    print("WARNING: Failed to decode preview with encoding \(selectedEncoding.rawValue)")
}
```

---

### 14. ImportService.swift - Missing Structured Logging

**Location:** Entire file

**Severity:** HIGH

**Issue Description:**
No structured logging throughout import process. The code lacks:
- Log entry for import start with parameters
- Log entry for each major phase (parse, execute, commit)
- Log entry for successful completion with summary
- Error IDs for Sentry tracking (as mentioned in CLAUDE.md)

**User Impact:**
When debugging import failures:
- No audit trail of import attempts
- Can't correlate errors across sessions
- Can't identify patterns in failures
- No telemetry for monitoring import success rates

**Recommendation:**
Add comprehensive logging:

```swift
func importSQL(from url: URL, config: ImportConfiguration) async throws -> ImportResult {
    print("INFO: Starting SQL import from \(url.path)")
    print("INFO: Configuration - transaction: \(config.wrapInTransaction), disableFK: \(config.disableForeignKeyChecks), encoding: \(config.encoding)")

    // TODO: Add when logging infrastructure available:
    // logEvent("import_started", properties: [
    //     "file_size": fileSize,
    //     "encoding": "\(config.encoding)",
    //     "transaction": config.wrapInTransaction,
    //     "disable_fk": config.disableForeignKeyChecks
    // ])

    defer {
        print("INFO: Import completed/failed - executed: \(executedCount)/\(totalStatements)")
        // TODO: logEvent("import_completed", properties: ["success": error == nil, "statements": executedCount])
    }

    // ... existing code
}
```

---

### 15. ImportDialog.swift - Lines 346-354: Misleading Error When Import Succeeds But Has Failed Statement

**Location:** `/Users/ngoquocdat/Workspace/TablePro/TablePro/Views/Import/ImportDialog.swift:343-354`

**Severity:** MEDIUM

**Issue Description:**
The logic shows error dialog when `result.failedStatement != nil`, but the import may have already thrown an error. This code path seems unreachable.

```swift
if result.failedStatement == nil {
    showSuccessDialog = true
} else {
    let statement = result.failedStatement ?? ""
    let line = result.failedLine ?? 0
    importError = ImportError.importFailed(
        statement: statement,
        line: line,
        error: "Unknown error"  // ← Generic error
    )
    showErrorDialog = true
}
```

**Issue:**
If a statement fails during import (line 184-188 of ImportService.swift), an error is thrown immediately. The function cannot return an `ImportResult` with `failedStatement` set. This code path appears to be dead code.

**Recommendation:**
Either:
1. Remove this dead code, OR
2. Change ImportService to NOT throw on statement failure and instead return partial results

If keeping this code, fix the generic error:
```swift
importError = ImportError.importFailed(
    statement: statement,
    line: line,
    error: "Statement execution failed (error details were not captured)"
)
print("ERROR: Import completed with failed statement at line \(line): \(statement.prefix(100))")
```

---

### 16. ImportService.swift - Line 144: Statement Preview Truncation Without Indicator

**Location:** `/Users/ngoquocdat/Workspace/TablePro/TablePro/Core/Services/ImportService.swift:144`

**Severity:** LOW

**Issue Description:**
Current statement is truncated to 50 characters without ellipsis indicator.

```swift
currentStatement = String(statement.prefix(50))
```

**User Impact:**
User sees partial statement in progress UI with no indication it's truncated. Could be confusing for debugging.

**Recommendation:**
```swift
currentStatement = statement.count > 50
    ? String(statement.prefix(50)) + "..."
    : statement
```

---

### 17. SQLFileParser.swift - Missing Validation of State Machine Invariants

**Location:** `/Users/ngoquocdat/Workspace/TablePro/TablePro/Core/Utilities/SQLFileParser.swift:80-182`

**Severity:** MEDIUM

**Issue Description:**
The state machine doesn't validate invariants or handle unexpected state transitions. If a bug causes an invalid state, parsing will silently produce incorrect results.

**Recommendation:**
Add state validation and defensive checks:

```swift
switch state {
case .normal:
    // ... existing code
default:
    // Should never reach here
    print("ERROR: Unexpected parser state at line \(currentLine): \(state)")
    state = .normal  // Reset to safe state
}
```

---

### 18. ImportDialog.swift - Lines 251-255: Deprecated API Fallback

**Location:** `/Users/ngoquocdat/Workspace/TablePro/TablePro/Views/Import/ImportDialog.swift:251-255`

**Severity:** MEDIUM

**Issue Description:**
File picker silently falls back to deprecated `allowedFileTypes` if `UTType` creation fails.

```swift
if !allowedTypes.isEmpty {
    panel.allowedContentTypes = allowedTypes
} else {
    // Fallback: restrict by file extensions if UTType lookup fails
    panel.allowedFileTypes = ["sql", "gz"]
}
```

**Hidden Issue:**
The comment says "if UTType lookup fails" but `UTType(filenameExtension:)` returns `nil` for unknown extensions, not for system errors. This fallback should never trigger for "sql" and "gz" extensions.

If this fallback triggers, it means:
- System UTType database is corrupted
- iOS/macOS version incompatibility

**Recommendation:**
```swift
if !allowedTypes.isEmpty {
    panel.allowedContentTypes = allowedTypes
} else {
    print("WARNING: Failed to create UTTypes for sql/gz extensions. Falling back to deprecated API.")
    // This should never happen - if it does, log it
    panel.allowedFileTypes = ["sql", "gz"]
}
```

---

### 19. ImportService.swift - Lines 281-286: Lossy Error Message Conversion

**Location:** `/Users/ngoquocdat/Workspace/TablePro/TablePro/Core/Services/ImportService.swift:281-286`

**Severity:** MEDIUM

**Issue Description:**
gunzip stderr is converted to String with fallback to "Unknown error", losing the raw error data.

```swift
let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
throw ImportError.fileReadFailed("Failed to decompress .gz file: \(errorMessage)")
```

**Hidden Issue:**
If stderr contains non-UTF8 data (e.g., binary corruption), error message is lost.

**Recommendation:**
```swift
let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
let errorMessage: String
if let decodedMessage = String(data: errorData, encoding: .utf8) {
    errorMessage = decodedMessage
} else {
    errorMessage = "Unknown error (stderr contained non-UTF8 data: \(errorData.count) bytes)"
    print("ERROR: gunzip stderr is not valid UTF-8: \(errorData.prefix(100).map { String(format: "%02x", $0) }.joined())")
}
throw ImportError.fileReadFailed("Failed to decompress .gz file: \(errorMessage)")
```

---

## Missing Error Types

The `ImportError` enum is missing several error cases that should be added:

```swift
enum ImportError: LocalizedError {
    // ... existing cases

    // Add these:
    case foreignKeyDisableFailed(String)
    case rollbackFailed(originalError: String, rollbackError: String)
    case fkReenableFailed(originalError: String, fkErrors: [String])
    case parseEncodingFailed(encoding: String, url: String)
    case tempFileCleanupFailed(path: String, error: String)

    var errorDescription: String? {
        switch self {
        case .foreignKeyDisableFailed(let details):
            return "Failed to disable foreign key checks: \(details). Import cannot proceed safely."
        case .rollbackFailed(let original, let rollback):
            return "Import failed: \(original)\n\nCRITICAL: Transaction rollback also failed: \(rollback)\nDatabase may be in an inconsistent state. Please verify your data."
        case .fkReenableFailed(let original, let fkErrors):
            return "Import failed: \(original)\n\nWARNING: Failed to re-enable foreign key checks:\n\(fkErrors.joined(separator: "\n"))\nForeign key validation is disabled for this session."
        case .parseEncodingFailed(let encoding, let url):
            return "Failed to decode file '\(url)' using \(encoding) encoding. Try selecting a different encoding."
        case .tempFileCleanupFailed(let path, let error):
            return "Warning: Failed to clean up temporary file at \(path): \(error)"
        // ... etc
        }
    }
}
```

---

## Logging Infrastructure Gap

**CRITICAL FINDING:**
The project's CLAUDE.md document specifies:
- `logForDebugging` for user-facing debug logs
- `logError` for production errors (Sentry)
- `logEvent` for analytics (Statsig)
- Error IDs from `constants/errorIds.ts`

**None of these exist in the codebase.**

Searched for:
- `logError`, `logForDebugging`, `logEvent` - 0 results
- `errorIds.ts`, `errorIds.swift` - 0 results

This means:
- No Sentry integration for error tracking
- No analytics for monitoring import success rates
- No structured logging for debugging
- The PR cannot implement proper error handling per project standards

**Recommendation:**
1. Create the logging infrastructure before merging this PR, OR
2. Add TODO comments everywhere logging should be added, OR
3. Use `print()` statements with clear prefixes (ERROR:, WARNING:, INFO:) as a temporary solution

---

## Positive Findings

Despite the critical issues, the PR does several things well:

1. **Typed Errors**: Uses `ImportError` enum with `LocalizedError` protocol
2. **Error Propagation**: Most errors are propagated correctly (except the silent catches)
3. **Transaction Handling**: Attempts rollback on errors (though silently)
4. **User Feedback**: Shows error dialog with details (when errors aren't silently caught)
5. **Context in Errors**: `ImportError.importFailed` includes statement, line number, and error details

---

## Summary Table

| Issue | Location | Severity | Type |
|-------|----------|----------|------|
| Silent parse failure | SQLFileParser.swift:207-209 | CRITICAL | Silent failure |
| Silent encoding failure | SQLFileParser.swift:56-59 | CRITICAL | Silent failure |
| Silent temp cleanup | ImportService.swift:86-88 | HIGH | Silent failure |
| Silent rollback failure | ImportService.swift:207-209 | CRITICAL | Silent failure |
| Silent FK re-enable failure | ImportService.swift:212-217 | CRITICAL | Silent failure |
| FK disable no verification | ImportService.swift:114-118 | HIGH | Missing verification |
| Silent count failure | ImportDialog.swift:318-322 | HIGH | Silent failure |
| Duplicate decompression | Both files | HIGH | Code duplication |
| Temp file creation error | ImportService.swift:267-269 | CRITICAL | Generic error |
| Preview error message | ImportDialog.swift:300-302 | HIGH | Poor error message |
| Preview encoding error | ImportDialog.swift:295-299 | HIGH | Poor error message |
| Missing structured logging | ImportService.swift | HIGH | Missing infrastructure |
| Misleading error path | ImportDialog.swift:346-354 | MEDIUM | Dead code |
| Statement truncation | ImportService.swift:144 | LOW | UX issue |
| State machine validation | SQLFileParser.swift | MEDIUM | Missing validation |
| Deprecated API fallback | ImportDialog.swift:251-255 | MEDIUM | Silent fallback |
| Lossy error conversion | ImportService.swift:281-286 | MEDIUM | Information loss |
| Missing error types | ImportModels.swift | HIGH | Incomplete types |
| No logging infrastructure | Entire codebase | CRITICAL | Missing foundation |

---

## Recommended Actions Before Merge

### Must Fix (CRITICAL)
1. Remove all empty/silent catch blocks - log errors at minimum
2. Fix silent rollback failure (lines 207-209) - critical data integrity issue
3. Fix silent FK re-enable failure (lines 212-217) - critical data integrity issue
4. Fix silent parse failures in SQLFileParser
5. Fix temp file creation to provide specific error

### Should Fix (HIGH)
6. Add comprehensive logging (or TODOs for logging)
7. Improve error messages for user-facing issues
8. Add FK disable verification
9. Add missing error types to ImportError enum
10. Extract decompression to shared utility

### Nice to Have (MEDIUM/LOW)
11. Add state machine validation
12. Add ellipsis to truncated statements
13. Fix deprecated API fallback logging
14. Improve stderr error handling

---

## Conclusion

This PR introduces critical error handling deficiencies that will create severe debugging challenges and potentially lead to data corruption (failed rollback/FK re-enable). The code **must not** be merged in its current state without addressing the CRITICAL and HIGH severity issues.

The most concerning patterns are:
1. **Silent failures with `try?`** - violates project's explicit "no silent failures" rule
2. **Missing logging infrastructure** - violates project standards in CLAUDE.md
3. **Broad catch blocks** - hide unrelated errors
4. **Generic error messages** - don't help users fix issues

**Priority 1:** Fix all CRITICAL issues (silent rollback, FK re-enable, parse failures)
**Priority 2:** Add logging infrastructure or clear TODOs
**Priority 3:** Improve error messages and user feedback
