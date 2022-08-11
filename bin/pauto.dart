import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:spotify/spotify.dart';

const _clientId = String.fromEnvironment('id');
const _clientSecret = String.fromEnvironment('secret');
const _refreshToken = String.fromEnvironment('token');

void main(List<String> arguments) {
  var runner = CommandRunner('pauto', 'pinokio auto script');
  runner
    ..addCommand(WriteCommand())
    ..addCommand(PlaylistCommand())
    ..run(arguments).catchError(
      (error) {
        if (error is! UsageException) throw error;
        print(error);
        exit(64);
      },
    );
}

class WriteCommand extends Command {
  @override
  String get description => 'Auto complete';

  @override
  String get name => 'write';

  WriteCommand() {
    argParser.addFlag('dryrun', abbr: 'n', help: 'dryrun');
  }

  @override
  void run() async {
    if (_clientId.isEmpty || _clientSecret.isEmpty || _refreshToken.isEmpty) {
      print('Not set environment value');
      exit(1);
    }
    final credentials = SpotifyApiCredentials(_clientId, _clientSecret);
    final spotify = SpotifyApi(credentials);

    final args = argResults!;
    if (args.rest.isEmpty) {
      printUsage();
      exit(1);
    }

    final path = args.rest.first;
    final file = File(path);
    if (!file.existsSync()) {
      print('Cant get file');
      exit(1);
    }
    final dryrun = args['dryrun'] ?? false;

    var outputs = <String>[];
    final body = file.readAsLinesSync();
    for (var line in body) {
      outputs.add(line);
      if (line.startsWith('##')) {
        var query = line.replaceAll('## ', '');
        final result = spotify.search.get(query, types: [SearchType.track]);
        final tracks = await result.first();
        final items = tracks.first.items;
        if (items == null || items.isEmpty) continue;

        final track = items.first;
        if (body[body.indexOf(line) + 1].isEmpty) {
          outputs.add('{{< spotify type="track" id="${track.id}" >}}');
        }
      }
    }

    if (dryrun) {
      print(outputs.join('\n'));
      exit(0);
    }

    file.writeAsStringSync(outputs.join('\n').trim());
    print('Success');
    exit(0);
  }
}

class PlaylistCommand extends Command {
  @override
  String get description => 'Add playlist from file';

  @override
  String get name => 'playlist';

  PlaylistCommand();

  Future<String> _refresh(String token) async {
    const String url = 'https://accounts.spotify.com/api/token';
    var client = http.Client();
    var data = {
      'grant_type': 'refresh_token',
      'refresh_token': token,
    };
    var encodedSecret = base64.encode(utf8.encode('$_clientId:$_clientSecret'));
    var header = {'Authorization': 'Basic $encodedSecret'};
    var res = await client.post(Uri.parse(url), headers: header, body: data);
    return json.decode(res.body)['access_token'];
  }

  @override
  void run() async {
    if (_clientId.isEmpty || _clientSecret.isEmpty || _refreshToken.isEmpty) {
      print('Not set environment value');
      exit(1);
    }
    var token = await _refresh(_refreshToken);
    final spotify = SpotifyApi.withAccessToken(token);

    final args = argResults!;
    if (args.rest.isEmpty) {
      printUsage();
      exit(1);
    }

    final path = args.rest.first;
    final file = File(path);
    if (!file.existsSync()) {
      print('Cant get file');
      exit(1);
    }

    var content = <String>[];
    final body = file.readAsLinesSync();
    final regexp = RegExp(r'{{< spotify type=\"track\" id=\"(.+)\" >}}');
    for (var line in body) {
      var match = regexp.firstMatch(line);
      if (match != null) {
        content.add('spotify:track:${match.group(1)}');
      }
    }

    await spotify.playlists.addTracks(content, '4g9tVzSqpIv51Zzf7DIVG5');
    print('Success');
    exit(0);
  }
}
