import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

const kHostPasswordArg = '--host-password';
const kHostPasswordSize = Size(420, 340);

/// TimeDesk Host: "Set password" opens as its own small window (a separate
/// process, like the install page) instead of a dialog squeezed into the
/// fixed-size main window. A multi-window sub-window crashed the app here.
Future<void> openHostPasswordWindow() async {
  await Process.start(Platform.resolvedExecutable, [kHostPasswordArg],
      mode: ProcessStartMode.detached);
}

class HostPasswordPage extends StatefulWidget {
  const HostPasswordPage({Key? key}) : super(key: key);

  @override
  State<HostPasswordPage> createState() => _HostPasswordPageState();
}

class _HostPasswordPageState extends State<HostPasswordPage> {
  void _close() => windowManager.close();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        // Title bar: drag anywhere on it, close on the right.
        GestureDetector(
          onPanStart: (_) => startDragging(true),
          child: Container(
            height: kDesktopRemoteTabBarHeight + 8,
            color: Colors.transparent,
            padding: const EdgeInsets.only(left: 16),
            child: Row(children: [
              Icon(Icons.key, size: 18, color: MyTheme.accent),
              const SizedBox(width: 8),
              Text(translate('Set Password'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: translate('Close'),
                onPressed: _close,
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: HostPasswordForm(onDone: _close),
        ),
      ]),
    );
  }
}

/// The Set password fields, rules and buttons. Used inline in the Host
/// window, where it opens at once, and by the standalone page above.
class HostPasswordForm extends StatefulWidget {
  final VoidCallback onDone;
  const HostPasswordForm({Key? key, required this.onDone}) : super(key: key);

  @override
  State<HostPasswordForm> createState() => _HostPasswordFormState();
}

class _HostPasswordFormState extends State<HostPasswordForm> {
  final _p0 = TextEditingController();
  final _p1 = TextEditingController();
  final _rxPass = ''.obs;
  final _rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    MinCharactersValidationRule(8),
  ];
  String _err0 = '';
  String _err1 = '';

  @override
  void dispose() {
    _p0.dispose();
    _p1.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pass = _p0.text.trim();
    final violations = _rules.where((r) => !r.validate(pass));
    if (pass.isEmpty || violations.isNotEmpty) {
      setState(() => _err0 =
          '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}');
      return;
    }
    if (_p1.text.trim() != pass) {
      setState(() => _err1 =
          '${translate('Prompt')}: ${translate("The confirmation is not identical.")}');
      return;
    }
    if (!await bind.mainSetPermanentPasswordWithResult(password: pass)) {
      setState(() => _err0 = '${translate('Prompt')}: ${translate("Failed")}');
      return;
    }
    widget.onDone();
  }

  Widget _field(TextEditingController c, String label, String err,
      {bool autofocus = false, ValueChanged<String>? onChanged}) {
    return TextField(
      controller: c,
      obscureText: true,
      autofocus: autofocus,
      maxLength: bind.mainMaxEncryptLen(),
      onChanged: onChanged,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(
        labelText: translate(label),
        errorText: err.isEmpty ? null : err,
        counterText: '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _field(_p0, 'Password', _err0, autofocus: true, onChanged: (v) {
        _rxPass.value = v.trim();
        setState(() => _err0 = '');
      }),
      PasswordStrengthIndicator(password: _rxPass)
          .marginOnly(top: 6, bottom: 12),
      _field(_p1, 'Confirmation', _err1,
          onChanged: (_) => setState(() => _err1 = '')),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        OutlinedButton(
            onPressed: widget.onDone, child: Text(translate('Cancel'))),
        const SizedBox(width: 10),
        ElevatedButton(onPressed: _submit, child: Text(translate('OK'))),
      ]),
    ]);
  }
}
