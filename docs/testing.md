# Testing record

## Environment

- Windows 11 Enterprise Evaluation VM
- VMware Workstation
- Workgroup configuration with NAT networking
- Windows PowerShell

## Manual tests

| Test | Method | Observed result |
|---|---|---|
| Normal disk check | Set free-space threshold to 20% | Drive with 64.7% free reported OK |
| Disk warning | Temporarily raised threshold to 100% | Same drive reported Warning |
| Missing service | Added HealthCheckFakeService between two valid services | Error recorded; subsequent service still checked |
| Successful network checks | Used example.com on port 443 | DNS and TCP checks reported OK |
| DNS failure | Used healthcheck.invalid | DNS reported Error; TCP check reported Skipped |
| System event retrieval | Queried Critical and Error events from the last 24 hours | Retrieved the latest 10 matching events; summary reported Warning |
| Missing event log | Queried HealthCheckMissingLog | Error recorded without displaying previous event results |
| Operating-system query failure | Used a nonexistent CIM class | Clear error displayed; script stopped |
| HTML generation | Ran the script with normal settings | Report created with all five sections |

## Findings

The System log contained TPM-WMI event 1040 and BitLocker-Driver
event 24641. These were recorded as findings requiring investigation.
Their root causes have not been established.

## Tests not yet verified

- Event query with no matching events.
- Failed disk query or unavailable disk measurements.
- Stopped monitored service.
- Successful DNS resolution followed by a failed TCP connection.

## Scope

These are manual lab tests, not an automated test suite.
Successful checks do not establish that the entire computer is healthy.
The event list is capped at 10 records and is not a total event count.
