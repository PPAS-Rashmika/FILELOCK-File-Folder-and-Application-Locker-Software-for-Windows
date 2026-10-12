# FileLock 0.4.1 validation

- Release application/service: zero warnings and errors.
- Core regression groups: 11 passed.
- WPF UI checks: 67 passed, including five actual Explorer window checks and three safe renamed-path rebasing checks.
- Live Windows checks: 88 passed in an isolated temporary SYSTEM service. This includes permanent deletion, an independently moved surviving child, unrelated replacements at old names, authenticated deletion-record removal, exact permission restoration, individual PINs and automatic relocking.
- Windows PowerShell 5.1 compatibility definitions: two passed.
- Setup package/safety checks: 14 passed.

Tests use disposable fixtures. Source and application archives exclude runtime state, personal recovery data and test fixtures. Files are unsigned and require .NET 10 Desktop Runtime x64. See Application/docs/PROTECTION.md for supported Windows locations and active-use limits.