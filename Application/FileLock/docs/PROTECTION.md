# Protection boundaries

FileLock changes NTFS security at the original location; content is not moved or encrypted. A SYSTEM Windows service saves each object's original owner, group, permission ACL, audit ACL and stable identity before changing it.

Locked items are owned by SYSTEM. Only SYSTEM has full access, while the item's Windows user can inspect metadata. Administrators do not receive a full-control grant. This blocks Explorer's routine **Continue** operation from granting permanent access without a passcode. [Microsoft describes Continue's permission changes](https://learn.microsoft.com/en-us/troubleshoot/windows-server/windows-security/dont-have-permission-access-folder).

The upgraded service relocks existing registered items when it starts, retaining the original permission journals. If a protected root or descendant has been replaced or an unjournaled object appeared while the recorded state was locked, the service refuses that identity change and reports a protection error. Review that item instead of assuming migration succeeded.

## Passcodes and active use

Each management-window opening requires a fresh master passcode. Adding or changing a protected location requires an explicit shared/individual selection; a separate passcode must contain six digits with matching confirmation. The master passcode cannot approve an individual location's normal opening. A previously saved shared location stays shared until its owner changes that setting.

Every opening mediated by FileLock, including the original folder's default Explorer action, requires the location passcode even if the location is already open. Approval restores the original Windows permissions and creates a short access session. Its token is tied to the account and Windows session, returned only by PIN approval, and rotated on another approved opening. An old token cannot close or renew a newer use. Closing the management window or signing out of settings does not authenticate another management opening and does not close an independently active document.

The desktop agent renews access while it can observe a supported use. Closing the last observed folder/viewer window normally requires a two-second settling period before relocking; a confirmed application process exit closes access on the next check. A location stays open while another observed use remains. If the agent exits or cannot observe use, the SYSTEM service closes access after its 15-second heartbeat deadline, checked once a second. **Lock now** ends access immediately. Service restart closes outstanding access sessions. If the service itself stops while an item is open, restored permissions can remain until it restarts.

Every account and process allowed by the original Windows permissions can access the location while an approved use is active. This includes an ordinary program reading a file without going through FileLock's prompt. Intercepting every generic file read and requiring a PIN each time would need a filesystem driver or an encryption-based design; this version provides neither. The files stay in plaintext at their original paths.

Already-open file handles, mapped files and running applications can retain access. Close them before locking. Protecting an executable does not stop an already-running application or another copy.

## Save and replacement behavior

Some editors save a document by replacing the file at its original name. During an approved open session, FileLock can journal and relock a replacement protected file/executable owned by the same Windows account on the same verified volume. The replacement's own permissions are saved before locking it. Folder descendants created or replaced during approved use are also journaled before relocking.

A replaced protected root folder, a replacement on a different volume, or a file replacement detected while locked is rejected. FileLock does not apply the old object's saved permissions to an unrelated replacement. Remove protection before moving a protected location to another volume.

## Renamed, moved and missing locations

Version 0.4.1 can recover a renamed or moved root on its original NTFS volume using the saved volume and file identity. It verifies the current canonical path, its ancestors and the protected tree before repairing the stored path and relocking. The original permission journal and shared or individual passcode remain intact. Recovery closes the old access session; opening the repaired location requires its passcode again.

An authenticated owner can choose **Manage → Repair moved location** to retry discovery. If FileLock cannot discover the path automatically, the owner can select the same item at its current location. A similarly named folder, an unrelated replacement or a copy on another volume cannot replace the saved identity.

A missing path alone does not prove deletion: the item may have moved, its drive may be unavailable, or a descendant may survive elsewhere. For an item you deleted or moved to the Recycle Bin, choose **Manage → Remove protection** after installing 0.4.1 or newer. FileLock verifies that the original NTFS volume is mounted with the saved identity, checks every journaled object by its saved file identity, and restores saved permissions on any surviving originals before removing the record. This includes surviving objects in the Recycle Bin; remaining content is kept. Automatic path recovery does not adopt a Recycle Bin location as a new protected path.

An invalid-parameter result for an old NTFS file ID is not deletion proof by itself. Removal confirms its absence with complete [NTFS metadata enumeration](https://learn.microsoft.com/en-us/windows/win32/api/winioctl/ni-winioctl-fsctl_enum_usn_data). This reads identities, not file contents. Unavailable drives, pending deletion, unsupported metadata or incomplete enumeration retain the recovery record.

If the volume is unavailable, identity verification fails, or any saved permissions cannot be restored, FileLock retains the recovery record and original permission journal for retry. Repair and record cleanup do not delete content. Return the drive or resolve the reported restoration issue before retrying removal.

## Windows integration

The background prompt agent handles the original folder's default Explorer action. It uses `HKCU\Software\Classes\Directory\shell\FileLock.Open`, saving and restoring the previous default. Unprotected folders are forwarded through Windows' explicit `explore` action. Prompt agents are isolated by Windows user and session.

Version 0.4.2 adds the explicit **Unlock & open with FileLock** file command at `HKCU\Software\Classes\*\shell\FileLock.Open`. On Windows 11 it may appear under **Show more options**. It preserves the existing file associations and default file verb. Only FileLock-owned command entries are changed or removed; disabling the command persists across agent restarts. Files and executables, including files inside a protected folder, can be opened with this command after their location passcode is approved.

Windows [4656 access events](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4656) report a requested handle, including denied background reads. They do not establish that the user chose to open the item. From 0.4.2 onward these audits are diagnostic only and never create a PIN prompt. The desktop also discards legacy broker challenges, so an old audit backlog cannot reappear after cancellation. No time-based cooldown can re-enable unsolicited prompts.

Ordinary file double-clicks, other programs and Explorer navigation routes can show Windows access denied while a location is locked. Use FileLock's **Unlock & open**, its explicit file command, or the protected folder's default action to enter the passcode. Cancel does not create a new access grant or open another view. The background agent must be running to observe an approved use; locked permissions remain applied when the desktop is closed.

Folder closure observation uses ordinary Explorer views at the protected root or below it. File closure observation uses a newly opened or changed viewer-window caption that identifies the filename, or a sufficiently distinctive filename stem. This is not a universal document/tab close API: hidden tabs, unchanged existing viewer captions, same-named documents, and viewers that omit filenames can be ambiguous. If no supported use can be identified, the launch grace ends after 10 seconds and the location relocks. FileLock can relock while an already-open viewer still holds a usable file handle. Application monitoring follows the launched process; launcher handoffs and applications without an observable window may not keep the session active.

## Supported locations

Use personal content on local fixed NTFS drives. Windows, Program Files, AppData/profile roots, FileLock state/installation, network/removable drives, reparse points, cloud placeholders, junctions, symlinks, hardlinked files and overlapping protected locations are rejected. A folder supports up to 10,000 entries.

Windows can authorize root renaming or deletion through the parent's permissions. FileLock leaves those parent permissions intact. It verifies stable file/volume identity and can recover same-volume root moves, while refusing to restore saved permissions onto an unrelated replacement. Remove protection before moving an item to another volume.

## Administrator and recovery access

A Windows administrator can deliberately take ownership, enable backup/restore privileges, replace the broker or inspect its state. SYSTEM and offline disk access remain outside this access-control boundary. Six-digit passcodes have a limited search space; online throttling does not provide protection from an administrator who controls the machine.

Recovery uses the saved recovery key and rotates it after use. Save the replacement. Removing protection restores the saved security descriptors; deleting service files or ProgramData state can destroy this recovery path. The uninstaller refuses while any account still has protected items and preserves account/recovery data for reinstall.

Back up important content. Use FileLock's removal and recovery features instead of deleting its service, journals or state manually.
