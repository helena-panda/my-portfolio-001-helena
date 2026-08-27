Add-Type -AssemblyName PresentationFramework

function New-TrimmedWav {
    param([string]$Src, [string]$Dst, [double]$Seconds)
    $b = [System.IO.File]::ReadAllBytes($Src)
    $fmtStart = -1
    $fmtLen = 0
    $dataPos = -1
    $dataLen = 0
    $i = 12
    while ($i -lt $b.Length - 8) {
        $id = [System.Text.Encoding]::ASCII.GetString($b, $i, 4)
        $len = [BitConverter]::ToInt32($b, $i + 4)
        if ($id -eq 'fmt ') { $fmtStart = $i; $fmtLen = $len }
        elseif ($id -eq 'data') { $dataPos = $i + 8; $dataLen = $len; break }
        $i += 8 + $len + ($len % 2)
    }
    if ($dataPos -lt 0 -or $fmtStart -lt 0) { return $false }
    $ch = [BitConverter]::ToInt16($b, $fmtStart + 10)
    $rate = [BitConverter]::ToInt32($b, $fmtStart + 12)
    $bits = [BitConverter]::ToInt16($b, $fmtStart + 22)
    $blockAlign = $ch * $bits / 8
    $bps = $rate * $blockAlign
    $cut = [int][Math]::Floor([Math]::Min($dataLen, $bps * $Seconds))
    $cut = $cut - ($cut % $blockAlign)
    $ms = New-Object System.IO.MemoryStream
    $w = New-Object System.IO.BinaryWriter($ms)
    $w.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF'))
    $w.Write(4 + (8 + $fmtLen) + (8 + $cut))
    $w.Write([System.Text.Encoding]::ASCII.GetBytes('WAVE'))
    $w.Write($b, $fmtStart, 8 + $fmtLen)
    $w.Write([System.Text.Encoding]::ASCII.GetBytes('data'))
    $w.Write($cut)
    $w.Write($b, $dataPos, $cut)
    $w.Flush()
    [System.IO.File]::WriteAllBytes($Dst, $ms.ToArray())
    return $true
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="番茄钟" Width="330" Height="232"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ResizeMode="NoResize" ShowInTaskbar="True"
        WindowStartupLocation="CenterScreen">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="18" Padding="14,7">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#2F7D4F"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Opacity" Value="0.75"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border x:Name="Card" Background="#DCEFDC" CornerRadius="20" BorderBrush="#9CC6A4" BorderThickness="1.5" Opacity="0.97">
    <StackPanel Margin="20,16">
      <TextBlock x:Name="TimeText" Text="25:00" FontSize="66" FontWeight="Light" HorizontalAlignment="Center"
                 Foreground="#2F4F3F" FontFamily="Segoe UI"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,10,0,0">
        <Button x:Name="MinusBtn" Content="-1" Width="42" Height="30" Background="#3E8E5A"/>
        <TextBlock x:Name="MinsText" Text="25 分钟" Margin="16,8" FontSize="14" Foreground="#45735C" Cursor="Hand" TextAlignment="Center"/>
        <TextBox x:Name="MinsBox" Width="64" Margin="16,3" FontSize="14" TextAlignment="Center" Visibility="Collapsed"/>
        <Button x:Name="PlusBtn" Content="+1" Width="42" Height="30" Background="#3E8E5A"/>
      </StackPanel>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,26,0,0">
        <Button x:Name="StartBtn" Content="开始" Width="96" Height="38" Background="#3E8E5A"/>
        <Button x:Name="PauseBtn" Content="暂停" Width="96" Height="38" Background="#7FA98A" Margin="16,0,0,0"/>
        <Button x:Name="CloseBtn" Content="×" Width="38" Height="38" Background="#C96B4B" Margin="16,0,0,0"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win = [System.Windows.Markup.XamlReader]::Load($reader)

$timeText = $win.FindName('TimeText')
$minsText = $win.FindName('MinsText')
$minsBox  = $win.FindName('MinsBox')
$minusBtn = $win.FindName('MinusBtn')
$plusBtn  = $win.FindName('PlusBtn')
$startBtn = $win.FindName('StartBtn')
$pauseBtn = $win.FindName('PauseBtn')
$closeBtn = $win.FindName('CloseBtn')

$script:totalMins = 25
$script:remaining = 25 * 60
$script:running = $false
$script:endMs = 0

function Update-Display {
    $m = [math]::Floor($script:remaining / 60)
    $s = $script:remaining % 60
    $timeText.Text = $m.ToString('00') + ':' + $s.ToString('00')
}

function Update-Stepper {
    $minusBtn.IsEnabled = (-not $script:running) -and ($script:totalMins -gt 1)
    $plusBtn.IsEnabled  = (-not $script:running) -and ($script:totalMins -lt 999)
}

function Set-Total([int]$mins) {
    $script:totalMins = [Math]::Max(1, [Math]::Min(999, $mins))
    $minsText.Text = "$($script:totalMins) 分钟"
    $script:remaining = $script:totalMins * 60
    Update-Display
    Update-Stepper
}

function Commit-Mins {
    if ($minsBox.Visibility -eq 'Visible') {
        $v = 0
        if ([int]::TryParse($minsBox.Text, [ref]$v)) { Set-Total $v }
        $minsBox.Visibility = 'Collapsed'
        $minsText.Visibility = 'Visible'
    }
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(250)
$timer.Add_Tick({
    if ($script:running) {
        $script:remaining = [Math]::Max(0, [Math]::Round(($script:endMs - [DateTimeOffset]::Now.ToUnixTimeMilliseconds()) / 1000))
        Update-Display
        if ($script:remaining -le 0) {
            $script:running = $false
            Update-Stepper
            Start-Sakura
        }
    }
})

$startBtn.Add_Click({
    if ($script:remaining -le 0) { $script:remaining = $script:totalMins * 60 }
    if ($script:running) { return }
    $script:running = $true
    $script:endMs = [DateTimeOffset]::Now.ToUnixTimeMilliseconds() + $script:remaining * 1000
    Update-Stepper
    Update-Display
})

$pauseBtn.Add_Click({
    if (-not $script:running) { return }
    $script:remaining = [Math]::Max(0, [Math]::Round(($script:endMs - [DateTimeOffset]::Now.ToUnixTimeMilliseconds()) / 1000))
    $script:running = $false
    Update-Stepper
    Update-Display
})

$closeBtn.Add_Click({ $win.Close() })

$minusBtn.Add_Click({ Set-Total ($script:totalMins - 1) })
$plusBtn.Add_Click({ Set-Total ($script:totalMins + 1) })

$minsText.Add_MouseLeftButtonUp({
    if ($script:running) { return }
    $minsBox.Text = "$($script:totalMins)"
    $minsText.Visibility = 'Collapsed'
    $minsBox.Visibility = 'Visible'
    $minsBox.Focus()
    $minsBox.SelectAll()
})

$minsBox.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq 'Enter') { Commit-Mins }
    if ($e.Key -eq 'Escape') {
        $minsBox.Visibility = 'Collapsed'
        $minsText.Visibility = 'Visible'
    }
})

$minsBox.Add_LostFocus({ Commit-Mins })

$win.Add_MouseLeftButtonDown({
    param($s, $e)
    if ($e.OriginalSource -is [System.Windows.Controls.Primitives.ButtonBase]) { return }
    if ($e.OriginalSource -is [System.Windows.Controls.TextBlock]) { return }
    if ($e.OriginalSource -is [System.Windows.Controls.TextBox]) { return }
    $win.DragMove()
})

$win.Add_Closed({ $timer.Stop() })

function New-Petal {
    $el = New-Object System.Windows.Shapes.Ellipse
    $el.Width = 7 + $script:swRand.NextDouble() * 6
    $el.Height = $el.Width * (0.7 + $script:swRand.NextDouble() * 0.4)
    $tone = [byte](195 + $script:swRand.Next(20))
    $el.Fill = New-Object System.Windows.Media.SolidColorBrush(
        [System.Windows.Media.Color]::FromArgb([byte](150 + $script:swRand.Next(80)), [byte]255, $tone, [byte](180 + $script:swRand.Next(40))))
    $script:canvas.Children.Add($el) | Out-Null
    return [pscustomobject]@{
        el  = $el
        x   = $script:swRand.NextDouble() * $script:sw.Width
        y   = -20 - $script:swRand.NextDouble() * 80
        vy  = 60 + $script:swRand.NextDouble() * 90
        wf  = 1.2 + $script:swRand.NextDouble() * 2
        ph  = $script:swRand.NextDouble() * 6.283
        amp = 1 + $script:swRand.NextDouble() * 2
        rot = $script:swRand.NextDouble() * 360
        vr  = (0.3 + $script:swRand.NextDouble() * 0.8) * $(if ($script:swRand.Next(2) -eq 0) { -1 } else { 1 })
    }
}

function Start-Sakura {
    try {
        if ($script:renderTimer) { $script:renderTimer.Stop() }
        if ($script:sakuraClose) { $script:sakuraClose.Stop() }
        if ($script:chimePlayer) {
            $script:chimePlayer.Stop()
            $script:chimePlayer.Dispose()
        }
        if ($script:chimePath) { Remove-Item -LiteralPath $script:chimePath -ErrorAction SilentlyContinue }
        if ($script:sw) {
            try { $script:sw.Close() } catch { }
        }
        $script:sw = $null
        $script:chimePath = $null
        $mediaDir = Join-Path $env:SystemRoot 'Media'
        $candidates = @('Windows Startup.wav', 'Windows XP Start.wav', 'tada.wav', 'chord.wav', 'ding.wav', 'Windows Notify System Generic.wav')
        $src = $null
        foreach ($name in $candidates) {
            $p = Join-Path $mediaDir $name
            if (Test-Path -LiteralPath $p) { $src = $p; break }
        }
        if ($src) {
            $script:chimePath = Join-Path $env:TEMP ("boot_" + [guid]::NewGuid().ToString('N') + '.wav')
            if (New-TrimmedWav $src $script:chimePath 4) {
                $script:chimePlayer = New-Object System.Media.SoundPlayer($script:chimePath)
                $script:chimePlayer.Play()
            }
        }

        $script:sw = New-Object System.Windows.Window
        $script:sw.WindowStyle = 'None'
        $script:sw.AllowsTransparency = $true
        $script:sw.Background = [System.Windows.Media.Brushes]::Transparent
        $script:sw.Topmost = $true
        $script:sw.ShowInTaskbar = $false
        $script:sw.IsHitTestVisible = $false
        $script:sw.Left = 0
        $script:sw.Top = 0
        $script:sw.Width = [System.Windows.SystemParameters]::PrimaryScreenWidth
        $script:sw.Height = [System.Windows.SystemParameters]::PrimaryScreenHeight
        $script:canvas = New-Object System.Windows.Controls.Canvas
        $script:sw.Content = $script:canvas
        $script:swRand = New-Object System.Random

        $script:petals = @()
        for ($i = 0; $i -lt 70; $i++) {
            $script:petals += New-Petal
        }
        $script:petalTime = 0
        $script:lastFrame = [DateTime]::Now

        $script:renderTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:renderTimer.Interval = [TimeSpan]::FromMilliseconds(33)
        $script:renderTimer.Add_Tick({
            $now = [DateTime]::Now
            $dt = [Math]::Min(0.05, ($now - $script:lastFrame).TotalSeconds)
            $script:lastFrame = $now
            $script:petalTime += $dt
            foreach ($p in $script:petals) {
                $p.x += [Math]::Sin($script:petalTime * $p.wf + $p.ph) * $p.amp * 22 * $dt
                $p.y += $p.vy * $dt
                $p.rot += $p.vr * 90 * $dt
                [System.Windows.Controls.Canvas]::SetLeft($p.el, $p.x)
                [System.Windows.Controls.Canvas]::SetTop($p.el, $p.y)
                $p.el.RenderTransform = New-Object System.Windows.Media.RotateTransform($p.rot)
            }
            $gone = @($script:petals | Where-Object { $_.y -gt $script:sw.Height + 20 })
            foreach ($g in $gone) {
                $script:canvas.Children.Remove($g.el)
            }
            $script:petals = @($script:petals | Where-Object { $_.y -le $script:sw.Height + 20 })
            while ($script:petals.Count -lt 40) {
                $script:petals += New-Petal
            }
        })

        $script:sakuraClose = New-Object System.Windows.Threading.DispatcherTimer
        $script:sakuraClose.Interval = [TimeSpan]::FromSeconds(14)
        $script:sakuraClose.Add_Tick({
            $script:sakuraClose.Stop()
            $script:renderTimer.Stop()
            if ($script:chimePlayer) {
                $script:chimePlayer.Stop()
                $script:chimePlayer.Dispose()
            }
            if ($script:chimePath) { Remove-Item -LiteralPath $script:chimePath -ErrorAction SilentlyContinue }
            $script:sw.Close()
        })
        $script:sw.Add_Closed({
            $script:renderTimer.Stop()
        })
        $script:sw.Show()
        $script:renderTimer.Start()
        $script:sakuraClose.Start()
    } catch {
        try {
            Add-Content -LiteralPath "$env:TEMP\pomo_debug.log" -Value ("[sakura] " + (Get-Date -Format 'HH:mm:ss') + " " + $_.Exception.Message) -Encoding UTF8
        } catch { }
    }
}

$timer.Start()
Update-Display
Update-Stepper
$win.ShowDialog() | Out-Null
