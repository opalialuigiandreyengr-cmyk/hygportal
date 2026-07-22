part of '../main.dart';

class HygAdminApp extends StatelessWidget {
  const HygAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HYG HR Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: HygColors.gold),
        fontFamily: HygTypography.fontFamily,
        scaffoldBackgroundColor: HygColors.background,
        textTheme: HygTypography.textTheme,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(textStyle: HygTypography.button),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(textStyle: HygTypography.button),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(textStyle: HygTypography.button),
        ),
        useMaterial3: true,
      ),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);

        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: const TextScaler.linear(1.05)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const StartupGate(),
    );
  }
}

class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _showSplash = true;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    _splashTimer = Timer(const Duration(milliseconds: 1700), () {
      if (mounted) {
        setState(() => _showSplash = false);
      }
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      child: _showSplash ? const SplashScreen() : const LoginScreen(),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HygColors.ink,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 112,
              height: 112,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 28,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: Image.asset('assets/hyg_icon.png', fit: BoxFit.contain),
            ),
            const SizedBox(height: 24),
            const Text(
              'HYG HR Admin',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Preparing desktop workspace',
              style: TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 26),
            const SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: HygColors.gold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  String _error = '';
  AdminLoginSession? _session;
  bool _isSignedIn = false;
  bool _isSigningIn = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    setState(() {
      if (username.isEmpty || password.isEmpty) {
        _error = 'Enter username and password.';
        return;
      }
      _isSigningIn = true;
      _error = '';
    });

    if (username.isEmpty || password.isEmpty) {
      return;
    }

    try {
      final session = await AdminAuthService.signInAdmin(
        username: username,
        password: password,
      );
      if (!mounted) return;
      setState(() {
        _error = '';
        _session = session;
        _isSignedIn = true;
        _isSigningIn = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isSigningIn = false;
      });
    }
  }

  Future<void> _signOut() async {
    await AdminAuthService.signOut();
    if (!mounted) {
      return;
    }
    setState(() {
      _isSignedIn = false;
      _session = null;
      _passwordController.clear();
      _error = '';
    });
    _usernameFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (_isSignedIn && session != null) {
      return AdminShell(
        session: session,
        onSignOut: () => unawaited(_signOut()),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [HygColors.ink, HygColors.panel],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 880;
                    final loginCard = LoginCard(
                      usernameController: _usernameController,
                      passwordController: _passwordController,
                      usernameFocus: _usernameFocus,
                      error: _error,
                      onSubmit: _submit,
                      isSubmitting: _isSigningIn,
                    );

                    if (isWide) {
                      final cardHeight = constraints.maxHeight.clamp(
                        460.0,
                        560.0,
                      );

                      return Center(
                        child: SizedBox(
                          height: cardHeight,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Expanded(child: BrandPanel()),
                              const SizedBox(width: 30),
                              Expanded(child: loginCard),
                            ],
                          ),
                        ),
                      );
                    }

                    return SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const BrandPanel(),
                          const SizedBox(height: 20),
                          loginCard,
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BrandPanel extends StatelessWidget {
  const BrandPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 460),
      padding: const EdgeInsets.fromLTRB(34, 28, 34, 28),
      decoration: BoxDecoration(
        color: HygColors.panelSoft.withValues(alpha: 0.88),
        border: Border.all(color: const Color(0xFF1E3A5F)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 164,
            height: 76,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Image.asset('assets/hyg_logo.png', fit: BoxFit.contain),
          ),
          const SizedBox(height: 18),
          const Kicker('HYG Internal Access'),
          const SizedBox(height: 8),
          const Text(
            'Welcome back to your HR admin workspace.',
            style: HygTypography.loginWelcome,
          ),
          const SizedBox(height: 16),
          const Text(
            'Review employee requests, maintain employee profiles, and manage approval workflows in one secure portal.',
            style: HygTypography.bodyLarge,
          ),
          const SizedBox(height: 18),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FeaturePill(
                icon: Icons.badge_outlined,
                label: 'Employee records',
              ),
              SizedBox(height: 8),
              FeaturePill(
                icon: Icons.event_available_outlined,
                label: 'Leave approvals',
              ),
              SizedBox(height: 8),
              FeaturePill(
                icon: Icons.access_time_filled_outlined,
                label: 'ESARF monitoring',
              ),
              SizedBox(height: 8),
              FeaturePill(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Offset balances',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FeaturePill extends StatelessWidget {
  const FeaturePill({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: HygColors.gold,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: HygColors.ink, size: 17),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            label,
            style: HygTypography.bodyLarge.copyWith(
              color: Color(0xFFE2E8F0),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class LoginCard extends StatelessWidget {
  const LoginCard({
    required this.usernameController,
    required this.passwordController,
    required this.usernameFocus,
    required this.error,
    required this.onSubmit,
    required this.isSubmitting,
    super.key,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final FocusNode usernameFocus;
  final String error;
  final Future<void> Function() onSubmit;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 22,
      shadowColor: Colors.black.withValues(alpha: 0.26),
      color: const Color(0xFFF3F4F6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(34, 28, 34, 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Kicker('Secure Desktop Portal', dark: true),
            const SizedBox(height: 6),
            const Text('Sign in', style: HygTypography.loginTitle),
            const SizedBox(height: 8),
            const Text(
              'Use your assigned username and password',
              style: HygTypography.bodyLarge,
            ),
            const SizedBox(height: 20),
            HygTextField(
              controller: usernameController,
              focusNode: usernameFocus,
              label: 'USERNAME',
              hint: 'Enter your username',
              icon: Icons.person,
              onSubmitted: (_) {
                if (!isSubmitting) {
                  unawaited(onSubmit());
                }
              },
            ),
            const SizedBox(height: 14),
            HygTextField(
              controller: passwordController,
              label: 'PASSWORD',
              hint: 'Enter your password',
              icon: Icons.lock,
              obscureText: true,
              onSubmitted: (_) {
                if (!isSubmitting) {
                  unawaited(onSubmit());
                }
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 20,
              child: Text(
                error,
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: HygColors.gold,
                foregroundColor: HygColors.ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontFamily: HygTypography.bodyFontFamily,
                  fontFamilyFallback: HygTypography.fontFallbacks,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
              onPressed: isSubmitting ? null : () => unawaited(onSubmit()),
              child: Text(isSubmitting ? 'SIGNING IN...' : 'SIGN IN'),
            ),
          ],
        ),
      ),
    );
  }
}

class HygTextField extends StatelessWidget {
  const HygTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.focusNode,
    this.obscureText = false,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: HygTypography.fieldLabel),
        const SizedBox(height: 6),
        SizedBox(
          height: 46,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: obscureText,
            onSubmitted: onSubmitted,
            style: HygTypography.input,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: HygTypography.input.copyWith(color: Color(0xFF94A3B8)),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Icon(icon, color: Color(0xFF64748B), size: 19),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 48),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: HygColors.goldStrong,
                  width: 1.8,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
