import 'package:args/command_runner.dart';
import 'package:dio/dio.dart';
import 'package:tuple/tuple.dart';

typedef Payload = Tuple4<int, String, String, String>;

class RemoveRunner extends Command {
  @override
  String get description => 'Remove categories from given id';

  @override
  String get name => 'remove';

  RemoveRunner() {
    argParser.addOption('id', mandatory: true, help: 'starting id');
    argParser.addOption('wp-url',
        help: 'Base wordpress url', defaultsTo: String.fromEnvironment('WP_URL', defaultValue: 'wp.morhpt.sv'));
    argParser.addOption('username',
        abbr: 'u', defaultsTo: String.fromEnvironment('WP_USERNAME', defaultValue: 'admin'));
    argParser.addOption('password',
        abbr: 'p', defaultsTo: String.fromEnvironment('WP_PASSWORD', defaultValue: 'admin'));
  }

  @override
  Future<void> run() async {
    final id = argResults!['id'];
    final wpUrl = argResults!['wp-url'];
    final username = argResults!['username'];
    final password = argResults!['password'];

    await removeWordpressCategory(Payload(int.parse(id), wpUrl, username, password));
  }
}

removeWordpressCategory(Payload payload) async {
  print('- [worker] Starting requests to ${payload.item2}');
  final dio = Dio(BaseOptions(baseUrl: 'https://${payload.item2}/wp-json'));


  int lastId = payload.item1;
  bool hasError = false;

  int? endId;

  do {
    final jwtRes = await dio.post(
      '/jwt-auth/v1/token',
      data: {
        'username': payload.item3,
        'password': payload.item4,
      },
      options: Options(headers: {'Content-Type': 'application/x-www-form-urlencoded'}),
    );
    final jwt = jwtRes.data['token'];

    if (endId == null) {
      final newCat = await dio.post(
        '/wc/v3/products/categories',
        data: {
          "name": 'test',
          "slug": 'test_o22k',
        },
        options: Options(headers: {
          'Authorization': 'Bearer $jwt',
          'Content-Type': 'application/json',
        }),
      );
      endId = newCat.data['id'];
    }

    try {
      final sw = Stopwatch()..start();

      final mI = hasError ? lastId + 1 : payload.item1;
      for (int i = mI; i <= endId!; i++) {
        final res = await dio.delete(
          '/wc/v3/products/categories/$i',
          queryParameters: {
            'force': true
          },
          options: Options(headers: {
            'Authorization': 'Bearer $jwt',
            'Content-Type': 'application/json',
          }),
        );

        lastId = i;
        print('- [worker] ${sw.elapsed.inMilliseconds}ms Removed #${res.data['id']} - ${res.data['name']}');
      }

      hasError = false;
    } catch (e, st) {
      if (e is DioError) {
        if (e.response?.statusCode == 404) {
          print('- [worker] ERROR - ${e.requestOptions.queryParameters['id']} not exists. skipping');
          hasError = true;
        }
      } else {
        print('- [worker] ERROR - $e');
        print(st);
        print('- [worker] Waiting 5 seconds for cool down');
        hasError = true;
        await Future.delayed(const Duration(seconds: 5));
      }
    }

  } while (hasError);
}