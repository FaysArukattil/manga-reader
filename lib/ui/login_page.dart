import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/auth_bloc.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (a, b) => b.error != null && a.error != b.error,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(state.error!)));
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.collections_bookmark_rounded,
                      size: 72,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Shelfmark',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'One shelf for every manga you read, on any site.\n'
                      'Close the tab - your place is saved.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 40),
                    BlocBuilder<AuthBloc, AuthState>(
                      buildWhen: (a, b) => a.busy != b.busy,
                      builder: (context, state) => SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: state.busy
                              ? null
                              : () => context.read<AuthBloc>().add(
                                  const AuthSignInRequested(),
                                ),
                          icon: state.busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.login),
                          label: const Text('Continue with Google'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
