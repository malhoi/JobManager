param (
    $jobsFlowFile,
    $errorLogFile
)

# default Param (for testing)
if (!$jobsFlowFile) {
    $jobsFlowFile = (Join-Path $PSScriptRoot "jobsflow.tsv")
}
if (!$errorLogFile) {
    $errorLogFile = (Join-Path $PSScriptRoot "ERROR.log")
}

# other setting
$scanIntervalSecond = "2"
$LogDir = Join-Path $PSScriptRoot "Log"
$logFile = Join-Path $LogDir "$(Get-Date -Format 'yyyyMMdd_HHmmss')_Jobs.log"

# components
class Log {
    $Date
    $Time
    $Command
    $Message

    Log ($date, $time, $command, $message) {
        $this.Date = $date
        $this.Time = $time
        $this.Command = $command
        $this.Message = $message
    }

    [bool] IsEnd($jobId) {
        if ($this.Message -eq "$($jobId)_END") {
            return $true
        }
        return $false
    }

}

function GetLogs($logFile) {
    $logs = @()
    foreach ($line in (Get-Content $logFile)) {
        $splitedLine = $line.Split("`t")
        $logs += New-Object Log($splitedLine[0], $splitedLine[1], $splitedLine[2], $splitedLine[3])
    }
    return $logs
}

class Job {
    $Id
    $Command
    [array]$PreIds
    $LogFile

    [bool]$IsStart

    Job ($id, $command, [array]$preIds, $logDir) {
        $this.Id = $id
        $this.Command = $command
        $this.PreIds = $preIds
        $this.LogFile = Join-Path $logDir $id
    }

    [bool] IsStandby() {
        if ($this.IsFirst()) {
            return $true
        }

        $endCount = 0
        foreach ($log in GetLogs($this.LogFile)) {
            foreach ($preId in $this.PreIds) {
                if ($log.IsEnd($preId)) {
                    $endCount++
                }
            }
        }
        if ($endCount -eq $this.PreIds.Length) {
            return $true
        }
        return $false
    }

    [bool] IsFirst() {
        if ($null -eq $this.preIds) {
            return $true
        }
        return $false
    }

    [void] Starts() {
        $commands = @(
            "echo %DATE%`t%TIME%"
            "echo %DATE%`t%TIME%`t$($this.Command)`t$($this.id)_START`t>>$($this.logFile)"
            "$($this.Command)"
            "echo %DATE%`t%TIME%"
            "echo %DATE%`t%TIME%`t$($this.Command)`t$($this.id)_END`t>>$($this.logFile)"
            "pause"
        )
        Start-Process -FilePath cmd	-ArgumentList "/c $($commands -join '&')"
        $this.IsStart = $true
    }

}

function IsRunning ($logFile, [array]$jobs) {
    $endCount = 0
    foreach ($log in GetLogs($logFile)) {
        foreach ($job in $jobs) {
            if ($log.IsEnd($job.Id)) {
                $endCount++
            }
        }
    }
    if ($endCount -eq $jobs.Length) {
        return $false
    }
    else {
        return $true
    }

}

class ErrorLog {
    $ErrorLogFile
    $InititalRowsCount

    ErrorLog ($errorLogFile) {
        $this.ErrorLogFile = $errorLogFile
        $this.InititalRowsCount = $this.RowsCount()
    }

    [bool] IsNewWritten() {
        if ($this.InititalRowsCount -ne $this.RowsCount()) {
            return $true
        }
        return $false
    }

    [int] RowsCount() {
        [array]$lines = Get-Content $this.ErrorLogFile
        return $lines.Length
    }

}

# main
function main() {

    if (!(Test-Path $LogDir)) { New-Item $LogDir -ItemType Directory > $null }

    [array]$inputLines = Get-Content $jobsFlowFile
    "LogFile: $logFile"; New-Item $logFile -ItemType File > $null
    
    $errorLog = New-Object ErrorLog($errorLogFile)
    
    $jobs = @()
    foreach ($line in $inputLines) {
        $splitedLine = $line.Split("`t")
        $id = $splitedLine[0]
        $command = $splitedLine[1]
        $preIds = if ($null -eq $splitedLine[2]) { $null }else { $splitedLine[2].Split(",") }
        $jobs += New-Object Job($id, $command, $preIds, $LogDir)
    }
    
    
    while ((IsRunning -logFile $logFile -jobs $jobs)) {
        
        # cheking error log
        if ($errorLog.IsNewWritten()) { "Detected new entries to the error log."; exit }

        # scan temp log files & write to log file
        $logItems = Get-ChildItem $LogDir | ForEach-Object { if ($_.Name -eq $_.BaseName) { $_ } }
        Get-ChildItem $LogDir -Include ($jobs.Id)
        foreach ($logItem in $logItems) {
            if ([bool](Select-String -Path $logItem.FullName -Pattern "end")) {
                Get-Content $logItem.FullName | Out-File $logFile -Encoding default -Append
                Remove-Item $logItem.FullName
            }  
        }

        # completation check and start jobs
        $jobs | ForEach-Object { 
            if (!$_.IsStart -and $_.IsStandby()) {
                $_.Starts(); "$(Get-Date -Format "yyyy/MM/dd HH:mm:ss")`n  ID: $($_.Id)`n  Command: $($_.Command)`n`  PreID: $($_.PreIds -join ",")"
            }
        }

        Start-Sleep -Seconds $scanIntervalSecond
    }

}

main
