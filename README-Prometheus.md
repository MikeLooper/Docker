# Prometheus

Ref: https://opentelemetry.io/docs/languages/dotnet/exporters/

To send your metric data to [Prometheus](https://prometheus.io/), you can either:

[Enable Prometheus’ OTLP Receiver](https://prometheus.io/docs/guides/opentelemetry/#enable-the-otlp-receiver) and use the [OTLP exporter](https://opentelemetry.io/docs/languages/dotnet/exporters/#otlp) (best practice), or
Use the Prometheus exporter, a MetricReader that starts an HTTP server that collects metrics and serializes to Prometheus text format on request.

## Backend setup

To run a Prometheus server backend and begin scraping metrics, see the [Prometheus getting started guide](https://prometheus.io/docs/prometheus/latest/getting_started/).

To enable the OTLP Receiver, see the [Prometheus guide for enabling the OTLP Receiver](https://prometheus.io/docs/guides/opentelemetry/#enable-the-otlp-receiver).

The following sections provide detailed, .NET-specific instructions for configuring the Prometheus exporter.

There are two approaches for exporting metrics to Prometheus:

1. Using OTLP Exporter (Push): Push metrics to Prometheus using the OTLP protocol. This requires [Prometheus’ OTLP Receiver](https://prometheus.io/docs/prometheus/2.55/feature_flags/#otlp-receiver) to be enabled. This is the recommended approach for production environments as it supports exemplars and is stable.

2. Using Prometheus Exporter (Pull/Scrape): Expose a scraping endpoint in your application that Prometheus can scrape. This is the traditional Prometheus approach.

## Using OTLP Exporter (Push)

This approach uses the OTLP exporter to push metrics directly to Prometheus' OTLP receiver endpoint. This is recommended for production environments because it supports exemplars and uses the stable OTLP protocol.

### Dependencies

Install the OpenTelemetry.Exporter.OpenTelemetryProtocol package as a dependency for your project:

```
dotnet add package OpenTelemetry.Exporter.OpenTelemetryProtocol
```

If you’re using ASP.NET Core install the OpenTelemetry.Extensions.Hosting package as well:
```
dotnet add package OpenTelemetry.Extensions.Hosting
```

### Usage

#### ASP.NET Core

Configure the OTLP exporter to send metrics to Prometheus OTLP receiver:

```
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenTelemetry()
    .WithMetrics(metrics => metrics
        // The rest of your setup code goes here
        .AddOtlpExporter(options =>
        {
            options.Endpoint = new Uri("http://localhost:9090/api/v1/otlp/v1/metrics");
            options.Protocol = OtlpExportProtocol.HttpProtobuf;
        }));
```

#### Non-ASP.NET Core

Configure the exporter when creating a MeterProvider:

```
var meterProvider = Sdk.CreateMeterProviderBuilder()
    // Other setup code, like setting a resource goes here too
    .AddOtlpExporter(options =>
    {
        options.Endpoint = new Uri("http://localhost:9090/api/v1/otlp/v1/metrics");
        options.Protocol = OtlpExportProtocol.HttpProtobuf;
    })
    .Build();
```

### Note
Make sure Prometheus is started with the OTLP receiver enabled:

```
./prometheus --web.enable-otlp-receiver
```

Or when using Docker:

```
docker run -p 9090:9090 prom/prometheus --web.enable-otlp-receiver
```

## Using Prometheus Exporter (Pull/Scrape)

This approach exposes a metrics endpoint in your application (e.g., /metrics) that Prometheus scrapes at regular intervals.

### Warning

This exporter is still under development and doesn’t support exemplars. For production environments, consider using the OTLP exporter approach instead.

### Dependencies

Install the exporter package as a dependency for your application:

```
dotnet add package OpenTelemetry.Exporter.Prometheus.AspNetCore --version 1.17.0-beta.1
```

If you’re using ASP.NET Core install the OpenTelemetry.Extensions.Hosting package as well:

```
dotnet add package OpenTelemetry.Extensions.Hosting
```

### Usage

#### ASP.NET Core

Configure the exporter in your ASP.NET Core services:

```
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenTelemetry()
    .WithMetrics(metrics => metrics.AddPrometheusExporter());
```

You’ll then need to register the Prometheus scraping middleware so that Prometheus can scrape your application. Use the UseOpenTelemetryPrometheusScrapingEndpoint extension method on IApplicationBuilder:

```
var builder = WebApplication.CreateBuilder(args);

// ... Setup

var app = builder.Build();

app.UseOpenTelemetryPrometheusScrapingEndpoint();

await app.RunAsync();
```

By default, this exposes the metrics endpoint at /metrics. You can customize the endpoint path or use a predicate function for more advanced configuration:

```
app.UseOpenTelemetryPrometheusScrapingEndpoint(
    context => context.Request.Path == "/internal/metrics"
        && context.Connection.LocalPort == 5067);
```

#### Non-ASP.NET Core

##### Warning

This component is intended for dev inner-loop, there is no plan to make it production ready. Production environments should use OpenTelemetry.Exporter.Prometheus.AspNetCore, or a combination of OpenTelemetry.Exporter.OpenTelemetryProtocol and OpenTelemetry Collector.

For applications not using ASP.NET Core, you can use the HttpListener version which is available in a different package:

```
dotnet add package OpenTelemetry.Exporter.Prometheus.HttpListener --version 1.17.0-beta.1
```

Then this is setup directly on the MeterProviderBuilder:

```
var meterProvider = Sdk.CreateMeterProviderBuilder()
    .AddMeter(MyMeter.Name)
    .AddPrometheusHttpListener(
        options => options.UriPrefixes = new string[] { "http://localhost:9464/" })
    .Build();
```

#### Prometheus Configuration (Scrape)

When using the Prometheus exporter (pull/scrape approach), you need to configure Prometheus to scrape your application. Add the following to your prometheus.yml:

```
scrape_configs:
  - job_name: 'your-app-name'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:5000'] # Your application's host:port
```

For more details on configuring the Prometheus exporter, see [OpenTelemetry.Exporter.Prometheus.AspNetCore](https://github.com/open-telemetry/opentelemetry-dotnet/blob/main/src/OpenTelemetry.Exporter.Prometheus.AspNetCore/README.md).
