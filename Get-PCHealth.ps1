# Windows PC Health Check
# Collect basic operating-system information and calculate uptime.

try {
    $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
}
catch {
    throw "Cannot collect operating-system information. Report generation stopped. $($_.Exception.Message)"
}
$checkedAt = Get-Date
$uptime = $checkedAt - $operatingSystem.LastBootUpTime

$systemSummary = [PSCustomObject]@{
    ComputerName = $env:COMPUTERNAME
    WindowsEdition = $operatingSystem.Caption
    LastBootTime = $operatingSystem.LastBootUpTime
    Uptime = "{0} days, {1} hours, {2} minutes" -f $uptime.Days,
                                                    $uptime.Hours,
                                                    $uptime.Minutes
    CheckedAt = $checkedAt
}

# Check free space on local fixed disks.
$warningThreshold = 20

try {
    $disks = @(
        Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3" -ErrorAction Stop
    )

    if ($disks.Count -eq 0) {
        throw "No local fixed disks were returned."
    }
}
catch {
    throw "Cannot collect disk information. Report generation stopped. $($_.Exception.Message)"
}

$diskResults = foreach ($disk in $disks) {
    # Report unavailable disk measurements, then continue to the next disk.
    if ($null -eq $disk.Size -or $disk.Size -le 0 -or
    $null -eq $disk.FreeSpace) {

    [PSCustomObject]@{
        Drive = $disk.DeviceID
        SizeGiB = "Unavailable"
        FreeGiB = "Unavailable"
        FreePercent = "Unavailable"
        Status = "Error"
    }

    continue
}

    $freePercent = ($disk.FreeSpace / $disk.Size) * 100

    if ($freePercent -lt $warningThreshold) {
        $status = "Warning"
    }
    else {
        $status = "OK"
    }

    [PSCustomObject]@{
        Drive = $disk.DeviceID
        SizeGiB = [math]::Round($disk.Size / 1GB, 2)
        FreeGiB = [math]::Round($disk.FreeSpace / 1GB, 2)
        FreePercent = [math]::Round($freePercent, 1)
        Status = $status
    }
}

# Check selected services that we expect to be running.
$serviceNames = @("Dnscache", "EventLog")

$serviceResults = foreach ($serviceName in $serviceNames) {
    try {
        $service = Get-Service -Name $serviceName -ErrorAction Stop

        if ($service.Status -eq "Running") {
            $checkStatus = "OK"
        }
        else {
            $checkStatus = "Warning"
        }

        [PSCustomObject]@{
            ServiceName = $service.Name
            DisplayName = $service.DisplayName
            State = $service.Status.ToString()
            Status = $checkStatus
            Details = "Expected state: Running"
        }
    }
    catch {
        [PSCustomObject]@{
            ServiceName = $serviceName
            DisplayName = "Unavailable"
            State = "Unknown"
            Status = "Error"
            Details = $_.Exception.Message
        }
    }
}

# Check DNS resolution, then TCP connectivity.
$targetHost = "example.com"
$targetPort = 443
$dnsSucceeded = $false

$networkResults = @(
    try {
        $dnsRecords = Resolve-DnsName -Name $targetHost -Type A -DnsOnly -ErrorAction Stop

        $addresses = @(
            $dnsRecords |
                Where-Object { $_.Type -eq "A" } |
                Select-Object -ExpandProperty IPAddress -Unique
        )

        if ($addresses.Count -eq 0) {
            throw "No IPv4 addresses were returned."
        }

        $dnsSucceeded = $true

        [PSCustomObject]@{
            Check = "DNS resolution"
            Target = $targetHost
            Status = "OK"
            Details = $addresses -join ", "
        }
    }
    catch {
        [PSCustomObject]@{
            Check = "DNS resolution"
            Target = $targetHost
            Status = "Error"
            Details = $_.Exception.Message
        }
    }

    if ($dnsSucceeded) {
        try {
            $connected = Test-NetConnection -ComputerName $targetHost -Port $targetPort -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction Stop

            if ($connected) {
                $connectionStatus = "OK"
                $connectionDetails = "TCP connection established."
            }
            else {
                $connectionStatus = "Warning"
                $connectionDetails = "TCP connection could not be established."
            }

            [PSCustomObject]@{
                Check = "TCP connectivity"
                Target = "${targetHost}:$targetPort"
                Status = $connectionStatus
                Details = $connectionDetails
            }
        }
        catch {
            [PSCustomObject]@{
                Check = "TCP connectivity"
                Target = "${targetHost}:$targetPort"
                Status = "Error"
                Details = $_.Exception.Message
            }
        }
    }
    else {
        [PSCustomObject]@{
            Check = "TCP connectivity"
            Target = "${targetHost}:$targetPort"
            Status = "Skipped"
            Details = "DNS resolution failed; TCP check was not attempted."
        }
    }
)

# Read the latest Critical and Error events from the System log.
$eventLogName = "System"
$eventStartTime = (Get-Date).AddHours(-24)
$eventLimit = 10
$eventResults = @()

$eventFilter = @{
    LogName = $eventLogName
    Level = 1, 2
    StartTime = $eventStartTime
}

try {
    $eventResults = @(
        Get-WinEvent -FilterHashtable $eventFilter -MaxEvents $eventLimit -ErrorAction Stop |
            Select-Object TimeCreated, Id, ProviderName,
                          LevelDisplayName, Message
    )

    $eventStatus = "Warning"
    $eventDetails = "Retrieved $($eventResults.Count) event(s) for review; limited to the latest $eventLimit."
}
catch {
    if ($_.FullyQualifiedErrorId -like "NoMatchingEventsFound*") {
        $eventStatus = "OK"
        $eventDetails = "No Critical or Error events matched the selected time window."
    }
    else {
        $eventStatus = "Error"
        $eventDetails = "Unable to read events: $($_.Exception.Message)"
    }
}

$eventSummary = [PSCustomObject]@{
    LogName = $eventLogName
    Since = $eventStartTime
    Status = $eventStatus
    Details = $eventDetails
}

# Display the results.
Write-Output "SYSTEM SUMMARY"
$systemSummary | Format-List

Write-Output "DISK SPACE"
$diskResults | Format-Table -AutoSize

Write-Output "WINDOWS SERVICES"
$serviceResults | Format-Table -AutoSize -Wrap

Write-Output "NETWORK CHECKS"
$networkResults | Format-Table -AutoSize -Wrap

Write-Output "SYSTEM EVENT LOG"
$eventSummary | Format-List

if ($eventResults.Count -gt 0) {
    $eventResults |
        Format-List TimeCreated, Id, ProviderName,
                    LevelDisplayName, Message
}

# Build an HTML report from the collected objects.
$reportFolder = Join-Path -Path $PSScriptRoot -ChildPath "reports"
New-Item -ItemType Directory -Path $reportFolder -Force -ErrorAction Stop |
    Out-Null

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss-fff"
$reportPath = Join-Path -Path $reportFolder -ChildPath "HealthCheck-$timestamp.html"

# Convert each group of results into an HTML fragment.
$systemHtml = $systemSummary |
    ConvertTo-Html -Fragment -As List |
    Out-String

$diskHtml = $diskResults |
    ConvertTo-Html -Fragment |
    Out-String

$serviceHtml = $serviceResults |
    ConvertTo-Html -Fragment |
    Out-String

$networkHtml = $networkResults |
    ConvertTo-Html -Fragment |
    Out-String

$eventSummaryHtml = $eventSummary |
    ConvertTo-Html -Fragment -As List |
    Out-String

if ($eventResults.Count -gt 0) {
    $eventDetailsHtml = $eventResults |
        ConvertTo-Html -Fragment -As List |
        Out-String
}
else {
    $eventDetailsHtml = "<p>No event details to display. See the event-log summary above.</p>"
}

# Define the report's appearance.
$reportHead = @'
<title>Windows PC Health Check</title>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
    body {
        font-family: "Segoe UI", Arial, sans-serif;
        margin: 0 auto;
        padding: 32px 20px;
        max-width: 1100px;
        background: #f3f6fa;
        color: #172b4d;
        line-height: 1.5;
    }
    h1 { margin-bottom: 6px; }
    h2 { margin-top: 0; font-size: 21px; }
    section {
        background: white;
        padding: 22px;
        margin-top: 20px;
        border: 1px solid #dce3ec;
        border-radius: 10px;
        overflow-x: auto;
    }
    table {
        border-collapse: collapse;
        width: 100%;
        margin: 12px 0;
    }
    th, td {
        text-align: left;
        padding: 10px;
        border: 1px solid #dce3ec;
        vertical-align: top;
        overflow-wrap: anywhere;
    }
    th { background: #eaf0f8; }
    .note { color: #526174; }
    .ok { color: #166534; background: #dcfce7; font-weight: bold; }
    .warning { color: #854d0e; background: #fef9c3; font-weight: bold; }
    .error { color: #991b1b; background: #fee2e2; font-weight: bold; }
    .skipped { color: #475569; background: #e2e8f0; font-weight: bold; }
</style>
'@

# Assemble the report sections.
$reportBody = @"
<h1>Windows PC Health Check</h1>
<p class="note">A snapshot of selected system checks at the time of execution.</p>

<section>
<h2>System summary</h2>
$systemHtml
</section>

<section>
<h2>Disk space</h2>
<p class="note">Warning when free space is below $warningThreshold%.</p>
$diskHtml
</section>

<section>
<h2>Windows services</h2>
$serviceHtml
</section>

<section>
<h2>Network checks</h2>
<p class="note">TCP connectivity tests port reachability, not website content or certificates.</p>
$networkHtml
</section>

<section>
<h2>System event log</h2>
<p class="note">Historical events require review; they do not automatically indicate a current fault.</p>
$eventSummaryHtml
<h3>Retrieved event details</h3>
$eventDetailsHtml
</section>
"@

$htmlReport = ConvertTo-Html -Title "Windows PC Health Check" -Head $reportHead -Body $reportBody |
    Out-String

# Colour cells containing an exact status value.
$htmlReport = $htmlReport.Replace('<td>OK</td>', '<td class="ok">OK</td>')
$htmlReport = $htmlReport.Replace('<td>Warning</td>', '<td class="warning">Warning</td>')
$htmlReport = $htmlReport.Replace('<td>Error</td>', '<td class="error">Error</td>')
$htmlReport = $htmlReport.Replace('<td>Skipped</td>', '<td class="skipped">Skipped</td>')

# Save the completed report.
$htmlReport | Set-Content -LiteralPath $reportPath -Encoding UTF8 -ErrorAction Stop
Write-Output "Report saved to: $reportPath"