param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'
$appDirectory = $PSScriptRoot
if (!$appDirectory) { $appDirectory = [AppDomain]::CurrentDomain.BaseDirectory }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Find-Adb {
    $local = Join-Path $appDirectory 'platform-tools\adb.exe'
    if (Test-Path -LiteralPath $local) { return $local }
    $cmd = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    if (Test-Path -LiteralPath $sdk) { return $sdk }
    return ''
}
function Start-Adb([string]$Arguments) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $adbBox.Text
    $info.Arguments = $Arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $info
    [void]$p.Start()
    return @{ Process = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync() }
}
function Read-Devices {
    if (!(Test-Path -LiteralPath $adbBox.Text -PathType Leaf)) { throw '请先选择有效的 adb.exe。' }
    $job = Start-Adb 'devices -l'
    try {
        if (!$job.Process.WaitForExit(8000)) { $job.Process.Kill(); throw '检测设备超时，请检查 USB 连接后重试。' }
        $raw = $job.Out.Result + $job.Err.Result
        if ($job.Process.ExitCode -ne 0) { throw $raw }
        Write-Log $raw.Trim()
        $deviceBox.Items.Clear()
        foreach ($line in ($raw -split "`r?`n")) {
            if ($line -match '^(\S+)\s+device(?:\s|$)') { [void]$deviceBox.Items.Add($Matches[1]) }
        }
        if ($deviceBox.Items.Count -gt 0) {
            $deviceBox.SelectedIndex = 0
            $status.Text = '设备已连接，请核对序列号后开始安装。'
        } elseif ($raw -match 'unauthorized') {
            $status.Text = '设备未授权：请戴上 Quest，允许此电脑进行 USB 调试。'
        } else { $status.Text = '未发现在线设备：请连接 USB，开启开发者模式并允许 USB 调试。' }
    } finally { $job.Process.Dispose() }
}
function Write-Log([string]$Text) {
    $log.AppendText(('[' + (Get-Date -Format 'HH:mm:ss') + '] ' + $Text + "`r`n"))
    $log.SelectionStart = $log.TextLength
    $log.ScrollToCaret()
}
function Set-Busy([bool]$Busy) {
    $script:busy = $Busy
    foreach ($control in @($folderButton,$adbButton,$refreshButton,$startButton,$demoButton,$retryButton,$deviceBox)) { $control.Enabled = !$Busy }
    $stopButton.Enabled = $Busy
}
function Add-Row([string]$Name,[string]$Size,[string]$Path) {
    $row = New-Object System.Windows.Forms.ListViewItem($Name)
    [void]$row.SubItems.Add($Size)
    [void]$row.SubItems.Add('等待安装')
    $row.Tag = $Path
    [void]$list.Items.Add($row)
}
function Begin-Queue([bool]$Demo,[bool]$Retry) {
    if (!$Demo) {
        if ($script:demo) { throw '当前是演示列表，请先选择真实 APK 文件夹。' }
        if ($deviceBox.SelectedIndex -lt 0) { throw '请先连接设备并点击“刷新设备”。' }
        if (!(Test-Path -LiteralPath $adbBox.Text -PathType Leaf)) { throw '请先选择 adb.exe。' }
    }
    $script:queue = @($list.Items | Where-Object { !$Retry -or $_.SubItems[2].Text -eq '失败' -or $_.SubItems[2].Text -eq '未执行' })
    if ($script:queue.Count -eq 0) { throw '没有可安装的 APK，请选择文件夹，或检查失败列表。' }
    foreach ($row in $script:queue) { $row.SubItems[2].Text = '等待安装'; $row.ForeColor = [Drawing.Color]::FromArgb(35,45,60) }
    $script:demo = $Demo
    $script:index = 0
    $script:success = 0
    $script:failed = 0
    $script:stopping = $false
    $script:activeJob = $null
    $script:serial = [string]$deviceBox.SelectedItem
    $progress.Maximum = $script:queue.Count
    $progress.Value = 0
    Set-Busy $true
    Write-Log $(if ($Demo) { '开始演示：所有安装结果均为模拟，不会向设备写入数据。' } else { "开始安装 $($script:queue.Count) 个 APK，目标设备：$script:serial" })
    $timer.Start()
}
function Finish-Queue {
    $timer.Stop()
    if ($script:stopping) {
        for ($n=$script:index; $n -lt $script:queue.Count; $n++) { $script:queue[$n].SubItems[2].Text = '未执行' }
    }
    $prefix = if ($script:demo) { '演示结束（模拟数据）' } elseif ($script:stopping) { '队列已停止' } else { '安装完成' }
    $status.Text = "$prefix  |  成功 $script:success  ·  失败 $script:failed  ·  已处理 $script:index / $($script:queue.Count)"
    Write-Log $status.Text
    Set-Busy $false
}
function Queue-Tick {
    if ($script:activeJob) {
        if (!$script:activeJob.Process.HasExited) { return }
        $detail = ($script:activeJob.Out.Result + $script:activeJob.Err.Result).Trim()
        $ok = $script:activeJob.Process.ExitCode -eq 0 -and $detail -match '(?m)^Success\s*$'
        $script:activeJob.Process.Dispose()
        $script:activeJob = $null
        Complete-Row $ok $detail
    } elseif ($script:demo -and $script:demoWaiting) {
        $script:demoWaiting = $false
        $ok = $script:index -ne 2
        Complete-Row $ok $(if ($ok) { '[模拟] Success' } else { '[模拟] INSTALL_FAILED_INSUFFICIENT_STORAGE：空间不足，展示失败效果。' })
    }
    if ($script:stopping -or $script:index -ge $script:queue.Count) { Finish-Queue; return }
    $row = $script:queue[$script:index]
    $row.SubItems[2].Text = $(if ($script:demo) { '模拟安装中…' } else { '安装中…' })
    $row.EnsureVisible()
    $status.Text = "$(if ($script:demo) { '[演示] ' })正在处理 $($script:index + 1) / $($script:queue.Count)：$($row.Text)"
    if ($script:demo) { $script:demoWaiting = $true; return }
    try {
        if (!(Test-Path -LiteralPath $row.Tag -PathType Leaf)) { throw 'APK 文件不存在。' }
        $script:activeJob = Start-Adb ('-s "' + $script:serial + '" install -r "' + $row.Tag + '"')
        Write-Log ('正在安装：' + $row.Tag)
    } catch { Complete-Row $false $_.Exception.Message }
}
function Complete-Row([bool]$Ok,[string]$Detail) {
    $row = $script:queue[$script:index]
    $row.SubItems[2].Text = if ($Ok) { '成功' } else { '失败' }
    $row.ForeColor = if ($Ok) { [Drawing.Color]::FromArgb(15,125,85) } else { [Drawing.Color]::FromArgb(190,60,60) }
    if ($Ok) { $script:success++ } else { $script:failed++ }
    Write-Log ($row.Text + '：' + $Detail)
    if (!$script:demo -and $Detail -match '(?i)device.*(not found|offline)|no devices|unauthorized|device disconnected') {
        $script:stopping = $true
        Write-Log '设备连接异常，停止后续安装。重新连接后可点击“重试失败/未执行”。'
    }
    $script:index++
    $progress.Value = $script:index
}
function Protect([scriptblock]$Action) {
    try { & $Action } catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Quest APK Installer'); Write-Log $_.Exception.Message }
}
function Label([string]$Text,[int]$X,[int]$Y,[int]$Width) {
    $c = New-Object Windows.Forms.Label
    $c.Text=$Text; $c.SetBounds($X,$Y,$Width,26); $form.Controls.Add($c)
    return $c
}
function Button([string]$Text,[int]$X,[int]$Y,[int]$Width) {
    $c = New-Object Windows.Forms.Button
    $c.Text=$Text; $c.SetBounds($X,$Y,$Width,34); $c.FlatStyle='Flat'; $c.BackColor=[Drawing.Color]::White
    $form.Controls.Add($c); return $c
}
function TextBox([int]$X,[int]$Y,[int]$Width) {
    $c=New-Object Windows.Forms.TextBox
    $c.SetBounds($X,$Y,$Width,30); $c.ReadOnly=$true; $c.BackColor=[Drawing.Color]::White
    $form.Controls.Add($c); return $c
}
$form=New-Object Windows.Forms.Form
$form.Text='Quest APK Installer · 批量安装'
$form.ClientSize=New-Object Drawing.Size(1000,790)
$form.StartPosition='CenterScreen'; $form.FormBorderStyle='FixedSingle'; $form.MaximizeBox=$false
$form.AutoScaleMode='Dpi'; $form.Font=New-Object Drawing.Font('Microsoft YaHei UI',10)
$form.BackColor=[Drawing.Color]::FromArgb(245,247,251)
$title=Label 'Quest APK Installer' 28 20 700
$title.Font=New-Object Drawing.Font('Segoe UI',21,[Drawing.FontStyle]::Bold); $title.Height=42
$subtitle=Label '选择文件夹，一次排队安装。适用于独立 APK，通过 USB / ADB 连接。' 30 68 940
$subtitle.ForeColor=[Drawing.Color]::SlateGray
$null=Label 'ADB 工具' 30 112 100
$adbBox=TextBox 135 108 685
$adbBox.Text=Find-Adb
$adbButton=Button '选择 ADB' 835 105 135
$null=Label '目标设备' 30 157 100
$deviceBox=New-Object Windows.Forms.ComboBox
$deviceBox.SetBounds(135,153,685,30); $deviceBox.DropDownStyle='DropDownList'; $form.Controls.Add($deviceBox)
$refreshButton=Button '刷新设备' 835 150 135
$null=Label 'APK 文件夹' 30 202 100
$folderBox=TextBox 135 198 685
$folderBox.Text='尚未选择文件夹（只扫描当前目录，不包含子目录）'
$folderButton=Button '选择文件夹' 835 195 135
$list=New-Object Windows.Forms.ListView
$list.SetBounds(30,247,940,245); $list.View='Details'; $list.FullRowSelect=$true; $list.GridLines=$false
$list.HeaderStyle='Nonclickable'; $list.HideSelection=$false
[void]$list.Columns.Add('安装包',620); [void]$list.Columns.Add('大小',125); [void]$list.Columns.Add('状态',160)
$form.Controls.Add($list)
$startButton=Button '开始安装' 30 509 145
$startButton.BackColor=[Drawing.Color]::FromArgb(49,92,220); $startButton.ForeColor=[Drawing.Color]::White
$retryButton=Button '重试失败/未执行' 188 509 180
$stopButton=Button '完成当前后停止' 381 509 180
$stopButton.Enabled=$false
$demoButton=Button '预览演示' 670 509 140
$exportButton=Button '导出日志' 823 509 147
$progress=New-Object Windows.Forms.ProgressBar
$progress.SetBounds(30,558,940,9); $form.Controls.Add($progress)
$status=Label '连接 Quest 并允许 USB 调试，或点击“预览演示”查看模拟效果。' 30 580 940
$status.Height=30
$log=New-Object Windows.Forms.TextBox
$log.SetBounds(30,618,940,118); $log.Multiline=$true; $log.ReadOnly=$true; $log.ScrollBars='Vertical'
$log.BackColor=[Drawing.Color]::FromArgb(233,237,244); $log.BorderStyle='None'; $form.Controls.Add($log)
$footer=Label '覆盖安装使用 -r 保留应用数据；签名冲突或版本不兼容会记为失败。' 30 751 940
$footer.ForeColor=[Drawing.Color]::SlateGray
$timer=New-Object Windows.Forms.Timer
$timer.Interval=600
$script:demo=$false; $script:busy=$false; $script:demoWaiting=$false; $script:activeJob=$null
$timer.Add_Tick({ try { Queue-Tick } catch { $timer.Stop(); Write-Log ('运行异常：'+$_.Exception.Message); Set-Busy $false } })
$adbButton.Add_Click({ Protect {
    $d=New-Object Windows.Forms.OpenFileDialog; $d.Filter='ADB 程序 (adb.exe)|adb.exe'
    if ($d.ShowDialog() -eq 'OK') { $adbBox.Text=$d.FileName; $deviceBox.Items.Clear(); Read-Devices }; $d.Dispose()
} })
$refreshButton.Add_Click({ Protect { Read-Devices } })
$folderButton.Add_Click({ Protect {
    $d=New-Object Windows.Forms.FolderBrowserDialog; $d.Description='选择存放独立 APK 的文件夹'
    if ($d.ShowDialog() -eq 'OK') {
        $files=@(Get-ChildItem -LiteralPath $d.SelectedPath -Filter '*.apk' -File | Sort-Object Name)
        $list.Items.Clear(); $script:demo=$false; $script:demoWaiting=$false
        $folderBox.Text=$d.SelectedPath
        foreach ($file in $files) { Add-Row $file.Name ('{0:N1} MB' -f ($file.Length/1MB)) $file.FullName }
        $status.Text="已找到 $($files.Count) 个 APK。请核对目标设备后点击开始安装。"
        $progress.Value=0; Write-Log $status.Text
    }; $d.Dispose()
} })
$startButton.Add_Click({ Protect { Begin-Queue $false $false } })
$retryButton.Add_Click({ Protect { Begin-Queue $false $true } })
$stopButton.Add_Click({ $script:stopping=$true; $stopButton.Enabled=$false; $status.Text='将在当前安装结束后停止；已安装的应用会保留。' })
$demoButton.Add_Click({ Protect {
    $list.Items.Clear(); $script:demoWaiting=$false
    $folderBox.Text='[演示模式] 以下是虚构的示例文件，不会执行真实安装。'
    foreach ($name in @('VR-Gallery.apk','Space-Explorer.apk','Fitness-Studio.apk','Learning-Lab.apk','Media-Room.apk','Puzzle-World.apk')) { Add-Row $name '模拟数据' '' }
    Begin-Queue $true $false
} })
$exportButton.Add_Click({ Protect {
    $d=New-Object Windows.Forms.SaveFileDialog; $d.Filter='文本日志 (*.txt)|*.txt'; $d.FileName='quest-install-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.txt'
    if ($d.ShowDialog() -eq 'OK') { [IO.File]::WriteAllText($d.FileName,$log.Text,[Text.Encoding]::UTF8) }; $d.Dispose()
} })
$form.Add_FormClosing({ param($sender,$e)
    if ($script:busy) { $e.Cancel=$true; $script:stopping=$true; $status.Text='正在等待当前安装结束，请队列停止后再关闭窗口。' }
})
if ($SelfTest) {
    if (!$adbBox.Text) { throw 'No ADB found' }
    Read-Devices
    Add-Row '中文 文件.apk' '1 MB' 'C:\APK test\中文 文件.apk'
    if ($list.Items.Count -ne 1) { throw 'List creation failed' }
    Begin-Queue $true $false
    $timer.Stop()
    Queue-Tick
    Queue-Tick
    if ($script:success -ne 1 -or $script:busy) { throw 'Demo queue failed' }
    $list.Items.Clear()
    foreach ($n in 1..6) { Add-Row "demo-$n.apk" '模拟数据' '' }
    Begin-Queue $true $false
    $timer.Stop()
    foreach ($n in 1..7) { Queue-Tick }
    if ($script:success -ne 5 -or $script:failed -ne 1 -or $script:busy) { throw 'Failure continuation failed' }
    Begin-Queue $true $false
    $timer.Stop()
    Queue-Tick
    $script:stopping=$true
    Queue-Tick
    if ($script:busy -or $script:index -ne 1 -or $list.Items[1].SubItems[2].Text -ne '未执行') { throw 'Stop queue failed' }
    Write-Output 'PASS: UI construction, real ADB device query, Unicode row, demo success/failure continuation and graceful stop.'
    $form.Dispose(); exit 0
}
$form.Add_Shown({ if ($adbBox.Text) { Protect { Read-Devices } } })
[void]$form.ShowDialog()
$timer.Dispose(); $form.Dispose()
