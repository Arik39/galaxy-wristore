import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app.dart';
import '../../app/local_network.dart';
import '../../core/api.dart';
import '../../design/controls.dart';
import '../../design/icons.dart';
import '../../design/tokens.dart';
import '../../design/type.dart';
import '../../design/widgets.dart';

/// Looks for the watch in this phone's Wi-Fi network and offers what answered.
Future<void> showFindWatchSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (_) => const _FindSheet(),
);

class _FindSheet extends StatefulWidget {
  const _FindSheet();

  @override
  State<_FindSheet> createState() => _FindSheetState();
}

class _FindSheetState extends State<_FindSheet> {
  double _progress = 0;
  List<FoundWatch>? _found;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _progress = 0;
      _found = null;
      _error = null;
    });
    try {
      final found = await WatchScope.read(context).find(
        onProgress: (f) {
          if (mounted) setState(() => _progress = f);
        },
      );
      if (mounted) setState(() => _found = found);
    } on LocalNetworkDenied catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = 'The search could not run: $e');
    }
  }

  Future<void> _use(FoundWatch watch) async {
    HapticFeedback.lightImpact();
    final controller = WatchScope.read(context);
    Navigator.of(context).pop();
    await controller.setAddress(watch.address);
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              found == null ? 'Looking for your watch' : (found.isEmpty ? 'No watch answered' : 'Found on your Wi-Fi'),
              style: AppType.title,
            ),
            const SizedBox(height: Space.s),
            if (found == null && _error == null) ...[
              Text('Keep the watch awake: tap its screen now and then.', style: AppType.secondary),
              const SizedBox(height: Space.xl),
              JobProgress(label: 'Looking on your Wi-Fi', progress: _progress == 0 ? -1 : _progress),
            ] else if (_error != null) ...[
              Text(_error!, style: AppType.body),
            ] else if (found!.isEmpty) ...[
              Text(
                'Wake the watch, check that Debugging is on and that it uses the same Wi-Fi as this phone, then look again. '
                'Or type its address: on the watch under Settings, Connections, Wi-Fi, your network.',
                style: AppType.secondary,
              ),
            ] else ...[
              const SizedBox(height: Space.s),
              for (final w in found)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s),
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: 2),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radii.panel),
                        side: BorderSide(color: Palette.line),
                      ),
                      leading: const AppIconView(AppIcon.watch, color: Palette.ink),
                      title: Text(w.address.host, style: AppType.figureSmall),
                      subtitle: Text(
                        w.busy ? 'Another device is connected to it' : 'Galaxy Watch, Debugging on',
                        style: AppType.caption.copyWith(color: Palette.inkSoft),
                      ),
                      trailing: const AppIconView(AppIcon.chevronRight, color: Palette.inkFaint),
                      onTap: () => _use(w),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: Space.xl),
            if (found != null || _error != null) ...[
              AppButton(label: 'Look again', onPressed: _search, filled: found?.isEmpty ?? true, expand: true),
              const SizedBox(height: Space.s),
              AppButton(
                label: 'Type its address',
                filled: false,
                expand: true,
                onPressed: () {
                  Navigator.of(context).pop();
                  showAddressSheet(context);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Lets the user type the watch's address; only private network addresses are taken.
Future<void> showAddressSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (_) => const _AddressSheet(),
);

class _AddressSheet extends StatefulWidget {
  const _AddressSheet();

  @override
  State<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<_AddressSheet> {
  late final _field = TextEditingController(text: WatchScope.read(context).address?.host ?? '');
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final address = WatchAddress.parse(_field.text);
    if (address == null) {
      setState(() => _error = 'Type an address of your home network, like 192.168.1.20.');
      return;
    }
    final controller = WatchScope.read(context);
    Navigator.of(context).pop();
    await controller.setAddress(address);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("Your watch's address", style: AppType.title),
              const SizedBox(height: Space.s),
              Text(
                'On the watch: Settings, Connections, Wi-Fi, then your network shows its IP address.',
                style: AppType.secondary,
              ),
              const SizedBox(height: Space.xl),
              TextField(
                controller: _field,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                style: AppType.figureSmall,
                decoration: InputDecoration(hintText: '192.168.1.20', errorText: _error),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: Space.xl),
              AppButton(label: 'Connect', onPressed: _save, expand: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// How to turn on Debugging, the switch the watch needs before this app can reach it.
Future<void> showDebuggingHelp(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Turning on Debugging', style: AppType.title),
          const SizedBox(height: Space.l),
          for (final (i, step) in debuggingSteps.indexed) NumberedStep(number: i + 1, text: step),
        ],
      ),
    ),
  ),
);

/// The steps that let this app reach the watch, in the watch's own words.
const debuggingSteps = [
  'On the watch, open Settings, About watch, Software. Tap Software version five times.',
  'Back in About watch, turn on Debugging.',
  'Restart the watch. A restart makes Debugging start answering.',
  'Keep it on the same Wi-Fi as this phone. The first time, the watch asks to allow this phone: tap the check mark.',
];

/// One step of a numbered list.
class NumberedStep extends StatelessWidget {
  const NumberedStep({super.key, required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              number.toString().padLeft(2, '0'),
              style: AppType.label.copyWith(color: Palette.inkSoft, height: 22 / 10.5),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppType.secondary.copyWith(color: Palette.ink, height: 22 / 14),
            ),
          ),
        ],
      ),
    );
  }
}
