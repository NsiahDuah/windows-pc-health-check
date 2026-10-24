# Windows PC Health Check

A PowerShell tool that collects selected Windows health information
and generates a readable HTML report.

I built this project in a Windows 11 virtual machine to practise
IT support automation, troubleshooting, error handling, and technical
documentation.

## What it checks

| Area | Information collected |
|---|---|
| System | Computer name, Windows edition, last boot time, and uptime |
| Storage | Capacity, free space, and free-space percentage for local fixed disks |
| Services | Status of the DNS Client and Windows Event Log services |
| Network | IPv4 DNS resolution and TCP connectivity to a configured destination |
| Event logs | Up to 10 recent Critical or Error events from the System log |

Results appear in the PowerShell console and in a timestamped HTML
report saved in the `reports` folder beside the script.

## Requirements

- Windows with Windows PowerShell 5.1.
- Access to local system information, services, and the System event log.
- A writable project folder for saving reports.
- Internet access for the default external network checks.
- A browser to view the HTML report.

The project was developed in a Windows 11 Enterprise Evaluation VM
using VMware Workstation and NAT networking. Other Windows versions
have not been verified.

## How to run

Download the project and open Windows PowerShell in its folder.

Run:

```powershell
.\Get-PCHealth.ps1
```

If script execution is disabled, you can allow locally created scripts
for the current PowerShell session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

Then run the script again. The process-scoped setting ends when that
PowerShell session closes. Organisational policies may override it.

Downloaded scripts may also carry an internet-origin marker.
After reviewing and trusting the script, you can remove that marker
from this specific file:

```powershell
Unblock-File -LiteralPath .\Get-PCHealth.ps1
```

Start with a normal PowerShell window. If a check reports access denied,
review the message and the permissions required.

## Open the latest report

```powershell
$latestReport = Get-ChildItem -Path .\reports -Filter "HealthCheck-*.html" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($null -ne $latestReport) {
    Invoke-Item -LiteralPath $latestReport.FullName
}
else {
    Write-Output "No report found. Run Get-PCHealth.ps1 first."
}
```

Reports contain inline styling and can be viewed without an internet
connection once generated.

## Configuration

Edit these settings in the script:

| Setting | Default | Purpose |
|---|---|---|
| `$warningThreshold` | `20` | Warn when free disk space is below this percentage |
| `$serviceNames` | `Dnscache`, `EventLog` | Services expected to be running |
| `$targetHost` | `example.com` | DNS and TCP test destination |
| `$targetPort` | `443` | TCP port to test |
| `$eventLogName` | `System` | Windows event log to inspect |
| `$eventLimit` | `10` | Maximum number of matching events retrieved |

The event search starts 24 hours before the query. Change
`(Get-Date).AddHours(-24)` to adjust that window.

Select monitored services carefully: some Windows services are
designed to remain stopped until needed.

## Understanding results

| Status | Meaning |
|---|---|
| OK | The configured check passed |
| Warning | A condition needs review, such as low disk space, a stopped monitored service, or matching historical events |
| Error | A lookup, query, or measurement failed |
| Skipped | A dependent check was not attempted because its prerequisite failed |

If DNS resolution fails, the TCP check is skipped.

Failure to retrieve essential operating-system or disk information
stops report generation. Individual service, network, and event-log
failures are recorded so other checks can continue.

An unavailable measurement for an individual disk produces an Error
row for that disk.

## Testing

Manual tests included:

- Raising the disk threshold to trigger a warning.
- Looking up a nonexistent service.
- Resolving an invalid hostname.
- Querying a nonexistent event log.
- Querying a nonexistent operating-system CIM class.
- Generating an HTML report with normal settings.

See [the testing record](docs/testing.md) for observed results and
cases not yet verified.

## Limitations

- This is a point-in-time diagnostic tool, not continuous monitoring.
- A successful report does not prove that the entire computer is healthy.
- DNS checking requires an IPv4 A record; IPv6-only destinations are
  not supported by this check.
- The TCP check uses the hostname and may resolve it again. It does
  not test every address returned by the DNS check.
- A successful TCP connection does not validate website content,
  HTTP responses, or TLS certificates.
- Network failures do not identify their root cause automatically.
- Event-log results are capped at 10 by default, not a total count.
- Historical events may describe issues that have already resolved.
- Uptime may span shutdowns when Windows Fast Startup is enabled.
- The script does not automatically repair detected issues.

## Project structure

```text
WindowsHealthCheck/
├── Get-PCHealth.ps1
├── README.md
├── .gitignore
├── docs/
│   └── testing.md
├── examples/
├── screenshots/
└── reports/          # Generated locally; excluded from Git
```

## Sharing reports

Review reports and screenshots before publishing them. They can
contain computer names, network addresses, local paths, and event
messages.

Keep routine reports in the ignored `reports` folder. Place only a
reviewed sample intended for publication in `examples`.

## What I learned

- Querying Windows information with CIM.
- Building structured PowerShell objects.
- Using thresholds to classify results.
- Handling failures with try/catch.
- Distinguishing failed checks from skipped checks.
- Converting collected objects into an HTML report.
- Testing failure paths deliberately and documenting the evidence.

## Sample report and test evidence

Download [the sample HTML report](examples/sample-report.html) and open it in a browser. GitHub displays HTML source rather than rendering this report. The sample comes from the lab run on 24 October 2026; its computer name was replaced with `LAB-WIN11`, and event findings were retained.

Selected screenshots show the tests performed:

- [Disk threshold test](screenshots/Drive-Space.png)
- [Missing service and continued execution](screenshots/Services-Check.png)
- [Successful DNS and TCP checks](screenshots/Network-Check.png)
- [Invalid hostname and skipped TCP check](screenshots/Network-Check%2002.png)
- [Missing event log](screenshots/HealthCheckMissingLog.png)
- [Essential system-query failure](screenshots/final-error.png)