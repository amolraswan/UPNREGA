using System.Diagnostics;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace MusterRollDownloader;

public sealed class MainForm : Form
{
    private readonly TextBox ddBox = new() { MaxLength = 2 };
    private readonly TextBox mmBox = new() { MaxLength = 2 };
    private readonly TextBox yyyyBox = new() { MaxLength = 4 };
    private readonly ComboBox districtCombo = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly TextBox outputBox = new() { ReadOnly = true };
    private readonly Button browseButton = new() { Text = "Browse..." };
    private readonly Button runButton = new() { Text = "Run" };
    private readonly Button cancelButton = new() { Text = "Cancel", Enabled = false };
    private readonly Button openOutputButton = new() { Text = "Open Output Folder", Visible = false };
    private readonly Button openLogButton = new() { Text = "Open Log File", Visible = false };
    private readonly Label statusLabel = new() { AutoSize = false, Height = 28, Text = "Ready." };
    private readonly TextBox logBox = new()
    {
        Multiline = true,
        ReadOnly = true,
        ScrollBars = ScrollBars.Vertical,
        WordWrap = false
    };

    private readonly string installRoot;
    private Process? currentProcess;
    private string? lastOutputFolder;
    private string? lastLogFile;
    private bool cancelRequested;

    public MainForm()
    {
        installRoot = ResolveInstallRoot();

        Text = "Muster Roll PDF Downloader";
        MinimumSize = new Size(760, 620);
        StartPosition = FormStartPosition.CenterScreen;

        BuildLayout();
        WireEvents();
        LoadDistricts();
    }

    private void BuildLayout()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(16),
            ColumnCount = 1,
            RowCount = 6
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        var title = new Label
        {
            Text = "Muster Roll PDF Downloader",
            AutoSize = true,
            Font = new Font(Font.FontFamily, 16, FontStyle.Bold),
            Margin = new Padding(0, 0, 0, 14)
        };
        root.Controls.Add(title, 0, 0);

        var inputs = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            ColumnCount = 6,
            AutoSize = true,
            Margin = new Padding(0, 0, 0, 12)
        };
        inputs.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        inputs.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 70));
        inputs.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 70));
        inputs.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 92));
        inputs.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        inputs.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));

        inputs.Controls.Add(new Label { Text = "Date", AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 7, 12, 0) }, 0, 0);
        inputs.Controls.Add(ddBox, 1, 0);
        inputs.Controls.Add(mmBox, 2, 0);
        inputs.Controls.Add(yyyyBox, 3, 0);
        inputs.Controls.Add(new Label { Text = "District", AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(20, 7, 12, 0) }, 4, 0);
        inputs.Controls.Add(districtCombo, 5, 0);

        ddBox.PlaceholderText = "DD";
        mmBox.PlaceholderText = "MM";
        yyyyBox.PlaceholderText = "YYYY";
        districtCombo.Dock = DockStyle.Fill;

        root.Controls.Add(inputs, 0, 1);

        var outputRow = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            ColumnCount = 3,
            AutoSize = true,
            Margin = new Padding(0, 0, 0, 12)
        };
        outputRow.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        outputRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        outputRow.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        outputRow.Controls.Add(new Label { Text = "Output folder", AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 7, 12, 0) }, 0, 0);
        outputBox.Dock = DockStyle.Fill;
        outputRow.Controls.Add(outputBox, 1, 0);
        outputRow.Controls.Add(browseButton, 2, 0);

        root.Controls.Add(outputRow, 0, 2);

        var actions = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            Margin = new Padding(0, 0, 0, 12)
        };
        runButton.Width = 96;
        cancelButton.Width = 96;
        openOutputButton.Width = 150;
        openLogButton.Width = 120;
        actions.Controls.Add(runButton);
        actions.Controls.Add(cancelButton);
        actions.Controls.Add(openOutputButton);
        actions.Controls.Add(openLogButton);

        root.Controls.Add(actions, 0, 3);

        logBox.Dock = DockStyle.Fill;
        logBox.Font = new Font("Consolas", 9);
        root.Controls.Add(logBox, 0, 4);

        statusLabel.Dock = DockStyle.Fill;
        root.Controls.Add(statusLabel, 0, 5);

        Controls.Add(root);
    }

    private void WireEvents()
    {
        browseButton.Click += (_, _) => PickOutputFolder();
        runButton.Click += async (_, _) => await RunAsync();
        cancelButton.Click += (_, _) => CancelRun();
        openOutputButton.Click += (_, _) => OpenPath(lastOutputFolder);
        openLogButton.Click += (_, _) => OpenPath(lastLogFile);
    }

    private void LoadDistricts()
    {
        var districtsPath = Path.Combine(installRoot, "app", "districts.json");
        if (!File.Exists(districtsPath))
        {
            statusLabel.Text = "districts.json was not found in the installed app files.";
            runButton.Enabled = false;
            return;
        }

        var districts = JsonSerializer.Deserialize<string[]>(File.ReadAllText(districtsPath)) ?? Array.Empty<string>();
        districtCombo.Items.Clear();
        districtCombo.Items.AddRange(districts);
        if (districtCombo.Items.Count > 0)
        {
            districtCombo.SelectedIndex = 0;
        }
    }

    private void PickOutputFolder()
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "Choose output folder",
            ShowNewFolderButton = true,
            UseDescriptionForTitle = true
        };

        if (Directory.Exists(outputBox.Text))
        {
            dialog.InitialDirectory = outputBox.Text;
        }

        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            outputBox.Text = dialog.SelectedPath;
        }
    }

    private async Task RunAsync()
    {
        if (!ValidateInputs(out var error))
        {
            statusLabel.Text = error;
            return;
        }

        var rscriptPath = ResolveRscriptPath();
        var runScriptPath = Path.Combine(installRoot, "app", "run.R");
        if (rscriptPath is null)
        {
            statusLabel.Text = "Bundled Rscript.exe was not found under the app R folder.";
            return;
        }
        if (!File.Exists(runScriptPath))
        {
            statusLabel.Text = "run.R was not found in the installed app files.";
            return;
        }

        Directory.CreateDirectory(outputBox.Text);
        var tempDir = Path.Combine(Path.GetTempPath(), "MusterRollDownloader");
        Directory.CreateDirectory(tempDir);

        lastOutputFolder = null;
        lastLogFile = Path.Combine(
            outputBox.Text,
            $"muster_roll_downloader_{DateTime.Now:yyyyMMdd_HHmmss}.log"
        );

        var configPath = Path.Combine(tempDir, $"config_{Guid.NewGuid():N}.json");
        var config = new
        {
            district = districtCombo.SelectedItem?.ToString(),
            dd = ddBox.Text.Trim(),
            mm = mmBox.Text.Trim(),
            yyyy = yyyyBox.Text.Trim(),
            output_folder = outputBox.Text,
            run_log_path = lastLogFile,
            num_sessions = 4
        };
        await File.WriteAllTextAsync(
            configPath,
            JsonSerializer.Serialize(config, new JsonSerializerOptions { WriteIndented = true })
        );

        logBox.Clear();
        openOutputButton.Visible = false;
        openLogButton.Visible = false;
        cancelRequested = false;
        SetRunning(true);
        statusLabel.Text = "Running...";

        var startInfo = new ProcessStartInfo
        {
            FileName = rscriptPath,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WorkingDirectory = Path.Combine(installRoot, "app")
        };
        startInfo.ArgumentList.Add(runScriptPath);
        startInfo.ArgumentList.Add("--config");
        startInfo.ArgumentList.Add(configPath);
        startInfo.Environment["R_HOME"] = Path.Combine(installRoot, "R");
        startInfo.Environment["R_LIBS_USER"] = Path.Combine(installRoot, "library");
        startInfo.Environment["R_LIBS_SITE"] = "";

        currentProcess = new Process
        {
            StartInfo = startInfo,
            EnableRaisingEvents = true
        };

        currentProcess.OutputDataReceived += (_, eventArgs) => AppendProcessLine(eventArgs.Data);
        currentProcess.ErrorDataReceived += (_, eventArgs) => AppendProcessLine(eventArgs.Data);

        try
        {
            currentProcess.Start();
            currentProcess.BeginOutputReadLine();
            currentProcess.BeginErrorReadLine();
            await currentProcess.WaitForExitAsync();
            var exitCode = currentProcess.ExitCode;
            FinishRun(exitCode);
        }
        catch (Exception ex)
        {
            AppendLogLine(ex.Message);
            statusLabel.Text = "Could not start the bundled R workflow.";
            ShowPostRunButtons(success: false);
        }
        finally
        {
            currentProcess?.Dispose();
            currentProcess = null;
            SetRunning(false);
            TryDelete(configPath);
        }
    }

    private bool ValidateInputs(out string error)
    {
        error = "";
        if (!Regex.IsMatch(ddBox.Text.Trim(), "^\\d{1,2}$") ||
            !Regex.IsMatch(mmBox.Text.Trim(), "^\\d{1,2}$") ||
            !Regex.IsMatch(yyyyBox.Text.Trim(), "^\\d{4}$"))
        {
            error = "Enter DD, MM, and YYYY as numbers.";
            return false;
        }

        var dd = int.Parse(ddBox.Text.Trim());
        var mm = int.Parse(mmBox.Text.Trim());
        var yyyy = int.Parse(yyyyBox.Text.Trim());
        try
        {
            var date = new DateTime(yyyy, mm, dd);
            if (date.Date > DateTime.Today)
            {
                error = "Date is in the future.";
                return false;
            }
            if ((DateTime.Today - date.Date).TotalDays > 14)
            {
                error = "Date must be within the past 14 days.";
                return false;
            }
        }
        catch
        {
            error = "Enter a valid date.";
            return false;
        }

        if (districtCombo.SelectedItem is null)
        {
            error = "Choose a district.";
            return false;
        }

        if (string.IsNullOrWhiteSpace(outputBox.Text))
        {
            error = "Choose an output folder.";
            return false;
        }

        return true;
    }

    private void AppendProcessLine(string? line)
    {
        if (line is null) return;

        BeginInvoke((Action)(() =>
        {
            if (line.StartsWith("OUTPUT:", StringComparison.OrdinalIgnoreCase))
            {
                lastOutputFolder = line["OUTPUT:".Length..].Trim();
            }
            else if (line.StartsWith("LOG:", StringComparison.OrdinalIgnoreCase))
            {
                lastLogFile = line["LOG:".Length..].Trim();
            }
            else if (line.StartsWith("RUN_LOG:", StringComparison.OrdinalIgnoreCase))
            {
                lastLogFile = line["RUN_LOG:".Length..].Trim();
            }

            AppendLogLine(line);
            if (!string.IsNullOrWhiteSpace(line) &&
                !line.StartsWith("R_HOME:", StringComparison.OrdinalIgnoreCase) &&
                !line.StartsWith("R_LIBRARY:", StringComparison.OrdinalIgnoreCase))
            {
                statusLabel.Text = TrimStatus(line);
            }
        }));
    }

    private void AppendLogLine(string line)
    {
        logBox.AppendText(line + Environment.NewLine);
    }

    private static string TrimStatus(string line)
    {
        line = line.Trim();
        return line.Length <= 120 ? line : line[..117] + "...";
    }

    private void FinishRun(int exitCode)
    {
        if (cancelRequested)
        {
            statusLabel.Text = "Cancelled.";
            ShowPostRunButtons(success: false);
            return;
        }

        if (exitCode == 0)
        {
            statusLabel.Text = "Completed.";
            ShowPostRunButtons(success: true);
        }
        else
        {
            statusLabel.Text = "Failed. Open the log file for details.";
            ShowPostRunButtons(success: false);
        }
    }

    private void SetRunning(bool running)
    {
        ddBox.Enabled = !running;
        mmBox.Enabled = !running;
        yyyyBox.Enabled = !running;
        districtCombo.Enabled = !running;
        browseButton.Enabled = !running;
        runButton.Enabled = !running;
        cancelButton.Enabled = running;
    }

    private void CancelRun()
    {
        if (currentProcess is null || currentProcess.HasExited) return;

        cancelRequested = true;
        statusLabel.Text = "Cancelling...";
        try
        {
            currentProcess.Kill(entireProcessTree: true);
        }
        catch (Exception ex)
        {
            AppendLogLine("Cancel failed: " + ex.Message);
        }
    }

    private void ShowPostRunButtons(bool success)
    {
        openOutputButton.Visible = success && Directory.Exists(lastOutputFolder);
        openLogButton.Visible = !string.IsNullOrWhiteSpace(lastLogFile) && File.Exists(lastLogFile);
    }

    private string? ResolveRscriptPath()
    {
        var preferred = Path.Combine(installRoot, "R", "bin", "Rscript.exe");
        var fallback = Path.Combine(installRoot, "R", "bin", "x64", "Rscript.exe");

        if (File.Exists(preferred)) return preferred;
        if (File.Exists(fallback)) return fallback;
        return null;
    }

    private string ResolveInstallRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        for (var i = 0; i < 8 && directory is not null; i++)
        {
            if (File.Exists(Path.Combine(directory.FullName, "app", "run.R")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        return AppContext.BaseDirectory;
    }

    private static void OpenPath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        if (!File.Exists(path) && !Directory.Exists(path)) return;

        Process.Start(new ProcessStartInfo
        {
            FileName = path,
            UseShellExecute = true
        });
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path)) File.Delete(path);
        }
        catch
        {
            // A temp config file left behind is harmless.
        }
    }
}
