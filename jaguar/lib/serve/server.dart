library jaguar.src.serve;

import 'dart:async';
import 'dart:io';

import 'package:jaguar/jaguar.dart';
import 'package:logging/logging.dart';

import 'package:jaguar/serve/error_writer/import.dart';
import 'package:path_tree/path_tree.dart';

export 'package:jaguar/serve/error_writer/import.dart';

/// The Jaguar server
class Jaguar extends Object with Muxable {
  final List<ConnectTo> _connectionInfos;

  /// Should the response be auto-compressed?
  ///
  /// Defaults to false.
  bool autoCompress;

  /// Base path of the served api.
  ///
  /// Defaults to '' (Aka. No base path).
  String basePath;

  /// Used to write error pages in case of HTTP errors.
  ///
  /// Defaults to [DefaultErrorWriter].
  ErrorWriter errorWriter;

  /// Session manager to parse and update session data for requests.
  ///
  /// Defaults to [JaguarSessionManager].
  SessionManager sessionManager;

  final before = <RouteInterceptor>[];

  final after = <RouteInterceptor>[];

  /// Logger used to log concise useful information about the request. This is
  /// also available in [Context] so that interceptors and route handlers can also
  /// log.
  final log = Logger('J');

  /// Internal http server
  List<HttpServer> _server;

  /// Constructs an instance of [Jaguar] with given configuration.
  ///
  /// [address]:[port] is the address and port at which the HTTP requests are
  /// listened.
  /// [multiThread] determines if the port can be serviced from multiple isolates.
  /// [securityContext] is used to configure HTTPS support.
  /// [autoCompress] determines if the response should be automatically compressed.
  /// [basePath] is the path prefix added to all constituting routes of this
  /// server.
  /// [errorWriter] is used to write custom error page [Response] in cases of HTTP
  /// errors.
  /// [sessionManager] provides ability to use custom session managers.
  Jaguar(
      {String address: "0.0.0.0",
      int port: 8080,
      bool multiThread: false,
      SecurityContext securityContext,
      this.autoCompress: false,
      this.basePath: '',
      ErrorWriter errorWriter,
      SessionManager sessionManager})
      : errorWriter = errorWriter ?? DefaultErrorWriter(),
        sessionManager = sessionManager ?? JaguarSessionManager(),
        _connectionInfos = [
          ConnectTo(
              address: address,
              port: port,
              securityContext: securityContext,
              multiThread: multiThread)
        ];

  void alsoTo(ConnectTo connection) {
    if (_server != null) throw Exception('Already started!');
    _connectionInfos.add(connection);
  }

  /// Starts serving the requests.
  Future<void> serve({bool logRequests: false}) async {
    if (_server != null) throw Exception('Already started!');

    _build();

    if (logRequests) log.info("Serving on " + _connectionInfos.join(', '));

    _server = List<HttpServer>(_connectionInfos.length);
    try {
      for (int i = 0; i < _connectionInfos.length; i++) {
        ConnectTo ct = _connectionInfos[i];
        if (ct.securityContext != null) {
          _server[i] = await HttpServer.bindSecure(
              ct.address, ct.port, ct.securityContext,
              shared: ct.multiThread);
        } else {
          _server[i] = await HttpServer.bind(ct.address, ct.port,
              shared: ct.multiThread);
        }
        _server[i].autoCompress = autoCompress;
      }
    } catch (e) {
      for (int i = 0; i < _connectionInfos.length; i++) {
        HttpServer server = _server[i];
        if (server != null) {
          await server.close();
        }
      }
      rethrow;
    }

    for (HttpServer server in _server) {
      if (logRequests) {
        server.listen((HttpRequest r) {
          log.info("Req => Method: ${r.method} Url: ${r.uri}");
          _handler(r);
        });
      } else {
        server.listen(_handler);
      }
    }
  }

  Future<void> restart({bool logRequests: false}) async {
    await close();
    return serve(logRequests: logRequests);
  }

  Future<void> _handler(HttpRequest request) async {
    final ctx = Context(Request(request),
        sessionManager: sessionManager, log: log, userFetchers: userFetchers);
    ctx.prefix = basePath;
    ctx.before.addAll(before);
    ctx.after.addAll(after);

    try {
      // Try to find a matching route and invoke it.
      RouteHandler handler =
          _routeTree.match(request.uri.pathSegments, request.method);
      if (handler != null) {
        await handler(ctx);
        // If no response, write 404 error.
        if (ctx.response == null) errorWriter.make404(ctx);
      } else {
        errorWriter.make404(ctx);
      }
    } catch (e, stack) {
      if (e is Response) {
        // If [Response] object was thrown, write it!
        ctx.response = e;
      } else if (e is ExceptionWithResponse) {
        ctx.response = e.response;
        if (ctx.response == null) errorWriter.make500(ctx, e, stack);
      } else
        errorWriter.make500(ctx, e, stack);
    }

    try {
      // Update session, if required.
      if (ctx.sessionNeedsUpdate) {
        dynamic mightBeFuture = sessionManager.write(ctx);
        if (mightBeFuture is Future) await mightBeFuture;
      }
    } catch (e, stack) {
      log.warning('${e.toString()}\n${stack.toString()}');
    }

    // Write response
    try {
      dynamic mightBeFuture = ctx.response.writeResponse(request.response);
      if (mightBeFuture is Future) await mightBeFuture;
    } catch (e, stack) {
      log.warning('${e.toString()}\n${stack.toString()}');
    }

    return request.response.close();
  }

  /// Closes the server
  Future<void> close() async {
    dynamic err;
    for (HttpServer server in _server) {
      try {
        await server.close(force: true);
      } catch (e) {
        if (err == null) err = e;
      }
    }
    _server = null;
    if (err != null) throw err;
  }

  /// Create a new route group
  GroupBuilder group([String path = '']) => GroupBuilder(this, path: path);

  /// Adds all the given [routes] to be served
  void add(Iterable<Route> routes) {
    if (_server != null) throw Exception('Server has started!');
    _routes.addAll(routes);
  }

  /// Adds the given [route] to be served
  Route addRoute(Route route) {
    if (_server != null) throw Exception('Server has started!');
    _routes.add(route);
    return route;
  }

  /// [RouteHandler]s
  final List<Route> _routes = [];

  final userFetchers = <Type, UserFetcher<AuthorizationUser>>{};

  PathTree<RouteHandler> _routeTree;

  void _build() {
    _routeTree = PathTree<RouteHandler>();

    for (Route route in _routes) {
      _routeTree.addPathAsSegments(route.pathSegments, route,
          tags: route.info.methods, pathRegEx: route.info.pathRegEx);
    }
  }
}

class ConnectTo {
  /// Address on which the API is serviced
  final String address;

  /// Port on which the API is serviced
  final int port;

  /// Security context for HTTPS
  final SecurityContext securityContext;

  /// Should the port be service-able from multiple isolates?
  ///
  /// Defaults to false.
  final bool multiThread;

  /// Base path
  String get authority => "$address:$port";

  ConnectTo(
      {this.address: "0.0.0.0",
      this.port: 8080,
      this.securityContext,
      this.multiThread: false});

  ConnectTo.https(this.securityContext,
      {this.address: "0.0.0.0", this.port: 443, this.multiThread: false});

  String toString() => authority;
}

abstract class ExceptionWithResponse {
  Response get response;
}
