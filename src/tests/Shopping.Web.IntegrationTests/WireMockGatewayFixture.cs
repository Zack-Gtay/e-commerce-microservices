using WireMock.Server;

namespace Shopping.Web.IntegrationTests;

/// <summary>
/// Stands up a WireMock server that impersonates the YARP API gateway.
///
/// This is the seam that lets the web tier be tested without Docker: the Refit clients
/// are pointed at the stub instead of http://yarpapigateway:8080, so we exercise the real
/// Refit interfaces, the real URL templates and the real JSON contract, while keeping the
/// test hermetic and fast.
/// </summary>
public sealed class WireMockGatewayFixture : IDisposable
{
    public WireMockServer Server { get; }

    public string GatewayUrl => Server.Urls[0];

    public WireMockGatewayFixture() => Server = WireMockServer.Start();

    public void Reset() => Server.Reset();

    public void Dispose() => Server.Dispose();
}
