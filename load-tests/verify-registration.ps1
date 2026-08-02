param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9-]{1,48}$')]
    [string] $RunId,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 10000000)]
    [int] $ExpectedCount,

    [ValidateRange(1, 86400)]
    [int] $TimeoutSeconds = 1800,

    [ValidateRange(1, 300)]
    [int] $PollIntervalSeconds = 5,

    [string] $SqlContainer = 'infra-sqlserver',
    [string] $SaPassword = 'YourStrong!Passw0rd'
)

$ErrorActionPreference = 'Stop'
$deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
$pattern = "load+$RunId-%@example.test"

$query = @"
SET NOCOUNT ON;
DECLARE @Pattern nvarchar(320) = N'$pattern';

SELECT CONCAT(
    (SELECT COUNT_BIG(*) FROM [IAM].[IAM].[AspNetUsers] WHERE [Email] LIKE @Pattern), '|',
    (SELECT COUNT_BIG(*) FROM [IAM].[IAM].[OutboxMessage] WHERE JSON_VALUE([Payload], '$.Email') LIKE @Pattern), '|',
    (SELECT COUNT_BIG(*) FROM [IAM].[IAM].[OutboxMessage] WHERE [DispatchedAt] IS NOT NULL AND JSON_VALUE([Payload], '$.Email') LIKE @Pattern), '|',
    (SELECT COUNT_BIG(*) FROM [Notification].[dbo].[EmailDeliveryLog] WHERE [RecipientEmail] LIKE @Pattern AND [Status] = 'Sent'), '|',
    (SELECT COUNT_BIG(*) FROM [Notification].[dbo].[EmailDeliveryLog] WHERE [RecipientEmail] LIKE @Pattern AND [Status] = 'Failed'), '|',
    (SELECT COUNT_BIG(*)
       FROM [Notification].[dbo].[PushDeliveryLog] AS p
       INNER JOIN [IAM].[IAM].[OutboxMessage] AS o ON o.[EventId] = p.[EventId]
       WHERE p.[Status] = 'Delivered' AND JSON_VALUE(o.[Payload], '$.Email') LIKE @Pattern)
);
"@

do {
    $output = & docker exec $SqlContainer /opt/mssql-tools18/bin/sqlcmd `
        -S localhost -U sa -P $SaPassword -C -h -1 -W -Q $query

    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed with exit code $LASTEXITCODE."
    }

    $line = $output | Where-Object { $_ -match '^\d+\|\d+\|\d+\|\d+\|\d+\|\d+$' } | Select-Object -Last 1
    if (-not $line) {
        throw "Could not parse the verification result from sqlcmd output."
    }

    [long] $users, [long] $outbox, [long] $dispatched, [long] $emailsSent, [long] $emailsFailed, [long] $pushDelivered = $line.Split('|')

    Write-Host ("users={0}/{6} outbox={1}/{6} dispatched={2}/{6} email-sent={3}/{6} email-failed={4} push-delivered={5}/{6}" -f `
        $users, $outbox, $dispatched, $emailsSent, $emailsFailed, $pushDelivered, $ExpectedCount)

    if ($emailsFailed -gt 0) {
        throw "The run contains $emailsFailed failed email deliveries."
    }

    if ($users -eq $ExpectedCount -and
        $outbox -eq $ExpectedCount -and
        $dispatched -eq $ExpectedCount -and
        $emailsSent -eq $ExpectedCount -and
        $pushDelivered -eq $ExpectedCount) {
        Write-Host "End-to-end verification passed for run '$RunId'."
        exit 0
    }

    Start-Sleep -Seconds $PollIntervalSeconds
} while ([DateTimeOffset]::UtcNow -lt $deadline)

Write-Error "Timed out waiting for run '$RunId' to reach $ExpectedCount end-to-end records."
exit 1
