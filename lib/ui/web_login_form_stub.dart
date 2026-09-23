import 'package:flutter/widgets.dart';

class WebLoginForm extends StatelessWidget {
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
