using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Windows.Forms;

internal static class Launcher
{
    [STAThread]
    private static void Main()
    {
        try
        {
            using (Runspace runspace = RunspaceFactory.CreateRunspace())
            {
                runspace.ApartmentState = ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                runspace.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    string root = AppDomain.CurrentDomain.BaseDirectory;
                    runspace.SessionStateProxy.SetVariable("PSScriptRoot", root);
                    shell.AddScript(File.ReadAllText(Path.Combine(root, "QuestApkInstaller.ps1")));
                    shell.Invoke();
                    if (shell.HadErrors)
                        Report(String.Join(Environment.NewLine, shell.Streams.Error));
                }
            }
        }
        catch (Exception error) { Report(error.ToString()); }
    }
    private static void Report(string message)
    {
        try { File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "startup-error.txt"), message); } catch { }
        MessageBox.Show(message, "Quest APK Installer");
    }
}
