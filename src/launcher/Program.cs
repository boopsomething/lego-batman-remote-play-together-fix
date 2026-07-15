using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("SOTAVPN LEGO Batman Remote Play Together Launcher")]
[assembly: AssemblyDescription("Transparent donor launcher for Steam Remote Play Together")]
[assembly: AssemblyCompany("SOTAVPN")]
[assembly: AssemblyProduct("SOTAVPN LEGO Batman COOP Fix")]
[assembly: AssemblyCopyright("SOTAVPN")]
[assembly: AssemblyVersion("1.3.1.0")]
[assembly: AssemblyFileVersion("1.3.1.0")]

namespace SotaVpnLegoBatmanLauncher
{
    internal static class Program
    {
        internal const string CampaignUrl = "https://t.me/sota?start=gaming";
        private const string ExpectedExecutableName = "LEGOBatmanLotDK-Win64-Shipping.exe";
        private const string MutexName = @"Local\SOTAVPN-LEGO-Batman-RPT-349620";

        [STAThread]
        private static int Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            try
            {
                string launcherDirectory = Path.GetDirectoryName(
                    Process.GetCurrentProcess().MainModule.FileName);
                string configPath = Path.Combine(launcherDirectory, "SOTAVPN-CoopLauncher.ini");
                bool selfTest = false;
                bool uiTest = false;

                for (int index = 0; index < args.Length; index++)
                {
                    string argument = args[index];
                    if (string.Equals(argument, "--self-test", StringComparison.OrdinalIgnoreCase))
                        selfTest = true;
                    else if (string.Equals(argument, "--ui-test", StringComparison.OrdinalIgnoreCase))
                        uiTest = true;
                    else if (string.Equals(argument, "--config", StringComparison.OrdinalIgnoreCase) && index + 1 < args.Length)
                        configPath = Path.GetFullPath(args[++index]);
                }

                LauncherConfig config = LauncherConfig.Load(configPath);
                ValidateTarget(config.GameExecutable);

                if (selfTest)
                {
                    WriteLog("Self-test passed. Config=" + configPath + "; Target=" + config.GameExecutable);
                    return 0;
                }

                bool ownsMutex;
                using (var mutex = new Mutex(true, MutexName, out ownsMutex))
                {
                    if (!ownsMutex)
                    {
                        WriteLog("Launch ignored because another instance is active.");
                        return 0;
                    }

                    using (var promo = new PromoForm())
                    {
                        DialogResult result = promo.ShowDialog();
                        if (result != DialogResult.OK)
                        {
                            WriteLog("Launch cancelled in the SOTAVPN information window.");
                            return 0;
                        }
                    }

                    if (uiTest)
                    {
                        WriteLog("UI test completed without starting the game.");
                        return 0;
                    }

                    return StartAndWaitForGame(config.GameExecutable);
                }
            }
            catch (Exception exception)
            {
                WriteLog("Launcher error: " + exception);
                MessageBox.Show(
                    "Не удалось запустить игру.\n\n" + exception.Message +
                    "\n\nПодробности: %LOCALAPPDATA%\\SOTAVPN\\LEGO_Batman_Remote_Play\\launcher.log",
                    "SOTAVPN — ошибка запуска",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
                return 1;
            }
        }

        private static int StartAndWaitForGame(string gameExecutable)
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = gameExecutable,
                WorkingDirectory = Path.GetDirectoryName(gameExecutable),
                UseShellExecute = false
            };

            WriteLog(
                "Starting game. SteamAppId=" +
                (Environment.GetEnvironmentVariable("SteamAppId") ?? "<unset>") +
                "; SteamGameId=" +
                (Environment.GetEnvironmentVariable("SteamGameId") ?? "<unset>") +
                "; Target=" + gameExecutable);

            using (Process process = Process.Start(startInfo))
            {
                if (process == null)
                    throw new InvalidOperationException("Windows вернула пустой процесс при запуске игры.");

                WriteLog("Game started with PID " + process.Id + ".");
                process.WaitForExit();
                WriteLog("Game exited with code " + process.ExitCode + ".");
                return process.ExitCode;
            }
        }

        private static void ValidateTarget(string gameExecutable)
        {
            if (string.IsNullOrWhiteSpace(gameExecutable))
                throw new InvalidDataException("В SOTAVPN-CoopLauncher.ini не указан GameExecutable.");

            if (!string.Equals(
                Path.GetFileName(gameExecutable),
                ExpectedExecutableName,
                StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException(
                    "Ожидался файл " + ExpectedExecutableName + ", но указан: " +
                    Path.GetFileName(gameExecutable));
            }

            if (!File.Exists(gameExecutable))
                throw new FileNotFoundException("Основной EXE LEGO Batman не найден.", gameExecutable);
        }

        internal static void OpenCampaignUrl()
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = CampaignUrl,
                UseShellExecute = true
            });
            WriteLog("SOTAVPN link opened by explicit user action.");
        }

        private static string DataDirectory
        {
            get
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "SOTAVPN",
                    "LEGO_Batman_Remote_Play");
            }
        }

        internal static void WriteLog(string message)
        {
            try
            {
                Directory.CreateDirectory(DataDirectory);
                string line = DateTimeOffset.Now.ToString("O") + " " + message + Environment.NewLine;
                File.AppendAllText(Path.Combine(DataDirectory, "launcher.log"), line, Encoding.UTF8);
            }
            catch
            {
                // Diagnostics must never block the game launch.
            }
        }
    }

    internal sealed class LauncherConfig
    {
        internal string GameExecutable { get; private set; }
        private LauncherConfig() { }

        internal static LauncherConfig Load(string path)
        {
            if (!File.Exists(path))
                throw new FileNotFoundException("Файл настройки launcher не найден.", path);

            var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (string rawLine in File.ReadAllLines(path, Encoding.UTF8))
            {
                string line = rawLine.Trim();
                if (line.Length == 0 || line.StartsWith("#") || line.StartsWith(";"))
                    continue;

                int separator = line.IndexOf('=');
                if (separator <= 0)
                    continue;

                values[line.Substring(0, separator).Trim()] = line.Substring(separator + 1).Trim();
            }

            var config = new LauncherConfig();
            string executable;
            if (values.TryGetValue("GameExecutable", out executable))
                config.GameExecutable = Environment.ExpandEnvironmentVariables(executable.Trim('"'));

            return config;
        }
    }

    internal sealed class PromoForm : Form
    {
        internal PromoForm()
        {
            Text = "SOTAVPN — LEGO Batman Remote Play Together";
            ClientSize = new Size(520, 258);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(24, 27, 34);
            ForeColor = Color.White;
            Font = new Font("Segoe UI", 10F, FontStyle.Regular, GraphicsUnit.Point);

            var title = new Label
            {
                AutoSize = false,
                Bounds = new Rectangle(24, 20, 472, 38),
                Text = "COOP FIX от SOTAVPN",
                Font = new Font("Segoe UI", 18F, FontStyle.Bold, GraphicsUnit.Point),
                ForeColor = Color.FromArgb(85, 199, 255),
                TextAlign = ContentAlignment.MiddleCenter
            };

            var description = new Label
            {
                AutoSize = false,
                Bounds = new Rectangle(28, 65, 464, 55),
                Text = "Решение запускает LEGO Batman через Steam Remote Play Together.\n" +
                       "Для стабильной игры рекомендуем VPN от SOTAVPN.",
                TextAlign = ContentAlignment.MiddleCenter
            };

            var link = new LinkLabel
            {
                AutoSize = false,
                Bounds = new Rectangle(28, 122, 464, 30),
                Text = "t.me/sota?start=gaming",
                TextAlign = ContentAlignment.MiddleCenter,
                LinkColor = Color.FromArgb(85, 199, 255),
                ActiveLinkColor = Color.White,
                VisitedLinkColor = Color.FromArgb(85, 199, 255)
            };
            link.LinkClicked += delegate { OpenSotaVpnLink(); };

            var launchButton = new Button
            {
                Bounds = new Rectangle(28, 180, 210, 44),
                Text = "Запустить игру",
                DialogResult = DialogResult.OK,
                BackColor = Color.FromArgb(31, 131, 200),
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat
            };
            launchButton.FlatAppearance.BorderSize = 0;

            var openButton = new Button
            {
                Bounds = new Rectangle(248, 180, 150, 44),
                Text = "Открыть SOTAVPN",
                BackColor = Color.FromArgb(45, 50, 61),
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat
            };
            openButton.FlatAppearance.BorderColor = Color.FromArgb(85, 199, 255);
            openButton.Click += delegate { OpenSotaVpnLink(); };

            var cancelButton = new Button
            {
                Bounds = new Rectangle(408, 180, 84, 44),
                Text = "Отмена",
                DialogResult = DialogResult.Cancel,
                BackColor = Color.FromArgb(45, 50, 61),
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat
            };

            var consent = new Label
            {
                AutoSize = false,
                Bounds = new Rectangle(28, 230, 464, 20),
                Text = "Ссылка открывается только после нажатия пользователем.",
                Font = new Font("Segoe UI", 8F, FontStyle.Regular, GraphicsUnit.Point),
                ForeColor = Color.Gray,
                TextAlign = ContentAlignment.MiddleCenter
            };

            AcceptButton = launchButton;
            CancelButton = cancelButton;
            Controls.Add(title);
            Controls.Add(description);
            Controls.Add(link);
            Controls.Add(launchButton);
            Controls.Add(openButton);
            Controls.Add(cancelButton);
            Controls.Add(consent);
        }

        private static void OpenSotaVpnLink()
        {
            try
            {
                Program.OpenCampaignUrl();
            }
            catch (Exception exception)
            {
                Program.WriteLog("Could not open SOTAVPN link: " + exception.Message);
                MessageBox.Show(
                    "Не удалось открыть ссылку автоматически.\n\n" + Program.CampaignUrl,
                    "SOTAVPN",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Warning);
            }
        }
    }
}
