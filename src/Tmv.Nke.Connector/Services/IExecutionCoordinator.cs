namespace Tmv.Nke.Connector.Services;

public interface IExecutionCoordinator
{
    bool IsBusy { get; }
    Task<T> ExecuteExclusivelyAsync<T>(Func<Task<T>> action, TimeSpan timeout, CancellationToken ct = default);
    Task ExecuteExclusivelyAsync(Func<Task> action, TimeSpan timeout, CancellationToken ct = default);
}

