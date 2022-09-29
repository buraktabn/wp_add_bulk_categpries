import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:recase/recase.dart';
import 'package:tuple/tuple.dart';

class Category extends Equatable {
  final int id;
  final String name;
  final int level;
  final int? parentId;

  const Category(this.id, this.level, this.name, [this.parentId]);

  Category copyWith({
    int? id,
    String? name,
    int? level,
    int? parentId,
  }) =>
      Category(id ?? this.id, level ?? this.level, name ?? this.name, parentId ?? this.parentId);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'level': level,
      'parentId': parentId,
    };
  }

  @override
  List<Object?> get props => [id, level, name, parentId];

  @override
  bool get stringify => true;
}

class StructuredCategory extends Equatable {
  final int id;
  final String name;
  final List<StructuredCategory> children;

  const StructuredCategory(this.id, this.name, [this.children = const []]);

  StructuredCategory copyWith({
    int? id,
    String? name,
    List<StructuredCategory>? children,
  }) =>
      StructuredCategory(id ?? this.id, name ?? this.name, children ?? this.children);

  @override
  List<Object?> get props => [id, name, children];

  @override
  bool get stringify => true;
}

class RunCommand extends Command {
  @override
  final name = "run";
  @override
  final description = "Run the worker";

  RunCommand() {
    argParser.addOption('wp-url',
        help: 'Base wordpress url', defaultsTo: String.fromEnvironment('WP_URL', defaultValue: 'wp.morhpt.sv'));
    argParser.addOption('username',
        abbr: 'u', defaultsTo: String.fromEnvironment('WP_USERNAME', defaultValue: 'admin'));
    argParser.addOption('password',
        abbr: 'p', defaultsTo: String.fromEnvironment('WP_PASSWORD', defaultValue: 'admin'));
    argParser.addOption('data',
        abbr: 'd',
        help: 'Data file location',
        defaultsTo: String.fromEnvironment('DATA_FILE', defaultValue: './data.txt'));
  }

  @override
  Future<void> run() async {
    final file = File(argResults!['data']);
    final lines = await file.readAsLines();

    const maxLevels = 8;
    const spaces = 3;

    String createSpace([int mSpaces = spaces]) {
      return List.filled(mSpaces, ' ').join();
    }

    List<Category> categories = [];
    final structuredCategories = <StructuredCategory>[];

    final map = <int, int>{};

    print('- Parsing ${argResults!['data']}');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (!line.startsWith(createSpace())) {
        categories.add(Category(i, 0, line.trim()));
        map[0] = i;
        continue;
      }

      for (int y = 1; y <= maxLevels; y++) {
        if (line.startsWith(createSpace(y * spaces)) && !line.startsWith(createSpace(y * spaces + spaces))) {
          categories.add(Category(i, y, line.trim(), map[y - 1]));
          map[y] = i;
        }
      }
    }

    for (final category in categories) {
      if (category.level == 0) {
        structuredCategories.add(StructuredCategory(category.id, category.name));
        continue;
      }
    }

    final dioOptions =
        Tuple3<String, String, String>(argResults!['wp-url'], argResults!['username'], argResults!['password']);
    // sendToWordpress(Tuple2(categories, dioOptions));


    await sendToWordpress(Tuple4(categories, dioOptions, 0, null));
    exit(0);

    const maxIsolates = 5;

    final layer0Ids = categories.where((e) => e.level == 0).toList();

    final asMap = Map.fromEntries(categories.map((e) => MapEntry(e.id, e)));
    final groupedMap = groupBy(categories, (Category c) => c.level);

    final List<List<Category>> isolateCategories = layer0Ids.slices(layer0Ids.length ~/ maxIsolates).toList();
    final receivePorts = List.generate(maxIsolates - 1, (i) => ReceivePort('worker ${i + 1}'));
    // final

    for (int i = 1; i < maxIsolates; i++) {
      await Isolate.spawn(
          sendToWordpress,
          Tuple4(
              categories.sublist(
                  isolateCategories[i].first.id, i + 1 < maxIsolates ? isolateCategories[i + 1].first.id - 1 : null),
              dioOptions,
              i, receivePorts[i-1].sendPort));
    }

    final broadcastStreams = receivePorts.map((e) => e.asBroadcastStream());
    await waitStreams(broadcastStreams);


    await sendToWordpress(Tuple4(categories.sublist(0, isolateCategories[1].first.id - 1), dioOptions, 0, null));

    await waitStreams(broadcastStreams);
    exit(0);


    for (int i = 0; i < maxIsolates; i++) {
      final start = (layer0Ids.length % 4) * (layer0Ids.length ~/ 4);
      isolateCategories[i] = categories.sublist(start);
    }

    for (int i = 1; i <= layer0Ids.length; i++) {
      if (layer0Ids.length / ~i == 2) {}
    }

    // print(categories.join('\n'));
  }
}

waitStreams(Iterable<Stream> streams) async {
  await Future.wait(streams.map((e) => e.first));
}

Future<void> sendToWordpress(Tuple4<List<Category>, Tuple3<String, String, String>, int, SendPort?> payload) async {
  print('- [worker #${payload.item3}] Starting requests to ${payload.item2.item1}');
  final dio = Dio(BaseOptions(baseUrl: 'https://${payload.item2.item1}/wp-json'));
  final port = ReceivePort();

  payload.item4?.send(port.sendPort);
  int lastId = 0;
  bool hasError = false;

  do {
    final jwtRes = await dio.post(
      '/jwt-auth/v1/token',
      data: {
        'username': payload.item2.item2,
        'password': payload.item2.item3,
      },
      options: Options(headers: {'Content-Type': 'application/x-www-form-urlencoded'}),
    );

    final jwt = jwtRes.data['token'];

    final categories = hasError ? payload.item1.where((e) => e.id >= lastId).toList() : payload.item1;

    if (hasError) {
      print('- [worker #${payload.item3}] Starting from #$lastId');
    }

    try {
      for (final c in categories) {
        lastId = c.id;
        int? newId;
        final sw = Stopwatch()..start();
        try {
          final res = await dio.post(
            '/wc/v3/products/categories',
            data: {
              "name": c.name,
              "slug": c.name.snakeCase,
              if (c.parentId != null) "parent": c.parentId,
            },
            options: Options(headers: {
              'Authorization': 'Bearer $jwt',
              'Content-Type': 'application/json',
            }),
          );

          newId = res.data['id'];

          print('- [worker #${payload.item3}] added ${c.name} with id $newId. ${sw.elapsed.inMilliseconds}ms');
        } on DioError catch (e) {
          if (e.response?.data['code'] == 'term_exists') {
            final res = await dio.get(
              '/wc/v3/products/categories/${e.response?.data['data']['resource_id']}',
              options: Options(headers: {
                'Authorization': 'Bearer $jwt',
              }),
            );

            newId = res.data['id'];
            print(
                '- [worker #${payload.item3}] Updated id for ${c.name}. New id: $newId. ${sw.elapsed.inMilliseconds}ms');
          } else {
            rethrow;
          }
        }

        categories[categories.indexOf(c)] = c.copyWith(id: newId);

        for (final c2 in categories.where((e) => e.parentId == c.id)) {
          categories[categories.indexOf(c2)] = c2.copyWith(parentId: newId);
        }
      }
      hasError = false;
    } catch (e, st) {
      print('- [worker #${payload.item3}] ERROR - $e');
      print(st);
      print('- [worker #${payload.item3}] Waiting 5 seconds for cool down');
      hasError = true;
      await Future.delayed(const Duration(seconds: 5));
    }
  } while (hasError);

  payload.item4?.send('done');
}
