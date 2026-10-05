import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Persistent, visible DOM fields let browser/password-manager heuristics see
/// both credentials before focus. Never submit a native HTTP form: only the
/// existing Matrix login path receives these values, read at submit time (some
/// password managers fill without dispatching input events).
class WebLoginForm extends StatefulWidget {
  const WebLoginForm({
    required this.registering,
    required this.loading,
    required this.onSubmit,
    super.key,
  });
  final bool registering;
  final bool loading;
  final void Function(String server, String username, String password) onSubmit;
  @override
  State<WebLoginForm> createState() => _WebLoginFormState();
}

class _WebLoginFormState extends State<WebLoginForm> {
  final _root = web.HTMLDivElement();
  final _serverSettings = web.HTMLDetailsElement();
  final _serverSummary =
      web.document.createElement('summary') as web.HTMLElement;
  final _form = web.HTMLFormElement();
  final _server = web.HTMLInputElement();
  final _username = web.HTMLInputElement();
  final _password = web.HTMLInputElement();
  final _confirmation = web.HTMLInputElement();
  final _submit = web.HTMLButtonElement();
  final _labels = <web.HTMLInputElement, web.HTMLLabelElement>{};
  late final JSFunction _submitListener;
  late final JSFunction _serverListener;
  final _eyeButtons = <web.HTMLInputElement, web.HTMLButtonElement>{};
  final _eyeListeners = <web.HTMLButtonElement, JSFunction>{};

  // Flutter widget tests do not attach HTML platform views to the real DOM.
  @visibleForTesting
  web.HTMLElement get debugDomRoot => _root;

  @override
  void initState() {
    super.initState();
    _form.id = 'deltiecord-login';
    _form.autocomplete = 'on';
    // POST is defense in depth against accidental URL/query-string disclosure.
    _form.method = 'post';
    _form.style.cssText =
        'width:100%;height:100%;display:flex;flex-direction:column;gap:12px;box-sizing:border-box;font-family:Arial,sans-serif;';
    _root.style.cssText =
        'width:100%;height:100%;font-family:Arial,sans-serif;';
    _addField(_server, 'homeserver', 'Homeserver', 'url', 'off');
    _server.value = 'https://matrix.deltie.net';
    _server.setAttribute('inputmode', 'url');
    _server.setAttribute('data-lpignore', 'true');
    _server.setAttribute('data-1p-ignore', 'true');
    // Configuration is outside the credential form and collapsed by default.
    // The only username candidate in the login form is the real username.
    _serverSummary.textContent = 'Homeserver: matrix.deltie.net (change)';
    _serverListener = ((web.Event _) {
      _serverSummary.textContent = 'Homeserver: ${_server.value} (change)';
    }).toJS;
    _server.addEventListener('input', _serverListener);
    _serverSettings.appendChild(_serverSummary);
    _serverSettings.appendChild(_labels[_server]!);
    _root.appendChild(_serverSettings);
    _root.appendChild(_form);
    _addField(
      _username,
      'username',
      'Username or Matrix ID',
      'text',
      'username',
    );
    _addField(
      _password,
      'password',
      'Password',
      'password',
      'current-password',
    );
    _addField(
      _confirmation,
      'password-confirmation',
      'Confirm password',
      'password',
      'new-password',
    );
    _addEye(_password);
    _addEye(_confirmation);
    _submit.type = 'submit';
    _form.appendChild(_submit);
    _submitListener = ((web.Event event) {
      event.preventDefault();
      if (widget.loading) return;
      _server.setCustomValidity('');
      _username.setCustomValidity('');
      _confirmation.setCustomValidity('');
      if (!widget.registering) {
        final raw = _server.value.trim();
        final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
        if (raw.isEmpty ||
            uri == null ||
            uri.scheme != 'https' ||
            !uri.hasAuthority) {
          _server.setCustomValidity('Enter a valid HTTPS homeserver address.');
        }
      } else {
        if (!RegExp(r'^[a-z0-9._=\-/]+$').hasMatch(_username.value.trim())) {
          _username.setCustomValidity(
            'Use lowercase letters, numbers, dots, hyphens, or underscores.',
          );
        }
        if (_password.value != _confirmation.value) {
          _confirmation.setCustomValidity('Passwords do not match.');
        }
      }
      if (!widget.registering && !_server.checkValidity()) {
        _serverSettings.open = true;
        _server.reportValidity();
        return;
      }
      if (_form.reportValidity()) {
        widget.onSubmit(
          widget.registering ? 'https://matrix.deltie.net' : _server.value,
          _username.value,
          _password.value,
        );
      }
    }).toJS;
    // Validation is explicit so a previous custom error cannot block retries
    // before our submit listener gets a chance to clear/re-evaluate it.
    _form.noValidate = true;
    _form.addEventListener('submit', _submitListener);
  }

  void _addEye(web.HTMLInputElement input) {
    final row = web.HTMLDivElement()
      ..style.cssText = 'display:flex;align-items:center;position:relative;';
    _labels[input]!.appendChild(row);
    row.appendChild(input);
    final button = web.HTMLButtonElement()..type = 'button';
    button.textContent = '👁︎';
    button.title = 'Show password';
    button.setAttribute('aria-label', 'Show password');
    button.setAttribute('aria-pressed', 'false');
    button.style.cssText =
        'position:absolute;right:4px;width:40px;height:40px;border:0;background:transparent;color:inherit;font-size:22px;cursor:pointer;';
    final listener = ((web.Event event) {
      event.preventDefault();
      final visible = input.type == 'password';
      input.type = visible ? 'text' : 'password';
      button.title = visible ? 'Hide password' : 'Show password';
      button.setAttribute('aria-label', button.title);
      button.setAttribute('aria-pressed', visible.toString());
    }).toJS;
    button.addEventListener('click', listener);
    _eyeButtons[input] = button;
    _eyeListeners[button] = listener;
    row.appendChild(button);
  }

  void _addField(
    web.HTMLInputElement input,
    String name,
    String title,
    String type,
    String autocomplete,
  ) {
    input.id = 'deltiecord-$name';
    input.name = name;
    input.type = type;
    input.autocomplete = autocomplete;
    input.required = true;
    input.spellcheck = false;
    input.setAttribute('autocapitalize', 'none');
    input.setAttribute('autocorrect', 'off');
    final label = web.HTMLLabelElement()..htmlFor = input.id;
    label.appendChild(web.Text(title));
    label.appendChild(input);
    _labels[input] = label;
    _form.appendChild(label);
  }

  @override
  void didUpdateWidget(WebLoginForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registering != widget.registering) {
      _password.value = '';
      _confirmation.value = '';
      for (final entry in _eyeButtons.entries) {
        entry.key.type = 'password';
        entry.value.title = 'Show password';
        entry.value.setAttribute('aria-label', 'Show password');
        entry.value.setAttribute('aria-pressed', 'false');
      }
      for (final input in _labels.keys) {
        input.setCustomValidity('');
      }
    }
  }

  String _css(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    _root.style.color = _css(colors.onSurface);
    _serverSettings.style.cssText = 'margin-bottom:12px;font-size:14px;';
    _serverSettings.style.display = widget.registering ? 'none' : 'block';
    _serverSummary.textContent = 'Homeserver: ${_server.value} (change)';
    _form.style.color = _css(colors.onSurface);
    for (final entry in _labels.entries) {
      entry.value.style.cssText =
          'display:flex;flex-direction:column;gap:6px;font-size:14px;';
      entry.key.style.cssText =
          'box-sizing:border-box;width:100%;min-height:46px;padding:10px 12px;border:1px solid ${_css(colors.outline)};border-radius:12px;background:${_css(colors.surfaceContainerHighest)};color:${_css(colors.onSurface)};font:16px Arial,sans-serif;';
      entry.key.readOnly = widget.loading;
      if (_eyeButtons.containsKey(entry.key)) {
        entry.key.style.paddingRight = '48px';
      }
    }
    _labels[_server]!.style.display = widget.registering ? 'none' : 'flex';
    _server.disabled = widget.registering;
    _labels[_confirmation]!.style.display = widget.registering
        ? 'flex'
        : 'none';
    _confirmation.disabled = !widget.registering;
    _password.autocomplete = widget.registering
        ? 'new-password'
        : 'current-password';
    _submit.disabled = widget.loading;
    _submit.textContent = widget.loading
        ? 'Please wait…'
        : widget.registering
        ? 'Create account'
        : 'Sign in';
    _submit.style.cssText =
        'min-height:48px;margin-top:6px;border:0;border-radius:24px;background:${_css(colors.primary)};color:${_css(colors.onPrimary)};font:16px Arial,sans-serif;cursor:pointer;';
    return SizedBox(
      height: _serverSettings.open ? 380 : 320,
      child: HtmlElementView.fromTagName(
        tagName: 'div',
        onElementCreated: (element) {
          final host = element as web.HTMLElement;
          host.style.cssText = 'width:100%;height:100%;';
          host.style.overflowY = 'auto';
          host.appendChild(_root);
        },
      ),
    );
  }

  @override
  void dispose() {
    _form.removeEventListener('submit', _submitListener);
    _server.removeEventListener('input', _serverListener);
    for (final entry in _eyeListeners.entries) {
      entry.key.removeEventListener('click', entry.value);
    }
    _password.value = '';
    _confirmation.value = '';
    _username.value = '';
    _root.remove();
    super.dispose();
  }
}
