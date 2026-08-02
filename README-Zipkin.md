# Zipkin

A distributed tracing system. It helps gather timing data needed to troubleshoot latency problems in service architectures. Features include both the collection and lookup of this data.

Ref: https://opentelemetry.io/docs/languages/dotnet/exporters/

## Backend Setup

## Note

If you have Zipkin or a Zipkin-compatible backend already set up, you can skip this section and setup the [Zipkin exporter dependencies](https://opentelemetry.io/docs/languages/dotnet/exporters/#zipkin-dependencies) for your application.

You can run [Zipkin](https://zipkin.io/) on in a Docker container by executing the following command:

```
docker run --rm -d -p 9411:9411 --name zipkin openzipkin/zipkin
```

## Dependencies

To send your trace data to [Zipkin](https://zipkin.io/), install the [exporter package](https://www.nuget.org/packages/OpenTelemetry.Exporter.Zipkin) as a dependency for your application:

```
dotnet add package OpenTelemetry.Exporter.Zipkin
```

If you’re using ASP.NET Core install the OpenTelemetry.Extensions.Hosting package as well:

```
dotnet add package OpenTelemetry.Extensions.Hosting
```

## Usage

### ASP.NET Core

Configure the exporter in your ASP.NET Core services:

```
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        // The rest of your setup code goes here
        .AddZipkinExporter(options =>
        {
            options.Endpoint = new Uri("your-zipkin-uri-here");
        }));
```

### Non-ASP.NET Core

Configure the exporter when creating a tracer provider:

```
var tracerProvider = Sdk.CreateTracerProviderBuilder()
    // The rest of your setup code goes here
    .AddZipkinExporter(options =>
    {
        options.Endpoint = new Uri("your-zipkin-uri-here");
    })
    .Build();
```
  