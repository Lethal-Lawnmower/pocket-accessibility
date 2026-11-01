namespace PocketLauncher;

internal static class Program
{
    /// <param name="args">Optionally the path of a cartridge dump to import,
    /// as Windows passes it when a ROM is dropped on the launcher or opened
    /// with it.</param>
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        string? rom = args.Length > 0 && File.Exists(args[0]) ? Path.GetFullPath(args[0]) : null;
        Application.Run(new MainForm(GamePaths.Discover(), rom));
    }
}
