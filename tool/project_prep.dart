import 'dart:io';

import '_workspace_cli.dart';

Future<void> main(List<String> args) async {
  enterWorkspaceRoot();

  final command = args.isEmpty ? 'app' : args.first;

  switch (command) {
    case 'app':
    case 'bootstrap':
      await _prepareApp(includeCerts: true);
      return;
    case 'test':
      await _prepareApp(includeCerts: false);
      return;
    case 'doctor':
      await _runDoctor();
      return;
    case 'help':
    case '--help':
    case '-h':
      stdout.writeln(_usage);
      return;
    default:
      stderr.writeln('未知 project prep 子命令: $command');
      stderr.writeln(_usage);
      exit(64);
  }
}

Future<void> _prepareApp({required bool includeCerts}) async {
  await ensurePubGet();
  await _generateL10n();
}

Future<void> _generateL10n() {
  return runOrExit(
    title: '生成 l10n',
    executable: Platform.resolvedExecutable,
    arguments: const ['tool/gen_l10n.dart'],
  );
}

Future<void> _runDoctor() async {
  stdout.writeln('==> 检查开发环境');
  await _printCommandStatus('Flutter', flutterExecutable, const ['--version']);
  await _printCommandStatus('Dart', Platform.resolvedExecutable, const ['--version']);

  stdout.writeln('==> 检查 l10n 生成状态');
  final l10nResult = await _runProcess(
    Platform.resolvedExecutable,
    const ['tool/gen_l10n.dart', '--check'],
  );
  stdout.write(l10nResult.combinedOutput);
  stdout.writeln(
    l10nResult.exitCode == 0 ? '[OK] l10n 生成状态正常' : '[FAILED] l10n 生成状态异常',
  );
}

Future<void> _printCommandStatus(
  String label,
  String executable,
  List<String> arguments,
) async {
  final result = await _runProcess(executable, arguments);
  if (result.exitCode == 0) {
    final firstLine = result.combinedOutput
        .split(RegExp(r'\r?\n'))
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    stdout.writeln('[OK] $label: $firstLine');
    return;
  }

  stdout.writeln('[MISSING] $label');
}

Future<_ProcessResult> _runProcess(
  String executable,
  List<String> arguments,
) async {
  try {
    final result = await Process.run(
      executable,
      arguments,
      runInShell: Platform.isWindows,
    );
    return _ProcessResult(
      exitCode: result.exitCode,
      combinedOutput: '${result.stdout}${result.stderr}',
    );
  } on ProcessException catch (error) {
    return _ProcessResult(exitCode: 1, combinedOutput: error.message);
  }
}

class _ProcessResult {
  const _ProcessResult({required this.exitCode, required this.combinedOutput});

  final int exitCode;
  final String combinedOutput;
}

const _usage = '''
用法:
  dart tool/project_prep.dart app
  dart tool/project_prep.dart test
  dart tool/project_prep.dart doctor
''';
