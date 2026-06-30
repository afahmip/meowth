enum Env { local, prod }

class AppConfig {
  static const _env = String.fromEnvironment('ENV', defaultValue: 'prod');

  static Env get env => _env == 'local' ? Env.local : Env.prod;

  static String get baseUrl => switch (env) {
        Env.local => 'http://localhost:8080',
        Env.prod => 'https://meowth-ancient-summit-8275.fly.dev',
      };
}
