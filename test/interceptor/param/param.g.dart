// GENERATED CODE - DO NOT MODIFY BY HAND

part of test.interceptor.param;

// **************************************************************************
// Generator: ApiGenerator
// Target: class ExampleApi
// **************************************************************************

abstract class _$JaguarExampleApi implements RequestHandler {
  static const List<RouteBase> routes = const <RouteBase>[
    const Route(path: '/user', methods: const <String>['GET'])
  ];

  String getUser(String who);

  String who();

  Future<Response> handleRequest(Request request, {String prefix: ''}) async {
    prefix += '/api';
    PathParams pathParams = new PathParams();
    bool match = false;

//Handler for getUser
    match =
        routes[0].match(request.uri.path, request.method, prefix, pathParams);
    if (match) {
      Response<String> rRouteResponse0 = new Response(null);
      WithParam iWithParam;
      try {
        iWithParam = new WrapWithParam(
          makeParams: const {#who: const MakeParamFromMethod(#who)},
          who: who(),
        )
            .createInterceptor();
        String rWithParam = iWithParam.pre();
        rRouteResponse0.statusCode = 200;
        rRouteResponse0.headers
            .set('content-type', 'text/plain; charset=utf-8');
        rRouteResponse0.value = getUser(
          rWithParam,
        );
        return rRouteResponse0;
      } catch (e) {
        await iWithParam?.onException();
        rethrow;
      }
    }

    return null;
  }
}
