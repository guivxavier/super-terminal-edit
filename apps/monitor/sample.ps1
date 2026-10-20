# Uma linha JSON por amostra (CPU, GPU, RAM, temperatura, processos) para o monitor. Corre neste PC e, por ssh,
# nos outros PCs: o monitor le a saida. Sem nomes de contadores (o Get-Counter muda com a lingua do Windows): CIM.
param([double]$Every = 2, [switch]$Once)
$cores = [Environment]::ProcessorCount
$ramTotal = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
$gpuName = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic|Virtual|Remote|Parsec' } | ForEach-Object Name)[0]
$cpuName = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim() -replace '\s+', ' ' -replace ' \d+-Core Processor', '' -replace '\(R\)|\(TM\)', ''
while ($true) {
    $cpu = (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
    $gpu = try { $g = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop | Where-Object Name -like '*engtype_3D'); [Math]::Min(100, ($g | Measure-Object UtilizationPercentage -Sum).Sum) } catch { $null }
    $os = Get-CimInstance Win32_OperatingSystem
    # temperatura: as zonas termicas do ACPI (sem admin); nem todos os PCs as tem
    $temp = try { $z = @(Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction Stop | Where-Object HighPrecisionTemperature -gt 0); if ($z) { [Math]::Round((($z | Measure-Object HighPrecisionTemperature -Maximum).Maximum / 10) - 273.15) } } catch { $null }
    $procs = @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -Filter "Name<>'_Total' AND Name<>'Idle'" |
        Group-Object { $_.Name -replace '#\d+$' } | ForEach-Object { [pscustomobject]@{ n = $_.Name; c = [Math]::Round(($_.Group | Measure-Object PercentProcessorTime -Sum).Sum / $cores, 1); m = [long](($_.Group | Measure-Object WorkingSetPrivate -Sum).Sum) } } |
        Sort-Object c, m -Descending | Select-Object -First 8)
    # (quem le fechou - monitor / hub terminou, ssh caiu: sai em vez de ficar a correr)
    try { [Console]::Out.WriteLine((@{ host = $env:COMPUTERNAME.ToLower(); cpu = $cpu; gpu = $gpu; temp = $temp; ramUsed = [long]$ramTotal - [long]$os.FreePhysicalMemory * 1024; ramTotal = [long]$ramTotal
                cpuName = $cpuName; gpuName = $gpuName; up = [int]((Get-Date) - $os.LastBootUpTime).TotalHours; procs = $procs } | ConvertTo-Json -Compress -Depth 3))
    [Console]::Out.Flush() } catch { break }
    if ($Once) { break }
    Start-Sleep -Seconds $Every
}
