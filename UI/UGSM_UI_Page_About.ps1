# About Page

function Write-UGSMAboutUILog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory)]
        [string]$Message,

        [AllowNull()]
        [System.Exception]$Exception
    )

    if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
        if ($Exception) {
            Write-UGSMLog -Level $Level -Category 'AboutUI' -Message $Message -Exception $Exception
        }
        else {
            Write-UGSMLog -Level $Level -Category 'AboutUI' -Message $Message
        }
        return
    }

    try { Write-Verbose ("[AboutUI] $Message") } catch {}
}

function New-UGSMAboutFallbackData {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        AppName        = 'Universal Game Server Manager'
        Version        = 'v2 Preview'
        Build          = 'Unknown'
        Author         = 'KraziActiv'
        Tagline        = ''
        Description    = 'UGSM About page placeholder.'
        DiscordUrl     = ''
        ReleaseNotes   = @('No release notes available.')
        SupportMessage = 'Support message unavailable.'
    }
}

function Set-UGSMAboutTextBoxStyle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Forms.TextBox]$TextBox,

        [Parameter(Mandatory)]
        $Theme,

        [float]$FontSize = 9
    )

    $TextBox.Multiline = $true
    $TextBox.ReadOnly = $true
    $TextBox.ScrollBars = 'Vertical'
    $TextBox.BorderStyle = 'FixedSingle'
    $TextBox.BackColor = $global:UGSM_ColorInputBackground
    $TextBox.ForeColor = $Theme.Text
    $TextBox.Font = New-Object System.Drawing.Font('Segoe UI', $FontSize)
}

function New-UGSMAboutPage {
    [CmdletBinding()]
    param(
        $Theme
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-UGSMAboutUILog -Level 'INFO' -Message 'About page creation started.'

    try {
        if (-not $Theme) {
            if (Get-Command Get-UGSMTheme -ErrorAction SilentlyContinue) {
                $Theme = Get-UGSMTheme
            }
            else {
                $Theme = @{
                    WindowBg   = $global:UGSM_ColorBackground
                    Surface    = $global:UGSM_ColorPanelBackground
                    Border     = $global:UGSM_ColorBorder
                    Text       = $global:UGSM_ColorText
                    Muted      = $global:UGSM_ColorMutedText
                    Accent     = $global:UGSM_ColorSuccess
                    AccentBlue = $global:UGSM_ColorPrimary
                }
            }
        }

        $data = $null
        try {
            $data = if (Get-Command Get-UGSMAboutData -ErrorAction SilentlyContinue) {
                Get-UGSMAboutData
            }
            else {
                Write-UGSMAboutUILog -Level 'WARN' -Message 'Get-UGSMAboutData was not loaded. Using fallback About data.'
                New-UGSMAboutFallbackData
            }
        }
        catch {
            Write-UGSMAboutUILog -Level 'ERROR' -Message 'Failed to load About data. Using fallback data.' -Exception $_.Exception
            $data = New-UGSMAboutFallbackData
        }

        $page = New-Object System.Windows.Forms.Panel
        $page.Dock = 'Fill'
        $page.BackColor = $Theme.WindowBg
        $page.Padding = New-Object System.Windows.Forms.Padding(14)

        if (Get-Command Enable-UGSMDoubleBuffer -ErrorAction SilentlyContinue) {
            Enable-UGSMDoubleBuffer -Control $page
        }

        $header = New-Object System.Windows.Forms.Panel
        $header.Dock = 'Top'
        $header.Height = 78
        $header.BackColor = $global:UGSM_ColorSuccessSurface
        $header.Padding = New-Object System.Windows.Forms.Padding(14, 10, 14, 10)
        [void]$page.Controls.Add($header)

        $title = New-Object System.Windows.Forms.Label
        $title.Text = 'About'
        $title.ForeColor = $global:UGSM_ColorText
        $title.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
        $title.Dock = 'Top'
        $title.Height = 30
        [void]$header.Controls.Add($title)

        $sub = New-Object System.Windows.Forms.Label
        $sub.Text = 'Project details and release information'
        $sub.ForeColor = $Theme.Muted
        $sub.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
        $sub.Dock = 'Top'
        $sub.Height = 22
        [void]$header.Controls.Add($sub)
        $sub.BringToFront()

        $body = New-Object System.Windows.Forms.TableLayoutPanel
        $body.Dock = 'Fill'
        $body.BackColor = $Theme.Surface
        $body.Padding = New-Object System.Windows.Forms.Padding(20)
        $body.ColumnCount = 1
        $body.RowCount = 5
        $body.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 185))) | Out-Null
        $body.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34))) | Out-Null
        $body.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
        $body.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 12))) | Out-Null
        $body.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42))) | Out-Null
        [void]$page.Controls.Add($body)
        $body.BringToFront()

        $txtAbout = New-Object System.Windows.Forms.TextBox
        $txtAbout.Dock = 'Fill'
        Set-UGSMAboutTextBoxStyle -TextBox $txtAbout -Theme $Theme -FontSize 10
        $txtAbout.Text = @"
$($data.AppName)

Version: $($data.Version)
Build: $($data.Build)
Author: $($data.Author)

$($data.Tagline)

$($data.Description)
"@
        [void]$body.Controls.Add($txtAbout, 0, 0)

        $lblRelease = New-Object System.Windows.Forms.Label
        $lblRelease.Text = 'Recent Release Notes'
        $lblRelease.ForeColor = $Theme.Text
        $lblRelease.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
        $lblRelease.Dock = 'Fill'
        $lblRelease.TextAlign = 'MiddleLeft'
        [void]$body.Controls.Add($lblRelease, 0, 1)

        $txtRelease = New-Object System.Windows.Forms.TextBox
        $txtRelease.Dock = 'Fill'
        Set-UGSMAboutTextBoxStyle -TextBox $txtRelease -Theme $Theme -FontSize 9
        $txtRelease.Text = (@($data.ReleaseNotes) -join ([Environment]::NewLine + [Environment]::NewLine))
        [void]$body.Controls.Add($txtRelease, 0, 2)

        $buttonRow = New-Object System.Windows.Forms.FlowLayoutPanel
        $buttonRow.Dock = 'Fill'
        $buttonRow.BackColor = [System.Drawing.Color]::Transparent
        $buttonRow.FlowDirection = 'LeftToRight'
        $buttonRow.WrapContents = $false
        [void]$body.Controls.Add($buttonRow, 0, 4)

        $btnDiscord = if (Get-Command New-UGSMButton -ErrorAction SilentlyContinue) {
            New-UGSMButton -Text 'Discord' -X 0 -Y 0 -Width 110 -Height 32 -BackColor $global:UGSM_ColorPrimary -ForeColor $global:UGSM_ColorText
        }
        else {
            New-Object System.Windows.Forms.Button
        }
        $btnDiscord.Text = 'Discord'
        $btnDiscord.Size = New-Object System.Drawing.Size(110, 32)
        $btnDiscord.Margin = New-Object System.Windows.Forms.Padding(0, 4, 10, 0)
        [void]$buttonRow.Controls.Add($btnDiscord)

        $btnSupport = if (Get-Command New-UGSMButton -ErrorAction SilentlyContinue) {
            New-UGSMButton -Text 'Support UGSM' -X 0 -Y 0 -Width 130 -Height 32 -BackColor $global:UGSM_ColorSecondaryPanel -ForeColor $global:UGSM_ColorText
        }
        else {
            New-Object System.Windows.Forms.Button
        }
        $btnSupport.Text = 'Support UGSM'
        $btnSupport.Size = New-Object System.Drawing.Size(130, 32)
        $btnSupport.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
        [void]$buttonRow.Controls.Add($btnSupport)

        $btnDiscord.Add_Click({
                try {
                    Write-UGSMAboutUILog -Level 'INFO' -Message 'Discord button clicked.'
                    if (-not [string]::IsNullOrWhiteSpace([string]$data.DiscordUrl)) {
                        Start-Process ([string]$data.DiscordUrl)
                        Write-UGSMAboutUILog -Level 'INFO' -Message 'Discord link opened.'
                    }
                    else {
                        Write-UGSMAboutUILog -Level 'WARN' -Message 'Discord link was empty.'
                    }
                }
                catch {
                    Write-UGSMAboutUILog -Level 'ERROR' -Message 'Failed to open Discord link.' -Exception $_.Exception
                    [System.Windows.Forms.MessageBox]::Show(
                        ('Failed to open Discord link: ' + $_.Exception.Message),
                        'Discord',
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Error
                    ) | Out-Null
                }
            }.GetNewClosure())

        $btnSupport.Add_Click({
                try {
                    Write-UGSMAboutUILog -Level 'INFO' -Message 'Support UGSM button clicked.'
                    [System.Windows.Forms.MessageBox]::Show(
                        [string]$data.SupportMessage,
                        'Support UGSM',
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Information
                    ) | Out-Null
                }
                catch {
                    Write-UGSMAboutUILog -Level 'ERROR' -Message 'Failed to show support message.' -Exception $_.Exception
                    [System.Windows.Forms.MessageBox]::Show(
                        ('Failed to show support message: ' + $_.Exception.Message),
                        'Support UGSM',
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Error
                    ) | Out-Null
                }
            }.GetNewClosure())

        $sw.Stop()
        Write-UGSMAboutUILog -Level 'INFO' -Message ("About page creation finished. DurationMs={0}" -f $sw.ElapsedMilliseconds)

        return $page
    }
    catch {
        $sw.Stop()
        Write-UGSMAboutUILog -Level 'ERROR' -Message ("About page creation failed. DurationMs={0}" -f $sw.ElapsedMilliseconds) -Exception $_.Exception
        throw
    }
}
