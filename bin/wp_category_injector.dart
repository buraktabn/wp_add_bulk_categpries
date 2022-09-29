import 'package:args/command_runner.dart';
import 'package:wp_category_injector/remove.dart';
import 'package:wp_category_injector/wp_category_injector.dart';

void main(List<String> arguments) async {
  CommandRunner('wp_category_injector', 'Inject Tab separated categories to Wordpress with JWT')
    ..addCommand(RunCommand())
    ..addCommand(RemoveRunner())
    ..run(arguments);
}
