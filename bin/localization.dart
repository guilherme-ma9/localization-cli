import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';

import 'package:yaml/yaml.dart';

void main(List<String> arguments) async {
  var path = await getPath(arguments);

  try {
    final yaml = File('$path/pubspec.yaml');
    var node = yaml.readAsStringSync();
    var doc = loadYaml(node);

    if (!(doc as Map).containsKey('localization_dir')) {
      throw 'Please, add param "localization_dir" (localization directory of your project) in your pubspec.yaml';
    }

    var localizationPath = '$path/${doc['localization_dir']}';

    if ((localizationPath ?? '') == '') {
      throw 'Please, the param "localization_dir" can not be null';
    }

    final dartFiles = await getAllDartFiles(path);
    final translations = dartFiles
        .cast<File>()
        .map(getI18nKeysFromFile)
        .reduce((x, y) => x..addAll(y));

    final jsonEncodedData = readJsonFiles(localizationPath);
    final newFilesData = jsonEncodedData.map((file, content) {
      final Map<String, dynamic> newContent = jsonDecode(content);
      final itemsToAdd = translations.entries
          .skipWhile((entry) => newContent.keys.contains(entry.key));
      print('${itemsToAdd.length} items to add.');
      newContent.addEntries(itemsToAdd);

      var encoder = JsonEncoder.withIndent('  ');
      return MapEntry(file, encoder.convert(newContent));
    });
    writeJsonFiles(newFilesData);

    print('Items added successful.');

    print('Replacing i18n comments');

    dartFiles.cast<File>().forEach(removeI18nComments);
  } catch (e) {
    print(e);
  }
}

Future<String> getPath(List<String> arguments) async {
  final lineNumber = 'line-number';
  ArgResults argResults;

  final parser = ArgParser()..addFlag(lineNumber, negatable: false, abbr: 'p');

  argResults = parser.parse(arguments);
  final paths = argResults.rest;

  return paths.first;
}

void removeI18nComments(File file) {
  final findRegex = RegExp(r'''[\'\"](.*)[\'\"].i18n\(.*\).*\/\/(.*)''');
  final replaceRegex = RegExp(r'''\/\/(.*)''');

  var data = file.readAsLinesSync();
  var containsUpdate = false;
  var newData = data.map((line) {
    if (line.contains(findRegex)) {
      containsUpdate = true;
      return line.replaceAll(replaceRegex, '');
    } else {
      return line;
    }
  }).toList();
  if (containsUpdate) {
    file.writeAsStringSync("${newData.join('\n')}\n");
    print('file ${file.path} updated');
  }
}

Future<List<FileSystemEntity>> getAllDartFiles(String path) async {
  final files = <FileSystemEntity>[];
  var dir = Directory('$path/lib');
  final filesSubscription = dir
      .list(recursive: true)
      .where((file) => file.path.substring(file.path.length - 5) == '.dart')
      .listen(files.add);

  await filesSubscription.asFuture();
  await filesSubscription.cancel();
  return files;
}

//https://regexr.com/4pvrh
Map<String, String> getI18nKeysFromFile(File file) {
  final regex = RegExp(r'''[\'\"](.*)[\'\"].i18n\(.*\).*\/\/(.*)''');
  final response = <String, String>{};
  var data = file.readAsStringSync();
  if (regex.hasMatch(data)) {
    regex.allMatches(data).forEach((match) => (match.groupCount == 4)
        ? response[match.group(3)] = match.group(3)
        : response[match.group(1)] = match.group(2));
  }
  return response;
}

Map<File, String> readJsonFiles(String localizationPath) {
  final response = <File, String>{};
  final dir = Directory(localizationPath);
  final files = dir.listSync();

  for (var file in files) {
    response[file] = (file as File).readAsStringSync();
  }

  return response;
}

void writeJsonFiles(Map<File, String> filesData) =>
    filesData.forEach((file, content) => file.writeAsStringSync(content));
