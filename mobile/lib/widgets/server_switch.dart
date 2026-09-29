import 'package:flutter/material.dart';

class ServerLink extends InheritedWidget {
  const ServerLink({
    super.key,
    required this.useCloud,
    required this.cloudHost,
    required this.onChanged,
    required super.child,
  });

  final bool useCloud;
  final String cloudHost;
  final void Function(bool useCloud, String cloudHost) onChanged;

  static ServerLink of(BuildContext context) {
    final link = context.dependOnInheritedWidgetOfExactType<ServerLink>();
    assert(link != null, 'ServerLink is missing above this screen');
    return link!;
  }

  @override
  bool updateShouldNotify(ServerLink oldWidget) =>
      useCloud != oldWidget.useCloud || cloudHost != oldWidget.cloudHost;
}

class ServerSwitch extends StatefulWidget {
  const ServerSwitch({super.key});

  @override
  State<ServerSwitch> createState() => _ServerSwitchState();
}

class _ServerSwitchState extends State<ServerSwitch> {
  final _host = TextEditingController();
  var _filled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _host.text = ServerLink.of(context).cloudHost;
    _filled = true;
  }

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = ServerLink.of(context);
    final cloud = link.useCloud;
    final host = _host.text.trim().isEmpty ? 'your-app.onrender.com' : _host.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(cloud ? 'Internet server' : 'This computer'),
          subtitle: Text(cloud ? 'wss://$host' : 'USB cable to this PC'),
          value: cloud,
          onChanged: (value) {
            final entered = _host.text.trim();
            if (value && entered.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Enter the Render host first, like your-app.onrender.com')),
              );
              return;
            }
            link.onChanged(value, entered);
          },
        ),
        TextField(
          controller: _host,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'Cloud host',
            hintText: 'your-app.onrender.com',
            filled: true,
            fillColor: const Color(0xFF0E1C30),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onSubmitted: (value) {
            if (link.useCloud) link.onChanged(true, value);
          },
        ),
      ],
    );
  }
}
