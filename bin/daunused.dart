#!/usr/bin/env dart

library daunused;

import 'dart:io';

import 'package:path/path.dart' as path;

Future<void> main(List<String> args) async {
  final Directory root = Directory(args[0]);
  final List<String> exceptions = _exceptions(args);
  final List<File> files = await _getFiles(root);
  final Set<String> usedFiles = await _getAllUsedFiles(files);

  for (final File file in files) {
    if (!_isException(file, exceptions) && !usedFiles.contains(file.path)) {
      stderr.writeln('\x1B[31m${file.uri}\x1B[0m');
    }
  }
}

Future<Set<String>> _getAllUsedFiles(List<File> files) async {
  final Set<String> usedFiles = <String>{};
  for (final File file in files) {
    usedFiles.addAll(await _getUsedFiles(file, files));
  }
  return usedFiles;
}

Future<Set<String>> _getUsedFiles(File file, List<File> allFiles) async {
  final String content = await file.readAsString();
  final List<String> lines = content.split('\n');
  final Set<String> usedFiles = <String>{};

  for (final String line in lines) {
    if (_isImportOrExportLine(line.trim())) {
      usedFiles.addAll(await _resolveImportExport(line.trim(), file, allFiles));
    }
  }

  return usedFiles;
}

Future<Set<String>> _resolveImportExport(String line, File currentFile, List<File> allFiles) async {
  final Set<String> resolvedFiles = <String>{};
  final RegExp fileNameRegex = RegExp(r"'([^']+\.dart)'");
  final Iterable<RegExpMatch> matches = fileNameRegex.allMatches(line);

  for (final RegExpMatch match in matches) {
    final String importPath = match.group(1)!;
    final String resolvedPath = path.normalize(path.join(path.dirname(currentFile.path), importPath));
    final File? resolvedFile = allFiles.firstWhere((File f) => f.path == resolvedPath, orElse: () => File(''));

    if (resolvedFile != null) {
      resolvedFiles.add(resolvedFile.path);
      if (line.startsWith('export')) {
        // For exports, also include files exported by the resolved file
        resolvedFiles.addAll(await _getUsedFiles(resolvedFile, allFiles));
      }
    }
  }

  return resolvedFiles;
}

bool _isException(File file, List<String> exceptions) {
  final String uri = file.uri.toString();
  if (exceptions.contains(uri)) {
    return true;
  } else {
    for (final String exception in exceptions) {
      final RegExp exp = RegExp(exception);
      if (exp.hasMatch(uri)) {
        return true;
      }
    }
    return false;
  }
}

bool _isImportOrExportLine(String line) {
  return line.startsWith('import ') || line.startsWith('export ') || line.startsWith('part ') || (line.startsWith('if (') && line.contains('.dart'));
}

List<String> _exceptions(List<String> args) {
  final List<String> result = <String>[];

  for (int i = 1; i < args.length; i++) {
    result.add(args[i]);
  }

  return result;
}

Future<List<File>> _getFiles(Directory root) async {
  final List<FileSystemEntity> list = await root.list(recursive: true).toList();
  final List<File> files = <File>[];

  for (final FileSystemEntity entity in list) {
    if (entity is File) {
      final File file = File(entity.path);
      final String fileName = _basename(file);

      if (fileName.endsWith('.dart')) {
        files.add(file);
      }
    }
  }

  return files;
}

Future<bool> _isNotUsed(File file, List<File> files) async {
  final String fileName = _basename(file);

  for (final File currentFile in files) {
    if (await _isUsed(fileName, currentFile)) {
      return false;
    }
  }

  return true;
}

Future<bool> _isUsed(String fileName, File file) async {
  final String content = await file.readAsString();
  final List<String> lines = content.split('\n');
  final List<String> imports = _filesImported(lines);

  for (final String fileImported in imports) {
    if (fileImported.contains(fileName)) {
      return true;
    }
  }

  return false;
}

List<String> _filesImported(List<String> lines) {
  final List<String> result = <String>[];

  for (final String line in lines) {
    if (_isImportLine(line.trim())) {
      result.add(line.trim());
    }
  }

  return result;
}

bool _isImportLine(String line) {
  if (line.startsWith('import ') || line.startsWith('part ')) {
    return true;
  } else if (line.startsWith('if (') && (line.endsWith('.dart\'') || line.endsWith('.dart\';'))) {
    return true;
  } else {
    return false;
  }
}

String _basename(File file) => Uri.parse(file.path).path.split(Platform.pathSeparator).last;
