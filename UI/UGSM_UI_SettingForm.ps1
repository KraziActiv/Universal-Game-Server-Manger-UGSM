Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing


function Get-UGSMSettingsColor {
    param(
        [string]$Name,
        [string]$FallbackHex
    )

    try {
        $var = Get-Variable -Name $Name -Scope Global -ErrorAction SilentlyContinue
        if ($var -and $var.Value -is [System.Drawing.Color]) {
            return [System.Drawing.Color]$var.Value
        }
    }
    catch {}

    try { return [System.Drawing.ColorTranslator]::FromHtml($FallbackHex) }
    catch { return [System.Drawing.Color]::Transparent }
}

function Write-UGSMSettingsUILog {
    [CmdletBinding()]
    param(
        [ValidateSet('TRACE','DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$Level = 'INFO',
        [Parameter(Mandatory)]
        [string]$Message,
        [System.Exception]$Exception
    )

    try {
        if (Get-Command Write-UGSMLog -ErrorAction SilentlyContinue) {
            if ($Exception) { Write-UGSMLog -Level $Level -Category 'SettingsUI' -Message $Message -Exception $Exception }
            else { Write-UGSMLog -Level $Level -Category 'SettingsUI' -Message $Message }
        }
    }
    catch {}
}

function New-UGSMSettingsForm {
    [CmdletBinding()]
    param(
        [System.Windows.Forms.IWin32Window]$Owner
    )

    $settings = Get-UGSMGlobalSettingsModel

    Write-UGSMSettingsUILog -Level 'INFO' -Message 'Opening global settings form.'

    $colors = [pscustomobject]@{
        Background       = Get-UGSMSettingsColor -Name 'UGSM_ColorBackground' -FallbackHex '#071120'
        Panel            = Get-UGSMSettingsColor -Name 'UGSM_ColorPanelBackground' -FallbackHex '#0B1728'
        Input            = Get-UGSMSettingsColor -Name 'UGSM_ColorInputBackground' -FallbackHex '#0A1320'
        Text             = Get-UGSMSettingsColor -Name 'UGSM_ColorText' -FallbackHex '#FFFFFF'
        TextStrong       = Get-UGSMSettingsColor -Name 'UGSM_ColorText' -FallbackHex '#F4F7FA'
        MutedText        = Get-UGSMSettingsColor -Name 'UGSM_ColorMutedText' -FallbackHex '#B8C7D9'
        Border           = Get-UGSMSettingsColor -Name 'UGSM_ColorBorder' -FallbackHex '#20344D'
        Neutral          = Get-UGSMSettingsColor -Name 'UGSM_ColorNeutral' -FallbackHex '#334155'
        Success          = Get-UGSMSettingsColor -Name 'UGSM_ColorSuccess' -FallbackHex '#22C55E'
        HealthyText      = Get-UGSMSettingsColor -Name 'UGSM_ColorSuccessTextBright' -FallbackHex '#87E3A8'
        Caution          = Get-UGSMSettingsColor -Name 'UGSM_ColorCapacity' -FallbackHex '#FCD34D'
        BrandTextDark    = Get-UGSMSettingsColor -Name 'UGSM_ColorBrandTextDark' -FallbackHex '#0B1220'
    }

    $form = [System.Windows.Forms.Form]::new()
    $form.Text = 'UGSM Global Settings'
    $form.StartPosition = if ($Owner) { 'CenterParent' } else { 'CenterScreen' }
    $form.Size = [System.Drawing.Size]::new(780, 580)
    $form.MinimumSize = [System.Drawing.Size]::new(740, 560)
    $form.BackColor = $colors.Background
    $form.ForeColor = $colors.Text
    $form.Font = [System.Drawing.Font]::new('Segoe UI', 9)
    $form.FormBorderStyle = 'Sizable'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $root = [System.Windows.Forms.TableLayoutPanel]::new()
    $root.Dock = 'Fill'
    $root.Margin = 0
    $root.Padding = [System.Windows.Forms.Padding]::new(18, 18, 18, 16)
    $root.ColumnCount = 1
    $root.RowCount = 4
    $root.BackColor = $form.BackColor
    [void]$root.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, 52))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, 52))
    [void]$root.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, 38))
    [void]$form.Controls.Add($root)

    $headerPanel = [System.Windows.Forms.Panel]::new()
    $headerPanel.Dock = 'Fill'
    $headerPanel.Margin = 0
    $headerPanel.BackColor = [System.Drawing.Color]::Transparent
    [void]$root.Controls.Add($headerPanel, 0, 0)

    $titleLabel = [System.Windows.Forms.Label]::new()
    $titleLabel.Text = 'Global Settings'
    $titleLabel.Location = [System.Drawing.Point]::new(0, 0)
    $titleLabel.Size = [System.Drawing.Size]::new(260, 24)
    $titleLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 14)
    $titleLabel.ForeColor = $colors.TextStrong
    [void]$headerPanel.Controls.Add($titleLabel)

    $subtitleLabel = [System.Windows.Forms.Label]::new()
    $subtitleLabel.Text = 'App-wide paths, Steam credentials, Discord webhook, and refresh interval.'
    $subtitleLabel.Location = [System.Drawing.Point]::new(0, 26)
    $subtitleLabel.Size = [System.Drawing.Size]::new(640, 18)
    $subtitleLabel.Font = [System.Drawing.Font]::new('Segoe UI', 8.5)
    $subtitleLabel.ForeColor = $colors.MutedText
    [void]$headerPanel.Controls.Add($subtitleLabel)

    $scrollHost = [System.Windows.Forms.Panel]::new()
    $scrollHost.Dock = 'Fill'
    $scrollHost.AutoScroll = $true
    $scrollHost.Margin = 0
    $scrollHost.BackColor = [System.Drawing.Color]::Transparent
    [void]$root.Controls.Add($scrollHost, 0, 1)

    $content = [System.Windows.Forms.TableLayoutPanel]::new()
    $content.Dock = 'Top'
    $content.AutoSize = $true
    $content.AutoSizeMode = 'GrowAndShrink'
    $content.Margin = 0
    $content.Padding = 0
    $content.ColumnCount = 1
    $content.RowCount = 3
    [void]$content.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
    [void]$scrollHost.Controls.Add($content)

    function New-SettingsSectionPanel {
        param([string]$SectionTitle, [string]$SectionSubtitle)

        $panel = [System.Windows.Forms.Panel]::new()
        $panel.Dock = 'Top'
        $panel.Height = 160
        $panel.Margin = [System.Windows.Forms.Padding]::new(0, 0, 0, 12)
        $panel.Padding = [System.Windows.Forms.Padding]::new(14)
        $panel.BackColor = $colors.Panel
        $panel.BorderStyle = 'FixedSingle'

        $sectionTitleLabel = [System.Windows.Forms.Label]::new()
        $sectionTitleLabel.Text = $SectionTitle
        $sectionTitleLabel.Location = [System.Drawing.Point]::new(14, 12)
        $sectionTitleLabel.Size = [System.Drawing.Size]::new(220, 22)
        $sectionTitleLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 11)
        $sectionTitleLabel.ForeColor = $colors.TextStrong
        [void]$panel.Controls.Add($sectionTitleLabel)

        $sectionSubtitleLabel = [System.Windows.Forms.Label]::new()
        $sectionSubtitleLabel.Text = $SectionSubtitle
        $sectionSubtitleLabel.Location = [System.Drawing.Point]::new(14, 34)
        $sectionSubtitleLabel.Size = [System.Drawing.Size]::new(620, 18)
        $sectionSubtitleLabel.Font = [System.Drawing.Font]::new('Segoe UI', 8.5)
        $sectionSubtitleLabel.ForeColor = $colors.MutedText
        [void]$panel.Controls.Add($sectionSubtitleLabel)

        return $panel
    }

    function Add-SettingsTextRow {
        param(
            [System.Windows.Forms.Panel]$Parent,
            [string]$FieldLabel,
            [int]$TopOffset,
            [string]$Value = '',
            [switch]$UsePassword,
            [switch]$WithBrowse
        )

        $labelControl = [System.Windows.Forms.Label]::new()
        $labelControl.Text = $FieldLabel
        $labelControl.Location = [System.Drawing.Point]::new(14, $TopOffset)
        $labelControl.Size = [System.Drawing.Size]::new(170, 22)
        $labelControl.ForeColor = $colors.Text
        $labelControl.Font = [System.Drawing.Font]::new('Segoe UI', 9)
        [void]$Parent.Controls.Add($labelControl)

        $textBoxWidth = if ($WithBrowse) { 410 } else { 510 }
        $textBox = [System.Windows.Forms.TextBox]::new()
        $textBox.Location = [System.Drawing.Point]::new(190, ($TopOffset - 2))
        $textBox.Size = [System.Drawing.Size]::new($textBoxWidth, 26)
        $textBox.BackColor = $colors.Input
        $textBox.ForeColor = $colors.Text
        $textBox.BorderStyle = 'FixedSingle'
        $textBox.Text = $Value
        if ($UsePassword) {
            $textBox.UseSystemPasswordChar = $true
        }
        [void]$Parent.Controls.Add($textBox)

        $browseButton = $null
        if ($WithBrowse) {
            $browseButton = [System.Windows.Forms.Button]::new()
            $browseButton.Text = 'Browse'
            $browseButton.Location = [System.Drawing.Point]::new(608, ($TopOffset - 3))
            $browseButton.Size = [System.Drawing.Size]::new(82, 28)
            $browseButton.BackColor = $colors.Neutral
            $browseButton.ForeColor = $colors.Text
            $browseButton.FlatStyle = 'Flat'
            $browseButton.FlatAppearance.BorderColor = $colors.Border
            $browseButton.FlatAppearance.BorderSize = 1
            [void]$Parent.Controls.Add($browseButton)
        }

        return [pscustomobject]@{
            TextBox = $textBox
            Browse  = $browseButton
        }
    }

    $pathsPanel = New-SettingsSectionPanel -SectionTitle 'Paths' -SectionSubtitle 'Global folders used by the app. SteamCMD Path should be a folder, not the EXE file.'
    $pathsPanel.Height = 194
    [void]$content.Controls.Add($pathsPanel)

    $steamPathRow = Add-SettingsTextRow -Parent $pathsPanel -FieldLabel 'SteamCMD Install Folder' -TopOffset 66 -Value ([string]$settings.SteamCmdPath) -WithBrowse
    $profilePathRow = Add-SettingsTextRow -Parent $pathsPanel -FieldLabel 'Profile Base Root' -TopOffset 116 -Value ([string]$settings.ProfileBaseRoot) -WithBrowse
    $backupPathRow = Add-SettingsTextRow -Parent $pathsPanel -FieldLabel 'Backup Root' -TopOffset 150 -Value ([string]$settings.BackupRoot) -WithBrowse

    $steamPathHint = [System.Windows.Forms.Label]::new()
    $steamPathHint.Text = 'UGSM will install steamcmd.exe into this folder and reuse it if it is already valid.'
    $steamPathHint.Location = [System.Drawing.Point]::new(190, 92)
    $steamPathHint.Size = [System.Drawing.Size]::new(470, 18)
    $steamPathHint.Font = [System.Drawing.Font]::new('Segoe UI', 8)
    $steamPathHint.ForeColor = $colors.MutedText
    [void]$pathsPanel.Controls.Add($steamPathHint)

    $steamPanel = New-SettingsSectionPanel -SectionTitle 'Steam' -SectionSubtitle 'Credentials used for downloads that require a Steam login.'
    $steamPanel.Height = 154
    [void]$content.Controls.Add($steamPanel)

    $steamUserRow = Add-SettingsTextRow -Parent $steamPanel -FieldLabel 'Steam Username' -TopOffset 66 -Value ([string]$settings.SteamUsername)
    $steamPasswordRow = Add-SettingsTextRow -Parent $steamPanel -FieldLabel 'Steam Password' -TopOffset 100 -Value ([string]$settings.SteamPassword) -UsePassword
    $steamPasswordHint = [System.Windows.Forms.Label]::new()
    $steamPasswordHint.Text = 'Leave blank to keep the saved password.'
    $steamPasswordHint.Location = [System.Drawing.Point]::new(190, 124)
    $steamPasswordHint.Size = [System.Drawing.Size]::new(300, 16)
    $steamPasswordHint.Font = [System.Drawing.Font]::new('Segoe UI', 8)
    $steamPasswordHint.ForeColor = $colors.MutedText
    [void]$steamPanel.Controls.Add($steamPasswordHint)

    $otherPanel = New-SettingsSectionPanel -SectionTitle 'App / Discord' -SectionSubtitle 'App behavior and shared notification target.'
    $otherPanel.Height = 154
    [void]$content.Controls.Add($otherPanel)

    $discordRow = Add-SettingsTextRow -Parent $otherPanel -FieldLabel 'Global Discord Webhook' -TopOffset 66 -Value ([string]$settings.GlobalDiscordWebhookUrl)
    $discordHint = [System.Windows.Forms.Label]::new()
    $discordHint.Text = 'Leave blank to keep the saved webhook.'
    $discordHint.Location = [System.Drawing.Point]::new(190, 90)
    $discordHint.Size = [System.Drawing.Size]::new(320, 16)
    $discordHint.Font = [System.Drawing.Font]::new('Segoe UI', 8)
    $discordHint.ForeColor = $colors.MutedText
    [void]$otherPanel.Controls.Add($discordHint)

    $refreshLabel = [System.Windows.Forms.Label]::new()
    $refreshLabel.Text = 'Refresh Seconds'
    $refreshLabel.Location = [System.Drawing.Point]::new(14, 120)
    $refreshLabel.Size = [System.Drawing.Size]::new(170, 20)
    $refreshLabel.ForeColor = $colors.Text
    [void]$otherPanel.Controls.Add($refreshLabel)

    $refreshBox = [System.Windows.Forms.NumericUpDown]::new()
    $refreshBox.Location = [System.Drawing.Point]::new(190, 118)
    $refreshBox.Size = [System.Drawing.Size]::new(100, 26)
    $refreshBox.Minimum = 1
    $refreshBox.Maximum = 300
    $refreshBox.Value = [decimal]([int]$settings.RefreshSeconds)
    $refreshBox.BackColor = $colors.Input
    $refreshBox.ForeColor = $colors.Text
    [void]$otherPanel.Controls.Add($refreshBox)

    $statusPanel = [System.Windows.Forms.Panel]::new()
    $statusPanel.Dock = 'Fill'
    $statusPanel.Margin = 0
    $statusPanel.BackColor = [System.Drawing.Color]::Transparent
    [void]$root.Controls.Add($statusPanel, 0, 2)

    $messageLabel = [System.Windows.Forms.Label]::new()
    $messageLabel.Text = "Settings file: $(Get-UGSMGlobalSettingsPath)"
    $messageLabel.Location = [System.Drawing.Point]::new(0, 0)
    $messageLabel.Size = [System.Drawing.Size]::new(700, 18)
    $messageLabel.ForeColor = $colors.MutedText
    $messageLabel.Font = [System.Drawing.Font]::new('Segoe UI', 8.5)
    [void]$statusPanel.Controls.Add($messageLabel)

    $steamStatusLabel = [System.Windows.Forms.Label]::new()
    $steamStatusLabel.Text = if ($settings.SteamCmdIsInstalled) { 'SteamCMD: Installed' } else { 'SteamCMD: Not verified yet' }
    $steamStatusLabel.Location = [System.Drawing.Point]::new(0, 24)
    $steamStatusLabel.Size = [System.Drawing.Size]::new(700, 20)
    $steamStatusLabel.ForeColor = if ($settings.SteamCmdIsInstalled) { ($colors.HealthyText) } else { ($colors.Caution) }
    $steamStatusLabel.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 8.5)
    [void]$statusPanel.Controls.Add($steamStatusLabel)

    $buttonPanel = [System.Windows.Forms.FlowLayoutPanel]::new()
    $buttonPanel.Dock = 'Fill'
    $buttonPanel.FlowDirection = 'RightToLeft'
    $buttonPanel.WrapContents = $false
    $buttonPanel.Margin = 0
    $buttonPanel.Padding = 0
    $buttonPanel.BackColor = [System.Drawing.Color]::Transparent
    [void]$root.Controls.Add($buttonPanel, 0, 3)

    $saveButton = [System.Windows.Forms.Button]::new()
    $saveButton.Text = 'Save'
    $saveButton.Size = [System.Drawing.Size]::new(96, 30)
    $saveButton.BackColor = $colors.Success
    $saveButton.ForeColor = $colors.BrandTextDark
    $saveButton.FlatStyle = 'Flat'
    $saveButton.FlatAppearance.BorderSize = 0
    [void]$buttonPanel.Controls.Add($saveButton)

    $cancelButton = [System.Windows.Forms.Button]::new()
    $cancelButton.Text = 'Cancel'
    $cancelButton.Size = [System.Drawing.Size]::new(96, 30)
    $cancelButton.BackColor = $colors.Neutral
    $cancelButton.ForeColor = $colors.Text
    $cancelButton.FlatStyle = 'Flat'
    $cancelButton.FlatAppearance.BorderColor = $colors.Border
    $cancelButton.FlatAppearance.BorderSize = 1
    [void]$buttonPanel.Controls.Add($cancelButton)

    $browseForFolder = {
        param([System.Windows.Forms.TextBox]$TargetBox)
        $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dialog.ShowNewFolderButton = $true
        if (-not [string]::IsNullOrWhiteSpace($TargetBox.Text) -and (Test-Path -LiteralPath $TargetBox.Text)) {
            $dialog.SelectedPath = $TargetBox.Text
        }
        if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
            $TargetBox.Text = $dialog.SelectedPath
            Write-UGSMSettingsUILog -Level 'DEBUG' -Message ('Folder selected from settings browse dialog: {0}' -f $dialog.SelectedPath)
        }
        $dialog.Dispose()
    }

    foreach ($row in @($steamPathRow, $profilePathRow, $backupPathRow)) {
        if ($row.Browse) {
            $targetBox = $row.TextBox
            $row.Browse.Add_Click({ & $browseForFolder $targetBox }.GetNewClosure())
        }
    }

    $cancelButton.Add_Click({
        Write-UGSMSettingsUILog -Level 'INFO' -Message 'Global settings form cancelled.'
        $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $form.Close()
    }.GetNewClosure())

    $saveButton.Add_Click({
        try {
            Write-UGSMSettingsUILog -Level 'INFO' -Message 'Global settings save requested from UI.'
            $steamFolder = [string]$steamPathRow.TextBox.Text.Trim()
            $exePath = if ([string]::IsNullOrWhiteSpace($steamFolder)) { '' } else { Join-Path $steamFolder 'steamcmd.exe' }
            $isInstalled = if ([string]::IsNullOrWhiteSpace($steamFolder)) { $false } else { (Test-Path -LiteralPath $exePath) }

            $inputObject = [pscustomobject]@{
                Theme                   = 'Dark'
                SteamCmdPath            = $steamFolder
                SteamCmdExePath         = $exePath
                SteamCmdIsInstalled     = $isInstalled
                SteamUsername           = [string]$steamUserRow.TextBox.Text.Trim()
                SteamPassword           = [string]$steamPasswordRow.TextBox.Text
                GlobalDiscordWebhookUrl = [string]$discordRow.TextBox.Text.Trim()
                ProfileBaseRoot         = [string]$profilePathRow.TextBox.Text.Trim()
                BackupRoot              = [string]$backupPathRow.TextBox.Text.Trim()
                RefreshSeconds          = [int]$refreshBox.Value
            }

            $saveResult = Save-UGSMGlobalSettingsValidated -Settings $inputObject

            Write-UGSMSettingsUILog -Level 'INFO' -Message 'Global settings saved from UI.'
            $form.Tag = $saveResult.Settings
            $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $form.Close()
        }
        catch {
            Write-UGSMSettingsUILog -Level 'ERROR' -Message 'Global settings UI save failed.' -Exception $_.Exception
            [System.Windows.Forms.MessageBox]::Show(
                $form,
                $_.Exception.Message,
                'Save Settings Failed',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    }.GetNewClosure())

    return $form
}
