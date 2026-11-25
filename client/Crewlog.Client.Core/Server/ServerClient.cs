using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Crewlog.Contracts;

namespace Crewlog.Client.Core.Server;

public sealed class ServerException(string message, HttpStatusCode? status = null) : Exception(message)
{
    public HttpStatusCode? Status { get; } = status;
}

/// <summary>HTTP client for the Crewlog server API (DESIGN §8.2).</summary>
public sealed class ServerClient(HttpClient http)
{
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) { Converters = { new JsonStringEnumConverter() } };

    /// <param name="addonVersion">The addon installed on disk, sent with every call (ApiHeaders) so the website sees the
    /// PC's versions while WoW is closed; null when there's none.</param>
    public static ServerClient Create(string baseUrl, string? token = null, string? addonVersion = null)
    {
        var http = new HttpClient { BaseAddress = new Uri(baseUrl.TrimEnd('/') + "/"), Timeout = TimeSpan.FromSeconds(60) };
        http.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue(ApiHeaders.ClientProduct, typeof(ServerClient).Assembly.GetName().Version?.ToString(3) ?? "0"));
        if (token is not null) http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        if (addonVersion is not null) http.DefaultRequestHeaders.TryAddWithoutValidation(ApiHeaders.AddonVersion, addonVersion);
        return new ServerClient(http);
    }

    public Task<DeviceStartResponse> StartDeviceLoginAsync(string deviceName, CancellationToken ct = default) =>
        PostAsync<DeviceStartRequest, DeviceStartResponse>(ApiRoutes.DeviceStart, new DeviceStartRequest(deviceName), ct);

    public Task<DevicePollResponse> PollDeviceLoginAsync(string deviceCode, CancellationToken ct = default) =>
        PostAsync<DevicePollRequest, DevicePollResponse>(ApiRoutes.DevicePoll, new DevicePollRequest(deviceCode), ct);

    /// <summary>Polls until the browser approves, the code expires, or <paramref name="ct"/> fires. Returns token + user name.</summary>
    public async Task<(string Token, string UserName)> WaitForApprovalAsync(DeviceStartResponse start, CancellationToken ct = default)
    {
        var deadline = DateTimeOffset.UtcNow.AddSeconds(start.ExpiresInSeconds);
        while (DateTimeOffset.UtcNow < deadline)
        {
            await Task.Delay(TimeSpan.FromSeconds(Math.Max(1, start.IntervalSeconds)), ct);
            var poll = await PollDeviceLoginAsync(start.DeviceCode, ct);
            switch (poll.Status)
            {
                case "approved" when poll.Token is not null: return (poll.Token, poll.UserName ?? "");
                case "pending": continue;
                default: throw new ServerException($"Linking was {poll.Status}. Start again.");
            }
        }
        throw new ServerException("The link code expired. Start again.");
    }

    public Task<SyncResponse> SyncAsync(AddonSave save, string clientVersion, CancellationToken ct = default) =>
        PostAsync<SyncRequest, SyncResponse>(ApiRoutes.Sync, new SyncRequest(save, clientVersion), ct);

    public async Task<MeResponse> MeAsync(CancellationToken ct = default)
    {
        using var resp = await http.GetAsync(ApiRoutes.Me.TrimStart('/'), ct);
        await EnsureOk(resp, ct);
        return (await resp.Content.ReadFromJsonAsync<MeResponse>(Json, ct))!;
    }

    public Task<JournalsResponse> JournalsAsync(CancellationToken ct = default) => GetAsync<JournalsResponse>(ApiRoutes.Journals, ct);

    public Task<InboxResponse> InboxAsync(CancellationToken ct = default) => GetAsync<InboxResponse>(ApiRoutes.Inbox, ct);

    /// <summary>Attach (true) or detach (false) one of your toons to a journal.</summary>
    public async Task SetAttachedAsync(Guid journalId, string characterGuid, bool attached, CancellationToken ct = default)
    {
        var route = ApiRoutes.JournalCharacterPath(journalId, characterGuid).TrimStart('/');
        using var resp = attached ? await http.PutAsync(route, null, ct) : await http.DeleteAsync(route, ct);
        await EnsureOk(resp, ct);
    }

    /// <summary>Unlinks this PC on the server: its token stops working there, not only on this PC.</summary>
    public async Task UnlinkAsync(CancellationToken ct = default)
    {
        using var resp = await http.DeleteAsync(ApiRoutes.DeviceSelf.TrimStart('/'), ct);
        await EnsureOk(resp, ct);
    }

    private async Task<T> GetAsync<T>(string route, CancellationToken ct)
    {
        using var resp = await http.GetAsync(route.TrimStart('/'), ct);
        await EnsureOk(resp, ct);
        return (await resp.Content.ReadFromJsonAsync<T>(Json, ct))!;
    }

    private async Task<TOut> PostAsync<TIn, TOut>(string route, TIn body, CancellationToken ct)
    {
        using var resp = await http.PostAsJsonAsync(route.TrimStart('/'), body, Json, ct);
        await EnsureOk(resp, ct);
        return (await resp.Content.ReadFromJsonAsync<TOut>(Json, ct))!;
    }

    private static async Task EnsureOk(HttpResponseMessage resp, CancellationToken ct)
    {
        if (resp.IsSuccessStatusCode) return;
        var text = await resp.Content.ReadAsStringAsync(ct);
        var msg = resp.StatusCode switch
        {
            HttpStatusCode.Unauthorized => "This PC is no longer linked. Link it again from the tray menu.",
            HttpStatusCode.TooManyRequests => "The server is busy (rate limited). Trying again later.",
            _ => $"Server answered {(int)resp.StatusCode}: {(text.Length > 200 ? text[..200] : text)}",
        };
        throw new ServerException(msg, resp.StatusCode);
    }
}

/// <summary>Device token at rest: DPAPI-protected for the current Windows user (DESIGN §7).</summary>
[SupportedOSPlatform("windows")]
public sealed class TokenStore(string path)
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("Crewlog.DeviceToken.v1");

    public string? Load()
    {
        try
        {
            if (!File.Exists(path)) return null;
            var plain = ProtectedData.Unprotect(File.ReadAllBytes(path), Entropy, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(plain);
        }
        catch (CryptographicException) { return null; } // other user / corrupted: link again
    }

    public void Save(string token)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, ProtectedData.Protect(Encoding.UTF8.GetBytes(token), Entropy, DataProtectionScope.CurrentUser));
    }

    public void Clear()
    {
        if (File.Exists(path)) File.Delete(path);
    }
}
