import 'package:args/command_runner.dart';
import 'package:wp_category_injector/wp_category_injector.dart' as wp_category_injector;

void main(List<String> arguments) async {
  CommandRunner('wp_category_injector', 'Inject Tab separated categories to Wordpress with JWT')
  ..addCommand(wp_category_injector.RunCommand())..run(arguments);
}
