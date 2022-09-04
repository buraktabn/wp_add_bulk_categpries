import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:recase/recase.dart';


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
  }) => Category(id ?? this.id, level ?? this.level, name ?? this.name, parentId ?? this.parentId);

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
  }) => StructuredCategory(id ?? this.id, name ?? this.name, children ?? this.children);

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
    argParser.addOption('wp-url',  help: 'Base wordpress url' ,defaultsTo: String.fromEnvironment('WP_URL', defaultValue: 'wp.morhpt.sv'));
    argParser.addOption('username', abbr: 'u',  defaultsTo: String.fromEnvironment('WP_USERNAME', defaultValue: 'admin'));
    argParser.addOption('password', abbr: 'p',  defaultsTo: String.fromEnvironment('WP_PASSWORD', defaultValue: 'admin'));
    argParser.addOption('data', abbr: 'd', help: 'Data file location', defaultsTo: String.fromEnvironment('DATA_FILE', defaultValue: './data.txt'));
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

    print('- Starting requests to ${argResults!['wp-url']}');
    final dio = Dio(BaseOptions(baseUrl: 'http://${argResults!['wp-url']}/wp-json'));

    final jwtRes = await dio.post(
      '/jwt-auth/v1/token',
      data: {
        'username': argResults!['username'],
        'password': argResults!['password']
      },
      options: Options(headers: {'Content-Type': 'application/x-www-form-urlencoded'}),
    );

    final jwt = jwtRes.data['data']['token'];

    for (final c in categories) {
      int? newId;
      final sw = Stopwatch()..start();
      try {
        final res = await dio.post(
          '/wc/v3/products/categories',
          data: {
            "name": c.name,
            "slug": c.name.snakeCase,
            if (c.parentId != null)
              "parent": c.parentId,
          },
          options: Options(headers: {
            'Authorization': 'Bearer $jwt',
            'Content-Type': 'application/json',
          }),
        );


         newId = res.data['id'];

        print('- added ${c.name} with id $newId. ${sw.elapsed.inMilliseconds}ms');


      } on DioError catch (e) {
       if ( e.response?.data['code'] == 'term_exists') {
         final res = await dio.get(
           '/wc/v3/products/categories/${e.response?.data['data']['resource_id']}',
           options: Options(headers: {
             'Authorization': 'Bearer $jwt',
           }),
         );

         newId = res.data['id'];
         print('- Updated id for ${c.name}. New id: $newId. ${sw.elapsed.inMilliseconds}ms');
       } else {
         rethrow;
       }
      }

      categories[c.id] = c.copyWith(id: newId);

      for (final c2 in categories.where((e) => e.parentId == c.id)) {
        categories[c2.id] = c2.copyWith(parentId: newId);
      }
    }


    // print(categories.join('\n'));
  }
}
