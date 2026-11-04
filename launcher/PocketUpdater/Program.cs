namespace PocketUpdater;

internal static class Program
{
    /// <param name="args">--from-launcher when the launcher opened it and closed.</param>
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new UpdaterForm(AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar), args.Contains("--from-launcher")));
    }
}
