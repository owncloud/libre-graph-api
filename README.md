# Libre Graph Api

An API for open Cloud Collaboration. See the [Libre Graph Home](https://libregraph.github.io/) for more details.

This API is inspired by [Microsoft Graph API](https://developer.microsoft.com/en-us/graph).


## Goal

The project goal is to provide an open source standard for open Cloud Collaboration.

Libre Graph is open source and open to any open source project that implements endpoints of the API.

## Specification

The API specification uses the OpenAPI Specification (OAS) standard.

The [OpenAPI Specification (OAS)](https://swagger.io/specification/) defines a standard, language-agnostic interface to RESTful APIs which allows both humans and computers to discover and understand the capabilities of the service without access to source code, documentation, or through network traffic inspection. When properly defined, a consumer can understand and interact with the remote service with a minimal amount of implementation logic.

An OpenAPI definition can then be used by documentation generation tools to display the API, code generation tools to generate servers and clients in various programming languages, testing tools, and many other use cases.

## Documentation

You can find a rendered version of the [API documentation](https://owncloud.dev/libre-graph-api/) in our dev docs.

## Clients

Client code can be generated from the API spec.

For example, to run the generator for the C++ bindings locally, run the following docker based command:
```bash
docker run --rm -v "${PWD}:/local" openapitools/openapi-generator-cli generate --enable-post-process-file  -t local/templates/cpp-qt-client  -i local/api/openapi-spec/v1.0.yaml -g cpp-qt-client -o /local/out/cpp
```
That generates the output in out/cpp.


### Available client libraries
- [C++/Qt](https://github.com/owncloud/libre-graph-api-cpp-qt-client)
- [go](https://github.com/owncloud/libre-graph-api-go)
- [php](https://github.com/owncloud/libre-graph-api-php)
- [typescript-axios](https://github.com/owncloud/libre-graph-api-typescript-axios)

