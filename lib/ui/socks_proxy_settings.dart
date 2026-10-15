import 'package:flutter/material.dart';
import '../services/socks_proxy.dart';

class SocksProxySettingsTile extends StatelessWidget {
  const SocksProxySettingsTile({super.key});
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: const Text('SOCKS5 proxy'),
    subtitle: Text(
      SocksProxy.supported
          ? 'Device-only connection settings. Restart SeND after changing them.'
          : 'Use your browser or system proxy settings. PWAs cannot select a SOCKS proxy.',
    ),
    trailing: SocksProxy.supported ? const Icon(Icons.chevron_right) : null,
    onTap: SocksProxy.supported ? () => showSocksProxySettings(context) : null,
  );
}

Future<void> showSocksProxySettings(
  BuildContext context, {
  Future<SocksProxyConfig> Function()? load,
  Future<void> Function(SocksProxyConfig)? save,
  Future<void> Function()? reset,
}) => showDialog<void>(
  context: context,
  builder: (_) => _ProxyDialog(
    load: load ?? SocksProxy.load,
    save: save ?? SocksProxy.save,
    reset: reset ?? SocksProxy.reset,
  ),
);

class _ProxyDialog extends StatefulWidget {
  const _ProxyDialog({
    required this.load,
    required this.save,
    required this.reset,
  });
  final Future<SocksProxyConfig> Function() load;
  final Future<void> Function(SocksProxyConfig) save;
  final Future<void> Function() reset;
  @override
  State<_ProxyDialog> createState() => _ProxyDialogState();
}

class _ProxyDialogState extends State<_ProxyDialog> {
  final _host = TextEditingController(text: '127.0.0.1');
  final _port = TextEditingController(text: '1080');
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _enabled = false,
      _allowDirect = true,
      _loading = true,
      _saving = false,
      _showPassword = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.load();
      if (!mounted) return;
      _host.text = value.host;
      _port.text = '${value.port}';
      _user.text = value.username;
      _password.text = value.password;
      _enabled = value.enabled;
      _allowDirect = value.allowDirectTraffic;
    } catch (_) {
      _error =
          'Could not read the saved proxy. Disable it to reset the connection settings.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save({bool reset = false}) async {
    final config = SocksProxyConfig(
      enabled: _enabled,
      host: _host.text.trim(),
      port: int.tryParse(_port.text) ?? 0,
      username: _user.text,
      password: _password.text,
      allowDirectTraffic: _allowDirect,
    );
    if (!reset && config.validationError != null) {
      setState(() => _error = config.validationError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (reset) {
        await widget.reset();
      } else {
        await widget.save(config);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Saved. Fully close and reopen SeND to apply the connection settings.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'Could not save the proxy. Check that your system keyring is unlocked.';
        });
      }
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('SOCKS5 proxy'),
    content: SizedBox(
      width: 440,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Routes messaging and media downloads through SOCKS5. The proxy resolves destination names. No direct fallback if it fails.',
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use SOCKS5 after restart'),
                    value: _enabled,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _enabled = v),
                  ),
                  TextField(
                    controller: _host,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Proxy hostname or IP address',
                    ),
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _port,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Port'),
                    autofillHints: const [],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _user,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Username (optional)',
                    ),
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    enabled: !_saving,
                    obscureText: !_showPassword,
                    enableSuggestions: false,
                    autocorrect: false,
                    autofillHints: const [],
                    decoration: InputDecoration(
                      labelText: 'Password (optional)',
                      suffixIcon: IconButton(
                        tooltip: _showPassword
                            ? 'Hide password'
                            : 'Show password',
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow unsupported traffic directly'),
                    subtitle: const Text(
                      'Calls and some previews, artwork and streams bypass SOCKS and may expose your IP address.',
                    ),
                    value: _allowDirect,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _allowDirect = v),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This is not a VPN. External browsers, other apps and OS/distributor push delivery use their own connections. The built-in Android notification listener is blocked in strict mode. SOCKS passwords are not encrypted between your device and the proxy; use a trusted local tunnel or VPN for remote proxies.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Current session: ${SocksProxy.configurationError
                        ? "blocked, proxy settings could not be loaded"
                        : SocksProxy.enabled
                        ? "proxy enabled"
                        : "direct connection"}. Existing connections change only after restart.',
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => _save(reset: true),
        child: const Text('Disable saved proxy'),
      ),
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving || _loading ? null : _save,
        child: const Text('Save'),
      ),
    ],
  );
}
